part of 'chat_view.dart';

extension _ChatViewTranscript on _ChatViewState {
  bool _needsUnreadDivider(int index, {List<ChatMessage>? messages}) {
    messages ??= _vm.messages;
    if (index < 0 || index >= messages.length) return false;
    final m = messages[index];
    return isCapturedUnreadDividerMessage(
      entryUnreadCount: _entryUnreadCount,
      firstUnreadMessageId: _entryFirstUnreadMessageId,
      messageId: m.id,
      isIncoming: !m.isOutgoing,
      isService: m.isService,
      lastReadInboxId: _entryLastReadInboxId,
      latestMessageId: _entryLatestMessageId,
    );
  }

  void _beginSwipeReply(ChatMessage message) {
    _vm.setReply(message);
    _vm.requestComposerFocus();
  }

  bool? _shortFirstContactHistoryFitsViewport() {
    if (_vm.firstContactInfo == null || _vm.messages.isEmpty) return false;
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) {
      return null;
    }
    if (_transcriptViewportClaimedByUser ||
        _hasTranscriptPointerDown ||
        _autoScrollPolicy.preservesViewport ||
        _maintainSessionScrollAnchor ||
        _scrollTargetId != null) {
      return null;
    }
    if (_vm.anchoredHistory ||
        (_vm.hasOlderHistory && !_olderHistoryExhaustedHint)) {
      return false;
    }
    if (_scroll.position.maxScrollExtent > 24) return false;

    final entries = _transcriptCache;
    final viewportObject = _transcriptViewportKey.currentContext
        ?.findRenderObject();
    final cardObject = _firstContactLayoutKey.currentContext
        ?.findRenderObject();
    final latestObject = entries == null || entries.isEmpty
        ? null
        : _entryVisibilityKeys[entries.last.last.id]?.currentContext
              ?.findRenderObject();
    if (viewportObject is! RenderBox ||
        !viewportObject.attached ||
        cardObject is! RenderBox ||
        !cardObject.attached ||
        latestObject is! RenderBox ||
        !latestObject.attached) {
      return null;
    }

