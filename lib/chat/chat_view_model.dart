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
import 'package:shared_preferences/shared_preferences.dart';

import '../channels/topic_list_actions.dart';
import '../config/build_flags.dart';
import '../notifications/notification_settings_payload.dart';
import '../settings/blocked_user_service.dart';
import '../settings/ghost_mode_controller.dart';
import '../settings/hidden_sender_store.dart';
import '../settings/keyword_blocker.dart';
import '../tdlib/forum_topic_index.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../tdlib/td_requests.dart';
import '../tdlib/td_user_index.dart';
import 'ai_translation/ai_reply_service.dart';
import 'ai_translation/telegram_ai_service.dart';
import 'ai_translation/unread_chat_summary_models.dart';
import 'chat_auto_scroll_policy.dart';
import 'chat_first_contact_info.dart';
import 'chat_message_merge.dart';
import 'chat_open_performance.dart';
import 'chat_send_failure.dart';
import 'chat_unread_progress.dart';
import 'composer/checklist_composer_view.dart';
import 'composer/checklist_service.dart';
import 'composer/message_send_options.dart';
import 'composer/outgoing_attachment.dart';
import 'composer/poll_composer_view.dart';
import 'composer/rich_message_source.dart';
import 'forum_topic_transcript.dart';
import 'links_search/link_preview_fixer.dart';
import 'messages/forward_markdown.dart';
import 'messages/forward_options.dart';
import 'messages/message_reaction_availability.dart';
import 'messages/message_text_quote.dart';
import 'messages/pangu_spacing.dart';
import 'messages/quick_reaction_choice.dart';
import 'secret_chat_service.dart';
import 'sponsored_messages_cache.dart';
import 'stickers/gif_item.dart';
import 'stickers/sticker_item.dart';

part 'chat_view_model_types.dart';
part 'chat_view_model_sending.dart';
part 'chat_view_model_actions.dart';
part 'chat_view_model_header_topics.dart';
part 'chat_view_model_history_paging.dart';
part 'chat_view_model_updates_merge.dart';

class ChatViewModel extends ChangeNotifier {
  static const int _maximumAiReplyContextMessages = 64;

  static const int _maximumAiReplySearchCharacters = 160;

