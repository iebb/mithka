import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import 'group_call_media_engine.dart';
import 'live_communication_bridge.dart';
import 'tgcalls_group_media_engine.dart';

enum GroupCallPhase { joining, active, ending }

Map<String, dynamic> buildGroupCallJoinParameters(
  GroupCallJoinPayload join, {
  required bool isMuted,
  required bool isVideoEnabled,
}) => {
  '@type': 'groupCallJoinParameters',
  'audio_source_id': join.audioSourceId,
  'payload': join.payload,
  'is_muted': isMuted,
  'is_my_video_enabled': isVideoEnabled,
};

Map<String, dynamic> buildJoinVideoChatRequest({
  required int groupCallId,
  required GroupCallJoinPayload join,
  required bool isMuted,
  required bool isVideoEnabled,
  required String inviteHash,
  Map<String, dynamic>? participantId,
}) => {
  '@type': 'joinVideoChat',
  'group_call_id': groupCallId,
  'participant_id': ?participantId,
  'join_parameters': buildGroupCallJoinParameters(
    join,
    isMuted: isMuted,
    isVideoEnabled: isVideoEnabled,
  ),
  'invite_hash': inviteHash,
};

Map<String, dynamic> buildJoinUnboundGroupCallRequest({
  required String inviteLink,
  required GroupCallJoinPayload join,
  required bool isMuted,
  required bool isVideoEnabled,
}) => {
  '@type': 'joinGroupCall',
  'input_group_call': {'@type': 'inputGroupCallLink', 'link': inviteLink},
  'join_parameters': buildGroupCallJoinParameters(
    join,
    isMuted: isMuted,
    isVideoEnabled: isVideoEnabled,
  ),
};

class GroupCallParticipant {
  GroupCallParticipant({
    required this.key,
    required this.sender,
    required this.audioSourceId,
    required this.order,
    required this.isCurrentUser,
    required this.isSpeaking,
    required this.isMuted,
    this.name = '',
    this.photo,
    this.videoEndpointId,
    this.videoSourceGroups = const [],
    this.isVideoPaused = false,
  });

  final String key;
  final Map<String, dynamic> sender;
  final int audioSourceId;
  String order;
  final bool isCurrentUser;
  bool isSpeaking;
  bool isMuted;
  String name;
  TdFileRef? photo;
  String? videoEndpointId;
  List<GroupCallVideoSourceGroup> videoSourceGroups;
  bool isVideoPaused;

  bool get hasVideo =>
      videoEndpointId != null && videoEndpointId!.isNotEmpty && !isVideoPaused;

  static GroupCallParticipant? fromTd(Map<String, dynamic> raw) {
    final sender = raw.obj('participant_id');
    if (sender == null) return null;
    final key = senderKey(sender);
    if (key == null) return null;
    final video = raw.obj('video_info');
    final groups = <GroupCallVideoSourceGroup>[];
    for (final group
        in video?.objects('source_groups') ?? const <Map<String, dynamic>>[]) {
      final semantics = group.str('semantics');
      final ids = group.int64Array('source_ids');
      if (semantics != null && ids != null && ids.isNotEmpty) {
        groups.add(
          GroupCallVideoSourceGroup(semantics: semantics, sourceIds: ids),
        );
      }
    }
    return GroupCallParticipant(
      key: key,
      sender: sender,
      audioSourceId: raw.integer('audio_source_id') ?? 0,
      order: raw.str('order') ?? '',
      isCurrentUser: raw.boolean('is_current_user') ?? false,
      isSpeaking: raw.boolean('is_speaking') ?? false,
      isMuted:
          (raw.boolean('is_muted_for_all_users') ?? false) ||
          (raw.boolean('is_muted_for_current_user') ?? false),
      videoEndpointId: video?.str('endpoint_id'),
      videoSourceGroups: groups,
      isVideoPaused: video?.boolean('is_paused') ?? false,
    );
  }

