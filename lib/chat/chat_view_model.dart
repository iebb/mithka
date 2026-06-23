//
//  chat_view_model.dart
//
//  Conversation view model. Opens a chat, loads history, and keeps the message
//  list live by folding TDLib updates. For groups/channels it resolves each
//  incoming message's sender name + photo + role through a small cache so
//  bubbles can show "who said what". Port of the Swift `ChatViewModel`.
//

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import 'sticker_item.dart';

class _SenderInfo {
  _SenderInfo(this.name, this.photo, this.role, this.title);
  final String name;
  final TdFileRef? photo;
  final MemberRole role;
  final String? title;
}

class ChatViewModel extends ChangeNotifier {
  ChatViewModel({required this.chatId, required String title})
    : peerTitle = title;

  final int chatId;

  List<ChatMessage> messages = [];
  String peerTitle;
  TdFileRef? peerPhoto;
  bool isGroup = false;
  int memberCount = 0;
  int? peerUserId; // private chat → call target
  String meName = '我';
  TdFileRef? mePhoto;
  String draft = '';
  ChatMessage? replyTo;

  // Live header state.
  bool peerOnline = false;
  String peerStatusText = '';
  int lastReadOutboxId = 0; // outgoing messages with id <= this are read
  int lastReadInboxId = 0; // incoming messages with id <= this are read
  int unreadCount = 0; // unread incoming messages on entry (for the divider)

  // 群公告 / pinned message shown in a bar below the header.
  ChatMessage? pinnedMessage;
  bool pinnedDismissed = false;

  // Membership / send permission. Defaults assume a normal, joined, sendable
  // chat; refined in _loadChatHeader once the chat type + member status load.
  bool canSendMessages = true; // composer enabled
  bool isMember = true; // gates 退出; false → join affordance
  bool canJoin = false; // not a member but joinable (public super/channel/left)
  bool joinByRequest = false; // joining needs approval → "申请加入"
  bool joinRequested = false; // a join request was sent (awaiting approval)
  bool isChannel = false; // broadcast channel (members can't post)
  bool isMuted =
      false; // notifications muted (channel subscribers get a toggle)
  String sendDisabledReason = ''; // shown in the disabled composer bar
  bool _chatCanSend = true; // chat-wide default can_send_basic_messages

  final TdClient _client = TdClient.shared;
  StreamSubscription? _sub;
  bool _isLoadingOlder = false;
  int? _restoreTopId;

  // Typing: sender ids currently acting, auto-cleared after a few seconds.
  final Map<int, String> _typing = {};
  Timer? _typingTimer;

  /// Header title: QQ shows the member count in parentheses after a group name.
  String get headerTitle =>
      (isGroup && memberCount > 0) ? '$peerTitle($memberCount)' : peerTitle;

  /// Subtitle under the title: typing (group/private) or online/last-seen
  /// (private). Group member count lives in the title, not here.
  String get subtitle {
    if (_typing.isNotEmpty) {
      if (!isGroup) return '正在输入…';
      final names = _typing.values.where((n) => n.isNotEmpty).toList();
      if (names.length == 1) return '${names.first} 正在输入…';
      if (names.isNotEmpty) return '${names.length} 人正在输入…';
      return '正在输入…';
    }
    if (isGroup) return '';
    if (peerOnline) return '在线';
    return peerStatusText;
  }

  bool isRead(ChatMessage m) => m.isOutgoing && m.id <= lastReadOutboxId;

  final Map<int, _SenderInfo> _senderCache = {};
  final Set<int> _resolvingSenders = {};

  /// After prepending older history, the view scrolls this id back to the top.
  int? consumeRestoreTop() {
    final id = _restoreTopId;
    _restoreTopId = null;
    return id;
  }

  // MARK: - Lifecycle

  void onAppear() {
    _client.send({'@type': 'openChat', 'chat_id': chatId});
    _subscribeToUpdates();
    () async {
      await _loadMe();
      await _loadChatHeader();
      await _loadInitialHistory();
    }();
  }

