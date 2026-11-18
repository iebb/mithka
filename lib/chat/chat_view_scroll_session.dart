part of 'chat_view.dart';

extension _ChatViewScrollSession on _ChatViewState {
  void _onScroll() {
    if (!_scroll.hasClients) return;
    // Nothing below lays out or moves the position synchronously, so every
    // bottom check in this tick can share one render-tree measurement.
    _scrollTickActive = true;
    try {
      _handleScrollTick();
    } finally {
      _scrollTickActive = false;
      _scrollTickLoadedBottomOffset = null;
    }
  }

  void _handleScrollTick() {
    final pos = _scroll.position;
    final scrollingUp = pos.pixels < _lastScrollPixels;
    _lastScrollPixels = pos.pixels;
    _autoScrollPolicy.noteUserScroll(
      towardOlderMessages: pos.userScrollDirection == ScrollDirection.forward,
      isAtBottom: _isAtLoadedBottom(1),
    );
    // Persist cheap scalar state while the finger is moving. Capturing an
    // anchor walks every mounted transcript entry and performs layout-space
    // conversions, so defer that work until scrolling settles or the view
    // exits.
    _saveSessionScrollSnapshot(captureAnchor: false);
    _scheduleUnreadProgressUpdate();
    if (_selectionAnchorId != null && scrollingUp != _selectionScrollingUp) {
      _updateState(() => _selectionScrollingUp = scrollingUp);
    }
    if (pos.userScrollDirection == ScrollDirection.forward &&
        isNearOldest(pos, threshold: 500)) {
      unawaited(_loadOlderFromScroll());
    }
    if (_initialTranscriptReady &&
        _scrollTargetId == null &&
        pos.userScrollDirection == ScrollDirection.reverse &&
        _isNearBottom(500)) {
      unawaited(_vm.loadNewer());
    }
    final nearBottom = _vm.historyReachesLatest && _isNearBottom(80);
    if (_isAtLoadedBottom(1)) {
      _autoScrollPolicy.returnToBottom();
      if (!_hasTranscriptPointerDown) {
        _transcriptViewportClaimedByUser = false;
      }
    }
    if (nearBottom &&
        (_liveNewMessageCount > 0 ||
            (!_openAtLatest && !_bannerDismissed && _vm.unreadCount > 0))) {
      _updateState(() {
        _unreadProgress.clearLiveMessages();
        _bannerDismissed = true;
      });
    }
    if (nearBottom) _markReadAtBottomIfNeeded();
    // Show the jump-to-bottom button once scrolled up from the newest message.
    final show =
        !_isAtLoadedBottom() &&
        (_vm.anchoredHistory || distanceToLatest(pos) > 120);
    if (show != _showJumpDown) _updateState(() => _showJumpDown = show);
  }

  bool _onTranscriptUserScroll(UserScrollNotification notification) {
    if (notification.direction == ScrollDirection.idle) {
      final endedTowardLatest =
          _lastTranscriptUserScrollDirection == ScrollDirection.reverse;
      _lastTranscriptUserScrollDirection = ScrollDirection.idle;
      final protectedRestoredPosition = _restoredPositionGuard
          .finishUserScroll();
      _releaseJumpOriginAfterDrag();
      _returnToLatestCoordinator.userDragEnded();
      if (endedTowardLatest && !protectedRestoredPosition) {
        unawaited(_continueHistoryIfNearLatest());
      }
    } else if (_initialTranscriptReady) {
      // Once an older-page request is in flight, a turn toward the latest
      // messages means the user has abandoned the pull. A later model frame
      // must not reveal that page by jumping the viewport back to the oldest
      // edge.
      if (notification.direction == ScrollDirection.reverse) {
        _revealLoadedOlderPage = false;
        _loadedOlderRevealPending = false;
      }
      _lastTranscriptUserScrollDirection = notification.direction;
      _restoredPositionGuard.noteUserScroll();
      _claimTranscriptViewport();
      // A real drag is the only thing that can carry the reader away from the
      // jump target; measure how far it went when it ends.
      _noteJumpOriginDragStart();
    }
    return false;
  }

