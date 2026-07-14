import '../tdlib/td_models.dart';

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
  return byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
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