  static String? senderKey(Map<String, dynamic> sender) {
    final id = switch (sender.type) {
      'messageSenderUser' => sender.int64('user_id'),
      'messageSenderChat' => sender.int64('chat_id'),
      _ => null,
    };
    if (id == null) return null;
    return '${sender.type == 'messageSenderUser' ? 'u' : 'c'}:$id';
  }
}

class ActiveGroupCall {
  ActiveGroupCall({
    required this.chatId,
    required this.groupCallId,
    required this.title,
    required this.isVideo,
    required this.phase,
    required this.systemUuid,
    this.startedAt,
    this.isOwned = false,
  });

  final int chatId;
  final int groupCallId;
  String title;
  bool isVideo;
  GroupCallPhase phase;
  final String systemUuid;
  DateTime? startedAt;
  bool isOwned;
}

class GroupCallController extends ChangeNotifier {
  GroupCallController({GroupCallMediaEngine? engine, TdClient? client})
    : _engine = engine ?? _defaultEngine(),
      _client = client ?? TdClient.shared;

  static GroupCallMediaEngine _defaultEngine() =>
      Platform.isAndroid || Platform.isIOS
      ? TgcallsGroupMediaEngine()
      : UnsupportedGroupCallMediaEngine();

  final TdClient _client;
  final GroupCallMediaEngine _engine;
  StreamSubscription? _subscription;
  final Map<String, GroupCallParticipant> _participants = {};
  final List<String> _displayOrder = [];
  Map<String, dynamic>? _selfSender;
  String _inviteHash = '';
  String _unboundInviteLink = '';

  ActiveGroupCall? session;
  bool isMuted = false;
  bool isSpeaker = true;
  bool isVideoEnabled = false;
  bool useFrontCamera = true;
  bool isMinimized = false;

  List<GroupCallParticipant> get participants {
    final ordered = <GroupCallParticipant>[];
    for (final key in _displayOrder) {
      final participant = _participants[key];
      if (participant != null) ordered.add(participant);
    }
    final missing =
        _participants.values
            .where((participant) => !_displayOrder.contains(participant.key))
            .toList()
          ..sort((a, b) => b.order.compareTo(a.order));
    ordered.addAll(missing);
    return ordered;
  }

  void start() {
    _subscription ??= _client.subscribe().listen(_handleUpdate);
  }

  Future<void> startOrJoin({
    required int chatId,
    required String title,
    required bool isVideo,
    String inviteHash = '',
  }) async {
    if (session != null) return;
    if (!await _engine.isSupported) {
      throw UnsupportedError(
        'This build does not include Telegram group-call media for this platform',
      );
    }
    await _ensurePermissions(isVideo);

    final chat = await _client.query({'@type': 'getChat', 'chat_id': chatId});
    final videoChat = chat.obj('video_chat');
    var groupCallId = videoChat?.integer('group_call_id') ?? 0;
    if (groupCallId == 0) {
      final created = await _client.query({
        '@type': 'createVideoChat',
        'chat_id': chatId,
        'title': '',
        'start_date': 0,
        'is_rtmp_stream': false,
      });
      groupCallId = created.integer('id') ?? 0;
      if (groupCallId == 0) {
        throw StateError('Telegram did not return a group call identifier');
      }
    }

    final uuid = LiveCommunicationBridge.newUuid();
    session = ActiveGroupCall(
      chatId: chatId,
      groupCallId: groupCallId,
      title: title,
      isVideo: isVideo,
      phase: GroupCallPhase.joining,
      systemUuid: uuid,
    );
    isMuted = false;
    isSpeaker = true;
    isVideoEnabled = isVideo;
    _inviteHash = inviteHash;
    _unboundInviteLink = '';
    notifyListeners();
    await LiveCommunicationBridge.instance.start(
      uuid: uuid,
      title: title,
      isVideo: isVideo,
      memberHandles: const [],
    );

    try {
      final me = await _client.query({'@type': 'getMe'});
      final meId = me.int64('id');
      if (meId != null) {
        _selfSender = {'@type': 'messageSenderUser', 'user_id': meId};
      }
      final join = await _engine.createJoinPayload(
        groupCallId: groupCallId,
        isVideo: isVideo,
      );
      final defaultParticipant = videoChat?.obj('default_participant_id');
      if (defaultParticipant != null) {
        _selfSender = defaultParticipant;
      }
      await _joinWithPayload(join, isVideoEnabled: isVideo);

      final current = session;
      if (current == null || current.groupCallId != groupCallId) return;
      current.phase = GroupCallPhase.active;
      current.startedAt = DateTime.now();
      await _refreshGroupCall();
      unawaited(
        _client
            .query({
              '@type': 'loadGroupCallParticipants',
              'group_call_id': groupCallId,
              'limit': 100,
            })
            .catchError((_) => <String, dynamic>{}),
      );
      await LiveCommunicationBridge.instance.connected(uuid);
      notifyListeners();
    } catch (_) {
      await _leave(clearTelegram: true, reportSystem: true);
      rethrow;
    }
  }

