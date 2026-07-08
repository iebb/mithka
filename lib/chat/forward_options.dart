import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';

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
  ForwardOptions options = const ForwardOptions(),
}) async {
  if (messageIds.isEmpty) return;
  await _assertForwardAllowed(
    client: client,
    fromChatId: fromChatId,
    messageIds: messageIds,
    options: options,
  );
  await client.query({
    '@type': 'forwardMessages',
    'chat_id': targetChatId,
    'from_chat_id': fromChatId,
    'message_ids': messageIds,
    'options': {'@type': 'messageSendOptions'},
    'send_copy': options.sendCopy,
    'remove_caption': options.removeCaption,
  });
}

Future<void> _assertForwardAllowed({
  required TdClient client,
  required int fromChatId,
  required List<int> messageIds,
  required ForwardOptions options,
}) async {
  try {
    for (final messageId in messageIds) {
      final properties = await client.query({
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
