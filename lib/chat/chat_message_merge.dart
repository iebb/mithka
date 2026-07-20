import '../tdlib/td_models.dart';

/// TDLib exposes yet-unsent messages with a normal positive ID plus
/// `sending_state`; the state, not the ID sign, is authoritative.
bool isPendingChatMessage(ChatMessage message) => message.isSending;

/// Orders server messages chronologically while keeping local pending
/// messages at the latest edge.
int compareChatMessagesChronologically(ChatMessage a, ChatMessage b) {
  final aIsPending = isPendingChatMessage(a);
  final bIsPending = isPendingChatMessage(b);
  if (aIsPending != bIsPending) return aIsPending ? 1 : -1;
  if (aIsPending) {
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) return byDate;
    return a.id.compareTo(b.id);
  }
  return a.id.compareTo(b.id);
}

/// Highest server-assigned ID, ignoring local pending messages.
int latestServerMessageId(Iterable<ChatMessage> messages) {
  var latest = 0;
  for (final message in messages) {
    if (!isPendingChatMessage(message) &&
        message.id > 0 &&
        message.id > latest) {
      latest = message.id;
    }
  }
  return latest;
}

/// Latest server ID visible to the transcript, falling back to the complete
/// loaded window when filtering leaves only local pending messages.
int latestServerMessageReadBoundary({
  required Iterable<ChatMessage> visibleMessages,
  required Iterable<ChatMessage> allMessages,
}) {
  final visible = latestServerMessageId(visibleMessages);
  return visible > 0 ? visible : latestServerMessageId(allMessages);
}

/// Pending local sends cannot have been acknowledged by the peer yet.
bool isOutgoingServerMessageRead({
  required ChatMessage message,
  required int lastReadOutboxId,
}) {
  return message.isOutgoing &&
      !message.isSending &&
      message.id > 0 &&
      message.id <= lastReadOutboxId;
}

/// Only an empty remote history page proves that no older page exists.
bool confirmsOlderHistoryExhausted({required bool onlyLocal}) {
  return !onlyLocal;
}

/// Chat-list preview / cold local cache often yields a single bubble. Windows
/// thinner than this must await a remote page before the transcript is marked
/// ready, otherwise the UI settles on the preview until the user scrolls.
const kThinInitialHistoryMessageCount = 12;

bool isThinInitialHistoryWindow(int messageCount) =>
    messageCount > 0 && messageCount < kThinInitialHistoryMessageCount;

/// Caught-up chats should open on the latest window. Around-last-read is only
/// for chats that still have unread inbox messages.
bool shouldLoadInitialHistoryAroundLastRead({
  required bool openAtLatest,
  required int lastReadInboxId,
  required int unreadCount,
}) =>
    !openAtLatest && lastReadInboxId > 0 && unreadCount > 0;

List<ChatMessage> mergeChatMessages(
  Iterable<ChatMessage> current,
  Iterable<ChatMessage> incoming, {
  Set<int> ignoredMessageIds = const <int>{},
}) {
  final byId = {for (final message in current) message.id: message};
  for (final message in incoming) {
    if (ignoredMessageIds.contains(message.id)) continue;
    final existing = byId[message.id];
    if (existing != null) {
      message.senderName ??= existing.senderName;
      message.senderIsChat = message.senderIsChat || existing.senderIsChat;
      message.senderPhoto ??= existing.senderPhoto;
      message.senderRole ??= existing.senderRole;
      message.senderTitle ??= existing.senderTitle;
    }
    byId[message.id] = message;
  }
  return byId.values.toList()..sort(compareChatMessagesChronologically);
}

/// Applies the result of a history request that was started while live message
/// updates could still arrive.
///
/// A foreground/background hydration request must merge into the visible
/// transcript. An explicit jump may replace the old window, but still keeps
/// messages that arrived after the request began so its late response cannot
/// erase live updates.
List<ChatMessage> mergeChatHistoryWindow({
  required Iterable<ChatMessage> currentAtRequestStart,
  required Iterable<ChatMessage> currentAtCompletion,
  required Iterable<ChatMessage> fetched,
  required bool replaceCurrentWindow,
  bool preserveLiveArrivals = true,
  Set<int> ignoredMessageIds = const <int>{},
}) {
  if (!replaceCurrentWindow) {
    return mergeChatMessages(
      currentAtCompletion,
      fetched,
      ignoredMessageIds: ignoredMessageIds,
    );
  }

  final startingIds = currentAtRequestStart
      .map((message) => message.id)
      .toSet();
  final liveArrivals = preserveLiveArrivals
      ? currentAtCompletion.where(
          (message) => !startingIds.contains(message.id),
        )
      : const <ChatMessage>[];
  return mergeChatMessages(
    fetched,
    liveArrivals,
    ignoredMessageIds: ignoredMessageIds,
  );
}

/// Whether a live message can be appended without creating a disconnected
/// transcript (an older history window followed directly by the newest item).
bool shouldMergeLiveMessageIntoChatWindow({
  required bool historyReachesLatest,
}) => historyReachesLatest;
