//
//  call_manager.dart
//
//  Drives TDLib's 1:1 call lifecycle. Subscribes to the update stream, maps each
//  `updateCall` state onto a UI-facing `CallPhase`, and exposes a single `call`
//  model the call screen observes. Signaling (createCall / acceptCall /
//  discardCall / key exchange / emoji verification) is handled here; the actual
//  audio/video transport is delegated to a `CallMediaEngine` (a
//  `NoopCallMediaEngine` by default). Port of the Swift `CallManager`.
//

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import 'call_media_engine.dart';
import 'group_call_controller.dart';
import 'live_communication_bridge.dart';
import 'tgcalls_media_engine.dart';

enum CallPhase {
  requesting, // outgoing, createCall sent, awaiting TDLib's call id
  ringingIncoming, // incoming pending, awaiting accept
  ringingOutgoing, // outgoing pending, peer's phone is ringing
  exchangingKeys, // both sides agreed, deriving the shared key
  active, // media flowing (callStateReady)
  ending, // hanging up / discarded
}

@visibleForTesting
String? selectCallLibraryVersion({
  required List<String> localVersions,
  required List<String> remoteVersions,
}) {
  final remote = remoteVersions.toSet();
  for (final version in localVersions) {
    if (remote.contains(version)) return version;
  }
  return null;
}

class ActiveCall {
  ActiveCall({
    required this.callId,
    required this.peerUserId,
    this.peerName = '',
    this.peerPhoto,
    required this.isOutgoing,
    required this.isVideo,
    required this.phase,
    this.emojis = const [],
    this.startedAt,
    String? systemUuid,
  }) : systemUuid = systemUuid ?? LiveCommunicationBridge.newUuid();
  int callId;
  final int peerUserId;
  String peerName;
  TdFileRef? peerPhoto;
  final bool isOutgoing;
  bool isVideo;
  CallPhase phase;
  List<String> emojis;
  DateTime? startedAt;
  final String systemUuid;
  bool systemConversationStarted = false;
}

class CallManager extends ChangeNotifier {
  CallManager({CallMediaEngine? engine, GroupCallController? groups})
    : _engine = engine ?? _defaultEngine(),
      groups = groups ?? GroupCallController() {
    this.groups.addListener(_groupCallChanged);
    final liveCommunication = LiveCommunicationBridge.instance;
    liveCommunication.installHandler();
    liveCommunication.onSystemMuted = _handleSystemMuted;
    liveCommunication.onSystemEnded = _handleSystemEnded;
  }

  /// Android and iOS both ship a native Telegram call engine. Other platforms
  /// keep the signaling-only fallback until they gain a media implementation.
  static CallMediaEngine _defaultEngine() =>
      Platform.isAndroid || Platform.isIOS
      ? TgcallsMediaEngine()
      : NoopCallMediaEngine();

  final TdClient _client = TdClient.shared;
  final CallMediaEngine _engine;
  final GroupCallController groups;
  StreamSubscription? _sub;
  bool _started = false;
  Future<void> _protocolReady = Future<void>.value();

  ActiveCall? call;
  bool isMuted = false;
  bool isSpeaker = false;
  bool isVideoEnabled = false;
  bool useFrontCamera = true; // last-selected lens (front by default)

  // Protocol advertised in createCall/acceptCall. Defaults are overwritten at
  // start() with the media engine's own supported protocol (so TDLib negotiates
  // a version ntgcalls actually implements).
  int _minLayer = 65;
  int _maxLayer = 92;
  List<String> _libraryVersions = const ['4.0.0', '3.0.0'];

  Map<String, dynamic> get _callProtocol => {
    '@type': 'callProtocol',
    'udp_p2p': true,
    'udp_reflector': true,
    'min_layer': _minLayer,
    'max_layer': _maxLayer,
    'library_versions': _libraryVersions,
  };

  // MARK: - Lifecycle

  /// Subscribes to TDLib updates and starts dispatching `updateCall`. Idempotent.
  void start() {
    if (_started) return;
    _started = true;
    groups.start();
    // A call must not be created/accepted until this resolves. Otherwise a fast
    // tap can send the stale fallback protocol while the native engine is still
    // reporting its actual versions, leaving the peers unable to bring up media.
    _protocolReady = _loadProtocol();
    // Outbound media signaling → TDLib. (v3/v4 calls negotiate WebRTC over this.)
    _engine.onSignalingData = _sendSignaling;
    _sub = _client.subscribe().listen((update) {
      switch (update.type) {
        case 'updateCall':
          final c = update.obj('call');
          if (c != null) _handle(c);
        case 'updateNewCallSignalingData':
          // Inbound media signaling → the engine. `data` is base64 in TDLib JSON.
          final d = update.str('data');
          if (d != null) {
            try {
              _engine.receiveSignaling(base64.decode(d));
            } catch (_) {}
          }
      }
    });
  }

