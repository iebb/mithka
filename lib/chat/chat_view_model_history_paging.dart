part of 'chat_view_model.dart';

extension ChatViewModelHistory on ChatViewModel {
  // MARK: - Paging

  /// Loads a bounded, read-only slice of older messages for an AI reply.
  ///
  /// Unlike [loadOlder] and [loadAroundMessage], this never merges messages
  /// into the transcript, moves the history window, or marks anything read.
  /// The TDLib client is captured with the view model so an account switch
  /// can't redirect a colliding chat id to another account while the request
  /// is in flight. [beforeMessageId] is an exclusive cursor; zero starts from
  /// the latest message available to TDLib.
  Future<AiReplyChatHistoryPage> loadAiReplyContext({
    required int beforeMessageId,
    required String query,
    required int limit,
  }) async {
    _requireAiReplyContextAccess();
    final blockedSenderKeys = await _aiReplyBlockedSenderKeys();
    _requireAiReplyContextAccess();

    final boundedBeforeMessageId = math.max(0, beforeMessageId);
    final boundedLimit = math.min(
      ChatViewModel._maximumAiReplyContextMessages,
      math.max(1, limit),
    );
    // TDLib includes from_message_id at offset zero. Ask for one extra item so
    // an exclusive cursor can still return the requested number of messages.
    final requestLimit = boundedBeforeMessageId > 0
        ? boundedLimit + 1
        : boundedLimit;
    final boundedQuery = _boundedAiReplySearchQuery(query);
    final request = boundedQuery.isEmpty
        ? <String, dynamic>{
            '@type': 'getChatHistory',
            'chat_id': chatId,
            'from_message_id': boundedBeforeMessageId,
            'offset': 0,
            'limit': requestLimit,
            'only_local': false,
          }
        : <String, dynamic>{
            '@type': 'searchChatMessages',
            'chat_id': chatId,
            'query': boundedQuery,
            'sender_id': null,
            'from_message_id': boundedBeforeMessageId,
            'offset': 0,
            'limit': requestLimit,
            'filter': {'@type': 'searchMessagesFilterEmpty'},
          };

    final Map<String, dynamic> response;
    try {
      response = await _client.queryTo(
        _scopedHistoryRequest(request),
        _accountClientId,
      );
    } catch (_) {
      _requireAiReplyContextAccess();
      return AiReplyChatHistoryPage(
        messages: const [],
        hasMore: true,
        blockedSenderKeys: blockedSenderKeys,
      );
    }
    _requireAiReplyContextAccess();

    final messagesById = <int, ChatMessage>{};
    final rawMessages =
        response.objects('messages') ?? const <Map<String, dynamic>>[];
    for (final raw in rawMessages) {
      final message = TDParse.message(raw);
      if (message == null ||
          message.id <= 0 ||
          (message.chatId != null && message.chatId != chatId) ||
          (boundedBeforeMessageId > 0 &&
              message.id >= boundedBeforeMessageId) ||
          !_canShareMessageWithAi(message, blockedSenderKeys)) {
        continue;
      }
      _hydrateAiReplySenderName(message);
      messagesById[message.id] = message;
      if (messagesById.length >= boundedLimit) break;
    }

    final result = messagesById.values.toList()
      ..sort(compareChatMessagesChronologically);
    final searchNextMessageId = response.int64('next_from_message_id');
    // TDLib may return fewer messages than requested without reaching the
    // beginning of chat history. Search responses expose an explicit cursor;
    // plain history does not, so only an empty page proves exhaustion there.
    final hasMore = boundedQuery.isNotEmpty
        ? searchNextMessageId == null
              ? rawMessages.isNotEmpty
              : searchNextMessageId != 0
        : rawMessages.isNotEmpty;
    return AiReplyChatHistoryPage(
      messages: List.unmodifiable(result),
      hasMore: hasMore,
      blockedSenderKeys: blockedSenderKeys,
    );
  }

  void _requireAiReplyContextAccess() {
    if (_canLoadAiReplyContext) return;
    throw AiReplyPrivacyException(
      AppStrings.t(AppStringKeys.aiReplyContextUnavailable),
    );
  }