    final cardTop = cardObject.localToGlobal(Offset.zero).dy;
    final latestBottom = latestObject
        .localToGlobal(Offset(0, latestObject.size.height))
        .dy;
    if (latestBottom < cardTop) return null;
    return firstContactHistoryFitsViewport(
      cardTop: cardTop,
      latestBottom: latestBottom,
      viewportExtent: viewportObject.size.height,
    );
  }

  bool _positionShortFirstContactHistoryIfItFits({
    required bool requireAtLatest,
  }) {
    final fits = _shortFirstContactHistoryFitsViewport();
    if (fits != true) {
      if (fits == false) {
        _showingFullyVisibleFirstContactHistory = false;
      }
      return false;
    }
    if (requireAtLatest &&
        !_showingFullyVisibleFirstContactHistory &&
        !isNearLatest(_scroll.position, threshold: 1)) {
      return false;
    }
    _showingFullyVisibleFirstContactHistory = true;
    final target = _scroll.position.minScrollExtent;
    if ((_scroll.position.pixels - target).abs() > 0.5) {
      _scroll.jumpTo(target);
    }
    return true;
  }

  void _scheduleShortFirstContactReveal() {
    if (_shortFirstContactRevealScheduled) return;
    _shortFirstContactRevealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shortFirstContactRevealScheduled = false;
      if (!mounted) return;
      final wasShowing = _showingFullyVisibleFirstContactHistory;
      final positioned = _positionShortFirstContactHistoryIfItFits(
        requireAtLatest: !wasShowing,
      );
      if (wasShowing &&
          !positioned &&
          !_showingFullyVisibleFirstContactHistory &&
          !_hasTranscriptPointerDown &&
          !_transcriptViewportClaimedByUser &&
          !_autoScrollPolicy.preservesViewport) {
        _scheduleScrollToBottom(animated: false);
      }
    });
  }

  Future<void> _openCommunityPreview(MessageCommunityPreview preview) async {
    if (preview.id == 0) return;
    CommunitySummary? summary;
    for (final update in TdClient.shared.latestCommunityUpdates) {
      final raw = update.obj('community');
      if (raw?.int64('id') != preview.id) continue;
      summary = CommunitySummary.fromTd(raw!);
      break;
    }
    summary ??= CommunitySummary(
      id: preview.id,
      name: preview.name,
      haveAccess: true,
      isAdministrator: false,
      canEditChatList: false,
      photo: preview.photo,
    );
    if (summary.name.isEmpty && preview.name.isNotEmpty) {
      summary.name = preview.name;
    }
    summary.photo ??= preview.photo;

    final chats = <ChatSummary>[];
    final viewableChats = <ChatSummary>[];
    try {
      final fullInfo = await TdClient.shared.query(
        communityFullInfoRequest(preview.id),
      );
      for (final peer in communityCatalogEntries(fullInfo)) {
        final chatId = peer.int64('chat_id');
        if (chatId == null) continue;
        try {
          final chat = TDParse.chat(
            await TdClient.shared.query({
              '@type': 'getChat',
              'chat_id': chatId,
            }),
          );
          if (chat == null) continue;
          if (peer.boolean('can_view_history') == true && chat.order == 0) {
            viewableChats.add(chat);
          } else {
            chats.add(chat);
          }
        } catch (_) {
          // A community peer can disappear while its directory is loading.
        }
      }
    } catch (_) {
      // Bot API accounts expose the event's id and name but no community
      // catalogue endpoint, so their preview opens with the available header.
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      AppPageRoute<void>(
        pageBuilder: (_, _, _) => CommunityView(
          community: summary!,
          chats: chats,
          viewableChats: viewableChats,
          onCollapsedChanged: (collapsed) => summary!.collapsed = collapsed,
        ),
      ),
    );
  }

  TranscriptPivotPartition<_TranscriptEntry> _partitionTranscript(
    List<_TranscriptEntry> entries,
  ) {
    if (entries.isEmpty) {
      return const TranscriptPivotPartition<_TranscriptEntry>(
        beforePivot: [],
        pivotAndAfter: [],
      );
    }
    final pivot = resolveTranscriptPivot<_TranscriptEntry>(
      currentPivot: _transcriptPivot,
      initialWindowLoaded: _vm.initialLoaded,
      entries: entries,
      firstOrderIdOf: (entry) => _transcriptOrderId(entry.first),
      estimatedExtentOf: _estimatedEntryExtent,
      viewportExtent: _scroll.hasClients
          ? _scroll.position.viewportDimension
          : MediaQuery.sizeOf(context).height,
    );
    if (pivot == null) {
      return TranscriptPivotPartition<_TranscriptEntry>(
        beforePivot: const [],
        pivotAndAfter: List<_TranscriptEntry>.unmodifiable(entries),
      );
    }
    final result = partitionTranscriptAtPivot<_TranscriptEntry>(
      entries: entries,
      pivot: pivot,
      messageIdsOf: (entry) => entry.messages.map(_transcriptOrderId),
    );
    _transcriptPivot = pivot;
    return result;
  }

  void _resetTranscriptPivot() {
    _transcriptPivot = null;
    _transcriptPivotFrozen = false;
  }

  void _scheduleTranscriptPivotFreeze() {
    if (_transcriptPivotFreezeScheduled ||
        _transcriptPivotFrozen ||
        !_initialTranscriptReady ||
        _maintainSessionScrollAnchor ||
        _transcriptPivot == null ||
        _transcriptPivot?.cutoffMessageId ==
            _ChatViewState._pendingTranscriptOrderId) {
      return;
    }
    _transcriptPivotFreezeScheduled = true;
    final scheduledPivot = _transcriptPivot;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _transcriptPivotFreezeScheduled = false;
      if (!mounted ||
          _transcriptPivotFrozen ||
          _maintainSessionScrollAnchor ||
          !_scroll.hasClients) {
        return;
      }
      if (!identical(scheduledPivot, _transcriptPivot)) {
        _scheduleTranscriptPivotFreeze();
        return;
      }
      if (shouldFreezeTranscriptPivot(
        latestArmIsShort: _isTranscriptShort(),
        canLoadOlder: _vm.canLoadOlder,
      )) {
        _transcriptPivotFrozen = true;
      }
    });
  }

  List<_TranscriptEntry> _transcriptEntries(bool groupImages) {
    final messages = _vm.messages;
    // blockedByUser is only written inside _applyKeywordFilter, which always
    // reassigns `messages` first — so the identity check below already covers
    // blocked-state changes. (A previous per-build Object.hashAll signature
    // over every message re-verified this at O(n) per frame; keep the flag
    // writes behind _applyKeywordFilter or the memo goes stale.)
    final cached = _transcriptCache;
    if (cached != null &&
        identical(_transcriptCacheMessages, messages) &&
        _transcriptCacheGrouped == groupImages &&
        _transcriptCacheEntryUnreadCount == _entryUnreadCount &&
        _transcriptCacheEntryLastReadInboxId == _entryLastReadInboxId &&
        _transcriptCacheEntryLatestMessageId == _entryLatestMessageId &&
        _transcriptCacheEntryFirstUnreadMessageId ==
            _entryFirstUnreadMessageId) {
      return cached;
    }
    final entries = groupImages ? _groupedTranscript() : _plainTranscript();
    _transcriptCache = entries;
    _transcriptCacheMessages = messages;
    _transcriptCacheGrouped = groupImages;
    _transcriptCacheEntryUnreadCount = _entryUnreadCount;
    _transcriptCacheEntryLastReadInboxId = _entryLastReadInboxId;
    _transcriptCacheEntryLatestMessageId = _entryLatestMessageId;
    _transcriptCacheEntryFirstUnreadMessageId = _entryFirstUnreadMessageId;
    // Read in place rather than copied: nothing mutates the map between here
    // and the swap below, and the copy was n-sized on every incoming message.
    final previousVisibilityKeys = _entryVisibilityKeys;
    final nextVisibilityKeys = <int, GlobalKey>{};
    final usedVisibilityKeys = <GlobalKey>{};
    for (final entry in entries) {
      GlobalKey? visibilityKey;
      for (final message in entry.messages.reversed) {
        final candidate = previousVisibilityKeys[message.id];
        if (candidate != null && usedVisibilityKeys.add(candidate)) {
          visibilityKey = candidate;
          break;
        }
      }
      visibilityKey ??= GlobalKey();
      usedVisibilityKeys.add(visibilityKey);
      for (final message in entry.messages) {
        nextVisibilityKeys[message.id] = visibilityKey;
      }
    }
    _entryVisibilityKeys = nextVisibilityKeys;
    _trackedTranscriptEntries = {
      for (final entry in entries) entry.last.id: entry,
    };
    return entries;
  }

  void _handleDesktopQuoteChanged(
    ChatMessage message,
    MessageTextQuote? quote,
  ) {
    if (!mounted) return;
    if (quote != null) {
      _desktopQuoteMessageId = message.id;
      _desktopQuote = quote;
    } else if (_desktopQuoteMessageId == message.id) {
      _desktopQuoteMessageId = null;
      _desktopQuote = null;
    }
  }

  void _showActionMenuForMessage(
    ChatMessage message,
    Rect? rect, [
    MessageActionSource source = MessageActionSource.normal,
  ]) {
    EmojiStore.shared.loadIfNeeded();
    final reactionGeneration = ++_actionReactionAvailabilityGeneration;
    final propertiesGeneration = ++_actionPropertiesGeneration;
    final overlayBox =
        _actionOverlayKey.currentContext?.findRenderObject() as RenderBox?;
    final platform = Theme.of(context).platform;
    final desktop = isDesktopTargetPlatform(platform);
    final usePointer =
        desktop ||
        (!desktop &&
            context.read<ThemeController>().mobileMessageActionMenuStyle ==
                MobileMessageActionMenuStyle.dropdown);
    final globalAnchor = MessageActionMenu.anchorRectForPresentation(
      targetRect: rect,
      pointer: _lastActionPointerGlobalPosition,
      usePointer: usePointer,
    );
    _lastActionPointerGlobalPosition = null;
    final overlayRect = globalAnchor != null && overlayBox?.hasSize == true
        ? MessageActionMenu.rectInOverlay(
            globalAnchor,
            globalToLocal: overlayBox!.globalToLocal,
          )
        : globalAnchor;
    final enableMobileTextSelection =
        !isDesktopTargetPlatform(platform) && !_vm.hasProtectedContent;
    final oldSelectionState = _mobileTextSelectionAreaKey?.currentState;
    final reactionMessageId = _reactionMessageFor(message).id;
    _updateState(() {
      _actionTarget = message;
      _actionReactionMessageId = reactionMessageId;
      // Keep the quote while the menu takes focus and clears Flutter's live
      // selection. Each newly opened menu replaces this snapshot.
      _actionQuote =
          desktop && _vm.canQuoteText && _desktopQuoteMessageId == message.id
          ? _desktopQuote
          : null;
      _actionRect = overlayRect;
      // The HUD's enter grows out of the pressed message and its exit
      // collapses back into it.
      _actionAnchor = overlayRect?.center;
      _mobileTextSelectionAreaKey = enableMobileTextSelection
          ? GlobalKey<SelectionAreaState>()
          : null;
      _mobileTextSelectionMessageId = enableMobileTextSelection
          ? message.id
          : null;
      _mobileTextSelectionActive = false;
      _actionSource = source;
      _reactionExpanded = false;
      _reactionTab = 'standard';
      _actionReactionAvailability = null;
      _actionMessageLinkAvailable = null;
      _actionCanReply = null;
    });
    oldSelectionState?.selectableRegion.clearSelection();
    if (!message.isCall) {
      unawaited(
        _loadActionReactionAvailability(reactionMessageId, reactionGeneration),
      );
    }
    unawaited(_loadActionAvailability(message.id, propertiesGeneration));
  }

  Future<void> _loadActionAvailability(int messageId, int generation) async {
    bool? canGetLink;
    bool? canBeReplied;
    try {
      final availability = await _vm.messageActionAvailability(messageId);
      canGetLink = availability.canGetLink;
      canBeReplied = availability.canBeReplied;
    } catch (_) {
      canGetLink = false; // Fail closed — no query answer, no action.
      canBeReplied = false;
    }
    if (!mounted ||
        generation != _actionPropertiesGeneration ||
        _actionTarget?.id != messageId) {
      return;
    }
    _updateState(() {
      _actionMessageLinkAvailable = canGetLink;
      _actionCanReply = canBeReplied;
    });
  }

  Future<void> _loadActionReactionAvailability(
    int messageId,
    int generation,
  ) async {
    MessageReactionAvailability? availability;
    try {
      availability = await _vm.messageReactionAvailability(messageId);
    } catch (_) {
      // Fail closed. Offering the global defaults after a failed availability
      // query recreates the exact MESSAGE_REACTION_INVALID bug this gate fixes.
    }
    if (!mounted ||
        !messageReactionAvailabilityResultIsCurrent(
          requestGeneration: generation,
          currentGeneration: _actionReactionAvailabilityGeneration,
          messageId: messageId,
          targetMessageId: _actionTarget == null
              ? null
              : _actionReactionMessageId,
        )) {
      return;
    }
    _updateState(() => _actionReactionAvailability = availability);
  }

  ChatMessage _reactionMessageFor(ChatMessage message) {
    final kind = chatMediaAlbumKind(message);
    if (message.mediaAlbumId == 0 || kind == null) return message;
    final album = _vm.messages
        .where(
          (m) =>
              m.mediaAlbumId == message.mediaAlbumId &&
              chatMediaAlbumKind(m) == kind,
        )
        .toList(growable: false);
    if (album.length < 2) return message;
    return selectMediaAlbumInteractionOwner(album);
  }

  void _clearMobileTextSelectionState() {
    final selectionState = _mobileTextSelectionAreaKey?.currentState;
    _mobileTextSelectionAreaKey = null;
    _mobileTextSelectionMessageId = null;
    _mobileTextSelectionActive = false;
    selectionState?.selectableRegion.clearSelection();
  }

  void _syncProtectedContentSelectionState() {
    final selectionState = _mobileTextSelectionAreaKey?.currentState;
    if (!protectedContentRequiresMobileSelectionClear(
      hasProtectedContent: _vm.hasProtectedContent,
      hasSelectionKey: _mobileTextSelectionAreaKey != null,
    )) {
      return;
    }
    _mobileTextSelectionAreaKey = null;
    _mobileTextSelectionMessageId = null;
    _mobileTextSelectionActive = false;
    _actionTarget = null;
    _actionRect = null;
    _lastActionPointerGlobalPosition = null;
    _actionSource = MessageActionSource.normal;
    _reactionExpanded = false;
    selectionState?.selectableRegion.clearSelection();
  }

  void _handleMobileTextSelectionChanged(SelectedContent? content) {
    if (content != null && content.plainText.isNotEmpty) {
      if (_actionTarget != null) {
        _updateState(() {
          _mobileTextSelectionActive = true;
          _actionTarget = null;
          _actionRect = null;
          _lastActionPointerGlobalPosition = null;
          _actionSource = MessageActionSource.normal;
          _reactionExpanded = false;
        });
      } else {
        _mobileTextSelectionActive = true;
      }
      return;
    }
    if (!_mobileTextSelectionActive) return;
    _mobileTextSelectionActive = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _actionTarget != null) return;
      if (_mobileTextSelectionMessageId != null) {
        _updateState(() => _mobileTextSelectionMessageId = null);
      }
    });
  }

  void _handleMobileTextSelectionDisposed(
    int messageId,
    GlobalKey<SelectionAreaState> selectionAreaKey,
  ) {
    if (!mounted ||
        _mobileTextSelectionMessageId != messageId ||
        !identical(_mobileTextSelectionAreaKey, selectionAreaKey)) {
      return;
    }
    _updateState(() {
      _mobileTextSelectionAreaKey = null;
      _mobileTextSelectionMessageId = null;
      _mobileTextSelectionActive = false;
    });
  }

  void _handleChatPointerDown(PointerDownEvent event) {
    _lastActionPointerGlobalPosition = event.position;
    final selectionAreaKey = _mobileTextSelectionAreaKey;
    if (!_mobileTextSelectionActive ||
        selectionAreaKey == null ||
        selectionAreaContainsGlobalTextPosition(
          selectionAreaKey: selectionAreaKey,
          globalPosition: event.position,
        )) {
      return;
    }
    selectionAreaKey.currentState?.selectableRegion.clearSelection();
  }

  List<_TranscriptEntry> _plainTranscript() {
    final messages = _vm.messages;
    final entries = <_TranscriptEntry>[];
    var i = 0;
    while (i < messages.length) {
      final first = messages[i];
      if (!first.blockedByUser) {
        entries.add(_TranscriptEntry([first], i));
        i++;
        continue;
      }
      final run = <ChatMessage>[first];
      final j = blockedMessageRunEnd(
        messages,
        i,
        startsNewSection: (index) =>
            _startsTranscriptPivotSection(messages, index) ||
            _needsSeparator(index, messages: messages) ||
            _needsUnreadDivider(index, messages: messages) ||
            _needsTopicSeparator(index, messages: messages),
      );
      run.addAll(messages.sublist(i + 1, j));
      entries.add(_TranscriptEntry(run, i));
      i = j;
    }
    return entries;
  }

  List<_TranscriptEntry> _groupedTranscript() {
    final messages = _vm.messages;
    final entries = <_TranscriptEntry>[];
    var i = 0;
    while (i < messages.length) {
      final first = messages[i];
      if (first.blockedByUser) {
        final run = <ChatMessage>[first];
        final j = blockedMessageRunEnd(
          messages,
          i,
          startsNewSection: (index) =>
              _startsTranscriptPivotSection(messages, index) ||
              _needsSeparator(index, messages: messages) ||
              _needsUnreadDivider(index, messages: messages) ||
              _needsTopicSeparator(index, messages: messages),
        );
        run.addAll(messages.sublist(i + 1, j));
        entries.add(_TranscriptEntry(run, i));
        i = j;
        continue;
      }
      if (chatMediaAlbumKind(first) == null || first.mediaAlbumId == 0) {
        entries.add(_TranscriptEntry([first], i));
        i++;
        continue;
      }

      final group = <ChatMessage>[first];
      var j = i + 1;
      while (j < messages.length) {
        final next = messages[j];
        if (_startsTranscriptPivotSection(messages, j) ||
            _needsSeparator(j, messages: messages) ||
            _needsUnreadDivider(j, messages: messages) ||
            _needsTopicSeparator(j, messages: messages)) {
          break;
        }
        if (!areMessagesInSameMediaAlbum(group.last, next)) break;
        group.add(next);
        j++;
      }

      entries.add(_TranscriptEntry(group, i));
      i = j;
    }
    return entries;
  }

  bool _startsTranscriptPivotSection(List<ChatMessage> messages, int index) {
    if (index <= 0 || index >= messages.length) return false;
    return startsTranscriptPivotSection(
      pivot: _transcriptPivot,
      previousMessageId: _transcriptOrderId(messages[index - 1]),
      currentMessageId: _transcriptOrderId(messages[index]),
    );
  }

  ChatMessage _mediaAlbumInteractionOwner(List<ChatMessage> group) {
    return selectMediaAlbumInteractionOwner(group);
  }

  void _react(String emoji) {
    final target = _actionTarget == null
        ? null
        : _actionReactionMessageId ?? _actionTarget!.id;
    _updateState(() {
      _actionTarget = null;
      _actionRect = null;
      _clearMobileTextSelectionState();
      _actionSource = MessageActionSource.normal;
      _reactionExpanded = false;
    });
    if (target != null) {
      unawaited(_sendReaction(() => _vm.addReaction(target, emoji)));
    }
  }

  void _reactQuick(QuickReactionChoice reaction) {
    if (reaction.isCustom) {
      _reactCustom(reaction.customEmojiId);
    } else {
      _react(reaction.emoji);
    }
  }

  void _reactCustom(int customEmojiId) {
    final target = _actionTarget == null
        ? null
        : _actionReactionMessageId ?? _actionTarget!.id;
    _updateState(() {
      _actionTarget = null;
      _actionRect = null;
      _clearMobileTextSelectionState();
      _actionSource = MessageActionSource.normal;
      _reactionExpanded = false;
    });
    if (target != null) {
      unawaited(
        _sendReaction(() => _vm.addCustomReaction(target, customEmojiId)),
      );
    }
  }

  Future<void> _sendReaction(Future<void> Function() send) async {
    try {
      await send();
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.topicPostContentActionFailed);
      }
    }
  }

  Future<void> _quoteMessageText(
    ChatMessage message, {
    MessageTextQuote? selectedQuote,
  }) async {
    if (!_vm.canQuoteText || !canQuoteMessageText(message)) return;
    final limit = await _vm.messageQuoteLengthLimit();
    if (!mounted || !_vm.canQuoteText) return;
    // Desktop quotes are chosen directly in the transcript, not in a second
    // window. Touch keeps the explicit quote-selection flow.
    if (selectedQuote == null &&
        isDesktopTargetPlatform(Theme.of(context).platform)) {
      return;
    }
    final quote =
        selectedQuote ??
        await showGeneralDialog<MessageTextQuote>(
          context: context,
          barrierDismissible: true,
          barrierLabel: AppStringKeys.confirmCancel.l10n(context),
          barrierColor: Colors.black.withValues(alpha: 0.52),
          transitionDuration: AppMotion.duration(context, AppMotion.responsive),
          transitionBuilder: AppMotion.dialogTransition,
          pageBuilder: (_, _, _) =>
              MessageQuoteSelectionDialog(message: message, maxLength: limit),
        );
    if (!mounted || quote == null || !_vm.canQuoteText) return;
    final current = _vm.messages.where((m) => m.id == message.id).firstOrNull;
    if (current == null) return;
    final validated = quoteMessageRange(
      current,
      start: quote.position,
      end: quote.position + quote.text.length,
      maxLength: limit,
    );
    if (validated == null || validated.text != quote.text) {
      showToast(context, AppStringKeys.topicPostContentActionFailed);
      return;
    }
    _vm.setReply(current, quote: validated);
  }

  Future<void> _toggleMessageReaction(
    ChatMessage message,
    MessageReaction reaction,
  ) => _sendReaction(() => _vm.toggleReaction(message, reaction));

  void _dismissActionOverlay() {
    if (_actionTarget == null) return;
    _updateState(() {
      _actionTarget = null;
      _actionRect = null;
      _lastActionPointerGlobalPosition = null;
      _clearMobileTextSelectionState();
      _actionSource = MessageActionSource.normal;
      _reactionExpanded = false;
    });
  }

  void _handleActionOverlayExitComplete() {
    if (!mounted || _actionTarget != null || _actionOverlaySnapshot == null) {
      return;
    }
    _updateState(() => _actionOverlaySnapshot = null);
  }

  List<QuickReactionChoice> _quickReactionChoices(
    MessageReactionAvailability availability,
  ) {
    final configured = effectiveQuickReactions(
      context.watch<ThemeController>().quickReactions,
      allowCustomEmoji:
          availability.allowArbitraryCustom ||
          availability.choices.any((choice) => choice.isCustom),
    );
    return availability.quickChoices(configured);
  }

  /// Long-pressing the reply banner jumps to the original message. A

  /// cross-chat reply's source lives outside this transcript, so only a

  /// same-chat target can be jumped to.

  void _jumpToReplySource(ChatMessage message) {
    if (_vm.replyToChatId != null) return;
    unawaited(_jumpToMessage(message.id));
  }

  /// Moves the pending reply into a chat picked from the chat list. The

  /// destination composer receives the reply as a cross-chat reply, so its

  /// send addresses the source message where it actually lives.

  Future<void> _replyInAnotherChat(
    ChatMessage message, {
    MessageTextQuote? quoteParam,
  }) async {
    final result = await Navigator.of(context).push<ChatPickerResult>(
      MaterialPageRoute(
        builder: (_) => const ChatPickerView(
          title: AppStringKeys.chatReplyInAnotherChatTitle,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final targetChat = result.chat;
    final sourceChatId = _vm.replyToChatId ?? _vm.chatId;
    if (targetChat.id == sourceChatId) return;
    // Read the composer draft before navigating: the current view model may
    // be disposed once the destination transcript opens.
    final draftText = _vm.composerFormattedDraft;
    final quote = quoteParam ?? _vm.replyQuote;
    ChatDeepLinkController.shared.openChat(
      chatId: targetChat.id,
      title: targetChat.title,
      externalReply: ExternalReplyHandoff(
        sourceChatId: sourceChatId,
        message: ChatMessagePayload(
          id: message.id,
          isOutgoing: message.isOutgoing,
          date: message.date,
          senderName: message.senderName,
          text: message.text,
        ),
        quote: quote,
        draftText: draftText,
      ),
    );
    _vm.setReply(null);
  }

  /// Installs a reply carried over from another chat ("reply in another

  /// chat"): the composer starts with the cross-chat reply pending and the

  /// draft text typed before the move. Consumed once; a later rebuild of the

  /// same widget re-runs this against an already-cleared handoff field.

  void _adoptExternalReplyHandoff() {
    final handoff = widget.externalReplyHandoff;
    if (handoff == null) return;
    if (handoff.sourceChatId == widget.chatId) return;
    _vm.setExternalReply(
      ChatMessage(
        id: handoff.message.id,
        isOutgoing: handoff.message.isOutgoing,
        date: handoff.message.date,
        senderName: handoff.message.senderName,
        text: handoff.message.text,
      ),
      handoff.sourceChatId,
      quote: handoff.quote as MessageTextQuote?,
    );
    if (handoff.draftText.isNotEmpty) {
      _vm.setDraft(handoff.draftText);
    }
  }

  void _adoptForwardHandoff() {
    final handoff = widget.forwardHandoff;
    if (handoff == null) return;
    _vm.adoptForwardHandoff(handoff);
  }
}