  void _sendSignaling(Uint8List data) {
    final callId = call?.callId;
    if (callId == null || callId == 0) return;
    _client.send({
      '@type': 'sendCallSignalingData',
      'call_id': callId,
      'data': base64.encode(data),
    });
  }

  void _ignoreSystemError(Future<void> operation) {
    unawaited(operation.catchError((Object _) {}));
  }

  @override
  void dispose() {
    _sub?.cancel();
    groups.removeListener(_groupCallChanged);
    groups.dispose();
    super.dispose();
  }

  // MARK: - User actions

  /// Places an outgoing call. Sets a `.requesting` placeholder immediately and
  /// resolves the peer's name/photo in the background.
  void startCall(int userId, bool isVideo) {
    if (groups.session != null) return;
    isMuted = false;
    isSpeaker = false;
    isVideoEnabled = isVideo;
    call = ActiveCall(
      callId: 0,
      peerUserId: userId,
      isOutgoing: true,
      isVideo: isVideo,
      phase: CallPhase.requesting,
    );
    notifyListeners();
    unawaited(_ensureSystemConversation(call!));
    _resolvePeer(userId);
    unawaited(_createCall(call!));
  }

  Future<void> startGroupCall({
    required int chatId,
    required String title,
    required bool isVideo,
  }) {
    if (call != null) {
      return Future.error(StateError('Another call is already active'));
    }
    return groups.startOrJoin(chatId: chatId, title: title, isVideo: isVideo);
  }

  void accept() {
    final active = call;
    if (active == null || active.callId == 0) return;
    unawaited(_acceptCall(active));
  }

  Future<void> _loadProtocol() async {
    Map<String, dynamic>? protocol;
    try {
      protocol = await _engine.queryProtocol().timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
    } catch (_) {
      return;
    }
    if (protocol == null) return;
    final versions = (protocol['versions'] as List?)
        ?.whereType<String>()
        .toList();
    if (versions != null && versions.isNotEmpty) {
      _libraryVersions = versions;
    }
    if (protocol['min'] is int) _minLayer = protocol['min'] as int;
    if (protocol['max'] is int) _maxLayer = protocol['max'] as int;
    debugPrint(
      '📞 call protocol versions=$_libraryVersions '
      'min=$_minLayer max=$_maxLayer',
    );
  }

  Future<void> _createCall(ActiveCall requestedCall) async {
    await Future.wait<void>([
      _ensureCallPermissions(requestedCall.isVideo),
      _protocolReady,
    ]);
    if (!identical(call, requestedCall)) return;
    if (requestedCall.isVideo && isVideoEnabled) {
      _engine.setVideoEnabled(true, front: useFrontCamera);
    }
    await _client
        .query({
          '@type': 'createCall',
          'user_id': requestedCall.peerUserId,
          'protocol': _callProtocol,
          'is_video': requestedCall.isVideo,
        })
        .catchError((_) => <String, dynamic>{});
  }

  Future<void> _acceptCall(ActiveCall requestedCall) async {
    await Future.wait<void>([
      _ensureCallPermissions(requestedCall.isVideo),
      _protocolReady,
    ]);
    if (!identical(call, requestedCall)) return;
    if (requestedCall.isVideo && isVideoEnabled) {
      _engine.setVideoEnabled(true, front: useFrontCamera);
    }
    await _client
        .query({
          '@type': 'acceptCall',
          'call_id': requestedCall.callId,
          'protocol': _callProtocol,
        })
        .catchError((_) => <String, dynamic>{});
  }

  /// Ensures mic (and camera, for video) permission before placing/answering a
  /// call — ntgcalls opens the devices itself, so the runtime grant must precede
  /// createCall/acceptCall. Best-effort: proceeds even if denied (audio-only).
  Future<void> _ensureCallPermissions(bool video) async {
    try {
      await <Permission>[
        Permission.microphone,
        if (video) Permission.camera,
      ].request();
    } catch (_) {}
  }

  void end() => _end(reportSystem: true);