  Future<Set<String>> _aiReplyBlockedSenderKeys() async {
    final existing = _aiReplyBlockedSenderKeysFuture;
    if (existing != null) return existing;
    final revision = _aiReplyBlockedSenderRevision;
    final future = () async {
      final result = await _fetchAiReplyBlockedSenderKeys();
      if (revision != _aiReplyBlockedSenderRevision) {
        return _aiReplyBlockedSenderKeys();
      }
      return result;
    }();
    _aiReplyBlockedSenderKeysFuture = future;
    try {
      return await future;
    } catch (_) {
      if (identical(_aiReplyBlockedSenderKeysFuture, future)) {
        _aiReplyBlockedSenderKeysFuture = null;
      }
      rethrow;
    }
  }

  Future<Set<String>> _fetchAiReplyBlockedSenderKeys() async {
    try {
      const pageLimit = 100;
      const maximumPages = 100;
      final blocked = <String>{};
      var offset = 0;
      for (var page = 0; page < maximumPages; page++) {
        _requireAiReplyContextAccess();
        final response = await _client.queryTo({
          '@type': 'getBlockedMessageSenders',
          'block_list': {'@type': 'blockListMain'},
          'offset': offset,
          'limit': pageLimit,
        }, _accountClientId);
        _requireAiReplyContextAccess();
        final senders =
            response.objects('senders') ?? const <Map<String, dynamic>>[];
        for (final raw in senders) {
          final sender = raw.obj('sender') ?? raw;
          final type = sender.type;
          final senderId = switch (type) {
            'messageSenderUser' => sender.int64('user_id'),
            'messageSenderChat' => sender.int64('chat_id'),
            _ => null,
          };
          final key = aiReplySenderKey(
            senderId: senderId,
            senderIsChat: type == 'messageSenderChat',
          );
          if (key != null) blocked.add(key);
        }
        // TDLib documents total_count as approximate, so it cannot safely
        // prove that every blocked sender was checked. A short page is the
        // only successful termination signal for this privacy gate.
        if (senders.length < pageLimit) {
          return Set.unmodifiable(blocked);
        }
        offset += senders.length;
      }
      throw AiReplyPrivacyException(
        AppStrings.t(AppStringKeys.aiReplyBlockedListTooLarge),
      );
    } on AiReplyPrivacyException {
      rethrow;
    } catch (_) {
      throw AiReplyPrivacyException(
        AppStrings.t(AppStringKeys.aiReplyBlockedCheckFailed),
      );
    }
  }

  String _boundedAiReplySearchQuery(String value) {
    final trimmed = value.trim();
    final runes = trimmed.runes.toList(growable: false);
    if (runes.length <= ChatViewModel._maximumAiReplySearchCharacters) {
      return trimmed;
    }
    return String.fromCharCodes(
      runes.take(ChatViewModel._maximumAiReplySearchCharacters),
    );
  }

  bool _canShareMessageWithAi(
    ChatMessage message,
    Set<String> blockedSenderKeys,
  ) {
    if (message.isService ||
        message.isContentRestricted ||
        message.blockedByUser ||
        message.text.trim().isEmpty) {
      return false;
    }
    if (message.isOutgoing) return true;

    final senderId = message.senderId;
    if (senderId != null && _blockedSenderIds.contains(senderId)) return false;
    final keywordBlocker = KeywordBlocker.shared;
    if (keywordBlocker.isSenderBlocked(senderId) ||
        keywordBlocker.matches(message.text) ||
        HiddenSenderStore.shared.hides(senderId, chatId)) {
      return false;
    }
    final senderKey = aiReplySenderKey(
      senderId: senderId,
      senderIsChat: message.senderIsChat,
    );
    return senderKey == null || !blockedSenderKeys.contains(senderKey);
  }

