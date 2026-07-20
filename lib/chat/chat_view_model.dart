//
//  chat_view_model.dart
//
//  Conversation view model. Opens a chat, loads history, and keeps the message
//  list live by folding TDLib updates. For groups/channels it resolves each
//  incoming message's sender name + photo + role through a small cache so
//  bubbles can show "who said what". Port of the Swift `ChatViewModel`.
//

import 'dart:async';
import 'dart:io';
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
import '../tdlib/td_requests.dart';
import '../tdlib/td_user_index.dart';
import 'chat_first_contact_info.dart';
import 'chat_message_merge.dart';
import 'chat_unread_progress.dart';
import 'checklist_composer_view.dart';
import 'checklist_service.dart';
import 'forward_options.dart';
import 'gif_item.dart';
import 'message_send_options.dart';
import 'outgoing_attachment.dart';
import 'poll_composer_view.dart';
import 'rich_message_source.dart';
import 'secret_chat_service.dart';
import 'sponsored_messages_cache.dart';
import 'sticker_item.dart';
import 'telegram_ai_service.dart';
import 'unread_chat_summary_models.dart';

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

@visibleForTesting
int unreadMentionCountAfterReading(int currentCount, int readCount) =>
    math.max(0, currentCount - math.max(0, readCount));

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

class MentionCandidate {
  const MentionCandidate({
    required this.userId,
    required this.name,
    this.username = '',
    this.photo,
  });