  ChatViewModel({
    required this.chatId,
    required String title,
    required this.markReadOnOpen,
    this.initialMessageId,
    this.sessionAnchorMessageId,
    this.sessionFallbackOpenAtLatest,
    List<ChatMessage>? sessionMessages,
    bool sessionAnchoredHistory = false,
    ChatFirstContactInfo? sessionFirstContactInfo,
    ChatMessage? seedMessage,
    this.forumTopicId,
  }) : _accountClientId = TdClient.shared.activeClientId,
       _accountSlot = TdClient.shared.activeSlot,
       peerTitle = title {
    // A pane rebuilt for another topic renders its rail from the shared index
    // on the first frame; loadForumTopics refreshes it moments later.
    final indexed = ForumTopicIndex.shared.topicsFor(_accountSlot, chatId);
    if (indexed.isNotEmpty) {
      forumTopics = [for (final entry in indexed) _optionFromIndex(entry)];
    }
    _historyAnchorMessageId = initialMessageId ?? sessionAnchorMessageId;
    if (sessionMessages != null && sessionMessages.isNotEmpty) {
      _allMessages = List<ChatMessage>.from(sessionMessages);
      messages = List<ChatMessage>.from(sessionMessages);
      _knownLatestMessageId = latestServerMessageId(sessionMessages);
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

  /// When set, this transcript shows a single forum topic as an ordinary
  /// chat: history, search, drafts, sends and live updates are scoped to it.
  final int? forumTopicId;

  bool get isForumTopicTranscript => (forumTopicId ?? 0) != 0;

  void _onForumTopicIndexChanged() {
    // Only the topic list is live-indexed here: a transcript's own unread
    // state arrives through its chat-scoped updates, and topics of other
    // chats never move this view model.
    final indexed = ForumTopicIndex.shared.topicsFor(_accountSlot, chatId);
    if (indexed.isEmpty) return;
    final previous = forumTopics;
    // The index owns identity + counters; row-only fields (preview, pin,
    // closed, creator) stay with the option that already carries them.
    final byId = {for (final option in previous) option.id: option};
    var same = indexed.length == previous.length;
    final next = <ForumTopicOption>[];
    for (final entry in indexed) {
      final option =
          byId[entry.id]?._withIndex(entry) ?? _optionFromIndex(entry);
      if (same && !option.sameDisplay(previous[next.length])) same = false;
      next.add(option);
    }
    if (same) return;
    forumTopics = next;
    notifyListeners();
  }

  Map<String, dynamic>? get _forumTopicRef => isForumTopicTranscript
      ? {'@type': 'messageTopicForum', 'forum_topic_id': forumTopicId}
      : null;

  /// Whether [raw] (a TDLib `message`) belongs to this transcript.
  ///
  /// In a bot topic chat there is no General topic, so an unattributed
  /// message must not fall back to it (see
  /// [rawMessageBelongsToForumTopic]).
  bool _belongsToTranscript(Map<String, dynamic> raw) =>
      !isForumTopicTranscript ||
      rawMessageBelongsToForumTopic(
        raw,
        forumTopicId!,
        isGeneralFallbackAllowed: isForum,
      );

  /// Rewrites a chat-wide history request into its topic-scoped equivalent.
  Map<String, dynamic> _scopedHistoryRequest(Map<String, dynamic> request) =>
      isForumTopicTranscript
      ? forumTopicHistoryRequest(request, forumTopicId!)
      : request;

  /// The topic's display name once loaded; empty for ordinary transcripts.
  String forumTopicName = '';

  Future<Map<String, dynamic>> _queryHistory(
    Map<String, dynamic> request,
  ) async {
    final scoped = _scopedHistoryRequest(request);
    if (scoped.type != 'getForumTopicHistory') return _client.query(scoped);
    try {
      return await _client.query(scoped);
    } catch (_) {
      return _client.query(forumTopicThreadHistoryRequest(scoped));
    }
  }

  Future<Map<String, dynamic>?> _loadForumTopic() async {
    try {
      final topic = await _client.query({
        '@type': 'getForumTopic',
        'chat_id': chatId,
        'forum_topic_id': forumTopicId,
      });
      forumTopicName = topic.obj('info')?.str('name') ?? forumTopicName;
      return topic;
    } catch (_) {
      return null;
    }
  }

  final int? initialMessageId;

  final int? sessionAnchorMessageId;

  final bool? sessionFallbackOpenAtLatest;

  final bool markReadOnOpen;

  /// 盘古之白 for outgoing text, mirrored from ThemeController by the view that
  /// owns this model: the model itself has no theme access.
  bool panguOnSend = false;

  /// 盘古之白 for edits, which rewrite a message the other side already read.
  bool panguOnEdit = false;

  int? _historyAnchorMessageId;

  int? get historyAnchorMessageId => _historyAnchorMessageId;

  List<ChatMessage> messages = [];

  List<ChatMessage> _allMessages = [];

  // Lookup indexes over the two transcript lists, filled by the single pass in
  // _applyKeywordFilter. Folding one update used to linear-scan the whole
  // transcript several times (id lookups, sender patches); at a few thousand
  // loaded messages that scanning dominated the incoming-update path.
  final Map<int, ChatMessage> _messagesById = {};

  final Map<int, ChatMessage> _allMessagesById = {};

  final Map<int, List<ChatMessage>> _messagesBySenderId = {};

  final Map<int, ValueNotifier<int>> _messageRevisionNotifiers = {};

  final ValueNotifier<int> _headerRevisionNotifier = ValueNotifier<int>(0);

  int _transcriptScanVisitsForTesting = 0;

  bool _messageIndexesDirty = true;

  // A pending send makes compareChatMessagesChronologically non-total, so the
  // order-preserving shortcuts below only run while there are none.
  int _pendingMessageCount = 0;

  String peerTitle;

  TdFileRef? peerPhoto;

  ChatFirstContactInfo? firstContactInfo;

  ChatKind? chatKind;

  bool isGroup = false;

  int memberCount = 0;

  int? peerUserId;

  // private chat → call target
  int? peerBasicGroupId;

  int? peerSupergroupId;

  String meName = AppStrings.t(AppStringKeys.chatMeLabel);

  int? meId;

  Set<String> meUsernames = const <String>{};

  TdFileRef? mePhoto;

  String draft = '';

  String _draftFormattedText = '';

  List<Map<String, dynamic>> _draftFormattedEntities = const [];

  final List<_DraftMention> _draftMentions = [];

  ChatMessage? _replyTo;

  MessageTextQuote? _replyQuote;

  /// Bumped every time the pending reply changes. A send stamps the
  /// revision it captured; when it completes, it only consumes the reply
  /// if the user hasn't picked a different one in the meantime.
  int _replyRevision = 0;

  ChatMessage? get replyTo => _replyTo;

  set replyTo(ChatMessage? message) {
    _replyTo = message;
    _replyQuote = null;
    _replyRevision++;
  }

  MessageTextQuote? get replyQuote => _replyQuote;

  /// The forum-topic destination for inline-bot and gif sends when this
  /// transcript is scoped to one topic.
  Map<String, dynamic>? get forumTopicSendRef => _forumTopicRef;

  Map<String, dynamic>? get replyToInput => replyTo == null
      ? null
      : {
          '@type': 'inputMessageReplyToMessage',
          'message_id': replyTo!.id,
          if (!isSecretChat && _replyQuote != null)
            'quote': _replyQuote!.toInputJson(),
        };

  /// Panel sends (sticker, GIF, voice note, poll, …) can't attach the reply
  /// anchor inside their content payloads, so they route through this helper:
  /// it stamps the pending reply onto the request and returns the revision
  /// the stamp was taken at. The send later consumes the reply only when
  /// that revision is still current, so completing an older send never
  /// clears a reply the user selected meanwhile. Failed sends keep the
  /// reply for retry, mirroring the text path's contract.
  ({Map<String, dynamic> request, int revision}) _withReplyAnchor(
    Map<String, dynamic> request,
  ) {
    final revision = _replyRevision;
    if (replyTo != null) {
      request['reply_to'] = replyToInput;
    }
    return (request: request, revision: revision);
  }

  /// Consumes the pending reply only if it is still the one [revision]
  /// stamped. A newer selection survives; a consumed anchor reports false.
  bool _consumeReplyAnchorIfCurrent(int revision) {
    if (replyTo == null) return false;
    if (revision != _replyRevision) return false;
    replyTo = null;
    notifyListeners();
    return true;
  }

  ChatMessage? editingMessage;

  String? _draftBeforeEditing;

  String _formattedDraftBeforeEditing = '';

  List<Map<String, dynamic>> _entitiesBeforeEditing = const [];

  List<_DraftMention> _mentionsBeforeEditing = const [];

  ChatMessage? _replyBeforeEditing;

  MessageTextQuote? _replyQuoteBeforeEditing;

  List<MessageSenderOption> availableMessageSenders = const [];

  MessageSenderOption? selectedMessageSender;

  Map<String, dynamic>? _messageSenderFromChat;

  // Live header state.
  bool peerOnline = false;

  String peerStatusText = '';

  int lastReadOutboxId = 0;

  // outgoing messages with id <= this are read
  int lastReadInboxId = 0;

  // incoming messages with id <= this are read
  int unreadCount = 0;

  // unread incoming messages on entry (for the divider)
  UnreadChatRangeSnapshot? unreadSummarySnapshot;

  bool _didCaptureUnreadSummaryRange = false;

  int unreadMentionCount = 0;

  int unreadReactionCount = 0;

  bool isMarkedUnread = false;

  // manual unread marker on the chat row
  bool initialLoaded = false;

  // first history page (+ unread boundary) is in
  bool anchoredHistory = false;

  // transcript is centered on an arbitrary target

  // 群公告 / pinned message shown in a bar below the header.
  ChatMessage? pinnedMessage;

  List<ChatMessage> pinnedMessages = const [];

  int pinnedMessageIndex = 0;

  bool pinnedDismissed = false;

  /// The pinned ids the bar was closed over, remembered on this device for
  /// this account and chat (and topic); null while the bar is not closed.
  Set<int>? _pinnedDismissedIds;

  Future<void>? _pinnedDismissalLoad;

  String? _pinnedDismissalKey;

  bool _pinnedDismissalChanged = false;

  // Membership / send permission. Defaults assume a normal, joined, sendable
  // chat; refined in _loadChatHeader once the chat type + member status load.
  bool canSendMessages = true;

  // composer enabled
  bool canSendVoiceNotes = true;

  bool isMember = true;

  // gates 退出; false → join affordance
  bool canJoin = false;

  // not a member but joinable (public super/channel/left)
  bool joinByRequest = false;

  // joining needs approval → "申请加入"
  bool joinRequested = false;

  // a join request was sent (awaiting approval)
  bool isChannel = false;

  // broadcast channel (members can't post)
  bool isMessageBubbleRepository = false;

  bool hasLinkedDiscussion = false;

  bool isDirectMessagesGroup = false;

  bool isAdministeredDirectMessagesGroup = false;

  bool isMuted = false;

  // notifications muted (channel subscribers get a toggle)
  bool canDeleteMessagesBySender = false;

  String sendDisabledReason = '';

  // shown in the disabled composer bar
  bool isPeerRestricted = false;

  bool isPeerPornographicRestricted = false;

  String peerRestrictionText = '';

  bool hasProtectedContent = false;

  bool _chatCanSend = true;

  // chat-wide default can_send_basic_messages

  /// Topic moderation rights for forum chats. Creating needs the
  /// can_manage_topics administrator right or the can_create_topics member
  /// right; pinning/editing/closing need can_manage_topics; deleting needs
  /// can_delete_messages unless the user created the topic.
  bool _chatCanCreateTopics = false;

  bool canManageTopics = false;

  bool canDeleteForumTopics = false;

  bool get canCreateForumTopics => _chatCanCreateTopics || canManageTopics;

  /// Per-topic creator deletion eligibility, verified against the topic's
  /// actual message history. TDLib's deleteForumTopic allows a non-admin
  /// creator to delete only while the topic holds at most 11 messages and
  /// none of them are from other users; creator identity alone is not
  /// sufficient. Cleared on topic traffic so the next menu open re-probes.
  final Map<int, bool> _creatorDeletableTopicIds = {};

  /// Whether this account may delete [topic] through the rights model, and —
  /// for the creator carve-out — the probed history limits. can_manage_topics
  /// grants management, not deletion; only can_delete_messages does.
  bool canDeleteTopic(ForumTopicOption topic) =>
      !topic.isGeneral &&
      (canDeleteForumTopics ||
          (meId != null &&
              topic.creatorId == meId &&
              (_creatorDeletableTopicIds[topic.id] ?? false)));

  /// Whether [topic] was created by this account.
  bool creatorOfTopic(ForumTopicOption topic) =>
      meId != null && topic.creatorId == meId;

  /// Probes whether the creator carve-out applies to [topicId]: at most 11
  /// messages and none from another user. The 12th message proves the limit
  /// is exceeded without paging further.
  Future<bool> ensureTopicCreatorDeletable(int topicId) async {
    if (!isForum || topicId == generalForumTopicId) return false;
    if (_creatorDeletableTopicIds.containsKey(topicId)) {
      return _creatorDeletableTopicIds[topicId]!;
    }
    bool eligible = false;
    try {
      final response = await _topicAccountQuery({
        '@type': 'getForumTopicHistory',
        'chat_id': chatId,
        'forum_topic_id': topicId,
        'from_message_id': 0,
        'offset': 0,
        'limit': 12,
      });
      final messages = response.objects('messages') ?? const [];
      eligible =
          messages.length <= 11 &&
          messages.every((raw) {
            if (raw.boolean('is_outgoing') ?? false) return true;
            final sender = raw.obj('sender_id');
            return sender?.type == 'messageSenderUser' &&
                sender?.int64('user_id') == meId;
          });
    } catch (_) {
      eligible = false;
    }
    _creatorDeletableTopicIds[topicId] = eligible;
    return eligible;
  }

  /// Drops the probed creator carve-out for any topic new traffic reached, so
  /// a topic that gained a 12th message or another user's message stops
  /// offering Delete on the next menu open.
  void _invalidateCreatorDeletionForTopic(int topicId) {
    if (_creatorDeletableTopicIds.remove(topicId) != null) {
      notifyListeners();
    }
  }

  bool peerIsBot = false;

  bool isBotApiAccount = false;

  bool botApiCanReadAllGroupMessages = false;

  bool botApiBotToBotAccessObserved = false;

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

  bool hasForumTabs = false;

  bool supportsBotTopics = false;

  bool get supportsTopics => isForum || supportsBotTopics;

  bool forumTopicsLoading = false;

  List<ForumTopicOption> forumTopics = const [];

  /// Resolved display names for topic-preview senders, kept across reloads so
  /// the row's "Alice: …" prefix survives a getForumTopics refresh.
  final Map<int, String> _topicSenderNames = {};

  /// Topic id → its last message's sender id, for late sender resolution.
  final Map<int, int> _topicRowSenderIds = {};

  int messageAutoDeleteTime = 0;

  int paidMessageStarCount = 0;

  /// Non-null once [loadForumTopics] registered the shared-index listener.
  /// ChangeNotifier.addListener returns void, so this only records whether
  /// the one-per-model registration happened (refreshes reuse it).
  bool _forumTopicIndexListening = false;

  bool peerRequiresPremiumOrContact = false;

  bool peerIsUnavailable = false;

  /// Loaded for channels and bot chats, but not yet rendered in the transcript.
  SponsoredMessagesSnapshot? sponsoredMessages;

  final TdClient _client = TdClient.shared;

  final int _accountClientId;

  final int _accountSlot;

  /// The account slot whose ids this transcript's data is scoped to.
  int get accountSlot => _accountSlot;

  int _groupBotCommandsGeneration = 0;

  Future<Set<String>>? _aiReplyBlockedSenderKeysFuture;

  int _aiReplyBlockedSenderRevision = 0;

  late final TelegramAiService telegramAi = TelegramAiService(client: _client);

  TelegramAiCapabilities? aiCapabilities;

  static final SponsoredMessagesCache _sponsoredMessagesCache =
      SponsoredMessagesCache();

  StreamSubscription? _sub;

  final ChatLiveMessageBuffer _liveIncomingMessages = ChatLiveMessageBuffer();

  bool _isLoadingOlder = false;

  bool _isLoadingNewer = false;

  final Set<int> _newerHistoryDeletedMessageIds = {};

  bool _hasOlderHistory = true;

  int? _pendingScrollToId;

  int? _lastForcedReadMessageId;

  bool _markReadInFlight = false;

  bool _restoredFromSession = false;

  bool _chatReadStateLoaded = false;

  bool get chatReadStateLoaded => _chatReadStateLoaded;

  int _chatReadStateRevision = 0;

  int get chatReadStateRevision => _chatReadStateRevision;

  int _chatReadInboxRevision = 0;

  bool _historyReachesLatest = false;

  bool get historyReachesLatest => _historyReachesLatest;

  int _knownLatestMessageId = 0;

  int get knownLatestMessageId => _knownLatestMessageId;

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

  final Set<int> _locallyViewedReactionIds = {};

  final Set<int> _blockedSenderIds = {};

  final Set<int> _discardedPendingMessageIds = {};

  final Set<int> _settledPendingMessageIds = {};

  final Set<int> _acknowledgedPendingMessageIds = {};

  final Map<int, Completer<void>> _messageSendWaiters = {};

  final Map<int, _MessageSendResult> _recentMessageSendResults = {};

  ChatSendFailure? _pendingSendFailure;

  String? _lastSendFailureKey;

  int _lastSendFailureAtMilliseconds = 0;

  Future<void>? _privateMessageInfoLoad;

  int? _privateMessageInfoUserId;

  bool _privateMessageInfoLoaded = false;

  // Transient chat actions: sender ids currently acting, auto-cleared shortly.
  final Map<int, _ChatActionInfo> _chatActions = {};

  Timer? _typingTimer;

  Timer? _draftSaveTimer;

  Timer? _coalescedNotifyTimer;

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
              ? AppStrings.t(AppStringKeys.presenceOnline)
              : peerStatusText);
    final action = _chatActionSubtitle;
    if (base.isEmpty) return action;
    if (action.isEmpty) return base;
    return '$base · $action';
  }