  void _hydrateAiReplySenderName(ChatMessage message) {
    if (message.senderName?.trim().isNotEmpty ?? false) return;
    if (message.isOutgoing && !message.senderIsChat) {
      message.senderName = meName;
      return;
    }

    final senderId = message.senderId;
    final cached = senderId == null ? null : _senderCache[senderId];
    if (cached != null && cached.name.trim().isNotEmpty) {
      message.senderName = cached.name;
      return;
    }
    if (senderId != null && senderId > 0 && !message.senderIsChat) {
      final user = TdUserIndex.shared.userFor(_accountSlot, senderId);
      if (user != null) {
        final name = TDParse.userName(user).trim();
        if (name.isNotEmpty) {
          message.senderName = name;
          return;
        }
      }
    }
    if (!isGroup && !message.isOutgoing && peerTitle.trim().isNotEmpty) {
      message.senderName = peerTitle.trim();
    }
  }

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
    if (_chatOpenWorkIsStale || _latestHistoryLoadInFlight) return false;
    final requestGeneration = ++_historyWindowGeneration;
    _latestHistoryLoadInFlight = true;
    _latestHistoryLiveArrivals.clear();
    _latestHistoryDeletedMessageIds.clear();
    _latestHistoryLoadInvalidated = false;
    notifyListeners();
    final messagesAtRequestStart = List<ChatMessage>.of(_allMessages);
    try {
      Map<String, dynamic> response;
      try {
        response = await _queryHistory({
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
      if (_chatOpenWorkIsStale ||
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
      _historyAnchorMessageId = null;
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
      notifyListeners();
    }

    return true;
  }

  /// Extends the current window toward the latest message without discarding
  /// unread history or changing its viewport anchor. A short TDLib page is not
  /// proof that we have reached the end of the chat.
  Future<bool> loadNewer() async {
    if (!canLoadNewer) return false;
    final fromMessageId = latestServerMessageId(_allMessages);
    final requestGeneration = _historyWindowGeneration;
    _isLoadingNewer = true;
    _newerHistoryDeletedMessageIds.clear();
    try {
      final response = await _queryHistory({
        '@type': 'getChatHistory',
        'chat_id': chatId,
        'from_message_id': fromMessageId,
        'offset': -30,
        'limit': 31,
        'only_local': false,
      });
      if (_chatOpenWorkIsStale ||
          requestGeneration != _historyWindowGeneration) {
        return false;
      }
      final parsed =
          (response.objects('messages') ?? const <Map<String, dynamic>>[])
              .map(TDParse.message)
              .whereType<ChatMessage>()
              .where(
                (message) =>
                    !_newerHistoryDeletedMessageIds.contains(message.id),
              )
              .toList();
      final newestId = latestServerMessageId(parsed);
      if (newestId <= fromMessageId) return false;
      _historyReachesLatest =
          _knownLatestMessageId > 0 && newestId >= _knownLatestMessageId;
      _knownLatestMessageId = math.max(_knownLatestMessageId, newestId);
      _merge(parsed);
      _resolveRichMessagesIfNeeded(parsed);
      _resolveSendersIfNeeded(parsed);
      _resolveRepliesIfNeeded(parsed);
      _resolveForwardsIfNeeded(parsed);
      _resolveServiceUsersIfNeeded(parsed);
      return true;
    } catch (error) {
      if (!_chatOpenWorkIsStale &&
          requestGeneration == _historyWindowGeneration &&
          _markPeerRestricted(error)) {
        notifyListeners();
      }
      return false;
    } finally {
      _isLoadingNewer = false;
      _newerHistoryDeletedMessageIds.clear();
    }
  }

  /// Called only after the reader reaches the actual latest edge. Unlike an
  /// explicit jump-to-latest, this keeps every paged message and its geometry.
  void resumeLatestHistoryIfLoaded() {
    if (!anchoredHistory || !_historyReachesLatest) return;
    anchoredHistory = false;
    _historyAnchorMessageId = null;
    notifyListeners();
  }

  /// Prevents an in-flight latest-history response from replacing the current
  /// anchored window after the user takes control of the transcript.
  ///
  /// TDLib does not expose cancellation for an already-sent query, so the
  /// generation check in [loadLatestHistory] discards its eventual response.
  void invalidateLatestHistoryLoad() {
    if (!_latestHistoryLoadInFlight) return;
    _latestHistoryLoadInvalidated = true;
    ++_historyWindowGeneration;
  }

  // MARK: - History

  Future<void> _loadInitialHistory({required bool openAtLatest}) async {
    if (shouldLoadInitialHistoryAroundLastRead(
      openAtLatest: openAtLatest,
      lastReadInboxId: lastReadInboxId,
      unreadCount: unreadCount,
    )) {
      final loaded = await _loadInitialAroundLastRead();
      if (_chatOpenWorkIsStale) return;
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
      scrollToTarget: false,
    );
    if (_chatOpenWorkIsStale) return false;
    if (loadedLocal) {
      if (isThinInitialHistoryWindow(messages.length)) {
        final loadedRemote = await loadAroundMessage(
          lastReadInboxId,
          scrollToTarget: false,
          replaceCurrentWindow: false,
        );
        if (_chatOpenWorkIsStale) return false;
        return loadedRemote;
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
    return loadAroundMessage(lastReadInboxId, scrollToTarget: false);
  }

  Future<void> _loadInitialLatestHistory() async {
    if (_chatOpenWorkIsStale) return;
    anchoredHistory = false;
    _historyAnchorMessageId = null;
    final localLoaded = await _fetchHistory(0, 0, 40, onlyLocal: true);
    if (_chatOpenWorkIsStale) return;
    if (shouldHydrateInitialHistoryInBackground(
      loadedMessageCount: _allMessages.length,
    )) {
      // The chat-list seed or a local TDLib page is enough to make the view
      // interactive. Refreshing through loadLatestHistory publishes its own
      // completion notification and blocks short-window paging from racing the
      // same remote request.
      unawaited(loadLatestHistory());
      return;
    }
    if (!localLoaded) await _fetchHistory(0, 0, 40);
  }

  Future<void> _hydrateRestoredLatestHistory() async {
    await _fetchHistory(0, 0, 40, onlyLocal: true);
    if (_chatOpenWorkIsStale) return;
    await _fetchHistory(0, 0, 40);
  }

  Future<bool> loadAroundMessage(
    int messageId, {
    bool onlyLocal = false,
    bool scrollToTarget = true,
    bool replaceCurrentWindow = true,
    bool Function()? isCancelled,
  }) async {
    bool cancelled() => isCancelled?.call() ?? false;

    if (_chatOpenWorkIsStale || cancelled()) return false;
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
      if (cancelled()) return false;
      final target = TDParse.message(targetRaw);
      if (target != null) batch.add(target);
    } catch (_) {
      if (cancelled()) return false;
      // A missing or restricted target message doesn't imply the containing
      // chat is restricted. Load its surrounding history when available.
    }

    if (_chatOpenWorkIsStale ||
        cancelled() ||
        requestGeneration != _historyWindowGeneration) {
      return false;
    }

    try {
      final response = await _queryHistory({
        '@type': 'getChatHistory',
        'chat_id': chatId,
        'from_message_id': messageId,
        'offset': -30,
        'limit': 80,
        'only_local': onlyLocal,
      });
      if (cancelled()) return false;
      batch.addAll(
        (response.objects('messages') ?? const <Map<String, dynamic>>[])
            .map(TDParse.message)
            .whereType<ChatMessage>(),
      );
    } catch (error) {
      if (cancelled()) return false;
      if (_markPeerRestricted(error)) notifyListeners();
    }

    if (_chatOpenWorkIsStale ||
        cancelled() ||
        requestGeneration != _historyWindowGeneration) {
      return false;
    }
    if (batch.isEmpty) return false;
    if (replaceCurrentWindow) {
      ++_historyWindowGeneration;
      ++_historyWindowRevision;
    }
    _hasOlderHistory = true;
    anchoredHistory = true;
    _historyAnchorMessageId = messageId;
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
      final response = await _queryHistory({
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

  Future<int?> openNextUnreadReaction() async {
    try {
      final response = await _queryHistory({
        '@type': 'searchChatMessages',
        'chat_id': chatId,
        'query': '',
        'sender_id': null,
        'from_message_id': 0,
        'offset': 0,
        'limit': math.min(
          100,
          math.max(10, unreadReactionCount + _locallyViewedReactionIds.length),
        ),
        'filter': {'@type': 'searchMessagesFilterUnreadReaction'},
      });
      final rawMessages =
          response.objects('messages') ?? const <Map<String, dynamic>>[];
      if (rawMessages.isEmpty) {
        _setUnreadReactionCount(0, emitLocalUpdate: true);
        return null;
      }
      final reactions = rawMessages
          .map(TDParse.message)
          .whereType<ChatMessage>()
          .where((message) => !_locallyViewedReactionIds.contains(message.id))
          .toList();
      final reaction = reactions.isEmpty ? null : reactions.first;
      return reaction?.id;
    } catch (_) {
      return null;
    }
  }

  /// Reports the exact messages that entered the viewport. TDLib tracks
  /// unread mentions and reactions independently from the ordinary inbox
  /// boundary. Sending the concrete IDs clears all three states correctly.
  void markVisibleMessagesViewed(Iterable<ChatMessage> visibleMessages) {
    final viewed = visibleMessages
        .where(
          (message) =>
              (!message.isOutgoing && !message.isService) ||
              message.hasUnreadReactions,
        )
        .toList(growable: false);
    if (viewed.isEmpty) return;
    // Ghost mode skips only the server report; the local mention/reaction
    // counters below still clear so the UI reads the chat as read.
    if (!(allowTelegramTosViolations &&
        GhostModeController.shared.shouldBlockRead(chatId).isBlock)) {
      _client.send({
        '@type': 'viewMessages',
        'chat_id': chatId,
        'message_ids': viewed.map((message) => message.id).toSet().toList(),
        'force_read': true,
      });
    }
    _consumeViewedMentions(
      viewed
          .where((message) => message.containsUnreadMention)
          .map((message) => message.id),
    );
    _consumeViewedReactions(
      viewed
          .where((message) => message.hasUnreadReactions)
          .map((message) => message.id),
    );
  }

  /// Marks the mention selected by the blue @ control after the view has
  /// scrolled it into place. Awaiting TDLib prevents a quick second tap from
  /// resolving the same mention again.
  Future<void> markUnreadMentionRead(int messageId) async {
    // Ghost mode skips only the server report; the blue-@ badge below still
    // clears so the UI reads the mention as read.
    if (!(allowTelegramTosViolations &&
        GhostModeController.shared.shouldBlockRead(chatId).isBlock)) {
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
    }
    _consumeViewedMentions([messageId], force: true);
  }

  Future<void> markUnreadReactionRead(int messageId) async {
    // Ghost mode skips only the server report; the local reaction counter
    // below still clears so the UI reads the reaction as seen.
    if (!(allowTelegramTosViolations &&
        GhostModeController.shared.shouldBlockRead(chatId).isBlock)) {
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
    }
    _consumeViewedReactions([messageId], force: true);
  }

  void _consumeViewedMentions(Iterable<int> messageIds, {bool force = false}) {
    final consumed = _consumeViewedFlags(
      messageIds,
      viewedIds: _locallyViewedMentionIds,
      isUnread: (message) => message.containsUnreadMention,
      markRead: (message) => message.containsUnreadMention = false,
      force: force,
    );
    if (consumed == 0) return;
    _setUnreadMentionCount(
      unreadMentionCountAfterReading(unreadMentionCount, consumed),
      emitLocalUpdate: true,
    );
  }

  void _consumeViewedReactions(Iterable<int> messageIds, {bool force = false}) {
    final consumed = _consumeViewedFlags(
      messageIds,
      viewedIds: _locallyViewedReactionIds,
      isUnread: (message) => message.hasUnreadReactions,
      markRead: (message) => message.hasUnreadReactions = false,
      force: force,
    );
    if (consumed == 0) return;
    _setUnreadReactionCount(
      unreadReactionCountAfterReading(unreadReactionCount, consumed),
      emitLocalUpdate: true,
    );
  }

  /// Remembers the [messageIds] still flagged by [isUnread] (all of them when
  /// [force]d) in [viewedIds], clears their flag, and returns how many were
  /// consumed.
  int _consumeViewedFlags(
    Iterable<int> messageIds, {
    required Set<int> viewedIds,
    required bool Function(ChatMessage message) isUnread,
    required void Function(ChatMessage message) markRead,
    required bool force,
  }) {
    final candidates = messageIds
        .where((id) => id > 0 && !viewedIds.contains(id))
        .toSet();
    if (candidates.isEmpty) return 0;
    final unreadIds = force
        ? candidates
        : _allMessages
              .where(
                (message) =>
                    candidates.contains(message.id) && isUnread(message),
              )
              .map((message) => message.id)
              .toSet();
    if (unreadIds.isEmpty) return 0;

    viewedIds.addAll(unreadIds);
    while (viewedIds.length > 512) {
      viewedIds.remove(viewedIds.first);
    }
    for (final message in _allMessages) {
      if (unreadIds.contains(message.id)) markRead(message);
    }
    return unreadIds.length;
  }

  bool _setUnreadMentionCount(int count, {bool emitLocalUpdate = false}) {
    final next = math.max(0, count);
    final changed = unreadMentionCount != next;
    unreadMentionCount = next;
    if (changed) notifyListeners();
    if (emitLocalUpdate && !isForumTopicTranscript) {
      _client.emitLocalUpdate({
        '@type': 'updateChatUnreadMentionCount',
        'chat_id': chatId,
        'unread_mention_count': next,
      });
    }
    return changed;
  }

  bool _setUnreadReactionCount(int count, {bool emitLocalUpdate = false}) {
    final next = math.max(0, count);
    final changed = unreadReactionCount != next;
    unreadReactionCount = next;
    if (changed) notifyListeners();
    if (emitLocalUpdate && !isForumTopicTranscript) {
      _client.emitLocalUpdate({
        '@type': 'updateChatUnreadReactionCount',
        'chat_id': chatId,
        'unread_reaction_count': next,
      });
    }
    return changed;
  }

  Future<bool> _fetchHistory(
    int fromMessageId,
    int offset,
    int limit, {
    bool isOlder = false,
    bool onlyLocal = false,
  }) async {
    if (_chatOpenWorkIsStale) return false;
    final requestGeneration = _historyWindowGeneration;
    Map<String, dynamic> response;
    try {
      response = await _queryHistory({
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
    if (_chatOpenWorkIsStale || requestGeneration != _historyWindowGeneration) {
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
      // An empty remote latest page for an empty window means the chat has
      // no history yet (an unstarted bot, a new DM, empty Saved Messages).
      // No gap is possible, so live messages must join the transcript —
      // mirroring loadLatestHistory's empty result.
      if (confirmsEmptyChatReachesLatest(
        onlyLocal: onlyLocal,
        fromMessageId: fromMessageId,
        offset: offset,
        anchoredHistory: anchoredHistory,
        restoredFromSession: _restoredFromSession,
        windowLatestServerMessageId: latestServerMessageId(_allMessages),
      )) {
        _historyReachesLatest = true;
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

  /// Confirms a session-reopen override from concrete messages rather than an
  /// unread-count delta. The latter can shrink after another-device reads,
  /// deletions, or the exit-time read that follows snapshot capture.
  Future<int?> confirmedNewIncomingUnreadSinceSession({
    required int savedKnownLatestMessageId,
    required int expectedReadStateRevision,
  }) async {
    if (!_chatReadStateLoaded ||
        expectedReadStateRevision != _chatReadStateRevision) {
      return null;
    }

    bool qualifies(ChatMessage message, int readBoundary) =>
        !isPendingChatMessage(message) &&
        isNewIncomingUnreadSinceChatSession(
          messageId: message.id,
          isOutgoing: message.isOutgoing,
          isService: message.isService,
          savedKnownLatestMessageId: savedKnownLatestMessageId,
          currentLastReadInboxId: readBoundary,
        );

    final readBoundary = lastReadInboxId;
    int? earliestConfirmedMessageId;
    for (final message in _allMessages) {
      if (qualifies(message, readBoundary)) {
        earliestConfirmedMessageId = earliestConfirmedMessageId == null
            ? message.id
            : math.min(earliestConfirmedMessageId, message.id);
      }
    }

    // A loaded concrete message is sufficient even if its paired unread-count
    // update has not arrived yet. The count only controls whether a read-only
    // history probe is warranted to find an earlier unread target.
    if (!shouldProbeChatSessionUnreadHistory(
      savedKnownLatestMessageId: savedKnownLatestMessageId,
      currentKnownLatestMessageId: _knownLatestMessageId,
      currentUnreadCount: unreadCount,
    )) {
      return earliestConfirmedMessageId;
    }

    final stopAtMessageId = math.max(savedKnownLatestMessageId, readBoundary);
    var fromMessageId = 0;
    var previousOldestMessageId = 0;
    var pagesScanned = 0;
    while (!_chatOpenWorkIsStale &&
        expectedReadStateRevision == _chatReadStateRevision &&
        shouldContinueChatSessionUnreadHistoryProbe(
          pagesScanned: pagesScanned,
        )) {
      Map<String, dynamic> response;
      try {
        response = await _queryHistory({
          '@type': 'getChatHistory',
          'chat_id': chatId,
          'from_message_id': fromMessageId,
          'offset': 0,
          'limit': 100,
          'only_local': false,
        });
      } catch (_) {
        return earliestConfirmedMessageId;
      }
      if (_chatOpenWorkIsStale ||
          expectedReadStateRevision != _chatReadStateRevision) {
        return null;
      }
      pagesScanned++;
      final page =
          (response.objects('messages') ?? const <Map<String, dynamic>>[])
              .map(TDParse.message)
              .whereType<ChatMessage>()
              .where(
                (message) => !isPendingChatMessage(message) && message.id > 0,
              )
              .toList(growable: false);
      for (final message in page) {
        if (qualifies(message, readBoundary)) {
          earliestConfirmedMessageId = earliestConfirmedMessageId == null
              ? message.id
              : math.min(earliestConfirmedMessageId, message.id);
        }
      }
      if (page.isEmpty) return earliestConfirmedMessageId;

      final oldestMessageId = page
          .map((message) => message.id)
          .reduce(math.min);
      if (oldestMessageId <= stopAtMessageId ||
          oldestMessageId == previousOldestMessageId) {
        return earliestConfirmedMessageId;
      }
      previousOldestMessageId = oldestMessageId;
      fromMessageId = oldestMessageId;
    }
    return earliestConfirmedMessageId;
  }

  Future<void> markLoadedMessagesRead() async {
    if (!_chatReadStateLoaded || !_historyReachesLatest) return;
    if (_markReadInFlight) return;
    _markReadInFlight = true;
    try {
      final latestLoadedId = latestServerMessageId(_allMessages);
      var messageId = latestLoadedId;
      final previousUnreadCount = unreadCount;
      final previousMarkedUnread = isMarkedUnread;
      if (previousUnreadCount > 0 || previousMarkedUnread || messageId <= 0) {
        try {
          final raw = isForumTopicTranscript
              ? await _client.query({
                  '@type': 'getForumTopic',
                  'chat_id': chatId,
                  'forum_topic_id': forumTopicId,
                })
              : await _client.query({'@type': 'getChat', 'chat_id': chatId});
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
      ++_chatReadInboxRevision;
      ++_chatReadStateRevision;
      notifyListeners();

      final ghostRead =
          allowTelegramTosViolations &&
          GhostModeController.shared.shouldBlockRead(chatId).isBlock;
      if (shouldClearMarker) {
        // Ghost mode keeps the local unread bookkeeping (emitLocalUpdate)
        // and only skips the server report.
        if (!ghostRead) {
          _client.send({
            '@type': 'toggleChatIsMarkedAsUnread',
            'chat_id': chatId,
            'is_marked_as_unread': false,
          });
        }
        _client.emitLocalUpdate({
          '@type': 'updateChatIsMarkedAsUnread',
          'chat_id': chatId,
          'is_marked_as_unread': false,
        });
      }
      if (shouldForceRead) {
        _lastForcedReadMessageId = messageId;
        if (!ghostRead) {
          _client.send({
            '@type': 'viewMessages',
            'chat_id': chatId,
            'message_ids': [messageId],
            'source': isForumTopicTranscript
                ? {'@type': 'messageSourceForumTopicHistory'}
                : null,
            'force_read': true,
          });
        }
        // A topic's read position is not the chat's; TDLib reports the
        // resulting chat-wide counts through its own updates.
        if (!isForumTopicTranscript) {
          _client.emitLocalUpdate({
            '@type': 'updateChatReadInbox',
            'chat_id': chatId,
            'last_read_inbox_message_id': messageId,
            'unread_count': 0,
          });
        }
      }
      if (isForumTopicTranscript) return;
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
}