  bool _onTranscriptScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is UserScrollNotification) {
      _onTranscriptUserScroll(notification);
    }
    if (notification is ScrollStartNotification) {
      _olderHistoryPull.reset();
    } else if (notification is ScrollUpdateNotification) {
      if (_olderHistoryPull.updateBouncingPosition(notification.metrics)) {
        _triggerOlderHistoryPull();
      }
    } else if (notification is OverscrollNotification) {
      if (isNearOldest(notification.metrics, threshold: 1) &&
          _olderHistoryPull.addClampedOverscroll(notification.overscroll)) {
        _triggerOlderHistoryPull();
      }
    } else if (notification is ScrollEndNotification) {
      _olderHistoryPull.reset();
      _scheduleLoadedOlderReveal();
      _scheduleTranscriptBottomGapCorrection();
      _saveSessionScrollSnapshot();
      _scheduleHandoffRefresh();
    }
    return false;
  }

  void _triggerOlderHistoryPull() {
    if (!_initialTranscriptReady ||
        _vm.messages.isEmpty ||
        !_vm.hasOlderHistory) {
      return;
    }
    _revealLoadedOlderPage = true;
    _loadedOlderRevealGestureGeneration = _transcriptGestureGeneration;
    _cancelBottomFollow();
    if (!_vm.isLoadingOlder && !_isFillingShortTranscript) {
      unawaited(_loadOlderFromScroll());
    }
  }

  void _scheduleLoadedOlderReveal() {
    if (!_loadedOlderRevealPending || _loadedOlderRevealScheduled) return;
    _loadedOlderRevealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadedOlderRevealScheduled = false;
      final supersededByUser =
          _transcriptGestureGeneration != _loadedOlderRevealGestureGeneration;
      final blockedByNavigation =
          _scrollTargetId != null ||
          _maintainSessionScrollAnchor ||
          _maintainRestoredBottom;
      if (!mounted ||
          !_loadedOlderRevealPending ||
          !_scroll.hasClients ||
          _hasTranscriptPointerDown ||
          _isUserScrolling ||
          supersededByUser ||
          blockedByNavigation) {
        if (_loadedOlderRevealPending &&
            (supersededByUser || blockedByNavigation)) {
          _loadedOlderRevealPending = false;
        }
        return;
      }
      _loadedOlderRevealPending = false;
      final target = _scroll.position.minScrollExtent;
      if ((_scroll.position.pixels - target).abs() > 0.5) {
        _scroll.jumpTo(target);
      }
      _saveSessionScrollSnapshot();
    });
  }

  void _onTranscriptPointerDown(PointerDownEvent event) {
    _transcriptPointersDown.add(event.pointer);
    ++_transcriptGestureGeneration;
    if (!_initialTranscriptReady) {
      _initialTranscriptPositionCancelled = true;
      // Let the first real drag claim the viewport immediately, even if the
      // opening unread correction has not completed its first frame yet.
      _initialTranscriptReady = true;
    }
    // A delayed message jump must never win back the viewport after the user
    // has touched the transcript. Clear the target before any subsequent
    // history/layout await can reuse its key.
    if (_scrollTargetId != null) {
      _updateState(_invalidateScrollNavigation);
    } else {
      _invalidateScrollNavigation();
    }
    _cancelSessionReopenNavigation();
    _cancelSessionScrollAnchorMaintenance();
    _maintainRestoredBottom = false;
    // A hold cancels an in-flight driven scroll immediately. It does not claim
    // the viewport permanently unless it becomes an actual drag.
    _cancelBottomFollow();
    _stopActiveTranscriptScroll();
    ++_shortTranscriptFillGeneration;
  }

  void _onTranscriptPointerEnd(PointerEvent event) {
    _transcriptPointersDown.remove(event.pointer);
    _scheduleLoadedOlderReveal();
    _scheduleShortFirstContactReveal();
    _scheduleShortTranscriptFill();
    _scheduleSessionScrollAnchorMaintenance();
    _scheduleRestoredBottomCorrection();
    _scheduleTranscriptBottomGapCorrection();
    if (!_hasTranscriptPointerDown && _isAtLoadedBottom(1)) {
      _transcriptViewportClaimedByUser = false;
    }
    if (!_hasTranscriptPointerDown) _drainReturnToLatestIntent();
  }

  void _claimTranscriptViewport() {
    ++_jumpOriginReturnGeneration;
    ++_transcriptGestureGeneration;
    if (_scrollTargetId != null) {
      _updateState(_invalidateScrollNavigation);
    } else {
      _invalidateScrollNavigation();
    }
    _cancelSessionReopenNavigation(userClaimedViewport: true);
    _cancelBottomFollow();
    _returnToLatestCoordinator.cancelForUserDrag();
    ++_shortTranscriptFillGeneration;
    _transcriptViewportClaimedByUser = true;
    _showingFullyVisibleFirstContactHistory = false;
    _maintainSessionScrollAnchor = false;
    _maintainRestoredBottom = false;
    // Do not freeze a thin after-center arm: that parks older history above the
    // center while the open animation / first touch is still settling.
    if (shouldFreezeTranscriptPivot(
      latestArmIsShort: _isTranscriptShort(),
      canLoadOlder: _vm.canLoadOlder,
    )) {
      _transcriptPivotFrozen = true;
    }
  }

  void _stopActiveTranscriptScroll() {
    if (!_scroll.hasClients || !_scroll.position.isScrollingNotifier.value) {
      return;
    }
    _scroll.jumpTo(_scroll.position.pixels);
  }

  void _saveSessionScrollSnapshot({bool captureAnchor = true}) {
    if (!_didInitialScroll ||
        !_initialTranscriptReady ||
        !shouldSaveChatSessionScrollSnapshot(
          sessionReopenPending: _sessionReopenPending,
          preservingSnapshotAfterFailedJump:
              _preserveSnapshotAfterFailedSessionJump,
        ) ||
        _maintainSessionScrollAnchor ||
        !_scroll.hasClients) {
      return;
    }
    final pos = _scroll.position;
    if (!pos.hasContentDimensions) return;
    final wasAtLoadedBottom = isChatSessionAtLoadedBottom(
      anchoredHistory: _vm.anchoredHistory,
      distanceToLoadedBottom: (_loadedBottomOffset - pos.pixels).abs(),
    );
    final anchor = wasAtLoadedBottom || !captureAnchor
        ? null
        : _captureSessionScrollAnchor();
    _ChatViewState._sessionScrollSnapshots[_sessionKey] = _ChatScrollSnapshot(
      pixels: clampScrollOffset(pos, pos.pixels),
      wasAtLoadedBottom: wasAtLoadedBottom,
      knownLatestMessageId: math.max(
        _vm.knownLatestMessageId,
        _latestServerMessage(_vm.messages)?.id ?? 0,
      ),
      pivotMessageId: _transcriptPivot?.cutoffMessageId,
      anchorMessageId: anchor?.messageId,
      anchorViewportOffset: anchor?.viewportOffset,
    );
  }

  void _cancelSessionReopenNavigation({bool userClaimedViewport = false}) {
    final wasPending = _sessionReopenPending;
    _sessionReopenNavigationGuard.cancel();
    _sessionReopenResolutionInFlight = false;
    _sessionReopenDispositionResolved = true;
    if (_prioritizingSessionUnread) {
      _prioritizingSessionUnread = false;
      _invalidateScrollNavigation();
    }
    if (userClaimedViewport) {
      _preserveSnapshotAfterFailedSessionJump = false;
    } else if (wasPending) {
      _preserveSnapshotAfterFailedSessionJump = true;
    }
  }

  void _prepareExitState() {
    if (_exitStatePrepared) return;
    _exitStatePrepared = true;
    _forgetJumpOrigin();
    final sessionReopenPending = _sessionReopenPending;
    _cancelSessionReopenNavigation();
    if (!sessionReopenPending && !_maintainSessionScrollAnchor) {
      _saveSessionScrollSnapshot();
    }
    _cacheCurrentTranscript(force: true);
    if (shouldMarkChatReadOnExit(
      isAtLoadedBottom: _isAtLoadedBottom(80),
      sessionReopenPending: sessionReopenPending,
      restoredPositionProtected: _restoredPositionGuard.blocksAutomaticReturn,
      preservesViewport: _autoScrollPolicy.preservesViewport,
      historyReachesLatest: _vm.historyReachesLatest,
    )) {
      unawaited(_vm.markLoadedMessagesRead());
    }
  }

  void _cacheCurrentTranscript({bool force = false}) {
    if (!_vm.initialLoaded || !_initialTranscriptReady) return;
    final olderHistoryExhausted =
        !_vm.hasOlderHistory || _olderHistoryExhaustedHint;
    if (!_sessionCacheWriteGate.shouldStore(
      messages: _vm.messages,
      anchoredHistory: _vm.anchoredHistory,
      olderHistoryExhausted: olderHistoryExhausted,
      firstContactInfo: _vm.firstContactInfo,
      force: force,
    )) {
      return;
    }
    _ChatViewState._sessionCache.store(
      accountSlot: _sessionKey.accountSlot,
      chatId: _sessionKey.chatId,
      forumTopicId: _sessionKey.forumTopicId,
      messages: _vm.messages,
      anchoredHistory: _vm.anchoredHistory,
      olderHistoryExhausted: olderHistoryExhausted,
      firstContactInfo: _vm.firstContactInfo,
    );
  }

  void _handleBack() {
    _prepareExitState();
    final onBack = widget.onBack;
    if (onBack != null) {
      onBack();
    } else {
      Navigator.of(context).pop();
    }
  }

  ({int messageId, double viewportOffset})? _captureSessionScrollAnchor() {
    final viewportContext = _transcriptViewportKey.currentContext;
    final viewportRenderObject = viewportContext?.findRenderObject();
    if (viewportRenderObject is! RenderBox || !viewportRenderObject.attached) {
      return null;
    }
    // Viewport-local coordinates: the offset is already relative to the
    // viewport top, and stopping the transform walk at the viewport avoids the
    // full ancestor chain per row.
    final viewportBottom = viewportRenderObject.size.height;
    int? visibleAnchorMessageId;
    double? visibleAnchorTop;
    int? partialAnchorMessageId;
    double? partialAnchorTop;
    for (final entry in _mountedTranscriptEntries.entries) {
      final itemRenderObject = entry.value;
      if (!itemRenderObject.attached) {
        continue;
      }
      final itemTop = itemRenderObject
          .localToGlobal(Offset.zero, ancestor: viewportRenderObject)
          .dy;
      final itemBottom = itemTop + itemRenderObject.size.height;
      if (itemBottom <= 0 || itemTop >= viewportBottom) continue;
      if (itemTop >= 0) {
        if (visibleAnchorTop == null || itemTop < visibleAnchorTop) {
          visibleAnchorMessageId = entry.key;
          visibleAnchorTop = itemTop;
        }
      } else if (partialAnchorTop == null || itemTop > partialAnchorTop) {
        partialAnchorMessageId = entry.key;
        partialAnchorTop = itemTop;
      }
    }
    final anchorMessageId = visibleAnchorMessageId ?? partialAnchorMessageId;
    final anchorTop = visibleAnchorTop ?? partialAnchorTop;
    if (anchorMessageId == null || anchorTop == null) return null;
    return (messageId: anchorMessageId, viewportOffset: anchorTop);
  }

  void _scheduleUnreadProgressUpdate() {
    if (_unreadProgressUpdateScheduled ||
        !_initialTranscriptReady ||
        !mounted) {
      return;
    }
    _unreadProgressUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _unreadProgressUpdateScheduled = false;
      if (mounted) _updateUnreadProgressFromViewport();
    });
  }

  void _updateUnreadProgressFromViewport() {
    final viewportContext = _transcriptViewportKey.currentContext;
    final viewportRenderObject = viewportContext?.findRenderObject();
    if (viewportRenderObject is! RenderBox || !viewportRenderObject.attached) {
      return;
    }
    // Measured in the viewport's own space: a root-relative localToGlobal walks
    // and multiplies the whole ancestor transform chain for every mounted row,
    // once per scroll frame.
    final viewportRect = Offset.zero & viewportRenderObject.size;
    var changed = false;
    final newlyVisible = <ChatMessage>[];

    for (final entry in _mountedTranscriptEntries.entries) {
      final itemRenderObject = entry.value;
      if (!itemRenderObject.attached) {
        continue;
      }
      final itemOrigin = itemRenderObject.localToGlobal(
        Offset.zero,
        ancestor: viewportRenderObject,
      );
      final itemRect = itemOrigin & itemRenderObject.size;
      if (!itemRect.overlaps(viewportRect)) continue;

      for (final message
          in _trackedTranscriptEntries[entry.key]?.messages ??
              const <ChatMessage>[]) {
        if (message.isOutgoing || message.isService) continue;
        final observation = _unreadProgress.observeVisibleIncoming(
          messageId: message.id,
          initialUnread: _isEntryUnreadMessage(message.id),
        );
        if (observation.shouldReportViewed) {
          newlyVisible.add(message);
        }
        changed = observation.unreadCountChanged || changed;
      }
    }

    if (_showEntryUnreadBanner &&
        _unreadProgress.initialRemaining(entryUnreadCount: _entryUnreadCount) ==
            0) {
      _showEntryUnreadBanner = false;
      changed = true;
    }

    if (newlyVisible.isNotEmpty) {
      _vm.markVisibleMessagesViewed(newlyVisible);
    }

    if (changed && mounted) _updateState(() {});
  }

  bool _isNearBottom([double threshold = 160]) {
    if (!_scroll.hasClients) return true;
    final position = _scroll.position;
    if (_showingFullyVisibleFirstContactHistory &&
        (position.pixels - position.minScrollExtent).abs() <= 1) {
      return true;
    }
    return (_loadedBottomOffset - position.pixels).abs() <= threshold;
  }

  double _measureLoadedBottomOffset() {
    final position = _scroll.position;
    if (_showingFullyVisibleFirstContactHistory) {
      return position.minScrollExtent;
    }
    if (_vm.isLoadingLatest) return position.maxScrollExtent;
    final latestId = _transcriptCache?.lastOrNull?.last.id;
    final latest = _mountedTranscriptEntries[latestId];
    final viewport = _transcriptViewportKey.currentContext?.findRenderObject();
    if (latest != null &&
        latest.attached &&
        latest.hasSize &&
        viewport is RenderBox &&
        viewport.attached &&
        viewport.hasSize) {
      final bottom = latest
          .localToGlobal(Offset(0, latest.size.height), ancestor: viewport)
          .dy;
      // A center sliver clamps maxScrollExtent to zero even when its short
      // final arm ends above the viewport bottom. Its real latest edge can
      // be negative, with older messages filling the space above it.
      return clampScrollOffset(
        position,
        position.pixels + bottom + 8 - viewport.size.height,
      );
    }
    return position.maxScrollExtent;
  }

  void _scheduleTranscriptBottomGapCorrection() {
    if (_bottomGapCorrectionScheduled) return;
    _bottomGapCorrectionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bottomGapCorrectionScheduled = false;
      if (!mounted ||
          !_initialTranscriptReady ||
          !_scroll.hasClients ||
          !_scroll.position.hasContentDimensions ||
          _hasTranscriptPointerDown ||
          _isUserScrolling ||
          _scrollTargetId != null ||
          _maintainSessionScrollAnchor ||
          _showingFullyVisibleFirstContactHistory) {
        return;
      }
      final target = _loadedBottomOffset;
      if (_scroll.position.pixels <= target + 1) return;
      // Clamp only the empty trailing area after a resize or finished drag.
      // Keep the pivot and the current history window; fetching latest here
      // would discard an unread/search destination.
      _cancelBottomFollow();
      _scroll.jumpTo(target);
      _saveSessionScrollSnapshot();
    });
  }

  bool _isAtLoadedBottom([double threshold = 24]) {
    return _vm.historyReachesLatest &&
        !_vm.anchoredHistory &&
        _isNearBottom(threshold);
  }

  void _clearBottomIndicatorsIfNeeded() {
    if (!_scroll.hasClients || !_isAtLoadedBottom()) return;
    var changed = false;
    if (_showJumpDown) {
      _showJumpDown = false;
      changed = true;
    }
    if (_liveNewMessageCount > 0) {
      _unreadProgress.clearLiveMessages();
      changed = true;
    }
    if (!_bannerDismissed) {
      if (!_showEntryUnreadBanner) {
        _bannerDismissed = true;
        changed = true;
      }
    }
    if (changed && mounted) _updateState(() {});
  }

  Future<void> _loadOlderFromScroll() async {
    if (_loadingOlderFromScroll ||
        _isFillingShortTranscript ||
        !_scroll.hasClients ||
        !_vm.canLoadOlder) {
      return;
    }
    _loadingOlderFromScroll = true;
    try {
      final loaded = await _vm.loadOlder();
      if (loaded) {
        _olderHistoryExhaustedHint = false;
      } else if (!_vm.hasOlderHistory) {
        _olderHistoryExhaustedHint = true;
      }
    } finally {
      _loadingOlderFromScroll = false;
    }
  }

  void _syncKeyboardInset(double inset) {
    if ((_keyboardInset - inset).abs() < 0.5) return;
    final wasNearBottom = _isNearBottom(260);
    final opening = inset > _keyboardInset;
    _keyboardInset = inset;
    if ((wasNearBottom || opening) &&
        !_autoScrollPolicy.preservesViewport &&
        _scrollTargetId == null) {
      _scheduleScrollToBottom(animated: false);
    }
    // The keyboard changes the viewport height without rebuilding the shell
    // any more, so the viewport-measuring sweeps _transcript() used to schedule
    // on every keyboard frame have to be asked for here instead.
    _scheduleTranscriptPivotFreeze();
    _scheduleUnreadProgressUpdate();
    _scheduleShortFirstContactReveal();
    _scheduleTranscriptBottomGapCorrection();
  }

  void _scheduleScrollToBottom({
    bool animated = true,
    bool userInitiated = false,
  }) {
    if (userInitiated) _transcriptViewportClaimedByUser = false;
    final generation = _bottomFollow.begin();
    _scheduledBottomGeneration = generation;
    if (_bottomScrollScheduled) {
      _scheduledBottomAnimated = _scheduledBottomAnimated && animated;
      return;
    }
    _bottomScrollScheduled = true;
    _scheduledBottomAnimated = animated;
    scheduleChatPostFrame(() {
      final shouldAnimate = _scheduledBottomAnimated;
      final scheduledGeneration = _scheduledBottomGeneration;
      _bottomScrollScheduled = false;
      _scheduledBottomAnimated = true;
      if (!_bottomFollow.isCurrent(scheduledGeneration)) return;
      if (!_canFollowLoadedBottom()) {
        _autoScrollPolicy.allowViewportPreservation();
        return;
      }
      // Re-measure after this frame's layout before choosing min (fully
      // visible first-contact history) versus max (the normal latest edge).
      // This prevents a stale min correction followed by a max correction.
      _positionShortFirstContactHistoryIfItFits(requireAtLatest: false);
      unawaited(
        _moveToLoadedBottom(animated: shouldAnimate).whenComplete(() {
          _scheduleBottomGeometryFollow(scheduledGeneration);
        }),
      );
    });
  }

  Future<void> _moveToLoadedBottom({required bool animated}) async {
    if (!_canFollowLoadedBottom()) return;
    _autoScrollPolicy.requestReturnToBottom();
    final target = _loadedBottomOffset;
    final delta = (target - _scroll.position.pixels).abs();
    if (delta <= 0.5) return;
    if (!animated || delta < 48) {
      _scroll.jumpTo(target);
      return;
    }
    await _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
    );
  }

  bool _canFollowLoadedBottom() =>
      mounted &&
      _scroll.hasClients &&
      !_hasTranscriptPointerDown &&
      !_transcriptViewportClaimedByUser &&
      !_vm.anchoredHistory &&
      !_autoScrollPolicy.preservesViewport &&
      _scrollTargetId == null;

  void _scheduleBottomGeometryFollow(
    int generation, {
    int remainingFrames = 12,
  }) {
    _bottomFollow.follow(
      generation: generation,
      remainingFrames: remainingFrames,
      schedulePostFrame: scheduleChatPostFrame,
      canFollow: _canFollowLoadedBottom,
      distanceToLatest: () =>
          (_loadedBottomOffset - _scroll.position.pixels).abs(),
      latestExtent: () => _loadedBottomOffset,
      correct: () => _scroll.jumpTo(_loadedBottomOffset),
      settled: () {
        _autoScrollPolicy.returnToBottom();
        _markReadAtBottomIfNeeded();
        _clearBottomIndicatorsIfNeeded();
        _saveSessionScrollSnapshot();
      },
      abandoned: _autoScrollPolicy.allowViewportPreservation,
    );
  }

  void _cancelBottomFollow() {
    _bottomFollow.cancel();
    _autoScrollPolicy.allowViewportPreservation();
  }

  /// Records where the reader is standing before an in-transcript jump. A
  /// chain of jumps keeps the FIRST origin: that is the place the reader
  /// actually left, and every later jump is only a detour away from it.
  void _captureJumpOrigin() {
    if (_jumpOrigin != null || _scrollTargetId != null) return;
    if (!mounted || !_initialTranscriptReady || !_scroll.hasClients) return;
    // Already at the newest edge: the arrow's existing meaning is still the
    // right one, so there is nothing to remember.
    if (_isAtLoadedBottom(80)) return;
    final anchor = _captureSessionScrollAnchor();
    if (anchor == null) return;
    _jumpOrigin = _ChatJumpOrigin(
      messageId: anchor.messageId,
      viewportOffset: anchor.viewportOffset,
    );
  }

  void _forgetJumpOrigin() {
    ++_jumpOriginReturnGeneration;
    _jumpOrigin = null;
    _jumpOriginDragBaseline = null;
  }

  /// Remembers where the viewport stood when a real drag began. A tap (reply
  /// quote, timestamp) produces no scroll notification, so it can never be
  /// mistaken for the drag that abandons the origin.
  void _noteJumpOriginDragStart() {
    if (_jumpOrigin == null || !_hasTranscriptPointerDown) return;
    _jumpOriginDragBaseline ??= _scroll.hasClients
        ? _scroll.position.pixels
        : null;
  }

  /// Drops the origin once a drag has carried the viewport a meaningful
  /// distance away from the jump target. A small nudge to read the quoted
  /// neighbourhood keeps the arrow pointing back at where the reader left.
  void _releaseJumpOriginAfterDrag() {
    final baseline = _jumpOriginDragBaseline;
    _jumpOriginDragBaseline = null;
    if (baseline == null || _jumpOrigin == null || !_scroll.hasClients) return;
    final viewport = _transcriptViewportKey.currentContext?.findRenderObject();
    final viewportHeight = viewport is RenderBox && viewport.attached
        ? viewport.size.height
        : 0.0;
    final threshold = math.max(120.0, viewportHeight * 0.35);
    if ((_scroll.position.pixels - baseline).abs() >= threshold) {
      _forgetJumpOrigin();
    }
  }

  /// The floating arrow: returns to the message the reader left while a jump
  /// origin is live, and to the newest message otherwise.
  void _onReturnToLatestTapped() {
    final origin = _jumpOrigin;
    if (origin != null) {
      // A tap always consumes the origin, even when its row can no longer be
      // reached: a stale origin must never outlive the tap that asked for it.
      _jumpOrigin = null;
      unawaited(_returnToJumpOrigin(origin));
      return;
    }
    _requestReturnToLatest(userInitiated: true);
  }

  /// The shell asked for the newest message — because the reader tapped the
  /// conversation that is already open, or re-opened it from a link. This is
  /// the same intent as tapping the return-to-latest arrow, so it goes through
  /// the same coordinator: an anchored history window loads the latest page
  /// first, and a plain scroll-up just animates back to the edge.
  void _onRevealLatestRequested() {
    if (!mounted) return;
    if (!_scroll.hasClients) {
      // The pane is still laying out (a fresh selection being built), so there
      // is no viewport to move yet. Re-ask once the frame is done instead of
      // leaving a pending intent that would fire on some later scroll.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _requestReturnToLatest(userInitiated: true);
      });
      return;
    }
    _requestReturnToLatest(userInitiated: true);
  }

  void _onReturnToLatestCoordinatorChanged() {
    if (!mounted) return;
    final failure = _returnToLatestCoordinator.takeFailure();
    if (failure != null) {
      _autoScrollPolicy.allowViewportPreservation();
      if (failure.userInitiated) {
        showToast(context, AppStringKeys.topicPostContentActionFailed);
      }
    }
    _updateState(() {});
  }

  void _drainReturnToLatestIntent() {
    if (!mounted || !_scroll.hasClients) return;
    final intent = _returnToLatestCoordinator.takeReady(
      pointerDown: _hasTranscriptPointerDown,
    );
    if (intent == null) return;
    _cancelSessionScrollAnchorMaintenance();
    _stopActiveTranscriptScroll();
    _autoScrollPolicy.requestReturnToBottom();
    _setScrollTarget(null);
    if (intent.userInitiated || _liveNewMessageCount > 0) {
      _updateState(() {
        _unreadProgress.clearLiveMessages();
        _bannerDismissed = _vm.unreadCount <= 0;
      });
    }
    _transcriptViewportClaimedByUser = false;
    _scheduleScrollToBottom();
    _markReadAtBottomIfNeeded();
  }

  Future<void> _returnToJumpOrigin(_ChatJumpOrigin origin) async {
    final restoration = _restoreJumpOrigin(origin);
    final generation = _jumpOriginReturnGeneration;
    final restored = await restoration;
    // The origin's row can vanish between the tap and the layout (a paged
    // window replaced under it); keep the arrow's old contract as the fallback
    // rather than swallowing the tap.
    if (!restored && mounted && generation == _jumpOriginReturnGeneration) {
      _requestReturnToLatest(userInitiated: true);
    }
  }

  Future<bool> _restoreJumpOrigin(_ChatJumpOrigin origin) async {
    if (!mounted || !_scroll.hasClients) return false;
    if (!_vm.messages.any((message) => message.id == origin.messageId)) {
      return false;
    }
    _cancelSessionScrollAnchorMaintenance();
    _maintainRestoredBottom = false;
    _restoredPositionGuard.cancel();
    _cancelBottomFollow();
    _stopActiveTranscriptScroll();
    // A re-pivot makes raw pixels meaningless, so approach the origin with the
    // alignment fraction it had and then correct by measurement.
    final viewport = _transcriptViewportKey.currentContext?.findRenderObject();
    final viewportHeight = viewport is RenderBox && viewport.attached
        ? viewport.size.height
        : null;
    final alignment = viewportHeight == null || viewportHeight <= 0
        ? 0.0
        : (origin.viewportOffset / viewportHeight).clamp(0.0, 1.0);
    final navigation = _scrollToMessageAndReport(
      origin.messageId,
      alignment: alignment,
      forceAlignment: true,
    );
    final generation = _jumpOriginReturnGeneration;
    final reached = await navigation;
    if (!reached || !mounted || generation != _jumpOriginReturnGeneration) {
      return false;
    }
    _restoreMessageViewportOffset(origin.messageId, origin.viewportOffset);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || generation != _jumpOriginReturnGeneration) return false;
    _restoreMessageViewportOffset(origin.messageId, origin.viewportOffset);
    _saveSessionScrollSnapshot();
    return true;
  }

  void _requestReturnToLatest({bool userInitiated = false}) {
    if (!userInitiated && _hasTranscriptPointerDown) return;
    if (userInitiated) {
      // Returning to the newest message abandons the jump origin by design.
      _forgetJumpOrigin();
      _transcriptViewportClaimedByUser = false;
      _cancelSessionReopenNavigation(userClaimedViewport: true);
      _restoredPositionGuard.cancel();
      _cancelSessionScrollAnchorMaintenance();
      _cancelBottomFollow();
      _stopActiveTranscriptScroll();
      _autoScrollPolicy.requestReturnToBottom();
    }
    _returnToLatestCoordinator.request(
      userInitiated
          ? ChatReturnToLatestSource.user
          : ChatReturnToLatestSource.automatic,
    );
  }

  Future<void> _continueHistoryIfNearLatest() async {
    if (!shouldContinueAnchoredHistory(
      anchoredHistory: _vm.anchoredHistory || !_vm.historyReachesLatest,
      restoredPositionProtected: _restoredPositionGuard.blocksAutomaticReturn,
      pointerDown: _hasTranscriptPointerDown,
      hasScrollTarget: _scrollTargetId != null,
      hasScrollClients: _scroll.hasClients,
      isNearLatestEdge:
          _scroll.hasClients && isNearLatest(_scroll.position, threshold: 36),
    )) {
      return;
    }
    if (!_vm.historyReachesLatest) {
      await _vm.loadNewer();
      return;
    }
    _vm.resumeLatestHistoryIfLoaded();
    _onScroll();
  }

  void _markReadAtBottomIfNeeded() {
    if (!shouldAllowAutomaticChatRead(
          sessionReopenPending: _sessionReopenPending,
          restoredPositionProtected:
              _restoredPositionGuard.blocksAutomaticReturn,
          preservesViewport: _autoScrollPolicy.preservesViewport,
          historyReachesLatest: _vm.historyReachesLatest,
        ) ||
        !_vm.initialLoaded ||
        _vm.messages.isEmpty ||
        _vm.anchoredHistory) {
      return;
    }
    unawaited(_vm.markLoadedMessagesRead());
  }

  void _onComposerMessageSent() {
    _cancelSessionScrollAnchorMaintenance();
    _maintainRestoredBottom = false;
    _autoScrollPolicy.noteMessageSent();
    _setScrollTarget(null);
    _unreadProgress.clearLiveMessages();
    _bannerDismissed = true;
    if (_vm.anchoredHistory) {
      _requestReturnToLatest(userInitiated: true);
      return;
    }
    _scheduleScrollToBottom(userInitiated: true);
  }

  void _onComposerPanelGeometryChanged() {
    final wasNearBottom = _isNearBottom(260);
    if (!_autoScrollPolicy.shouldFollowComposerPanelChange(
      wasNearBottom: wasNearBottom,
    )) {
      return;
    }
    _setScrollTarget(null);
    _scheduleScrollToBottom(animated: false);
  }

  /// The transcript sits above the composer in a forward scroll view, so a
  /// field that wraps onto more lines shrinks the viewport from the bottom and
  /// would cover the newest message. Unlike a panel change this keeps a
  /// pending unread/linked-message jump.
  void _onComposerInputHeightChanged() {
    if (_scrollTargetId != null ||
        !_autoScrollPolicy.shouldFollowComposerPanelChange(
          wasNearBottom: _isNearBottom(260),
        )) {
      return;
    }
    _scheduleScrollToBottom(animated: false);
  }

  void _onComposerMediaSendTapped() {
    _cancelSessionScrollAnchorMaintenance();
    _maintainRestoredBottom = false;
    _autoScrollPolicy.requestReturnToBottom();
    _setScrollTarget(null);
    if (_vm.anchoredHistory) {
      _requestReturnToLatest(userInitiated: true);
      return;
    }
    _scheduleScrollToBottom(animated: false, userInitiated: true);
  }

  void _playMusicMessage(ChatMessage message) {
    unawaited(
      MusicPlayerController.shared.playChat(
        message,
        widget.chatId,
        title: widget.title,
      ),
    );
  }

  void _sendCommand(String command) {
    if (!_vm.sendCommand(command)) return;
    _onComposerMessageSent();
  }

  void _sendKeyboardButtonText(String text) {
    if (!_vm.sendKeyboardButtonText(text)) return;
    _onComposerMessageSent();
  }

  void _sendBotStart() {
    if (!_vm.sendBotStart()) return;
    _onComposerMessageSent();
  }

  void _captureEntryUnreadState() {
    _entryUnreadCount = _vm.unreadCount;
    _entryLastReadInboxId = _vm.lastReadInboxId;
    _entryLatestMessageId = resolveCapturedEntryLatestMessageId(
      knownLatestMessageId: _vm.knownLatestMessageId,
      loadedLatestMessageId: _latestServerMessage(_vm.messages)?.id ?? 0,
    );
  }

  bool _isEntryUnreadMessage(int messageId) => isCapturedEntryUnreadMessage(
    messageId: messageId,
    lastReadInboxId: _entryLastReadInboxId,
    latestMessageId: _entryLatestMessageId,
  );

  int? _firstLoadedEntryUnreadMessageId() => firstUnreadMessageIdAfterBoundary(
    incomingMessageIds: _vm.messages
        .where(
          (message) =>
              !message.isOutgoing &&
              !message.isService &&
              _isEntryUnreadMessage(message.id),
        )
        .map((message) => message.id),
    lastReadInboxId: _entryLastReadInboxId,
  );

  /// Jump to the unread boundary captured when the chat opened. The live TDLib
  /// boundary may already point at the newest message after the chat is marked
  /// read, so it cannot be used to resolve this button later.
  Future<void> _jumpToFirstUnread() async {
    // Choosing a different destination drops the recorded jump origin.
    _forgetJumpOrigin();
    _claimTranscriptViewport();
    await _jumpToFirstUnreadImpl();
  }

  Future<bool> _jumpToFirstUnreadForSession(int generation) =>
      _jumpToFirstUnreadImpl(sessionReopenGeneration: generation);

  Future<bool> _jumpToFirstUnreadImpl({int? sessionReopenGeneration}) async {
    final gestureGeneration = _transcriptGestureGeneration;

    bool isCancelled() =>
        _transcriptGestureGeneration != gestureGeneration ||
        (sessionReopenGeneration != null &&
            !_sessionReopenNavigationGuard.isCurrent(sessionReopenGeneration));

    if (isCancelled()) return false;
    var targetMessageId = _entryFirstUnreadMessageId;
    final entryBoundaryId = _entryLastReadInboxId;
    _cancelSessionScrollAnchorMaintenance();
    _cancelBottomFollow();
    _autoScrollPolicy.noteUserScroll(
      towardOlderMessages: true,
      isAtBottom: false,
    );
    _updateState(() {
      _unreadProgress.clearLiveMessages();
      _showEntryUnreadBanner = false;
      _bannerDismissed = true;
    });

    if (targetMessageId == null && entryBoundaryId > 0) {
      _updateState(() => _setScrollTarget(entryBoundaryId));
      await _vm.loadAroundMessage(
        entryBoundaryId,
        scrollToTarget: false,
        isCancelled: isCancelled,
      );
      if (!mounted || isCancelled()) return false;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || isCancelled()) return false;
      targetMessageId = _firstLoadedEntryUnreadMessageId();
      if (targetMessageId == null &&
          _vm.messages.any((message) => message.id == entryBoundaryId)) {
        targetMessageId = entryBoundaryId;
      }
    }

    // With a zero boundary (for example, a never-opened channel), TDLib has no
    // concrete message to page around. Moving to the oldest loaded unread
    // message still gives the control a useful, deterministic upward action.
    targetMessageId ??= _firstLoadedEntryUnreadMessageId();
    if (targetMessageId == null) {
      if (_scrollTargetId != null) _updateState(() => _setScrollTarget(null));
      return false;
    }
    _entryFirstUnreadMessageId = targetMessageId;
    final didReachTarget = await _scrollToMessageAndReport(
      targetMessageId,
      alignment: _ChatViewState._initialUnreadAlignment,
      forceAlignment: true,
      alignUnreadDivider: _isEntryUnreadMessage(targetMessageId),
      isCancelled: isCancelled,
    );
    return didReachTarget && !isCancelled();
  }

  void _scheduleSendFailureDialog(ChatSendFailure failure) {
    _sendFailureDialogVisible = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _sendFailureDialogVisible = false;
        return;
      }
      unawaited(_showSendFailureDialog(failure));
    });
  }

  Future<void> _showSendFailureDialog(ChatSendFailure failure) async {
    final message = switch (failure.kind) {
      ChatSendFailureKind.paidMessageRequired
          when failure.paidMessageStarCount > 0 =>
        AppStrings.t(AppStringKeys.chatSendFailedPaidCount, {
          'value1': failure.paidMessageStarCount,
        }),
      ChatSendFailureKind.paidMessageRequired => AppStrings.t(
        AppStringKeys.chatSendFailedPaid,
      ),
      ChatSendFailureKind.insufficientStars => AppStrings.t(
        AppStringKeys.chatSendFailedInsufficientStars,
      ),
      ChatSendFailureKind.premiumRequired => AppStrings.t(
        AppStringKeys.chatSendFailedPremium,
      ),
      ChatSendFailureKind.mutualContactRequired => AppStrings.t(
        AppStringKeys.chatSendFailedMutualContact,
      ),
      ChatSendFailureKind.privacyRestricted => AppStrings.t(
        AppStringKeys.chatSendFailedPrivacy,
      ),
      ChatSendFailureKind.blocked => AppStrings.t(
        AppStringKeys.chatSendFailedBlocked,
      ),
      ChatSendFailureKind.chatPermissionDenied => AppStrings.t(
        AppStringKeys.chatSendFailedPermission,
      ),
      ChatSendFailureKind.recipientUnavailable => AppStrings.t(
        AppStringKeys.chatSendFailedUnavailable,
      ),
      ChatSendFailureKind.rateLimited => AppStrings.t(
        AppStringKeys.chatSendFailedRateLimited,
      ),
      ChatSendFailureKind.generic => AppStrings.t(
        AppStringKeys.chatSendFailedGeneric,
        {'value1': failure.technicalMessage},
      ),
    };
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppStrings.t(AppStringKeys.confirmOk),
      barrierColor: Colors.black.withValues(alpha: 0.52),
      transitionDuration: AppMotion.duration(context, AppMotion.responsive),
      transitionBuilder: AppMotion.dialogTransition,
      pageBuilder: (dialogContext, _, _) => AppDialogSurface(
        title: AppStrings.t(AppStringKeys.chatSendFailedTitle),
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: AppTextStyle.body(
            dialogContext.colors.textSecondary,
          ).copyWith(height: 1.4),
        ),
        actions: [
          AppDialogAction(
            label: AppStrings.t(AppStringKeys.confirmOk),
            primary: true,
            onTap: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _sendFailureDialogVisible = false;
    final nextFailure = _vm.consumeSendFailure();
    if (nextFailure != null) _scheduleSendFailureDialog(nextFailure);
  }

  void _resolveRestoredSessionEntry() {
    if (_sessionReopenDispositionResolved ||
        _sessionReopenResolutionInFlight ||
        !_vm.chatReadStateLoaded) {
      return;
    }
    final snapshot = _sessionScrollSnapshot;
    if (snapshot == null) {
      _sessionReopenDispositionResolved = true;
      return;
    }
    _sessionReopenResolutionInFlight = true;
    final generation = _sessionReopenNavigationGuard.begin();
    final readStateRevision = _vm.chatReadStateRevision;
    unawaited(
      _resolveRestoredSessionEntryAsync(
        snapshot: snapshot,
        generation: generation,
        readStateRevision: readStateRevision,
      ),
    );
  }

  Future<void> _resolveRestoredSessionEntryAsync({
    required _ChatScrollSnapshot snapshot,
    required int generation,
    required int readStateRevision,
  }) async {
    // TDLib can deliver updateNewMessage and the paired unread-count update as
    // separate events. Let the current event batch settle, then retry whenever
    // either boundary changes during the read-only confirmation probe.
    await Future<void>.delayed(Duration.zero);
    if (!mounted || !_sessionReopenNavigationGuard.isCurrent(generation)) {
      return;
    }
    if (_vm.chatReadStateRevision != readStateRevision) {
      _sessionReopenResolutionInFlight = false;
      _resolveRestoredSessionEntry();
      return;
    }
    final confirmedUnreadMessageId = await _vm
        .confirmedNewIncomingUnreadSinceSession(
          savedKnownLatestMessageId: snapshot.knownLatestMessageId,
          expectedReadStateRevision: readStateRevision,
        );
    if (!mounted || !_sessionReopenNavigationGuard.isCurrent(generation)) {
      return;
    }
    if (_vm.chatReadStateRevision != readStateRevision) {
      _sessionReopenResolutionInFlight = false;
      _resolveRestoredSessionEntry();
      return;
    }

    _sessionReopenResolutionInFlight = false;
    _sessionReopenDispositionResolved = true;
    final prioritizeUnread = shouldPrioritizeUnreadOnChatReopen(
      currentUnreadCount: _vm.unreadCount,
      currentLastReadInboxId: _vm.lastReadInboxId,
      savedAnchorMessageId: snapshot.anchorMessageId,
      hasConfirmedNewUnread: confirmedUnreadMessageId != null,
    );
    final disposition = resolveChatReopenDisposition(
      hasExplicitTarget: widget.initialMessageId != null,
      hasSavedPosition: true,
      prioritizeUnread: prioritizeUnread,
    );
    if (disposition != ChatReopenDisposition.firstUnread) return;

    _prioritizingSessionUnread = true;
    _maintainRestoredBottom = false;
    _restoredPositionGuard.cancel();
    _cancelSessionScrollAnchorMaintenance();
    _cancelBottomFollow();
    _stopActiveTranscriptScroll();
    _resetTranscriptPivot();
    _captureEntryUnreadState();
    _entryFirstUnreadMessageId = _entryLastReadInboxId == 0
        ? confirmedUnreadMessageId
        : _firstLoadedEntryUnreadMessageId();
    var jumped = false;
    try {
      jumped = await _jumpToFirstUnreadForSession(generation);
    } catch (_) {
      jumped = false;
    }
    if (!mounted || !_sessionReopenNavigationGuard.isCurrent(generation)) {
      return;
    }
    _prioritizingSessionUnread = false;
    if (jumped) {
      _preserveSnapshotAfterFailedSessionJump = false;
      _ChatViewState._sessionScrollSnapshots.remove(_sessionKey);
      _saveSessionScrollSnapshot();
    } else {
      _preserveSnapshotAfterFailedSessionJump = true;
    }
  }

  void _onModel() {
    if (!mounted) return;
    final nextFullViewRevision = _vm.fullViewRevision;
    final requiresFullViewSync = chatViewRequiresFullSync(
      previousRevision: _fullViewRevision,
      nextRevision: nextFullViewRevision,
    );
    if (!chatViewSyncsModelNotification(
      viewTickerEnabled: _viewTickerEnabled,
      exitStatePrepared: _exitStatePrepared,
    )) {
      // A covered transcript still owes the sync once it is visible again; one
      // that is on its way out never does.
      if (!_viewTickerEnabled && requiresFullViewSync) {
        _modelDirtyWhileInactive = true;
      }
      return;
    }
    if (!requiresFullViewSync) return;
    _fullViewRevision = nextFullViewRevision;
    _syncProtectedContentSelectionState();
    _reportChatKindIfReady();
    _modelDirtyWhileInactive = false;
    _scheduleHandoffRefresh();
    if (!_sendFailureDialogVisible) {
      final failure = _vm.consumeSendFailure();
      if (failure != null) _scheduleSendFailureDialog(failure);
    }
    _resolveRestoredSessionEntry();
    final olderLoadFinished = _wasLoadingOlder && !_vm.isLoadingOlder;
    _wasLoadingOlder = _vm.isLoadingOlder;
    final oldest = _oldestServerMessage(_vm.messages);
    final previousOldestId = _lastOldestMessageId;
    final prependedOlder =
        oldest != null &&
        previousOldestId != null &&
        oldest.id < previousOldestId;
    // _isTranscriptShort walks every cached entry; nothing below moves the
    // scroll position or the pivot, so one measurement serves all three tests.
    final latestArmIsShort = _isTranscriptShort();
    final hasPendingMessageTarget =
        _scrollTargetId != null ||
        widget.initialMessageId != null ||
        (_didInitialScroll && !_initialTranscriptReady);
    final hydratedShortTranscript = shouldRebaseForHydratedOlderPage(
      prependedOlder: prependedOlder,
      latestArmWasShort: latestArmIsShort,
      historyFillInFlight: _isFillingShortTranscript || _loadingOlderFromScroll,
      revealRequested: _revealLoadedOlderPage,
      hasPendingMessageTarget: hasPendingMessageTarget,
    );
    final followingLatest = transcriptFollowsLatestEdge(
      preservesViewport: _autoScrollPolicy.preservesViewport,
      maintainsSessionAnchor: _maintainSessionScrollAnchor,
      viewportClaimedByUser: _transcriptViewportClaimedByUser,
      hasPendingMessageTarget: hasPendingMessageTarget,
    );
    final hasMessageOlderThanPivot =
        _transcriptPivot != null &&
        _vm.messages.any(
          (message) =>
              _transcriptOrderId(message) < _transcriptPivot!.cutoffMessageId,
        );
    final expandedInitialWindow = shouldRebaseForExpandedInitialWindow(
      transcriptChanged: !identical(_transcriptCacheMessages, _vm.messages),
      latestArmIsShort: latestArmIsShort,
      hasMessageOlderThanPivot: hasMessageOlderThanPivot,
      followingLatest: followingLatest,
      viewportClaimedByUser: _transcriptViewportClaimedByUser,
    );
    final parkedShortArm = shouldRebaseParkedShortTranscriptPivot(
      pivotCutoffMessageId: _transcriptPivot?.cutoffMessageId,
      latestArmIsShort: latestArmIsShort,
      hasMessageOlderThanPivot: hasMessageOlderThanPivot,
      followingLatest: followingLatest,
      viewportClaimedByUser: _transcriptViewportClaimedByUser,
    );
    final wasPinnedToLoadedBottom =
        _initialTranscriptReady &&
        !_hasTranscriptPointerDown &&
        !_isUserScrolling &&
        !_transcriptViewportClaimedByUser &&
        !_autoScrollPolicy.preservesViewport &&
        _scrollTargetId == null &&
        _isAtLoadedBottom(2);
    final historyWindowInvalidated =
        _historyWindowInvalidationRevision !=
        _vm.historyWindowInvalidationRevision;
    _historyWindowInvalidationRevision = _vm.historyWindowInvalidationRevision;
    if (_historyWindowRevision != _vm.historyWindowRevision) {
      _historyWindowRevision = _vm.historyWindowRevision;
      final preservesSavedCoordinate =
          shouldPreserveChatSessionAnchorAcrossWindowChange(
            anchorMaintenanceActive: _maintainSessionScrollAnchor,
            hasSavedPivot: _sessionScrollSnapshot?.pivotMessageId != null,
            historyWindowInvalidated: historyWindowInvalidated,
          );
      if (!preservesSavedCoordinate) {
        _cancelSessionScrollAnchorMaintenance();
        _cancelBottomFollow();
        _stopActiveTranscriptScroll();
        _resetTranscriptPivot();
      }
      if (historyWindowInvalidated) {
        _maintainRestoredBottom = false;
        _olderHistoryExhaustedHint = true;
        _transcriptViewportClaimedByUser = false;
        _showingFullyVisibleFirstContactHistory = false;
        _autoScrollPolicy.returnToBottom();
        _ChatViewState._sessionScrollSnapshots.remove(_sessionKey);
      } else if (!preservesSavedCoordinate) {
        _olderHistoryExhaustedHint = false;
      }
    }
    // The server-message scan only matters for a pending cutoff; as an argument
    // it ran on every notification.
    if (_transcriptPivot?.cutoffMessageId ==
            _ChatViewState._pendingTranscriptOrderId &&
        shouldRebasePendingTranscriptPivot(
          pivot: _transcriptPivot,
          pendingOrderId: _ChatViewState._pendingTranscriptOrderId,
          hasServerMessage: _vm.messages.any(
            (message) => !isPendingChatMessage(message) && message.id > 0,
          ),
        )) {
      _resetTranscriptPivot();
    }
    final shouldResetParkedPivot =
        parkedShortArm ||
        expandedInitialWindow ||
        hydratedShortTranscript ||
        (!_transcriptPivotFrozen &&
            !hasPendingMessageTarget &&
            _vm.initialLoaded &&
            !identical(_transcriptCacheMessages, _vm.messages));
    if (shouldResetParkedPivot) {
      // Cold local pages may be followed by a larger remote hydration. Until
      // the latest arm fills a viewport (or the user scrolls), let that fuller
      // initial window establish the fixed cutoff. Also unpark a frozen newest
      // pivot that already has older messages sitting in before-center.
      _resetTranscriptPivot();
    }
    final rebasedParkedShortArm = parkedShortArm || expandedInitialWindow;
    final liveIncomingMessageIds = _vm.consumeLiveIncomingMessageIds();
    final newest = _latestServerMessage(_vm.messages);
    final transcriptBoundaryChanged = chatTranscriptBoundaryChanged(
      previousCount: _lastCount,
      currentCount: _vm.messages.length,
      previousNewestMessageId: _lastNewestMessageId,
      currentNewestMessageId: newest?.id,
      previousOldestMessageId: _lastOldestMessageId,
      currentOldestMessageId: oldest?.id,
      hasBufferedLiveMessages: liveIncomingMessageIds.isNotEmpty,
    );
    if (transcriptBoundaryChanged) {
      final wasNearBottom = _isNearBottom(72);
      final previousNewestId = _lastNewestMessageId;
      final appendedNewest =
          newest != null &&
          newest.id != previousNewestId &&
          (newest.isOutgoing ||
              previousNewestId == null ||
              newest.id > previousNewestId);
      final appendedIncomingIds = appendedLiveIncomingMessageIds(
        previousNewestMessageId: previousNewestId,
        liveIncomingMessageIds: liveIncomingMessageIds,
        currentMessageIds: _vm.messages.map((message) => message.id),
      );
      if (prependedOlder && _revealLoadedOlderPage) {
        _revealLoadedOlderPage = false;
        if (_transcriptGestureGeneration ==
            _loadedOlderRevealGestureGeneration) {
          _loadedOlderRevealPending = true;
          _scheduleLoadedOlderReveal();
        }
      }
      _lastCount = _vm.messages.length;
      _lastNewestMessageId = newest?.id ?? _lastNewestMessageId;
      _lastOldestMessageId = oldest?.id ?? _lastOldestMessageId;
      final shouldAutoScroll =
          _initialTranscriptReady &&
          _scrollTargetId == null &&
          !_vm.anchoredHistory &&
          appendedNewest &&
          !_hasTranscriptPointerDown &&
          !_transcriptViewportClaimedByUser &&
          !_isUserScrolling &&
          _autoScrollPolicy.shouldFollowAppendedMessage(
            wasNearBottom: wasNearBottom,
          );
      if (shouldAutoScroll) {
        _unreadProgress.clearLiveMessages();
        _scheduleScrollToBottom(animated: newest.isOutgoing);
      } else if (_didInitialScroll &&
          appendedNewest &&
          appendedIncomingIds.isNotEmpty &&
          (_hasTranscriptPointerDown ||
              _isUserScrolling ||
              _autoScrollPolicy.preservesViewport ||
              !wasNearBottom ||
              !_isAtLoadedBottom(1))) {
        _unreadProgress.addLiveMessages(appendedIncomingIds);
        _bannerDismissed = false;
        _bannerTimer?.cancel();
        _bannerTimer = null;
      }
    }
    if (olderLoadFinished && _revealLoadedOlderPage) {
      _revealLoadedOlderPage = false;
    }
    final target = _vm.consumePendingScrollToId();
    if (target != null) {
      _setScrollTarget(target, forceNavigation: true);
      final navigationGeneration = _scrollTargetGeneration;
      if (_initialTranscriptReady) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              !_isCurrentScrollTarget(target, navigationGeneration)) {
            return;
          }
          unawaited(
            _ensureMessageVisible(
              target,
              navigationGeneration: navigationGeneration,
            ),
          );
        });
      }
    }
    // Telegram-style entry: once the initial history (incl. the unread
    // boundary) is loaded, jump to the first unread message — or stay at the
    // bottom when caught up. Runs exactly once per chat open.
    if (!_didInitialScroll && _vm.initialLoaded) {
      _captureEntryUnreadState();
      final firstEntryUnreadMessageId = _firstLoadedEntryUnreadMessageId();
      final loadedIncomingUnreadCount = _vm.messages
          .where(
            (message) =>
                !message.isOutgoing &&
                !message.isService &&
                _isEntryUnreadMessage(message.id),
          )
          .length;
      final entryBoundaryIsLoaded =
          _entryLastReadInboxId > 0 &&
          _vm.messages.isNotEmpty &&
          _vm.messages.first.id <= _entryLastReadInboxId;
      final entireUnreadRangeIsLoaded =
          _entryUnreadCount > 0 &&
          loadedIncomingUnreadCount >= _entryUnreadCount;
      _entryFirstUnreadMessageId =
          entryBoundaryIsLoaded || entireUnreadRangeIsLoaded
          ? firstEntryUnreadMessageId
          : null;
      _showEntryUnreadBanner = _openAtLatest && _entryUnreadCount > 0;
      _didInitialScroll = true;
      if (_vm.messages.isEmpty) {
        _initialTranscriptReady = true;
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_completeInitialScroll());
        });
      }
    } else if (_vm.initialLoaded && _vm.messages.isNotEmpty) {
      _scheduleShortTranscriptFill();
    }
    // Keep the entry unread banner visible; only live-new-message banners
    // auto-hide after a short delay. (Each new live message cancels the
    // timer, so the countdown restarts from the latest arrival.)
    if (_liveNewMessageCount > 0 && _bannerTimer == null && !_bannerDismissed) {
      _bannerTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) _updateState(() => _bannerDismissed = true);
      });
    }
    if ((wasPinnedToLoadedBottom || rebasedParkedShortArm) &&
        !_transcriptViewportClaimedByUser &&
        !_bottomScrollScheduled) {
      _scheduleScrollToBottom(animated: false);
    }
    _scheduleChatLanguageDetection();
    _scheduleAutomaticTranslations();
    _updateState(() {});
    _cacheCurrentTranscript();
    _scheduleSessionScrollAnchorMaintenance();
    _scheduleRestoredBottomCorrection();
    _scheduleParkedShortTranscriptRepair();
  }

  void _reportChatKindIfReady() {
    final kind = _vm.chatKind;
    final callback = widget.onChatKindResolved;
    if (kind == null || callback == null || kind == _reportedChatKind) return;
    _reportedChatKind = kind;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _vm.chatKind != kind) return;
      widget.onChatKindResolved?.call(kind);
    });
  }

  bool _isCurrentScrollTarget(int messageId, int navigationGeneration) =>
      _scrollTargetId == messageId &&
      _scrollTargetGeneration == navigationGeneration;

  void _invalidateScrollNavigation() {
    if (_scrollTargetId != null) {
      _setScrollTarget(null);
    } else {
      ++_scrollTargetGeneration;
    }
  }

  void _setScrollTarget(int? messageId, {bool forceNavigation = false}) {
    if (forceNavigation) ++_jumpOriginReturnGeneration;
    if (forceNavigation || _scrollTargetId != messageId) {
      ++_scrollTargetGeneration;
    }
    if (messageId != null) {
      _restoredPositionGuard.cancel();
      _returnToLatestCoordinator.cancel();
      _maintainRestoredBottom = false;
      _cancelSessionScrollAnchorMaintenance();
      _cancelBottomFollow();
      _stopActiveTranscriptScroll();
    }
    _scrollTargetId = messageId;
  }

  /// Makes an arbitrary loaded target the first child after the scroll view's
  /// center sliver, so Flutter lays it out without depending on guessed row
  /// heights. The transcript keeps the same chronological order on both sides
  /// of the new pivot; only its zero scroll coordinate moves to the target.
  bool _stageMessageAtTranscriptCenter(int messageId) {
    if (!_scroll.hasClients) return false;
    ChatMessage? target;
    for (final message in _vm.messages) {
      if (message.id == messageId) {
        target = message;
        break;
      }
    }
    if (target == null) return false;

    final cutoff = _transcriptOrderId(target);
    if (_transcriptPivot?.cutoffMessageId != cutoff ||
        !_transcriptPivotFrozen) {
      _updateState(() {
        _transcriptPivot = TranscriptPivot(cutoff);
        // Async sender, preview, and media hydration must not reset the pivot
        // before the target's final alignment passes have completed.
        _transcriptPivotFrozen = true;
      });
    }
    _scroll.jumpTo(clampScrollOffset(_scroll.position, 0));
    return true;
  }

  void _cancelSessionScrollAnchorMaintenance() {
    _maintainSessionScrollAnchor = false;
  }

  void _scheduleRestoredBottomCorrection() {
    if (!_maintainRestoredBottom) return;
    if (_vm.anchoredHistory || _scrollTargetId != null) {
      _maintainRestoredBottom = false;
      return;
    }
    _restoredBottomCorrection.schedule(
      enabled: _maintainRestoredBottom,
      schedulePostFrame: (callback) {
        WidgetsBinding.instance.addPostFrameCallback((_) => callback());
      },
      canCorrect: () =>
          mounted &&
          _maintainRestoredBottom &&
          !_hasTranscriptPointerDown &&
          !_transcriptViewportClaimedByUser &&
          !_vm.anchoredHistory &&
          _scrollTargetId == null &&
          _scroll.hasClients,
      correct: _scrollToBottom,
    );
  }

  void _scheduleSessionScrollAnchorMaintenance() {
    if (!_maintainSessionScrollAnchor ||
        !_initialTranscriptReady ||
        _sessionAnchorMaintenanceScheduled) {
      return;
    }
    final snapshot = _sessionScrollSnapshot;
    if (snapshot == null) return;
    _sessionAnchorMaintenanceScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sessionAnchorMaintenanceScheduled = false;
      if (!mounted ||
          !_maintainSessionScrollAnchor ||
          !_scroll.hasClients ||
          _transcriptViewportClaimedByUser ||
          _scrollTargetId != null) {
        return;
      }
      if (_hasTranscriptPointerDown) return;
      _restoreSessionScrollAnchor(snapshot);
    });
  }

  int _firstUnreadIndex() => _vm.messages.indexWhere(
    (m) => !m.isOutgoing && !m.isService && _isEntryUnreadMessage(m.id),
  );

  /// One-time positioning when a chat opens. This must never block painting:
  /// a hidden transcript reads as a black screen in dark mode. We jump to the
  /// deterministic estimate immediately and then do one zero-duration correction
  /// after layout, without waiting to reveal the UI.
  Future<void> _completeInitialScroll() async {
    // Opening (or reopening) the session establishes a fresh reading position;
    // an origin from a previous visit of this state must not survive it.
    _forgetJumpOrigin();
    if (_shouldRestoreSessionScroll) {
      await _restoreSessionScrollPosition();
    } else {
      await _positionInitialTranscript();
    }
    if (!mounted) return;
    if (_initialTranscriptPositioningAborted) {
      _updateState(() => _initialTranscriptReady = true);
      return;
    }
    final shortUnreadTail =
        _initialViewportTarget().kind ==
            ChatInitialViewportTargetKind.firstUnread &&
        _vm.historyReachesLatest &&
        _isTranscriptShort();
    if (_repairParkedShortTranscriptPivot()) {
      // Rebuild the rebased slivers before correcting their scroll coordinates.
      // Waiting for a frame alone leaves the old center layout in place.
      _updateState(() {});
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      if (_initialTranscriptPositioningAborted) {
        _updateState(() => _initialTranscriptReady = true);
        return;
      }
      if (_canFollowLoadedBottom() || shortUnreadTail) _scrollToBottom();
      if (shortUnreadTail) {
        // Finish the short unread tail's bottom alignment before revealing it.
        // Rebasing a one-row center otherwise exposes empty space, then the
        // first gesture repairs it with a sudden jump to the newest message.
        for (var pass = 0; pass < 3; pass++) {
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted || _initialTranscriptPositioningAborted) return;
          _scrollToBottom();
        }
      }
    }
    if (!mounted) return;
    _updateState(() => _initialTranscriptReady = true);
    _saveSessionScrollSnapshot();
    _scheduleShortTranscriptFill();
  }

  Future<void> _restoreSessionScrollPosition() async {
    final snapshot = _sessionScrollSnapshot;
    if (snapshot == null ||
        !_scroll.hasClients ||
        _initialTranscriptPositioningAborted) {
      return;
    }
    if (_hasSessionScrollAnchor) {
      final anchorMessageId = snapshot.anchorMessageId!;
      for (var attempt = 0; attempt < 4; attempt++) {
        if (_initialTranscriptPositioningAborted) return;
        if (_restoreSessionScrollAnchor(snapshot)) {
          await WidgetsBinding.instance.endOfFrame;
          if (mounted &&
              _scroll.hasClients &&
              !_initialTranscriptPositioningAborted) {
            _restoreSessionScrollAnchor(snapshot);
          }
          return;
        }
        final estimate = _estimateMessageOffset(anchorMessageId, 0);
        if (estimate != null) _scroll.jumpTo(estimate);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted ||
            !_scroll.hasClients ||
            _initialTranscriptPositioningAborted) {
          return;
        }
      }
      // A transcript can be evicted before its independently stored scroll
      // anchor. Raw pixels belong to that old centered window, so never apply
      // them to a new window (or one that no longer contains the anchor).
      final hasMatchingCachedWindow = _sessionRenderState != null;
      final anchorStillLoaded = _vm.messages.any(
        (message) => message.id == anchorMessageId,
      );
      if (!hasMatchingCachedWindow || !anchorStillLoaded) {
        await _invalidateSessionSnapshotAndPositionCold();
        return;
      }
    }
    if (_sessionRenderState == null) {
      await _invalidateSessionSnapshotAndPositionCold();
      return;
    }
    if (_initialTranscriptPositioningAborted) return;
    _jumpToSessionScrollSnapshot(snapshot);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
        !_scroll.hasClients ||
        _initialTranscriptPositioningAborted) {
      return;
    }

    var guard = 0;
    while (mounted &&
        _scroll.hasClients &&
        !_initialTranscriptPositioningAborted &&
        _vm.canLoadOlder &&
        snapshot.pixels + 24 < _scroll.position.minScrollExtent &&
        guard < 6) {
      final loaded = await _vm.loadOlderLocal();
      if (!loaded) break;
      await WidgetsBinding.instance.endOfFrame;
      if (_initialTranscriptPositioningAborted) return;
      guard++;
    }

    if (!mounted ||
        !_scroll.hasClients ||
        _initialTranscriptPositioningAborted) {
      return;
    }
    _jumpToSessionScrollSnapshot(snapshot);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
        !_scroll.hasClients ||
        _initialTranscriptPositioningAborted) {
      return;
    }
    _jumpToSessionScrollSnapshot(snapshot);
    _saveSessionScrollSnapshot();
  }

  Future<void> _invalidateSessionSnapshotAndPositionCold() async {
    _ChatViewState._sessionScrollSnapshots.remove(_sessionKey);
    _sessionScrollSnapshot = null;
    _cancelSessionReopenNavigation(userClaimedViewport: true);
    _maintainSessionScrollAnchor = false;
    _restoredPositionGuard.cancel();
    if (_openAtLatest) {
      _autoScrollPolicy.returnToBottom();
    } else {
      _autoScrollPolicy.allowViewportPreservation();
    }
    _resetTranscriptPivot();
    await _positionInitialTranscript();
  }

  bool _restoreSessionScrollAnchor(_ChatScrollSnapshot snapshot) {
    final messageId = snapshot.anchorMessageId;
    final desiredOffset = snapshot.anchorViewportOffset;
    if (messageId == null || desiredOffset == null) return false;
    return _restoreMessageViewportOffset(messageId, desiredOffset);
  }

  /// Puts [messageId] back at [desiredOffset] pixels below the transcript
  /// viewport top, measured rather than replayed as raw pixels: the row may sit
  /// in a different sliver window than it did when the offset was recorded.
  bool _restoreMessageViewportOffset(int messageId, double desiredOffset) {
    if (!_scroll.hasClients) return false;
    final viewportContext = _transcriptViewportKey.currentContext;
    final itemContext = _entryVisibilityKeys[messageId]?.currentContext;
    final viewportRenderObject = viewportContext?.findRenderObject();
    final itemRenderObject = itemContext?.findRenderObject();
    if (viewportRenderObject is! RenderBox ||
        !viewportRenderObject.attached ||
        itemRenderObject is! RenderBox ||
        !itemRenderObject.attached) {
      return false;
    }
    final viewportTop = viewportRenderObject.localToGlobal(Offset.zero).dy;
    final itemTop = itemRenderObject.localToGlobal(Offset.zero).dy;
    final position = _scroll.position;
    final target = correctedChatSessionScrollOffset(
      currentPixels: position.pixels,
      currentAnchorViewportOffset: itemTop - viewportTop,
      savedAnchorViewportOffset: desiredOffset,
      minScrollExtent: position.minScrollExtent,
      maxScrollExtent: position.maxScrollExtent,
    );
    _scroll.jumpTo(target);
    return true;
  }

  void _jumpToSessionScrollSnapshot(_ChatScrollSnapshot snapshot) {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final target = clampScrollOffset(pos, snapshot.pixels);
    _scroll.jumpTo(target);
  }

  Future<void> _positionInitialTranscript() async {
    if (!_scroll.hasClients || _initialTranscriptPositioningAborted) return;
    // Build the resolved unread row before aligning it. Height estimates can
    // skip it entirely in channels with long posts and mixed media.
    final decision = _initialViewportTarget();
    final initialTarget = decision.messageId;
    if (initialTarget != null &&
        (decision.kind == ChatInitialViewportTargetKind.message ||
            decision.kind == ChatInitialViewportTargetKind.readBoundary)) {
      _updateState(() => _setScrollTarget(initialTarget));
    }
    if (initialTarget == null ||
        !_stageMessageAtTranscriptCenter(initialTarget)) {
      _jumpToInitialEstimate();
    }
    var corrected = false;
    for (var i = 0; i < 3; i++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          !_scroll.hasClients ||
          _initialTranscriptPositioningAborted) {
        return;
      }
      corrected = await _correctInitialPosition() || corrected;
      if (_initialTranscriptPositioningAborted) return;
    }
    // Keep one target key through every alignment pass. Clearing it inside
    // the loop leaves later passes pointing at a key that was never built.
    if (corrected && mounted && _scrollTargetId == initialTarget) {
      _updateState(() => _setScrollTarget(null));
    }
  }

  void _jumpToInitialEstimate() {
    if (!_scroll.hasClients || _vm.messages.isEmpty) return;
    final position = _initialPositionEstimate();
    if (position == null) return;
    _scroll.jumpTo(position);
  }

  double? _initialPositionEstimate() {
    if (!_scroll.hasClients || _vm.messages.isEmpty) return null;
    final max = _scroll.position.maxScrollExtent;
    final decision = _initialViewportTarget();
    return switch (decision.kind) {
      ChatInitialViewportTargetKind.message ||
      ChatInitialViewportTargetKind.readBoundary => () {
        final target = decision.messageId!;
        _setScrollTarget(target);
        return _estimateMessageOffset(
          target,
          _ChatViewState._initialTargetAlignment,
        );
      }(),
      ChatInitialViewportTargetKind.firstUnread => _estimateMessageOffset(
        decision.messageId!,
        _ChatViewState._initialUnreadAlignment,
        beforeUnreadDivider: true,
      ),
      ChatInitialViewportTargetKind.loadedBottom => max,
      ChatInitialViewportTargetKind.preserveAnchoredHistory => null,
    };
  }

  Future<bool> _correctInitialPosition() async {
    if (!_scroll.hasClients || _initialTranscriptPositioningAborted) {
      return false;
    }
    final decision = _initialViewportTarget();
    switch (decision.kind) {
      case ChatInitialViewportTargetKind.message:
      case ChatInitialViewportTargetKind.readBoundary:
        final target = decision.messageId!;
        _setScrollTarget(target);
        final corrected = await _ensureKeyVisible(
          _targetKey,
          alignment: _ChatViewState._initialTargetAlignment,
        );
        if (_initialTranscriptPositioningAborted) return false;
        return corrected;
      case ChatInitialViewportTargetKind.firstUnread:
        return _ensureKeyVisible(
          _unreadKey,
          alignment: _ChatViewState._initialUnreadAlignment,
        );
      case ChatInitialViewportTargetKind.loadedBottom:
        _scrollToBottom();
        _markReadAtBottomIfNeeded();
        return true;
      case ChatInitialViewportTargetKind.preserveAnchoredHistory:
        return true;
    }
  }

  Future<bool> _ensureKeyVisible(
    GlobalKey key, {
    required double alignment,
  }) async {
    final ctx = key.currentContext;
    if (ctx == null || !ctx.mounted) return false;
    await Scrollable.ensureVisible(ctx, alignment: alignment);
    return true;
  }

  double? _estimateMessageOffset(
    int messageId,
    double alignment, {
    bool beforeUnreadDivider = false,
  }) {
    final entries = _transcriptEntries(
      context.read<ThemeController>().groupImageMessages,
    );
    if (entries.isEmpty || !_scroll.hasClients) return null;
    _TranscriptEntry? targetEntry;
    for (final entry in entries) {
      if (entry.messages.any((message) => message.id == messageId)) {
        targetEntry = entry;
        break;
      }
    }
    if (targetEntry == null) return null;
    // The visibility retry loop calls this up to six times in a row, so it
    // reuses the partition and key indexes _transcript() already cached rather
    // than repartitioning the whole entry list and rescanning it per attempt.
    // `older` holds beforePivot reversed, which is why it is walked forwards.
    final List<_TranscriptEntry> older;
    final List<_TranscriptEntry> newer;
    final int olderIndex;
    final int newerIndex;
    if (identical(entries, _sliverCacheEntries) &&
        identical(_transcriptPivot, _sliverCachePivot) &&
        _sliverCacheInitialLoaded == _vm.initialLoaded &&
        _sliverCacheLeadingItemCount >= 0) {
      older = _sliverCacheOlderEntries!;
      newer = _sliverCacheNewerEntries!;
      olderIndex = _sliverCacheOlderIndexByKey![targetEntry.key] ?? -1;
      // The newer map is offset by the leading first-contact card, which is not
      // an entry.
      final mapped = olderIndex >= 0
          ? null
          : _sliverCacheNewerIndexByKey![targetEntry.key];
      newerIndex = mapped == null ? -1 : mapped - _sliverCacheLeadingItemCount;
    } else {
      final partition = _partitionTranscript(entries);
      older = partition.beforePivot.reversed.toList(growable: false);
      newer = partition.pivotAndAfter;
      olderIndex = older.indexOf(targetEntry);
      newerIndex = olderIndex >= 0 ? -1 : newer.indexOf(targetEntry);
    }
    final messages = _transcriptCacheMessages ?? _vm.messages;
    final position = _scroll.position;
    final viewport = _scroll.position.viewportDimension;

    if (olderIndex >= 0) {
      var targetTop = 0.0;
      for (var i = 0; i <= olderIndex; i++) {
        targetTop -= _estimatedEntryExtent(older[i]);
      }
      if (!beforeUnreadDivider &&
          _needsUnreadDivider(targetEntry.startIndex, messages: messages)) {
        targetTop += _ChatViewState._estimatedUnreadDividerExtent;
      }
      return clampScrollOffset(position, targetTop - viewport * alignment);
    }

    var targetTop = 0.0;
    for (var i = 0; i < newerIndex; i++) {
      targetTop += _estimatedEntryExtent(newer[i]);
    }
    if (!beforeUnreadDivider &&
        _needsUnreadDivider(targetEntry.startIndex, messages: messages)) {
      targetTop += _ChatViewState._estimatedUnreadDividerExtent;
    }
    return clampScrollOffset(position, targetTop - viewport * alignment);
  }

  double _estimatedEntryExtent(_TranscriptEntry entry) {
    var extent = 0.0;
    final messages = _transcriptCacheMessages ?? _vm.messages;
    if (_needsUnreadDivider(entry.startIndex, messages: messages)) {
      extent += _ChatViewState._estimatedUnreadDividerExtent;
    }
    if (_needsSeparator(entry.startIndex, messages: messages)) {
      extent += _ChatViewState._estimatedSeparatorExtent;
    }
    final first = entry.first;
    if (first.isService) return extent + 38;
    if (entry.isBlockedRun) {
      if (!_expandedBlockedRunIds.contains(entry.last.id)) return extent + 40;
      return extent +
          entry.messages.fold<double>(
            0,
            (sum, message) => sum + _estimatedMessageExtent(message),
          );
    }
    if (entry.isImageGroup) {
      return extent + _estimatedImageGroupExtent(entry);
    }
    if (entry.isDocumentGroup) {
      final hasCaption = entry.messages.any(
        (message) => message.text.trim().isNotEmpty,
      );
      return extent + entry.messages.length * 71 + (hasCaption ? 54 : 0) + 16;
    }
    return extent + _estimatedMessageExtent(first);
  }

  double _estimatedImageGroupExtent(_TranscriptEntry entry) {
    final width = MediaQuery.sizeOf(context).width;
    final maxWidth = _messageMediaMaxWidth(width);
    final layout = buildTelegramMediaAlbumLayout(
      items: [
        for (final message in entry.messages.take(9))
          MediaAlbumItem(
            width: message.imageWidth,
            height: message.imageHeight,
          ),
      ],
      maxWidth: maxWidth - 8,
      gap: 4,
      maxSingleHeight: 300,
      minRowHeight: 82,
      maxRowHeight: 230,
    );
    final hasCaption = entry.messages.any((m) => m.text.trim().isNotEmpty);
    return layout.height + (hasCaption ? 38 : 0) + 16;
  }

  double _estimatedMessageExtent(ChatMessage message) {
    if (message.animatedSticker != null || message.videoSticker != null) {
      return 180;
    }
    if (message.image != null || message.video != null) {
      final h = message.imageHeight ?? 180;
      final w = message.imageWidth ?? 180;
      final scaled = w <= 0 ? 180.0 : _messageMediaMaxWidth() * h / w;
      return scaled.clamp(120.0, 310.0) + 16;
    }
    if (message.document != null ||
        message.music != null ||
        message.voice != null ||
        message.location != null ||
        message.isCall) {
      return 78;
    }
    if (message.diceEmoji != null || message.stickerFileId != null) {
      return 94;
    }
    final text = message.text.trim();
    final width = MediaQuery.sizeOf(context).width;
    final charsPerLine = math.max(10, (width * 0.52 / 15).floor());
    final lines = text.isEmpty
        ? 1
        : (text.length / charsPerLine).ceil().clamp(1, 8);
    final sender = _vm.isGroup && !message.isOutgoing ? 18.0 : 0.0;
    final reply = message.replyToMessageId != null ? 42.0 : 0.0;
    final buttons = message.buttonRows.isNotEmpty
        ? message.buttonRows.length * 38.0
        : 0.0;
    return 30 + sender + reply + lines * 22.0 + buttons;
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _cancelSessionScrollAnchorMaintenance();
    _autoScrollPolicy.requestReturnToBottom();
    if (_positionShortFirstContactHistoryIfItFits(requireAtLatest: false)) {
      _autoScrollPolicy.returnToBottom();
      _markReadAtBottomIfNeeded();
      _clearBottomIndicatorsIfNeeded();
      return;
    }
    _showingFullyVisibleFirstContactHistory = false;
    final generation = _bottomFollow.begin();
    final position = _scroll.position;
    if ((_loadedBottomOffset - position.pixels).abs() > 0.5) {
      _scroll.jumpTo(_loadedBottomOffset);
    }
    _markReadAtBottomIfNeeded();
    _clearBottomIndicatorsIfNeeded();
    _scheduleBottomGeometryFollow(generation);
  }

  void _scheduleShortTranscriptFill() {
    if (_shortTranscriptFillScheduled || _isFillingShortTranscript) return;
    _shortTranscriptFillScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shortTranscriptFillScheduled = false;
      unawaited(_fillShortTranscript());
    });
  }

  void _scheduleParkedShortTranscriptRepair() {
    if (_parkedShortTranscriptRepairScheduled) return;
    _parkedShortTranscriptRepairScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _parkedShortTranscriptRepairScheduled = false;
      if (!mounted || !_initialTranscriptReady) return;
      if (!_repairParkedShortTranscriptPivot()) return;
      _updateState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _canFollowLoadedBottom()) _scrollToBottom();
      });
    });
  }

  /// Unparks a frozen newest (or newest-like) pivot when older messages are
  /// already in the model but only the after-center arm is visible.
  bool _repairParkedShortTranscriptPivot() {
    if (!mounted ||
        (_vm.anchoredHistory && !_isTranscriptShort()) ||
        _maintainSessionScrollAnchor ||
        _autoScrollPolicy.preservesViewport ||
        _scrollTargetId != null ||
        _initialTranscriptPositionCancelled ||
        _transcriptViewportClaimedByUser) {
      return false;
    }
    final pivot = _transcriptPivot;
    if (pivot == null) return false;
    final hasOlder = _vm.messages.any(
      (message) => _transcriptOrderId(message) < pivot.cutoffMessageId,
    );
    if (!shouldRebaseParkedShortTranscriptPivot(
      pivotCutoffMessageId: pivot.cutoffMessageId,
      latestArmIsShort: _isTranscriptShort(),
      hasMessageOlderThanPivot: hasOlder,
      followingLatest: true,
      hasExplicitMessageTarget: widget.initialMessageId != null,
      viewportClaimedByUser: _transcriptViewportClaimedByUser,
    )) {
      return false;
    }
    _resetTranscriptPivot();
    _transcriptCache = null;
    _transcriptCacheMessages = null;
    return true;
  }

  Future<void> _fillShortTranscript() async {
    if (!mounted ||
        !_initialTranscriptReady ||
        !_scroll.hasClients ||
        !_vm.initialLoaded ||
        _initialTranscriptPositionCancelled) {
      return;
    }
    // Repair does not need another network page: history may already sit in
    // before-center under a frozen pivot.
    if (_repairParkedShortTranscriptPivot()) {
      _updateState(() {});
      await WidgetsBinding.instance.endOfFrame;
      if (mounted && _canFollowLoadedBottom()) _scrollToBottom();
    }
    if (!mounted ||
        !_scroll.hasClients ||
        (_vm.anchoredHistory && !_isTranscriptShort()) ||
        _maintainSessionScrollAnchor ||
        _autoScrollPolicy.preservesViewport ||
        _scrollTargetId != null ||
        _initialTranscriptPositionCancelled ||
        _transcriptViewportClaimedByUser ||
        !_vm.canLoadOlder) {
      return;
    }
    if (!_isTranscriptShort()) return;
    // A restored or touch-claimed freeze on a thin arm must not block fill;
    // otherwise older pages stay in the before-center sliver forever.
    if (_transcriptPivotFrozen) {
      if (!shouldFreezeTranscriptPivot(
        latestArmIsShort: true,
        canLoadOlder: _vm.canLoadOlder,
      )) {
        _transcriptPivotFrozen = false;
      } else {
        return;
      }
    }

    final generation = ++_shortTranscriptFillGeneration;
    _isFillingShortTranscript = true;
    var loadedAny = false;
    try {
      var guard = 0;
      while (_canContinueShortTranscriptFill(generation) &&
          _vm.canLoadOlder &&
          _isTranscriptShort() &&
          guard < 8) {
        final loaded = await _vm.loadOlder();
        if (!loaded) break;
        _olderHistoryExhaustedHint = false;
        loadedAny = true;
        if (!_canContinueShortTranscriptFill(generation)) break;
        await WidgetsBinding.instance.endOfFrame;
        if (!_canContinueShortTranscriptFill(generation)) break;
        guard++;
      }
    } finally {
      _isFillingShortTranscript = false;
    }
    if (!_vm.hasOlderHistory) _olderHistoryExhaustedHint = true;
    if (_repairParkedShortTranscriptPivot()) {
      _updateState(() {});
      await WidgetsBinding.instance.endOfFrame;
      if (mounted && _canFollowLoadedBottom()) {
        _scrollToBottom();
        return;
      }
    }
    if (_canContinueShortTranscriptFill(generation)) {
      if (loadedAny) await _positionAfterShortFill(generation);
      // An empty older page flips canLoadOlder without a model notification.
      // Re-evaluate the first-contact card now that history is known complete.
      _scheduleShortFirstContactReveal();
    }
    if (_revealLoadedOlderPage && _vm.canLoadOlder) {
      unawaited(_loadOlderFromScroll());
    }
  }

  bool _canContinueShortTranscriptFill(int generation) {
    return mounted &&
        generation == _shortTranscriptFillGeneration &&
        _scroll.hasClients &&
        !_hasTranscriptPointerDown &&
        !_initialTranscriptPositionCancelled &&
        !_transcriptViewportClaimedByUser &&
        !(_vm.anchoredHistory && !_isTranscriptShort()) &&
        !_maintainSessionScrollAnchor &&
        !_autoScrollPolicy.preservesViewport &&
        _scrollTargetId == null &&
        (!_transcriptPivotFrozen || _isTranscriptShort());
  }

  bool _isTranscriptShort() {
    if (!_scroll.hasClients) return true;
    // An unread/search destination can contain just one or two very tall
    // messages. A thin around-unread page may also fall back to latest history,
    // clearing anchoredHistory without changing the unread entry destination.
    // In either case, a low row count must not rebase a full-height message
    // and jump past its unread divider to the bottom.
    if (_vm.anchoredHistory ||
        (_entryUnreadCount > 0 && !_shouldOpenAtBottom)) {
      return _scroll.position.maxScrollExtent <= 24;
    }
    // With a center sliver, only the after-center arm defines the latest edge.
    // A large negative min extent says nothing about whether that arm fills
    // the viewport.
    return isLatestTranscriptArmShort(
      maxScrollExtent: _scroll.position.maxScrollExtent,
      afterCenterEntryCount: _latestArmEntryCount(),
    );
  }

  int _latestArmEntryCount() {
    final entries = _transcriptCache;
    if (entries == null || entries.isEmpty) {
      return _vm.messages.isEmpty ? 0 : _vm.messages.length;
    }
    final pivot = _transcriptPivot;
    if (pivot == null) return entries.length;
    var count = 0;
    for (final entry in entries) {
      final belongsToLatestArm = entry.messages.any(
        (message) => _transcriptOrderId(message) >= pivot.cutoffMessageId,
      );
      if (belongsToLatestArm) count++;
    }
    return count;
  }

  Future<void> _positionAfterShortFill(int generation) async {
    if (!_canContinueShortTranscriptFill(generation)) return;
    if (_shouldOpenAtBottom) {
      _scrollToBottom();
      return;
    }
    final i = _firstUnreadIndex();
    final boundaryLoaded = _isUnreadBoundaryLoaded();
    if (_entryUnreadCount > 0 && i >= 0 && boundaryLoaded) {
      final ctx = _unreadKey.currentContext;
      if (ctx != null) {
        await Scrollable.ensureVisible(ctx, alignment: 0.12);
        if (!_canContinueShortTranscriptFill(generation)) return;
        return;
      }
    }
    if (_canContinueShortTranscriptFill(generation)) _scrollToBottom();
  }

  bool _isUnreadBoundaryLoaded() {
    if (_vm.messages.isEmpty) return false;
    return _entryLastReadInboxId <= 0 ||
        _vm.messages.first.id <= _entryLastReadInboxId;
  }

  Future<void> _popFromBackSwipe() async {
    if (_backSwipePopping || !mounted) return;
    _backSwipePopping = true;
    try {
      _prepareExitState();
      final onBack = widget.onBack;
      if (onBack != null) {
        onBack();
      } else {
        await Navigator.of(context).maybePop();
      }
    } finally {
      _backSwipePopping = false;
    }
  }
}