  Future<void> _loadMe() async {
    try {
      final me = await _client.query({'@type': 'getMe'});
      final name = TDParse.userName(me);
      if (name.isNotEmpty) meName = name;
      mePhoto = TDParse.smallPhoto(me.obj('profile_photo'));
      notifyListeners();
    } catch (_) {}
  }

  void onDisappear() {
    _sub?.cancel();
    _sub = null;
    _client.send({'@type': 'closeChat', 'chat_id': chatId});
  }

  @override
  void dispose() {
    _sub?.cancel();
    _typingTimer?.cancel();
    super.dispose();
  }

  /// Tell TDLib the user is typing (drives the peer's typing indicator).
  void sendTyping() {
    _client.send({
      '@type': 'sendChatAction',
      'chat_id': chatId,
      'action': {'@type': 'chatActionTyping'},
    });
  }

  // MARK: - Sending

  void setDraft(String value) {
    draft = value;
  }

  /// Appends an "@name " mention to the composer (long-press an avatar).
  void insertMention(String name) {
    if (name.isEmpty) return;
    final sep = (draft.isEmpty || draft.endsWith(' ')) ? '' : ' ';
    draft = '$draft$sep@$name ';
    notifyListeners();
  }

  void send() {
    final trimmed = draft.trim();
    if (trimmed.isEmpty) return;
    draft = '';

    final request = <String, dynamic>{
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessageText',
        'text': {'@type': 'formattedText', 'text': trimmed},
      },
    };
    if (replyTo != null) {
      request['reply_to'] = {
        '@type': 'inputMessageReplyToMessage',
        'message_id': replyTo!.id,
      };
    }
    replyTo = null;
    _client.send(request);
    notifyListeners();
  }

  /// Sends text that may contain inline custom emoji — [entities] is the list of
  /// TDLib textEntity objects (e.g. textEntityTypeCustomEmoji) over [text]
  /// (offsets in UTF-16 of [text], which already has the fallback chars).
  void sendFormatted(String text, List<Map<String, dynamic>> entities) {
    if (text.trim().isEmpty) return;
    draft = '';
    final request = <String, dynamic>{
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessageText',
        'text': {
          '@type': 'formattedText',
          'text': text,
          if (entities.isNotEmpty) 'entities': entities,
        },
      },
    };
    if (replyTo != null) {
      request['reply_to'] = {
        '@type': 'inputMessageReplyToMessage',
        'message_id': replyTo!.id,
      };
    }
    replyTo = null;
    _client.send(request);
    notifyListeners();
  }

  /// 引用: set (or clear) the reply target. In a group, replying to someone also
  /// @-mentions them in the draft (QQ behavior).
  void setReply(ChatMessage? message) {
    replyTo = message;
    if (message != null &&
        isGroup &&
        !message.isOutgoing &&
        (message.senderName?.isNotEmpty ?? false)) {
      final mention = '@${message.senderName} ';
      if (!draft.contains(mention)) draft = mention + draft;
    }
    notifyListeners();
  }

  void sendPhoto(String path) {
    _client.send({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessagePhoto',
        'photo': {
          '@type': 'inputPhoto',
          'photo': {'@type': 'inputFileLocal', 'path': path},
        },
      },
    });
  }

  void sendVideo(String path) {
    _client.send({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessageVideo',
        'video': {
          '@type': 'inputVideo',
          'video': {'@type': 'inputFileLocal', 'path': path},
          'supports_streaming': true,
        },
      },
    });
  }

  void sendSticker(StickerItem sticker) {
    final input = sticker.remoteId != null
        ? {'@type': 'inputFileRemote', 'id': sticker.remoteId}
        : {'@type': 'inputFileId', 'id': sticker.id};
    _client.send({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessageSticker',
        'sticker': input,
        'width': sticker.width,
        'height': sticker.height,
        'emoji': sticker.emoji,
      },
    });
  }

  void sendDocument(String path) {
    _client.send({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessageDocument',
        'document': {
          '@type': 'inputDocument',
          'document': {'@type': 'inputFileLocal', 'path': path},
        },
      },
    });
  }

  void sendLocation(double latitude, double longitude) {
    _client.send({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessageLocation',
        'location': {
          '@type': 'location',
          'latitude': latitude,
          'longitude': longitude,
          'horizontal_accuracy': 0,
        },
      },
    });
  }

  void sendVoice(String path, int duration) {
    _client.send({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessageVoiceNote',
        'voice_note': {'@type': 'inputFileLocal', 'path': path},
        'duration': duration,
      },
    });
  }

  /// 音频: send a picked audio file as a music message (TDLib computes metadata).
  void sendAudio(String path) {
    _client.send({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessageAudio',
        'audio': {
          '@type': 'inputAudio',
          'audio': {'@type': 'inputFileLocal', 'path': path},
          'duration': 0,
          'title': '',
          'performer': '',
        },
      },
    });
  }

  /// 清单: send a checklist (to-do list). Creating checklists needs Premium.
  void sendChecklist(String title, List<String> tasks) {
    final items = tasks
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (title.trim().isEmpty || items.isEmpty) return;
    _client.send({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessageChecklist',
        'checklist': {
          '@type': 'inputChecklist',
          'title': {'@type': 'formattedText', 'text': title.trim()},
          'tasks': [
            for (var i = 0; i < items.length; i++)
              {
                '@type': 'inputChecklistTask',
                'id': i + 1,
                'text': {'@type': 'formattedText', 'text': items[i]},
              },
          ],
          'others_can_add_tasks': false,
          'others_can_mark_tasks_as_done': true,
        },
      },
    });
  }

  void sendPoll(String question, List<String> options) {
    final q = question.trim();
    final opts = options
        .map((o) => o.trim())
        .where((o) => o.isNotEmpty)
        .toList();
    if (q.isEmpty || opts.length < 2) return;
    _client.send({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessagePoll',
        'question': {'@type': 'formattedText', 'text': q},
        'options': opts
            .map((o) => {'@type': 'formattedText', 'text': o})
            .toList(),
        'type': {'@type': 'pollTypeRegular', 'allow_multiple_answers': false},
      },
    });
  }

  /// Re-sends the same content (the "+1" quick repeat) — only plain text and
  /// photos; the badge that calls this is gated to those kinds too.
  void repeatMessage(ChatMessage message) {
    // Photo: send a clean copy (forwardMessages send_copy drops the "转发"
    // header and works regardless of the original file's upload state).
    if (message.isPhoto && message.image != null) {
      _client.send({
        '@type': 'forwardMessages',
        'chat_id': chatId,
        'from_chat_id': chatId,
        'message_ids': [message.id],
        'send_copy': true,
      });
      return;
    }
    if (!message.isPlainText) return;
    final text = message.text.trim();
    if (text.isEmpty) return;
    _client.send({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessageText',
        'text': {'@type': 'formattedText', 'text': text},
      },
    });
  }

  // MARK: - Message actions (long-press menu)

  void forward(int messageId, int targetChatId) {
    _client.send({
      '@type': 'forwardMessages',
      'chat_id': targetChatId,
      'from_chat_id': chatId,
      'message_ids': [messageId],
      'send_copy': false,
      'remove_caption': false,
    });
  }

  Future<void> saveToFavorites(int messageId) async {
    try {
      final me = await _client.query({'@type': 'getMe'});
      final myId = me.int64('id');
      if (myId == null) return;
      _client.send({
        '@type': 'forwardMessages',
        'chat_id': myId,
        'from_chat_id': chatId,
        'message_ids': [messageId],
        'send_copy': true,
        'remove_caption': false,
      });
    } catch (_) {}
  }

  void saveFavoriteSticker(int fileId) {
    _client.send({
      '@type': 'addFavoriteSticker',
      'sticker': {'@type': 'inputFileId', 'id': fileId},
    });
  }

  void deleteMessage(int id) {
    _client.send({
      '@type': 'deleteMessages',
      'chat_id': chatId,
      'message_ids': [id],
      'revoke': true,
    });
    messages.removeWhere((m) => m.id == id);
    if (replyTo?.id == id) replyTo = null;
    notifyListeners();
  }

  // MARK: - Paging

  void loadOlder() {
    if (_isLoadingOlder || messages.isEmpty) return;
    _isLoadingOlder = true;
    _fetchHistory(
      messages.first.id,
      0,
      30,
      isOlder: true,
    ).whenComplete(() => _isLoadingOlder = false);
  }

  // MARK: - Header

  Future<void> _loadChatHeader() async {
    Map<String, dynamic> chat;
    try {
      chat = await _client.query({'@type': 'getChat', 'chat_id': chatId});
    } catch (_) {
      return;
    }
    peerTitle = chat.str('title') ?? peerTitle;
    peerPhoto = TDParse.smallPhoto(chat.obj('photo'));
    lastReadOutboxId = chat.int64('last_read_outbox_message_id') ?? 0;
    lastReadInboxId = chat.int64('last_read_inbox_message_id') ?? 0;
    unreadCount = chat.integer('unread_count') ?? 0;
    isMuted = (chat.obj('notification_settings')?.integer('mute_for') ?? 0) > 0;
    final kind = TDParse.chatKind(chat);
    isGroup = kind == ChatKind.group || kind == ChatKind.channel;

    // Chat-wide default send permission + permissive membership defaults
    // (refined per type below).
    _chatCanSend =
        chat.obj('permissions')?.boolean('can_send_basic_messages') ?? true;
    canSendMessages = true;
    isMember = true;
    canJoin = false;
    joinByRequest = false;
    isChannel = false;
    sendDisabledReason = '';

    final type = chat.obj('type');
    switch (type?.type) {
      case 'chatTypePrivate':
        peerUserId = type?.int64('user_id');
        final uid = peerUserId;
        if (uid != null) {
          try {
            final user = await _client.query({
              '@type': 'getUser',
              'user_id': uid,
            });
            peerOnline = TDParse.isUserOnline(user);
            peerStatusText = TDParse.userStatus(user);
          } catch (_) {}
        }
      case 'chatTypeBasicGroup':
        final gid = type?.int64('basic_group_id');
        if (gid != null) {
          try {
            final bg = await _client.query({
              '@type': 'getBasicGroup',
              'basic_group_id': gid,
            });
            memberCount = bg.integer('member_count') ?? 0;
            _applyGroupStatus(bg.obj('status'));
          } catch (_) {}
        }
      case 'chatTypeSupergroup':
        final sgid = type?.int64('supergroup_id');
        if (sgid != null) {
          try {
            final sg = await _client.query({
              '@type': 'getSupergroup',
              'supergroup_id': sgid,
            });
            isChannel = sg.boolean('is_channel') ?? false;
            joinByRequest = sg.boolean('join_by_request') ?? false;
            _applyGroupStatus(sg.obj('status'));
          } catch (_) {}
          try {
            final full = await _client.query({
              '@type': 'getSupergroupFullInfo',
              'supergroup_id': sgid,
            });
            memberCount = full.integer('member_count') ?? 0;
          } catch (_) {}
        }
    }
    notifyListeners();
    _loadPinnedMessage();
  }

  /// Maps the current user's member status (+ channel-ness / chat defaults) onto
  /// the send / membership / join flags the chat UI reads.
  void _applyGroupStatus(Map<String, dynamic>? status) {
    switch (status?.type) {
      case 'chatMemberStatusCreator':
      case 'chatMemberStatusAdministrator':
        isMember = true;
        canSendMessages = true;
      case 'chatMemberStatusMember':
        isMember = true;
        canSendMessages = isChannel ? false : _chatCanSend;
        if (!canSendMessages) {
          sendDisabledReason = isChannel ? '只有管理员可以发布内容' : '已被全员禁言';
        }
      case 'chatMemberStatusRestricted':
        isMember = status?.boolean('is_member') ?? true;
        canSendMessages =
            status?.obj('permissions')?.boolean('can_send_basic_messages') ??
            false;
        if (!isMember) canJoin = true;
        if (!canSendMessages) sendDisabledReason = '您已被禁言';
      case 'chatMemberStatusLeft':
        isMember = false;
        canSendMessages = false;
        canJoin = true;
      case 'chatMemberStatusBanned':
        isMember = false;
        canSendMessages = false;
        sendDisabledReason = '您已被移出该群组';
    }
  }

  /// Mute / unmute notifications — the bottom-bar action for a channel you're
  /// subscribed to but can't post in (mirrors the official client).
  Future<void> toggleMute() async {
    final target = isMuted;
    isMuted = !isMuted;
    notifyListeners();
    try {
      await _client.query({
        '@type': 'setChatNotificationSettings',
        'chat_id': chatId,
        'notification_settings': {
          '@type': 'chatNotificationSettings',
          'use_default_mute_for': false,
          'mute_for': target ? 0 : 2147483647, // INT32_MAX = "forever"
          'use_default_sound': true,
          'use_default_show_preview': true,
          'use_default_mute_stories': true,
          'use_default_story_sound': true,
          'use_default_show_story_sender': true,
          'use_default_disable_pinned_message_notifications': true,
          'use_default_disable_mention_notifications': true,
        },
      });
    } catch (_) {
      isMuted = target; // revert on failure
      notifyListeners();
    }
  }

  /// Joins (or, for approval-required chats, requests to join) the current chat.
  /// Optimistically updates membership; TDLib updates refine it.
  Future<void> joinChat() async {
    try {
      await _client.query({'@type': 'joinChat', 'chat_id': chatId});
      if (joinByRequest) {
        joinRequested = true;
      } else {
        isMember = true;
        canJoin = false;
        canSendMessages = isChannel ? false : _chatCanSend;
        if (!canSendMessages && isChannel) {
          sendDisabledReason = '只有管理员可以发布内容';
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadPinnedMessage() async {
    try {
      final res = await _client.query({
        '@type': 'searchChatMessages',
        'chat_id': chatId,
        'query': '',
        'sender_id': null,
        'from_message_id': 0,
        'offset': 0,
        'limit': 1,
        'filter': {'@type': 'searchMessagesFilterPinned'},
      });
      final list = res.objects('messages');
      if (list == null || list.isEmpty) return;
      final parsed = TDParse.message(list.first);
      if (parsed == null) return;
      pinnedMessage = parsed;
      notifyListeners();
    } catch (_) {}
  }

  void dismissPinned() {
    pinnedDismissed = true;
    notifyListeners();
  }

  // MARK: - History

  Future<void> _loadInitialHistory() async {
    await _fetchHistory(0, 0, 40);
    if (messages.length < 12 && messages.isNotEmpty) {
      await _fetchHistory(messages.first.id, 0, 40);
    }
  }

  Future<void> _fetchHistory(
    int fromMessageId,
    int offset,
    int limit, {
    bool isOlder = false,
  }) async {
    final anchor = messages.isNotEmpty ? messages.first.id : null;
    Map<String, dynamic> response;
    try {
      response = await _client.query({
        '@type': 'getChatHistory',
        'chat_id': chatId,
        'from_message_id': fromMessageId,
        'offset': offset,
        'limit': limit,
        'only_local': false,
      });
    } catch (_) {
      return;
    }

    final parsed =
        (response.objects('messages') ?? const <Map<String, dynamic>>[])
            .map(TDParse.message)
            .whereType<ChatMessage>()
            .toList();
    if (parsed.isEmpty) return;

    _merge(parsed);
    if (isOlder && anchor != null && messages.first.id != anchor) {
      _restoreTopId = anchor;
    }
    _resolveSendersIfNeeded(parsed);
    _resolveRepliesIfNeeded(parsed);
    _resolveForwardsIfNeeded(parsed);
  }

  // MARK: - Live updates

  void _subscribeToUpdates() {
    _sub ??= _client.subscribe().listen(_handle);
  }

  void _handle(Map<String, dynamic> update) {
    switch (update.type) {
      case 'updateNewMessage':
        final raw = update.obj('message');
        if (raw == null || raw.int64('chat_id') != chatId) return;
        final message = TDParse.message(raw);
        if (message == null) return;
        _merge([message]);
        _resolveSendersIfNeeded([message]);
        _resolveRepliesIfNeeded([message]);
        _resolveForwardsIfNeeded([message]);
        _client.send({
          '@type': 'viewMessages',
          'chat_id': chatId,
          'message_ids': [message.id],
          'force_read': true,
        });

      case 'updateMessageContent':
        if (update.int64('chat_id') != chatId) return;
        final messageId = update.int64('message_id');
        final content = update.obj('new_content');
        if (messageId == null || content == null) return;
        _replaceText(messageId, TDParse.messageText(content));

      case 'updateChatReadOutbox':
        if (update.int64('chat_id') != chatId) return;
        lastReadOutboxId =
            update.int64('last_read_outbox_message_id') ?? lastReadOutboxId;
        notifyListeners();

      case 'updateChatAction':
        if (update.int64('chat_id') != chatId) return;
        final sender = update.obj('sender_id');
        final sid = sender?.int64('user_id') ?? sender?.int64('chat_id');
        if (sid == null) return;
        if (update.obj('action')?.type == 'chatActionCancel') {
          _typing.remove(sid);
        } else {
          _typing[sid] = _senderCache[sid]?.name ?? '';
          if ((_senderCache[sid]?.name ?? '').isEmpty && isGroup && sid > 0) {
            _resolveSender(sid); // fills the name for the next render
          }
          _restartTypingTimer();
        }
        notifyListeners();

      case 'updateUserStatus':
        if (isGroup || update.int64('user_id') != peerUserId) return;
        peerOnline = update.obj('status')?.type == 'userStatusOnline';
        peerStatusText = _statusLabel(update.obj('status')?.type);
        notifyListeners();

      case 'updateMessageEdited':
        if (update.int64('chat_id') != chatId) return;
        final mid = update.int64('message_id');
        final i = messages.indexWhere((m) => m.id == mid);
        if (i >= 0) {
          messages[i].isEdited = true;
          notifyListeners();
        }

      case 'updateMessageInteractionInfo':
        if (update.int64('chat_id') != chatId) return;
        final mid = update.int64('message_id');
        final i = messages.indexWhere((m) => m.id == mid);
        if (i >= 0) {
          messages[i].reactions = TDParse.reactionsFrom({
            'interaction_info': update.obj('interaction_info'),
          });
          notifyListeners();
        }
    }
  }

  // MARK: - Reactions

  void addReaction(int messageId, String emoji) {
    _client.send({
      '@type': 'addMessageReaction',
      'chat_id': chatId,
      'message_id': messageId,
      'reaction_type': {'@type': 'reactionTypeEmoji', 'emoji': emoji},
      'is_big': false,
      'update_recent_reactions': true,
    });
  }

  /// Custom (premium) emoji reaction.
  void addCustomReaction(int messageId, int customEmojiId) {
    _client.send({
      '@type': 'addMessageReaction',
      'chat_id': chatId,
      'message_id': messageId,
      'reaction_type': {
        '@type': 'reactionTypeCustomEmoji',
        'custom_emoji_id': customEmojiId,
      },
      'is_big': false,
      'update_recent_reactions': true,
    });
  }

  void toggleReaction(ChatMessage m, MessageReaction r) {
    if (r.chosen) {
      _client.send({
        '@type': 'removeMessageReaction',
        'chat_id': chatId,
        'message_id': m.id,
        'reaction_type': r.type,
      });
    } else {
      _client.send({
        '@type': 'addMessageReaction',
        'chat_id': chatId,
        'message_id': m.id,
        'reaction_type': r.type,
        'is_big': false,
        'update_recent_reactions': true,
      });
    }
  }

  void _restartTypingTimer() {
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 6), () {
      if (_typing.isNotEmpty) {
        _typing.clear();
        notifyListeners();
      }
    });
  }

  String _statusLabel(String? type) {
    switch (type) {
      case 'userStatusOnline':
        return '在线';
      case 'userStatusRecently':
        return '最近在线';
      case 'userStatusLastWeek':
        return '一周内在线';
      case 'userStatusLastMonth':
        return '一个月内在线';
      default:
        return '离线';
    }
  }

  // MARK: - 引用 reply-quote resolution

  /// For each message that replies to another, resolve the quoted sender +
  /// preview — from the already-loaded list when possible, else via getMessage.
  void _resolveRepliesIfNeeded(List<ChatMessage> batch) {
    for (final m in batch) {
      final rid = m.replyToMessageId;
      if (rid == null || m.replyToPreview != null) continue;
      final idx = messages.indexWhere((x) => x.id == rid);
      if (idx >= 0) {
        _applyReply(m, messages[idx]);
      } else {
        _client
            .query({
              '@type': 'getMessage',
              'chat_id': chatId,
              'message_id': rid,
            })
            .then((raw) {
              final q = TDParse.message(raw);
              if (q != null) {
                _applyReply(m, q);
                notifyListeners();
              }
            })
            .catchError((_) {});
      }
    }
  }

  void _applyReply(ChatMessage m, ChatMessage quoted) {
    m.replyToPreview = _replyPreview(quoted);
    if (quoted.isOutgoing) {
      m.replyToSender = meName;
      return;
    }
    // Name the actual author of the quoted message — never the chat/group name.
    final name = quoted.senderName;
    if (name != null && name.isNotEmpty) {
      m.replyToSender = name;
      return;
    }
    final sid = quoted.senderId;
    final cached = sid == null ? null : _senderCache[sid];
    if (cached != null) {
      m.replyToSender = cached.name;
    } else if (sid != null) {
      m.replyToSender = ''; // resolve in the background, fill on next render
      _resolveQuotedSender(m, sid);
    } else {
      m.replyToSender = isGroup ? '' : peerTitle;
    }
  }

  /// Resolves a quoted message's author name (user or chat sender) and patches
  /// the reply in place. Reuses the sender cache populated for the transcript.
  Future<void> _resolveQuotedSender(ChatMessage m, int senderId) async {
    final existing = _senderCache[senderId];
    if (existing != null) {
      m.replyToSender = existing.name;
      notifyListeners();
      return;
    }
    String? name;
    try {
      if (senderId > 0) {
        final user = await _client.query({
          '@type': 'getUser',
          'user_id': senderId,
        });
        name = TDParse.userName(user);
      } else {
        final chat = await _client.query({
          '@type': 'getChat',
          'chat_id': senderId,
        });
        name = chat.str('title');
      }
    } catch (_) {}
    if (name != null && name.isNotEmpty) {
      m.replyToSender = name;
      notifyListeners();
    }
  }

  String _replyPreview(ChatMessage q) {
    if (q.document != null) return '[文件]${q.document!.fileName}';
    if (q.voice != null) return '[语音]';
    if (q.location != null) return '[位置]';
    if (q.animatedSticker != null) return '[动画表情]';
    if (q.image != null) return q.text.isEmpty ? '[图片]' : q.text;
    return q.text;
  }

  // MARK: - Merge / mutate

  void _merge(List<ChatMessage> incoming) {
    if (incoming.isEmpty) return;
    final byId = {for (final m in messages) m.id: m};
    for (final message in incoming) {
      final existing = byId[message.id];
      if (existing != null) {
        message.senderName ??= existing.senderName;
        message.senderPhoto ??= existing.senderPhoto;
        message.senderRole ??= existing.senderRole;
        message.senderTitle ??= existing.senderTitle;
      }
      byId[message.id] = message;
    }
    messages = byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    notifyListeners();
  }

  void _replaceText(int messageId, String text) {
    final index = messages.indexWhere((m) => m.id == messageId);
    if (index < 0) return;
    messages[index].text = text;
    notifyListeners();
  }

  void _patchSender(_SenderInfo info, int senderId) {
    var changed = false;
    for (final m in messages) {
      if (m.senderId != senderId || m.isOutgoing) continue;
      if (m.senderName == info.name &&
          m.senderRole == info.role &&
          m.senderTitle == info.title) {
        continue;
      }
      m.senderName = info.name;
      m.senderPhoto = info.photo;
      m.senderRole = info.role;
      m.senderTitle = info.title;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  // MARK: - Sender resolution (groups/channels only)

  void _resolveSendersIfNeeded(List<ChatMessage> batch) {
    if (!isGroup) return;
    final pending = <int>{};
    for (final message in batch) {
      if (message.isOutgoing || message.isService) continue;
      final senderId = message.senderId;
      if (senderId == null) continue;
      final cached = _senderCache[senderId];
      if (cached != null) {
        _patchSender(cached, senderId);
      } else if (!_resolvingSenders.contains(senderId)) {
        pending.add(senderId);
      }
    }
    for (final senderId in pending) {
      _resolvingSenders.add(senderId);
      _resolveSender(senderId);
    }
  }

  /// Fills `forwardOrigin` for forwarded messages whose origin is a user or
  /// chat we can name (hidden-user names already arrive inline).
  void _resolveForwardsIfNeeded(List<ChatMessage> batch) {
    for (final m in batch) {
      if (m.forwardOrigin != null && m.forwardOrigin!.isNotEmpty) continue;
      final uid = m.forwardFromUserId;
      final cid = m.forwardFromChatId;
      if (uid != null) {
        final cached = _senderCache[uid];
        if (cached != null) {
          m.forwardOrigin = cached.name;
        } else {
          _resolveForwardName(m, userId: uid);
        }
      } else if (cid != null) {
        _resolveForwardName(m, chatId: cid);
      }
    }
  }

  Future<void> _resolveForwardName(
    ChatMessage m, {
    int? userId,
    int? chatId,
  }) async {
    try {
      if (userId != null) {
        final user = await _client.query({
          '@type': 'getUser',
          'user_id': userId,
        });
        m.forwardOrigin = TDParse.userName(user);
      } else if (chatId != null) {
        final chat = await _client.query({
          '@type': 'getChat',
          'chat_id': chatId,
        });
        m.forwardOrigin = chat.str('title');
      }
      if (m.forwardOrigin != null && m.forwardOrigin!.isNotEmpty) {
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _resolveSender(int senderId) async {
    _SenderInfo info;
    if (senderId > 0) {
      String name;
      TdFileRef? photo;
      try {
        final user = await _client.query({
          '@type': 'getUser',
          'user_id': senderId,
        });
        name = TDParse.userName(user);
        photo = TDParse.smallPhoto(user.obj('profile_photo'));
      } catch (_) {
        name = '用户 $senderId';
        photo = null;
      }
      final role = await _resolveRole(senderId);
      info = _SenderInfo(name, photo, role.$1, role.$2);
    } else {
      try {
        final chat = await _client.query({
          '@type': 'getChat',
          'chat_id': senderId,
        });
        info = _SenderInfo(
          chat.str('title') ?? '群成员',
          TDParse.smallPhoto(chat.obj('photo')),
          MemberRole.member,
          null,
        );
      } catch (_) {
        info = _SenderInfo('群成员', null, MemberRole.member, null);
      }
    }
    _senderCache[senderId] = info;
    _resolvingSenders.remove(senderId);
    _patchSender(info, senderId);
  }

  Future<(MemberRole, String?)> _resolveRole(int userId) async {
    try {
      final member = await _client.query({
        '@type': 'getChatMember',
        'chat_id': chatId,
        'member_id': {'@type': 'messageSenderUser', 'user_id': userId},
      });
      final status = member.obj('status');
      final title = status?.str('custom_title');
      final cleanTitle = (title?.isNotEmpty ?? false) ? title : null;
      switch (status?.type) {
        case 'chatMemberStatusCreator':
          return (MemberRole.owner, cleanTitle);
        case 'chatMemberStatusAdministrator':
          return (MemberRole.admin, cleanTitle);
        default:
          return (MemberRole.member, null);
      }
    } catch (_) {
      return (MemberRole.member, null);
    }
  }
}
