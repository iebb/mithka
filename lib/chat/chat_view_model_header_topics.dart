part of 'chat_view_model.dart';

extension ChatViewModelHeaderTopics on ChatViewModel {
  // MARK: - Header

  Future<void> _loadChatHeader() async {
    final readStateRevisionAtRequestStart = _chatReadStateRevision;
    final readInboxRevisionAtRequestStart = _chatReadInboxRevision;
    Map<String, dynamic> chat;
    try {
      chat = await _client.query({'@type': 'getChat', 'chat_id': chatId});
    } catch (error) {
      if (_markPeerRestricted(error)) {
        notifyListeners();
      }
      return;
    }
    if (_chatOpenWorkIsStale) return;
    if (isForumTopicTranscript) {
      final topic = await _loadForumTopic();
      if (_chatOpenWorkIsStale) return;
      chat = forumTopicChatSnapshot(chat, topic);
    }
    peerTitle = chat.str('title') ?? peerTitle;
    _messageSenderFromChat = chat.obj('message_sender_id');
    peerPhoto = TDParse.smallPhoto(chat.obj('photo'));
    firstContactInfo = ChatFirstContactInfo.fromActionBar(
      chat.obj('action_bar'),
    );
    _applyBusinessBotManageBar(chat.obj('business_bot_manage_bar'));
    lastReadOutboxId = chat.int64('last_read_outbox_message_id') ?? 0;
    if (shouldApplyInitialChatReadState(
      readInboxRevisionAtRequestStart: readInboxRevisionAtRequestStart,
      currentReadInboxRevision: _chatReadInboxRevision,
    )) {
      lastReadInboxId = chat.int64('last_read_inbox_message_id') ?? 0;
      unreadCount = chat.integer('unread_count') ?? 0;
    }
    unreadMentionCount = chat.integer('unread_mention_count') ?? 0;
    unreadReactionCount = chat.integer('unread_reaction_count') ?? 0;
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
    chatKind = kind;
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
    _primeLastMessage(
      chat,
      preserveNewer: _chatReadStateRevision != readStateRevisionAtRequestStart,
    );
    _chatReadStateLoaded = true;
    ++_chatReadStateRevision;
    // Reopen positioning and safe read marking need only the coherent getChat
    // read/latest snapshot. Publish it before optional peer metadata awaits.
    notifyListeners();
    // Chat-wide default send permission + permissive membership defaults
    // (refined per type below).
    _chatCanSend =
        chat.obj('permissions')?.boolean('can_send_basic_messages') ?? true;
    _chatCanCreateTopics =
        chat.obj('permissions')?.boolean('can_create_topics') ?? false;
    canSendMessages = _chatCanSend;
    canSendVoiceNotes =
        chat.obj('permissions')?.boolean('can_send_voice_notes') ?? true;
    isMember = true;
    canJoin = false;
    joinByRequest = false;
    isChannel = false;
    isMessageBubbleRepository = false;
    hasLinkedDiscussion = false;
    isDirectMessagesGroup = false;
    isAdministeredDirectMessagesGroup = false;
    canDeleteMessagesBySender = false;
    canManageTopics = false;
    canDeleteForumTopics = false;
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
      if (_chatOpenWorkIsStale) return;
    } else {
      _secretChatId = null;
    }
    switch (type?.type) {
      case 'chatTypePrivate':
      case 'chatTypeSecret':
        peerBasicGroupId = null;
        peerSupergroupId = null;
        peerUserId = type?.int64('user_id');
        final uid = peerUserId;
        if (uid != null) {
          try {
            final user = await _client.query({
              '@type': 'getUser',
              'user_id': uid,
            });
            if (_chatOpenWorkIsStale) return;
            final restrictionReason = TDParse.restrictionReasonFor(user);
            if (restrictionReason != null &&
                TDParse.isBlockingRestriction(user)) {
              _setPeerRestricted(
                restrictionReason,
                isPornographic: TDParse.isPornographicRestriction(user),
              );
            }
            _applyPeerBotCapabilities(user, notify: false);
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
            if (peerIsBot) {
              await _loadBotInfo(uid);
              if (_chatOpenWorkIsStale) return;
            }
          }
        }
      case 'chatTypeBasicGroup':
        final gid = type?.int64('basic_group_id');
        peerUserId = null;
        peerBasicGroupId = gid;
        peerSupergroupId = null;
        if (gid != null) {
          try {
            final bg = await _client.query({
              '@type': 'getBasicGroup',
              'basic_group_id': gid,
            });
            if (_chatOpenWorkIsStale) return;
            memberCount = bg.integer('member_count') ?? 0;
            _applyGroupStatus(bg.obj('status'));
          } catch (_) {}
          unawaited(_loadBasicGroupFullInfo(gid));
        }
      case 'chatTypeSupergroup':
        final sgid = type?.int64('supergroup_id');
        peerUserId = null;
        peerBasicGroupId = null;
        peerSupergroupId = sgid;
        if (sgid != null) {
          try {
            final sg = await _client.query({
              '@type': 'getSupergroup',
              'supergroup_id': sgid,
            });
            if (_chatOpenWorkIsStale) return;
            final restrictionReason = TDParse.restrictionReasonFor(sg);
            if (restrictionReason != null &&
                TDParse.isBlockingRestriction(sg)) {
              _setPeerRestricted(
                restrictionReason,
                isPornographic: TDParse.isPornographicRestriction(sg),
              );
            }
            isChannel = sg.boolean('is_channel') ?? false;
            final usernames = sg.obj('usernames');
            final activeUsernames = usernames?['active_usernames'];
            final repositoryNames = <String>{
              if (activeUsernames is List)
                for (final value in activeUsernames.whereType<String>())
                  value.toLowerCase(),
              if ((usernames?.str('editable_username') ?? '').isNotEmpty)
                usernames!.str('editable_username')!.toLowerCase(),
            };
            isMessageBubbleRepository =
                isChannel && repositoryNames.contains('msgbubble');
            isDirectMessagesGroup =
                sg.boolean('is_direct_messages_group') ?? false;
            isAdministeredDirectMessagesGroup =
                sg.boolean('is_administered_direct_messages_group') ?? false;
            isForum = isForum || (sg.boolean('is_forum') ?? false);
            hasForumTabs = sg.boolean('has_forum_tabs') ?? false;
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
    if (supportsTopics) {
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
      final snapshot = await ChatViewModel._sponsoredMessagesCache.retrieve(
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

  void _primeLastMessage(
    Map<String, dynamic> chat, {
    bool preserveNewer = false,
  }) {
    final lastRaw = chat.obj('last_message');
    final lastMessage = lastRaw == null ? null : TDParse.message(lastRaw);
    if (lastMessage == null) return;
    final lastMessageId = isPendingChatMessage(lastMessage)
        ? 0
        : lastMessage.id;
    _knownLatestMessageId = preserveNewer
        ? math.max(_knownLatestMessageId, lastMessageId)
        : lastMessageId;
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
      if (_isDisposed || peerSupergroupId != supergroupId) return;
      memberCount = full.integer('member_count') ?? memberCount;
      hasLinkedDiscussion =
          isChannel && (full.int64('linked_chat_id') ?? 0) != 0;
      _setPaidMessageStarCount(_paidMessageStars(full), notify: false);
      notifyListeners();
      if (isChannel) {
        _clearGroupBotCommands();
      } else {
        unawaited(_applyGroupBotCommands(full));
      }
    } catch (_) {}
  }

  Future<void> _loadBasicGroupFullInfo(int basicGroupId) async {
    try {
      final full = await _client.query({
        '@type': 'getBasicGroupFullInfo',
        'basic_group_id': basicGroupId,
      });
      if (_isDisposed || peerBasicGroupId != basicGroupId) return;
      final members = full.objects('members');
      if (members != null) memberCount = members.length;
      notifyListeners();
      unawaited(_applyGroupBotCommands(full));
    } catch (_) {}
  }

  Future<void> _applyGroupBotCommands(Map<String, dynamic> fullInfo) async {
    final generation = ++_groupBotCommandsGeneration;
    final commands = await resolveGroupBotCommandOptions(fullInfo, (
      userId,
    ) async {
      try {
        return await _client.query({'@type': 'getUser', 'user_id': userId});
      } catch (_) {
        return null;
      }
    });
    if (_isDisposed ||
        generation != _groupBotCommandsGeneration ||
        !isGroup ||
        isChannel) {
      return;
    }
    botCommands = commands;
    notifyListeners();
  }

  void _clearGroupBotCommands() {
    _groupBotCommandsGeneration++;
    if (botCommands.isEmpty) return;
    botCommands = const [];
    notifyListeners();
  }

  Future<void> _loadPrivatePaidMessageInfo(int userId, {bool force = false}) {
    if (!force &&
        _privateMessageInfoLoaded &&
        _privateMessageInfoUserId == userId) {
      return Future.value();
    }
    final current = _privateMessageInfoLoad;
    if (current != null && _privateMessageInfoUserId == userId) return current;
    _privateMessageInfoUserId = userId;
    final future = _fetchPrivateMessageInfo(userId);
    _privateMessageInfoLoad = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_privateMessageInfoLoad, future)) {
          _privateMessageInfoLoad = null;
        }
      }),
    );
    return future;
  }

  Future<void> _fetchPrivateMessageInfo(int userId) async {
    var next = 0;
    var restrictsNewChats = false;
    var isUnavailable = false;
    var voiceMessagesForbidden = false;
    try {
      final full = await _client.query({
        '@type': 'getUserFullInfo',
        'user_id': userId,
      });
      next = _paidMessageStars(full);
      voiceMessagesForbidden =
          full.boolean('has_restricted_voice_and_video_note_messages') ?? false;
    } catch (_) {}
    try {
      final result = await _client.query({
        '@type': 'canSendMessageToUser',
        'user_id': userId,
        'only_local': false,
      });
      switch (result.type) {
        case 'canSendMessageToUserResultUserHasPaidMessages':
          next = _paidMessageStars(result);
        case 'canSendMessageToUserResultUserRestrictsNewChats':
          next = 0;
          restrictsNewChats = true;
        case 'canSendMessageToUserResultUserIsDeleted':
          next = 0;
          isUnavailable = true;
        case 'canSendMessageToUserResultOk':
          next = 0;
      }
    } catch (_) {}
    if (_isDisposed || peerUserId != userId) return;
    _privateMessageInfoLoaded = true;
    final paidCountChanged = paidMessageStarCount != next;
    final requirementChanged =
        peerRequiresPremiumOrContact != restrictsNewChats ||
        peerIsUnavailable != isUnavailable;
    final voiceRestrictionChanged =
        canSendVoiceNotes != !voiceMessagesForbidden;
    peerRequiresPremiumOrContact = restrictsNewChats;
    peerIsUnavailable = isUnavailable;
    canSendVoiceNotes = !voiceMessagesForbidden;
    _setPaidMessageStarCount(next, notify: false);
    if (paidCountChanged || requirementChanged || voiceRestrictionChanged) {
      notifyListeners();
    }
  }

  Future<void> loadForumTopics() async {
    if (!supportsTopics || forumTopicsLoading) return;
    forumTopicsLoading = true;
    notifyListeners();
    // One listener per view model, not per refresh: dispose removes only
    // one copy, so a refresh-added duplicate would survive disposal and
    // keep mutating this model's topics.
    if (!_forumTopicIndexListening) {
      ForumTopicIndex.shared.addListener(_onForumTopicIndexChanged);
      _forumTopicIndexListening = true;
    }
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
      if (_isDisposed) return;
      final raw = response.objects('topics') ?? const <Map<String, dynamic>>[];
      final topics = <ForumTopicOption>[];
      final previewMessages = <ChatMessage>[];
      for (final topic in raw) {
        final info = topic.obj('info') ?? topic;
        final id = _forumTopicId(topic, info);
        if (id == null || id == 0) continue;
        final name =
            info.str('name') ??
            topic.str('name') ??
            AppStrings.t(AppStringKeys.topicChatTopicTitle);
        final icon = info.obj('icon') ?? topic.obj('icon');
        final pageUnread =
            topic.integer('unread_count') ?? info.integer('unread_count') ?? 0;
        final live = ForumTopicIndex.shared.entryFor(_accountSlot, chatId, id);
        final pageRead =
            info.integer('last_read_inbox_message_id') ??
            topic.integer('last_read_inbox_message_id') ??
            0;
        final pageLast = topic.obj('last_message')?.int64('id') ?? 0;
        // A live counter that already saw newer traffic wins over the page's
        // snapshot; otherwise the page is authoritative.
        final unread = live != null && live.readsAheadOfPage(pageRead, pageLast)
            ? live.unreadCount
            : (pageUnread < 0 ? 0 : pageUnread);
        // A real last message (a service one included) drives the row preview;
        // a synthetic fallback's text is the topic's own name, so the preview
        // stays hidden exactly the way the chat list hides empty ones.
        final rawLast = topic.obj('last_message');
        final parsed = rawLast == null ? null : TDParse.message(rawLast);
        if (parsed != null) previewMessages.add(parsed);
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
            unreadCount: unread,
            isMuted:
                (topic.obj('notification_settings')?.integer('mute_for') ?? 0) >
                0,
            isPinned: topic.boolean('is_pinned') ?? false,
            isGeneral:
                info.boolean('is_general') == true ||
                topic.boolean('is_general') == true,
            isClosed:
                info.boolean('is_closed') == true ||
                topic.boolean('is_closed') == true,
            creatorId: _forumTopicCreatorId(info),
            lastPreview: parsed != null ? parsed.text.trim() : '',
            lastSender: parsed != null ? _topicPreviewSender(id, parsed) : null,
            lastMessageDate: parsed?.date ?? 0,
            lastMessageId: parsed?.id ?? 0,
          ),
        );
      }
      final previous = forumTopics;
      forumTopics = topics;
      ForumTopicIndex.shared.storeAll(_accountSlot, chatId, [
        for (final topic in raw) ?ForumTopicIndexEntry.fromTopic(topic),
      ]);
      // storeAll merged the live counters; show exactly what it kept, without
      // discarding the page's row fields (preview, pin, closed, creator).
      final stored = ForumTopicIndex.shared.topicsFor(_accountSlot, chatId);
      if (stored.isNotEmpty) {
        final byId = {for (final option in topics) option.id: option};
        final oldById = {for (final option in previous) option.id: option};
        forumTopics = [
          for (final entry in stored)
            byId[entry.id]?._withIndex(entry) ??
                oldById[entry.id]?._withIndex(entry) ??
                _optionFromIndex(entry),
        ];
      }
      unawaited(_resolveTopicPreviewSenders(previewMessages));
    } catch (_) {
      forumTopics = const [];
    } finally {
      forumTopicsLoading = false;
      notifyListeners();
    }
  }

  ForumTopicOption _optionFromIndex(ForumTopicIndexEntry entry) =>
      ForumTopicOption(
        id: entry.id,
        name: entry.name,
        iconCustomEmojiId: entry.iconCustomEmojiId,
        iconColor: entry.iconColor,
        unreadCount: entry.unreadCount,
        isMuted: entry.isMuted,
        lastMessageId: entry.lastMessageId,
      );

  int? _forumTopicId(Map<String, dynamic> topic, Map<String, dynamic> info) {
    return info.integer('forum_topic_id') ??
        topic.integer('forum_topic_id') ??
        info.int64('message_thread_id') ??
        topic.int64('message_thread_id');
  }

  int _forumTopicCreatorId(Map<String, dynamic> info) {
    final creator = info.obj('creator_id');
    if (creator?.type == 'messageSenderUser') {
      return creator?.int64('user_id') ?? 0;
    }
    return 0;
  }

  /// Resolves preview sender names so the topic rows can draw the
  /// "Alice: …" prefix; unresolved senders simply keep the name TDLib
  /// carried, or omit the prefix entirely.
  Future<void> _resolveTopicPreviewSenders(List<ChatMessage> messages) async {
    final missing = messages
        .where((message) => !message.isOutgoing)
        .map((message) => message.senderId)
        .whereType<int>()
        .where((id) => id != 0 && !_topicSenderNames.containsKey(id))
        .toSet();
    if (missing.isEmpty) return;
    for (final id in missing) {
      try {
        if (id > 0) {
          final user = await _client.query({'@type': 'getUser', 'user_id': id});
          _topicSenderNames[id] = TDParse.userName(user);
        } else {
          final chat = await _client.query({'@type': 'getChat', 'chat_id': id});
          _topicSenderNames[id] =
              chat.str('title') ?? AppStrings.t(AppStringKeys.topicChatUsers);
        }
      } catch (_) {
        // An unresolved sender simply omits the preview prefix.
      }
    }
    if (_isDisposed) return;
    _refreshTopicRowSenders();
  }

  /// Re-derives resolved sender names onto the topic rows.
  void _refreshTopicRowSenders() {
    var changed = false;
    final next = <ForumTopicOption>[];
    for (final option in forumTopics) {
      final senderId = _topicRowSenderIds[option.id];
      String? sender = option.lastSender;
      if (option.lastPreview.isNotEmpty &&
          senderId != null &&
          _topicSenderNames.containsKey(senderId)) {
        final resolved = _topicSenderNames[senderId]?.trim();
        if (resolved != null && resolved.isNotEmpty) sender = resolved;
      }
      final withSender = _topicOptionWithSender(option, sender);
      if (!withSender.sameDisplay(option)) changed = true;
      next.add(withSender);
    }
    if (!changed) return;
    forumTopics = next;
    notifyListeners();
  }

  ForumTopicOption _topicOptionWithSender(
    ForumTopicOption option,
    String? sender,
  ) => ForumTopicOption(
    id: option.id,
    name: option.name,
    iconCustomEmojiId: option.iconCustomEmojiId,
    iconColor: option.iconColor,
    unreadCount: option.unreadCount,
    isMuted: option.isMuted,
    isPinned: option.isPinned,
    isGeneral: option.isGeneral,
    isClosed: option.isClosed,
    creatorId: option.creatorId,
    lastPreview: option.lastPreview,
    lastSender: sender,
    lastMessageDate: option.lastMessageDate,
    lastMessageId: option.lastMessageId,
  );

  /// The preview sender for a topic's last message: "You" for outgoing, the
  /// resolved sender name, or the name TDLib carried with the message.
  String? _topicPreviewSender(int topicId, ChatMessage message) {
    if (message.isOutgoing) {
      return AppStrings.t(AppStringKeys.chatMeLabel);
    }
    final senderId = message.senderId;
    if (senderId != null && senderId != 0) {
      _topicRowSenderIds[topicId] = senderId;
      final cached = _topicSenderNames[senderId]?.trim();
      if (cached != null && cached.isNotEmpty) return cached;
    }
    final name = message.senderName?.trim();
    return name != null && name.isNotEmpty ? name : null;
  }

  // MARK: - Topic moderation (Telegram iOS parity)

  /// Sends a topic request to the client that owns this pane's account.
  ///
  /// Chat and topic ids are account-scoped. A moderation request awaiting a
  /// dialog confirmation must not follow a later account switch onto another
  /// account's client, so every destructive topic call routes through the
  /// client id captured when this view model was created.
  Future<Map<String, dynamic>> _topicAccountQuery(
    Map<String, dynamic> request,
  ) => _client.queryTo(request, _accountClientId);

  /// Creates a topic; returns its id, or throws the request error.
  Future<int?> createForumTopic({
    required String name,
    required int iconColor,
    required int iconCustomEmojiId,
  }) async {
    final created = await _topicAccountQuery(
      createForumTopicRequest(
        chatId: chatId,
        name: name,
        color: iconColor,
        customEmojiId: iconCustomEmojiId,
      ),
    );
    await loadForumTopics();
    return created.integer('forum_topic_id');
  }

  Future<void> editForumTopic({
    required int forumTopicId,
    required String name,
    required int iconCustomEmojiId,
  }) async {
    await _topicAccountQuery(
      editForumTopicRequest(
        chatId: chatId,
        forumTopicId: forumTopicId,
        name: name,
        customEmojiId: iconCustomEmojiId,
      ),
    );
    await loadForumTopics();
  }

  Future<void> deleteForumTopic(int forumTopicId) async {
    await _topicAccountQuery(
      deleteForumTopicRequest(chatId: chatId, forumTopicId: forumTopicId),
    );
    await loadForumTopics();
  }

  Future<void> setForumTopicPinned(
    int forumTopicId, {
    required bool pinned,
  }) async {
    await _topicAccountQuery(
      toggleForumTopicPinnedRequest(
        chatId: chatId,
        forumTopicId: forumTopicId,
        isPinned: pinned,
      ),
    );
    await loadForumTopics();
  }

  Future<void> setForumTopicMuted(
    int forumTopicId, {
    required bool muted,
  }) async {
    await _topicAccountQuery(
      setForumTopicMutedRequest(
        chatId: chatId,
        forumTopicId: forumTopicId,
        muted: muted,
      ),
    );
    await loadForumTopics();
  }

  Future<void> setForumTopicClosed(
    int forumTopicId, {
    required bool closed,
  }) async {
    await _topicAccountQuery(
      toggleForumTopicClosedRequest(
        chatId: chatId,
        forumTopicId: forumTopicId,
        isClosed: closed,
      ),
    );
    await loadForumTopics();
  }

  /// Marks the topic read the way viewing its newest message does: TDLib
  /// advances the topic's inbox watermark to the highest viewed message id.
  Future<void> markForumTopicRead(ForumTopicOption topic) async {
    if (topic.lastMessageId == 0 || topic.unreadCount == 0) return;
    try {
      await _topicAccountQuery(
        forumTopicViewMessagesRequest(
          chatId: chatId,
          messageIds: [topic.lastMessageId],
        ),
      );
      await loadForumTopics();
    } catch (_) {
      // A failed mark-read is silent: nothing destructive happened.
    }
  }

  /// Clears every one of [topicIds] at once: the rows drop their unread
  /// counters before the first request leaves, each topic's read is sent
  /// scoped to its own newest message, and a failed topic gets its own counter
  /// back. Reads run even for topics that already report zero locally, so a
  /// stale counter cannot survive on the server.
  ///
  /// Rollback is deliberately per topic and state-guarded: a topic whose
  /// request failed regains its counter only while the index still holds the
  /// exact read state captured before the optimistic clear. An authoritative
  /// updateForumTopic (or new traffic) that moved the watermark while the
  /// batch was in flight wins, so a successful read's zero is never
  /// overwritten by an older counter.
  ///
  /// Throws only when no topic could be read at all. With [failureFeedback]
  /// false a partial failure is silent (the counters still roll back); the
  /// caller decides what to say.
  Future<void> markForumTopicsRead(
    Iterable<int> topicIds, {
    bool failureFeedback = true,
  }) async {
    if (_isDisposed) return;
    final wanted = topicIds.toSet();
    final targets = [
      for (final topic in forumTopics)
        if (wanted.contains(topic.id) && topic.lastMessageId > 0) topic,
    ];
    if (targets.isEmpty) return;
    // Snapshot the index state behind each counter, not just the number: the
    // rollback guard needs to know whether the read position moved since.
    final previous =
        <
          int,
          ({int unreadCount, int? lastReadInboxMessageId, int? lastMessageId})
        >{};
    for (final topic in targets) {
      if (topic.unreadCount <= 0) continue;
      final entry = ForumTopicIndex.shared.entryFor(
        _accountSlot,
        chatId,
        topic.id,
      );
      previous[topic.id] = (
        unreadCount: topic.unreadCount,
        lastReadInboxMessageId: entry?.lastReadInboxMessageId,
        lastMessageId: entry?.lastMessageId,
      );
    }
    if (previous.isNotEmpty) {
      _applyTopicUnreadCounts({
        for (final topicId in previous.keys) topicId: 0,
      });
    }
    var failures = 0;
    Object? firstError;
    for (final topic in targets) {
      try {
        await _topicAccountQuery(
          forumTopicViewMessagesRequest(
            chatId: chatId,
            messageIds: [topic.lastMessageId],
          ),
        );
        if (_isDisposed) return;
        // TDLib advanced this topic's inbox watermark; remember it so a stale
        // getForumTopics page cannot regress the successful read.
        ForumTopicIndex.shared.recordRead(
          _accountSlot,
          chatId,
          topic.id,
          readMessageId: topic.lastMessageId,
          lastMessageId: topic.lastMessageId,
        );
      } catch (error) {
        if (_isDisposed) return;
        failures++;
        firstError ??= error;
        final snapshot = previous[topic.id];
        if (snapshot == null) continue;
        // Restore only this topic, and only while nothing authoritative moved
        // its read position or newest message during the batch.
        final restored = ForumTopicIndex.shared.restoreUnreadCountIfUnmoved(
          _accountSlot,
          chatId,
          topic.id,
          restoreCount: snapshot.unreadCount,
          expectedUnreadCount: 0,
          expectedLastReadInboxMessageId: snapshot.lastReadInboxMessageId,
          expectedLastMessageId: snapshot.lastMessageId,
        );
        if (restored) {
          _applyTopicUnreadCounts({topic.id: snapshot.unreadCount});
        }
      }
    }
    if (failures > 0) {
      if (failures == targets.length) throw firstError!;
      if (failureFeedback) {
        // Some topics could not be read: say so once, after the rollback.
        _bulkReadFailed = true;
        notifyListeners();
      }
    }
    await loadForumTopics();
  }

  bool takeBulkReadFailure() {
    final failed = _bulkReadFailed;
    _bulkReadFailed = false;
    return failed;
  }

  /// Rewrites the unread counter of the named rows in place (the index owns
  /// every other displayed field), notifying only on a real change.
  void _applyTopicUnreadCounts(Map<int, int> counts) {
    if (counts.isEmpty) return;
    var changed = false;
    final next = <ForumTopicOption>[];
    for (final topic in forumTopics) {
      final count = counts[topic.id];
      if (count == null || count == topic.unreadCount) {
        next.add(topic);
        continue;
      }
      changed = true;
      next.add(topic._withUnreadCount(count));
    }
    ForumTopicIndex.shared.setUnreadCounts(_accountSlot, chatId, counts);
    if (!changed) return;
    forumTopics = next;
    notifyListeners();
  }

  /// Folds live updates into the topic rows so previews, pins, closes and
  /// renames move without a full getForumTopics round-trip. Runs for every
  /// update of this chat — including topics other than the open transcript.
  void _foldForumTopicRowUpdate(Map<String, dynamic> update) {
    if (!supportsTopics || forumTopics.isEmpty) return;
    switch (update.type) {
      case 'updateNewMessage':
        final raw = update.obj('message');
        if (raw?.int64('chat_id') != chatId) return;
        final message = TDParse.message(raw!);
        if (message == null) return;
        final topicRef = raw.obj('topic_id');
        // A message outside any topic belongs to General (id 1) — but only
        // in a real forum. A bot topic chat has no General topic and every
        // one of its messages carries an explicit topic reference, so a
        // missing one is unattributable traffic, not General.
        final topicId = topicRef?.type == 'messageTopicForum'
            ? topicRef?.integer('forum_topic_id')
            : isForum
            ? 1
            : null;
        if (topicId == null) return;
        final index = forumTopics.indexWhere((topic) => topic.id == topicId);
        if (index < 0) return;
        final topic = forumTopics[index];
        if (topic.lastMessageId != 0 &&
            (message.date < topic.lastMessageDate ||
                message.id < topic.lastMessageId)) {
          return;
        }
        forumTopics[index] = ForumTopicOption(
          id: topic.id,
          name: topic.name,
          iconCustomEmojiId: topic.iconCustomEmojiId,
          iconColor: topic.iconColor,
          unreadCount: topic.unreadCount,
          isMuted: topic.isMuted,
          isPinned: topic.isPinned,
          isGeneral: topic.isGeneral,
          isClosed: topic.isClosed,
          creatorId: topic.creatorId,
          lastPreview: message.text.trim(),
          lastSender: _topicPreviewSender(topic.id, message),
          lastMessageDate: message.date,
          lastMessageId: message.id,
        );
        notifyListeners();
        unawaited(_resolveTopicPreviewSenders([message]));
        // New traffic can cross the 12-message or other-user boundary of the
        // creator deletion carve-out.
        _invalidateCreatorDeletionForTopic(topicId);

      case 'updateForumTopic':
        if (update.int64('chat_id') != chatId) return;
        final topicId = update.integer('forum_topic_id');
        if (topicId == null) return;
        final index = forumTopics.indexWhere((topic) => topic.id == topicId);
        if (index < 0) return;
        final settings = update.obj('notification_settings');
        forumTopics[index] = ForumTopicOption(
          id: forumTopics[index].id,
          name: forumTopics[index].name,
          iconCustomEmojiId: forumTopics[index].iconCustomEmojiId,
          iconColor: forumTopics[index].iconColor,
          unreadCount: forumTopics[index].unreadCount,
          isMuted: settings == null
              ? forumTopics[index].isMuted
              : (settings.integer('mute_for') ?? 0) > 0,
          isPinned: update.boolean('is_pinned') ?? forumTopics[index].isPinned,
          isGeneral: forumTopics[index].isGeneral,
          isClosed: forumTopics[index].isClosed,
          creatorId: forumTopics[index].creatorId,
          lastPreview: forumTopics[index].lastPreview,
          lastSender: forumTopics[index].lastSender,
          lastMessageDate: forumTopics[index].lastMessageDate,
          lastMessageId: forumTopics[index].lastMessageId,
        );
        notifyListeners();

      case 'updateForumTopicInfo':
        final info = update.obj('info');
        if (info?.int64('chat_id') != chatId) return;
        final topicId = info?.integer('forum_topic_id');
        final name = info?.str('name');
        if (topicId == null || name == null || name.isEmpty) return;
        final index = forumTopics.indexWhere((topic) => topic.id == topicId);
        if (index < 0) return;
        final topic = forumTopics[index];
        final icon = info?.obj('icon');
        forumTopics[index] = ForumTopicOption(
          id: topic.id,
          name: name,
          iconCustomEmojiId:
              icon?.int64('custom_emoji_id') ?? topic.iconCustomEmojiId,
          iconColor: icon?.integer('color') ?? topic.iconColor,
          unreadCount: topic.unreadCount,
          isMuted: topic.isMuted,
          isPinned: topic.isPinned,
          isGeneral: topic.isGeneral,
          isClosed: info?.boolean('is_closed') ?? topic.isClosed,
          creatorId: topic.creatorId,
          lastPreview: topic.lastPreview,
          lastSender: topic.lastSender,
          lastMessageDate: topic.lastMessageDate,
          lastMessageId: topic.lastMessageId,
        );
        notifyListeners();

      case 'updateDeleteMessages':
        if (update.int64('chat_id') != chatId) return;
        // A deleted last message leaves a stale preview; a refresh is cheap
        // enough here because deletions in forum lists are rare. The deleted
        // message's topic is not part of the update, so every probed creator
        // carve-out is dropped and re-probed on the next menu open.
        if (_creatorDeletableTopicIds.isNotEmpty) {
          _creatorDeletableTopicIds.clear();
          notifyListeners();
        }
        unawaited(loadForumTopics());
    }
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

  bool _isBotUser(Map<String, dynamic> user) => TDParse.isBotUser(user);

  void _applyPeerBotCapabilities(
    Map<String, dynamic> user, {
    bool notify = true,
  }) {
    if (user.int64('id') != peerUserId) return;
    final nextIsBot = TDParse.isBotUser(user);
    final nextSupportsTopics = TDParse.botUserHasTopics(user);
    if (peerIsBot == nextIsBot && supportsBotTopics == nextSupportsTopics) {
      return;
    }
    peerIsBot = nextIsBot;
    supportsBotTopics = nextSupportsTopics;
    if (!supportsTopics) {
      forumTopicsLoading = false;
      forumTopics = const [];
    }
    if (notify) notifyListeners();
  }

  Future<int?> webAppBotUserId(ChatMessage? message) async {
    final viaBotId = message?.viaBotUserId;
    if (viaBotId != null && viaBotId > 0) return viaBotId;
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

  /// Resolves the `@username` of the bot that owns [message] (either its
  /// `via_bot_user_id`, the message's bot sender, or the current bot peer).
  Future<String?> resolveInlineBotUsername(ChatMessage? message) async {
    final cachedHandle = message?.viaBotUsername?.trim();
    if (cachedHandle != null && cachedHandle.startsWith('@')) {
      final clean = cachedHandle.substring(1).trim();
      if (clean.isNotEmpty) return clean;
    }
    final candidates = <int>[
      if (message?.viaBotUserId case final id? when id > 0) id,
      if (message?.senderId case final id? when id > 0) id,
      if (peerIsBot && peerUserId != null && peerUserId! > 0) peerUserId!,
      if (message?.forwardFromUserId case final id? when id > 0) id,
    ];
    final seen = <int>{};
    for (final userId in candidates) {
      if (!seen.add(userId)) continue;
      final cached = _viaBotUsernames[userId];
      if (cached != null && cached.startsWith('@')) {
        final clean = cached.substring(1).trim();
        if (clean.isNotEmpty) return clean;
      }
      try {
        final user = await _client.query({
          '@type': 'getUser',
          'user_id': userId,
        });
        if (!_isBotUser(user)) continue;
        final username = ChatViewModel._primaryUsername(user);
        if (username.isNotEmpty) {
          _viaBotUsernames[userId] = '@$username';
          return username;
        }
      } catch (_) {}
    }
    return null;
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
  /// the send / membership / join flags the chat UI reads, plus the topic
  /// moderation rights the forum topic list gates its actions on.
  void _applyGroupStatus(Map<String, dynamic>? status) {
    switch (status?.type) {
      case 'chatMemberStatusCreator':
        canDeleteMessagesBySender = true;
        canManageTopics = true;
        canDeleteForumTopics = true;
        isMember = true;
        canSendMessages = true;
      case 'chatMemberStatusAdministrator':
        canDeleteMessagesBySender =
            status?.obj('rights')?.boolean('can_delete_messages') ?? false;
        canManageTopics =
            status?.obj('rights')?.boolean('can_manage_topics') ?? false;
        canDeleteForumTopics = canDeleteMessagesBySender;
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
        canSendVoiceNotes =
            status?.obj('permissions')?.boolean('can_send_voice_notes') ??
            canSendVoiceNotes;
        if (!isMember) canJoin = true;
        if (!canSendMessages) {
          sendDisabledReason = AppStrings.t(AppStringKeys.chatYouAreMuted);
        }
      case 'chatMemberStatusLeft':
        isMember = false;
        canSendMessages = false;
        canSendVoiceNotes = false;
        canJoin = true;
      case 'chatMemberStatusBanned':
        isMember = false;
        canSendMessages = false;
        canSendVoiceNotes = false;
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
    // Read alongside the search so a closed bar never flashes open on reopen.
    final dismissal = _ensurePinnedDismissalLoaded();
    try {
      final res = await _queryHistory({
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
      final parsed = (list ?? const [])
          .map(TDParse.message)
          .whereType<ChatMessage>()
          .toList();
      await dismissal;
      _applyPinnedMessages(parsed);
    } catch (_) {}
  }

  /// Re-runs the pinned search after a pin/unpin update: the bar must reflect
  /// both new pins and unpins, including the list becoming empty. A closed bar
  /// stays closed unless the update brought a pin it was not closed over.
  Future<void> _reloadPinnedMessages() async {
    await _loadPinnedMessage();
  }

  void _applyPinnedMessages(List<ChatMessage> parsed) {
    if (parsed.isEmpty) {
      final hadPinned = pinnedMessage != null;
      pinnedMessages = const [];
      pinnedMessageIndex = 0;
      pinnedMessage = null;
      _applyPinnedDismissal();
      if (hadPinned) notifyListeners();
      return;
    }
    pinnedMessages = parsed;
    pinnedMessageIndex = pinnedMessageIndex.clamp(0, parsed.length - 1);
    pinnedMessage = parsed[pinnedMessageIndex];
    _applyPinnedDismissal();
    notifyListeners();
  }

  /// Reads the stored dismissal once per view model. Never throws: without an
  /// account id or preferences the dismissal only lives in memory.
  Future<void> _ensurePinnedDismissalLoaded() =>
      _pinnedDismissalLoad ??= _readPinnedDismissal();

  Future<void> _readPinnedDismissal() async {
    try {
      // Chat ids are account-scoped and slots are reused, so the record is
      // keyed by the stable user id of the account that owns this pane. The
      // pinned search is topic-scoped in a topic transcript, and so is this.
      final me = await _client.queryTo({'@type': 'getMe'}, _accountClientId);
      final userId = me.int64('id');
      if (userId == null || userId <= 0) return;
      final prefs = await SharedPreferences.getInstance();
      final topic = isForumTopicTranscript ? '.topic.$forumTopicId' : '';
      final key =
          '${ChatViewModel._pinnedDismissalPrefix}.$userId.chat.$chatId$topic';
      _pinnedDismissalKey = key;
      // A change made meanwhile is newer than the record and is written next.
      if (_pinnedDismissalChanged) return;
      final stored = prefs.getStringList(key);
      if (stored == null) return;
      _pinnedDismissedIds = stored.map(int.tryParse).whereType<int>().toSet();
    } catch (_) {}
  }

  void _setPinnedDismissal(Set<int>? ids) {
    _pinnedDismissedIds = ids;
    _pinnedDismissalChanged = true;
    unawaited(_writePinnedDismissal());
  }

  Future<void> _writePinnedDismissal() async {
    await _ensurePinnedDismissalLoaded();
    final key = _pinnedDismissalKey;
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      // Read after the awaits: overlapping writes all store the latest state.
      final ids = _pinnedDismissedIds;
      if (ids == null) {
        await prefs.remove(key);
      } else {
        await prefs.setStringList(key, [for (final id in ids) '$id']);
      }
    } catch (_) {}
  }

  /// Re-applies a closed bar to [pinnedMessages]: it stays closed while every
  /// pinned id was already pinned when it was closed. A pin it was not closed
  /// over drops the record and shows the bar again; an empty list prunes the
  /// record, since any later pin is new anyway.
  void _applyPinnedDismissal() {
    final dismissed = _pinnedDismissedIds;
    if (dismissed == null) {
      pinnedDismissed = false;
      return;
    }
    if (pinnedMessages.isNotEmpty &&
        pinnedMessages.every((m) => dismissed.contains(m.id))) {
      pinnedDismissed = true;
      // Forget unpinned ids, so pinning one of them again counts as new.
      if (dismissed.length > pinnedMessages.length) {
        _setPinnedDismissal({for (final m in pinnedMessages) m.id});
      }
      return;
    }
    pinnedDismissed = false;
    _setPinnedDismissal(null);
  }

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
    final current = pinnedMessage;
    _setPinnedDismissal({
      for (final m in pinnedMessages) m.id,
      if (current != null) current.id,
    });
    pinnedDismissed = true;
    notifyListeners();
  }

  Future<void> pinTodo(ChatMessage message) async {
    await _topicAccountQuery({
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
    // A pin made here is new by definition, so the bar shows again.
    pinnedDismissed = false;
    _setPinnedDismissal(null);
    notifyListeners();
  }

  Future<void> unpinTodo(ChatMessage message) async {
    await _topicAccountQuery({
      '@type': 'unpinChatMessage',
      'chat_id': chatId,
      'message_id': message.id,
    });
    final removedIndex = pinnedMessages.indexWhere((m) => m.id == message.id);
    pinnedMessages = pinnedMessages.where((m) => m.id != message.id).toList();
    if (pinnedMessages.isEmpty) {
      pinnedMessage = null;
      pinnedMessageIndex = 0;
      _applyPinnedDismissal();
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
    // Unpinning never reopens a closed bar.
    _applyPinnedDismissal();
    notifyListeners();
  }
}
