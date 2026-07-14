enum ChatBottomIndicator { none, newMessages, jumpToBottom }

ChatBottomIndicator chatBottomIndicator({
  required bool isScrolledUp,
  required bool hasNewMessages,
}) {
  if (!isScrolledUp) return ChatBottomIndicator.none;
  return hasNewMessages
      ? ChatBottomIndicator.newMessages
      : ChatBottomIndicator.jumpToBottom;
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