  Future<void> joinUnbound({
    required String inviteLink,
    String title = 'Group call',
    bool isVideo = true,
  }) async {
    if (session != null) return;
    final link = inviteLink.trim();
    if (link.isEmpty) throw ArgumentError.value(inviteLink, 'inviteLink');
    if (!await _engine.isSupported) {
      throw UnsupportedError(
        'This build does not include Telegram group-call media for this platform',
      );
    }
    await _ensurePermissions(isVideo);
    final temporaryMediaId = link.hashCode & 0x7fffffff;
    final join = await _engine.createJoinPayload(
      groupCallId: temporaryMediaId == 0 ? 1 : temporaryMediaId,
      isVideo: isVideo,
    );
    isMuted = false;
    isSpeaker = true;
    isVideoEnabled = isVideo;
    final response = await _client.query(
      buildJoinUnboundGroupCallRequest(
        inviteLink: link,
        join: join,
        isMuted: isMuted,
        isVideoEnabled: isVideo,
      ),
    );
    final groupCallId = response.integer('group_call_id') ?? 0;
    final responsePayload = response.str('join_payload') ?? '';
    if (groupCallId == 0 || responsePayload.isEmpty) {
      _engine.stop();
      throw StateError('Telegram returned invalid group-call join data');
    }
    final uuid = LiveCommunicationBridge.newUuid();
    session = ActiveGroupCall(
      chatId: 0,
      groupCallId: groupCallId,
      title: title,
      isVideo: isVideo,
      phase: GroupCallPhase.joining,
      systemUuid: uuid,
    );
    _inviteHash = '';
    _unboundInviteLink = link;
    notifyListeners();
    try {
      final me = await _client.query({'@type': 'getMe'});
      final meId = me.int64('id');
      if (meId != null) {
        _selfSender = {'@type': 'messageSenderUser', 'user_id': meId};
      }
      await LiveCommunicationBridge.instance.start(
        uuid: uuid,
        title: title,
        isVideo: isVideo,
        memberHandles: const [],
      );
      await _engine.connect(responsePayload);
      final current = session;
      if (current == null || current.groupCallId != groupCallId) return;
      current.phase = GroupCallPhase.active;
      current.startedAt = DateTime.now();
      await _refreshGroupCall();
      await _refreshUnboundParticipants();
      await LiveCommunicationBridge.instance.connected(uuid);
      notifyListeners();
    } catch (_) {
      await _leave(clearTelegram: true, reportSystem: true);
      rethrow;
    }
  }

  Future<void> end() => _leave(clearTelegram: true, reportSystem: true);

  Future<void> endFromSystem() =>
      _leave(clearTelegram: true, reportSystem: false);

