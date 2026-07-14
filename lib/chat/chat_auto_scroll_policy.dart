class ChatAutoScrollPolicy {
  factory ChatAutoScrollPolicy({bool preserveViewport = false}) =>
      ChatAutoScrollPolicy._(preserveViewport);

  ChatAutoScrollPolicy._(this._preserveViewport);

  bool _preserveViewport;

  bool get preservesViewport => _preserveViewport;

  void noteUserScroll({
    required bool towardOlderMessages,
    required bool isAtBottom,
  }) {
    if (isAtBottom) {
      _preserveViewport = false;
    } else if (towardOlderMessages) {
      _preserveViewport = true;
    }
  }

  void returnToBottom() => _preserveViewport = false;

  bool shouldFollowAppendedMessage({required bool wasNearBottom}) =>
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
}) {
  final finiteSavedPixels = savedPixels?.isFinite == true
      ? savedPixels!.clamp(0.0, double.maxFinite)
      : 0.0;
  return ChatInitialScrollPlan(
    initialOffset: hasCachedTranscript ? finiteSavedPixels : 0.0,
    correctToBottomAfterLayout: hasCachedTranscript && savedAtBottom,
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

bool shouldRestoreChatSessionOffset({
  required bool hasExplicitTarget,
  required bool hasSnapshot,
  required bool snapshotWasAtBottom,
}) {
  return !hasExplicitTarget && hasSnapshot && !snapshotWasAtBottom;
}

bool shouldOpenChatAtBottom({
  required bool hasExplicitTarget,
  required bool openAtLatest,
  required bool hasSnapshot,
  required bool snapshotWasAtBottom,
}) {
  if (hasExplicitTarget) return false;
  if (hasSnapshot) return snapshotWasAtBottom;
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
