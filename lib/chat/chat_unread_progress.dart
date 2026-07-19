enum ChatBottomIndicator { none, newMessages, jumpToBottom }

enum ChatNewMessagesControlPlacement { hidden, top, bottom }

ChatBottomIndicator chatBottomIndicator({
  required bool isScrolledUp,
  required bool hasNewMessages,
}) {
  if (!isScrolledUp) return ChatBottomIndicator.none;
  return hasNewMessages
      ? ChatBottomIndicator.newMessages
      : ChatBottomIndicator.jumpToBottom;
}

ChatNewMessagesControlPlacement chatNewMessagesControlPlacement({
  required bool isScrolledUp,
  required bool hasNewMessages,
  required bool isEntryUnread,
}) {
  if (!hasNewMessages) return ChatNewMessagesControlPlacement.hidden;
  if (isScrolledUp) return ChatNewMessagesControlPlacement.bottom;
  return isEntryUnread
      ? ChatNewMessagesControlPlacement.top
      : ChatNewMessagesControlPlacement.hidden;
}

/// Buffers only message IDs received through TDLib's `updateNewMessage` path.
/// History pages loaded while restoring a saved scroll position must never be
/// mistaken for live arrivals.
class ChatLiveMessageBuffer {
  final Set<int> _messageIds = <int>{};

  bool add(int messageId) => _messageIds.add(messageId);

  List<int> takeAll() {
    if (_messageIds.isEmpty) return const <int>[];
    final result = _messageIds.toList(growable: false);
    _messageIds.clear();
    return result;
  }
}

/// Live incoming IDs that were appended to the currently loaded transcript.
///
/// A null previous newest ID means the chat previously had no server message;
/// the first live arrival must still be surfaced if auto-follow is suppressed.
List<int> appendedLiveIncomingMessageIds({
  required int? previousNewestMessageId,
  required Iterable<int> liveIncomingMessageIds,
  required Iterable<int> currentMessageIds,
}) {
  final currentIds = currentMessageIds.toSet();
  return liveIncomingMessageIds
      .where(
        (id) =>
            (previousNewestMessageId == null || id > previousNewestMessageId) &&
            currentIds.contains(id),
      )
      .toList(growable: false);
}

/// Returns the earliest loaded incoming message beyond a captured read
/// boundary. The boundary must be the value from when the chat opened: TDLib
/// advances its live boundary as soon as the latest messages are marked read.
int? firstUnreadMessageIdAfterBoundary({
  required Iterable<int> incomingMessageIds,
  required int lastReadInboxId,
}) {
  int? earliest;
  for (final messageId in incomingMessageIds) {
    if (messageId <= lastReadInboxId) continue;
    if (earliest == null || messageId < earliest) earliest = messageId;
  }
  return earliest;
}

class ChatUnreadProgress {
  final Set<int> _seenInitialMessageIds = <int>{};
  final Set<int> _liveMessageIds = <int>{};

  int get liveCount => _liveMessageIds.length;

  int remaining({required int initialUnreadCount}) =>
      (initialUnreadCount - _seenInitialMessageIds.length).clamp(0, 1 << 30) +
      _liveMessageIds.length;

  bool addLiveMessage(int messageId) => _liveMessageIds.add(messageId);

  bool addLiveMessages(Iterable<int> messageIds) {
    var changed = false;
    for (final messageId in messageIds) {
      changed = _liveMessageIds.add(messageId) || changed;
    }
    return changed;
  }

  bool markVisible({required int messageId, required bool initialUnread}) {
    if (_liveMessageIds.remove(messageId)) return true;
    return initialUnread && _seenInitialMessageIds.add(messageId);
  }

  bool clearLiveMessages() {
    if (_liveMessageIds.isEmpty) return false;
    _liveMessageIds.clear();
    return true;
  }
}