  Future<void> _leave({
    required bool clearTelegram,
    required bool reportSystem,
  }) async {
    final current = session;
    if (current == null) return;
    current.phase = GroupCallPhase.ending;
    notifyListeners();
    _engine.stop();
    if (clearTelegram) {
      unawaited(
        _client
            .query({
              '@type': 'leaveGroupCall',
              'group_call_id': current.groupCallId,
            })
            .catchError((_) => <String, dynamic>{}),
      );
    }
    if (reportSystem) {
      await LiveCommunicationBridge.instance.end(current.systemUuid);
    }
    _clear();
  }

  void toggleMute() => _setMuted(!isMuted, reportSystem: true);

  void setMutedFromSystem(bool muted) => _setMuted(muted, reportSystem: false);

  void _setMuted(bool muted, {required bool reportSystem}) {
    final current = session;
    if (current == null) return;
    if (isMuted == muted) return;
    isMuted = muted;
    _engine.setMuted(isMuted);
    final sender = _selfSender;
    if (sender != null) {
      unawaited(
        _client
            .query({
              '@type': 'toggleGroupCallParticipantIsMuted',
              'group_call_id': current.groupCallId,
              'participant_id': sender,
              'is_muted': isMuted,
            })
            .catchError((_) => <String, dynamic>{}),
      );
    }
    if (reportSystem) {
      unawaited(
        LiveCommunicationBridge.instance.setMuted(current.systemUuid, isMuted),
      );
    }
    notifyListeners();
  }

  void toggleSpeaker() {
    isSpeaker = !isSpeaker;
    _engine.setSpeaker(isSpeaker);
    notifyListeners();
  }

  void setVideoEnabled(bool enabled, {bool front = true}) {
    final current = session;
    if (current == null) return;
    isVideoEnabled = enabled;
    useFrontCamera = front;
    current.isVideo = current.isVideo || enabled;
    notifyListeners();
    unawaited(_setVideoEnabled(enabled, front: front));
  }

  Future<void> _setVideoEnabled(bool enabled, {required bool front}) async {
    final current = session;
    if (current == null) return;
    try {
      final rejoinPayload = await _engine.setVideoEnabled(
        enabled,
        front: front,
      );
      if (rejoinPayload != null && session == current) {
        await _joinWithPayload(rejoinPayload, isVideoEnabled: enabled);
      }
    } catch (error) {
      logGroupCallMediaError('setVideoEnabled', error);
    }
    unawaited(
      _client
          .query({
            '@type': 'toggleGroupCallIsMyVideoEnabled',
            'group_call_id': current.groupCallId,
            'is_my_video_enabled': enabled,
          })
          .catchError((_) => <String, dynamic>{}),
    );
    notifyListeners();
  }

  Future<void> _joinWithPayload(
    GroupCallJoinPayload join, {
    required bool isVideoEnabled,
  }) async {
    final current = session;
    if (current == null) return;
    final sender = _selfSender;
    final request = buildJoinVideoChatRequest(
      groupCallId: current.groupCallId,
      join: join,
      isMuted: isMuted,
      isVideoEnabled: isVideoEnabled,
      inviteHash: _inviteHash,
      participantId: sender,
    );
    final response = await _client.query(request);
    final responsePayload = response.str('text');
    if (responsePayload == null || responsePayload.isEmpty) {
      throw StateError('Telegram returned no tgcalls response payload');
    }
    await _engine.connect(responsePayload);
  }

  void switchCamera() {
    useFrontCamera = !useFrontCamera;
    _engine.switchCamera();
    notifyListeners();
  }

  void moveParticipant(String draggedKey, String targetKey) {
    if (draggedKey == targetKey) return;
    _ensureDisplayOrder();
    final from = _displayOrder.indexOf(draggedKey);
    final to = _displayOrder.indexOf(targetKey);
    if (from < 0 || to < 0) return;
    final value = _displayOrder.removeAt(from);
    _displayOrder.insert(to, value);
    notifyListeners();
  }

  void minimize() {
    if (session == null || isMinimized) return;
    isMinimized = true;
    notifyListeners();
  }

