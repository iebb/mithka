import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';

typedef ForwardQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

class ForwardOptions {
  const ForwardOptions({this.removeCaption = false, this.removeSender = false});

  final bool removeCaption;
  final bool removeSender;

  bool get sendCopy => removeSender || removeCaption;
}

class ForwardBlockedException implements Exception {
  const ForwardBlockedException();

  @override
  String toString() => 'ForwardBlockedException';
}

bool isForwardProtectedError(Object error) {
  if (error is ForwardBlockedException) return true;
  final text = error.toString().toLowerCase();
  return text.contains('can_be_forwarded') ||
      text.contains('can_be_copied') ||
      text.contains('protected') ||
      text.contains('forwards restricted') ||
      text.contains('message was not forwarded') ||
      text.contains('message can\'t be forwarded') ||
      text.contains('message cannot be forwarded') ||
      text.contains('message_copy_forbidden') ||
      text.contains('chat_forwards_restricted');
}

Future<void> forwardMessagesWithOptions({
  required TdClient client,
  required int targetChatId,
  required int fromChatId,
  required List<int> messageIds,
  Map<String, dynamic>? topicId,
  ForwardOptions options = const ForwardOptions(),
}) async {
  if (messageIds.isEmpty) return;
  await assertForwardAllowed(
    query: client.query,
    fromChatId: fromChatId,
    messageIds: messageIds,
    options: options,
  );
  final response = await client.query({
    '@type': 'forwardMessages',
    'chat_id': targetChatId,
    'topic_id': ?topicId,
    'from_chat_id': fromChatId,
    'message_ids': messageIds,
    'options': {'@type': 'messageSendOptions'},
    'send_copy': options.sendCopy,
    'remove_caption': options.removeCaption,
  });
  assertForwardResponseComplete(response, messageIds.length);
}

Future<void> assertForwardAllowed({
  required ForwardQuery query,
  required int fromChatId,
  required List<int> messageIds,
  required ForwardOptions options,
}) async {
  // Chat protection changes are delivered independently from message
  // properties. Checking the chat first makes the restriction effective as
  // soon as updateChatHasProtectedContent is folded into TDLib's local state.
  try {
    final chat = await query({'@type': 'getChat', 'chat_id': fromChatId});
    if (chat.boolean('has_protected_content') == true) {
      throw const ForwardBlockedException();
    }
  } on ForwardBlockedException {
    rethrow;
  } catch (_) {
    // Per-message properties below remain authoritative if an old/local TDLib
    // state can't return the source chat yet.
  }

  try {
    for (final messageId in messageIds) {
      final properties = await query({
        '@type': 'getMessageProperties',
        'chat_id': fromChatId,
        'message_id': messageId,
      });
      final allowed = options.sendCopy
          ? properties.boolean('can_be_copied') == true
          : properties.boolean('can_be_forwarded') == true;
      if (!allowed) throw const ForwardBlockedException();
    }
  } on ForwardBlockedException {
    rethrow;
  } catch (_) {
    // Older/local TDLib states can fail to provide properties. Let the actual
    // forward request decide and normalize the server error in the caller.
  }
}

void assertForwardResponseComplete(
  Map<String, dynamic> response,
  int expectedCount,
) {
  final messages = response['messages'];
  if (response.type != 'messages' || messages is! List) return;
  if (messages.length != expectedCount ||
      messages.any((item) => item == null)) {
    throw const ForwardBlockedException();
  }
}