  /// The header title for this transcript: the topic's name when a forum topic
  /// is shown as an ordinary chat, otherwise the peer title.
  String get displayTitle =>
      forumTopicName.trim().isNotEmpty ? forumTopicName.trim() : peerTitle;

  bool get hasActiveChatAction => _chatActions.isNotEmpty;

  bool isRead(ChatMessage m) => isOutgoingServerMessageRead(
    message: m,
    lastReadOutboxId: lastReadOutboxId,
  );

  bool get canChooseMessageSender => availableMessageSenders.length > 1;

  bool get canForwardContent => !hasProtectedContent;

  bool get canLoadOlder =>
      !_isLoadingOlder &&
      !_latestHistoryLoadInFlight &&
      _allMessages.isNotEmpty &&
      _hasOlderHistory;

  bool get isLoadingOlder => _isLoadingOlder;

  bool get canLoadNewer =>
      !_chatOpenWorkIsStale &&
      !_isLoadingNewer &&
      !_latestHistoryLoadInFlight &&
      !_historyReachesLatest &&
      latestServerMessageId(_allMessages) > 0;

  bool get isLoadingLatest => _latestHistoryLoadInFlight;

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

  /// The chat is the account's own Saved Messages.
  bool get isSavedMessages => peerUserId != null && peerUserId == meId;