  void _end({required bool reportSystem}) {
    final current = call;
    if (current == null) return;
    final duration = current.startedAt == null
        ? 0
        : DateTime.now().difference(current.startedAt!).inSeconds;
    final callId = current.callId;
    final isVideo = current.isVideo;
    current.phase = CallPhase.ending;
    notifyListeners();

    if (callId != 0) {
      _client
          .query({
            '@type': 'discardCall',
            'call_id': callId,
            'is_disconnected': false,
            'invite_link': '',
            'duration': duration,
            'is_video': isVideo,
            'connection_id': 0,
          })
          .catchError((_) => <String, dynamic>{});
    }
    _engine.stop();
    if (reportSystem) {
      _ignoreSystemError(
        LiveCommunicationBridge.instance.end(current.systemUuid),
      );
    }
    _clear();
  }

  void toggleMute() => _setMuted(!isMuted, reportSystem: true);

  void _setMuted(bool muted, {required bool reportSystem}) {
    if (isMuted == muted) return;
    isMuted = muted;
    _engine.setMuted(isMuted);
    final active = call;
    if (active != null && reportSystem) {
      _ignoreSystemError(
        LiveCommunicationBridge.instance.setMuted(active.systemUuid, isMuted),
      );
    }
    notifyListeners();
  }

  void toggleSpeaker() {
    isSpeaker = !isSpeaker;
    _engine.setSpeaker(isSpeaker);
    notifyListeners();
  }

  /// Turn the outgoing camera on with the chosen lens. The UI shows a front/back
  /// selector before calling this. `call.isVideo` remains the original Telegram
  /// call type; the live call surface follows [isVideoEnabled].
  void enableVideo(bool front) {
    isVideoEnabled = true;
    useFrontCamera = front;
    _engine.setVideoEnabled(true, front: front);
    notifyListeners();
  }

  /// Turn the outgoing camera off and return to the voice-call surface. The call
  /// stays up and video can be re-enabled at any time.
  void disableVideo() {
    isVideoEnabled = false;
    _engine.setVideoEnabled(false);
    notifyListeners();
  }

  /// Flip the front/back camera during a video call.
  void switchCamera() {
    useFrontCamera = !useFrontCamera;
    _engine.switchCamera();
    notifyListeners();
  }

  // MARK: - Update handling

  void _handle(Map<String, dynamic> tdCall) {
    final callId = tdCall.integer('id');
    if (callId == null) return;
    final peerUserId = tdCall.int64('user_id') ?? 0;
    final isOutgoing = tdCall.boolean('is_outgoing') ?? false;
    final isVideo = tdCall.boolean('is_video') ?? false;
    final state = tdCall.obj('state');
    debugPrint(
      '📞 TDLib call id=$callId state=${state?.type ?? "unknown"} '
      'outgoing=$isOutgoing video=$isVideo',
    );

    switch (state?.type) {
      case 'callStatePending':
        final isReceived = state?.boolean('is_received') ?? false;
        if (isOutgoing) {
          _bindCallId(callId);
          _updatePhase(
            isReceived ? CallPhase.ringingOutgoing : CallPhase.requesting,
            callId,
          );
        } else if (call?.callId != callId) {
          call = ActiveCall(
            callId: callId,
            peerUserId: peerUserId,
            isOutgoing: false,
            isVideo: isVideo,
            phase: CallPhase.ringingIncoming,
          );
          isMuted = false;
          isSpeaker = false;
          isVideoEnabled = isVideo;
          notifyListeners();
          unawaited(_ensureSystemConversation(call!));
          _resolvePeer(peerUserId);
        } else {
          _updatePhase(CallPhase.ringingIncoming, callId);
        }

      case 'callStateExchangingKeys':
        _bindCallId(callId);
        _updatePhase(CallPhase.exchangingKeys, callId);

      case 'callStateReady':
        _bindCallId(callId);
        final active = call;
        if (active == null || active.callId != callId) break;
        active.phase = CallPhase.active;
        active.startedAt ??= DateTime.now();
        final emojis = state?['emojis'];
        active.emojis = emojis is List
            ? emojis.whereType<String>().toList()
            : const [];
        notifyListeners();

        final remoteVersions = () {
          final versions = state?.obj('protocol')?['library_versions'];
          return versions is List
              ? versions.whereType<String>().toList()
              : <String>[];
        }();
        final selectedVersion = selectCallLibraryVersion(
          localVersions: _libraryVersions,
          remoteVersions: remoteVersions,
        );
        if (selectedVersion == null) {
          debugPrint(
            '📞 no common tgcalls version; '
            'local=$_libraryVersions remote=$remoteVersions',
          );
          _engine.stop();
          _client
              .query({
                '@type': 'discardCall',
                'call_id': callId,
                'is_disconnected': true,
                'invite_link': '',
                'duration': 0,
                'is_video': active.isVideo,
                'connection_id': 0,
              })
              .catchError((_) => <String, dynamic>{});
          active.phase = CallPhase.ending;
          notifyListeners();
          break;
        }
        debugPrint(
          '📞 call ready version=$selectedVersion '
          'remoteVersions=$remoteVersions servers=${state?.objects("servers")?.length ?? 0}',
        );

        _engine.start(
          CallReadyConfig(
            callId: callId,
            servers:
                state?.objects('servers') ?? const <Map<String, dynamic>>[],
            encryptionKey: _decodeKey(state?.str('encryption_key')),
            config: state?.str('config') ?? '',
            customParameters: state?.str('custom_parameters') ?? '',
            // `callStateReady.protocol` describes the peer. Pass one mutually
            // supported version to the native engine, matching Telegram's own
            // first-local-preference selection.
            libraryVersions: [selectedVersion],
            maxLayer: state?.obj('protocol')?.integer('max_layer') ?? _maxLayer,
            isOutgoing: active.isOutgoing,
            isVideo: isVideoEnabled,
            allowP2p: state?.boolean('allow_p2p') ?? true,
          ),
        );
        unawaited(
          _ensureSystemConversation(active)
              .then<void>((_) async {
                if (!active.systemConversationStarted) return;
                await LiveCommunicationBridge.instance.connected(
                  active.systemUuid,
                );
              })
              .catchError((Object _) {}),
        );

      case 'callStateHangingUp':
        _updatePhase(CallPhase.ending, callId);

      case 'callStateDiscarded':
      case 'callStateError':
        _engine.stop();
        final active = call;
        if (active != null) {
          _ignoreSystemError(
            LiveCommunicationBridge.instance.end(active.systemUuid),
          );
        }
        _clear();
    }
  }

