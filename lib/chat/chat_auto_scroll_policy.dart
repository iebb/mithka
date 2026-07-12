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