  /// Telegram accepts View Once and self-destructing media only in one-on-one
  /// chats with another person: not groups, channels, bots, Saved Messages or
  /// secret chats, which have their own message timer.
  bool get canSendSelfDestructingMedia =>
      canSendWhenOnline && !isSavedMessages && !isSecretChat;

  bool get showBotApiPrivacyWarning =>
      isBotApiAccount &&
      isGroup &&
      !isChannel &&
      !botApiCanReadAllGroupMessages;

  bool get showBotApiBotToBotWarning =>
      isBotApiAccount && isGroup && !isChannel && !botApiBotToBotAccessObserved;

  bool get showBotApiAccessWarning =>
      showBotApiPrivacyWarning || showBotApiBotToBotWarning;

  List<AvailableMessageEffect> availableMessageEffects = const [];

  MessageSendConfiguration? _nextSendConfiguration;

  String get inputPlaceholder =>
      AppStrings.t(AppStringKeys.chatMessageInputPlaceholder);

  final Map<int, _SenderInfo> _senderCache = {};

  final Set<int> _resolvingSenders = {};

  final Set<int> _resolvedSenderDetails = {};

  bool _isDisposed = false;

  bool get _chatOpenWorkIsStale => chatOpenWorkIsStale(
    disposed: _isDisposed,
    openingClientId: _accountClientId,
    openingAccountSlot: _accountSlot,
    activeClientId: _client.activeClientId,
    activeAccountSlot: _client.activeSlot,
  );

