//
//  chat_view_model.dart
//
//  Conversation view model. Opens a chat, loads history, and keeps the message
//  list live by folding TDLib updates. For groups/channels it resolves each
//  incoming message's sender name + photo + role through a small cache so
//  bubbles can show "who said what". Port of the Swift `ChatViewModel`.
//

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/notifications/scope_notification_settings.dart';

import '../l10n/telegram_language_controller.dart';
import '../notifications/notification_settings_payload.dart';
import '../settings/blocked_user_service.dart';
import '../settings/keyword_blocker.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import 'forward_options.dart';
import 'gif_item.dart';
import 'outgoing_attachment.dart';
import 'rich_message_source.dart';
import 'sticker_item.dart';

class _SenderInfo {
  _SenderInfo(
    this.name,
    this.photo,
    this.role,
    this.title, {
    this.isPremium = false,
    this.accentColorId = -1,
    this.emojiStatusId = 0,
  });
  final String name;
  final TdFileRef? photo;
  final MemberRole role;
  final String? title;
  final bool isPremium;
  final int accentColorId;
  final int emojiStatusId;
}

class _MessageSendResult {
  const _MessageSendResult.success() : error = null;
  const _MessageSendResult.failure(this.error);

  final TdError? error;
}

class _ChatActionInfo {
  const _ChatActionInfo(this.name, this.actionType);

  final String name;
  final String actionType;
}

class MessageSenderOption {
  const MessageSenderOption({
    required this.sender,
    required this.id,
    required this.title,
    this.photo,
    this.needsPremium = false,
  });

  final Map<String, dynamic> sender;
  final int id;
  final String title;
  final TdFileRef? photo;
  final bool needsPremium;

  bool sameSender(Map<String, dynamic>? other) {
    if (other == null || other.type != sender.type) return false;
    return switch (sender.type) {
      'messageSenderUser' => other.int64('user_id') == id,
      'messageSenderChat' => other.int64('chat_id') == id,
      _ => false,
    };
  }
}

class MessageReactionUser {
  const MessageReactionUser({
    required this.senderId,
    required this.title,
    this.photo,
    this.date = 0,
  });

  final int senderId;
  final String title;
  final TdFileRef? photo;
  final int date;
}

class BotCommandOption {
  const BotCommandOption({required this.command, required this.description});

  final String command;
  final String description;
}

class BotMenuInfo {
  const BotMenuInfo({required this.type, this.text = '', this.url = ''});

  final String type;
  final String text;
  final String url;

  bool get isWebApp => type == 'botMenuButton' && url.isNotEmpty;
  bool get opensCommands =>
      type == 'botMenuButtonCommands' || type == 'botMenuButtonDefault';
}

class ForumTopicOption {
  const ForumTopicOption({
    required this.id,
    required this.name,
    this.iconCustomEmojiId = 0,
    this.iconColor = 0,
  });

  final int id;
  final String name;
  final int iconCustomEmojiId;
  final int iconColor;
}

class _DraftMention {
  const _DraftMention({required this.text, required this.userId});

  final String text;
  final int userId;
}

class ChatViewModel extends ChangeNotifier {
  ChatViewModel({
    required this.chatId,
    required String title,
    required this.markReadOnOpen,
    this.initialMessageId,
    ChatMessage? seedMessage,
  }) : peerTitle = title {
    if (seedMessage != null) {
      _allMessages = [seedMessage];
      messages = [seedMessage];
    }
  }

  final int chatId;
  final int? initialMessageId;
  final bool markReadOnOpen;

  List<ChatMessage> messages = [];
  List<ChatMessage> _allMessages = [];
  String peerTitle;
  TdFileRef? peerPhoto;
  bool isGroup = false;
  int memberCount = 0;
  int? peerUserId; // private chat → call target
  int? peerSupergroupId;
  String meName = AppStrings.t(AppStringKeys.chatMeLabel);
  int? meId;
  TdFileRef? mePhoto;
  String draft = '';
  String _draftFormattedText = '';
  List<Map<String, dynamic>> _draftFormattedEntities = const [];
  final List<_DraftMention> _draftMentions = [];
  ChatMessage? replyTo;
  List<MessageSenderOption> availableMessageSenders = const [];
  MessageSenderOption? selectedMessageSender;

  // Live header state.
  bool peerOnline = false;
  String peerStatusText = '';
  int lastReadOutboxId = 0; // outgoing messages with id <= this are read
  int lastReadInboxId = 0; // incoming messages with id <= this are read
  int unreadCount = 0; // unread incoming messages on entry (for the divider)
  bool isMarkedUnread = false; // manual unread marker on the chat row
  bool initialLoaded = false; // first history page (+ unread boundary) is in
  bool anchoredHistory = false; // transcript is centered on an arbitrary target

  // 群公告 / pinned message shown in a bar below the header.
  ChatMessage? pinnedMessage;
  List<ChatMessage> pinnedMessages = const [];
  int pinnedMessageIndex = 0;
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
  bool canDeleteMessagesBySender = false;
  String sendDisabledReason = ''; // shown in the disabled composer bar
  bool isTelegramTosRestricted = false;
  String telegramTosRestrictionText = '';
  bool _chatCanSend = true; // chat-wide default can_send_basic_messages
  bool peerIsBot = false;
  bool botStartSent = false;
  BotMenuInfo? botMenu;
  List<BotCommandOption> botCommands = const [];
  bool isForum = false;
  bool forumTopicsLoading = false;
  List<ForumTopicOption> forumTopics = const [];
  int messageAutoDeleteTime = 0;
  int paidMessageStarCount = 0;

  final TdClient _client = TdClient.shared;
  StreamSubscription? _sub;
  bool _isLoadingOlder = false;
  bool _hasOlderHistory = true;
  int? _restoreTopId;
  int? _pendingScrollToId;
  int? _lastForcedReadMessageId;
  bool _markReadInFlight = false;
  final Set<int> _blockedReadIds = {};
  final Set<int> _blockedSenderIds = {};
  final Set<int> _discardedPendingMessageIds = {};
  final Map<int, Completer<void>> _messageSendWaiters = {};
  final Map<int, _MessageSendResult> _recentMessageSendResults = {};

  // Transient chat actions: sender ids currently acting, auto-cleared shortly.
  final Map<int, _ChatActionInfo> _chatActions = {};
  Timer? _typingTimer;
  Timer? _draftSaveTimer;
  Timer? _senderPatchTimer;
  String? _lastSavedDraftText;

  /// Header title: profile shows the member count in parentheses after a group name.
  String get headerTitle =>
      (isGroup && memberCount > 0) ? '$peerTitle($memberCount)' : peerTitle;

  /// Subtitle under the title: online/last-seen plus transient chat actions.
  /// Group member count lives in the title, not here.
  String get subtitle {
    final base = isGroup
        ? ''
        : (peerOnline
              ? AppStrings.t(AppStringKeys.chatOnline)
              : peerStatusText);
    final action = _chatActionSubtitle;
    if (base.isEmpty) return action;
    if (action.isEmpty) return base;
    return '$base · $action';
  }

  bool get hasActiveChatAction => _chatActions.isNotEmpty;

  bool isRead(ChatMessage m) => m.isOutgoing && m.id <= lastReadOutboxId;
  bool get canChooseMessageSender => availableMessageSenders.length > 1;
  bool get canLoadOlder =>
      !_isLoadingOlder && _allMessages.isNotEmpty && _hasOlderHistory;
  bool get requiresPaidMessage => paidMessageStarCount > 0;
  String get inputPlaceholder => messageAutoDeleteTime > 0
      ? AppStrings.t(AppStringKeys.chatAutoDeleteCountdown, {
          'value1': TDParse.formatDuration(messageAutoDeleteTime),
        })
      : AppStrings.t(AppStringKeys.chatMessageInputPlaceholder);

  final Map<int, _SenderInfo> _senderCache = {};
  final Set<int> _resolvingSenders = {};
  bool _isDisposed = false;

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  /// After prepending older history, the view scrolls this id back to the top.
  int? consumeRestoreTop() {
    final id = _restoreTopId;
    _restoreTopId = null;
    return id;
  }

  int? consumePendingScrollToId() {
    final id = _pendingScrollToId;
    _pendingScrollToId = null;
    return id;
  }

  Map<String, dynamic> _withPaidMessageOptions(Map<String, dynamic> request) {
    final count = paidMessageStarCount;
    if (count <= 0) return request;
    final existing = request.obj('options') ?? const <String, dynamic>{};
    request['options'] = {
      ...existing,
      '@type': 'messageSendOptions',
      'paid_message_star_count': count,
    };
    return request;
  }

  void _setPaidMessageStarCount(int count, {bool notify = true}) {
    final next = count < 0 ? 0 : count;
    if (paidMessageStarCount == next) return;
    paidMessageStarCount = next;
    if (notify) notifyListeners();
  }

  // MARK: - Lifecycle

  void onAppear() {
    _client.send({'@type': 'openChat', 'chat_id': chatId});
    _subscribeToUpdates();
    KeywordBlocker.shared.removeListener(_applyKeywordFilter);
    KeywordBlocker.shared.addListener(_applyKeywordFilter);
    () async {
      unawaited(_loadMe());
      await _loadChatHeader();
      final target = initialMessageId;
      if (target != null) {
        await loadAroundMessage(target);
      } else {
        await _loadInitialHistory(openAtLatest: markReadOnOpen);
      }
      initialLoaded = true;
      notifyListeners();
      unawaited(_loadAvailableMessageSenders());
    }();
  }