  void restore() {
    if (!isMinimized) return;
    isMinimized = false;
    notifyListeners();
  }

  void _handleUpdate(Map<String, dynamic> update) {
    final current = session;
    if (current == null) return;
    switch (update.type) {
      case 'updateGroupCall':
        final groupCall = update.obj('group_call');
        if (groupCall?.integer('id') != current.groupCallId) return;
        current.title = groupCall?.str('title')?.trim().isNotEmpty == true
            ? groupCall!.str('title')!
            : current.title;
        current.isOwned = groupCall?.boolean('is_owned') ?? current.isOwned;
        if (groupCall?.boolean('is_active') == false) {
          unawaited(_leave(clearTelegram: false, reportSystem: true));
          return;
        }
        if (groupCall?.boolean('need_rejoin') == true) {
          unawaited(_leave(clearTelegram: false, reportSystem: true));
          return;
        }
        notifyListeners();
      case 'updateGroupCallParticipant':
        if (update.integer('group_call_id') != current.groupCallId) return;
        final raw = update.obj('participant');
        if (raw != null) _upsertParticipant(raw);
      case 'updateGroupCallParticipants':
        if (update.integer('group_call_id') != current.groupCallId ||
            _unboundInviteLink.isEmpty) {
          return;
        }
        unawaited(_refreshUnboundParticipants());
    }
  }

  Future<void> _refreshGroupCall() async {
    final current = session;
    if (current == null) return;
    final groupCall = await _client.query({
      '@type': 'getGroupCall',
      'group_call_id': current.groupCallId,
    });
    current.title = groupCall.str('title')?.trim().isNotEmpty == true
        ? groupCall.str('title')!
        : current.title;
    current.isOwned = groupCall.boolean('is_owned') ?? false;
  }

  Future<void> _refreshUnboundParticipants() async {
    final link = _unboundInviteLink;
    if (link.isEmpty || session == null) return;
    final response = await _client.query({
      '@type': 'getGroupCallParticipants',
      'input_group_call': {'@type': 'inputGroupCallLink', 'link': link},
      'limit': 100,
    });
    final senders = response.objects('participant_ids') ?? const [];
    final keep = <String>{};
    for (final sender in senders) {
      final key = GroupCallParticipant.senderKey(sender);
      if (key == null) continue;
      keep.add(key);
      final previous = _participants[key];
      final participant = GroupCallParticipant(
        key: key,
        sender: sender,
        audioSourceId: previous?.audioSourceId ?? 0,
        order: previous?.order ?? '1',
        isCurrentUser:
            GroupCallParticipant.senderKey(_selfSender ?? const {}) == key,
        isSpeaking: previous?.isSpeaking ?? false,
        isMuted: previous?.isMuted ?? false,
        name: previous?.name ?? '',
        photo: previous?.photo,
      );
      _participants[key] = participant;
      if (!_displayOrder.contains(key)) _displayOrder.add(key);
      unawaited(_resolveParticipant(participant));
    }
    _participants.removeWhere((key, _) => !keep.contains(key));
    _displayOrder.removeWhere((key) => !keep.contains(key));
    _updateSystemMembers();
    notifyListeners();
  }

  void _upsertParticipant(Map<String, dynamic> raw) {
    final parsed = GroupCallParticipant.fromTd(raw);
    if (parsed == null) return;
    final old = _participants[parsed.key];
    if (parsed.order.isEmpty) {
      _participants.remove(parsed.key);
      _displayOrder.remove(parsed.key);
      _syncMediaSubscriptions();
      _updateSystemMembers();
      notifyListeners();
      return;
    }
    if (old != null) {
      parsed.name = old.name;
      parsed.photo = old.photo;
    }
    _participants[parsed.key] = parsed;
    _displayOrder.add(parsed.key);
    _ensureDisplayOrder();
    _syncMediaSubscriptions();
    unawaited(_resolveParticipant(parsed));
    _updateSystemMembers();
    notifyListeners();
  }

