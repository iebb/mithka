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
