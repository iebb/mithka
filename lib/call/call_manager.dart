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

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import 'call_media_engine.dart';
import 'tgcalls_media_engine.dart';

enum CallPhase {
  requesting, // outgoing, createCall sent, awaiting TDLib's call id
  ringingIncoming, // incoming pending, awaiting accept
  ringingOutgoing, // outgoing pending, peer's phone is ringing
  exchangingKeys, // both sides agreed, deriving the shared key
  active, // media flowing (callStateReady)
  ending, // hanging up / discarded
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
  });
  int callId;
  final int peerUserId;
  String peerName;
  TdFileRef? peerPhoto;
  final bool isOutgoing;
  bool isVideo;
  CallPhase phase;
  List<String> emojis;
  DateTime? startedAt;
}

class CallManager extends ChangeNotifier {
  CallManager({CallMediaEngine? engine}) : _engine = engine ?? _defaultEngine();

  /// Android gets the real ntgcalls engine; other platforms fall back to Noop
  /// (signaling works, no audio) until a native engine exists for them.
  static CallMediaEngine _defaultEngine() =>
      Platform.isAndroid ? TgcallsMediaEngine() : NoopCallMediaEngine();

  final TdClient _client = TdClient.shared;
  final CallMediaEngine _engine;
  StreamSubscription? _sub;
  bool _started = false;

  ActiveCall? call;
  bool isMuted = false;
  bool isSpeaker = false;
  bool isVideoEnabled = false;

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
    // Advertise the engine's own protocol so TDLib negotiates a compatible version.
    _engine.queryProtocol().then((p) {
      if (p == null) return;
      final v = (p['versions'] as List?)?.whereType<String>().toList();
      if (v != null && v.isNotEmpty) _libraryVersions = v;
      if (p['min'] is int) _minLayer = p['min'] as int;
      if (p['max'] is int) _maxLayer = p['max'] as int;
      debugPrint(
        '📞 ntgcalls protocol versions=$_libraryVersions '
        'min=$_minLayer max=$_maxLayer',
      );
    });
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

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // MARK: - User actions

  /// Places an outgoing call. Sets a `.requesting` placeholder immediately and
  /// resolves the peer's name/photo in the background.
  void startCall(int userId, bool isVideo) {
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
    _resolvePeer(userId);
    _client
        .query({
          '@type': 'createCall',
          'user_id': userId,
          'protocol': _callProtocol,
          'is_video': isVideo,
        })
        .catchError((_) => <String, dynamic>{});
  }

  void accept() {
    final callId = call?.callId;
    if (callId == null) return;
    _client
        .query({
          '@type': 'acceptCall',
          'call_id': callId,
          'protocol': _callProtocol,
        })
        .catchError((_) => <String, dynamic>{});
  }

  void end() {
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
    _clear();
  }

  void toggleMute() {
    isMuted = !isMuted;
    _engine.setMuted(isMuted);
    notifyListeners();
  }

  void toggleSpeaker() {
    isSpeaker = !isSpeaker;
    _engine.setSpeaker(isSpeaker);
    notifyListeners();
  }

  void toggleVideo() {
    isVideoEnabled = !isVideoEnabled;
    call?.isVideo = isVideoEnabled;
    _engine.setVideoEnabled(isVideoEnabled);
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

        _engine.start(
          CallReadyConfig(
            callId: callId,
            servers:
                state?.objects('servers') ?? const <Map<String, dynamic>>[],
            encryptionKey: _decodeKey(state?.str('encryption_key')),
            config: state?.str('config') ?? '',
            customParameters: state?.str('custom_parameters') ?? '',
            libraryVersions: () {
              final v = state?.obj('protocol')?['library_versions'];
              return v is List ? v.whereType<String>().toList() : <String>[];
            }(),
            isOutgoing: active.isOutgoing,
            isVideo: active.isVideo,
            allowP2p: state?.boolean('allow_p2p') ?? true,
          ),
        );

      case 'callStateHangingUp':
        _updatePhase(CallPhase.ending, callId);

      case 'callStateDiscarded':
      case 'callStateError':
        _engine.stop();
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
      notifyListeners();
    } catch (_) {}
  }
}
