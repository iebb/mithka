class ChatAutoScrollPolicy {
  factory ChatAutoScrollPolicy({bool preserveViewport = false}) =>
      ChatAutoScrollPolicy._(preserveViewport);

  ChatAutoScrollPolicy._(this._preserveViewport);

  bool _preserveViewport;

  /// After [requestReturnToBottom], ignore ballistic scroll updates that would
  /// otherwise re-lock [preservesViewport] before the jump finishes.
  bool _suppressViewportPreservation = false;

  bool get preservesViewport => _preserveViewport;

  void noteUserScroll({
    required bool towardOlderMessages,
    required bool isAtBottom,
  }) {
    if (isAtBottom) {
      _preserveViewport = false;
      _suppressViewportPreservation = false;
      return;
    }
    if (_suppressViewportPreservation) return;
    if (towardOlderMessages) {
      _preserveViewport = true;
    }
  }

  /// Clear viewport lock (e.g. already at bottom). Does not suppress re-locking.
  void returnToBottom() {
    _preserveViewport = false;
    _suppressViewportPreservation = false;
  }

  /// Explicit navigation to the latest edge. Ignores inertia-driven re-locks
  /// until settled at bottom or [allowViewportPreservation].
  void requestReturnToBottom() {
    _preserveViewport = false;
    _suppressViewportPreservation = true;
  }

  /// User took over the transcript; allow viewport locking again.
  void allowViewportPreservation() {
    _suppressViewportPreservation = false;
  }

  void noteMessageSent() => requestReturnToBottom();

  bool shouldFollowAppendedMessage({required bool wasNearBottom}) =>
      !_preserveViewport && wasNearBottom;

  bool shouldFollowComposerPanelChange({required bool wasNearBottom}) =>
      !_preserveViewport && wasNearBottom;
}

enum ChatReopenDisposition {
  explicitTarget,
  firstUnread,
  savedPosition,
  defaultPosition,
}

ChatReopenDisposition resolveChatReopenDisposition({
  required bool hasExplicitTarget,
  required bool hasSavedPosition,
  required bool hasConfirmedNewUnread,
}) {
  if (hasExplicitTarget) return ChatReopenDisposition.explicitTarget;
  if (hasConfirmedNewUnread) return ChatReopenDisposition.firstUnread;
  if (hasSavedPosition) return ChatReopenDisposition.savedPosition;
  return ChatReopenDisposition.defaultPosition;
}

bool shouldLoadLatestChatHistory({
  required bool anchoredHistory,
  required bool historyReachesLatest,
}) => anchoredHistory || !historyReachesLatest;

/// Whether one concrete message proves that a new unread arrived after the
/// saved session. Counts are intentionally excluded: reads on another device,
/// deletions, and an exit-time read can all make the count stay flat or fall.
bool isNewIncomingUnreadSinceChatSession({
  required int messageId,
  required bool isOutgoing,
  required bool isService,
  required int savedKnownLatestMessageId,
  required int currentLastReadInboxId,
}) {
  return savedKnownLatestMessageId > 0 &&
      !isOutgoing &&
      !isService &&
      messageId > savedKnownLatestMessageId &&
      messageId > currentLastReadInboxId;
}

bool shouldProbeChatSessionUnreadHistory({
  required int savedKnownLatestMessageId,
  required int currentKnownLatestMessageId,
  required int currentUnreadCount,
}) =>
    savedKnownLatestMessageId > 0 &&
    currentUnreadCount > 0 &&
    currentKnownLatestMessageId > savedKnownLatestMessageId;

bool shouldContinueChatSessionUnreadHistoryProbe({
  required int pagesScanned,
  int maximumPages = 5,
}) => pagesScanned < maximumPages;

/// A delayed initial `getChat` response must not replace a newer live inbox
/// boundary received while that request was in flight.
bool shouldApplyInitialChatReadState({
  required int readInboxRevisionAtRequestStart,
  required int currentReadInboxRevision,
}) => readInboxRevisionAtRequestStart == currentReadInboxRevision;

/// Invalidates asynchronous session-reopen work when a newer resolution starts
/// or the user claims/exits the viewport.
class ChatSessionReopenNavigationGuard {
  int _generation = 0;

  int begin() => ++_generation;

  void cancel() => ++_generation;

  bool isCurrent(int generation) => generation == _generation;
}

bool shouldMarkChatReadOnExit({
  required bool isAtLoadedBottom,
  required bool sessionReopenPending,
  required bool restoredPositionProtected,
  required bool preservesViewport,
  required bool historyReachesLatest,
}) =>
    isAtLoadedBottom &&
    shouldAllowAutomaticChatRead(
      sessionReopenPending: sessionReopenPending,
      restoredPositionProtected: restoredPositionProtected,
      preservesViewport: preservesViewport,
      historyReachesLatest: historyReachesLatest,
    );

