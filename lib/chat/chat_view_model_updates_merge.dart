part of 'chat_view_model.dart';

extension ChatViewModelUpdates on ChatViewModel {
  void _subscribeToUpdates() {
    // An open chat used to be woken for every update in the app — including the
    // `updateFile` storm of a chunked download — only to walk 33 cases and
    // return. It now hears exactly the types it handles.
    _sub ??= _client
        .updatesOfAny(ChatViewModel._handledUpdateTypes)
        .listen(_handle);
  }

  void _handle(Map<String, dynamic> update) {
    _foldForumTopicRowUpdate(update);
    switch (update.type) {
      case 'updateNewMessage':
        final raw = update.obj('message');
        if (raw == null || raw.int64('chat_id') != chatId) return;
        if (!_belongsToTranscript(raw)) return;
        final rawContent = raw.obj('content');
        if (rawContent?.type == 'messageChatHasProtectedContentToggled') {
          hasProtectedContent =
              rawContent?.boolean('new_has_protected_content') ??
              hasProtectedContent;
        }
        final message = _parseMessage(raw);
        if (message == null) return;
        final senderId = message.senderId;
        if (isBotApiAccount &&
            !botApiBotToBotAccessObserved &&
            !message.isOutgoing &&
            senderId != null) {
          final sender = TdUserIndex.shared.userFor(
            _client.activeSlot,
            senderId,
          );
          if (sender != null && TDParse.isBotUser(sender)) {
            botApiBotToBotAccessObserved = true;
          }
        }
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
          ++_chatReadStateRevision;
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
        // Apply concealment immediately, before an asynchronous media refresh.
        for (final message in _messageRefs(messageId)) {
          message.hasSpoiler = content.boolean('has_spoiler') ?? false;
        }
        if (content.type == 'messageChatHasProtectedContentToggled') {
          hasProtectedContent =
              content.boolean('new_has_protected_content') ??
              hasProtectedContent;
        }
        if (mediaContentUpdateNeedsRefresh(
          contentType: content.type,
          isSending: _isSending(messageId),
        )) {
          unawaited(_refreshMessage(messageId));
        } else if (content.type == 'messageVideo') {
          _replaceVideoMedia(messageId, content);
        }
        if (content.type == 'messageChatSetBackground' ||
            content.type == 'messageChatSetTheme') {
          unawaited(_refreshMessage(messageId));
          return;
        }
        // A gift's state (converted, upgraded, refunded, an offer's answer)
        // changes in place, and so does a transfer's transaction once it is
        // sent; re-read them so `ChatMessage.gift` / `.gramTransfer` stay
        // current.
        if (TDParse.isGiftContent(content.type) ||
            content.type == MessageGramTransfer.contentType) {
          unawaited(_refreshMessage(messageId));
        }
        _replaceText(
          messageId,
          // Chat-list previews deliberately synthesize labels such as
          // "Photo", "Video", and a document name. A transcript update must
          // keep using only user-authored text, otherwise TDLib's live content
          // update for a just-sent attachment turns that preview label into a
          // visible caption until the confirmed message replaces it.
          TDParse.messageContentText(content, isChannel: isChannel),
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

      case 'updateMessageSuggestedPostInfo':
        if (update.int64('chat_id') != chatId) return;
        final messageId = update.int64('message_id');
        if (messageId == null) return;
        unawaited(_refreshMessage(messageId));

      case 'updateChatUnreadMentionCount':
        if (update.int64('chat_id') != chatId || isForumTopicTranscript) {
          return;
        }
        _setUnreadMentionCount(
          update.integer('unread_mention_count') ?? unreadMentionCount,
        );

      case 'updateMessageMentionRead':
        if (update.int64('chat_id') != chatId) return;
        final messageId = update.int64('message_id');
        if (messageId == null) return;
        _locallyViewedMentionIds.add(messageId);
        while (_locallyViewedMentionIds.length > 512) {
          _locallyViewedMentionIds.remove(_locallyViewedMentionIds.first);
        }
        final targets = _messageRefs(messageId);
        final flagChanged = targets.any(
          (message) => message.containsUnreadMention,
        );
        for (final message in targets) {
          message.containsUnreadMention = false;
        }
        final countChanged = _setUnreadMentionCount(
          update.integer('unread_mention_count') ?? unreadMentionCount,
        );
        if (flagChanged && !countChanged) {
          _notifyLocalizedMessages([messageId]);
        }

      case 'updateChatUnreadReactionCount':
        if (update.int64('chat_id') != chatId || isForumTopicTranscript) {
          return;
        }
        _setUnreadReactionCount(
          update.integer('unread_reaction_count') ?? unreadReactionCount,
        );

      case 'updateMessageUnreadReactions':
        if (update.int64('chat_id') != chatId) return;
        final messageId = update.int64('message_id');
        if (messageId == null) return;
        final hasUnreadReactions =
            (update.objects('unread_reactions') ?? const []).isNotEmpty;
        if (hasUnreadReactions) {
          _locallyViewedReactionIds.remove(messageId);
        } else {
          _locallyViewedReactionIds.add(messageId);
          while (_locallyViewedReactionIds.length > 512) {
            _locallyViewedReactionIds.remove(_locallyViewedReactionIds.first);
          }
        }
        final targets = _messageRefs(messageId);
        final flagChanged = targets.any(
          (message) => message.hasUnreadReactions != hasUnreadReactions,
        );
        for (final message in targets) {
          message.hasUnreadReactions = hasUnreadReactions;
        }
        final countChanged = _setUnreadReactionCount(
          update.integer('unread_reaction_count') ?? unreadReactionCount,
        );
        if (flagChanged && !countChanged) {
          _notifyLocalizedMessages([messageId]);
        }

      case 'updateMessageSendSucceeded':
        if (messageSendUpdateChatId(update) != chatId) return;
        final oldMessageId = update.int64('old_message_id');
        final rawSentMessage = update.obj('message');
        if (oldMessageId == null || rawSentMessage == null) return;
        _acknowledgedPendingMessageIds.remove(oldMessageId);
        if (_latestHistoryLoadInFlight) {
          _latestHistoryLiveArrivals.remove(oldMessageId);
          final sentMessage = _parseMessage(rawSentMessage);
          if (sentMessage != null) {
            _latestHistoryLiveArrivals[sentMessage.id] = sentMessage;
          }
        }
        _replacePendingMessage(oldMessageId, rawSentMessage);
        _recordMessageSendResult(
          oldMessageId,
          const _MessageSendResult.success(),
        );

      case 'updateMessageSendAcknowledged':
        if (update.int64('chat_id') != chatId) return;
        final messageId = update.int64('message_id');
        if (messageId == null) return;
        _rememberAcknowledgedPendingMessageId(messageId);
        final targets = _messageRefs(messageId);
        if (targets.isEmpty) return;
        for (final message in targets) {
          message.isSendAcknowledged = true;
        }
        _notifyLocalizedMessages([messageId]);

      case 'updateMessageSendFailed':
        if (messageSendUpdateChatId(update) != chatId) return;
        final oldMessageId = update.int64('old_message_id');
        if (oldMessageId == null) return;
        _acknowledgedPendingMessageIds.remove(oldMessageId);
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
        if (_isVoiceMessageRestrictionError(error)) {
          canSendVoiceNotes = false;
        }
        _discardPendingMessage(oldMessageId);
        _recordMessageSendResult(
          oldMessageId,
          _MessageSendResult.failure(error),
        );
        _publishSendFailure(
          ChatSendFailure.fromError(
            error,
            paidMessageStarCount: paidMessageStarCount,
          ),
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
        if (!isForumTopicTranscript &&
            chat.containsKey('last_read_inbox_message_id') &&
            chat.containsKey('unread_count')) {
          lastReadInboxId =
              chat.int64('last_read_inbox_message_id') ?? lastReadInboxId;
          unreadCount = chat.integer('unread_count') ?? unreadCount;
          _primeLastMessage(chat, preserveNewer: true);
          ++_chatReadInboxRevision;
          ++_chatReadStateRevision;
        }
        if (!isForumTopicTranscript) {
          unreadMentionCount =
              chat.integer('unread_mention_count') ?? unreadMentionCount;
          unreadReactionCount =
              chat.integer('unread_reaction_count') ?? unreadReactionCount;
        }
        messageAutoDeleteTime = _autoDeleteSeconds(chat);
        _setPaidMessageStarCount(_paidMessageStars(chat), notify: false);
        hasProtectedContent =
            chat.boolean('has_protected_content') ?? hasProtectedContent;
        if (chat.containsKey('permissions')) {
          canSendVoiceNotes =
              chat.obj('permissions')?.boolean('can_send_voice_notes') ??
              canSendVoiceNotes;
        }
        if (!isForumTopicTranscript && chat.containsKey('draft_message')) {
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
        if (update.int64('chat_id') != chatId || isForumTopicTranscript) {
          return;
        }
        _applyRemoteDraft(update.obj('draft_message'));

      case 'updateForumTopic':
        if (!isForumTopicTranscript ||
            update.int64('chat_id') != chatId ||
            update.integer('forum_topic_id') != forumTopicId) {
          return;
        }
        lastReadOutboxId =
            update.int64('last_read_outbox_message_id') ?? lastReadOutboxId;
        final topicReadInbox = update.int64('last_read_inbox_message_id');
        if (topicReadInbox != null && topicReadInbox > lastReadInboxId) {
          lastReadInboxId = topicReadInbox;
          ++_chatReadInboxRevision;
          ++_chatReadStateRevision;
        }
        _setUnreadMentionCount(
          update.integer('unread_mention_count') ?? unreadMentionCount,
        );
        _setUnreadReactionCount(
          update.integer('unread_reaction_count') ?? unreadReactionCount,
        );
        if (update.containsKey('draft_message')) {
          _applyRemoteDraft(update.obj('draft_message'), notify: false);
        }
        notifyListeners();

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

      case 'updateMessageIsPinned':
        if (update.int64('chat_id') != chatId) return;
        // The pinned bar is a topic-scoped search's snapshot; a pin or unpin
        // elsewhere in the chat invalidates it. Re-running the scoped search
        // also keeps the topic's own pinned message current, which the update
        // alone cannot tell because it carries no topic reference.
        unawaited(_reloadPinnedMessages());

      case 'updateDeleteMessages':
        if (update.int64('chat_id') != chatId) return;
        // from_cache unloads (is_permanent == false) must not remove messages
        // from the UI — the messages still exist on the server.
        if (update.boolean('is_permanent') != true) return;
        final deletedIds = update.int64Array('message_ids') ?? const <int>[];
        ++_chatReadStateRevision;
        if (_isLoadingNewer) {
          _newerHistoryDeletedMessageIds.addAll(deletedIds);
        }
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
        _messageIndexesDirty = true;
        _hasOlderHistory = false;
        anchoredHistory = false;
        _historyAnchorMessageId = null;
        _historyReachesLatest = true;
        _knownLatestMessageId = 0;
        ++_chatReadStateRevision;
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
        if (update.int64('chat_id') != chatId || isForumTopicTranscript) {
          return;
        }
        lastReadOutboxId =
            update.int64('last_read_outbox_message_id') ?? lastReadOutboxId;
        notifyListeners();

      case 'updateChatReadInbox':
        if (update.int64('chat_id') != chatId || isForumTopicTranscript) {
          return;
        }
        lastReadInboxId =
            update.int64('last_read_inbox_message_id') ?? lastReadInboxId;
        unreadCount = update.integer('unread_count') ?? unreadCount;
        ++_chatReadInboxRevision;
        ++_chatReadStateRevision;
        notifyListeners();

      case 'updateChatIsMarkedAsUnread':
        if (update.int64('chat_id') != chatId || isForumTopicTranscript) {
          return;
        }
        isMarkedUnread = update.boolean('is_marked_as_unread') ?? false;
        notifyListeners();

      case 'updateChatAction':
        if (update.int64('chat_id') != chatId) return;
        final sender = update.obj('sender_id');
        final sid = sender?.int64('user_id') ?? sender?.int64('chat_id');
        if (sid == null) return;
        final actionType = update.obj('action')?.type;
        if (actionType == 'chatActionCancel') {
          // Nothing rendered changes when the sender had no active action.
          if (_chatActions.remove(sid) == null) return;
        } else {
          final name = _senderCache[sid]?.name ?? '';
          final action = actionType ?? 'chatActionTyping';
          final active = _chatActions[sid];
          // TDLib re-sends the same action every few seconds while it lasts;
          // notifying again rebuilds the whole screen for the same subtitle.
          final unchanged =
              active != null &&
              active.actionType == action &&
              active.name == name;
          if (!unchanged) _chatActions[sid] = _ChatActionInfo(name, action);
          if (name.isEmpty && isGroup && sid > 0) {
            _resolveSender(sid); // fills the name for the next render
          }
          _restartTypingTimer();
          if (unchanged) return;
        }
        _notifyComposerNeutral();

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
        if (!isGroup && user.int64('id') == peerUserId) {
          _applyPeerBotCapabilities(user);
        }
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
        final nextIsForum = supergroup.boolean('is_forum') ?? isForum;
        final nextHasForumTabs =
            supergroup.boolean('has_forum_tabs') ?? hasForumTabs;
        if (isForum != nextIsForum || hasForumTabs != nextHasForumTabs) {
          isForum = nextIsForum;
          hasForumTabs = nextHasForumTabs;
          notifyListeners();
          if (supportsTopics && forumTopics.isEmpty) {
            unawaited(loadForumTopics());
          }
        }
        _setPaidMessageStarCount(_paidMessageStars(supergroup));

      case 'updateSupergroupFullInfo':
        if (update.int64('supergroup_id') != peerSupergroupId) return;
        final fullInfo = update.obj('supergroup_full_info') ?? update;
        linkedDiscussionChatId = isChannel
            ? (fullInfo.int64('linked_chat_id') ?? 0)
            : 0;
        hasLinkedDiscussion = linkedDiscussionChatId != 0;
        directMessagesChatId = isChannel
            ? (fullInfo.int64('direct_messages_chat_id') ?? 0)
            : 0;
        _setPaidMessageStarCount(_paidMessageStars(fullInfo));
        if (isChannel) {
          _clearGroupBotCommands();
        } else {
          unawaited(_applyGroupBotCommands(fullInfo));
        }

      case 'updateBasicGroupFullInfo':
        if (update.int64('basic_group_id') != peerBasicGroupId) return;
        final fullInfo = update.obj('basic_group_full_info') ?? update;
        final members = fullInfo.objects('members');
        if (members != null) memberCount = members.length;
        notifyListeners();
        unawaited(_applyGroupBotCommands(fullInfo));

      case 'updateUserStatus':
        if (isGroup || update.int64('user_id') != peerUserId) return;
        final status = update.obj('status');
        peerOnline = status?.type == 'userStatusOnline';
        peerStatusText = status == null
            ? ''
            : TDParse.userStatus({'status': status});
        _notifyComposerNeutral();

      case 'updateMessageEdited':
        if (update.int64('chat_id') != chatId) return;
        final mid = update.int64('message_id');
        if (mid == null) return;
        final rows = TDParse.messageButtonRows(update.obj('reply_markup'));
        final targets = _messageRefs(mid);
        if (targets.isEmpty) return;
        // One lookup and one notify for the whole edit: the button rows used
        // to be applied through a second scan that notified on its own.
        var edited = false;
        for (final message in targets) {
          if (!identical(message.buttonRows, rows)) {
            message.buttonRows = rows;
            edited = true;
          }
          if (!message.isEdited) {
            message.isEdited = true;
            edited = true;
          }
        }
        if (edited) _notifyLocalizedMessages([mid]);

      case 'updateMessageInteractionInfo':
        if (update.int64('chat_id') != chatId) return;
        final mid = update.int64('message_id');
        if (mid == null) return;
        final targets = _messageRefs(mid);
        if (targets.isNotEmpty) {
          final interactionInfo = update.obj('interaction_info');
          final replyInfo = interactionInfo?.obj('reply_info');
          final reactions = TDParse.reactionsFrom({
            'interaction_info': interactionInfo,
          });
          for (final message in targets) {
            message.commentThreadMetadataKnown = true;
            message.reactions = reactions;
            message.viewCount = interactionInfo?.integer('view_count') ?? 0;
            message.forwardCount =
                interactionInfo?.integer('forward_count') ?? 0;
            if (!message.isContentRestricted) {
              message.hasCommentThread = replyInfo != null;
              message.commentCount =
                  replyInfo?.integer('reply_count') ??
                  replyInfo?.integer('comment_count') ??
                  0;
              message.lastCommentMessageId = replyInfo?.int64(
                'last_message_id',
              );
            }
          }
          _notifyLocalizedMessages([mid]);
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
        _aiReplyBlockedSenderKeysFuture = null;
        _aiReplyBlockedSenderRevision++;
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

  // MARK: - 引用 reply-quote resolution

  /// For each message that replies to another, resolve the quoted sender +
  /// preview — from the already-loaded list when possible, else via getMessages.
  void _resolveRepliesIfNeeded(List<ChatMessage> batch) {
    final repliesToResolve = batch
        .where(
          (message) =>
              message.replyToMessageId != null &&
              message.replyToPreview == null,
        )
        .toList(growable: false);
    if (repliesToResolve.isEmpty) return;
    // This index is already maintained by transcript mutations. Rebuilding a
    // map for each history page (or scanning the transcript for a live reply)
    // made quoting increasingly expensive as more history was loaded.
    _ensureMessageIndexes();
    final unresolvedByChat = <int, Map<int, List<ChatMessage>>>{};
    for (final m in repliesToResolve) {
      final rid = m.replyToMessageId!;
      final rChatId = m.replyToChatId ?? m.chatId ?? chatId;
      final quoted = rChatId == chatId
          ? (_messagesById[rid] ?? _allMessagesById[rid])
          : null;
      if (quoted != null) {
        // The locally cached target is trusted only across the restriction
        // boundary: a redacted message must not lend its text to this anchor,
        // and no remote lookup can repair the hole it would leave.
        if (!quoted.isContentRestricted) {
          _applyReply(m, quoted);
        }
        continue;
      }
      // Reply-to-deleted fill: when the target is not in
      // the transcript, the local mirror may still hold a kept copy of the
      // deleted original; its text fills the reply anchor like a quote.
      if (_applyMirrorReply(m, rid, rChatId)) {
        continue;
      }
      final unresolved = unresolvedByChat.putIfAbsent(
        rChatId,
        () => <int, List<ChatMessage>>{},
      );
      unresolved.putIfAbsent(rid, () => <ChatMessage>[]).add(m);
    }
    if (unresolvedByChat.isEmpty) return;
    // One getMessage per distinct target meant 10-25 concurrent round trips for
    // a single reply-heavy history page, repeated for every page scrolled up.
    // getMessages answers them all at once, so the previews fill in together.
    for (final entry in unresolvedByChat.entries) {
      final targetChatId = entry.key;
      final unresolved = entry.value;
      final targets = unresolved.keys.toList();
      for (var start = 0; start < targets.length; start += 100) {
        final end = start + 100 > targets.length ? targets.length : start + 100;
        _resolveReplyTargets(
          targetChatId,
          targets.sublist(start, end),
          unresolved,
        );
      }
    }
  }

  /// Fetches one batch of reply targets and patches every message waiting on it.
  void _resolveReplyTargets(
    int targetChatId,
    List<int> messageIds,
    Map<int, List<ChatMessage>> unresolved,
  ) {
    _client
        .query({
          '@type': 'getMessages',
          'chat_id': targetChatId,
          'message_ids': messageIds,
        })
        .then((response) {
          if (_chatOpenWorkIsStale) return;
          final updatedIds = <int>{};
          // Unavailable ids come back as nulls that carry no identity, so the
          // bucket is looked up by the id on each returned message, not by
          // position.
          final raws =
              response.objects('messages') ?? const <Map<String, dynamic>>[];
          for (final raw in raws) {
            final quoted = _parseMessage(raw);
            if (quoted == null) continue;
            final waiting = unresolved[quoted.id];
            if (waiting == null) continue;
            for (final m in waiting) {
              final refs = _messageRefs(m.id);
              final targets = refs.isEmpty ? <ChatMessage>[m] : refs;
              for (final message in targets) {
                // A held lookup belongs to the COMPLETE target captured when it
                // was issued. The message id alone is not identity: the refresh
                // may have retargeted this very reply to another chat that uses
                // the same numeric id, and applying the old chat's payload
                // would hydrate the new target with another message's text.
                final liveChatId =
                    message.replyToChatId ?? message.chatId ?? chatId;
                if (message.replyToMessageId != quoted.id ||
                    liveChatId != targetChatId ||
                    message.replyToPreview != null) {
                  continue;
                }
                // Returned quotes must come from the requested chat: a
                // mis-addressed response would otherwise smuggle a same-id
                // message of a foreign chat into the reply anchor.
                final quotedChatId = quoted.chatId ?? targetChatId;
                if (quotedChatId != targetChatId) continue;
                // A restriction-redacted reply must never be hydrated from
                // cached quote plaintext, and a redacted response is a
                // withdrawal, not an anchor to copy.
                if (message.isContentRestricted || quoted.isContentRestricted) {
                  continue;
                }
                _applyReply(message, quoted);
                updatedIds.add(message.id);
              }
            }
          }
          if (updatedIds.isNotEmpty) {
            _bumpMaterializedMessageRevisions(updatedIds);
            _scheduleCoalescedNotify();
          }
        })
        .catchError((_) {});
  }

  void _applyReply(ChatMessage m, ChatMessage quoted) {
    m.replyToPreview = _replyPreview(quoted);
    m.replyToDate = quoted.date;
    m.replyToEntities = quoted.textEntities;
    m.replyToImage = quoted.previewImage;
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
    if (existing != null && existing.name.isNotEmpty) {
      m.replyToSender = existing.name;
      _bumpMaterializedMessageRevisions([m.id]);
      _scheduleCoalescedNotify();
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
      _bumpMaterializedMessageRevisions([m.id]);
      _scheduleCoalescedNotify();
    }
  }

  String _replyPreview(ChatMessage q) {
    if (q.document != null) {
      return AppStrings.t(AppStringKeys.composerFilePreview, {
        'value1': q.document!.fileName,
      });
    }
    if (q.voice != null) {
      return AppStrings.t(AppStringKeys.composerVoicePreview);
    }
    if (q.location != null) {
      return AppStrings.t(AppStringKeys.composerLocationPreview);
    }
    if (q.isDice) {
      return q.diceEmoji ?? q.text;
    }
    if (q.isAnimatedEmoji) {
      return q.text;
    }
    if (q.animatedSticker != null) {
      return AppStrings.t(AppStringKeys.composerAnimatedEmojiPreview);
    }
    if (q.image != null) {
      final placeholder = switch (q.contentType) {
        'messagePhoto' => AppStrings.t(AppStringKeys.composerImagePreview),
        'messageVideo' => AppStrings.t(AppStringKeys.chatVideoPlaceholder),
        'messageAnimation' => AppStrings.t(AppStringKeys.tdMessageGif),
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
    if (HiddenSenderStore.shared.hides(senderId, chatId)) return true;
    return KeywordBlocker.shared.matches(message.text);
  }

  // ---------------------------------------------------------------------------
  // Ghost transcript (Telegram §1.4 mirror, self-build gated)
  // ---------------------------------------------------------------------------

  /// Rebuilds `messages` from `_allMessages` and refreshes the lookup indexes.
  ///
  /// One pass does the filtering, the blocked-user marking and the index fill
  /// that used to cost four separate walks plus a sort. `_allMessages` is kept
  /// sorted by every writer, so re-sorting the filtered subsequence here was
  /// pure cost on every incoming message.
  void _applyKeywordFilter() {
    // The chat_view transcript memo relies on list identity to notice
    // blocked-state changes, so the flags must be set before `messages` is
    // published — never flip them outside this pass.
    final blockedUserService = BlockedUserService.shared;
    final marksBlockedUsers = blockedUserService.enabled;
    _marksBlockedUsers = marksBlockedUsers;
    final visible = <ChatMessage>[];
    final blockedIds = <int>[];
    _messagesById.clear();
    _allMessagesById.clear();
    _messagesBySenderId.clear();
    _pendingMessageCount = 0;
    for (final message in _allMessages) {
      assert(_recordTranscriptScanVisitForTesting());
      _allMessagesById[message.id] = message;
      if (isPendingChatMessage(message)) ++_pendingMessageCount;
      if (_isBlockedMessage(message)) {
        blockedIds.add(message.id);
        continue;
      }
      final senderId = message.senderId;
      message.blockedByUser =
          marksBlockedUsers &&
          !message.isOutgoing &&
          !message.isService &&
          senderId != null &&
          blockedUserService.isBlocked(senderId);
      visible.add(message);
      _messagesById[message.id] = message;
      if (senderId != null) {
        (_messagesBySenderId[senderId] ??= <ChatMessage>[]).add(message);
      }
    }
    _messageIndexesDirty = false;
    // Guards the dropped sort. With a pending send in the list the comparator
    // is not a total order, so only the pure-id case can be checked.
    assert(_pendingMessageCount > 0 || _isSortedById(_allMessages));
    messages = visible;
    _foldGhostsIntoTranscript();
    _blockedMessageIds = blockedIds;
    _markBlockedMessagesReadThroughVisibleBoundary(blockedIds);
    notifyListeners();
  }

  /// Folds one strictly-newest message into the published transcript without
  /// the whole-transcript rebuild [_applyKeywordFilter] does.
  ///
  /// That rebuild walked every loaded message and refilled three indexes per
  /// arrival, so a chat got measurably slower the further back the user had
  /// scrolled — thousands of blocked checks and map inserts for one message.
  void _appendToVisibleTranscript(ChatMessage message) {
    final blockedUserService = BlockedUserService.shared;
    // The full pass re-evaluates blockedByUser for the whole transcript. The
    // other inputs to it announce themselves (KeywordBlocker notifies,
    // updateBlockMessageSender reloads), but this toggle does not, so a change
    // has to fall back.
    if (blockedUserService.enabled != _marksBlockedUsers) {
      _applyKeywordFilter();
      return;
    }
    // Guaranteed by _appendIfStrictlyNewest, so the pending count cannot move.
    assert(!isPendingChatMessage(message));
    // A revived message (the same id as a folded ghost re-entering the
    // transcript) must retire its ghost through the full rebuild — the fast
    // path would leave both the ghost and the live copy on screen.
    if (_ghostsEnabled) {
      final accountUserId = _accountUserId;
      final revivedGhost =
          accountUserId != null &&
          (historyStoreOverride ?? MessageHistoryStore.shared)
              .deletedEntriesFor(
                accountUserId,
                chatId,
                topicId: forumTopicId ?? 0,
              )
              .any((entry) => entry.messageId == message.id);
      if (revivedGhost) {
        _applyKeywordFilter();
        return;
      }
    }
    _allMessagesById[message.id] = message;
    if (_isBlockedMessage(message)) {
      _blockedMessageIds.add(message.id);
    } else {
      final senderId = message.senderId;
      message.blockedByUser =
          _marksBlockedUsers &&
          !message.isOutgoing &&
          !message.isService &&
          senderId != null &&
          blockedUserService.isBlocked(senderId);
      // Reassigned, never mutated: chat_view's transcript memo keys on the
      // list's identity.
      messages = [...messages, message];
      _messagesById[message.id] = message;
      if (senderId != null) {
        (_messagesBySenderId[senderId] ??= <ChatMessage>[]).add(message);
      }
    }
    _messageIndexesDirty = false;
    _markBlockedMessagesReadThroughVisibleBoundary(_blockedMessageIds);
    notifyListeners();
  }

  bool _isSortedById(List<ChatMessage> list) {
    for (var i = 1; i < list.length; i++) {
      if (list[i - 1].id > list[i].id) return false;
    }
    return true;
  }

  /// Refreshes the lookup indexes after a caller mutated either list without
  /// going through `_applyKeywordFilter`.
  void _ensureMessageIndexes() {
    if (!_messageIndexesDirty) return;
    _messagesById.clear();
    _allMessagesById.clear();
    _messagesBySenderId.clear();
    _pendingMessageCount = 0;
    for (final message in _allMessages) {
      assert(_recordTranscriptScanVisitForTesting());
      _allMessagesById[message.id] = message;
      if (isPendingChatMessage(message)) ++_pendingMessageCount;
    }
    for (final message in messages) {
      assert(_recordTranscriptScanVisitForTesting());
      _messagesById[message.id] = message;
      final senderId = message.senderId;
      if (senderId != null) {
        (_messagesBySenderId[senderId] ??= <ChatMessage>[]).add(message);
      }
    }
    _messageIndexesDirty = false;
  }

  void _markBlockedMessagesReadThroughVisibleBoundary(List<int> blockedIds) {
    if (blockedIds.isEmpty || _allMessages.isEmpty) return;
    final visibleMax = latestServerMessageReadBoundary(
      visibleMessages: messages,
      allMessages: _allMessages,
    );
    if (visibleMax <= 0) return;
    final ids = blockedIds
        .where((id) => id <= visibleMax && !_blockedReadIds.contains(id))
        .toList();
    if (ids.isEmpty) return;
    _blockedReadIds.addAll(ids);
    for (var i = 0; i < ids.length; i += 100) {
      final end = i + 100 > ids.length ? ids.length : i + 100;
      final chunk = ids.sublist(i, end);
      // Blocked-country messages must clear locally too; only the server
      // report is skipped in ghost mode.
      if (!(allowTelegramTosViolations &&
          GhostModeController.shared.shouldBlockRead(chatId).isBlock)) {
        _client.send({
          '@type': 'viewMessages',
          'chat_id': chatId,
          'message_ids': chunk,
          'force_read': true,
        });
      }
    }
  }

  /// Re-applies what this client already knows about [incoming] messages
  /// (acknowledged sends, locally viewed mentions and reactions) before they
  /// replace their stale copies.
  void _applyLocalMessageState(List<ChatMessage> incoming) {
    for (final message in incoming) {
      if (_acknowledgedPendingMessageIds.contains(message.id)) {
        message.isSendAcknowledged = true;
      }
      if (_locallyViewedMentionIds.contains(message.id)) {
        message.containsUnreadMention = false;
      }
      if (_locallyViewedReactionIds.contains(message.id)) {
        message.hasUnreadReactions = false;
      }
    }
  }

  void _merge(List<ChatMessage> incoming) {
    if (incoming.isEmpty) return;
    _applyLocalMessageState(incoming);
    if (_appendIfStrictlyNewest(incoming)) {
      _appendToVisibleTranscript(incoming.first);
      return;
    }
    _allMessages = mergeChatMessages(
      _allMessages,
      incoming,
      ignoredMessageIds: _ignoredMergeMessageIds,
    );
    _applyKeywordFilter();
  }

  /// A live message almost always arrives newer than everything loaded, where
  /// the general merge still rebuilds a map of the whole transcript and
  /// re-sorts it. Appending skips both — but only while the list holds no
  /// pending send, because then the comparator is a plain ascending id order
  /// and the tail is provably the largest element.
  bool _appendIfStrictlyNewest(List<ChatMessage> incoming) {
    if (incoming.length != 1 || _allMessages.isEmpty) return false;
    final message = incoming.first;
    if (isPendingChatMessage(message)) return false;
    _ensureMessageIndexes();
    if (_pendingMessageCount > 0) return false;
    if (_allMessages.last.id >= message.id) return false;
    if (_allMessagesById.containsKey(message.id)) return false;
    if (_ignoredMergeMessageIds.contains(message.id)) return false;
    _allMessages.add(message);
    _messageIndexesDirty = true;
    return true;
  }

  void _mergeHistoryWindow(
    List<ChatMessage> incoming, {
    required List<ChatMessage> messagesAtRequestStart,
    required bool replaceCurrentWindow,
    required bool preserveLiveArrivals,
  }) {
    if (incoming.isEmpty) return;
    _applyLocalMessageState(incoming);
    _allMessages = mergeChatHistoryWindow(
      currentAtRequestStart: messagesAtRequestStart,
      currentAtCompletion: _allMessages,
      fetched: incoming,
      replaceCurrentWindow: replaceCurrentWindow,
      preserveLiveArrivals: preserveLiveArrivals,
      ignoredMessageIds: _ignoredMergeMessageIds,
    );
    _applyKeywordFilter();
  }

  void _rememberSettledPendingMessageId(int messageId) {
    _settledPendingMessageIds.add(messageId);
    while (_settledPendingMessageIds.length > 256) {
      _settledPendingMessageIds.remove(_settledPendingMessageIds.first);
    }
    _ignoredMergeMessageIdsCache = null;
  }

  void _rememberAcknowledgedPendingMessageId(int messageId) {
    _acknowledgedPendingMessageIds.add(messageId);
    while (_acknowledgedPendingMessageIds.length > 256) {
      _acknowledgedPendingMessageIds.remove(
        _acknowledgedPendingMessageIds.first,
      );
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
        final current = _parseMessage(raw);
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
      target.textQuoteSource = text;
      target.textQuoteSourceEntities = entities ?? target.textEntities;
      if (entities != null) target.textEntities = entities;
      if (customEmoji != null) target.customEmoji = customEmoji;
      if (updateLinkPreview) target.linkPreview = linkPreview;
      if (edited) target.isEdited = true;
    }
    // Text can only change transcript membership while text rules exist.
    // Sender blocking is independent of the body, so the overwhelmingly
    // common no-keyword path can avoid republishing and rescanning every
    // loaded message. A full ChatView sync is still required because message
    // text feeds chat-language detection, automatic translation, the repeat
    // affordance on the next bubble, and any open message action overlay.
    if (!KeywordBlocker.shared.hasTextRules) {
      _notifyMessagesWithFullViewSync([messageId]);
    } else {
      _applyKeywordFilter();
    }
  }

  bool _isSending(int messageId) =>
      _messageRefs(messageId).any((message) => message.isSending);

  void _replaceVideoMedia(int messageId, Map<String, dynamic> content) {
    final media = TDParse.mediaAttachment(content);
    for (final target in _messageRefs(messageId)) {
      target.contentType = content.type;
      target.image =
          media.image?.inheritLocalPathFrom(target.image) ?? target.image;
      target.video =
          media.video?.inheritLocalPathFrom(target.video) ?? target.video;
      if ((media.width ?? 0) > 0) target.imageWidth = media.width;
      if ((media.height ?? 0) > 0) target.imageHeight = media.height;
      if ((media.videoDuration ?? 0) > 0) {
        target.videoDuration = media.videoDuration;
      }
      if ((media.videoFileSize ?? 0) > 0) {
        target.videoFileSize = media.videoFileSize;
      }
    }
  }

  void _replacePendingMessage(
    int pendingMessageId,
    Map<String, dynamic> rawMessage,
  ) {
    _rememberSettledPendingMessageId(pendingMessageId);
    if (_discardedPendingMessageIds.remove(pendingMessageId)) {
      _ignoredMergeMessageIdsCache = null;
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
    _ensureMessageIndexes();
    final pendingMessage =
        _allMessagesById[pendingMessageId] ?? _messagesById[pendingMessageId];
    _allMessages.removeWhere((message) => message.id == pendingMessageId);
    // Reassigned (not mutated) so the transcript memo's identity check stays
    // valid even if a notify lands before the merge below.
    messages = messages
        .where((message) => message.id != pendingMessageId)
        .toList();
    _messageIndexesDirty = true;
    final sentMessage = _parseMessage(rawMessage);
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
    _scheduleCoalescedNotify();
  }

  void restoreMessageTranslation(
    int messageId,
    MessageTranslationResult translation,
  ) {
    _replaceTranslation(
      messageId,
      translation.text,
      translation.entities,
      translation.languageCode,
    );
  }

  void clearTranslations(Iterable<int> messageIds) {
    var changed = false;
    for (final messageId in messageIds.toSet()) {
      for (final message in _messageRefs(messageId)) {
        if (message.translationText == null && !message.isTranslating) continue;
        message.translationText = null;
        message.translationEntities = const [];
        message.translationLanguageCode = null;
        message.isTranslating = false;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  List<ChatMessage> _messageRefs(int messageId) {
    _ensureMessageIndexes();
    final refs = <ChatMessage>[];
    final visible = _messagesById[messageId];
    final loaded = _allMessagesById[messageId];
    if (visible != null) refs.add(visible);
    if (loaded != null && (visible == null || !identical(visible, loaded))) {
      refs.add(loaded);
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
    // This path bypasses _applyKeywordFilter, so the lookup indexes would
    // otherwise keep handing out deleted messages.
    _messageIndexesDirty = true;
    _blockedReadIds.removeWhere(removed.contains);
    // Same reason: the incremental append path hands this list straight to the
    // read-boundary marker, so a deleted id left here is force-read again (and
    // never dropped until the next full pass).
    _blockedMessageIds.removeWhere(removed.contains);
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
      _applyPinnedDismissal();
    }
    notifyListeners();
  }

  void _patchSender(_SenderInfo info, int senderId) {
    _patchSenders(<int, _SenderInfo>{senderId: info});
  }

  void _patchSenders(Map<int, _SenderInfo> senders) {
    if (senders.isEmpty) return;
    // Walk only the bubbles of the senders being patched. _resolveSender fires
    // this twice per sender, so a whole-transcript walk per call was the bulk
    // of the cost of opening or paging a busy group.
    _ensureMessageIndexes();
    var changed = false;
    for (final entry in senders.entries) {
      final bucket = _messagesBySenderId[entry.key];
      if (bucket == null) continue;
      final info = entry.value;
      for (final m in bucket) {
        if (m.isOutgoing && !m.senderIsChat) continue;
        if (m.senderName == info.name &&
            _sameSenderPhoto(m.senderPhoto, info.photo) &&
            m.senderRole == info.role &&
            m.senderTitle == (info.title ?? m.senderTitle) &&
            m.senderIsPremium == info.isPremium &&
            m.senderIsDeleted == info.isDeleted &&
            m.senderAccentColorId == info.accentColorId &&
            m.senderEmojiStatusId == info.emojiStatusId) {
          continue;
        }
        m.senderName = info.name;
        m.senderPhoto = info.photo;
        m.senderRole = info.role;
        m.senderTitle = info.title ?? m.senderTitle;
        m.senderIsPremium = info.isPremium;
        m.senderIsDeleted = info.isDeleted;
        m.senderAccentColorId = info.accentColorId;
        m.senderEmojiStatusId = info.emojiStatusId;
        changed = true;
      }
    }
    // Ghost bubbles never join the id/sender indexes (their ids no longer
    // exist on Telegram's side), so the loop above cannot reach them. Patch
    // the folded ghosts of the resolved senders directly — otherwise a group
    // ghost stays unattributed until the next full transcript rebuild.
    if (allowTelegramTosViolations) {
      for (final m in messages) {
        final entry = m.mirrorEntry;
        if (entry == null) continue;
        if (!senders.containsKey(entry.senderId)) continue;
        final name = senders[entry.senderId]!.name;
        if (m.senderName != name) {
          m.senderName = name;
          changed = true;
        }
      }
    }
    if (changed) _scheduleCoalescedNotify();
  }

  bool _sameSenderPhoto(TdFileRef? current, TdFileRef? next) {
    if (identical(current, next)) return true;
    if (current == null || next == null) return false;
    return current.id == next.id &&
        current.localPath == next.localPath &&
        current.photoId == next.photoId &&
        current.hasAnimation == next.hasAnimation;
  }

  /// Folds a burst of background patches into one notify per frame. Every
  /// notify drives a full chat-screen rebuild, and the per-message resolvers
  /// (senders, replies, forwards, service text, translations) each complete on
  /// their own round trip.
  void _scheduleCoalescedNotify() {
    if (_isDisposed) return;
    if (_coalescedNotifyTimer != null) return;
    _coalescedNotifyTimer = Timer(const Duration(milliseconds: 16), () {
      _coalescedNotifyTimer = null;
      notifyListeners();
    });
  }

  // MARK: - Sender resolution (groups/channels only)

  void _resolveSendersIfNeeded(List<ChatMessage> batch) {
    if (!isGroup) return;
    final senderIds = _resolvableSenderIds(batch);
    final cachedToPatch = _primeCachedSenderIdentities(senderIds);
    final pending = <int>{};
    for (final senderId in senderIds) {
      final cached = _senderCache[senderId];
      if (cached != null) {
        cachedToPatch[senderId] = cached;
        if (!_resolvedSenderDetails.contains(senderId) &&
            !_resolvingSenders.contains(senderId)) {
          pending.add(senderId);
        }
      } else if (!_resolvingSenders.contains(senderId)) {
        pending.add(senderId);
      }
    }
    _patchSenders(cachedToPatch);
    for (final senderId in pending) {
      _resolvingSenders.add(senderId);
      _resolveSender(senderId);
    }
  }

  Set<int> _resolvableSenderIds(Iterable<ChatMessage> batch) => {
    for (final message in batch)
      if (!(message.isOutgoing && !message.senderIsChat) &&
          !message.isService &&
          message.senderId != null)
        message.senderId!,
  };

  Map<int, _SenderInfo> _primeCachedSenderIdentities(Set<int> senderIds) {
    final primed = <int, _SenderInfo>{};
    for (final senderId in senderIds) {
      if (senderId <= 0) continue;
      final user = TdUserIndex.shared.userFor(_client.activeSlot, senderId);
      if (user == null) continue;
      final existing = _senderCache[senderId];
      final info = _senderInfoFromUser(
        user,
        role: existing?.role ?? MemberRole.member,
        title: existing?.title,
      );
      _senderCache[senderId] = info;
      primed[senderId] = info;
    }
    return primed;
  }

  @visibleForTesting
  void primeCachedSenderIdentitiesForTesting() {
    _patchSenders(_primeCachedSenderIdentities(_resolvableSenderIds(messages)));
  }

  @visibleForTesting
  void applySenderUserUpdateForTesting(Map<String, dynamic> user) {
    _applySenderUserUpdate(user);
  }

  @visibleForTesting
  void applyLiveUpdateForTesting(Map<String, dynamic> update) {
    _handle(update);
  }

  @visibleForTesting
  void markChatReadStateReadyForTesting() {
    _chatReadStateLoaded = true;
    _historyReachesLatest = true;
  }

  @visibleForTesting
  void isForumForTesting(bool value) {
    isForum = value;
  }

  @visibleForTesting
  void supportsBotTopicsForTesting(bool value) {
    supportsBotTopics = value;
  }

  @visibleForTesting
  void forumTopicsLoadedForTesting(List<ForumTopicIndexEntry> entries) {
    forumTopicsLoading = false;
    _forumTopicsLoaded = true;
    if (!_forumTopicIndexListening) {
      ForumTopicIndex.shared.addListener(_onForumTopicIndexChanged);
      _forumTopicIndexListening = true;
    }
    ForumTopicIndex.shared.storeAll(_accountSlot, chatId, entries);
    forumTopics = [
      for (final entry in ForumTopicIndex.shared.topicsFor(
        _accountSlot,
        chatId,
      ))
        _optionFromIndex(entry),
    ];
  }

  @visibleForTesting
  void historyReachesLatestForTesting() {
    _historyReachesLatest = true;
  }

  @visibleForTesting
  void mergeMessageForTesting(ChatMessage message) {
    _merge([message]);
  }

  void _applySenderUserUpdate(Map<String, dynamic> user) {
    if (!isGroup) return;
    final userId = user.int64('id');
    if (userId == null) return;
    // TDLib emits updateUser for every user the account learns about, so test
    // the cheap cache before touching the transcript at all.
    if (!_senderCache.containsKey(userId) && !_hasVisibleSender(userId)) return;
    final existing = _senderCache[userId];
    final info = _senderInfoFromUser(
      user,
      role: existing?.role ?? MemberRole.member,
      title: existing?.title,
    );
    _senderCache[userId] = info;
    _patchSender(info, userId);
  }

  bool _hasVisibleSender(int userId) {
    _ensureMessageIndexes();
    final bucket = _messagesBySenderId[userId];
    if (bucket == null) return false;
    for (final message in bucket) {
      if (message.isOutgoing && !message.senderIsChat) continue;
      if (message.isService) continue;
      return true;
    }
    return false;
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
      isDeleted: TDParse.isDeletedUser(user),
      accentColorId: user.integer('accent_color_id') ?? -1,
      emojiStatusId: TDParse.emojiStatusCustomEmojiId(user.obj('emoji_status')),
    );
  }

  /// Fills `forwardOrigin` for forwarded messages whose origin is a user or
  /// chat we can name (hidden-user names already arrive inline).
  void _resolveForwardsIfNeeded(List<ChatMessage> batch) {
    _resolveViaBotsIfNeeded(batch);
    for (final m in batch) {
      if (m.forwardOrigin != null && m.forwardOrigin!.isNotEmpty) continue;
      final uid = m.forwardFromUserId;
      final cid = m.forwardFromChatId;
      if (uid != null) {
        final cached = _senderCache[uid]?.name ?? _forwardUserNames[uid];
        if (cached != null) {
          m.forwardOrigin = cached;
          continue;
        }
        final waiting = _pendingForwardUsers[uid];
        if (waiting != null) {
          waiting.add(m);
          continue;
        }
        _pendingForwardUsers[uid] = <ChatMessage>[m];
        _resolveForwardName(userId: uid);
      } else if (cid != null) {
        final cached = _forwardChatTitles[cid];
        if (cached != null) {
          m.forwardOrigin = cached;
          continue;
        }
        final waiting = _pendingForwardChats[cid];
        if (waiting != null) {
          waiting.add(m);
          continue;
        }
        _pendingForwardChats[cid] = <ChatMessage>[m];
        _resolveForwardName(chatId: cid);
      }
    }
  }

  Future<void> _resolveForwardName({int? userId, int? chatId}) async {
    String? name;
    try {
      if (userId != null) {
        final user = await _client.query({
          '@type': 'getUser',
          'user_id': userId,
        });
        name = TDParse.userName(user);
      } else if (chatId != null) {
        final chat = await _client.query({
          '@type': 'getChat',
          'chat_id': chatId,
        });
        name = chat.str('title');
      }
    } catch (_) {}
    final List<ChatMessage>? waiting;
    if (userId != null) {
      waiting = _pendingForwardUsers.remove(userId);
    } else if (chatId != null) {
      waiting = _pendingForwardChats.remove(chatId);
    } else {
      waiting = null;
    }
    // A failed lookup is not remembered, so a later page retries it exactly as
    // it used to.
    if (name == null || name.isEmpty || waiting == null) return;
    if (userId != null) {
      _forwardUserNames[userId] = name;
    } else if (chatId != null) {
      _forwardChatTitles[chatId] = name;
    }
    for (final message in waiting) {
      message.forwardOrigin = name;
    }
    _bumpMaterializedMessageRevisions(waiting.map((m) => m.id));
    _scheduleCoalescedNotify();
  }

  void _resolveViaBotsIfNeeded(List<ChatMessage> batch) {
    for (final m in batch) {
      if (m.isContentRestricted) continue;
      if (m.viaBotUsername != null && m.viaBotUsername!.isNotEmpty) continue;
      final botUserId = m.viaBotUserId;
      if (botUserId == null || botUserId <= 0) continue;
      final cached = _viaBotUsernames[botUserId];
      if (cached != null) {
        m.viaBotUsername = cached;
        continue;
      }
      final waiting = _pendingViaBotUsers[botUserId];
      if (waiting != null) {
        waiting.add(m);
        continue;
      }
      _pendingViaBotUsers[botUserId] = <ChatMessage>[m];
      unawaited(_resolveViaBotUsername(botUserId));
    }
  }

  Future<void> _resolveViaBotUsername(int botUserId) async {
    String? label;
    try {
      final user = await _client.query({
        '@type': 'getUser',
        'user_id': botUserId,
      });
      final username = ChatViewModel._primaryUsername(user);
      if (username.isNotEmpty) {
        label = '@$username';
      } else {
        final name = TDParse.userName(user).trim();
        if (name.isNotEmpty) label = name;
      }
    } catch (_) {}
    final waiting = _pendingViaBotUsers.remove(botUserId);
    if (label == null || label.isEmpty || waiting == null) return;
    _viaBotUsernames[botUserId] = label;
    final updatedIds = <int>{};
    for (final m in waiting) {
      final refs = _messageRefs(m.id);
      final targets = refs.isEmpty ? <ChatMessage>[m] : refs;
      for (final message in targets) {
        if (message.isContentRestricted || message.viaBotUserId != botUserId) {
          continue;
        }
        message.viaBotUsername = label;
        updatedIds.add(message.id);
      }
    }
    if (updatedIds.isEmpty) return;
    _bumpMaterializedMessageRevisions(updatedIds);
    _scheduleCoalescedNotify();
  }

  void _resolveServiceUsersIfNeeded(List<ChatMessage> batch) {
    for (final message in batch) {
      if (!message.isService) continue;
      switch (message.contentType) {
        case 'messageChatAddedToCommunity':
        case 'messageChatRemovedFromCommunity':
          _resolveCommunityServiceText(message);
        case 'messageChatAddMembers':
        case 'messageChatJoinByLink':
        case 'messageChatJoinByRequest':
          if (message.serviceUserIds.isNotEmpty) {
            _resolveJoinServiceText(message);
          }
        case 'messageChatBoost':
          if (message.serviceUserIds.isNotEmpty) {
            _resolveBoostServiceText(message);
          }
        case 'messageChatDeleteMember':
          if (message.serviceUserIds.isNotEmpty) {
            _resolveDeleteMemberServiceText(message);
          }
      }
    }
  }

  Future<void> _resolveCommunityServiceText(ChatMessage message) async {
    _ensureMessageIndexes();
    final target = _messagesById[message.id] ?? message;
    var changed = _hydrateCommunityPreviewFromCache(target);
    var actorName = '';
    if (message.serviceUserIds.isNotEmpty) {
      final userId = message.serviceUserIds.first;
      try {
        final user =
            TdUserIndex.shared.userFor(_client.activeSlot, userId) ??
            await _client.query({'@type': 'getUser', 'user_id': userId});
        actorName = TDParse.userName(user);
      } catch (_) {}
    }
    final text = resolvedCommunityServiceText(
      contentType: message.contentType ?? '',
      actorName: actorName,
      communityName: target.communityPreview?.name ?? '',
      isChannel: isChannel,
    );
    if (target.text != text) {
      target.text = text;
      changed = true;
    }
    if (changed) _scheduleCoalescedNotify();
  }

  bool _hydrateCommunityPreviewFromCache(ChatMessage message) {
    final preview = message.communityPreview;
    if (preview == null || preview.id == 0) return false;
    for (final update in _client.latestCommunityUpdates) {
      final community = update.obj('community');
      if (community?.int64('id') != preview.id) continue;
      var changed = false;
      final name = community?.str('name') ?? community?.str('title') ?? '';
      if (preview.name.isEmpty && name.isNotEmpty) {
        preview.name = name;
        changed = true;
      }
      final photo = TDParse.smallPhoto(community?.obj('photo'));
      if (preview.photo == null && photo != null) {
        preview.photo = photo;
        changed = true;
      }
      return changed;
    }
    return false;
  }

  Future<void> _resolveJoinServiceText(ChatMessage message) async {
    final names = <String>[];
    for (final userId in message.serviceUserIds.take(5)) {
      try {
        final user =
            TdUserIndex.shared.userFor(_client.activeSlot, userId) ??
            await _client.query({'@type': 'getUser', 'user_id': userId});
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
    final text = AppStrings.t(
      isChannel
          ? AppStringKeys.chatUsersJoinedChannel
          : AppStringKeys.chatUsersJoinedGroup,
      {
        'value1': names.join(AppStrings.t(AppStringKeys.listSeparator)),
        'value2': suffix,
      },
    );
    _ensureMessageIndexes();
    final target = _messagesById[message.id];
    if (target == null || target.text == text) return;
    target.text = text;
    _scheduleCoalescedNotify();
  }

  Future<void> _resolveBoostServiceText(ChatMessage message) async {
    if (message.serviceUserIds.isEmpty) return;
    final userId = message.serviceUserIds.first;
    try {
      final user =
          TdUserIndex.shared.userFor(_client.activeSlot, userId) ??
          await _client.query({'@type': 'getUser', 'user_id': userId});
      final name = TDParse.userName(user);
      if (name.isEmpty) return;
      final text = AppStrings.t(
        isChannel
            ? AppStringKeys.chatUserBoostedChannel
            : AppStringKeys.chatUserBoostedGroup,
        {'value1': name},
      );
      _ensureMessageIndexes();
      final target = _messagesById[message.id];
      if (target == null || target.text == text) return;
      target.text = text;
      _scheduleCoalescedNotify();
    } catch (_) {}
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
      final text = AppStrings.t(
        isChannel
            ? AppStringKeys.chatUserLeftChannel
            : AppStringKeys.chatUserLeftGroup,
        {'value1': name},
      );
      _ensureMessageIndexes();
      final target = _messagesById[message.id];
      if (target == null || target.text == text) return;
      target.text = text;
      _scheduleCoalescedNotify();
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
                AppStrings.t(AppStringKeys.chatInfoGroupMembers),
            TDParse.smallPhoto(chat.obj('photo')),
            MemberRole.channel,
            null,
          );
        } catch (_) {
          info = _SenderInfo(
            AppStrings.t(AppStringKeys.chatInfoGroupMembers),
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

  void _setTranslationLoading(int messageId, bool loading) {
    final target = _messageRefs(messageId);
    if (target.isEmpty) return;
    for (final message in target) {
      message.isTranslating = loading;
    }
    _scheduleCoalescedNotify();
  }

  /// Parses one TDLib message with this chat's group/channel label context.
  ChatMessage? _parseMessage(Map<String, dynamic> raw) =>
      TDParse.message(raw, isChannel: isChannel);

  /// Re-labels service messages that were parsed before [isChannel] resolved.
  /// A channel opened from a cold cache can hydrate its first history page in
  /// parallel with getChat/getSupergroup; those banners must not keep group
  /// wording once the type is known.
  void _relabelChannelServiceMessages() {
    if (!isChannel) return;
    final seen = <ChatMessage>{};
    for (final message in [..._allMessages, ...messages, ...pinnedMessages]) {
      if (!seen.add(message)) continue;
      final text = TDParse.channelServiceText(message);
      if (text != null) message.text = text;
    }
    // Join/leave/boost banners carry an actor name resolved asynchronously.
    // Re-run that resolution so a banner personalised before the channel type
    // resolved is rebuilt with channel wording instead of being left as-is.
    _resolveServiceUsersIfNeeded([
      for (final message in _allMessages)
        if (message.isService) message,
    ]);
  }

  /// Fills a reply anchor from the mirror when the quoted message was
  /// deleted (Telegram §1.4, self-build gated): the kept copy's text,
  /// sender and date become the quote-style preview. Only used when the
  /// live transcript does not have the target — a live message always wins.
  bool _applyMirrorReply(ChatMessage m, int replyId, int replyChatId) {
    if (!allowTelegramTosViolations) return false;
    final store = historyStoreOverride ?? MessageHistoryStore.shared;
    final accountUserId = _accountUserId;
    if (accountUserId == null) return false;
    final entry = store.entryFor(accountUserId, replyChatId, replyId);
    if (entry == null) return false;
    // Only the plain fallback preview takes the mirror text — a real quote
    // (replyToQuote, an explicit quote of part of the original) keeps its
    // own stored excerpt, which stays more truthful than the whole copy.
    if (m.replyToQuote != null) return true;
    final body = entry.text.trim().isNotEmpty
        ? entry.text.trim()
        : ChatViewModel.localizedHistoryKindLabelStub(entry.kindKey);
    m.replyToPreview = body;
    m.replyToDate = entry.date;
    if (entry.senderId != 0) {
      m.replyToSender = _senderCache[entry.senderId]?.name ?? '';
      if ((m.replyToSender ?? '').isEmpty && entry.senderId > 0) {
        unawaited(_resolveQuotedSender(m, entry.senderId));
      }
    } else {
      m.replyToSender = isGroup ? '' : peerTitle;
    }
    return true;
  }

  /// Deleted mirror entries of this chat become in-place ghost bubbles; the
  /// ids not present in the transcript are the ghosts to fold in. A topic
  /// transcript folds only its own topic's ghosts.
  List<MessageHistoryEntry> _ghostEntriesForTranscript() {
    if (!_ghostsEnabled) return const [];
    final accountUserId = _accountUserId;
    if (accountUserId == null) return const [];
    return (historyStoreOverride ?? MessageHistoryStore.shared)
        .deletedEntriesFor(accountUserId, chatId, topicId: forumTopicId ?? 0);
  }

  /// Folds ghost bubbles into the published transcript after every rebuild.
  /// Ghosts are render-only: they join `messages` (sorted by their original
  /// message id, so they sit where the message used to be) but never enter
  /// `_allMessages` or any id index — the id no longer exists on Telegram's
  /// side, so read states, mentions and merges must not see it.
  void _foldGhostsIntoTranscript() {
    if (!_ghostsEnabled) return;
    final entries = _ghostEntriesForTranscript();
    final inTranscript = _allMessages.map((m) => m.id).toSet();
    final accountUserId = _accountUserId;
    final ghosts = <ChatMessage>[];
    for (final entry in entries) {
      if (inTranscript.contains(entry.messageId)) continue;
      ghosts.add(_ghostChatMessageFor(entry, accountUserId));
    }
    if (ghosts.isEmpty) return;
    messages = mergeChatMessages(messages, ghosts);
  }

  /// One ghost as a transcript [ChatMessage]. `contentType` marks the ghost
  /// for the bubble layer; media ghosts carry their snapshot through
  /// [ChatMessage.mirrorEntry].
  ChatMessage _ghostChatMessageFor(
    MessageHistoryEntry entry,
    int? accountUserId,
  ) {
    final senderId = entry.senderId == 0 ? null : entry.senderId;
    final isOutgoing = accountUserId != null && entry.senderId == accountUserId;
    return ChatMessage(
      id: entry.messageId,
      isOutgoing: isOutgoing,
      // Media-only kept copies have no text; the localized kind label keeps
      // the ghost bubble from rendering as an empty shell.
      text: entry.text.trim().isNotEmpty
          ? entry.text
          : ChatViewModel.localizedHistoryKindLabelStub(entry.kindKey),
      date: entry.date,
      chatId: chatId,
      senderId: senderId,
      contentType: 'mithkaGhost',
      // Attribution: a group ghost renders the sender header like any kept
      // message would; the fold re-runs on every rebuild, so a cached name
      // lands without waiting for another pass.
      senderName: isOutgoing
          ? (meName.trim().isNotEmpty ? meName : null)
          : _senderCache[senderId]?.name,
    )..mirrorEntry = entry;
  }

  void debugRebuildTranscriptForTesting() => _applyKeywordFilter();
  void debugMergeMessagesForTesting(List<ChatMessage> incoming) {
    _merge(incoming);
    _resolveRepliesIfNeeded(incoming);
  }

  Iterable<int> debugAllMessageIdsForTesting() => _allMessages.map((m) => m.id);

  /// Settings and mirror flips re-fold the transcript: turning ghosts off
  /// must remove them, a new deletion must insert one.
  void _onGhostSourceChanged() {
    if (_isDisposed) return;
    _applyKeywordFilter();
  }
}