  int _composerRevision = 0;

  int _fullViewRevision = 0;

  int _composerFocusTick = 0;

  /// Bumped by every notification except the handful proven not to touch
  /// anything the composer renders, so the input bar can skip those rebuilds.
  /// Bumping is the default: a path that forgets to opt out stays correct.
  int get composerRevision => _composerRevision;

  /// Changes only when a notification can affect ChatView's shell, transcript
  /// boundaries, scrolling, or overlays. Header-only and in-place bubble
  /// updates keep this stable so ChatView can skip its O(n) synchronization.
  int get fullViewRevision => _fullViewRevision;

  ValueListenable<int> get headerRevisionListenable => _headerRevisionNotifier;

  /// Bumped when a gesture outside the composer asks for the caret. The reply
  /// target itself travels with [setReply]; this only says "and start typing".
  int get composerFocusTick => _composerFocusTick;

  /// Hands the composer the caret without touching its draft or revision.
  void requestComposerFocus() {
    if (_isDisposed) return;
    _composerFocusTick++;
    super.notifyListeners();
  }

  ValueListenable<int> messageRevisionListenable(int messageId) =>
      _messageRevisionNotifiers.putIfAbsent(
        messageId,
        () => ValueNotifier<int>(0),
      );

  @visibleForTesting
  int get transcriptScanVisitsForTesting => _transcriptScanVisitsForTesting;

  @visibleForTesting
  int get messageRevisionNotifierCountForTesting =>
      _messageRevisionNotifiers.length;

  @visibleForTesting
  void resetTranscriptScanVisitsForTesting() {
    _transcriptScanVisitsForTesting = 0;
  }

  @visibleForTesting
  void primeMessageIndexesForTesting() {
    _ensureMessageIndexes();
  }

  bool _recordTranscriptScanVisitForTesting() {
    _transcriptScanVisitsForTesting++;
    return true;
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    _composerRevision++;
    _fullViewRevision++;
    super.notifyListeners();
  }

  /// Notifies without bumping [composerRevision]. Only for state no composer
  /// widget reads — the typing subtitle and the peer's online status, both of
  /// which belong to the header.
  void _notifyComposerNeutral() {
    if (_isDisposed) return;
    _headerRevisionNotifier.value++;
    super.notifyListeners();
  }

  /// Rebuilds only materialized bubbles for [messageIds]. The regular model
  /// notification is deliberately retained: ChatInputBar uses it to invalidate
  /// AI context and preserves its focused revision-rebuild policy.
  void _notifyLocalizedMessages(Iterable<int> messageIds) {
    if (_isDisposed) return;
    if (!_bumpMaterializedMessageRevisions(messageIds)) return;
    _composerRevision++;
    super.notifyListeners();
  }

  /// Refreshes materialized bubbles while retaining ChatView's full sync for
  /// cross-message and shell dependencies such as translation and overlays.
  void _notifyMessagesWithFullViewSync(Iterable<int> messageIds) {
    if (_isDisposed) return;
    if (!_bumpMaterializedMessageRevisions(messageIds)) return;
    notifyListeners();
  }

  bool _bumpMaterializedMessageRevisions(Iterable<int> messageIds) {
    var changed = false;
    for (final messageId in messageIds.toSet()) {
      final notifier = _messageRevisionNotifiers[messageId];
      if (notifier != null) notifier.value++;
      changed = true;
    }
    return changed;
  }

  int? consumePendingScrollToId() {
    final id = _pendingScrollToId;
    _pendingScrollToId = null;
    return id;
  }

  List<int> consumeLiveIncomingMessageIds() => _liveIncomingMessages.takeAll();

  ChatSendFailure? consumeSendFailure() {
    final failure = _pendingSendFailure;
    _pendingSendFailure = null;
    return failure;
  }

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
    final topic = _forumTopicRef;
    if (topic != null && request.int64('chat_id') == chatId) {
      request.remove('message_thread_id');
      request['topic_id'] = topic;
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

  Future<bool> prepareMessageSend() async {
    if (!canSendMessages) return false;
    final userId = peerUserId;
    if (isGroup || isSecretChat || peerIsBot || userId == null) return true;
    await _loadPrivatePaidMessageInfo(userId);
    if (peerIsUnavailable) {
      _publishSendFailure(ChatSendFailure.recipientUnavailable());
      return false;
    }
    if (peerRequiresPremiumOrContact) {
      _publishSendFailure(ChatSendFailure.premiumOrContactRequired());
      return false;
    }
    return true;
  }

  /// Points TDLib at a preview mirror for the message's first link when the user
  /// opted in to fixing link previews. Requests that already carry
  /// `link_preview_options` keep them: an explicit choice beats a preference.
  Map<String, dynamic> _withFixedLinkPreview(Map<String, dynamic> request) =>
      LinkPreviewFixer.shared.applyTo(request);

  Future<bool> _submitMessageRequest(Map<String, dynamic> request) async {
    try {
      await _client.query(
        _withPaidMessageOptions(_withFixedLinkPreview(request)),
      );
      return true;
    } catch (error) {
      _publishSendFailure(
        ChatSendFailure.fromError(
          error,
          paidMessageStarCount: paidMessageStarCount,
        ),
      );
      return false;
    }
  }

  /// Panel fire-and-forget sends: stamps the reply anchor, submits the
  /// request and consumes the reply only after the send actually
  /// succeeded — and only if the user hasn't selected a newer reply in
  /// the meantime. A failed send keeps the reply for retry.
  void _submitPanelMessage(Map<String, dynamic> request) {
    final stamped = _withReplyAnchor(request);
    unawaited(
      _submitMessageRequest(stamped.request).then((sent) {
        if (sent) _consumeReplyAnchorIfCurrent(stamped.revision);
      }),
    );
  }

  void _submitMessageRequestWithoutWaiting(Map<String, dynamic> request) {
    unawaited(_submitMessageRequest(request));
  }

  void _publishSendFailure(ChatSendFailure failure) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastSendFailureKey == failure.deduplicationKey &&
        now - _lastSendFailureAtMilliseconds < 1500) {
      return;
    }
    _lastSendFailureKey = failure.deduplicationKey;
    _lastSendFailureAtMilliseconds = now;
    _pendingSendFailure = failure;
    notifyListeners();