bool shouldAllowAutomaticChatRead({
  required bool sessionReopenPending,
  required bool restoredPositionProtected,
  required bool preservesViewport,
  required bool historyReachesLatest,
}) =>
    !sessionReopenPending &&
    !restoredPositionProtected &&
    !preservesViewport &&
    historyReachesLatest;

bool shouldSaveChatSessionScrollSnapshot({
  required bool sessionReopenPending,
  required bool preservingSnapshotAfterFailedJump,
}) => !sessionReopenPending && !preservingSnapshotAfterFailedJump;

/// Protects the first real gesture after restoring a non-bottom viewport.
///
/// Centered history windows can report their loaded edge as "near latest".
/// Consuming the first gesture prevents that edge from immediately replacing
/// the restored window with the newest messages.
class ChatRestoredPositionGuard {
  ChatRestoredPositionGuard(this._armed);

  bool _armed;
  bool _gestureActive = false;

  bool get blocksAutomaticReturn => _armed;

  void noteUserScroll() {
    if (_armed) _gestureActive = true;
  }

  bool finishUserScroll() {
    if (!_armed || !_gestureActive) return false;
    _armed = false;
    _gestureActive = false;
    return true;
  }

  void cancel() {
    _armed = false;
    _gestureActive = false;
  }
}

/// Session restoration must distinguish an exact latest-edge position from a
/// viewport that merely happens to be close to it. A generous "near bottom"
/// threshold is useful for read markers and UI affordances, but using it here
/// discards the final partially visible reading position on reopen.
bool isChatSessionAtLoadedBottom({
  required bool anchoredHistory,
  required double distanceToLoadedBottom,
  double epsilon = 0.5,
}) {
  return !anchoredHistory &&
      distanceToLoadedBottom.isFinite &&
      distanceToLoadedBottom >= 0 &&
      distanceToLoadedBottom <= epsilon;
}

enum ChatInitialViewportTargetKind {
  message,
  firstUnread,
  readBoundary,
  loadedBottom,
  preserveAnchoredHistory,
}

class ChatInitialViewportTarget {
  const ChatInitialViewportTarget(this.kind, {this.messageId});

  final ChatInitialViewportTargetKind kind;
  final int? messageId;
}

/// Resolves one shared initial-position contract for both the estimate and
/// post-layout correction passes.
///
/// In particular, an around-last-read history window is anchored, but its
/// unread boundary still takes precedence over preserving an arbitrary window
/// offset. Explicit search/reply targets remain the highest priority.
ChatInitialViewportTarget resolveChatInitialViewportTarget({
  required int? explicitMessageId,
  required int? pendingMessageId,
  required bool openAtBottom,
  required bool anchoredHistory,
  required int unreadCount,
  required int? firstUnreadMessageId,
  required bool unreadBoundaryLoaded,
  required int lastReadInboxId,
}) {
  final messageTarget = explicitMessageId ?? pendingMessageId;
  if (messageTarget != null) {
    return ChatInitialViewportTarget(
      ChatInitialViewportTargetKind.message,
      messageId: messageTarget,
    );
  }
  if (openAtBottom) {
    return const ChatInitialViewportTarget(
      ChatInitialViewportTargetKind.loadedBottom,
    );
  }
  if (unreadCount > 0 && firstUnreadMessageId != null && unreadBoundaryLoaded) {
    return ChatInitialViewportTarget(
      ChatInitialViewportTargetKind.firstUnread,
      messageId: firstUnreadMessageId,
    );
  }
  if (unreadCount > 0 && lastReadInboxId > 0) {
    return ChatInitialViewportTarget(
      ChatInitialViewportTargetKind.readBoundary,
      messageId: lastReadInboxId,
    );
  }
  if (anchoredHistory) {
    return const ChatInitialViewportTarget(
      ChatInitialViewportTargetKind.preserveAnchoredHistory,
    );
  }
  return const ChatInitialViewportTarget(
    ChatInitialViewportTargetKind.loadedBottom,
  );
}

class ChatInitialScrollPlan {
  const ChatInitialScrollPlan({
    required this.initialOffset,
    required this.correctToBottomAfterLayout,
  });

  final double initialOffset;
  final bool correctToBottomAfterLayout;
}

