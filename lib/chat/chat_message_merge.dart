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
