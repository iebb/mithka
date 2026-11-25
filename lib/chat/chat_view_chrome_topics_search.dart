part of 'chat_view.dart';

extension _ChatViewChrome on _ChatViewState {
  Future<void> _showBusinessBotControls() async {
    final changed = await showAppModalSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => BusinessBotChatControlSheet(
        chatId: widget.chatId,
        botName: AppStrings.t(AppStringKeys.chatConnectedBusinessBot),
        paused: _vm.businessBotPaused,
      ),
    );
    if (changed == true) await _vm.refreshPeerRestrictionState();
  }

  Future<void> _openChannelMoments() async {
    ChatSummary? channel;
    try {
      channel = TDParse.chat(
        await TdClient.shared.queryForSlot({
          '@type': 'getChat',
          'chat_id': _vm.chatId,
        }, _vm.accountSlot),
      );
    } catch (_) {}
    if (!mounted) return;
    if (channel == null) {
      showToast(context, AppStringKeys.topicPostContentActionFailed);
      return;
    }
    final feedChannel = channel;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChannelMomentsView(channel: feedChannel),
      ),
    );
  }

  void _openTopicTranscript(int? topicId) {
    if (topicId == widget.forumTopicId) return;
    _prepareExitState();
    final onOpenTopicTranscript = widget.onOpenTopicTranscript;
    if (onOpenTopicTranscript != null) {
      onOpenTopicTranscript(topicId);
      return;
    }
    if (ChatPane.replace(
      context,
      (onBack) => ChatView(
        // A distinct key per transcript: ChatView reads its topic only once.
        key: ValueKey(('pane-topic-transcript', widget.chatId, topicId)),
        chatId: widget.chatId,
        title: widget.title,
        forumTopicId: topicId,
        showBackButton: widget.showBackButton,
        headerHeight: widget.headerHeight,
        headerColor: widget.headerColor,
        showHeaderDivider: widget.showHeaderDivider,
        trailingPane: widget.trailingPane,
        trailingPaneWidth: widget.trailingPaneWidth,
        onTrailingPaneToggle: widget.onTrailingPaneToggle,
        exitController: widget.exitController,
        onChatKindResolved: widget.onChatKindResolved,
        onInfoPressed: widget.onInfoPressed,
        onOpenFullInfo: widget.onOpenFullInfo,
        onOpenUserProfile: widget.onOpenUserProfile,
        onBack: onBack,
      ),
    )) {
      return;
    }
    unawaited(
      replaceWithAppChatRoute<void, void>(
        context,
        AppChatPageRoute<void>(
          // An in-place topic swap: the new transcript replaces this one in a
          // single frame so the header and tab strip never flash or slide.
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          builder: (_) => ChatView(
            chatId: widget.chatId,
            title: widget.title,
            forumTopicId: topicId,
          ),
        ),
      ),
    );
  }

  ForumTopicOption? _topicById(int? id) {
    if (id == null) return null;
    for (final topic in _vm.forumTopics) {
      if (topic.id == id) return topic;
    }
    return null;
  }

  Future<void> _openCreateTopicDialog() async {
    final draft = await showDialog<TopicDraft>(
      context: context,
      builder: (dialogContext) => TopicDraftDialog(
        title: AppStrings.t(AppStringKeys.groupAdministrationNewTopic),
        initialName: '',
        initialColor:
            topicIconColors[_vm.forumTopics.length % topicIconColors.length],
        initialCustomEmojiId: 0,
        canChangeColor: true,
      ),
    );
    if (!mounted || draft == null || draft.name.isEmpty) return;
    try {
      final created = await _vm.createForumTopic(
        name: draft.name,
        iconColor: draft.color,
        iconCustomEmojiId: draft.customEmojiId,
      );
      // Open the fresh topic the way iOS does after creation.
      if (mounted && created != null && created != 0) {
        _openTopicTranscript(created);
      }
    } catch (error) {
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(
          AppStringKeys.groupAdministrationCouldnTCreateTopicValue1,
          {'value1': error},
        ),
      );
    }
  }

  Future<void> _editTopic(ForumTopicOption topic) async {
    if (topic.isGeneral) return;
    final draft = await showDialog<TopicDraft>(
      context: context,
      builder: (dialogContext) => TopicDraftDialog(
        title: AppStrings.t(AppStringKeys.groupAdministrationEditTopic),
        initialName: topic.name,
        initialColor: topic.iconColor == 0
            ? topicIconColors.first
            : topic.iconColor,
        initialCustomEmojiId: topic.iconCustomEmojiId,
        canChangeColor: false,
      ),
    );
    if (!mounted || draft == null || draft.name.isEmpty) return;
    try {
      await _vm.editForumTopic(
        forumTopicId: topic.id,
        name: draft.name,
        iconCustomEmojiId: draft.customEmojiId,
      );
    } catch (error) {
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.groupAdministrationCouldnTEditTopicValue1, {
          'value1': error,
        }),
      );
    }
  }

  Future<void> _deleteTopic(ForumTopicOption topic) async {
    if (topic.isGeneral || !_vm.canDeleteTopic(topic)) return;
    final ok = await confirmDialog(
      context,
      title: AppStrings.t(
        AppStringKeys.groupAdministrationDeleteTopicAndMessages,
        {'value1': topic.name},
      ),
      confirmText: AppStringKeys.chatDelete,
      destructive: true,
    );
    if (!ok || !mounted) return;
    // The dialog can stay open across a rights change, a revocation or an
    // account switch; re-verify the current state before anything
    // destructive is sent.
    final current = _topicById(topic.id);
    if (current == null || !_vm.canDeleteTopic(current)) return;
    try {
      await _vm.deleteForumTopic(current.id);
      if (widget.forumTopicId == topic.id) {
        _openTopicTranscript(null);
      }
    } catch (error) {
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(
          AppStringKeys.groupAdministrationCouldnTDeleteTopicValue1,
          {'value1': error},
        ),
      );
    }
  }

  Future<void> _toggleTopicPinned(ForumTopicOption topic) async {
    try {
      await _vm.setForumTopicPinned(topic.id, pinned: !topic.isPinned);
    } catch (error) {
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.groupAdministrationCouldnTPinTopicValue1, {
          'value1': error,
        }),
      );
    }
  }

  Future<void> _toggleTopicMuted(ForumTopicOption topic) async {
    try {
      await _vm.setForumTopicMuted(topic.id, muted: !topic.isMuted);
    } catch (error) {
      if (!mounted) return;
      showToast(
        context,
        topicActionErrorText(
          AppStrings.t(AppStringKeys.topicChatMuteFailed),
          error,
        ),
      );
    }
  }

  Future<void> _toggleTopicClosed(ForumTopicOption topic) async {
    try {
      await _vm.setForumTopicClosed(topic.id, closed: !topic.isClosed);
    } catch (error) {
      if (!mounted) return;
      showToast(
        context,
        topicActionErrorText(
          AppStrings.t(AppStringKeys.topicPostContentActionFailed),
          error,
        ),
      );
    }
  }

  Future<void> _markTopicRead(ForumTopicOption topic) =>
      _vm.markForumTopicRead(topic);

  Future<void> _markAllTopicsRead() async {
    try {
      await _vm.markForumTopicsRead(_vm.forumTopics.map((topic) => topic.id));
    } catch (_) {
      // Every read failed: the rows were rolled back; say so once.
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.topicChatMarkAllReadFailed),
      );
      return;
    }
    if (!mounted) return;
    if (_vm.takeBulkReadFailure()) {
      showToast(
        context,
        AppStrings.t(AppStringKeys.topicChatMarkAllReadFailed),
      );
    }
  }

  Future<void> _showTopicRowMenu(
    TopicNavigationItem item,
    Offset? globalPosition,
  ) async {
    final topic = _topicById(item.id);
    if (topic == null) return;
    // The creator deletion carve-out depends on the topic's live history
    // (at most 11 messages, none from other users), so probe before the menu
    // is offered. Rights-based eligibility is already known synchronously, and
    // a bot topic chat offers Delete without the probe.
    if (!topic.isGeneral &&
        !_vm.isBotTopicChat &&
        _vm.canDeleteForumTopics != true &&
        _vm.creatorOfTopic(topic)) {
      await _vm.ensureTopicCreatorDeletable(topic.id);
      if (!mounted) return;
    }
    await showTopicRowMenuSheet(
      context: context,
      topic: item,
      actions: topicRowActions(
        topic: item,
        canManage: _vm.canPinAndEditTopics,
        canDelete: _vm.canDeleteTopic(topic),
        canClose: _vm.canCloseTopic(topic),
        onMarkRead: () => _markTopicRead(topic),
        onTogglePinned: () => _toggleTopicPinned(topic),
        onToggleMuted: () => _toggleTopicMuted(topic),
        onEdit: () => _editTopic(topic),
        onToggleClosed: () => _toggleTopicClosed(topic),
        onDelete: () => _deleteTopic(topic),
      ),
    );
  }

  Future<void> _showTopicSelector() async {
    if (!_vm.supportsTopics) return;
    if (_vm.forumTopics.isEmpty && !_vm.forumTopicsLoading) {
      await _vm.loadForumTopics();
    }
    if (!mounted) return;
    if (_vm.forumTopics.isEmpty) {
      showToast(
        context,
        _vm.forumTopicsLoading
            ? AppStringKeys.chatLoadingTopics
            : AppStringKeys.chatNoTopics,
      );
      return;
    }
    final c = context.colors;
    // Desktop/wide-tablet layouts present the sheet centered with every
    // corner rounded; only the phone bottom-sheet form rounds the top edge.
    final centered = appModalUsesCenteredPresentation(
      MediaQuery.sizeOf(context),
    );
    final currentTopicId = widget.forumTopicId;
    await showAppModalSheet<void>(
      context: context,
      backgroundColor: c.background,
      shape: RoundedRectangleBorder(
        borderRadius: centered
            ? BorderRadius.circular(AppRadius.xl)
            : const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        // Live, like the strip above the transcript: a message that lands
        // while the list is open reorders its rows and bumps counters, and
        // the transcript the user is in stays marked.
        child: ListenableBuilder(
          listenable: _vm,
          builder: (_, _) {
            final topics = _vm.forumTopics;
            if (topics.isEmpty) return const SizedBox.shrink();
            return ListView.separated(
              key: const ValueKey('topic-selector-list'),
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: topics.length + 1,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, indent: 56, color: c.divider),
              itemBuilder: (_, index) {
                final all = index == 0;
                final topic = all ? null : topics[index - 1];
                final current = topic?.id == currentTopicId;
                return ChatListSelectionHighlight(
                  key: ValueKey('topic-selector-row-${topic?.id ?? "all"}'),
                  selected: current,
                  // The same anchored menu the topic tabs open, but hung off
                  // the finger that pressed the row: a long press on a list
                  // row is a pointer gesture, so the menu has to open where
                  // the finger is, not at the row's box.
                  child: GestureDetector(
                    onLongPressStart: topic == null
                        ? null
                        : (details) {
                            final press = details.globalPosition;
                            unawaited(
                              _showTopicMenu(
                                topic,
                                Rect.fromLTWH(press.dx, press.dy, 0, 0),
                              ),
                            );
                          },
                    child: ListTile(
                      leading: _forumTopicIcon(topic, all, c, current: current),
                      title: Text(
                        (all ? AppStringKeys.topicChatAllTopics : topic!.name)
                            .l10n(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: current ? AppTheme.brand : c.textPrimary,
                          fontSize: 16,
                          fontWeight: current ? FontWeight.w600 : null,
                        ),
                      ),
                      // The centered sheet variant lays tiles out at a narrow
                      // width; an unsized badge can exceed the whole row, so
                      // wrap the trailing slot in a bounded box.
                      trailing: _topicSelectorTrailing(topic, all, current),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _openTopicTranscript(topic?.id);
                      },
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _openPinnedFromBar(ChatMessage pinned) async {
    await _scrollToMessage(pinned.id, pinnedJump: true);
  }

  void _goToPreviousPinned() {
    final pinned = _vm.previousPinnedMessage();
    if (pinned != null) {
      unawaited(_scrollToMessage(pinned.id, pinnedJump: true));
    }
  }

  void _goToNextPinned() {
    final pinned = _vm.nextPinnedMessage();
    if (pinned != null) {
      unawaited(_scrollToMessage(pinned.id, pinnedJump: true));
    }
  }

  Future<void> _scrollToMessage(
    int messageId, {
    bool pinnedJump = false,
    double? alignment,
    bool forceAlignment = false,
    bool Function()? isCancelled,
  }) async {
    _claimTranscriptViewport();
    await _scrollToMessageAndReport(
      messageId,
      pinnedJump: pinnedJump,
      alignment: alignment,
      forceAlignment: forceAlignment,
      isCancelled: isCancelled,
    );
  }

  Future<void> _openReplyMessage(int messageId) async {
    // Capture before the viewport is claimed: the claim marks a navigation in
    // progress and the recorded origin is the frame the reader just left.
    _captureJumpOrigin();
    _claimTranscriptViewport();
    final didReachTarget = await _scrollToMessageAndReport(messageId);
    if (!didReachTarget || !mounted) return;
    if (isDesktopTargetPlatform(Theme.of(context).platform)) {
      _flashLinkedMessageHighlight(messageId);
    }
  }

  void _flashLinkedMessageHighlight(int messageId) {
    _linkedMessageHighlightFadeTimer?.cancel();
    _linkedMessageHighlightClearTimer?.cancel();
    _updateState(() {
      _linkedMessageHighlightId = messageId;
      _linkedMessageHighlightActive = true;
    });
    _linkedMessageHighlightFadeTimer = Timer(
      const Duration(milliseconds: 650),
      () {
        if (!mounted || _linkedMessageHighlightId != messageId) return;
        _updateState(() => _linkedMessageHighlightActive = false);
        _linkedMessageHighlightClearTimer = Timer(AppMotion.deliberate, () {
          if (!mounted || _linkedMessageHighlightId != messageId) return;
          _updateState(() => _linkedMessageHighlightId = null);
        });
      },
    );
  }

  Future<bool> _scrollToMessageAndReport(
    int messageId, {
    bool pinnedJump = false,
    double? alignment,
    bool forceAlignment = false,
    bool alignUnreadDivider = false,
    bool Function()? isCancelled,
  }) async {
    if (isCancelled?.call() ?? false) return false;
    if (!mounted) return false;
    _updateState(() => _setScrollTarget(messageId, forceNavigation: true));
    final navigationGeneration = _scrollTargetGeneration;
    bool targetCancelled() =>
        !_isCurrentScrollTarget(messageId, navigationGeneration) ||
        (isCancelled?.call() ?? false);
    // The target key moves to the requested row during layout. Waiting for
    // that frame prevents an already-loaded jump from reusing the previous
    // pinned row's context.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || targetCancelled()) return false;
    if (_vm.messages.any((m) => m.id == messageId)) {
      return _ensureMessageVisibleAndReport(
        messageId,
        navigationGeneration: navigationGeneration,
        pinnedJump: pinnedJump,
        alignment: alignment,
        forceAlignment: forceAlignment,
        alignUnreadDivider: alignUnreadDivider,
        isCancelled: targetCancelled,
      );
    }
    final loaded = await _vm.loadAroundMessage(
      messageId,
      scrollToTarget: false,
      isCancelled: targetCancelled,
    );
    if (!loaded || !mounted || targetCancelled()) return false;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || targetCancelled()) return false;
    return _ensureMessageVisibleAndReport(
      messageId,
      navigationGeneration: navigationGeneration,
      pinnedJump: pinnedJump,
      alignment: alignment,
      forceAlignment: forceAlignment,
      alignUnreadDivider: alignUnreadDivider,
      isCancelled: targetCancelled,
    );
  }

  void _openHashtagSearch(String hashtag) {
    final tag = hashtag.trim();
    if (tag.isEmpty) return;
    _openSearch(initialQuery: tag.startsWith('#') ? tag : '#$tag');
  }

  void _onSearchChanged() {
    final active = _search.isActive;
    if (active == _searchActive) return;
    _searchActive = active;
    if (mounted) _updateState(() {});
  }

  void _openSearch({String? initialQuery}) {
    if (_isSelecting) _exitSelection();
    _search.open(initialQuery: initialQuery);
  }

  void _closeSearch() {
    if (!_search.isActive) return;
    _updateState(() => _searchHighlightId = null);
    _search.close();
  }

  Future<void> _openSearchResult(
    ChatMessage result, {
    required bool automatic,
  }) async {
    _updateState(() => _searchHighlightId = result.id);
    // A phone gives up most of its height to the keyboard, so a deliberate
    // jump puts it away — the message asked for should be the thing on screen.
    // A query's own landing must not, or typing would close the keyboard on
    // every pause.
    if (!automatic && !_searchResultsPaneVisible) _search.focusNode.unfocus();
    await _scrollToMessage(
      result.id,
      alignment: 0.38,
      forceAlignment: true,
      // A query's own landing can outlive the query: the history fetch it may
      // need takes longer than the next keystroke. Aborting it beats racing it.
      isCancelled: automatic
          ? () => _search.activeMessageId != result.id
          : null,
    );
  }

  bool _searchUsesResultsPane(double conversationWidth) =>
      _search.isActive &&
      chatSearchUsesResultsPane(
        windowSize: MediaQuery.sizeOf(context),
        conversationWidth: conversationWidth,
      );

  Future<void> _jumpToDateMessage(ChatMessage message) async {
    _search.focusNode.unfocus();
    await _scrollToMessage(message.id, alignment: 0.38, forceAlignment: true);
  }

  Future<void> _ensureMessageVisible(
    int messageId, {
    required int navigationGeneration,
    bool pinnedJump = false,
    bool instant = false,
    double? alignment,
    bool forceAlignment = false,
  }) async {
    await _ensureMessageVisibleAndReport(
      messageId,
      navigationGeneration: navigationGeneration,
      pinnedJump: pinnedJump,
      instant: instant,
      alignment: alignment,
      forceAlignment: forceAlignment,
    );
  }

  Future<bool> _ensureMessageVisibleAndReport(
    int messageId, {
    required int navigationGeneration,
    bool pinnedJump = false,
    bool instant = false,
    double? alignment,
    bool forceAlignment = false,
    bool alignUnreadDivider = false,
    bool Function()? isCancelled,
  }) async {
    bool targetCancelled() =>
        !_isCurrentScrollTarget(messageId, navigationGeneration) ||
        (isCancelled?.call() ?? false);

    final targetAlignment =
        alignment ?? (pinnedJump ? pinnedMessageScrollAlignment : 0.3);
    var stagedAtTranscriptCenter = false;
    for (var tries = 0; tries < 6; tries++) {
      if (targetCancelled()) return false;
      // Unread navigation targets the divider, not a fraction of the message
      // body. For an oversized post, aligning its body at 12% would put the
      // beginning and the divider hundreds of pixels above the viewport.
      final activeKey = alignUnreadDivider ? _unreadKey : _targetKey;
      final ctx = activeKey.currentContext;
      if (ctx != null && ctx.mounted) {
        if (pinnedJump && alignment == null && _scroll.hasClients) {
          final aligned = await _alignPinnedMessage(
            messageId,
            navigationGeneration: navigationGeneration,
            instant: instant,
            isCancelled: isCancelled,
          );
          if (aligned && targetCancelled()) {
            return false;
          }
          if (aligned) {
            if (mounted && !targetCancelled()) {
              _updateState(() => _setScrollTarget(null));
              return true;
            }
            return false;
          }
        }
        // Do not realign a message that is already on screen. Reply, search,
        // and other linked-message jumps used to always force the row to 30%
        // of the viewport, which made an already-visible target bounce.
        if (!forceAlignment && _isKeyMostlyVisible(activeKey)) {
          if (mounted && !targetCancelled()) {
            _updateState(() => _setScrollTarget(null));
            return true;
          }
          return false;
        }
        if (!mounted || !ctx.mounted || targetCancelled()) return false;
        final aligned = await _alignMessageTarget(
          activeKey,
          alignment: targetAlignment,
          instant: instant,
          pinnedJump: pinnedJump,
          isCancelled: targetCancelled,
        );
        if (!mounted || targetCancelled()) return false;
        // A correction pass can lose the row's context without the navigation
        // being cancelled, and the jump is over either way. Holding the target
        // past that point stalls new-message auto-scroll, short-transcript
        // fill, and parked-pivot repair for as long as the chat stays open.
        _updateState(() => _setScrollTarget(null));
        return aligned;
      }
      if (!_scroll.hasClients) return false;
      // A loaded target can be arbitrarily far from the currently laid-out
      // sliver children. Move the bidirectional transcript's center to that
      // row once; unlike an absolute height estimate, this guarantees Flutter
      // will build the target even when every preceding row was underestimated.
      if (!stagedAtTranscriptCenter &&
          _stageMessageAtTranscriptCenter(messageId)) {
        stagedAtTranscriptCenter = true;
      } else {
        final estimate = _estimateMessageOffset(
          messageId,
          targetAlignment,
          beforeUnreadDivider: alignUnreadDivider,
        );
        if (estimate != null) _scroll.jumpTo(estimate);
      }
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || targetCancelled()) return false;
    }
    if (mounted && !targetCancelled()) {
      _updateState(() => _setScrollTarget(null));
    }
    return false;
  }

  Future<bool> _alignMessageTarget(
    GlobalKey targetKey, {
    required double alignment,
    required bool instant,
    required bool pinnedJump,
    required bool Function() isCancelled,
  }) async {
    for (var pass = 0; pass < 3; pass++) {
      if (isCancelled()) return false;
      final ctx = targetKey.currentContext;
      if (ctx == null || !ctx.mounted) return false;
      // Nothing reflowed during the previous pass, so the remaining correction
      // animations would only spend their duration re-issuing the offset the
      // row already sits at.
      if (pass > 0 && _isTargetAtAlignment(targetKey, alignment)) return true;
      await Scrollable.ensureVisible(
        ctx,
        alignment: alignment,
        duration: instant
            ? Duration.zero
            : pass == 0
            ? pinnedJump
                  ? const Duration(milliseconds: 140)
                  : const Duration(milliseconds: 220)
            : const Duration(milliseconds: 80),
        curve: Curves.easeOutCubic,
      );
      if (isCancelled()) return false;
      await WidgetsBinding.instance.endOfFrame;
    }
    return !isCancelled();
  }

  bool _isTargetAtAlignment(GlobalKey targetKey, double alignment) {
    if (!_scroll.hasClients) return false;
    final object = targetKey.currentContext?.findRenderObject();
    if (object == null || !object.attached) return false;
    final viewport = RenderAbstractViewport.maybeOf(object);
    if (viewport == null) return false;
    final target = clampScrollOffset(
      _scroll.position,
      viewport.getOffsetToReveal(object, alignment).offset,
    );
    return (target - _scroll.position.pixels).abs() <= 0.5;
  }

  Future<bool> _alignPinnedMessage(
    int messageId, {
    required int navigationGeneration,
    required bool instant,
    bool Function()? isCancelled,
  }) async {
    bool targetCancelled() =>
        !_isCurrentScrollTarget(messageId, navigationGeneration) ||
        (isCancelled?.call() ?? false);

    for (var pass = 0; pass < 3; pass++) {
      if (targetCancelled()) return false;
      final activeKey = _targetKey;
      final targetObject = activeKey.currentContext?.findRenderObject();
      final viewportObject = _transcriptViewportKey.currentContext
          ?.findRenderObject();
      if (targetObject is! RenderBox ||
          !targetObject.attached ||
          viewportObject is! RenderBox ||
          !viewportObject.attached ||
          !_scroll.hasClients) {
        return false;
      }
      final target = pinnedMessageTargetScrollOffset(
        _scroll.position,
        targetTop: targetObject.localToGlobal(Offset.zero).dy,
        viewportTop: viewportObject.localToGlobal(Offset.zero).dy,
      );
      if ((target - _scroll.position.pixels).abs() <= 0.5) return true;
      if (instant) {
        _scroll.jumpTo(target);
      } else {
        await _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
        );
      }
      if (targetCancelled()) return false;
      await WidgetsBinding.instance.endOfFrame;
      if (targetCancelled()) return false;
    }
    return !targetCancelled();
  }

  bool _isKeyMostlyVisible(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return false;
    final renderObject = ctx.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return false;
    final viewportObject = _transcriptViewportKey.currentContext
        ?.findRenderObject();
    if (viewportObject is! RenderBox || !viewportObject.attached) return false;
    final targetTop = renderObject.localToGlobal(Offset.zero).dy;
    final targetBottom = targetTop + renderObject.size.height;
    final viewportTop = viewportObject.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + viewportObject.size.height;
    final pinnedOverlayInset =
        !_search.isActive && _vm.pinnedMessage != null && !_vm.pinnedDismissed
        ? pinnedMessageTargetTopInset
        : 0.0;
    // The viewport already excludes the header, bottom composer, keyboard,
    // and safe areas. Comparing against those widgets' assumed heights was the
    // source of false "already visible" results after an Android resize.
    return targetTop >= viewportTop + pinnedOverlayInset - 24 &&
        targetBottom <= viewportBottom + 24;
  }

  /// The topic tab strip: a folder-tab-styled selector pinned under the

  /// header, shown for forum groups and bot topic chats on narrow layouts —

  /// the whole chat included, where the "All" tab is the selected one. Wide

  /// shells render their rail instead.

  Widget _topicTabStrip(Widget child) {
    if (!_topicsKnown || usesSplitSelectionLayout(MediaQuery.sizeOf(context))) {
      return child;
    }
    final theme = context.watch<ThemeController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TopicTabStrip(
          chatId: widget.chatId,
          topics: [
            for (final topic in _vm.forumTopics) _topicNavigationItem(topic),
          ],
          selectedTopicId: widget.forumTopicId,
          onSelected: _openTopicTranscript,
          showUnreadBadges: theme.showFolderUnreadBadges,
          badgeOverflowLabel: theme.unreadBadgeOverflowMode.format,
          isLoading: _vm.forumTopicsLoading && _vm.forumTopics.isEmpty,
          onLongPress: _showTopicTabMenu,
        ),
        if (_showsChatTranslationPanel) _chatTranslationPanel(),
        Expanded(child: child),
      ],
    );
  }

  /// The read-all menu behind a long press on the mention pill: one anchored

  /// row that clears every mention, mirroring the reference client's ReadAllMentionsMenu

  /// over the chat's side control. Reactions need no menu — that long press

  /// clears them directly.

  Future<void> _showReadAllMentionsMenu(Rect anchor) => showAppAnchoredMenu(
    context: context,
    anchor: anchor,
    actions: [
      AppMenuAction(
        key: 'read-all-mentions',
        label: AppStrings.t(AppStringKeys.chatListMarkAllRead),
        icon: HeroAppIcons.check,
        onSelected: () => unawaited(_markAllMentionsRead()),
      ),
    ],
  );
  Future<void> _markAllMentionsRead() async {
    if (!await _vm.markAllMentionsRead() && mounted) {
      showToast(context, AppStrings.t(AppStringKeys.channelMarkAllReadFailed));
    }
  }

  Future<void> _markAllReactionsRead() async {
    if (!await _vm.markAllReactionsRead() && mounted) {
      showToast(context, AppStrings.t(AppStringKeys.channelMarkAllReadFailed));
    }
  }

  /// Opens the channel's linked chat (discussion group or direct messages)

  /// from the bottom panel. The title paints the header until TDLib answers

  /// with the real one, so the cached chat is read first.

  Future<void> _openChannelLinkedChat(int chatId) async {
    if (chatId == 0) return;
    var title = '';
    try {
      final chat = await TdClient.shared.query({
        '@type': 'getChat',
        'chat_id': chatId,
      });
      title = chat.str('title') ?? '';
    } catch (_) {}
    if (title.isEmpty) title = _vm.peerTitle;
    if (!mounted) return;
    await openChatFromCurrentWindow(context, chatId: chatId, title: title);
  }

  /// Follows the topic a send just started from this bot topic chat's "All"

  /// view: the reference client selects the freshly created topic's tab the moment the

  /// send creates it, and the message must not stay stranded in a mixed list.

  ///

  /// The switch is scheduled for after the frame: the notification it rides in

  /// on can arrive mid-send, and replacing this transcript synchronously would

  /// tear it down under the caller.

  void _maybeOpenCreatedBotTopic() {
    final topicId = _vm.consumePendingBotTopicOpen();
    if (topicId == null || topicId == widget.forumTopicId) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _exitStatePrepared) return;
      _openTopicTranscript(topicId);
    });
  }

  /// mute and mark-read stay available to everyone.

  /// The tab's long press resolves the tab to its topic row and opens the

  /// shared menu. A tab strip is a bar the menu belongs to, so the menu hugs

  /// its bottom edge instead of hanging the default gap below it.

  Future<void> _showTopicTabMenu(TopicNavigationItem item, Rect anchor) async {
    final topic = _topicById(item.id);
    if (topic == null) return;
    await _showTopicMenu(topic, anchor, gap: AppSpacing.xs);
  }

  /// The topic menu, the way the reference client opens ItemOptions over a long-pressed

  /// tab or list row: pin / edit / close-reopen / delete, each gated by the

  /// rights the row menu uses. No name header — the tab or row under the

  /// finger already names the topic. The creator deletion carve-out probes the

  /// topic's live history before Delete can be offered; a bot topic chat has

  /// no such probe.

  Future<void> _showTopicMenu(
    ForumTopicOption topic,
    Rect anchor, {
    double gap = 8,
  }) async {
    if (!topic.isGeneral &&
        !_vm.isBotTopicChat &&
        _vm.canDeleteForumTopics != true &&
        _vm.creatorOfTopic(topic)) {
      await _vm.ensureTopicCreatorDeletable(topic.id);
      if (!mounted) return;
    }
    final actions = <AppMenuAction>[
      if (_vm.canPinAndEditTopics)
        AppMenuAction(
          key: 'pin',
          label: AppStrings.t(
            topic.isPinned
                ? AppStringKeys.chatListUnpin
                : AppStringKeys.chatInfoPin,
          ),
          icon: HeroAppIcons.pin,
          onSelected: () => unawaited(_toggleTopicPinned(topic)),
        ),
      if (_vm.canPinAndEditTopics && !topic.isGeneral)
        AppMenuAction(
          key: 'edit',
          label: AppStrings.t(AppStringKeys.groupAdministrationEditTopic),
          icon: HeroAppIcons.pen,
          onSelected: () => unawaited(_editTopic(topic)),
        ),
      if (_vm.canCloseTopic(topic))
        AppMenuAction(
          key: 'close',
          label: AppStrings.t(
            topic.isClosed
                ? AppStringKeys.topicChatReopenTopic
                : AppStringKeys.topicChatCloseTopic,
          ),
          icon: topic.isClosed ? HeroAppIcons.eye : HeroAppIcons.lock,
          onSelected: () => unawaited(_toggleTopicClosed(topic)),
        ),
      if (_vm.canDeleteTopic(topic))
        AppMenuAction(
          key: 'delete',
          label: AppStrings.t(AppStringKeys.channelDeleteTopic),
          icon: HeroAppIcons.trash,
          destructive: true,
          onSelected: () => unawaited(_deleteTopic(topic)),
        ),
    ];
    if (actions.isEmpty) return;
    await showAppAnchoredMenu(
      context: context,
      anchor: anchor,
      actions: actions,
      gap: gap,
    );
  }

  /// The selector row's trailing slot: a brand check for the transcript the

  /// user is already in, the unread pill for the others (both when the open

  /// topic was manually marked unread).

  Widget? _topicSelectorTrailing(
    ForumTopicOption? topic,
    bool all,
    bool current,
  ) {
    final unread = !all && topic != null && topic.unreadCount > 0;
    if (!current && !unread) return null;
    return SizedBox(
      width: 64,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (current)
            AppIcon(HeroAppIcons.check, size: 18, color: AppTheme.brand),
          if (unread) ...[
            if (current) const SizedBox(width: AppSpacing.xs + 2),
            UnreadBadge(
              key: ValueKey('topic-selector-unread-${topic.id}'),
              count: topic.unreadCount,
              muted: topic.isMuted,
            ),
          ],
        ],
      ),
    );
  }
}