  // MARK: - Helpers

  Uint8List _decodeKey(String? b64) {
    if (b64 == null || b64.isEmpty) return Uint8List(0);
    try {
      return base64.decode(b64);
    } catch (_) {
      return Uint8List(0);
    }
  }

  void _bindCallId(int callId) {
    final active = call;
    if (active == null || active.callId != 0) return;
    active.callId = callId;
    notifyListeners();
  }

  void _updatePhase(CallPhase phase, int callId) {
    if (call?.callId != callId) return;
    call?.phase = phase;
    notifyListeners();
  }

  void _clear() {
    call = null;
    isMuted = false;
    isSpeaker = false;
    isVideoEnabled = false;
    notifyListeners();
  }

  Future<void> _resolvePeer(int userId) async {
    try {
      final user = await _client.query({'@type': 'getUser', 'user_id': userId});
      if (call?.peerUserId != userId) return;
      call?.peerName = TDParse.userName(user);
      call?.peerPhoto = TDParse.smallPhoto(user.obj('profile_photo'));
      final active = call;
      if (active != null) {
        _ignoreSystemError(
          LiveCommunicationBridge.instance.updateMembers(active.systemUuid, [
            active.peerName,
          ]),
        );
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _ensureSystemConversation(ActiveCall active) async {
    if (active.systemConversationStarted) return;
    active.systemConversationStarted = true;
    try {
      await LiveCommunicationBridge.instance.start(
        uuid: active.systemUuid,
        title: active.peerName.isEmpty ? 'Telegram' : active.peerName,
        isVideo: active.isVideo,
        memberHandles: [active.peerUserId.toString()],
      );
    } catch (_) {
      active.systemConversationStarted = false;
    }
  }

  void _groupCallChanged() => notifyListeners();

  void _handleSystemMuted(String uuid, bool muted) {
    if (call?.systemUuid == uuid) {
      _setMuted(muted, reportSystem: false);
      return;
    }
    if (groups.session?.systemUuid == uuid) {
      groups.setMutedFromSystem(muted);
    }
  }

  void _handleSystemEnded(String uuid) {
    if (call?.systemUuid == uuid) {
      _end(reportSystem: false);
      return;
    }
    if (groups.session?.systemUuid == uuid) {
      unawaited(groups.endFromSystem());
    }
  }
}