  void _syncMediaSubscriptions() {
    final mediaDescriptions = _participants.values
        .where((participant) => participant.audioSourceId != 0)
        .map(
          (participant) => GroupCallMediaChannelDescription(
            audioSourceId: participant.audioSourceId,
            userId: _participantId(participant),
          ),
        )
        .where((description) => description.userId != 0)
        .toList(growable: false);
    _engine.setMediaChannelDescriptions(mediaDescriptions);

    final videoParticipants = _participants.values
        .where(
          (participant) =>
              !participant.isCurrentUser &&
              participant.hasVideo &&
              participant.videoSourceGroups.isNotEmpty,
        )
        .toList(growable: false);
    final maxQuality = switch (videoParticipants.length) {
      0 => GroupCallVideoQuality.thumbnail,
      1 => GroupCallVideoQuality.full,
      <= 4 => GroupCallVideoQuality.medium,
      _ => GroupCallVideoQuality.thumbnail,
    };
    final channels = videoParticipants
        .map(
          (participant) => GroupCallVideoChannel(
            audioSourceId: participant.audioSourceId,
            userId: _participantId(participant),
            endpointId: participant.videoEndpointId!,
            sourceGroups: participant.videoSourceGroups,
            maxQuality: maxQuality,
          ),
        )
        .where((channel) => channel.userId != 0)
        .toList(growable: false);
    _engine.setRequestedVideoChannels(channels);
  }

  int _participantId(GroupCallParticipant participant) =>
      switch (participant.sender.type) {
        'messageSenderUser' => participant.sender.int64('user_id') ?? 0,
        'messageSenderChat' => participant.sender.int64('chat_id') ?? 0,
        _ => 0,
      };

  Future<void> _resolveParticipant(GroupCallParticipant participant) async {
    try {
      switch (participant.sender.type) {
        case 'messageSenderUser':
          final id = participant.sender.int64('user_id');
          if (id == null) return;
          final user = await _client.query({'@type': 'getUser', 'user_id': id});
          final current = _participants[participant.key];
          if (current == null) return;
          current.name = TDParse.userName(user);
          current.photo = TDParse.smallPhoto(user.obj('profile_photo'));
        case 'messageSenderChat':
          final id = participant.sender.int64('chat_id');
          if (id == null) return;
          final chat = await _client.query({'@type': 'getChat', 'chat_id': id});
          final current = _participants[participant.key];
          if (current == null) return;
          current.name = chat.str('title') ?? '';
          current.photo = TDParse.smallPhoto(chat.obj('photo'));
      }
      _updateSystemMembers();
      notifyListeners();
    } catch (_) {}
  }

  void _ensureDisplayOrder() {
    final seen = <String>{};
    _displayOrder.removeWhere(
      (key) => !_participants.containsKey(key) || !seen.add(key),
    );
    final missing =
        _participants.values
            .where((participant) => !seen.contains(participant.key))
            .toList()
          ..sort((a, b) => b.order.compareTo(a.order));
    _displayOrder.addAll(missing.map((participant) => participant.key));
  }

  void _updateSystemMembers() {
    final current = session;
    if (current == null) return;
    unawaited(
      LiveCommunicationBridge.instance.updateMembers(
        current.systemUuid,
        participants
            .map((participant) => participant.name)
            .where((name) => name.isNotEmpty)
            .toList(),
      ),
    );
  }

  Future<void> _ensurePermissions(bool video) async {
    await <Permission>[
      Permission.microphone,
      if (video) Permission.camera,
    ].request();
  }

  void _clear() {
    session = null;
    _participants.clear();
    _displayOrder.clear();
    _selfSender = null;
    _inviteHash = '';
    _unboundInviteLink = '';
    isMuted = false;
    isSpeaker = true;
    isVideoEnabled = false;
    isMinimized = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _engine.stop();
    super.dispose();
  }
}