  Future<void> _loadMe() async {
    try {
      final me = await _client.query({'@type': 'getMe'});
      meId = me.int64('id');
      final name = TDParse.userName(me);
      if (name.isNotEmpty) meName = name;
      mePhoto = TDParse.smallPhoto(me.obj('profile_photo'));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadAvailableMessageSenders() async {
    try {
      final res = await _client.query({
        '@type': 'getChatAvailableMessageSenders',
        'chat_id': chatId,
      });
      final raw = res.objects('senders') ?? const <Map<String, dynamic>>[];
      final loaded = <MessageSenderOption>[];
      for (final item in raw) {
        final sender = item.obj('sender');
        if (sender == null) continue;
        final option = await _messageSenderOption(
          sender,
          item.boolean('needs_premium') ?? false,
        );
        if (option != null) loaded.add(option);
      }
      availableMessageSenders = loaded;
      if (selectedMessageSender == null && loaded.isNotEmpty) {
        selectedMessageSender = loaded.first;
      } else if (selectedMessageSender != null) {
        MessageSenderOption? selected;
        for (final option in loaded) {
          if (option.sameSender(selectedMessageSender!.sender)) {
            selected = option;
            break;
          }
        }
        selectedMessageSender =
            selected ?? (loaded.isNotEmpty ? loaded.first : null);
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<MessageSenderOption?> _messageSenderOption(
    Map<String, dynamic> sender,
    bool needsPremium,
  ) async {
    switch (sender.type) {
      case 'messageSenderUser':
        final userId = sender.int64('user_id');
        if (userId == null) return null;
        if (peerUserId == userId || userId > 0) {
          try {
            final user = await _client.query({
              '@type': 'getUser',
              'user_id': userId,
            });
            final name = TDParse.userName(user);
            return MessageSenderOption(
              sender: sender,
              id: userId,
              title: name.isEmpty ? meName : name,
              photo: TDParse.smallPhoto(user.obj('profile_photo')),
              needsPremium: needsPremium,
            );
          } catch (_) {}
        }
        return MessageSenderOption(
          sender: sender,
          id: userId,
          title: meName,
          photo: mePhoto,
          needsPremium: needsPremium,
        );
      case 'messageSenderChat':
        final senderChatId = sender.int64('chat_id');
        if (senderChatId == null) return null;
        try {
          final chat = await _client.query({
            '@type': 'getChat',
            'chat_id': senderChatId,
          });
          return MessageSenderOption(
            sender: sender,
            id: senderChatId,
            title: chat.str('title') ?? AppStrings.t(AppStringKeys.tabChannels),
            photo: TDParse.smallPhoto(chat.obj('photo')),
            needsPremium: needsPremium,
          );
        } catch (_) {
          return MessageSenderOption(
            sender: sender,
            id: senderChatId,
            title: AppStrings.t(AppStringKeys.tabChannels),
            needsPremium: needsPremium,
          );
        }
    }
    return null;
  }

  Future<void> selectMessageSender(MessageSenderOption option) async {
    final previous = selectedMessageSender;
    selectedMessageSender = option;
    notifyListeners();
    try {
      await _client.query({
        '@type': 'setChatMessageSender',
        'chat_id': chatId,
        'message_sender_id': option.sender,
      });
    } catch (_) {
      selectedMessageSender = previous;
      notifyListeners();
    }
  }

  void onDisappear() {
    _flushPendingDraftSave();
    _sub?.cancel();
    _sub = null;
    KeywordBlocker.shared.removeListener(_applyKeywordFilter);
    _client.send({'@type': 'closeChat', 'chat_id': chatId});
  }

  @override
  void dispose() {
    _isDisposed = true;
    KeywordBlocker.shared.removeListener(_applyKeywordFilter);
    _sub?.cancel();
    _typingTimer?.cancel();
    _draftSaveTimer?.cancel();
    _senderPatchTimer?.cancel();
    for (final waiter in _messageSendWaiters.values) {
      if (!waiter.isCompleted) {
        waiter.completeError(StateError('Chat view model was disposed'));
      }
    }
    _messageSendWaiters.clear();
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

  void setDraft(
    String value, {
    String? formattedText,
    List<Map<String, dynamic>> entities = const [],
  }) {
    draft = value;
    _draftFormattedText = formattedText ?? value;
    _draftFormattedEntities = entities;
    _draftMentions.removeWhere((m) => !draft.contains(m.text));
    _scheduleDraftSave();
  }

  void _scheduleDraftSave() {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 750), () {
      _draftSaveTimer = null;
      _saveDraftNow();
    });
  }

  void _flushPendingDraftSave() {
    final timer = _draftSaveTimer;
    if (timer == null) return;
    timer.cancel();
    _draftSaveTimer = null;
    _saveDraftNow();
  }

  void _clearDraft({bool syncRemote = true}) {
    draft = '';
    _draftFormattedText = '';
    _draftFormattedEntities = const [];
    _draftMentions.clear();
    _draftSaveTimer?.cancel();
    _draftSaveTimer = null;
    if (syncRemote) _saveDraftNow();
  }

  void _saveDraftNow() {
    final text = _draftFormattedText;
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      if (_lastSavedDraftText == '') return;
      _lastSavedDraftText = '';
      _client.send({
        '@type': 'setChatDraftMessage',
        'chat_id': chatId,
        'message_thread_id': 0,
        'draft_message': null,
      });
      return;
    }

    final allEntities = [
      ..._draftFormattedEntities,
      ..._mentionEntitiesFor(text, _draftFormattedEntities),
    ];
    if (_lastSavedDraftText == text && allEntities.isEmpty) return;
    _lastSavedDraftText = text;
    _client.send({
      '@type': 'setChatDraftMessage',
      'chat_id': chatId,
      'message_thread_id': 0,
      'draft_message': {
        '@type': 'draftMessage',
        'date': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'input_message_text': {
          '@type': 'inputMessageText',
          'text': {
            '@type': 'formattedText',
            'text': text,
            if (allEntities.isNotEmpty) 'entities': allEntities,
          },
        },
      },
    });
  }

  void _applyRemoteDraft(
    Map<String, dynamic>? remoteDraft, {
    bool force = false,
    bool notify = true,
  }) {
    if (!force && (_draftSaveTimer?.isActive ?? false)) return;
    final text = TDParse.draftText(remoteDraft);
    if (!force && text == _lastSavedDraftText) return;
    draft = text;
    _draftFormattedText = text;
    _draftFormattedEntities = const [];
    _draftMentions.clear();
    _lastSavedDraftText = text;
    if (notify) notifyListeners();
  }

  /// Appends an "@name " mention to the composer (long-press an avatar), backed
  /// by a user-id entity so Telegram doesn't resolve the text as a public user.
  void insertMention(ChatMessage message) {
    final name = message.senderName?.trim() ?? '';
    final userId = message.senderId;
    if (name.isEmpty || userId == null || userId <= 0) return;
    _insertMention(name, userId);
  }

  void _insertMention(String name, int userId) {
    final mention = '@$name';
    if (_draftMentions.any((m) => m.text == mention && m.userId == userId)) {
      return;
    }
    final sep = (draft.isEmpty || draft.endsWith(' ')) ? '' : ' ';
    draft = '$draft$sep$mention ';
    _draftFormattedText = draft;
    _draftFormattedEntities = const [];
    _draftMentions.add(_DraftMention(text: mention, userId: userId));
    _scheduleDraftSave();
    notifyListeners();
  }

  void send() {
    final trimmed = draft.trim();
    if (trimmed.isEmpty) return;
    _clearDraft();

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
    _client.send(_withPaidMessageOptions(request));
    notifyListeners();
  }

  void sendBotStart() {
    if (!peerIsBot) return;
    _clearDraft();
    botStartSent = true;
    _sendText('/start');
    notifyListeners();
  }

  void _sendText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _client.send(
      _withPaidMessageOptions({
        '@type': 'sendMessage',
        'chat_id': chatId,
        'input_message_content': {
          '@type': 'inputMessageText',
          'text': {'@type': 'formattedText', 'text': trimmed},
        },
      }),
    );
  }

  /// Sends text that may contain inline custom emoji — [entities] is the list of
  /// TDLib textEntity objects (e.g. textEntityTypeCustomEmoji) over [text]
  /// (offsets in UTF-16 of [text], which already has the fallback chars).
  void sendFormatted(String text, List<Map<String, dynamic>> entities) {
    if (text.trim().isEmpty) return;
    if (entities.isEmpty && _sendDiceIfNeeded(text)) return;
    final allEntities = [...entities, ..._mentionEntitiesFor(text, entities)];
    _clearDraft();
    final request = <String, dynamic>{
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessageText',
        'text': {
          '@type': 'formattedText',
          'text': text,
          if (allEntities.isNotEmpty) 'entities': allEntities,
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
    _client.send(_withPaidMessageOptions(request));
    notifyListeners();
  }

  Future<void> sendRichMessageHtml(
    String html, {
    List<RichMessageSendFile> files = const [],
  }) async {
    if (html.trim().isEmpty) return;
    _clearDraft();
    final request = <String, dynamic>{
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessageRichMessage',
        'message': {
          '@type': 'inputRichMessage',
          'source': {'@type': 'richMessageSourceHtml', 'text': html},
          'is_rtl': false,
          'detect_automatic_blocks': true,
          if (files.isNotEmpty)
            'files': files.map(_richMessageFilePayload).toList(),
        },
        'clear_draft': true,
      },
    };
    if (replyTo != null) {
      request['reply_to'] = {
        '@type': 'inputMessageReplyToMessage',
        'message_id': replyTo!.id,
      };
    }
    replyTo = null;
    final pendingMessage = await _client.query(
      _withPaidMessageOptions(request),
    );
    final pendingMessageId = pendingMessage.int64('id');
    if (pendingMessageId != null &&
        pendingMessage.obj('sending_state') != null) {
      await _waitForMessageSend(pendingMessageId);
    }
    notifyListeners();
  }

  Future<bool> currentUserIsPremium() async {
    final user = await _client.query({'@type': 'getMe'});
    return user.boolean('is_premium') ?? false;
  }

  Future<void> _waitForMessageSend(int pendingMessageId) {
    final recent = _recentMessageSendResults.remove(pendingMessageId);
    if (recent != null) {
      final error = recent.error;
      return error == null ? Future.value() : Future.error(error);
    }
    final waiter = Completer<void>();
    _messageSendWaiters[pendingMessageId] = waiter;
    return waiter.future
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            _discardPendingMessage(pendingMessageId);
            throw TimeoutException('Rich message send timed out');
          },
        )
        .whenComplete(() {
          if (identical(_messageSendWaiters[pendingMessageId], waiter)) {
            _messageSendWaiters.remove(pendingMessageId);
          }
        });
  }

  void _discardPendingMessage(int pendingMessageId) {
    _discardedPendingMessageIds.add(pendingMessageId);
    _removeMessages([pendingMessageId]);
    unawaited(_deleteDiscardedPendingMessage(pendingMessageId));
  }

  Future<void> _deleteDiscardedPendingMessage(int pendingMessageId) async {
    try {
      await _client.query({
        '@type': 'deleteMessages',
        'chat_id': chatId,
        'message_ids': [pendingMessageId],
        'revoke': false,
      });
    } catch (error) {
      debugPrint('Failed to delete pending message $pendingMessageId: $error');
    }
  }

  void _recordMessageSendResult(
    int pendingMessageId,
    _MessageSendResult result,
  ) {
    final waiter = _messageSendWaiters.remove(pendingMessageId);
    if (waiter != null) {
      final error = result.error;
      if (error == null) {
        waiter.complete();
      } else {
        waiter.completeError(error);
      }
      return;
    }
    _recentMessageSendResults[pendingMessageId] = result;
    while (_recentMessageSendResults.length > 32) {
      _recentMessageSendResults.remove(_recentMessageSendResults.keys.first);
    }
  }

  Map<String, dynamic> _richMessageFilePayload(RichMessageSendFile file) {
    final attachment = file.attachment;
    final inputFile = {'@type': 'inputFileLocal', 'path': attachment.path};
    final segments = Uri.file(attachment.path).pathSegments;
    final fileName = segments.isEmpty ? attachment.path : segments.last;
    return switch (attachment.kind) {
      OutgoingAttachmentKind.photo => {
        '@type': 'inputRichMessageFilePhoto',
        'id': file.id,
        'photo': {
          '@type': 'inputPhoto',
          'photo': inputFile,
          'added_sticker_file_ids': <int>[],
          'width': 0,
          'height': 0,
        },
      },
      OutgoingAttachmentKind.video => {
        '@type': 'inputRichMessageFileVideo',
        'id': file.id,
        'video': {
          '@type': 'inputVideo',
          'video': inputFile,
          'start_timestamp': 0,
          'added_sticker_file_ids': <int>[],
          'duration': 0,
          'width': 0,
          'height': 0,
          'supports_streaming': true,
        },
      },
      OutgoingAttachmentKind.animation => {
        '@type': 'inputRichMessageFileAnimation',
        'id': file.id,
        'animation': {
          '@type': 'inputAnimation',
          'animation': inputFile,
          'added_sticker_file_ids': <int>[],
          'duration': 0,
          'width': 0,
          'height': 0,
        },
      },
      OutgoingAttachmentKind.audio => {
        '@type': 'inputRichMessageFileAudio',
        'id': file.id,
        'audio': {
          '@type': 'inputAudio',
          'audio': inputFile,
          'duration': 0,
          'title': fileName,
          'performer': '',
        },
      },
      OutgoingAttachmentKind.document => {
        '@type': 'inputRichMessageFileDocument',
        'id': file.id,
        'document': {
          '@type': 'inputDocument',
          'document': inputFile,
          'disable_content_type_detection': false,
        },
      },
    };
  }

  static const _diceEmojis = {'🎲', '🎯', '🏀', '⚽', '🎳', '🎰'};

  bool _sendDiceIfNeeded(String text) {
    final emoji = text.trim();
    if (!_diceEmojis.contains(emoji)) return false;
    _clearDraft();
    final request = <String, dynamic>{
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {'@type': 'inputMessageDice', 'emoji': emoji},
    };
    if (replyTo != null) {
      request['reply_to'] = {
        '@type': 'inputMessageReplyToMessage',
        'message_id': replyTo!.id,
      };
    }
    replyTo = null;
    _client.send(_withPaidMessageOptions(request));
    notifyListeners();
    return true;
  }

  /// 引用: set (or clear) the reply target. In a group, replying to someone also
  /// @-mentions them in the draft (messenger behavior).
  void setReply(ChatMessage? message) {
    replyTo = message;
    if (message != null &&
        isGroup &&
        !message.isOutgoing &&
        (message.senderName?.isNotEmpty ?? false)) {
      final userId = message.senderId;
      if (userId != null && userId > 0) {
        _insertMention(message.senderName!, userId);
      }
    }
    notifyListeners();
  }

  List<Map<String, dynamic>> _mentionEntitiesFor(
    String text,
    List<Map<String, dynamic>> existing,
  ) {
    final out = <Map<String, dynamic>>[];
    final occupied = existing.map((e) {
      final offset = e.integer('offset') ?? 0;
      final length = e.integer('length') ?? 0;
      return (offset, offset + length);
    }).toList();
    for (final mention in _draftMentions) {
      var start = 0;
      while (start < text.length) {
        final offset = text.indexOf(mention.text, start);
        if (offset < 0) break;
        final end = offset + mention.text.length;
        final overlaps = occupied.any((r) => offset < r.$2 && end > r.$1);
        if (!overlaps) {
          out.add({
            '@type': 'textEntity',
            'offset': offset,
            'length': mention.text.length,
            'type': {
              '@type': 'textEntityTypeMentionName',
              'user_id': mention.userId,
            },
          });
          occupied.add((offset, end));
          break;
        }
        start = end;
      }
    }
    return out;
  }

  Future<void> sendAttachments(
    List<OutgoingAttachment> attachments, {
    String caption = '',
    List<Map<String, dynamic>> captionEntities = const [],
  }) async {
    if (attachments.isEmpty) return;
    final allEntities = [
      ...captionEntities,
      ..._mentionEntitiesFor(caption, captionEntities),
    ];
    final reply = replyTo;
    final requests = buildAttachmentSendRequests(
      chatId: chatId,
      attachments: attachments,
      caption: caption,
      captionEntities: allEntities,
      replyTo: reply == null
          ? null
          : {'@type': 'inputMessageReplyToMessage', 'message_id': reply.id},
    );
    replyTo = null;
    _clearDraft();
    notifyListeners();
    for (final request in requests) {
      await _client.query(_withPaidMessageOptions(request));
    }
  }

  void sendPhoto(
    String path, {
    String caption = '',
    List<Map<String, dynamic>> captionEntities = const [],
  }) {
    final captionText = captionEntities.isEmpty ? caption.trim() : caption;
    _client.send(
      _withPaidMessageOptions({
        '@type': 'sendMessage',
        'chat_id': chatId,
        'input_message_content': {
          '@type': 'inputMessagePhoto',
          'photo': {
            '@type': 'inputPhoto',
            'photo': {'@type': 'inputFileLocal', 'path': path},
          },
          if (captionText.trim().isNotEmpty)
            'caption': {
              '@type': 'formattedText',
              'text': captionText,
              if (captionEntities.isNotEmpty) 'entities': captionEntities,
            },
        },
      }),
    );
  }

  void sendVideo(
    String path, {
    String caption = '',
    List<Map<String, dynamic>> captionEntities = const [],
  }) {
    final captionText = captionEntities.isEmpty ? caption.trim() : caption;
    _client.send(
      _withPaidMessageOptions({
        '@type': 'sendMessage',
        'chat_id': chatId,
        'input_message_content': {
          '@type': 'inputMessageVideo',
          'video': {
            '@type': 'inputVideo',
            'video': {'@type': 'inputFileLocal', 'path': path},
            'supports_streaming': true,
          },
          if (captionText.trim().isNotEmpty)
            'caption': {
              '@type': 'formattedText',
              'text': captionText,
              if (captionEntities.isNotEmpty) 'entities': captionEntities,
            },
        },
      }),
    );
  }

  void sendAnimation(
    String path, {
    String caption = '',
    List<Map<String, dynamic>> captionEntities = const [],
  }) {
    final captionText = captionEntities.isEmpty ? caption.trim() : caption;
    _client.send(
      _withPaidMessageOptions({
        '@type': 'sendMessage',
        'chat_id': chatId,
        'input_message_content': {
          '@type': 'inputMessageAnimation',
          'animation': {'@type': 'inputFileLocal', 'path': path},
          'duration': 0,
          'width': 0,
          'height': 0,
          if (captionText.trim().isNotEmpty)
            'caption': {
              '@type': 'formattedText',
              'text': captionText,
              if (captionEntities.isNotEmpty) 'entities': captionEntities,
            },
        },
      }),
    );
  }

  Future<bool> sendGif(GifItem gif) async {
    try {
      await _client.query(
        _withPaidMessageOptions({
          '@type': 'sendMessage',
          'chat_id': chatId,
          'input_message_content': gifMessageContent(gif),
        }),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  void sendSticker(StickerItem sticker) {
    final input = sticker.remoteId != null
        ? {'@type': 'inputFileRemote', 'id': sticker.remoteId}
        : {'@type': 'inputFileId', 'id': sticker.id};
    _client.send(
      _withPaidMessageOptions({
        '@type': 'sendMessage',
        'chat_id': chatId,
        'input_message_content': {
          '@type': 'inputMessageSticker',
          'sticker': input,
          'width': sticker.width,
          'height': sticker.height,
          'emoji': sticker.emoji,
        },
      }),
    );
  }

  void sendDocument(String path, {String caption = ''}) {
    _client.send(
      _withPaidMessageOptions({
        '@type': 'sendMessage',
        'chat_id': chatId,
        'input_message_content': {
          '@type': 'inputMessageDocument',
          'document': {
            '@type': 'inputDocument',
            'document': {'@type': 'inputFileLocal', 'path': path},
          },
          if (caption.trim().isNotEmpty)
            'caption': {'@type': 'formattedText', 'text': caption.trim()},
        },
      }),
    );
  }

  void sendLocation(double latitude, double longitude) {
    _client.send(
      _withPaidMessageOptions({
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
      }),
    );
  }

  void sendVoice(String path, int duration) {
    _client.send(
      _withPaidMessageOptions({
        '@type': 'sendMessage',
        'chat_id': chatId,
        'input_message_content': {
          '@type': 'inputMessageVoiceNote',
          'voice_note': {'@type': 'inputFileLocal', 'path': path},
          'duration': duration,
        },
      }),
    );
  }

  /// 音频: send a picked audio file as a music message (TDLib computes metadata).
  void sendAudio(String path) {
    _client.send(
      _withPaidMessageOptions({
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
      }),
    );
  }

  /// 音频搜索: send a clean copy of an existing Telegram audio message.
  Future<void> sendAudioFromMessage(
    int sourceChatId,
    ChatMessage message,
  ) async {
    final music = message.music;
    final fileId = music?.file?.id;
    if (music != null && fileId != null && fileId > 0) {
      try {
        await _client.query(
          _withPaidMessageOptions({
            '@type': 'sendMessage',
            'chat_id': chatId,
            'input_message_content': {
              '@type': 'inputMessageAudio',
              'audio': {
                '@type': 'inputAudio',
                'audio': {'@type': 'inputFileId', 'id': fileId},
                'duration': music.duration,
                'title': music.title,
                'performer': music.performer ?? '',
              },
            },
          }),
        );
        return;
      } catch (_) {}
    }
    await _client.query(
      _withPaidMessageOptions({
        '@type': 'forwardMessages',
        'chat_id': chatId,
        'from_chat_id': sourceChatId,
        'message_ids': [message.id],
        'options': {'@type': 'messageSendOptions'},
        'send_copy': true,
        'remove_caption': false,
      }),
    );
  }

  /// 清单: send a checklist (to-do list). Creating checklists needs Premium.
  void sendChecklist(String title, List<String> tasks) {
    final items = tasks
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (title.trim().isEmpty || items.isEmpty) return;
    _client.send(
      _withPaidMessageOptions({
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
      }),
    );
  }

  void sendPoll(String question, List<String> options) {
    final q = question.trim();
    final opts = options
        .map((o) => o.trim())
        .where((o) => o.isNotEmpty)
        .toList();
    if (q.isEmpty || opts.length < 2) return;
    _client.send(
      _withPaidMessageOptions({
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
      }),
    );
  }

  /// Re-sends the same content (the "+1" quick repeat) — only plain text and
  /// photos; the badge that calls this is gated to those kinds too.
  void repeatMessage(ChatMessage message) {
    // Photo: send a clean copy (forwardMessages send_copy drops the "转发"
    // header and works regardless of the original file's upload state).
    if (message.isPhoto && message.image != null) {
      _client.send(
        _withPaidMessageOptions({
          '@type': 'forwardMessages',
          'chat_id': chatId,
          'from_chat_id': chatId,
          'message_ids': [message.id],
          'send_copy': true,
        }),
      );
      return;
    }
    if (!message.isPlainText) return;
    final text = message.text.trim();
    if (text.isEmpty) return;
    _client.send(
      _withPaidMessageOptions({
        '@type': 'sendMessage',
        'chat_id': chatId,
        'input_message_content': {
          '@type': 'inputMessageText',
          'text': {'@type': 'formattedText', 'text': text},
        },
      }),
    );
  }

  void sendKeyboardButtonText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _client.send(
      _withPaidMessageOptions({
        '@type': 'sendMessage',
        'chat_id': chatId,
        'input_message_content': {
          '@type': 'inputMessageText',
          'text': {'@type': 'formattedText', 'text': trimmed},
        },
      }),
    );
  }

  void sendCommand(String command) {
    final trimmed = command.trim();
    if (!trimmed.startsWith('/')) return;
    _sendText(trimmed);
  }

  Future<Map<String, dynamic>> answerCallbackButton(
    int messageId,
    MessageButton button,
  ) async {
    final answer = await _client.query({
      '@type': 'getCallbackQueryAnswer',
      'chat_id': chatId,
      'message_id': messageId,
      'payload': {
        '@type': 'callbackQueryPayloadData',
        'data': button.data ?? '',
      },
    });
    await _refreshMessage(messageId);
    unawaited(
      Future<void>.delayed(
        const Duration(milliseconds: 700),
        () => _refreshMessage(messageId),
      ),
    );
    return answer;
  }

  Future<void> _refreshMessage(int messageId) async {
    if (_isDisposed) return;
    try {
      final raw = await _client.query({
        '@type': 'getMessage',
        'chat_id': chatId,
        'message_id': messageId,
      });
      if (_isDisposed) return;
      final refreshed = TDParse.message(raw);
      if (refreshed == null) return;
      _merge([refreshed]);
      _resolveRichMessagesIfNeeded([refreshed]);
      _resolveSendersIfNeeded([refreshed]);
      _resolveRepliesIfNeeded([refreshed]);
      _resolveForwardsIfNeeded([refreshed]);
      _resolveServiceUsersIfNeeded([refreshed]);
    } catch (_) {
      // Live TDLib updates remain the source of truth if a direct refresh fails.
    }
  }

  Future<void> translateMessage(int messageId, String toLanguageCode) async {
    _setTranslationLoading(messageId, true);
    try {
      final formatted = await _client.query({
        '@type': 'translateMessageText',
        'chat_id': chatId,
        'message_id': messageId,
        'to_language_code': toLanguageCode,
      });
      _replaceTranslation(
        messageId,
        formatted.str('text') ?? '',
        TDParse.textEntities(formatted),
        toLanguageCode,
      );
    } catch (_) {
      _setTranslationLoading(messageId, false);
      rethrow;
    }
  }

  Future<String> translateText(String text, String toLanguageCode) async {
    final formatted = await _client.query({
      '@type': 'translateText',
      'text': {
        '@type': 'formattedText',
        'text': text,
        'entities': const <Map<String, dynamic>>[],
      },
      'to_language_code': toLanguageCode,
    });
    return formatted.str('text') ?? '';
  }

  Future<void> translateMessageExternally(
    int messageId,
    String toLanguageCode,
    Future<String> Function() translate, {
    bool showLoading = true,
  }) async {
    if (showLoading) _setTranslationLoading(messageId, true);
    try {
      final translated = await translate();
      _replaceTranslation(messageId, translated, const [], toLanguageCode);
    } catch (_) {
      if (showLoading) _setTranslationLoading(messageId, false);
      rethrow;
    }
  }

  // MARK: - Message actions (long-press menu)

  Future<void> forward(
    int messageId,
    int targetChatId, {
    ForwardOptions options = const ForwardOptions(),
  }) async {
    await forwardMany([messageId], targetChatId, options: options);
  }

  Future<void> forwardMany(
    List<int> messageIds,
    int targetChatId, {
    ForwardOptions options = const ForwardOptions(),
  }) async {
    await forwardMessagesWithOptions(
      client: _client,
      targetChatId: targetChatId,
      fromChatId: chatId,
      messageIds: messageIds,
      options: options,
    );
  }

  Future<void> saveToFavorites(int messageId) async {
    await saveToFavoritesMany([messageId]);
  }

  Future<void> saveToFavoritesMany(List<int> messageIds) async {
    if (messageIds.isEmpty) return;
    final me = await _client.query({'@type': 'getMe'});
    final myId = me.int64('id');
    if (myId == null) throw TdError({'message': 'Missing current user id'});
    final saved = await _client.query({
      '@type': 'createPrivateChat',
      'user_id': myId,
      'force': false,
    });
    final savedChatId = saved.int64('id');
    if (savedChatId == null) {
      throw TdError({'message': 'Missing Saved Messages chat id'});
    }
    await _client.query({
      '@type': 'forwardMessages',
      'chat_id': savedChatId,
      'from_chat_id': chatId,
      'message_ids': messageIds,
      'options': {'@type': 'messageSendOptions'},
      'send_copy': false,
      'remove_caption': false,
    });
  }

  void saveFavoriteSticker(int fileId) {
    _client.send({
      '@type': 'addFavoriteSticker',
      'sticker': {'@type': 'inputFileId', 'id': fileId},
    });
  }

  Future<void> deleteMessage(int id) {
    return deleteMessages([id]);
  }

  Future<void> deleteMessages(List<int> ids) async {
    if (ids.isEmpty) return;
    await _client.query({
      '@type': 'deleteMessages',
      'chat_id': chatId,
      'message_ids': ids,
      'revoke': true,
    });
    _removeMessages(ids);
  }

  Future<void> deleteMessagesFromSender(ChatMessage message) async {
    final senderId = message.senderId;
    final sender = _messageSenderFor(message);
    if (senderId == null || sender == null) {
      throw TdError({'message': 'Missing message sender'});
    }
    await _client.query({
      '@type': 'deleteChatMessagesBySender',
      'chat_id': chatId,
      'sender_id': sender,
    });
    final ids = _allMessages
        .where((candidate) => candidate.senderId == senderId)
        .map((candidate) => candidate.id)
        .toList();
    _removeMessages(ids);
  }

  Future<void> reportMessage(ChatMessage message) async {
    await _reportTelegramContent(message);
  }

  Future<void> blockSender(ChatMessage message) async {
    final senderId = message.senderId;
    final sender = _messageSenderFor(message);
    if (senderId == null || sender == null) {
      throw TdError({'message': 'Missing message sender'});
    }
    _blockedSenderIds.add(senderId);
    KeywordBlocker.shared.addBlockedSender(senderId);
    _applyKeywordFilter();
    try {
      await _client.query({
        '@type': 'setMessageSenderBlockList',
        'sender_id': sender,
        'block_list': {'@type': 'blockListMain'},
      });
    } catch (_) {
      _blockedSenderIds.remove(senderId);
      KeywordBlocker.shared.removeBlockedSender(senderId);
      _applyKeywordFilter();
      rethrow;
    }
  }

  Future<void> blockAndReportSender(ChatMessage message) async {
    await blockSender(message);
    unawaited(_reportTelegramContent(message).catchError((_) {}));
  }

  Map<String, dynamic>? _messageSenderFor(ChatMessage message) {
    final senderId = message.senderId;
    if (senderId == null) return null;
    if (senderId > 0) {
      return {'@type': 'messageSenderUser', 'user_id': senderId};
    }
    return {'@type': 'messageSenderChat', 'chat_id': senderId};
  }

  Future<void> _reportTelegramContent(ChatMessage message) async {
    final sender = _messageSenderFor(message);
    final base = <String, dynamic>{
      '@type': 'reportChat',
      'chat_id': chatId,
      'message_ids': [message.id],
      'sender_id': sender,
      'option_id': '',
      'text': 'Objectionable or abusive content reported from Mithka.',
    };
    final result = await _client.query(base);
    if (result.type != 'reportChatResultOptionRequired') return;
    final options = result.objects('options') ?? const <Map<String, dynamic>>[];
    if (options.isEmpty) return;
    await _client.query({...base, 'option_id': options.first['id'] ?? ''});
  }

  Future<void> editMessageText(
    int id,
    String text, {
    List<Map<String, dynamic>> entities = const [],
  }) async {
    if (text.trim().isEmpty) return;
    await _client.query({
      '@type': 'editMessageText',
      'chat_id': chatId,
      'message_id': id,
      'input_message_content': {
        '@type': 'inputMessageText',
        'text': {
          '@type': 'formattedText',
          'text': text,
          if (entities.isNotEmpty) 'entities': entities,
        },
        'link_preview_options': {
          '@type': 'linkPreviewOptions',
          'is_disabled': false,
        },
        'clear_draft': false,
      },
    });
    final parsed = TDParse.textEntities({
      '@type': 'formattedText',
      'text': text,
      'entities': entities,
    });
    _replaceText(
      id,
      text,
      edited: true,
      entities: parsed,
      customEmoji: TDParse.customEmojiEntitiesFrom(parsed),
    );
  }

  Future<void> editMessageCaption(
    int id,
    String caption, {
    List<Map<String, dynamic>> entities = const [],
  }) async {
    await _client.query({
      '@type': 'editMessageCaption',
      'chat_id': chatId,
      'message_id': id,
      'caption': {
        '@type': 'formattedText',
        'text': caption,
        if (entities.isNotEmpty) 'entities': entities,
      },
    });
    _replaceText(
      id,
      caption,
      edited: true,
      entities: TDParse.textEntities({
        '@type': 'formattedText',
        'text': caption,
        'entities': entities,
      }),
      customEmoji: TDParse.customEmojiEntitiesFrom(
        TDParse.textEntities({
          '@type': 'formattedText',
          'text': caption,
          'entities': entities,
        }),
      ),
    );
  }

  Future<void> editMessageMedia(
    int id,
    String path, {
    required bool isVideo,
    required String caption,
    List<Map<String, dynamic>> entities = const [],
  }) async {
    await _client.query({
      '@type': 'editMessageMedia',
      'chat_id': chatId,
      'message_id': id,
      'input_message_content': {
        '@type': isVideo ? 'inputMessageVideo' : 'inputMessagePhoto',
        isVideo ? 'video' : 'photo': {
          '@type': isVideo ? 'inputVideo' : 'inputPhoto',
          isVideo ? 'video' : 'photo': {
            '@type': 'inputFileLocal',
            'path': path,
          },
          if (isVideo) 'supports_streaming': true,
        },
        if (caption.trim().isNotEmpty)
          'caption': {
            '@type': 'formattedText',
            'text': caption,
            if (entities.isNotEmpty) 'entities': entities,
          },
      },
    });
  }

  // MARK: - Paging

  Future<bool> loadOlder() async {
    if (!canLoadOlder) return false;
    _isLoadingOlder = true;
    try {
      return await _fetchHistory(_allMessages.first.id, 0, 30, isOlder: true);
    } finally {
      _isLoadingOlder = false;
    }
  }

  Future<bool> loadOlderLocal({bool restorePosition = true}) async {
    if (!canLoadOlder) return false;
    _isLoadingOlder = true;
    try {
      return await _fetchHistory(
        _allMessages.first.id,
        0,
        30,
        isOlder: true,
        restorePosition: restorePosition,
        onlyLocal: true,
      );
    } finally {
      _isLoadingOlder = false;
    }
  }

  Future<bool> loadLatestHistory() async {
    anchoredHistory = false;
    _pendingScrollToId = null;
    _allMessages = [];
    messages = [];
    _hasOlderHistory = true;
    final ok = await _fetchHistory(0, 0, 40, restorePosition: false);
    if (!ok) return false;
    if (messages.length < 12 && _allMessages.isNotEmpty) {
      await _fetchHistory(_allMessages.first.id, 0, 40, restorePosition: false);
    }
    return true;
  }

  // MARK: - Header

  Future<void> _loadChatHeader() async {
    Map<String, dynamic> chat;
    try {
      chat = await _client.query({'@type': 'getChat', 'chat_id': chatId});
    } catch (error) {
      if (_markTelegramTosRestricted(error)) notifyListeners();
      return;
    }
    peerTitle = chat.str('title') ?? peerTitle;
    peerPhoto = TDParse.smallPhoto(chat.obj('photo'));
    lastReadOutboxId = chat.int64('last_read_outbox_message_id') ?? 0;
    lastReadInboxId = chat.int64('last_read_inbox_message_id') ?? 0;
    unreadCount = chat.integer('unread_count') ?? 0;
    isMarkedUnread = chat.boolean('is_marked_as_unread') ?? false;
    final notificationSettings = chat.obj('notification_settings');
    isMuted = ScopeNotificationSettings.shared.isMuted(chat);
    if (hasLegacyHiddenNotificationPreview(notificationSettings)) {
      unawaited(_repairLegacyNotificationPreview(notificationSettings!));
    }
    isForum = chat.boolean('view_as_topics') ?? false;
    messageAutoDeleteTime = _autoDeleteSeconds(chat);
    _setPaidMessageStarCount(_paidMessageStars(chat), notify: false);
    _applyRemoteDraft(chat.obj('draft_message'), force: true, notify: false);
    final kind = TDParse.chatKind(chat);
    isGroup = kind == ChatKind.group || kind == ChatKind.channel;
    _primeLastMessage(chat);
    if (isTelegramTosRestricted) {
      notifyListeners();
      return;
    }

    // Chat-wide default send permission + permissive membership defaults
    // (refined per type below).
    _chatCanSend =
        chat.obj('permissions')?.boolean('can_send_basic_messages') ?? true;
    canSendMessages = true;
    isMember = true;
    canJoin = false;
    joinByRequest = false;
    isChannel = false;
    canDeleteMessagesBySender = false;
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
            peerIsBot = _isBotUser(user);
            peerOnline = TDParse.isUserOnline(user);
            peerStatusText = TDParse.userStatus(user);
          } catch (_) {}
          unawaited(_loadPrivatePaidMessageInfo(uid));
          if (peerIsBot) await _loadBotInfo(uid);
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
        peerSupergroupId = sgid;
        if (sgid != null) {
          try {
            final sg = await _client.query({
              '@type': 'getSupergroup',
              'supergroup_id': sgid,
            });
            isChannel = sg.boolean('is_channel') ?? false;
            isForum = isForum || (sg.boolean('is_forum') ?? false);
            joinByRequest = sg.boolean('join_by_request') ?? false;
            _setPaidMessageStarCount(_paidMessageStars(sg), notify: false);
            _applyGroupStatus(sg.obj('status'));
          } catch (_) {}
          unawaited(_loadSupergroupFullInfo(sgid));
        }
    }
    if (isForum) {
      unawaited(loadForumTopics());
    } else if (forumTopics.isNotEmpty || forumTopicsLoading) {
      forumTopicsLoading = false;
      forumTopics = const [];
    }
    notifyListeners();
    unawaited(_loadPinnedMessage());
  }

  void _primeLastMessage(Map<String, dynamic> chat) {
    final lastRaw = chat.obj('last_message');
    final lastMessage = lastRaw == null ? null : TDParse.message(lastRaw);
    if (lastMessage == null) return;
    if (_markTelegramTosRestrictedText(lastMessage.text)) return;
    _merge([lastMessage]);
    _resolveRichMessagesIfNeeded([lastMessage]);
    _resolveRepliesIfNeeded([lastMessage]);
    _resolveForwardsIfNeeded([lastMessage]);
  }

  Future<void> _loadSupergroupFullInfo(int supergroupId) async {
    try {
      final full = await _client.query({
        '@type': 'getSupergroupFullInfo',
        'supergroup_id': supergroupId,
      });
      memberCount = full.integer('member_count') ?? memberCount;
      _setPaidMessageStarCount(_paidMessageStars(full), notify: false);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadPrivatePaidMessageInfo(int userId) async {
    var next = 0;
    try {
      final full = await _client.query({
        '@type': 'getUserFullInfo',
        'user_id': userId,
      });
      next = _paidMessageStars(full);
    } catch (_) {}
    if (next <= 0) {
      try {
        final result = await _client.query({
          '@type': 'canSendMessageToUser',
          'user_id': userId,
          'only_local': false,
        });
        if (result.type == 'canSendMessageToUserResultUserHasPaidMessages') {
          next = _paidMessageStars(result);
        }
      } catch (_) {}
    }
    _setPaidMessageStarCount(next);
  }

  Future<void> loadForumTopics() async {
    if (!isForum || forumTopicsLoading) return;
    forumTopicsLoading = true;
    notifyListeners();
    try {
      final response = await _client.query({
        '@type': 'getForumTopics',
        'chat_id': chatId,
        'query': '',
        'offset_date': 0,
        'offset_message_id': 0,
        'offset_forum_topic_id': 0,
        'limit': 80,
      });
      final raw = response.objects('topics') ?? const <Map<String, dynamic>>[];
      final topics = <ForumTopicOption>[];
      for (final topic in raw) {
        final info = topic.obj('info') ?? topic;
        final id = _forumTopicId(topic, info);
        if (id == null || id == 0) continue;
        final name =
            info.str('name') ??
            topic.str('name') ??
            AppStrings.t(AppStringKeys.topicChatTopicTitle);
        final icon = info.obj('icon') ?? topic.obj('icon');
        topics.add(
          ForumTopicOption(
            id: id,
            name: name,
            iconCustomEmojiId:
                icon?.int64('custom_emoji_id') ??
                info.int64('icon_custom_emoji_id') ??
                topic.int64('icon_custom_emoji_id') ??
                0,
            iconColor:
                icon?.integer('color') ??
                info.integer('icon_color') ??
                topic.integer('icon_color') ??
                0,
          ),
        );
      }
      forumTopics = topics;
    } catch (_) {
      forumTopics = const [];
    } finally {
      forumTopicsLoading = false;
      notifyListeners();
    }
  }

  int? _forumTopicId(Map<String, dynamic> topic, Map<String, dynamic> info) {
    return info.integer('forum_topic_id') ??
        topic.integer('forum_topic_id') ??
        info.int64('message_thread_id') ??
        topic.int64('message_thread_id');
  }

  int _autoDeleteSeconds(Map<String, dynamic> chat) {
    final nested = chat.obj('message_auto_delete_time');
    return nested?.integer('time') ??
        chat.integer('message_auto_delete_time') ??
        chat.integer('auto_delete_time') ??
        0;
  }

  int _paidMessageStars(Map<String, dynamic> object) {
    final direct = object.obj('direct_messages_chat_topic');
    final settings = object.obj('paid_message_settings');
    return object.int64('outgoing_paid_message_star_count') ??
        object.int64('paid_message_star_count') ??
        object.int64('send_paid_message_star_count') ??
        object.int64('paid_messages_star_count') ??
        direct?.int64('outgoing_paid_message_star_count') ??
        direct?.int64('paid_message_star_count') ??
        direct?.int64('send_paid_message_star_count') ??
        settings?.int64('outgoing_paid_message_star_count') ??
        settings?.int64('paid_message_star_count') ??
        settings?.int64('send_paid_message_star_count') ??
        0;
  }

  bool _isBotUser(Map<String, dynamic> user) =>
      user.obj('type')?.type == 'userTypeBot' ||
      user.obj('type')?.type == 'userTypeRegularBot' ||
      user.boolean('is_bot') == true;

  Future<void> _loadBotInfo(int userId) async {
    try {
      final full = await _client.query({
        '@type': 'getUserFullInfo',
        'user_id': userId,
      });
      final info = full.obj('bot_info');
      if (info == null) return;
      final menu = _parseBotMenu(info.obj('menu_button'));
      final commands =
          (info.objects('commands') ?? const <Map<String, dynamic>>[])
              .map(
                (c) => BotCommandOption(
                  command: c.str('command') ?? '',
                  description: c.str('description') ?? '',
                ),
              )
              .where((c) => c.command.trim().isNotEmpty)
              .toList();
      botMenu = menu;
      botCommands = commands;
      notifyListeners();
    } catch (_) {}
  }

  BotMenuInfo? _parseBotMenu(Map<String, dynamic>? menu) {
    if (menu == null) return null;
    switch (menu.type) {
      case 'botMenuButton':
        return BotMenuInfo(
          type: menu.type!,
          text: menu.str('text') ?? AppStrings.t(AppStringKeys.chatMenu),
          url: menu.str('url') ?? '',
        );
      case 'botMenuButtonCommands':
      case 'botMenuButtonDefault':
        return BotMenuInfo(type: menu.type!);
    }
    return null;
  }

  /// Maps the current user's member status (+ channel-ness / chat defaults) onto
  /// the send / membership / join flags the chat UI reads.
  void _applyGroupStatus(Map<String, dynamic>? status) {
    switch (status?.type) {
      case 'chatMemberStatusCreator':
        canDeleteMessagesBySender = true;
        isMember = true;
        canSendMessages = true;
      case 'chatMemberStatusAdministrator':
        canDeleteMessagesBySender =
            status?.obj('rights')?.boolean('can_delete_messages') ?? false;
        isMember = true;
        canSendMessages = true;
      case 'chatMemberStatusMember':
        isMember = true;
        canSendMessages = isChannel ? false : _chatCanSend;
        if (!canSendMessages) {
          sendDisabledReason = isChannel
              ? AppStrings.t(AppStringKeys.chatAdminsOnlyPosting)
              : AppStrings.t(AppStringKeys.chatAllMembersMuted);
        }
      case 'chatMemberStatusRestricted':
        isMember = status?.boolean('is_member') ?? true;
        canSendMessages =
            status?.obj('permissions')?.boolean('can_send_basic_messages') ??
            false;
        if (!isMember) canJoin = true;
        if (!canSendMessages) {
          sendDisabledReason = AppStrings.t(AppStringKeys.chatYouAreMuted);
        }
      case 'chatMemberStatusLeft':
        isMember = false;
        canSendMessages = false;
        canJoin = true;
      case 'chatMemberStatusBanned':
        isMember = false;
        canSendMessages = false;
        sendDisabledReason = AppStrings.t(
          AppStringKeys.chatYouWereRemovedFromGroup,
        );
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
        'notification_settings': inheritedChatNotificationSettings(
          muteFor: target ? 0 : 2147483647,
        ),
      });
    } catch (_) {
      isMuted = target; // revert on failure
      notifyListeners();
    }
  }

  Future<void> _repairLegacyNotificationPreview(
    Map<String, dynamic> settings,
  ) async {
    try {
      await _client.query({
        '@type': 'setChatNotificationSettings',
        'chat_id': chatId,
        'notification_settings': repairedChatNotificationSettings(settings),
      });
    } catch (_) {}
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
          sendDisabledReason = AppStrings.t(
            AppStringKeys.chatAdminsOnlyPosting,
          );
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
        'limit': 50,
        'filter': {'@type': 'searchMessagesFilterPinned'},
      });
      final list = res.objects('messages');
      if (list == null || list.isEmpty) return;
      final parsed = list
          .map(TDParse.message)
          .whereType<ChatMessage>()
          .toList();
      if (parsed.isEmpty) return;
      pinnedMessages = parsed;
      pinnedMessageIndex = pinnedMessageIndex.clamp(0, parsed.length - 1);
      pinnedMessage = parsed[pinnedMessageIndex];
      notifyListeners();
    } catch (_) {}
  }

  bool get hasPreviousPinnedMessage => pinnedMessageIndex > 0;
  bool get hasNextPinnedMessage =>
      pinnedMessageIndex < pinnedMessages.length - 1;

  ChatMessage? previousPinnedMessage() {
    if (!hasPreviousPinnedMessage) return null;
    pinnedMessageIndex--;
    pinnedMessage = pinnedMessages[pinnedMessageIndex];
    pinnedDismissed = false;
    notifyListeners();
    return pinnedMessage;
  }

  ChatMessage? nextPinnedMessage() {
    if (!hasNextPinnedMessage) return null;
    pinnedMessageIndex++;
    pinnedMessage = pinnedMessages[pinnedMessageIndex];
    pinnedDismissed = false;
    notifyListeners();
    return pinnedMessage;
  }

  void dismissPinned() {
    pinnedDismissed = true;
    notifyListeners();
  }

  Future<void> pinTodo(ChatMessage message) async {
    await _client.query({
      '@type': 'pinChatMessage',
      'chat_id': chatId,
      'message_id': message.id,
      'disable_notification': true,
      'only_for_self': false,
    });
    pinnedMessage = message;
    pinnedMessages = [
      message,
      ...pinnedMessages.where((m) => m.id != message.id),
    ];
    pinnedMessageIndex = 0;
    pinnedDismissed = false;
    notifyListeners();
  }

  Future<void> unpinTodo(ChatMessage message) async {
    await _client.query({
      '@type': 'unpinChatMessage',
      'chat_id': chatId,
      'message_id': message.id,
    });
    final removedIndex = pinnedMessages.indexWhere((m) => m.id == message.id);
    pinnedMessages = pinnedMessages.where((m) => m.id != message.id).toList();
    if (pinnedMessages.isEmpty) {
      pinnedMessage = null;
      pinnedMessageIndex = 0;
      pinnedDismissed = false;
      notifyListeners();
      return;
    }
    if (removedIndex >= 0 && removedIndex <= pinnedMessageIndex) {
      pinnedMessageIndex = (pinnedMessageIndex - 1).clamp(
        0,
        pinnedMessages.length - 1,
      );
    } else {
      pinnedMessageIndex = pinnedMessageIndex.clamp(
        0,
        pinnedMessages.length - 1,
      );
    }
    pinnedMessage = pinnedMessages[pinnedMessageIndex];
    pinnedDismissed = false;
    notifyListeners();
  }

  // MARK: - History

  Future<void> _loadInitialHistory({required bool openAtLatest}) async {
    if (!openAtLatest && lastReadInboxId > 0) {
      final loaded = await _loadInitialAroundLastRead();
      if (loaded) return;
    }
    await _loadInitialLatestHistory();
  }

  Future<bool> _loadInitialAroundLastRead() async {
    final loadedLocal = await loadAroundMessage(
      lastReadInboxId,
      onlyLocal: true,
    );
    if (loadedLocal) {
      unawaited(loadAroundMessage(lastReadInboxId, scrollToTarget: false));
      return true;
    }
    return loadAroundMessage(lastReadInboxId);
  }

  Future<void> _loadInitialLatestHistory() async {
    final localLoaded = await _fetchHistory(
      0,
      0,
      40,
      onlyLocal: true,
      restorePosition: false,
    );
    if (!localLoaded) {
      await _fetchHistory(0, 0, 40);
    } else {
      unawaited(_fetchHistory(0, 0, 40, restorePosition: false));
    }
    if (_allMessages.isEmpty) return;
    // Render the first page immediately. Older unread-boundary paging used to
    // happen here and could block a large media channel for seconds on cold
    // cache before any UI appeared.
    if (messages.length < 12) {
      unawaited(
        _fetchHistory(_allMessages.first.id, 0, 40, restorePosition: false),
      );
    }
  }

  Future<bool> loadAroundMessage(
    int messageId, {
    bool onlyLocal = false,
    bool scrollToTarget = true,
  }) async {
    final batch = <ChatMessage>[];
    try {
      final targetRaw = await _client.query({
        '@type': 'getMessage',
        'chat_id': chatId,
        'message_id': messageId,
      });
      final target = TDParse.message(targetRaw);
      if (target != null) batch.add(target);
    } catch (error) {
      if (_markTelegramTosRestricted(error)) {
        notifyListeners();
        return false;
      }
    }

    try {
      final response = await _client.query({
        '@type': 'getChatHistory',
        'chat_id': chatId,
        'from_message_id': messageId,
        'offset': -30,
        'limit': 80,
        'only_local': onlyLocal,
      });
      batch.addAll(
        (response.objects('messages') ?? const <Map<String, dynamic>>[])
            .map(TDParse.message)
            .whereType<ChatMessage>(),
      );
    } catch (error) {
      if (_markTelegramTosRestricted(error)) notifyListeners();
    }

    final visibleBatch = _withoutRestrictedNoticeMessages(batch);
    if (visibleBatch.isEmpty) return false;
    _allMessages = [];
    messages = [];
    _hasOlderHistory = true;
    anchoredHistory = true;
    if (scrollToTarget) _pendingScrollToId = messageId;
    _merge(visibleBatch);
    _resolveRichMessagesIfNeeded(visibleBatch);
    _resolveSendersIfNeeded(visibleBatch);
    _resolveRepliesIfNeeded(visibleBatch);
    _resolveForwardsIfNeeded(visibleBatch);
    _resolveServiceUsersIfNeeded(visibleBatch);
    return messages.any((m) => m.id == messageId);
  }

  Future<bool> _fetchHistory(
    int fromMessageId,
    int offset,
    int limit, {
    bool isOlder = false,
    bool restorePosition = true,
    bool onlyLocal = false,
  }) async {
    final anchor = messages.isNotEmpty ? messages.first.id : null;
    final allAnchor = _allMessages.isNotEmpty ? _allMessages.first.id : null;
    Map<String, dynamic> response;
    try {
      response = await _client.query({
        '@type': 'getChatHistory',
        'chat_id': chatId,
        'from_message_id': fromMessageId,
        'offset': offset,
        'limit': limit,
        'only_local': onlyLocal,
      });
    } catch (error) {
      if (_markTelegramTosRestricted(error)) notifyListeners();
      return false;
    }

    final rawMessages =
        response.objects('messages') ?? const <Map<String, dynamic>>[];
    final parsed = rawMessages
        .map(TDParse.message)
        .whereType<ChatMessage>()
        .toList();
    final visibleMessages = _withoutRestrictedNoticeMessages(parsed);
    if (parsed.isNotEmpty && visibleMessages.isEmpty) {
      notifyListeners();
      return false;
    }
    if (visibleMessages.isEmpty) {
      if (isOlder || fromMessageId != 0) _hasOlderHistory = false;
      return false;
    }

    _merge(visibleMessages);
    _resolveRichMessagesIfNeeded(visibleMessages);
    if (isOlder &&
        restorePosition &&
        anchor != null &&
        allAnchor != null &&
        _allMessages.first.id != allAnchor) {
      _restoreTopId = anchor;
    }
    _resolveSendersIfNeeded(visibleMessages);
    _resolveRepliesIfNeeded(visibleMessages);
    _resolveForwardsIfNeeded(visibleMessages);
    _resolveServiceUsersIfNeeded(visibleMessages);
    return true;
  }

  bool _markTelegramTosRestricted(Object error) {
    final text = error.toString();
    final normalized = _normalizedRestrictionText(text);
    final restricted =
        _isTelegramTosRestrictedText(text) ||
        normalized.contains('chat_restricted') ||
        normalized.contains('channel_restricted');
    if (!restricted) return false;
    _setTelegramTosRestricted(text);
    return true;
  }

  bool _markTelegramTosRestrictedText(String text) {
    if (!_isTelegramTosRestrictedText(text)) return false;
    _setTelegramTosRestricted(text);
    return true;
  }

  bool _isTelegramTosRestrictedText(String text) {
    final normalized = _normalizedRestrictionText(text);
    final cannotDisplay =
        normalized.contains("can't be displayed") ||
        normalized.contains('cannot be displayed');
    final telegramTerms =
        normalized.contains('terms of service') ||
        normalized.contains('violated telegram');
    return cannotDisplay && telegramTerms;
  }

  String _normalizedRestrictionText(String text) =>
      text.toLowerCase().replaceAll('’', "'");

  List<ChatMessage> _withoutRestrictedNoticeMessages(List<ChatMessage> source) {
    var restrictedNotice = '';
    final visible = <ChatMessage>[];
    for (final message in source) {
      if (_isTelegramTosRestrictedText(message.text)) {
        restrictedNotice = message.text;
        continue;
      }
      visible.add(message);
    }
    if (restrictedNotice.isNotEmpty) {
      _setTelegramTosRestricted(restrictedNotice);
    }
    return visible;
  }

  void _setTelegramTosRestricted(String text) {
    isTelegramTosRestricted = true;
    telegramTosRestrictionText = text;
    messages = messages
        .where((message) => !_isTelegramTosRestrictedText(message.text))
        .toList();
    _allMessages = _allMessages
        .where((message) => !_isTelegramTosRestrictedText(message.text))
        .toList();
    anchoredHistory = false;
    canSendMessages = false;
    canJoin = false;
    isMember = true;
    sendDisabledReason = AppStrings.t(
      AppStringKeys.chatRestrictedTelegramTosMessage,
    );
  }

  Future<void> leaveChat() async {
    await _client.query({'@type': 'leaveChat', 'chat_id': chatId});
  }

  Future<void> markLoadedMessagesRead() async {
    if (_markReadInFlight) return;
    _markReadInFlight = true;
    try {
      final latestLoadedId = _allMessages.isNotEmpty ? _allMessages.last.id : 0;
      var messageId = latestLoadedId;
      final previousUnreadCount = unreadCount;
      final previousMarkedUnread = isMarkedUnread;
      if (previousUnreadCount > 0 || previousMarkedUnread || messageId <= 0) {
        try {
          final raw = await _client.query({
            '@type': 'getChat',
            'chat_id': chatId,
          });
          final latestRaw = raw.obj('last_message');
          final latest = latestRaw == null ? null : TDParse.message(latestRaw);
          messageId = math.max(messageId, latest?.id ?? 0);
        } catch (_) {}
      }

      final shouldClearMarker = previousMarkedUnread;
      final shouldForceRead =
          messageId > 0 &&
          (previousUnreadCount > 0 ||
              messageId > lastReadInboxId ||
              _lastForcedReadMessageId != messageId);
      if (!shouldClearMarker && !shouldForceRead) return;

      if (shouldClearMarker) isMarkedUnread = false;
      if (messageId > lastReadInboxId) lastReadInboxId = messageId;
      if (unreadCount != 0) unreadCount = 0;
      notifyListeners();

      if (shouldClearMarker) {
        _client.send({
          '@type': 'toggleChatIsMarkedAsUnread',
          'chat_id': chatId,
          'is_marked_as_unread': false,
        });
        _client.emitLocalUpdate({
          '@type': 'updateChatIsMarkedAsUnread',
          'chat_id': chatId,
          'is_marked_as_unread': false,
        });
      }
      if (shouldForceRead) {
        _lastForcedReadMessageId = messageId;
        _client.send({
          '@type': 'viewMessages',
          'chat_id': chatId,
          'message_ids': [messageId],
          'force_read': true,
        });
        _client.emitLocalUpdate({
          '@type': 'updateChatReadInbox',
          'chat_id': chatId,
          'last_read_inbox_message_id': messageId,
          'unread_count': 0,
        });
      }
      final chatDelta =
          !isMuted && (previousUnreadCount > 0 || shouldClearMarker) ? -1 : 0;
      final messageDelta = !isMuted && previousUnreadCount > 0
          ? -previousUnreadCount
          : 0;
      if (chatDelta != 0 || messageDelta != 0) {
        _client.emitLocalUpdate({
          '@type': 'mithkaUnreadDelta',
          'chat_list': {'@type': 'chatListMain'},
          'chat_id': chatId,
          'chat_delta': chatDelta,
          'message_delta': messageDelta,
        });
      }
    } finally {
      _markReadInFlight = false;
    }
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
        _resolveRichMessagesIfNeeded([message]);
        _resolveSendersIfNeeded([message]);
        _resolveRepliesIfNeeded([message]);
        _resolveForwardsIfNeeded([message]);
        _resolveServiceUsersIfNeeded([message]);
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
        _replaceText(
          messageId,
          TDParse.messageText(content),
          entities: TDParse.messageTextEntities(content),
          customEmoji: TDParse.customEmojiEntitiesForContent(content),
          linkPreview: TDParse.linkPreview(content.obj('link_preview')),
          updateLinkPreview: true,
        );
        if (content.type == 'messageRichMessage') {
          _replaceRichMessageContent(messageId, content);
          final target = _messageRefs(messageId);
          _resolveRichMessagesIfNeeded(target);
        }

      case 'updateMessageSendSucceeded':
        if (update.int64('chat_id') != chatId) return;
        final oldMessageId = update.int64('old_message_id');
        final rawSentMessage = update.obj('message');
        if (oldMessageId == null || rawSentMessage == null) return;
        _replacePendingMessage(oldMessageId, rawSentMessage);
        _recordMessageSendResult(
          oldMessageId,
          const _MessageSendResult.success(),
        );

      case 'updateMessageSendFailed':
        if (update.int64('chat_id') != chatId) return;
        final oldMessageId = update.int64('old_message_id');
        if (oldMessageId == null) return;
        final errorData =
            update.obj('error') ??
            update.obj('message')?.obj('sending_state')?.obj('error') ??
            <String, dynamic>{
              '@type': 'error',
              'code': 400,
              'message': 'Message send failed',
            };
        final error = TdError(errorData);
        debugPrint('Message $oldMessageId failed to send: $error');
        _discardPendingMessage(oldMessageId);
        _recordMessageSendResult(
          oldMessageId,
          _MessageSendResult.failure(error),
        );

      case 'updateChat':
        final chat = update.obj('chat');
        if (chat == null || chat.int64('id') != chatId) return;
        messageAutoDeleteTime = _autoDeleteSeconds(chat);
        _setPaidMessageStarCount(_paidMessageStars(chat), notify: false);
        if (chat.containsKey('draft_message')) {
          _applyRemoteDraft(chat.obj('draft_message'), notify: false);
        }
        notifyListeners();

      case 'updateChatDraftMessage':
        if (update.int64('chat_id') != chatId) return;
        _applyRemoteDraft(update.obj('draft_message'));

      case 'updateChatMessageAutoDeleteTime':
        if (update.int64('chat_id') != chatId) return;
        messageAutoDeleteTime =
            update.obj('message_auto_delete_time')?.integer('time') ??
            update.integer('message_auto_delete_time') ??
            update.integer('time') ??
            0;
        notifyListeners();

      case 'updateChatPaidMessageStarCount':
        if (update.int64('chat_id') != chatId) return;
        _setPaidMessageStarCount(
          update.int64('paid_message_star_count') ??
              update.int64('outgoing_paid_message_star_count') ??
              update.int64('star_count') ??
              0,
        );

      case 'updateDeleteMessages':
        if (update.int64('chat_id') != chatId) return;
        _removeMessages(update.int64Array('message_ids') ?? const <int>[]);

      case 'mithkaChatHistoryCleared':
        if (update.int64('chat_id') != chatId) return;
        _allMessages = [];
        messages = [];
        _hasOlderHistory = false;
        _pendingScrollToId = null;
        notifyListeners();

      case 'mithkaChatLeft':
        if (update.int64('chat_id') != chatId) return;
        isMember = false;
        canSendMessages = false;
        canJoin = true;
        sendDisabledReason = isChannel
            ? AppStrings.t(AppStringKeys.topicChatLeaveChannel)
            : AppStrings.t(AppStringKeys.chatYouWereRemovedFromGroup);
        notifyListeners();

      case 'updateChatReadOutbox':
        if (update.int64('chat_id') != chatId) return;
        lastReadOutboxId =
            update.int64('last_read_outbox_message_id') ?? lastReadOutboxId;
        notifyListeners();

      case 'updateChatReadInbox':
        if (update.int64('chat_id') != chatId) return;
        lastReadInboxId =
            update.int64('last_read_inbox_message_id') ?? lastReadInboxId;
        unreadCount = update.integer('unread_count') ?? unreadCount;
        notifyListeners();

      case 'updateChatIsMarkedAsUnread':
        if (update.int64('chat_id') != chatId) return;
        isMarkedUnread = update.boolean('is_marked_as_unread') ?? false;
        notifyListeners();

      case 'updateChatAction':
        if (update.int64('chat_id') != chatId) return;
        final sender = update.obj('sender_id');
        final sid = sender?.int64('user_id') ?? sender?.int64('chat_id');
        if (sid == null) return;
        final actionType = update.obj('action')?.type;
        if (actionType == 'chatActionCancel') {
          _chatActions.remove(sid);
        } else {
          _chatActions[sid] = _ChatActionInfo(
            _senderCache[sid]?.name ?? '',
            actionType ?? 'chatActionTyping',
          );
          if ((_senderCache[sid]?.name ?? '').isEmpty && isGroup && sid > 0) {
            _resolveSender(sid); // fills the name for the next render
          }
          _restartTypingTimer();
        }
        notifyListeners();

      case 'updateChatMessageSender':
        if (update.int64('chat_id') != chatId) return;
        final sender = update.obj('message_sender_id');
        if (sender == null) {
          selectedMessageSender = null;
          notifyListeners();
          return;
        }
        for (final option in availableMessageSenders) {
          if (option.sameSender(sender)) {
            selectedMessageSender = option;
            notifyListeners();
            return;
          }
        }
        _loadAvailableMessageSenders();

      case 'updateUserFullInfo':
        if (isGroup || update.int64('user_id') != peerUserId) return;
        _setPaidMessageStarCount(
          _paidMessageStars(update.obj('user_full_info') ?? update),
        );

      case 'updateSupergroup':
        final supergroup = update.obj('supergroup');
        if (supergroup == null || supergroup.int64('id') != peerSupergroupId) {
          return;
        }
        _setPaidMessageStarCount(_paidMessageStars(supergroup));

      case 'updateSupergroupFullInfo':
        if (update.int64('supergroup_id') != peerSupergroupId) return;
        _setPaidMessageStarCount(
          _paidMessageStars(update.obj('supergroup_full_info') ?? update),
        );

      case 'updateUserStatus':
        if (isGroup || update.int64('user_id') != peerUserId) return;
        peerOnline = update.obj('status')?.type == 'userStatusOnline';
        peerStatusText = _statusLabel(update.obj('status')?.type);
        notifyListeners();

      case 'updateMessageEdited':
        if (update.int64('chat_id') != chatId) return;
        final mid = update.int64('message_id');
        if (mid == null) return;
        final replyMarkup = update.obj('reply_markup');
        _replaceButtonRows(mid, TDParse.messageButtonRows(replyMarkup));
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

      case 'updateBlockMessageSender':
        // Invalidate blocked-user cache so the hide-on-block toggle
        // takes effect immediately without app restart.
        if (BlockedUserService.shared.enabled) {
          unawaited(BlockedUserService.shared.loadBlockedUsers().then((_) {
            _applyKeywordFilter();
          }));
        }
    }
  }

  // MARK: - Reactions

  void addReaction(int messageId, String emoji) {
    _client.send({
      '@type': 'addMessageReaction',
      'chat_id': chatId,
      'message_id': messageId,
      'reaction_type': {
        '@type': 'reactionTypeEmoji',
        'emoji': emoji.replaceAll(RegExp('[\uFE0E\uFE0F]'), ''),
      },
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

  Future<List<MessageReactionUser>> reactionUsers(
    ChatMessage message,
    MessageReaction reaction,
  ) async {
    final res = await _client.query({
      '@type': 'getMessageAddedReactions',
      'chat_id': chatId,
      'message_id': message.id,
      'reaction_type': reaction.type,
      'offset': '',
      'limit': 100,
    });
    final added = res.objects('reactions') ?? const <Map<String, dynamic>>[];
    final users = <MessageReactionUser>[];
    for (final item in added) {
      final senderId = _senderIdFromTd(item.obj('sender_id'));
      if (senderId == null) continue;
      final info = await _reactionSenderInfo(senderId);
      users.add(
        MessageReactionUser(
          senderId: senderId,
          title: info.name,
          photo: info.photo,
          date: item.integer('date') ?? 0,
        ),
      );
    }
    return users;
  }

  int? _senderIdFromTd(Map<String, dynamic>? sender) {
    return switch (sender?.type) {
      'messageSenderUser' => sender?.int64('user_id'),
      'messageSenderChat' => sender?.int64('chat_id'),
      _ => null,
    };
  }

  Future<_SenderInfo> _reactionSenderInfo(int senderId) async {
    final cached = _senderCache[senderId];
    if (cached != null) return cached;
    if (senderId > 0) {
      try {
        final user = await _client.query({
          '@type': 'getUser',
          'user_id': senderId,
        });
        return _SenderInfo(
          TDParse.userName(user),
          TDParse.smallPhoto(user.obj('profile_photo')),
          MemberRole.member,
          null,
        );
      } catch (_) {
        return _SenderInfo(
          AppStrings.t(AppStringKeys.chatUserFallbackName, {
            'value1': senderId,
          }),
          null,
          MemberRole.member,
          null,
        );
      }
    }
    try {
      final chat = await _client.query({
        '@type': 'getChat',
        'chat_id': senderId,
      });
      return _SenderInfo(
        chat.str('title') ?? telegramText(AppStringKeys.chatInfoGroupMembers),
        TDParse.smallPhoto(chat.obj('photo')),
        MemberRole.member,
        null,
      );
    } catch (_) {
      return _SenderInfo(
        telegramText(AppStringKeys.chatInfoGroupMembers),
        null,
        MemberRole.member,
        null,
      );
    }
  }

  void _restartTypingTimer() {
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 6), () {
      if (_chatActions.isNotEmpty) {
        _chatActions.clear();
        notifyListeners();
      }
    });
  }

  String get _chatActionSubtitle {
    if (_chatActions.isEmpty) return '';
    final actions = _chatActions.values.toList(growable: false);
    if (actions.length > 1) {
      final allTyping = actions.every(
        (a) => a.actionType == 'chatActionTyping',
      );
      return AppStrings.t(
        allTyping
            ? AppStringKeys.chatPeopleTyping
            : AppStringKeys.chatPeopleDoingAction,
        {'value1': actions.length},
      );
    }

    final action = actions.first;
    final label = _chatActionLabel(action.actionType);
    if (!isGroup) return label;
    final name = action.name.trim();
    if (name.isEmpty) return label;
    if (action.actionType == 'chatActionTyping') {
      return AppStrings.t(AppStringKeys.chatUserTyping, {'value1': name});
    }
    return AppStrings.t(AppStringKeys.chatUserDoingAction, {
      'value1': name,
      'value2': label,
    });
  }

  String _chatActionLabel(String type) {
    switch (type) {
      case 'chatActionRecordingVideo':
        return AppStrings.t(AppStringKeys.chatActionRecordingVideo);
      case 'chatActionUploadingVideo':
        return AppStrings.t(AppStringKeys.chatActionUploadingVideo);
      case 'chatActionRecordingVoiceNote':
        return AppStrings.t(AppStringKeys.chatActionRecordingVoice);
      case 'chatActionUploadingVoiceNote':
        return AppStrings.t(AppStringKeys.chatActionUploadingVoice);
      case 'chatActionUploadingPhoto':
        return AppStrings.t(AppStringKeys.chatActionUploadingPhoto);
      case 'chatActionUploadingDocument':
        return AppStrings.t(AppStringKeys.chatActionUploadingFile);
      case 'chatActionChoosingSticker':
        return AppStrings.t(AppStringKeys.chatActionChoosingSticker);
      case 'chatActionChoosingLocation':
        return AppStrings.t(AppStringKeys.chatActionChoosingLocation);
      case 'chatActionChoosingContact':
        return AppStrings.t(AppStringKeys.chatActionChoosingContact);
      case 'chatActionStartPlayingGame':
        return AppStrings.t(AppStringKeys.chatActionPlayingGame);
      case 'chatActionRecordingVideoNote':
        return AppStrings.t(AppStringKeys.chatActionRecordingVideoNote);
      case 'chatActionUploadingVideoNote':
        return AppStrings.t(AppStringKeys.chatActionUploadingVideoNote);
      case 'chatActionWatchingAnimations':
        return AppStrings.t(AppStringKeys.chatActionWatchingAnimations);
      case 'chatActionTyping':
      default:
        return AppStrings.t(AppStringKeys.chatTyping);
    }
  }

  String _statusLabel(String? type) {
    switch (type) {
      case 'userStatusOnline':
        return AppStrings.t(AppStringKeys.chatOnline);
      case 'userStatusRecently':
        return AppStrings.t(AppStringKeys.chatRecentlyOnline);
      case 'userStatusLastWeek':
        return AppStrings.t(AppStringKeys.chatOnlineWithinWeek);
      case 'userStatusLastMonth':
        return AppStrings.t(AppStringKeys.chatOnlineWithinMonth);
      default:
        return AppStrings.t(AppStringKeys.chatOffline);
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
    m.replyToDate = quoted.date;
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
    if (q.document != null) {
      return AppStrings.t(AppStringKeys.composerFilePreview, {
        'value1': q.document!.fileName,
      });
    }
    if (q.voice != null) {
      return telegramText(AppStringKeys.composerVoicePreview);
    }
    if (q.location != null) {
      return telegramText(AppStringKeys.composerLocationPreview);
    }
    if (q.isDice) {
      return q.diceEmoji ?? q.text;
    }
    if (q.isAnimatedEmoji) {
      return q.text;
    }
    if (q.animatedSticker != null) {
      return telegramText(AppStringKeys.composerAnimatedEmojiPreview);
    }
    if (q.image != null) {
      return q.text.isEmpty
          ? telegramText(AppStringKeys.composerImagePreview)
          : q.text;
    }
    return q.text;
  }

  // MARK: - Merge / mutate

  bool _isBlockedMessage(ChatMessage message) {
    if (message.isOutgoing || message.isService) return false;
    final senderId = message.senderId;
    if (senderId != null && _blockedSenderIds.contains(senderId)) return true;
    if (KeywordBlocker.shared.isSenderBlocked(senderId)) return true;
    return KeywordBlocker.shared.matches(message.text);
  }

  void _applyKeywordFilter() {
    messages =
        _allMessages.where((message) => !_isBlockedMessage(message)).toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    _markBlockedUserMessages();
    _markBlockedMessagesReadThroughVisibleBoundary();
    notifyListeners();
  }

  /// Mark messages from Telegram-blocked users so the renderer can show a
  /// compact placeholder instead of the full bubble.
  void _markBlockedUserMessages() {
    final svc = BlockedUserService.shared;
    if (!svc.enabled) {
      for (final m in messages) {
        m.blockedByUser = false;
      }
      return;
    }
    for (final m in messages) {
      m.blockedByUser = !m.isOutgoing &&
          !m.isService &&
          m.senderId != null &&
          svc.isBlocked(m.senderId!);
    }
  }

  void _markBlockedMessagesReadThroughVisibleBoundary() {
    if (_allMessages.isEmpty) return;
    final visibleMax = messages.isNotEmpty
        ? messages.last.id
        : _allMessages.last.id;
    final ids = _allMessages
        .where(
          (m) =>
              m.id <= visibleMax &&
              !_blockedReadIds.contains(m.id) &&
              _isBlockedMessage(m),
        )
        .map((m) => m.id)
        .toList();
    if (ids.isEmpty) return;
    _blockedReadIds.addAll(ids);
    for (var i = 0; i < ids.length; i += 100) {
      final end = i + 100 > ids.length ? ids.length : i + 100;
      final chunk = ids.sublist(i, end);
      _client.send({
        '@type': 'viewMessages',
        'chat_id': chatId,
        'message_ids': chunk,
        'force_read': true,
      });
    }
  }

  void _merge(List<ChatMessage> incoming) {
    if (incoming.isEmpty) return;
    final byId = {for (final m in _allMessages) m.id: m};
    for (final message in incoming) {
      if (_discardedPendingMessageIds.contains(message.id)) continue;
      final existing = byId[message.id];
      if (existing != null) {
        message.senderName ??= existing.senderName;
        message.senderPhoto ??= existing.senderPhoto;
        message.senderRole ??= existing.senderRole;
        message.senderTitle ??= existing.senderTitle;
      }
      byId[message.id] = message;
    }
    _allMessages = byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    _applyKeywordFilter();
  }

  void _replaceText(
    int messageId,
    String text, {
    bool edited = false,
    List<MessageTextEntity>? entities,
    List<CustomEmojiEntity>? customEmoji,
    MessageLinkPreview? linkPreview,
    bool updateLinkPreview = false,
  }) {
    final index = messages.indexWhere((m) => m.id == messageId);
    final allIndex = _allMessages.indexWhere((m) => m.id == messageId);
    if (index < 0 && allIndex < 0) return;
    final target = allIndex >= 0 ? _allMessages[allIndex] : messages[index];
    target.text = text;
    if (entities != null) target.textEntities = entities;
    if (customEmoji != null) target.customEmoji = customEmoji;
    if (updateLinkPreview) target.linkPreview = linkPreview;
    if (edited) target.isEdited = true;
    _applyKeywordFilter();
  }

  void _replacePendingMessage(
    int pendingMessageId,
    Map<String, dynamic> rawMessage,
  ) {
    if (_discardedPendingMessageIds.remove(pendingMessageId)) {
      final sentMessageId = rawMessage.int64('id');
      if (sentMessageId != null) {
        _discardedPendingMessageIds.add(sentMessageId);
        _removeMessages([pendingMessageId, sentMessageId]);
        unawaited(_deleteDiscardedPendingMessage(sentMessageId));
      } else {
        _removeMessages([pendingMessageId]);
      }
      return;
    }
    ChatMessage? pendingMessage;
    for (final message in _allMessages) {
      if (message.id == pendingMessageId) {
        pendingMessage = message;
        break;
      }
    }
    if (pendingMessage == null) {
      for (final message in messages) {
        if (message.id == pendingMessageId) {
          pendingMessage = message;
          break;
        }
      }
    }
    _allMessages.removeWhere((message) => message.id == pendingMessageId);
    messages.removeWhere((message) => message.id == pendingMessageId);
    final sentMessage = TDParse.message(rawMessage);
    if (sentMessage == null) {
      _applyKeywordFilter();
      return;
    }
    if (pendingMessage != null) {
      sentMessage.inheritLocalMediaFrom(pendingMessage);
    }
    _merge([sentMessage]);
    _resolveRichMessagesIfNeeded([sentMessage]);
    _resolveSendersIfNeeded([sentMessage]);
    _resolveRepliesIfNeeded([sentMessage]);
    _resolveForwardsIfNeeded([sentMessage]);
    _resolveServiceUsersIfNeeded([sentMessage]);
  }

  final Set<int> _loadingFullRichMessageIds = <int>{};

  void _replaceRichMessageContent(int messageId, Map<String, dynamic> content) {
    final refs = _messageRefs(messageId);
    if (refs.isEmpty) return;
    final full = content.obj('message')?.boolean('is_full') ?? false;
    final text = TDParse.richMessageDisplayText(content);
    final entities = TDParse.messageTextEntities(content);
    final blocks = TDParse.richMessageBlocks(content);
    final customEmoji = TDParse.customEmojiEntitiesForContent(content);
    for (final message in refs) {
      message.text = text;
      message.textEntities = entities;
      message.richBlocks = blocks;
      message.customEmoji = customEmoji;
      message.richMessageIsFull = full;
    }
    _applyKeywordFilter();
  }

  void _resolveRichMessagesIfNeeded(List<ChatMessage> candidates) {
    for (final message in candidates) {
      if (message.contentType != 'messageRichMessage' ||
          message.richMessageIsFull ||
          !_loadingFullRichMessageIds.add(message.id)) {
        continue;
      }
      unawaited(_loadFullRichMessage(message.id));
    }
  }

  Future<void> _loadFullRichMessage(int messageId) async {
    try {
      final richMessage = await _client.query({
        '@type': 'getFullRichMessage',
        'chat_id': chatId,
        'message_id': messageId,
      });
      _replaceRichMessageContent(messageId, {
        '@type': 'messageRichMessage',
        'message': richMessage,
      });
    } catch (error) {
      // Keep the partial placeholder; a later content/history update retries it.
      debugPrint('Failed to load full rich message $messageId: $error');
    } finally {
      _loadingFullRichMessageIds.remove(messageId);
    }
  }

  void _replaceButtonRows(int messageId, List<List<MessageButton>> buttonRows) {
    final index = messages.indexWhere((m) => m.id == messageId);
    final allIndex = _allMessages.indexWhere((m) => m.id == messageId);
    if (index < 0 && allIndex < 0) return;
    if (index >= 0) messages[index].buttonRows = buttonRows;
    if (allIndex >= 0) _allMessages[allIndex].buttonRows = buttonRows;
    notifyListeners();
  }

  void _setTranslationLoading(int messageId, bool loading) {
    final target = _messageRefs(messageId);
    if (target.isEmpty) return;
    for (final message in target) {
      message.isTranslating = loading;
    }
    notifyListeners();
  }

  void _replaceTranslation(
    int messageId,
    String text,
    List<MessageTextEntity> entities,
    String languageCode,
  ) {
    final target = _messageRefs(messageId);
    if (target.isEmpty) return;
    for (final message in target) {
      message.translationText = text;
      message.translationEntities = entities;
      message.translationLanguageCode = languageCode;
      message.isTranslating = false;
    }
    notifyListeners();
  }

  List<ChatMessage> _messageRefs(int messageId) {
    final refs = <ChatMessage>[];
    final index = messages.indexWhere((m) => m.id == messageId);
    final allIndex = _allMessages.indexWhere((m) => m.id == messageId);
    if (index >= 0) refs.add(messages[index]);
    if (allIndex >= 0 &&
        (index < 0 || !identical(messages[index], _allMessages[allIndex]))) {
      refs.add(_allMessages[allIndex]);
    }
    return refs;
  }

  void _removeMessages(List<int> ids) {
    if (ids.isEmpty) return;
    final removed = ids.toSet();
    _allMessages.removeWhere((m) => removed.contains(m.id));
    messages.removeWhere((m) => removed.contains(m.id));
    _blockedReadIds.removeWhere(removed.contains);
    if (replyTo != null && removed.contains(replyTo!.id)) replyTo = null;
    if (pinnedMessages.any((m) => removed.contains(m.id))) {
      pinnedMessages = pinnedMessages
          .where((m) => !removed.contains(m.id))
          .toList();
      pinnedMessageIndex = pinnedMessageIndex.clamp(
        0,
        math.max(0, pinnedMessages.length - 1),
      );
      pinnedMessage = pinnedMessages.isEmpty
          ? null
          : pinnedMessages[pinnedMessageIndex];
      pinnedDismissed = pinnedMessage == null ? false : pinnedDismissed;
    }
    notifyListeners();
  }

  void _patchSender(_SenderInfo info, int senderId) {
    var changed = false;
    for (final m in messages) {
      if (m.senderId != senderId || m.isOutgoing) continue;
      if (m.senderName == info.name &&
          m.senderRole == info.role &&
          m.senderTitle == (info.title ?? m.senderTitle) &&
          m.senderIsPremium == info.isPremium &&
          m.senderAccentColorId == info.accentColorId &&
          m.senderEmojiStatusId == info.emojiStatusId) {
        continue;
      }
      m.senderName = info.name;
      m.senderPhoto = info.photo;
      m.senderRole = info.role;
      m.senderTitle = info.title ?? m.senderTitle;
      m.senderIsPremium = info.isPremium;
      m.senderAccentColorId = info.accentColorId;
      m.senderEmojiStatusId = info.emojiStatusId;
      changed = true;
    }
    if (changed) _scheduleSenderPatchNotify();
  }

  void _scheduleSenderPatchNotify() {
    if (_isDisposed) return;
    if (_senderPatchTimer != null) return;
    _senderPatchTimer = Timer(const Duration(milliseconds: 16), () {
      _senderPatchTimer = null;
      notifyListeners();
    });
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

  void _resolveServiceUsersIfNeeded(List<ChatMessage> batch) {
    for (final message in batch) {
      if (!message.isService || message.serviceUserIds.isEmpty) continue;
      switch (message.contentType) {
        case 'messageChatAddMembers':
        case 'messageChatJoinByLink':
        case 'messageChatJoinByRequest':
          _resolveJoinServiceText(message);
        case 'messageChatDeleteMember':
          _resolveDeleteMemberServiceText(message);
      }
    }
  }

  Future<void> _resolveJoinServiceText(ChatMessage message) async {
    final names = <String>[];
    for (final userId in message.serviceUserIds.take(5)) {
      try {
        final user = await _client.query({
          '@type': 'getUser',
          'user_id': userId,
        });
        final name = TDParse.userName(user);
        if (name.isNotEmpty) names.add(name);
      } catch (_) {}
    }
    if (names.isEmpty) return;
    final suffix = message.serviceUserIds.length > names.length
        ? AppStrings.t(AppStringKeys.chatAndOthersCount, {
            'value1': message.serviceUserIds.length,
          })
        : '';
    final text = AppStrings.t(AppStringKeys.chatUsersJoinedGroup, {
      'value1': names.join(AppStrings.t(AppStringKeys.listSeparator)),
      'value2': suffix,
    });
    final index = messages.indexWhere((m) => m.id == message.id);
    if (index < 0 || messages[index].text == text) return;
    messages[index].text = text;
    notifyListeners();
  }

  Future<void> _resolveDeleteMemberServiceText(ChatMessage message) async {
    if (message.serviceUserIds.isEmpty) return;
    try {
      final user = await _client.query({
        '@type': 'getUser',
        'user_id': message.serviceUserIds.first,
      });
      final name = TDParse.userName(user);
      if (name.isEmpty) return;
      final text = AppStrings.t(AppStringKeys.chatUserLeftGroup, {
        'value1': name,
      });
      final index = messages.indexWhere((m) => m.id == message.id);
      if (index < 0 || messages[index].text == text) return;
      messages[index].text = text;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _resolveSender(int senderId) async {
    _SenderInfo info;
    if (senderId > 0) {
      String name;
      TdFileRef? photo;
      var isPremium = false;
      var accentColorId = -1;
      var emojiStatusId = 0;
      try {
        final user = await _client.query({
          '@type': 'getUser',
          'user_id': senderId,
        });
        name = TDParse.userName(user);
        photo = TDParse.smallPhoto(user.obj('profile_photo'));
        isPremium = user.boolean('is_premium') ?? false;
        accentColorId = user.integer('accent_color_id') ?? -1;
        emojiStatusId =
            user.obj('emoji_status')?.obj('type')?.int64('custom_emoji_id') ??
            user.obj('emoji_status')?.int64('custom_emoji_id') ??
            0;
      } catch (_) {
        name = AppStrings.t(AppStringKeys.chatUserFallbackName, {
          'value1': senderId,
        });
        photo = null;
      }
      final role = isChannel
          ? (MemberRole.member, null)
          : await _resolveRole(senderId);
      info = _SenderInfo(
        name,
        photo,
        role.$1,
        role.$2,
        isPremium: isPremium,
        accentColorId: accentColorId,
        emojiStatusId: emojiStatusId,
      );
    } else {
      try {
        final chat = await _client.query({
          '@type': 'getChat',
          'chat_id': senderId,
        });
        info = _SenderInfo(
          chat.str('title') ?? telegramText(AppStringKeys.chatInfoGroupMembers),
          TDParse.smallPhoto(chat.obj('photo')),
          MemberRole.member,
          null,
        );
      } catch (_) {
        info = _SenderInfo(
          telegramText(AppStringKeys.chatInfoGroupMembers),
          null,
          MemberRole.member,
          null,
        );
      }
    }
    if (_isDisposed) return;
    _senderCache[senderId] = info;
    final activeAction = _chatActions[senderId];
    if (activeAction != null && activeAction.name.isEmpty) {
      _chatActions[senderId] = _ChatActionInfo(
        info.name,
        activeAction.actionType,
      );
    }
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
      final cleanTitle = _memberTitle(member, status);
      switch (status?.type) {
        case 'chatMemberStatusCreator':
          return (MemberRole.owner, cleanTitle);
        case 'chatMemberStatusAdministrator':
          return (MemberRole.admin, cleanTitle);
        default:
          return (MemberRole.member, cleanTitle);
      }
    } catch (_) {
      return (MemberRole.member, null);
    }
  }

  String? _memberTitle(
    Map<String, dynamic> member,
    Map<String, dynamic>? status,
  ) {
    final raw =
        status?.str('custom_title') ??
        member.str('custom_title') ??
        member.str('tag') ??
        status?.str('title') ??
        member.str('title');
    final title = raw?.trim();
    return title == null || title.isEmpty ? null : title;
  }
}
