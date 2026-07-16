import '../tdlib/td_models.dart';

/// Returns the exclusive end index of one uninterrupted blocked-message run.
/// Date/unread boundaries are supplied by the transcript so those semantic
/// separators remain visible even when the adjacent senders are blocked.
int blockedMessageRunEnd(
  List<ChatMessage> messages,
  int start, {
  required bool Function(int index) startsNewSection,
}) {
  if (start < 0 || start >= messages.length || !messages[start].blockedByUser) {
    return start;
  }
  var end = start + 1;
  while (end < messages.length &&
      messages[end].blockedByUser &&
      !startsNewSection(end)) {
    end++;
  }
  return end;
}