  final int userId;
  final String name;
  final String username;
  final TdFileRef? photo;
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
  bool get isLegacyMenuUrl => url.startsWith('menu://');
  String get webAppUrl => isLegacyMenuUrl ? '' : url;
  String get actionTitle => text.trim().isEmpty ? 'Open' : text.trim();
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
    this.sessionAnchorMessageId,
    List<ChatMessage>? sessionMessages,
    bool sessionAnchoredHistory = false,
    ChatFirstContactInfo? sessionFirstContactInfo,
    ChatMessage? seedMessage,
  }) : peerTitle = title {
    if (sessionMessages != null && sessionMessages.isNotEmpty) {
      _allMessages = List<ChatMessage>.from(sessionMessages);
      messages = List<ChatMessage>.from(sessionMessages);
      anchoredHistory = sessionAnchoredHistory;
      firstContactInfo = sessionFirstContactInfo;
      initialLoaded = true;
      _restoredFromSession = true;
    } else if (seedMessage != null) {
      _allMessages = [seedMessage];
      messages = [seedMessage];
    }
  }

  final int chatId;
  final int? initialMessageId;
  final int? sessionAnchorMessageId;
  final bool markReadOnOpen;

  List<ChatMessage> messages = [];
  List<ChatMessage> _allMessages = [];
  String peerTitle;
  TdFileRef? peerPhoto;
  ChatFirstContactInfo? firstContactInfo;
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
  UnreadChatRangeSnapshot? unreadSummarySnapshot;
  bool _didCaptureUnreadSummaryRange = false;
  int unreadMentionCount = 0;
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
  bool isDirectMessagesGroup = false;
  bool isAdministeredDirectMessagesGroup = false;
  bool isMuted =
      false; // notifications muted (channel subscribers get a toggle)
  bool canDeleteMessagesBySender = false;
  String sendDisabledReason = ''; // shown in the disabled composer bar
  bool isPeerRestricted = false;
  bool isPeerPornographicRestricted = false;
  String peerRestrictionText = '';
  bool hasProtectedContent = false;
  bool _chatCanSend = true; // chat-wide default can_send_basic_messages
  bool peerIsBot = false;
  bool isSecretChat = false;
  int businessBotUserId = 0;
  String businessBotManageUrl = '';
  bool businessBotPaused = false;
  bool businessBotCanReply = false;
  int? _secretChatId;
  bool botStartSent = false;
  BotMenuInfo? botMenu;
  List<BotCommandOption> botCommands = const [];
  bool isForum = false;
  bool forumTopicsLoading = false;
  List<ForumTopicOption> forumTopics = const [];
  int messageAutoDeleteTime = 0;
  int paidMessageStarCount = 0;

  /// Loaded for channels and bot chats, but not yet rendered in the transcript.
  SponsoredMessagesSnapshot? sponsoredMessages;

  final TdClient _client = TdClient.shared;
  late final TelegramAiService telegramAi = TelegramAiService(client: _client);
  TelegramAiCapabilities? aiCapabilities;
  static final SponsoredMessagesCache _sponsoredMessagesCache =
      SponsoredMessagesCache();
  StreamSubscription? _sub;
  final ChatLiveMessageBuffer _liveIncomingMessages = ChatLiveMessageBuffer();
  bool _isLoadingOlder = false;
  bool _hasOlderHistory = true;
  int? _pendingScrollToId;
  int? _lastForcedReadMessageId;
  bool _markReadInFlight = false;
  bool _restoredFromSession = false;
  bool _historyReachesLatest = false;
  int _knownLatestMessageId = 0;
  bool _latestHistoryLoadInFlight = false;
  final Map<int, ChatMessage> _latestHistoryLiveArrivals = {};
  final Set<int> _latestHistoryDeletedMessageIds = {};
  bool _latestHistoryLoadInvalidated = false;
  int _historyWindowGeneration = 0;
  int _historyWindowRevision = 0;
  int get historyWindowRevision => _historyWindowRevision;
  int _historyWindowInvalidationRevision = 0;
  int get historyWindowInvalidationRevision =>
      _historyWindowInvalidationRevision;
  final Set<int> _blockedReadIds = {};
  final Set<int> _messagePropertiesLoading = {};
  final Map<int, bool> _speechRecognitionEligibility = {};
  final Set<int> _locallyViewedMentionIds = {};
  final Set<int> _blockedSenderIds = {};
  final Set<int> _discardedPendingMessageIds = {};
  final Set<int> _settledPendingMessageIds = {};
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
              ? telegramPresenceText(TelegramPresenceLabel.online)
              : peerStatusText);
    final action = _chatActionSubtitle;
    if (base.isEmpty) return action;
    if (action.isEmpty) return base;
    return '$base · $action';
  }

  bool get hasActiveChatAction => _chatActions.isNotEmpty;

  bool isRead(ChatMessage m) => isOutgoingServerMessageRead(
    message: m,
    lastReadOutboxId: lastReadOutboxId,
  );
  bool get canChooseMessageSender => availableMessageSenders.length > 1;
  bool get canForwardContent => !hasProtectedContent;
  bool get canLoadOlder =>
      !_isLoadingOlder && _allMessages.isNotEmpty && _hasOlderHistory;
  bool get isLoadingOlder => _isLoadingOlder;
  bool get hasOlderHistory => _hasOlderHistory;
  int get _oldestServerMessageId {
    for (final message in _allMessages) {
      if (!isPendingChatMessage(message) && message.id > 0) return message.id;
    }
    return 0;
  }

  bool get requiresPaidMessage => paidMessageStarCount > 0;
  bool get canUseAiComposition =>
      aiCapabilities?.compositionSupported == true && !isSecretChat;
  bool get canUseAiSummary => aiCapabilities?.summarySupported == true;
  bool get canUseSpeechRecognition =>
      aiCapabilities?.transcriptionSupported == true;
  bool get canSendWhenOnline => !isGroup && !peerIsBot;
  List<AvailableMessageEffect> availableMessageEffects = const [];
  MessageSendConfiguration? _nextSendConfiguration;
  String get inputPlaceholder => messageAutoDeleteTime > 0
      ? AppStrings.t(AppStringKeys.chatAutoDeleteCountdown, {
          'value1': TDParse.formatDuration(messageAutoDeleteTime),
        })
      : AppStrings.t(AppStringKeys.chatMessageInputPlaceholder);

  final Map<int, _SenderInfo> _senderCache = {};
  final Set<int> _resolvingSenders = {};
  final Set<int> _resolvedSenderDetails = {};
  bool _isDisposed = false;

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  int? consumePendingScrollToId() {
    final id = _pendingScrollToId;
    _pendingScrollToId = null;
    return id;
  }

  List<int> consumeLiveIncomingMessageIds() => _liveIncomingMessages.takeAll();

  void useNextSendConfiguration(MessageSendConfiguration configuration) {
    _nextSendConfiguration = configuration;
  }

  Map<String, dynamic> _withPaidMessageOptions(
    Map<String, dynamic> request, {
    MessageSendConfiguration? sendConfiguration,
    bool consumePendingConfiguration = true,
  }) {
    final count = paidMessageStarCount;
    final pending = sendConfiguration ?? _nextSendConfiguration;
    if (consumePendingConfiguration && sendConfiguration == null) {
      _nextSendConfiguration = null;
    }
    final existing = request.obj('options') ?? const <String, dynamic>{};
    if (count > 0 || pending != null || existing.isNotEmpty) {
      request['options'] = {
        if (pending != null)
          ...pending.messageSendOptions(paidStarCount: count),
        ...existing,
        '@type': 'messageSendOptions',
        if (count > 0) 'paid_message_star_count': count,
      };
    }
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
      unawaited(_loadAiCapabilities());
      await _loadChatHeader();
      if (_restoredFromSession) {
        unawaited(_discardStaleRestoredPendingMessages());
        _resolveRichMessagesIfNeeded(messages);
        _resolveSendersIfNeeded(messages);
        _resolveRepliesIfNeeded(messages);
        _resolveForwardsIfNeeded(messages);
        _resolveServiceUsersIfNeeded(messages);
        notifyListeners();
        if (!anchoredHistory) {
          unawaited(_hydrateRestoredLatestHistory());
        }
        unawaited(_loadAvailableMessageSenders());
        return;
      }
      final target = initialMessageId;
      if (target != null) {
        await loadAroundMessage(target);
      } else if (sessionAnchorMessageId != null) {
        final restored = await loadAroundMessage(
          sessionAnchorMessageId!,
          scrollToTarget: false,
          onlyLocal: true,
        );
        if (!restored) {
          await _loadInitialHistory(openAtLatest: markReadOnOpen);
        }
      } else {
        await _loadInitialHistory(openAtLatest: markReadOnOpen);
      }
      initialLoaded = true;
      notifyListeners();
      unawaited(_loadAvailableMessageSenders());
    }();
  }

  Future<void> _loadAiCapabilities() async {
    try {
      aiCapabilities = await telegramAi.capabilities();
      notifyListeners();
    } catch (_) {
      // Capability discovery is optional. Unsupported servers keep all AI
      // entry points hidden instead of exposing actions that will fail.
    }
  }

  void ensureMessageCapabilities(ChatMessage message) {
    if (message.contentType != 'messageVoiceNote' &&
        message.contentType != 'messageVideoNote') {
      return;
    }
    final cached = _speechRecognitionEligibility[message.id];
    if (cached != null) {
      message.canRecognizeSpeech = cached;
      return;
    }
    if (!_messagePropertiesLoading.add(message.id)) return;
    unawaited(_loadMessageCapabilities(message.id));
  }

  Future<void> _loadMessageCapabilities(int messageId) async {
    try {
      final properties = await _client.query({
        '@type': 'getMessageProperties',
        'chat_id': chatId,
        'message_id': messageId,
      });
      final eligible = properties.boolean('can_recognize_speech') ?? false;
      _speechRecognitionEligibility[messageId] = eligible;
      for (final target in _messageRefs(messageId)) {
        target.canRecognizeSpeech = eligible;
      }
      notifyListeners();
    } catch (_) {
      _speechRecognitionEligibility[messageId] = false;
    } finally {
      _messagePropertiesLoading.remove(messageId);
    }
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
    telegramAi.dispose();
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
      _client.send(
        setTextChatDraftRequest(
          chatId: chatId,
          formattedText: null,
          date: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ),
      );
      return;
    }

    final allEntities = [
      ..._draftFormattedEntities,
      ..._mentionEntitiesFor(text, _draftFormattedEntities),
    ];
    if (_lastSavedDraftText == text && allEntities.isEmpty) return;
    _lastSavedDraftText = text;
    _client.send(
      setTextChatDraftRequest(
        chatId: chatId,
        date: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        formattedText: {
          '@type': 'formattedText',
          'text': text,
          if (allEntities.isNotEmpty) 'entities': allEntities,
        },
      ),
    );
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

  Future<List<MentionCandidate>> searchMentionCandidates(String query) async {
    if (!isGroup) return const [];
    try {
      final result = await _client.query({
        '@type': 'searchChatMembers',
        'chat_id': chatId,
        'query': query.trim(),
        'limit': 50,
        'filter': {'@type': 'chatMembersFilterMembers'},
      });
      final members = result.objects('members') ?? const [];
      final resolved = await Future.wait(
        members.map(_mentionCandidateFromMember),
      );
      return resolved.whereType<MentionCandidate>().toList(growable: false);
    } catch (_) {
      return _recentMentionCandidates(query);
    }
  }

  Future<MentionCandidate?> _mentionCandidateFromMember(
    Map<String, dynamic> member,
  ) async {
    final sender = member.obj('member_id');
    if (sender?.type != 'messageSenderUser') return null;
    final userId = sender?.int64('user_id');
    if (userId == null || userId <= 0) return null;
    try {
      final user = await _client.query({'@type': 'getUser', 'user_id': userId});
      final name = TDParse.userName(user).trim();
      if (name.isEmpty) return null;
      final usernames = user.obj('usernames');
      final active = usernames?['active_usernames'];
      final activeUsernames = active is List
          ? active.whereType<String>().toList(growable: false)
          : const <String>[];
      final username = activeUsernames.isNotEmpty
          ? activeUsernames.first
          : usernames?.str('editable_username') ?? '';
      return MentionCandidate(
        userId: userId,
        name: name.startsWith('@') ? name.substring(1) : name,
        username: username,
        photo: TDParse.smallPhoto(user.obj('profile_photo')),
      );
    } catch (_) {
      return null;
    }
  }

  List<MentionCandidate> _recentMentionCandidates(String query) {
    final normalized = query.trim().toLowerCase();
    final seen = <int>{};
    final result = <MentionCandidate>[];
    for (final message in messages.reversed) {
      final userId = message.senderId;
      final name = message.senderName?.trim() ?? '';
      if (userId == null || userId <= 0 || name.isEmpty || !seen.add(userId)) {
        continue;
      }
      if (normalized.isNotEmpty && !name.toLowerCase().contains(normalized)) {
        continue;
      }
      result.add(
        MentionCandidate(
          userId: userId,
          name: name,
          photo: message.senderPhoto,
        ),
      );
      if (result.length == 30) break;
    }
    return result;
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
    if (!canSendMessages) return;
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

  Future<void> sendSuggestedPost({
    required String text,
    OutgoingAttachment? attachment,
    SuggestedPostPrice? price,
    int sendDate = 0,
  }) async {
    if (!canSendMessages || !isDirectMessagesGroup) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachment == null) return;
    Map<String, dynamic> content;
    if (attachment == null) {
      content = {
        '@type': 'inputMessageText',
        'text': {'@type': 'formattedText', 'text': trimmed},
      };
    } else {
      final resolved = await resolveAttachmentDimensions(attachment);
      content = attachmentInputMessageContent(resolved, caption: trimmed);
    }
    final request = <String, dynamic>{
      '@type': 'sendMessage',
      'chat_id': chatId,
      'options': {
        '@type': 'messageSendOptions',
        'suggested_post_info': {
          '@type': 'inputSuggestedPostInfo',
          'price': price?.toTdJson(),
          'send_date': sendDate,
        },
      },
      'input_message_content': content,
    };
    final response = await _client.query(_withPaidMessageOptions(request));
    final message = TDParse.message(response);
    if (message != null) {
      _merge([message]);
      _resolveSendersIfNeeded([message]);
    }
  }

  Future<void> addSuggestedPostOffer(
    int messageId, {
    SuggestedPostPrice? price,
    int sendDate = 0,
  }) async {
    if (!isDirectMessagesGroup) return;
    await _client.query({
      '@type': 'addOffer',
      'chat_id': chatId,
      'message_id': messageId,
      'options': {
        '@type': 'messageSendOptions',
        'suggested_post_info': {
          '@type': 'inputSuggestedPostInfo',
          'price': price?.toTdJson(),
          'send_date': sendDate,
        },
      },
    });
    await _refreshMessage(messageId);
  }

  bool sendBotStart() {
    if (!peerIsBot) return false;
    _clearDraft();
    botStartSent = true;
    _sendText('/start');
    notifyListeners();
    return true;
  }

  void _sendText(String text) {
    if (!canSendMessages) return;
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
    if (!canSendMessages) return;
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
    List<Map<String, dynamic>> blocks = const [],
  }) async {
    if (blocks.isEmpty) {
      throw StateError('Rich message blocks are required for user accounts');
    }
    for (final file in files) {
      if ((file.attachment.fileId ?? 0) > 0) continue;
      final localFile = File(file.attachment.path);
      if (!await localFile.exists() || await localFile.length() <= 0) {
        throw StateError('Unable to read rich message media');
      }
    }
    _clearDraft();
    final request = <String, dynamic>{
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': richMessageInputContent(blocks),
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

  Future<int> currentUserId() async {
    final user = await _client.query({'@type': 'getMe'});
    final id = user.int64('id');
    if (id == null || id <= 0) throw StateError('Current user is unavailable');
    return id;
  }

  Future<void> _waitForMessageSend(
    int pendingMessageId, {
    Duration timeout = const Duration(seconds: 15),
  }) {
    final recent = _recentMessageSendResults.remove(pendingMessageId);
    if (recent != null) {
      final error = recent.error;
      return error == null ? Future.value() : Future.error(error);
    }
    final waiter = Completer<void>();
    _messageSendWaiters[pendingMessageId] = waiter;
    return waiter.future
        .timeout(
          timeout,
          onTimeout: () {
            // A timeout means TDLib has not reported the final state yet. It
            // does not mean the accepted message failed. In particular, do
            // not mark it discarded: a late updateMessageSendSucceeded would
            // otherwise delete the newly assigned server message id.
            debugPrint(
              'Message $pendingMessageId is still pending; keeping it until '
              'TDLib reports success or failure',
            );
          },
        )
        .whenComplete(() {
          if (identical(_messageSendWaiters[pendingMessageId], waiter)) {
            _messageSendWaiters.remove(pendingMessageId);
          }
        });
  }

  @visibleForTesting
  Future<void> waitForMessageSendTimeoutForTest(
    int pendingMessageId, {
    required Duration timeout,
  }) => _waitForMessageSend(pendingMessageId, timeout: timeout);

  @visibleForTesting
  bool isPendingMessageDiscardedForTest(int pendingMessageId) =>
      _discardedPendingMessageIds.contains(pendingMessageId);

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

  /// Sets or clears the reply target without changing the current draft.
  ///
  /// The reply metadata already addresses the sender. Mentions remain an
  /// explicit action so replying cannot accidentally invoke inline-bot search.
  void setReply(ChatMessage? message) {
    replyTo = message;
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
    MessageSendConfiguration sendConfiguration =
        const MessageSendConfiguration(),
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
      sendConfiguration: sendConfiguration,
    );
    replyTo = null;
    _clearDraft();
    notifyListeners();
    for (final request in requests) {
      await _client.query(
        _withPaidMessageOptions(
          request,
          sendConfiguration: sendConfiguration,
          consumePendingConfiguration: false,
        ),
      );
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
          'animation': {
            '@type': 'inputAnimation',
            'animation': {'@type': 'inputFileLocal', 'path': path},
            'duration': 0,
            'width': 0,
            'height': 0,
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

  Future<bool> sendGif(GifItem gif) async {
    if (!canSendMessages) return false;
    try {
      final pendingMessage = await _client.query(
        _withPaidMessageOptions(gifSendRequest(chatId: chatId, gif: gif)),
      );
      final pendingMessageId = pendingMessage.int64('id');
      if (pendingMessageId != null &&
          pendingMessage.obj('sending_state') != null) {
        await _waitForMessageSend(pendingMessageId);
      }
      return true;
    } catch (error) {
      debugPrint('Failed to send GIF: $error');
      return false;
    }
  }

  Future<bool> sendSticker(StickerItem sticker) async {
    if (!canSendMessages) return false;
    try {
      final pendingMessage = await _client.query(
        stickerMessageRequest(sticker),
      );
      final pendingMessageId = pendingMessage.int64('id');
      if (pendingMessageId != null &&
          pendingMessage.obj('sending_state') != null) {
        await _waitForMessageSend(pendingMessageId);
      }
      return true;
    } catch (error) {
      debugPrint('Failed to send sticker: $error');
      return false;
    }
  }

  @visibleForTesting
  Map<String, dynamic> stickerMessageRequest(StickerItem sticker) {
    final remoteId = sticker.remoteId?.trim();
    final inputFile = remoteId != null && remoteId.isNotEmpty
        ? {'@type': 'inputFileRemote', 'id': remoteId}
        : {'@type': 'inputFileId', 'id': sticker.id};
    return _withPaidMessageOptions({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessageSticker',
        // The bundled TDLib schema carries sticker file metadata in an
        // inputSticker object rather than directly on inputMessageSticker.
        'sticker': {
          '@type': 'inputSticker',
          'sticker': inputFile,
          'width': sticker.width,
          'height': sticker.height,
        },
        'emoji': sticker.emoji,
      },
    });
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

  Future<bool> sendVenue({
    required double latitude,
    required double longitude,
    required String title,
    required String address,
  }) async {
    final venueTitle = title.trim();
    if (venueTitle.isEmpty) return false;
    try {
      await _client.query(
        _withPaidMessageOptions({
          '@type': 'sendMessage',
          'chat_id': chatId,
          'input_message_content': {
            '@type': 'inputMessageVenue',
            'venue': {
              '@type': 'venue',
              'location': {
                '@type': 'location',
                'latitude': latitude,
                'longitude': longitude,
                'horizontal_accuracy': 0,
              },
              'title': venueTitle,
              'address': address.trim(),
              'provider': '',
              'id': '',
              'type': '',
            },
          },
        }),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sendContact(MessageContactCard contact) async {
    if (contact.phoneNumber.trim().isEmpty) return false;
    try {
      await _client.query(
        _withPaidMessageOptions({
          '@type': 'sendMessage',
          'chat_id': chatId,
          'input_message_content': {
            '@type': 'inputMessageContact',
            'contact': {
              '@type': 'contact',
              'phone_number': contact.phoneNumber,
              'first_name': contact.firstName,
              'last_name': contact.lastName,
              'vcard': contact.vcard,
              'user_id': contact.userId,
            },
          },
        }),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sendVoice(
    String path,
    int duration, {
    String waveform = '',
    MessageSendConfiguration sendConfiguration =
        const MessageSendConfiguration(),
  }) async {
    try {
      await _client.query(
        _withPaidMessageOptions({
          '@type': 'sendMessage',
          'chat_id': chatId,
          'input_message_content': {
            '@type': 'inputMessageVoiceNote',
            'voice_note': {
              '@type': 'inputVoiceNote',
              'voice_note': {'@type': 'inputFileLocal', 'path': path},
              'duration': duration,
              'waveform': waveform,
            },
            'self_destruct_type': ?sendConfiguration.selfDestructType,
          },
        }, sendConfiguration: sendConfiguration),
      );
      return true;
    } catch (error) {
      debugPrint('Failed to send voice note: $error');
      return false;
    }
  }

  Future<bool> sendVideoNote(
    String path,
    int duration, {
    MessageSendConfiguration sendConfiguration =
        const MessageSendConfiguration(),
  }) async {
    try {
      await _client.query(
        _withPaidMessageOptions({
          '@type': 'sendMessage',
          'chat_id': chatId,
          'input_message_content': {
            '@type': 'inputMessageVideoNote',
            'video_note': {
              '@type': 'inputVideoNote',
              'video_note': {'@type': 'inputFileLocal', 'path': path},
              'duration': duration,
              'length': 0,
            },
            'self_destruct_type': ?sendConfiguration.selfDestructType,
          },
        }, sendConfiguration: sendConfiguration),
      );
      return true;
    } catch (error) {
      debugPrint('Failed to send video note: $error');
      return false;
    }
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
    await assertForwardAllowed(
      query: _client.query,
      fromChatId: sourceChatId,
      messageIds: [message.id],
      options: const ForwardOptions(removeSender: true),
    );
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
  void sendChecklist(ChecklistComposerResult draft) {
    if (draft.title.trim().isEmpty || draft.tasks.isEmpty) return;
    _client.send(
      _withPaidMessageOptions({
        '@type': 'sendMessage',
        'chat_id': chatId,
        'input_message_content': {
          '@type': 'inputMessageChecklist',
          'checklist': ChecklistRequests.inputChecklist(draft),
        },
      }),
    );
  }

  Future<void> editChecklist(
    ChatMessage message,
    ChecklistComposerResult draft,
  ) async {
    final checklist = message.checklist;
    if (checklist == null) return;
    await _client.query(
      ChecklistRequests.edit(
        chatId: chatId,
        messageId: message.id,
        original: checklist,
        draft: draft,
      ),
    );
    await _refreshMessage(message.id);
  }

  Future<int> pollAnswerCountMax() async {
    try {
      final option = await _client.query({
        '@type': 'getOption',
        'name': 'poll_answer_count_max',
      });
      return (option.integer('value') ?? 30).clamp(2, 100);
    } catch (_) {
      return 30;
    }
  }

  Future<bool> sendPoll(PollComposerResult draft) async {
    final question = draft.question.trim();
    final options = draft.options
        .where((option) => option.text.trim().isNotEmpty)
        .toList(growable: false);
    if (question.isEmpty || options.length < 2) return false;
    if (draft.isQuiz && draft.correctOptionIndexes.isEmpty) return false;
    try {
      await _client.query(
        _withPaidMessageOptions({
          '@type': 'sendMessage',
          'chat_id': chatId,
          'input_message_content': {
            '@type': 'inputMessagePoll',
            'question': {'@type': 'formattedText', 'text': question},
            'options': [
              for (final option in options)
                {
                  '@type': 'inputPollOption',
                  'text': {
                    '@type': 'formattedText',
                    'text': option.text.trim(),
                  },
                  if (option.mediaPath case final path?)
                    'media': _inputPollPhoto(path),
                },
            ],
            if (draft.description.trim().isNotEmpty)
              'description': {
                '@type': 'formattedText',
                'text': draft.description.trim(),
              },
            if (draft.pollMediaPath case final path?)
              'media': _inputPollPhoto(path),
            'is_anonymous': draft.isAnonymous,
            'allows_multiple_answers': draft.allowsMultipleAnswers,
            'allows_revoting': draft.allowsRevoting,
            'shuffle_options': draft.shuffleOptions,
            'hide_results_until_closes': draft.hideResultsUntilCloses,
            'type': draft.isQuiz
                ? {
                    '@type': 'inputPollTypeQuiz',
                    'correct_option_ids': draft.correctOptionIndexes.toList()
                      ..sort(),
                    'explanation': {
                      '@type': 'formattedText',
                      'text': draft.explanation.trim(),
                    },
                  }
                : {
                    '@type': 'inputPollTypeRegular',
                    'allow_adding_options': draft.allowAddingOptions,
                  },
            'open_period': draft.openPeriod,
          },
        }),
      );
      return true;
    } catch (error) {
      debugPrint('Failed to send poll: $error');
      return false;
    }
  }

  Map<String, dynamic> _inputPollPhoto(String path) => {
    '@type': 'inputPollMediaPhoto',
    'photo': {
      '@type': 'inputPhoto',
      'photo': {'@type': 'inputFileLocal', 'path': path},
    },
  };

  Future<void> addPollOption(ChatMessage message, String text) async {
    final value = text.trim();
    if (message.poll == null || value.isEmpty) return;
    await _client.query({
      '@type': 'addPollOption',
      'chat_id': chatId,
      'message_id': message.id,
      'option': {
        '@type': 'inputPollOption',
        'text': {'@type': 'formattedText', 'text': value},
      },
    });
    await _refreshMessage(message.id);
  }

  Future<void> recognizeSpeech(ChatMessage message) async {
    if (!canUseSpeechRecognition) {
      throw StateError('SPEECH_RECOGNITION_UNAVAILABLE');
    }
    final properties = await _client.query({
      '@type': 'getMessageProperties',
      'chat_id': chatId,
      'message_id': message.id,
    });
    if (properties.boolean('can_recognize_speech') != true) {
      _speechRecognitionEligibility[message.id] = false;
      for (final target in _messageRefs(message.id)) {
        target.canRecognizeSpeech = false;
      }
      notifyListeners();
      throw StateError('SPEECH_RECOGNITION_UNAVAILABLE');
    }
    await _client.query({
      '@type': 'recognizeSpeech',
      'chat_id': chatId,
      'message_id': message.id,
    });
    await _refreshMessage(message.id);
  }

  Future<Map<String, dynamic>> pollVoteStatistics(
    ChatMessage message, {
    required bool isDark,
  }) => _client.query({
    '@type': 'getPollVoteStatistics',
    'chat_id': chatId,
    'message_id': message.id,
    'is_dark': isDark,
  });

  Future<List<Map<String, dynamic>>> pollVoters(
    ChatMessage message,
    int optionIndex, {
    int offset = 0,
  }) async {
    final response = await _client.query({
      '@type': 'getPollVoters',
      'chat_id': chatId,
      'message_id': message.id,
      'option_id': optionIndex,
      'offset': offset,
      'limit': 50,
    });
    return response.objects('voters') ?? const <Map<String, dynamic>>[];
  }

  Future<void> votePoll(ChatMessage message, int optionIndex) async {
    final poll = message.poll;
    if (poll == null || poll.isClosed) return;
    final selected = <int>[...poll.chosenOptionIndexes];
    if (poll.allowsMultipleAnswers) {
      selected.contains(optionIndex)
          ? selected.remove(optionIndex)
          : selected.add(optionIndex);
    } else if (selected.length == 1 && selected.first == optionIndex) {
      if (!poll.allowsRevoting) return;
      selected.clear();
    } else {
      selected
        ..clear()
        ..add(optionIndex);
    }
    await _client.query({
      '@type': 'setPollAnswer',
      'chat_id': chatId,
      'message_id': message.id,
      'option_ids': selected,
    });
    await _refreshMessage(message.id);
  }

  Future<void> stopPoll(ChatMessage message) async {
    if (message.poll == null || message.poll!.isClosed) return;
    await _client.query({
      '@type': 'stopPoll',
      'chat_id': chatId,
      'message_id': message.id,
    });
    await _refreshMessage(message.id);
  }

  Future<void> toggleChecklistTask(
    ChatMessage message,
    MessageChecklistTask task,
  ) async {
    final checklist = message.checklist;
    if (checklist == null || !checklist.canMarkTasksAsDone) return;
    await _client.query({
      '@type': 'markChecklistTasksAsDone',
      'chat_id': chatId,
      'message_id': message.id,
      'marked_as_done_task_ids': task.isCompleted ? <int>[] : [task.id],
      'marked_as_not_done_task_ids': task.isCompleted ? [task.id] : <int>[],
    });
    await _refreshMessage(message.id);
  }

  Future<void> addChecklistTask(ChatMessage message, String text) async {
    final checklist = message.checklist;
    final value = text.trim();
    if (checklist == null || !checklist.canAddTasks || value.isEmpty) return;
    final nextId =
        checklist.tasks.fold<int>(
          0,
          (current, task) => math.max(current, task.id),
        ) +
        1;
    await _client.query({
      '@type': 'addChecklistTasks',
      'chat_id': chatId,
      'message_id': message.id,
      'tasks': [
        {
          '@type': 'inputChecklistTask',
          'id': nextId,
          'text': {'@type': 'formattedText', 'text': value},
        },
      ],
    });
    await _refreshMessage(message.id);
  }

  /// Re-sends the same content (the "+1" quick repeat) — only plain text and
  /// photos; the badge that calls this is gated to those kinds too.
  void repeatMessage(ChatMessage message) {
    if (hasProtectedContent) return;
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

  bool sendKeyboardButtonText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
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
    return true;
  }

  bool sendCommand(String command) {
    final trimmed = command.trim();
    if (!trimmed.startsWith('/')) return false;
    _sendText(trimmed);
    return true;
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

  Future<void> summarizeMessage(
    ChatMessage message, {
    String translateToLanguageCode = '',
    String tone = 'neutral',
  }) async {
    if (!canUseAiSummary ||
        message.summaryLanguageCode.isEmpty ||
        message.aiSummaryLoading) {
      return;
    }
    final targets = _messageRefs(message.id);
    for (final target in targets) {
      target.aiSummaryLoading = true;
    }
    notifyListeners();
    try {
      final result = await telegramAi.summarize(
        chatId: chatId,
        messageId: message.id,
        translateToLanguageCode: translateToLanguageCode,
        tone: tone,
      );
      final formatted = result.toTdJson();
      for (final target in _messageRefs(message.id)) {
        target.aiSummaryText = result.text;
        target.aiSummaryEntities = TDParse.textEntities(formatted);
        target.aiSummaryLoading = false;
      }
      notifyListeners();
    } catch (_) {
      for (final target in _messageRefs(message.id)) {
        target.aiSummaryLoading = false;
      }
      notifyListeners();
      rethrow;
    }
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
    if (hasProtectedContent) throw const ForwardBlockedException();
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
    if (hasProtectedContent) throw const ForwardBlockedException();
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
    await forwardMessagesWithOptions(
      client: _client,
      targetChatId: savedChatId,
      fromChatId: chatId,
      messageIds: messageIds,
    );
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
    OutgoingAttachment attachment, {
    required String caption,
    List<Map<String, dynamic>> entities = const [],
  }) async {
    await _client.query({
      '@type': 'editMessageMedia',
      'chat_id': chatId,
      'message_id': id,
      'input_message_content': attachmentInputMessageContent(
        attachment,
        caption: caption,
        captionEntities: entities,
      ),
    });
  }

  // MARK: - Paging

  Future<bool> loadOlder() async {
    if (!canLoadOlder) return false;
    _isLoadingOlder = true;
    notifyListeners();
    try {
      return await _fetchHistory(_oldestServerMessageId, 0, 30, isOlder: true);
    } finally {
      _isLoadingOlder = false;
      notifyListeners();
    }
  }

  Future<bool> loadOlderLocal() async {
    if (!canLoadOlder) return false;
    _isLoadingOlder = true;
    notifyListeners();
    try {
      return await _fetchHistory(
        _oldestServerMessageId,
        0,
        30,
        isOlder: true,
        onlyLocal: true,
      );
    } finally {
      _isLoadingOlder = false;
      notifyListeners();
    }
  }

  Future<bool> loadLatestHistory() async {
    if (_latestHistoryLoadInFlight) return false;
    final requestGeneration = ++_historyWindowGeneration;
    _latestHistoryLoadInFlight = true;
    _latestHistoryLiveArrivals.clear();
    _latestHistoryDeletedMessageIds.clear();
    _latestHistoryLoadInvalidated = false;
    final messagesAtRequestStart = List<ChatMessage>.of(_allMessages);
    try {
      Map<String, dynamic> response;
      try {
        response = await _client.query({
          '@type': 'getChatHistory',
          'chat_id': chatId,
          'from_message_id': 0,
          'offset': 0,
          'limit': 40,
          'only_local': false,
        });
      } catch (error) {
        if (_markPeerRestricted(error)) notifyListeners();
        return false;
      }
      if (_isDisposed ||
          _latestHistoryLoadInvalidated ||
          requestGeneration != _historyWindowGeneration) {
        return false;
      }
      final rawMessages =
          response.objects('messages') ?? const <Map<String, dynamic>>[];
      final latest = rawMessages
          .map(TDParse.message)
          .whereType<ChatMessage>()
          .toList();
      if (rawMessages.isNotEmpty && latest.isEmpty) return false;

      final fetched =
          <ChatMessage>[...latest, ..._latestHistoryLiveArrivals.values]
              .where(
                (message) =>
                    !_latestHistoryDeletedMessageIds.contains(message.id),
              )
              .toList();

      ++_historyWindowGeneration;
      ++_historyWindowRevision;
      anchoredHistory = false;
      _pendingScrollToId = null;
      _hasOlderHistory = fetched.isNotEmpty;
      _historyReachesLatest = true;
      _knownLatestMessageId = latestServerMessageId(fetched);
      if (fetched.isEmpty) {
        _allMessages = [];
        _applyKeywordFilter();
      } else {
        _mergeHistoryWindow(
          fetched,
          messagesAtRequestStart: messagesAtRequestStart,
          replaceCurrentWindow: true,
          preserveLiveArrivals: false,
        );
      }
      _resolveRichMessagesIfNeeded(fetched);
      _resolveSendersIfNeeded(fetched);
      _resolveRepliesIfNeeded(fetched);
      _resolveForwardsIfNeeded(fetched);
      _resolveServiceUsersIfNeeded(fetched);
    } finally {
      _latestHistoryLoadInFlight = false;
      _latestHistoryLiveArrivals.clear();
      _latestHistoryDeletedMessageIds.clear();
      _latestHistoryLoadInvalidated = false;
    }

    return true;
  }

  // MARK: - Header

  Future<void> _loadChatHeader() async {
    Map<String, dynamic> chat;
    try {
      chat = await _client.query({'@type': 'getChat', 'chat_id': chatId});
    } catch (error) {
      if (_markPeerRestricted(error)) {
        notifyListeners();
      }
      return;
    }
    peerTitle = chat.str('title') ?? peerTitle;
    peerPhoto = TDParse.smallPhoto(chat.obj('photo'));
    firstContactInfo = ChatFirstContactInfo.fromActionBar(
      chat.obj('action_bar'),
    );
    _applyBusinessBotManageBar(chat.obj('business_bot_manage_bar'));
    lastReadOutboxId = chat.int64('last_read_outbox_message_id') ?? 0;
    lastReadInboxId = chat.int64('last_read_inbox_message_id') ?? 0;
    unreadCount = chat.integer('unread_count') ?? 0;
    unreadMentionCount = chat.integer('unread_mention_count') ?? 0;
    isMarkedUnread = chat.boolean('is_marked_as_unread') ?? false;
    hasProtectedContent =
        chat.boolean('has_protected_content') ?? hasProtectedContent;
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
    isSecretChat = kind == ChatKind.secret;
    final entryUpperMessageId = chat.obj('last_message')?.int64('id') ?? 0;
    if (!_didCaptureUnreadSummaryRange) {
      _didCaptureUnreadSummaryRange = true;
      if (unreadCount > 0 &&
          entryUpperMessageId > lastReadInboxId &&
          !isSecretChat &&
          !hasProtectedContent) {
        unreadSummarySnapshot = UnreadChatRangeSnapshot(
          chatId: chatId,
          accountSlot: _client.activeSlot,
          lastReadInboxId: lastReadInboxId,
          unreadCount: unreadCount,
          upperMessageId: entryUpperMessageId,
          capturedAt: DateTime.now(),
        );
      }
    }
    _primeLastMessage(chat);
    // Chat-wide default send permission + permissive membership defaults
    // (refined per type below).
    _chatCanSend =
        chat.obj('permissions')?.boolean('can_send_basic_messages') ?? true;
    canSendMessages = _chatCanSend;
    isMember = true;
    canJoin = false;
    joinByRequest = false;
    isChannel = false;
    isDirectMessagesGroup = false;
    isAdministeredDirectMessagesGroup = false;
    canDeleteMessagesBySender = false;
    sendDisabledReason = '';
    isPeerRestricted = false;
    isPeerPornographicRestricted = false;
    peerRestrictionText = '';
    final chatRestrictionReason = TDParse.restrictionReasonFor(chat);
    if (chatRestrictionReason != null && TDParse.isBlockingRestriction(chat)) {
      _setPeerRestricted(
        chatRestrictionReason,
        isPornographic: TDParse.isPornographicRestriction(chat),
      );
    }

    final type = chat.obj('type');
    if (type?.type == 'chatTypeSecret') {
      _secretChatId = type?.integer('secret_chat_id');
      _applySecretChatReadiness(SecretChatReadiness.unknown, notify: false);
      await _loadSecretChatState();
    } else {
      _secretChatId = null;
    }
    switch (type?.type) {
      case 'chatTypePrivate':
      case 'chatTypeSecret':
        peerUserId = type?.int64('user_id');
        final uid = peerUserId;
        if (uid != null) {
          try {
            final user = await _client.query({
              '@type': 'getUser',
              'user_id': uid,
            });
            final restrictionReason = TDParse.restrictionReasonFor(user);
            if (restrictionReason != null &&
                TDParse.isBlockingRestriction(user)) {
              _setPeerRestricted(
                restrictionReason,
                isPornographic: TDParse.isPornographicRestriction(user),
              );
            }
            peerIsBot = _isBotUser(user);
            peerOnline = TDParse.isUserOnline(user);
            peerStatusText = TDParse.userStatus(user);
            firstContactInfo = firstContactInfo?.withUser(user);
          } catch (error) {
            if (_markPeerRestricted(error)) {
              notifyListeners();
            }
          }
          if (type?.type == 'chatTypePrivate') {
            unawaited(_loadPrivatePaidMessageInfo(uid));
            if (peerIsBot) await _loadBotInfo(uid);
          }
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
            final restrictionReason = TDParse.restrictionReasonFor(sg);
            if (restrictionReason != null &&
                TDParse.isBlockingRestriction(sg)) {
              _setPeerRestricted(
                restrictionReason,
                isPornographic: TDParse.isPornographicRestriction(sg),
              );
            }
            isChannel = sg.boolean('is_channel') ?? false;
            isDirectMessagesGroup =
                sg.boolean('is_direct_messages_group') ?? false;
            isAdministeredDirectMessagesGroup =
                sg.boolean('is_administered_direct_messages_group') ?? false;
            isForum = isForum || (sg.boolean('is_forum') ?? false);
            joinByRequest = sg.boolean('join_by_request') ?? false;
            _setPaidMessageStarCount(_paidMessageStars(sg), notify: false);
            _applyGroupStatus(sg.obj('status'));
          } catch (error) {
            if (_markPeerRestricted(error)) {
              notifyListeners();
            }
          }
          unawaited(_loadSupergroupFullInfo(sgid));
        }
    }
    if (isForum) {
      unawaited(loadForumTopics());
    } else if (forumTopics.isNotEmpty || forumTopicsLoading) {
      forumTopicsLoading = false;
      forumTopics = const [];
    }
    if (isChannel || peerIsBot) {
      unawaited(_retrieveSponsoredMessages());
    }
    if (!canSendMessages && sendDisabledReason.isEmpty && isPeerRestricted) {
      sendDisabledReason = AppStrings.t(
        AppStringKeys.chatRestrictedTelegramTosMessage,
      );
    }
    notifyListeners();
    unawaited(_loadPinnedMessage());
  }

  Future<void> refreshPeerRestrictionState() => _loadChatHeader();

  Future<void> _loadSecretChatState() async {
    final secretChatId = _secretChatId;
    if (secretChatId == null) return;
    try {
      final secretChat = await SecretChatService.get(secretChatId);
      if (_secretChatId != secretChatId) return;
      _applySecretChatReadiness(
        SecretChatService.readiness(secretChat),
        notify: false,
      );
    } catch (error) {
      debugPrint('Could not load secret chat $secretChatId: $error');
      _applySecretChatReadiness(SecretChatReadiness.unknown, notify: false);
    }
  }

  void _applySecretChatReadiness(
    SecretChatReadiness readiness, {
    bool notify = true,
  }) {
    switch (readiness) {
      case SecretChatReadiness.ready:
        canSendMessages = _chatCanSend;
        sendDisabledReason = canSendMessages
            ? ''
            : AppStrings.t(AppStringKeys.chatRestrictedTelegramTosMessage);
      case SecretChatReadiness.closed:
        canSendMessages = false;
        sendDisabledReason = AppStrings.t(AppStringKeys.secretChatClosed);
      case SecretChatReadiness.pending:
      case SecretChatReadiness.unknown:
        canSendMessages = false;
        sendDisabledReason = AppStrings.t(AppStringKeys.secretChatWaiting);
    }
    if (notify) notifyListeners();
  }

  Future<void> _retrieveSponsoredMessages() async {
    final cacheKey = '${_client.activeSlot}:$chatId';
    try {
      final snapshot = await _sponsoredMessagesCache.retrieve(
        cacheKey: cacheKey,
        refresh: true,
        fetch: () => _client.query({
          '@type': 'getChatSponsoredMessages',
          'chat_id': chatId,
        }),
      );
      if (_isDisposed) return;
      sponsoredMessages = snapshot;
    } catch (_) {
      // Sponsorship retrieval must never prevent a channel from opening.
    }
  }

  void _primeLastMessage(Map<String, dynamic> chat) {
    final lastRaw = chat.obj('last_message');
    final lastMessage = lastRaw == null ? null : TDParse.message(lastRaw);
    if (lastMessage == null) return;
    _knownLatestMessageId = isPendingChatMessage(lastMessage)
        ? 0
        : lastMessage.id;
    if (_restoredFromSession) {
      // A restored transcript may predate this item. Appending it here would
      // create a visible hole until history hydration completes.
      _historyReachesLatest = false;
      return;
    }
    final canPrimeWindow =
        _allMessages.isEmpty ||
        _allMessages.any((message) => message.id == lastMessage.id);
    if (!canPrimeWindow) {
      _historyReachesLatest = false;
      return;
    }
    _historyReachesLatest = true;
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

  Future<int?> webAppBotUserId(ChatMessage? message) async {
    if (peerIsBot && peerUserId != null) return peerUserId;
    final senderId = message?.senderId;
    if (senderId == null || senderId <= 0) return null;
    try {
      final user = await _client.query({
        '@type': 'getUser',
        'user_id': senderId,
      });
      return _isBotUser(user) ? senderId : null;
    } catch (_) {
      return null;
    }
  }

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
    if (shouldLoadInitialHistoryAroundLastRead(
      openAtLatest: openAtLatest,
      lastReadInboxId: lastReadInboxId,
      unreadCount: unreadCount,
    )) {
      final loaded = await _loadInitialAroundLastRead();
      // A chat-list preview hit can satisfy around-last-read with one local
      // bubble. Fall through to latest hydration so the open path does not
      // settle until the user scrolls.
      if (loaded && !isThinInitialHistoryWindow(messages.length)) return;
    }
    await _loadInitialLatestHistory();
  }

  Future<bool> _loadInitialAroundLastRead() async {
    final loadedLocal = await loadAroundMessage(
      lastReadInboxId,
      onlyLocal: true,
    );
    if (loadedLocal) {
      if (isThinInitialHistoryWindow(messages.length)) {
        return loadAroundMessage(
          lastReadInboxId,
          scrollToTarget: false,
          replaceCurrentWindow: false,
        );
      }
      unawaited(
        loadAroundMessage(
          lastReadInboxId,
          scrollToTarget: false,
          replaceCurrentWindow: false,
        ),
      );
      return true;
    }
    return loadAroundMessage(lastReadInboxId);
  }

  Future<void> _loadInitialLatestHistory() async {
    anchoredHistory = false;
    final localLoaded = await _fetchHistory(0, 0, 40, onlyLocal: true);
    if (!localLoaded) {
      await _fetchHistory(0, 0, 40);
    } else if (isThinInitialHistoryWindow(messages.length)) {
      // Await the remote page for preview-sized local caches. Fire-and-forget
      // left the UI on a single bubble until a scroll triggered loadOlder.
      await _fetchHistory(0, 0, 40);
    } else {
      unawaited(_fetchHistory(0, 0, 40));
    }
    if (_allMessages.isEmpty) return;
    // Render the first page immediately. Older unread-boundary paging used to
    // happen here and could block a large media channel for seconds on cold
    // cache before any UI appeared.
    if (isThinInitialHistoryWindow(messages.length)) {
      await _fetchHistory(_allMessages.first.id, 0, 40);
    }
  }

  Future<void> _hydrateRestoredLatestHistory() async {
    await _fetchHistory(0, 0, 40, onlyLocal: true);
    if (_isDisposed) return;
    await _fetchHistory(0, 0, 40);
  }

  Future<bool> loadAroundMessage(
    int messageId, {
    bool onlyLocal = false,
    bool scrollToTarget = true,
    bool replaceCurrentWindow = true,
  }) async {
    final requestGeneration = replaceCurrentWindow
        ? ++_historyWindowGeneration
        : _historyWindowGeneration;
    final messagesAtRequestStart = List<ChatMessage>.of(_allMessages);
    final latestMessageIdAtRequestStart = _knownLatestMessageId;
    final batch = <ChatMessage>[];
    try {
      final targetRaw = await _client.query({
        '@type': 'getMessage',
        'chat_id': chatId,
        'message_id': messageId,
      });
      final target = TDParse.message(targetRaw);
      if (target != null) batch.add(target);
    } catch (_) {
      // A missing or restricted target message doesn't imply the containing
      // chat is restricted. Load its surrounding history when available.
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
      if (_markPeerRestricted(error)) notifyListeners();
    }

    if (_isDisposed || requestGeneration != _historyWindowGeneration) {
      return false;
    }
    if (batch.isEmpty) return false;
    if (replaceCurrentWindow) {
      ++_historyWindowGeneration;
      ++_historyWindowRevision;
    }
    _hasOlderHistory = true;
    anchoredHistory = true;
    if (scrollToTarget) _pendingScrollToId = messageId;
    _mergeHistoryWindow(
      batch,
      messagesAtRequestStart: messagesAtRequestStart,
      replaceCurrentWindow: replaceCurrentWindow,
      preserveLiveArrivals:
          latestMessageIdAtRequestStart <= 0 ||
          batch.any((message) => message.id == latestMessageIdAtRequestStart),
    );
    final reachesKnownLatest =
        _knownLatestMessageId <= 0 ||
        _allMessages.any((message) => message.id == _knownLatestMessageId);
    _historyReachesLatest = replaceCurrentWindow
        ? reachesKnownLatest
        : _historyReachesLatest || reachesKnownLatest;
    _resolveRichMessagesIfNeeded(batch);
    _resolveSendersIfNeeded(batch);
    _resolveRepliesIfNeeded(batch);
    _resolveForwardsIfNeeded(batch);
    _resolveServiceUsersIfNeeded(batch);
    return messages.any((m) => m.id == messageId);
  }

  Future<int?> openNextUnreadMention() async {
    try {
      final response = await _client.query({
        '@type': 'searchChatMessages',
        'chat_id': chatId,
        'query': '',
        'sender_id': null,
        'from_message_id': 0,
        'offset': 0,
        'limit': math.min(
          100,
          math.max(10, unreadMentionCount + _locallyViewedMentionIds.length),
        ),
        'filter': {'@type': 'searchMessagesFilterUnreadMention'},
      });
      final rawMessages =
          response.objects('messages') ?? const <Map<String, dynamic>>[];
      if (rawMessages.isEmpty) {
        _setUnreadMentionCount(0, emitLocalUpdate: true);
        return null;
      }
      final mentions = rawMessages
          .map(TDParse.message)
          .whereType<ChatMessage>()
          .where((message) => !_locallyViewedMentionIds.contains(message.id))
          .toList();
      final mention = mentions.isEmpty ? null : mentions.first;
      return mention?.id;
    } catch (_) {
      return null;
    }
  }

  /// Reports the exact messages that entered the viewport. TDLib tracks
  /// unread mentions independently from the ordinary inbox boundary, so only
  /// advancing `last_read_inbox_message_id` leaves `unread_mention_count`
  /// behind. Sending the concrete IDs clears both states correctly.
  void markVisibleMessagesViewed(Iterable<ChatMessage> visibleMessages) {
    final incoming = visibleMessages
        .where((message) => !message.isOutgoing && !message.isService)
        .toList(growable: false);
    if (incoming.isEmpty) return;
    _client.send({
      '@type': 'viewMessages',
      'chat_id': chatId,
      'message_ids': incoming.map((message) => message.id).toList(),
      'force_read': true,
    });
    _consumeViewedMentions(
      incoming
          .where((message) => message.containsUnreadMention)
          .map((message) => message.id),
    );
  }

  /// Marks the mention selected by the blue @ control after the view has
  /// scrolled it into place. Awaiting TDLib prevents a quick second tap from
  /// resolving the same mention again.
  Future<void> markUnreadMentionRead(int messageId) async {
    try {
      await _client.query({
        '@type': 'viewMessages',
        'chat_id': chatId,
        'message_ids': [messageId],
        'force_read': true,
      });
    } catch (_) {
      return;
    }
    _consumeViewedMentions([messageId], force: true);
  }

  void _consumeViewedMentions(Iterable<int> messageIds, {bool force = false}) {
    final candidates = messageIds
        .where((id) => id > 0 && !_locallyViewedMentionIds.contains(id))
        .toSet();
    if (candidates.isEmpty) return;
    final unreadIds = force
        ? candidates
        : _allMessages
              .where(
                (message) =>
                    candidates.contains(message.id) &&
                    message.containsUnreadMention,
              )
              .map((message) => message.id)
              .toSet();
    if (unreadIds.isEmpty) return;

    _locallyViewedMentionIds.addAll(unreadIds);
    while (_locallyViewedMentionIds.length > 512) {
      _locallyViewedMentionIds.remove(_locallyViewedMentionIds.first);
    }
    for (final message in _allMessages) {
      if (unreadIds.contains(message.id)) {
        message.containsUnreadMention = false;
      }
    }
    _setUnreadMentionCount(
      unreadMentionCountAfterReading(unreadMentionCount, unreadIds.length),
      emitLocalUpdate: true,
    );
  }

  void _setUnreadMentionCount(int count, {bool emitLocalUpdate = false}) {
    final next = math.max(0, count);
    final changed = unreadMentionCount != next;
    unreadMentionCount = next;
    if (changed) notifyListeners();
    if (emitLocalUpdate) {
      _client.emitLocalUpdate({
        '@type': 'updateChatUnreadMentionCount',
        'chat_id': chatId,
        'unread_mention_count': next,
      });
    }
  }

  Future<bool> _fetchHistory(
    int fromMessageId,
    int offset,
    int limit, {
    bool isOlder = false,
    bool onlyLocal = false,
  }) async {
    final requestGeneration = _historyWindowGeneration;
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
      if (_markPeerRestricted(error)) notifyListeners();
      return false;
    }
    if (_isDisposed || requestGeneration != _historyWindowGeneration) {
      return false;
    }

    final rawMessages =
        response.objects('messages') ?? const <Map<String, dynamic>>[];
    final parsed = rawMessages
        .map(TDParse.message)
        .whereType<ChatMessage>()
        .toList();
    if (parsed.isEmpty) {
      // A local-cache miss says nothing about whether the server still has
      // older history. Only an empty remote page confirms exhaustion.
      if (confirmsOlderHistoryExhausted(onlyLocal: onlyLocal)) {
        _hasOlderHistory = false;
      }
      return false;
    }

    _merge(parsed);
    if (fromMessageId == 0) {
      _historyReachesLatest =
          _knownLatestMessageId <= 0 ||
          parsed.any((message) => message.id == _knownLatestMessageId);
    }
    _resolveRichMessagesIfNeeded(parsed);
    _resolveSendersIfNeeded(parsed);
    _resolveRepliesIfNeeded(parsed);
    _resolveForwardsIfNeeded(parsed);
    _resolveServiceUsersIfNeeded(parsed);
    return true;
  }

  bool _markPeerRestricted(Object error) {
    final text = error.toString();
    final normalized = _normalizedRestrictionText(text);
    final restricted =
        TDParse.isTelegramTermsRestrictionText(text) ||
        TDParse.isPornographicRestrictionText(text) ||
        normalized.contains('chat_restricted') ||
        normalized.contains('channel_restricted');
    if (!restricted) return false;
    _setPeerRestricted(
      text,
      isPornographic: TDParse.isPornographicRestrictionText(text),
    );
    return true;
  }

  String _normalizedRestrictionText(String text) =>
      text.toLowerCase().replaceAll('’', "'");

  void _setPeerRestricted(String text, {required bool isPornographic}) {
    isPeerRestricted = true;
    isPeerPornographicRestricted =
        isPeerPornographicRestricted || isPornographic;
    peerRestrictionText = text;
  }

  Future<void> leaveChat() async {
    await _client.query({'@type': 'leaveChat', 'chat_id': chatId});
  }

  Future<void> markLoadedMessagesRead() async {
    if (_markReadInFlight) return;
    _markReadInFlight = true;
    try {
      final latestLoadedId = latestServerMessageId(_allMessages);
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
          messageId = math.max(
            messageId,
            latest == null ? 0 : latestServerMessageId([latest]),
          );
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
        final rawContent = raw.obj('content');
        if (rawContent?.type == 'messageChatHasProtectedContentToggled') {
          hasProtectedContent =
              rawContent?.boolean('new_has_protected_content') ??
              hasProtectedContent;
        }
        final message = TDParse.message(raw);
        if (message == null) return;
        if (_latestHistoryLoadInFlight) {
          _latestHistoryLiveArrivals[message.id] = message;
        }
        final canAppendToTranscript = shouldMergeLiveMessageIntoChatWindow(
          historyReachesLatest: _historyReachesLatest,
        );
        if (!message.isOutgoing && !message.isService) {
          _liveIncomingMessages.add(message.id);
        }
        if (!isPendingChatMessage(message)) {
          _knownLatestMessageId = math.max(_knownLatestMessageId, message.id);
        }
        if (!canAppendToTranscript) {
          notifyListeners();
          return;
        }
        _merge([message]);
        _resolveRichMessagesIfNeeded([message]);
        _resolveSendersIfNeeded([message]);
        _resolveRepliesIfNeeded([message]);
        _resolveForwardsIfNeeded([message]);
        _resolveServiceUsersIfNeeded([message]);

      case 'updateMessageContent':
        if (update.int64('chat_id') != chatId) return;
        final messageId = update.int64('message_id');
        final content = update.obj('new_content');
        if (messageId == null || content == null) return;
        if (content.type == 'messageChatHasProtectedContentToggled') {
          hasProtectedContent =
              content.boolean('new_has_protected_content') ??
              hasProtectedContent;
        }
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
        if (content.type == 'messageVoiceNote' ||
            content.type == 'messageVideoNote') {
          unawaited(_refreshMessage(messageId));
        }

      case 'updateMessageSuggestedPostInfo':
        if (update.int64('chat_id') != chatId) return;
        final messageId = update.int64('message_id');
        if (messageId == null) return;
        unawaited(_refreshMessage(messageId));

      case 'updateChatUnreadMentionCount':
        if (update.int64('chat_id') != chatId) return;
        _setUnreadMentionCount(
          update.integer('unread_mention_count') ?? unreadMentionCount,
        );

      case 'updateMessageSendSucceeded':
        if (update.int64('chat_id') != chatId) return;
        final oldMessageId = update.int64('old_message_id');
        final rawSentMessage = update.obj('message');
        if (oldMessageId == null || rawSentMessage == null) return;
        if (_latestHistoryLoadInFlight) {
          _latestHistoryLiveArrivals.remove(oldMessageId);
          final sentMessage = TDParse.message(rawSentMessage);
          if (sentMessage != null) {
            _latestHistoryLiveArrivals[sentMessage.id] = sentMessage;
          }
        }
        _replacePendingMessage(oldMessageId, rawSentMessage);
        _recordMessageSendResult(
          oldMessageId,
          const _MessageSendResult.success(),
        );

      case 'updateMessageSendFailed':
        if (update.int64('chat_id') != chatId) return;
        final oldMessageId = update.int64('old_message_id');
        if (oldMessageId == null) return;
        if (_latestHistoryLoadInFlight) {
          _latestHistoryLiveArrivals.remove(oldMessageId);
        }
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

      case 'updateSecretChat':
        final secretChat = update.obj('secret_chat');
        if (secretChat == null || secretChat.integer('id') != _secretChatId) {
          return;
        }
        _applySecretChatReadiness(SecretChatService.readiness(secretChat));

      case 'updateChat':
        final chat = update.obj('chat');
        if (chat == null || chat.int64('id') != chatId) return;
        messageAutoDeleteTime = _autoDeleteSeconds(chat);
        _setPaidMessageStarCount(_paidMessageStars(chat), notify: false);
        hasProtectedContent =
            chat.boolean('has_protected_content') ?? hasProtectedContent;
        if (chat.containsKey('draft_message')) {
          _applyRemoteDraft(chat.obj('draft_message'), notify: false);
        }
        if (chat.containsKey('action_bar')) {
          firstContactInfo = ChatFirstContactInfo.fromActionBar(
            chat.obj('action_bar'),
          );
        }
        notifyListeners();

      case 'updateChatActionBar':
        if (update.int64('chat_id') != chatId) return;
        firstContactInfo = ChatFirstContactInfo.fromActionBar(
          update.obj('action_bar'),
        );
        notifyListeners();

      case 'updateChatBusinessBotManageBar':
        if (update.int64('chat_id') != chatId) return;
        _applyBusinessBotManageBar(update.obj('business_bot_manage_bar'));
        notifyListeners();

      case 'updateChatHasProtectedContent':
        if (update.int64('chat_id') != chatId) return;
        hasProtectedContent =
            update.boolean('has_protected_content') ?? hasProtectedContent;
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
        // from_cache unloads (is_permanent == false) must not remove messages
        // from the UI — the messages still exist on the server.
        if (update.boolean('is_permanent') != true) return;
        final deletedIds = update.int64Array('message_ids') ?? const <int>[];
        if (_latestHistoryLoadInFlight) {
          _latestHistoryDeletedMessageIds.addAll(deletedIds);
          for (final messageId in deletedIds) {
            _latestHistoryLiveArrivals.remove(messageId);
          }
        }
        _removeMessages(deletedIds);

      case 'mithkaChatHistoryCleared':
        if (update.int64('chat_id') != chatId) return;
        ++_historyWindowGeneration;
        ++_historyWindowRevision;
        ++_historyWindowInvalidationRevision;
        if (_latestHistoryLoadInFlight) {
          _latestHistoryLoadInvalidated = true;
          _latestHistoryLiveArrivals.clear();
        }
        _allMessages = [];
        messages = [];
        _hasOlderHistory = false;
        anchoredHistory = false;
        _historyReachesLatest = true;
        _knownLatestMessageId = 0;
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

      case 'updateUser':
        final user = update.obj('user');
        if (user == null) return;
        _applySenderUserUpdate(user);

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
        final status = update.obj('status');
        peerOnline = status?.type == 'userStatusOnline';
        peerStatusText = status == null
            ? ''
            : TDParse.userStatus({'status': status});
        notifyListeners();

      case 'updateMessageEdited':
        if (update.int64('chat_id') != chatId) return;
        final mid = update.int64('message_id');
        if (mid == null) return;
        final replyMarkup = update.obj('reply_markup');
        _replaceButtonRows(mid, TDParse.messageButtonRows(replyMarkup));
        final targets = _messageRefs(mid);
        if (targets.isNotEmpty) {
          for (final message in targets) {
            message.isEdited = true;
          }
          notifyListeners();
        }

      case 'updateMessageInteractionInfo':
        if (update.int64('chat_id') != chatId) return;
        final mid = update.int64('message_id');
        if (mid == null) return;
        final targets = _messageRefs(mid);
        if (targets.isNotEmpty) {
          final reactions = TDParse.reactionsFrom({
            'interaction_info': update.obj('interaction_info'),
          });
          for (final message in targets) {
            message.reactions = reactions;
          }
          notifyListeners();
        }

      case 'updateAvailableMessageEffects':
        final ids = <int>{
          ...?update.int64Array('reaction_effect_ids'),
          ...?update.int64Array('sticker_effect_ids'),
        };
        unawaited(_resolveMessageEffects(ids));

      case 'updateBlockMessageSender':
        // Invalidate blocked-user cache so the hide-on-block toggle
        // takes effect immediately without app restart.
        if (BlockedUserService.shared.enabled) {
          unawaited(
            BlockedUserService.shared.loadBlockedUsers().then((_) {
              _applyKeywordFilter();
            }),
          );
        }
    }
  }

  void _applyBusinessBotManageBar(Map<String, dynamic>? value) {
    businessBotUserId = value?.int64('bot_user_id') ?? 0;
    businessBotManageUrl = value?.str('manage_url') ?? '';
    businessBotPaused = value?.boolean('is_bot_paused') ?? false;
    businessBotCanReply = value?.boolean('can_bot_reply') ?? false;
  }

  Future<void> _resolveMessageEffects(Set<int> ids) async {
    if (ids.isEmpty) {
      availableMessageEffects = const [];
      notifyListeners();
      return;
    }
    final effects = await Future.wait(
      ids.map((id) async {
        try {
          final effect = await _client.query({
            '@type': 'getMessageEffect',
            'effect_id': id,
          });
          return AvailableMessageEffect(
            id: id,
            emoji: effect.str('emoji') ?? '✨',
          );
        } catch (_) {
          return null;
        }
      }),
    );
    if (_isDisposed) return;
    availableMessageEffects = effects
        .whereType<AvailableMessageEffect>()
        .toList(growable: false);
    notifyListeners();
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
    m.replyToImage = quoted.image;
    m.replyToImageWidth = quoted.imageWidth;
    m.replyToImageHeight = quoted.imageHeight;
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
      final placeholder = switch (q.contentType) {
        'messagePhoto' => telegramText(AppStringKeys.composerImagePreview),
        'messageVideo' => telegramText(AppStringKeys.chatVideoPlaceholder),
        'messageAnimation' => telegramText(AppStringKeys.tdMessageGif),
        _ => null,
      };
      return q.text == placeholder ? '' : q.text;
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
          ..sort(compareChatMessagesChronologically);
    _markBlockedUserMessages();
    _markBlockedMessagesReadThroughVisibleBoundary();
    notifyListeners();
  }

  /// Mark messages from Telegram-blocked users so the renderer can show a
  /// compact placeholder instead of the full bubble.
  ///
  /// Only ever called from _applyKeywordFilter (right after `messages` is
  /// reassigned): the chat_view transcript memo relies on list identity to
  /// notice blocked-state changes, so never flip these flags elsewhere.
  void _markBlockedUserMessages() {
    final svc = BlockedUserService.shared;
    if (!svc.enabled) {
      for (final m in messages) {
        m.blockedByUser = false;
      }
      return;
    }
    for (final m in messages) {
      m.blockedByUser =
          !m.isOutgoing &&
          !m.isService &&
          m.senderId != null &&
          svc.isBlocked(m.senderId!);
    }
  }

  void _markBlockedMessagesReadThroughVisibleBoundary() {
    if (_allMessages.isEmpty) return;
    final visibleMax = latestServerMessageReadBoundary(
      visibleMessages: messages,
      allMessages: _allMessages,
    );
    if (visibleMax <= 0) return;
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
    for (final message in incoming) {
      if (_locallyViewedMentionIds.contains(message.id)) {
        message.containsUnreadMention = false;
      }
    }
    _allMessages = mergeChatMessages(
      _allMessages,
      incoming,
      ignoredMessageIds: {
        ..._discardedPendingMessageIds,
        ..._settledPendingMessageIds,
      },
    );
    _applyKeywordFilter();
  }

  void _mergeHistoryWindow(
    List<ChatMessage> incoming, {
    required List<ChatMessage> messagesAtRequestStart,
    required bool replaceCurrentWindow,
    required bool preserveLiveArrivals,
  }) {
    if (incoming.isEmpty) return;
    for (final message in incoming) {
      if (_locallyViewedMentionIds.contains(message.id)) {
        message.containsUnreadMention = false;
      }
    }
    _allMessages = mergeChatHistoryWindow(
      currentAtRequestStart: messagesAtRequestStart,
      currentAtCompletion: _allMessages,
      fetched: incoming,
      replaceCurrentWindow: replaceCurrentWindow,
      preserveLiveArrivals: preserveLiveArrivals,
      ignoredMessageIds: {
        ..._discardedPendingMessageIds,
        ..._settledPendingMessageIds,
      },
    );
    _applyKeywordFilter();
  }

  void _rememberSettledPendingMessageId(int messageId) {
    _settledPendingMessageIds.add(messageId);
    while (_settledPendingMessageIds.length > 256) {
      _settledPendingMessageIds.remove(_settledPendingMessageIds.first);
    }
  }

  Future<void> _discardStaleRestoredPendingMessages() async {
    final pendingIds = _allMessages
        .where((message) => message.isOutgoing && message.isSending)
        .map((message) => message.id)
        .toList(growable: false);
    if (pendingIds.isEmpty) return;

    final staleIds = <int>[];
    final replacements = <ChatMessage>[];
    for (final pendingId in pendingIds) {
      try {
        final raw = await _client.query({
          '@type': 'getMessage',
          'chat_id': chatId,
          'message_id': pendingId,
        });
        final current = TDParse.message(raw);
        if (current == null || current.id != pendingId || !current.isSending) {
          staleIds.add(pendingId);
          if (current != null) replacements.add(current);
        }
      } on TdError catch (error) {
        if (error.code == 400 || error.code == 404) staleIds.add(pendingId);
      } catch (_) {
        // Keep a pending bubble if TDLib cannot confirm its current state.
      }
    }
    if (_isDisposed || staleIds.isEmpty) return;
    for (final pendingId in staleIds) {
      _rememberSettledPendingMessageId(pendingId);
    }
    _removeMessages(staleIds);
    if (replacements.isNotEmpty) _merge(replacements);
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
    final targets = _messageRefs(messageId);
    if (targets.isEmpty) return;
    for (final target in targets) {
      target.text = text;
      if (entities != null) target.textEntities = entities;
      if (customEmoji != null) target.customEmoji = customEmoji;
      if (updateLinkPreview) target.linkPreview = linkPreview;
      if (edited) target.isEdited = true;
    }
    _applyKeywordFilter();
  }

  void _replacePendingMessage(
    int pendingMessageId,
    Map<String, dynamic> rawMessage,
  ) {
    _rememberSettledPendingMessageId(pendingMessageId);
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
    // Reassigned (not mutated) so the transcript memo's identity check stays
    // valid even if a notify lands before the merge below.
    messages = messages
        .where((message) => message.id != pendingMessageId)
        .toList();
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
    final targets = _messageRefs(messageId);
    if (targets.isEmpty) return;
    for (final message in targets) {
      message.buttonRows = buttonRows;
    }
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
    final buffered = _latestHistoryLiveArrivals[messageId];
    if (buffered != null &&
        !refs.any((message) => identical(message, buffered))) {
      refs.add(buffered);
    }
    return refs;
  }

  void _removeMessages(List<int> ids) {
    if (ids.isEmpty) return;
    final removed = ids.toSet();
    _allMessages.removeWhere((m) => removed.contains(m.id));
    // Reassign (never mutate in place): the transcript memo in chat_view
    // caches on the list's identity, so an in-place removeWhere would keep
    // rendering the deleted message.
    messages = messages.where((m) => !removed.contains(m.id)).toList();
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
      if (m.senderId != senderId || (m.isOutgoing && !m.senderIsChat)) continue;
      if (m.senderName == info.name &&
          _sameSenderPhoto(m.senderPhoto, info.photo) &&
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

  bool _sameSenderPhoto(TdFileRef? current, TdFileRef? next) {
    if (identical(current, next)) return true;
    if (current == null || next == null) return false;
    return current.id == next.id &&
        current.localPath == next.localPath &&
        current.photoId == next.photoId &&
        current.hasAnimation == next.hasAnimation;
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
    _primeCachedSenderIdentities(batch);
    final pending = <int>{};
    for (final message in batch) {
      if ((message.isOutgoing && !message.senderIsChat) || message.isService) {
        continue;
      }
      final senderId = message.senderId;
      if (senderId == null) continue;
      final cached = _senderCache[senderId];
      if (cached != null) {
        _patchSender(cached, senderId);
        if (!_resolvedSenderDetails.contains(senderId) &&
            !_resolvingSenders.contains(senderId)) {
          pending.add(senderId);
        }
      } else if (!_resolvingSenders.contains(senderId)) {
        pending.add(senderId);
      }
    }
    for (final senderId in pending) {
      _resolvingSenders.add(senderId);
      _resolveSender(senderId);
    }
  }

  void _primeCachedSenderIdentities(List<ChatMessage> batch) {
    for (final message in batch) {
      if ((message.isOutgoing && !message.senderIsChat) || message.isService) {
        continue;
      }
      final senderId = message.senderId;
      if (senderId == null || senderId <= 0) continue;
      final user = TdUserIndex.shared.userFor(_client.activeSlot, senderId);
      if (user == null) continue;
      final existing = _senderCache[senderId];
      final info = _senderInfoFromUser(
        user,
        role: existing?.role ?? MemberRole.member,
        title: existing?.title,
      );
      _senderCache[senderId] = info;
      _patchSender(info, senderId);
    }
  }

  @visibleForTesting
  void primeCachedSenderIdentitiesForTesting() {
    _primeCachedSenderIdentities(messages);
  }

  @visibleForTesting
  void applySenderUserUpdateForTesting(Map<String, dynamic> user) {
    _applySenderUserUpdate(user);
  }

  void _applySenderUserUpdate(Map<String, dynamic> user) {
    if (!isGroup) return;
    final userId = user.int64('id');
    if (userId == null) return;
    final isVisibleSender = messages.any(
      (message) =>
          message.senderId == userId &&
          !(message.isOutgoing && !message.senderIsChat) &&
          !message.isService,
    );
    if (!isVisibleSender && !_senderCache.containsKey(userId)) return;
    final existing = _senderCache[userId];
    final info = _senderInfoFromUser(
      user,
      role: existing?.role ?? MemberRole.member,
      title: existing?.title,
    );
    _senderCache[userId] = info;
    _patchSender(info, userId);
  }

  _SenderInfo _senderInfoFromUser(
    Map<String, dynamic> user, {
    required MemberRole role,
    required String? title,
  }) {
    return _SenderInfo(
      TDParse.userName(user),
      TDParse.smallPhoto(user.obj('profile_photo')),
      role,
      title,
      isPremium: user.boolean('is_premium') ?? false,
      accentColorId: user.integer('accent_color_id') ?? -1,
      emojiStatusId: TDParse.emojiStatusCustomEmojiId(user.obj('emoji_status')),
    );
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
            // The string reads "and N others" — N is the remainder beyond
            // the listed names, not the total joiner count.
            'value1': message.serviceUserIds.length - names.length,
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
    try {
      _SenderInfo info;
      if (senderId > 0) {
        Map<String, dynamic>? user = TdUserIndex.shared.userFor(
          _client.activeSlot,
          senderId,
        );
        if (user == null) {
          try {
            user = await _client.query({
              '@type': 'getUser',
              'user_id': senderId,
            });
          } catch (_) {
            // A discovery update can still be in flight. Do not permanently
            // cache a placeholder; updateUser will patch the sender when it
            // arrives, and a later batch remains free to retry resolution.
            return;
          }
        }
        final existing = _senderCache[senderId];
        final immediate = _senderInfoFromUser(
          user,
          role: existing?.role ?? MemberRole.member,
          title: existing?.title,
        );
        if (_isDisposed) return;
        _senderCache[senderId] = immediate;
        _patchSender(immediate, senderId);
        final role = isChannel
            ? (MemberRole.member, null)
            : await _resolveRole(senderId);
        final latestUser =
            TdUserIndex.shared.userFor(_client.activeSlot, senderId) ?? user;
        info = _senderInfoFromUser(latestUser, role: role.$1, title: role.$2);
      } else {
        try {
          final chat = await _client.query({
            '@type': 'getChat',
            'chat_id': senderId,
          });
          info = _SenderInfo(
            chat.str('title') ??
                telegramText(AppStringKeys.chatInfoGroupMembers),
            TDParse.smallPhoto(chat.obj('photo')),
            MemberRole.channel,
            null,
          );
        } catch (_) {
          info = _SenderInfo(
            telegramText(AppStringKeys.chatInfoGroupMembers),
            null,
            MemberRole.channel,
            null,
          );
        }
      }
      if (_isDisposed) return;
      _senderCache[senderId] = info;
      _resolvedSenderDetails.add(senderId);
      final activeAction = _chatActions[senderId];
      if (activeAction != null && activeAction.name.isEmpty) {
        _chatActions[senderId] = _ChatActionInfo(
          info.name,
          activeAction.actionType,
        );
      }
      _patchSender(info, senderId);
    } finally {
      _resolvingSenders.remove(senderId);
    }
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