    if (failure.kind == ChatSendFailureKind.paidMessageRequired ||
        failure.kind == ChatSendFailureKind.premiumRequired) {
      final userId = peerUserId;
      if (!isGroup && !isSecretChat && userId != null) {
        unawaited(_loadPrivatePaidMessageInfo(userId, force: true));
      }
    }
  }

  // MARK: - Lifecycle

  void onAppear() {
    _client.send({'@type': 'openChat', 'chat_id': chatId});
    _subscribeToUpdates();
    KeywordBlocker.shared.removeListener(_applyKeywordFilter);
    KeywordBlocker.shared.addListener(_applyKeywordFilter);
    HiddenSenderStore.shared.removeListener(_applyKeywordFilter);
    HiddenSenderStore.shared.addListener(_applyKeywordFilter);
    () async {
      unawaited(_loadMe());
      unawaited(_loadAiCapabilities());
      unawaited(_loadBotApiAccessInfo());
      await _loadChatHeader();
      if (_chatOpenWorkIsStale) return;
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
        if (_chatOpenWorkIsStale) return;
      } else if (sessionAnchorMessageId != null) {
        var restored = await loadAroundMessage(
          sessionAnchorMessageId!,
          scrollToTarget: false,
          onlyLocal: true,
        );
        if (_chatOpenWorkIsStale) return;
        if (!restored) {
          restored = await loadAroundMessage(
            sessionAnchorMessageId!,
            scrollToTarget: false,
          );
          if (_chatOpenWorkIsStale) return;
        }
        if (!restored) {
          await _loadInitialHistory(
            openAtLatest: sessionFallbackOpenAtLatest ?? markReadOnOpen,
          );
          if (_chatOpenWorkIsStale) return;
        }
      } else {
        await _loadInitialHistory(openAtLatest: markReadOnOpen);
        if (_chatOpenWorkIsStale) return;
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
      _notifyLocalizedMessages([messageId]);
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
      final usernames = me.obj('usernames');
      final active = usernames?['active_usernames'];
      final editable = usernames?.str('editable_username');
      meUsernames = Set.unmodifiable({
        if (active is List)
          for (final username in active.whereType<String>())
            if (username.trim().isNotEmpty)
              username.trim().replaceFirst('@', '').toLowerCase(),
        if (editable?.trim().isNotEmpty == true)
          editable!.trim().replaceFirst('@', '').toLowerCase(),
      });
      mePhoto = TDParse.smallPhoto(me.obj('profile_photo'));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadBotApiAccessInfo() async {
    try {
      final info = await _client.query({'@type': 'getBotApiAccountInfo'});
      if (info.type != 'botApiAccountInfo' || _chatOpenWorkIsStale) return;
      isBotApiAccount = true;
      botApiCanReadAllGroupMessages =
          info.boolean('can_read_all_group_messages') ?? false;
      botApiBotToBotAccessObserved =
          info.boolean('bot_to_bot_access_observed') ?? false;
      notifyListeners();
    } catch (_) {
      // Native TDLib accounts do not implement this Bot API-only query.
    }
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
      selectedMessageSender = preferredMessageSenderOption(
        loaded,
        preferredSender: _messageSenderFromChat,
        current: selectedMessageSender,
      );
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
    _messageSenderFromChat = option.sender;
    notifyListeners();
    try {
      await _client.query({
        '@type': 'setChatMessageSender',
        'chat_id': chatId,
        'message_sender_id': option.sender,
      });
    } catch (_) {
      selectedMessageSender = previous;
      _messageSenderFromChat = previous?.sender;
      notifyListeners();
    }
  }

  void onDisappear() {
    if (editingMessage != null) {
      _restoreComposerAfterMessageEdit(notify: false);
    }
    _flushPendingDraftSave();
    _sub?.cancel();
    _sub = null;
    KeywordBlocker.shared.removeListener(_applyKeywordFilter);
    HiddenSenderStore.shared.removeListener(_applyKeywordFilter);
    _client.send({'@type': 'closeChat', 'chat_id': chatId});
  }

  @override
  void dispose() {
    _isDisposed = true;
    KeywordBlocker.shared.removeListener(_applyKeywordFilter);
    HiddenSenderStore.shared.removeListener(_applyKeywordFilter);
    if (_forumTopicIndexListening) {
      ForumTopicIndex.shared.removeListener(_onForumTopicIndexChanged);
      _forumTopicIndexListening = false;
    }
    _sub?.cancel();
    _typingTimer?.cancel();
    _draftSaveTimer?.cancel();
    _coalescedNotifyTimer?.cancel();
    for (final waiter in _messageSendWaiters.values) {
      if (!waiter.isCompleted) {
        waiter.completeError(StateError('Chat view model was disposed'));
      }
    }
    _messageSendWaiters.clear();
    for (final notifier in _messageRevisionNotifiers.values) {
      notifier.dispose();
    }
    _messageRevisionNotifiers.clear();
    _headerRevisionNotifier.dispose();
    telegramAi.dispose();
    super.dispose();
  }

  /// Tell TDLib the user is typing (drives the peer's typing indicator).
  void sendTyping() {
    if (allowTelegramTosViolations &&
        GhostModeController.shared.shouldBlockTyping(chatId).isBlock) {
      return;
    }
    _client.send({
      '@type': 'sendChatAction',
      'chat_id': chatId,
      'topic_id': ?_forumTopicRef,
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
    if (editingMessage == null) _scheduleDraftSave();
  }

  String get composerFormattedDraft => _draftFormattedText;

  List<Map<String, dynamic>> get composerDraftEntities =>
      List.unmodifiable(_draftFormattedEntities);

  bool get editingMessageUsesCaption => switch (editingMessage?.contentType) {
    'messagePhoto' ||
    'messageVideo' ||
    'messageAnimation' ||
    'messageAudio' ||
    'messageDocument' => true,
    _ => false,
  };

  /// Sends text that may contain inline custom emoji — [entities] is the list of
  /// TDLib textEntity objects (e.g. textEntityTypeCustomEmoji) over [text]
  /// (offsets in UTF-16 of [text], which already has the fallback chars).
  Future<bool> sendFormatted(
    String text,
    List<Map<String, dynamic>> entities,
  ) async {
    if (!canSendMessages) return false;
    if (text.trim().isEmpty) return false;
    if (entities.isEmpty && _diceEmojis.contains(text.trim())) {
      return _sendDice(text);
    }
    final spaced = _spacedOutgoing(text, entities);
    final allEntities = [
      ...spaced.entities,
      ..._mentionEntitiesFor(spaced.text, spaced.entities),
    ];
    final request = <String, dynamic>{
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessageText',
        'text': {
          '@type': 'formattedText',
          'text': spaced.text,
          if (allEntities.isNotEmpty) 'entities': allEntities,
        },
      },
    };
    final replyRevision = _replyRevision;
    if (replyTo != null) {
      request['reply_to'] = replyToInput;
    }
    final sent = await _submitMessageRequest(request);
    if (!sent) return false;
    _consumeReplyAnchorIfCurrent(replyRevision);
    _clearDraft();
    notifyListeners();
    return true;
  }

  Future<void> sendRichMessageHtml(
    String html, {
    List<RichMessageSendFile> files = const [],
    List<Map<String, dynamic>> blocks = const [],
  }) async {
    final botApiDirect = await _client.activeAccountUsesBotApi();
    if (!botApiDirect && blocks.isEmpty) {
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
      'input_message_content': botApiDirect
          ? botApiDirectRichMessageInputContent(html, files, blocks: blocks)
          : richMessageInputContent(blocks),
    };
    final replyRevision = _replyRevision;
    if (replyTo != null) {
      request['reply_to'] = replyToInput;
    }
    final pendingMessage = await _client.query(
      _withPaidMessageOptions(request),
    );
    _consumeReplyAnchorIfCurrent(replyRevision);
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

  static const _diceEmojis = {'🎲', '🎯', '🏀', '⚽', '🎳', '🎰'};

  bool get canQuoteText =>
      canSendMessages && !isSecretChat && !hasProtectedContent;

  Future<bool> sendGif(GifItem gif) async {
    if (!canSendMessages) return false;
    try {
      final stamped = _withReplyAnchor(
        gifSendRequest(chatId: chatId, gif: gif),
      );
      final pendingMessage = await _client.query(
        _withPaidMessageOptions(stamped.request),
      );
      final pendingMessageId = pendingMessage.int64('id');
      if (pendingMessageId != null &&
          pendingMessage.obj('sending_state') != null) {
        await _waitForMessageSend(pendingMessageId);
      }
      _consumeReplyAnchorIfCurrent(stamped.revision);
      return true;
    } catch (error) {
      debugPrint('Failed to send GIF: $error');
      _publishSendFailure(
        ChatSendFailure.fromError(
          error,
          paidMessageStarCount: paidMessageStarCount,
        ),
      );
      return false;
    }
  }

  Future<bool> sendSticker(StickerItem sticker) async {
    if (!canSendMessages) return false;
    try {
      final stamped = _withReplyAnchor(stickerMessageRequest(sticker));
      final pendingMessage = await _client.query(stamped.request);
      final pendingMessageId = pendingMessage.int64('id');
      if (pendingMessageId != null &&
          pendingMessage.obj('sending_state') != null) {
        await _waitForMessageSend(pendingMessageId);
      }
      _consumeReplyAnchorIfCurrent(stamped.revision);
      return true;
    } catch (error) {
      debugPrint('Failed to send sticker: $error');
      _publishSendFailure(
        ChatSendFailure.fromError(
          error,
          paidMessageStarCount: paidMessageStarCount,
        ),
      );
      return false;
    }
  }

  /// Sends one voice note. A non-empty [caption] travels on the same message
  /// (`inputMessageVoiceNote.caption`) and clears the composer draft once
  /// TDLib accepts it, as a sent text would.
  ///
  /// With [reportGenericFailure] false, a failure the user can do nothing
  /// about beyond retrying is left to the caller to show; failures that need
  /// an action (stars, Premium, privacy, permissions…) are still published.
  Future<bool> sendVoice(
    String path,
    int duration, {
    String waveform = '',
    String caption = '',
    List<Map<String, dynamic>> captionEntities = const [],
    MessageSendConfiguration sendConfiguration =
        const MessageSendConfiguration(),
    bool reportGenericFailure = true,
  }) async {
    if (!canSendMessages || !canSendVoiceNotes) return false;
    final hasCaption = caption.trim().isNotEmpty;
    final spaced = hasCaption
        ? _spacedOutgoing(caption, captionEntities)
        : (text: '', entities: const <Map<String, dynamic>>[]);
    final allEntities = [
      ...spaced.entities,
      if (hasCaption) ..._mentionEntitiesFor(spaced.text, spaced.entities),
    ];
    try {
      final stamped = _withReplyAnchor(
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
            if (hasCaption)
              'caption': {
                '@type': 'formattedText',
                'text': spaced.text,
                if (allEntities.isNotEmpty) 'entities': allEntities,
              },
            'self_destruct_type': ?sendConfiguration.selfDestructType,
          },
        }, sendConfiguration: sendConfiguration),
      );
      await _client.query(stamped.request);
      _consumeReplyAnchorIfCurrent(stamped.revision);
      if (hasCaption) {
        _clearDraft();
        notifyListeners();
      }
      return true;
    } catch (error) {
      if (_isVoiceMessageRestrictionError(error)) {
        canSendVoiceNotes = false;
        notifyListeners();
      }
      debugPrint('Failed to send voice note: $error');
      final failure = ChatSendFailure.fromError(
        error,
        paidMessageStarCount: paidMessageStarCount,
      );
      if (reportGenericFailure || failure.kind != ChatSendFailureKind.generic) {
        _publishSendFailure(failure);
      }
      return false;
    }
  }

  bool get _canLoadAiReplyContext =>
      !_isDisposed &&
      !isSecretChat &&
      !hasProtectedContent &&
      _accountClientId > 0 &&
      _client.activeClientId == _accountClientId &&
      _client.activeSlot == _accountSlot;

  bool get canShareAiReplyContext => _canLoadAiReplyContext;

  /// True when the last bulk read lost some topics; the surface reads and
  /// clears it to raise one toast.
  bool _bulkReadFailed = false;

  static String _primaryUsername(Map<String, dynamic> user) {
    final usernames = user.obj('usernames');
    final active = usernames?['active_usernames'];
    if (active is List) {
      for (final value in active) {
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
    }
    final editable = usernames?.str('editable_username')?.trim();
    if (editable != null && editable.isNotEmpty) return editable;
    return (user.str('username') ?? '').trim();
  }

  static const _pinnedDismissalPrefix = 'mithka.pinnedBarDismissal.v1.user';

  bool get hasPreviousPinnedMessage => pinnedMessageIndex > 0;

  bool get hasNextPinnedMessage =>
      pinnedMessageIndex < pinnedMessages.length - 1;

  // MARK: - Live updates

  /// Every `@type` [_handle] has an arm for. Keep in sync with its switch: an
  /// omission silently stops that arm from ever running.
  static const _handledUpdateTypes = <String>[
    'updateNewMessage',
    'updateMessageContent',
    'updateMessageSuggestedPostInfo',
    'updateChatUnreadMentionCount',
    'updateMessageMentionRead',
    'updateChatUnreadReactionCount',
    'updateMessageUnreadReactions',
    'updateMessageSendSucceeded',
    'updateMessageSendAcknowledged',
    'updateMessageSendFailed',
    'updateSecretChat',
    'updateChat',
    'updateChatActionBar',
    'updateChatBusinessBotManageBar',
    'updateChatHasProtectedContent',
    'updateChatDraftMessage',
    'updateForumTopic',
    'updateChatMessageAutoDeleteTime',
    'updateChatPaidMessageStarCount',
    'updateDeleteMessages',
    'mithkaChatHistoryCleared',
    'mithkaChatLeft',
    'updateChatReadOutbox',
    'updateChatReadInbox',
    'updateChatIsMarkedAsUnread',
    'updateChatAction',
    'updateChatMessageSender',
    'updateUser',
    'updateUserFullInfo',
    'updateSupergroup',
    'updateSupergroupFullInfo',
    'updateBasicGroupFullInfo',
    'updateUserStatus',
    'updateMessageEdited',
    'updateMessageInteractionInfo',
    'updateMessageIsPinned',
    'updateAvailableMessageEffects',
    'updateBlockMessageSender',
  ];

  // MARK: - Reactions

  bool get _usesBotApiBackend =>
      isBotApiAccount || _client.isBotApiSlot(_accountSlot);

  /// True while the client this pane was opened on is still the active one.
  /// Destructive actions confirmed through a dialog re-check this after the
  /// await so the write cannot land on a replacement account.
  bool get isAccountCurrent =>
      !_isDisposed &&
      _accountClientId > 0 &&
      _client.activeClientId == _accountClientId &&
      _client.activeSlot == _accountSlot;

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

  // State the incremental append path needs to stay equivalent to the full
  // pass: what `blockedByUser` was last computed against, and every blocked id
  // in `_allMessages` (the read-boundary marker is handed the whole set each
  // time, because an arrival can move the boundary past an older blocked one).
  bool _marksBlockedUsers = false;

  List<int> _blockedMessageIds = <int>[];

  Set<int>? _ignoredMergeMessageIdsCache;

  /// Union of the two pending-id sets. Building it inline allocated a fresh
  /// set of up to 512 ids on every merge.
  Set<int> get _ignoredMergeMessageIds => _ignoredMergeMessageIdsCache ??= {
    ..._discardedPendingMessageIds,
    ..._settledPendingMessageIds,
  };

  final Set<int> _loadingFullRichMessageIds = <int>{};

  // Forwards arrive in runs from the same origin, and the resolver used to keep
  // no result and no in-flight set: a page with 20 forwards from one channel
  // fired 20 identical getChat round trips, and every later page repeated them.
  // Chat and user ids need separate maps — TDLib chat ids for groups/channels
  // are already negative, and a private chat id equals its user id.
  final Map<int, String> _forwardUserNames = {};

  final Map<int, String> _forwardChatTitles = {};

  final Map<int, List<ChatMessage>> _pendingForwardUsers = {};

  final Map<int, List<ChatMessage>> _pendingForwardChats = {};

  final Map<int, String> _viaBotUsernames = {};

  final Map<int, List<ChatMessage>> _pendingViaBotUsers = {};
}