ChatInitialScrollPlan chatInitialScrollPlan({
  required bool hasCachedTranscript,
  required double? savedPixels,
  required bool savedAtBottom,
  bool openAtBottom = false,
}) {
  final finiteSavedPixels = savedPixels?.isFinite == true ? savedPixels! : 0.0;
  // A cached latest window without a "was at bottom" snapshot still opens at
  // the latest edge. Without a post-layout correction, center-keyed transcripts
  // paint from offset zero and leave a one-bubble gap above empty space.
  return ChatInitialScrollPlan(
    initialOffset: hasCachedTranscript ? finiteSavedPixels : 0.0,
    correctToBottomAfterLayout:
        hasCachedTranscript && (savedAtBottom || openAtBottom),
  );
}

class ChatBottomCorrectionCoordinator {
  bool _scheduled = false;

  void schedule({
    required bool enabled,
    required void Function(void Function()) schedulePostFrame,
    required bool Function() canCorrect,
    required void Function() correct,
  }) {
    if (!enabled || _scheduled) return;
    _scheduled = true;
    schedulePostFrame(() {
      _scheduled = false;
      if (canCorrect()) correct();
    });
  }
}

/// Drives bottom correction from actual laid-out geometry instead of timers.
///
/// Each correction gets a generation. User navigation cancels the generation,
/// so a queued frame can never reclaim the viewport after the user scrolls.
class ChatBottomFollowCoordinator {
  int _generation = 0;

  int begin() => ++_generation;

  void cancel() => ++_generation;

  bool isCurrent(int generation) => generation == _generation;

  void follow({
    required int generation,
    required void Function(void Function()) schedulePostFrame,
    required bool Function() canFollow,
    required double Function() distanceToLatest,
    required double Function() latestExtent,
    required void Function() correct,
    required void Function() settled,
    required void Function() abandoned,
    double epsilon = 0.5,
    int remainingFrames = 12,
    double? previousLatestExtent,
  }) {
    if (!isCurrent(generation)) return;
    if (remainingFrames <= 0) {
      abandoned();
      return;
    }
    schedulePostFrame(() {
      if (!isCurrent(generation)) return;
      if (!canFollow()) {
        abandoned();
        return;
      }
      final currentLatestExtent = latestExtent();
      if (distanceToLatest() <= epsilon) {
        final extentIsStable =
            previousLatestExtent != null &&
            (currentLatestExtent - previousLatestExtent).abs() <= epsilon;
        if (extentIsStable) {
          settled();
          return;
        }
        follow(
          generation: generation,
          schedulePostFrame: schedulePostFrame,
          canFollow: canFollow,
          distanceToLatest: distanceToLatest,
          latestExtent: latestExtent,
          correct: correct,
          settled: settled,
          abandoned: abandoned,
          epsilon: epsilon,
          remainingFrames: remainingFrames - 1,
          previousLatestExtent: currentLatestExtent,
        );
        return;
      }
      correct();
      follow(
        generation: generation,
        schedulePostFrame: schedulePostFrame,
        canFollow: canFollow,
        distanceToLatest: distanceToLatest,
        latestExtent: latestExtent,
        correct: correct,
        settled: settled,
        abandoned: abandoned,
        epsilon: epsilon,
        remainingFrames: remainingFrames - 1,
        previousLatestExtent: currentLatestExtent,
      );
    });
  }
}

bool shouldRestoreChatSessionOffset({
  required bool hasExplicitTarget,
  required bool hasSnapshot,
  required bool snapshotWasAtBottom,
}) {
  return !hasExplicitTarget && hasSnapshot && !snapshotWasAtBottom;
}

/// A cold window replacement may keep the saved coordinate, but an explicit
/// history invalidation (for example clearing the chat) must discard it.
bool shouldPreserveChatSessionAnchorAcrossWindowChange({
  required bool anchorMaintenanceActive,
  required bool hasSavedPivot,
  required bool historyWindowInvalidated,
}) {
  return anchorMaintenanceActive && hasSavedPivot && !historyWindowInvalidated;
}

bool shouldOpenChatAtBottom({
  required bool hasExplicitTarget,
  required bool openAtLatest,
  required bool hasSnapshot,
  required bool snapshotWasAtBottom,
  bool hasCachedLatestTranscript = false,
}) {
  if (hasExplicitTarget) return false;
  if (hasSnapshot) return snapshotWasAtBottom;
  if (hasCachedLatestTranscript) return true;
  return openAtLatest;
}

double correctedChatSessionScrollOffset({
  required double currentPixels,
  required double currentAnchorViewportOffset,
  required double savedAnchorViewportOffset,
  required double minScrollExtent,
  required double maxScrollExtent,
}) {
  return (currentPixels +
          currentAnchorViewportOffset -
          savedAnchorViewportOffset)
      .clamp(minScrollExtent, maxScrollExtent);
}
