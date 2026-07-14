import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';

typedef SecretChatQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

enum SecretChatReadiness { unknown, pending, ready, closed }

class SecretChatDestination {
  const SecretChatDestination({required this.id, required this.title});

  final int id;
  final String title;
}

/// Starts a TDLib-managed end-to-end encrypted chat and validates its result.
/// TDLib creates and stores the encryption keys; this layer only routes UI to
/// the returned chat.
abstract final class SecretChatService {
  static SecretChatReadiness readiness(Map<String, dynamic>? secretChat) {
    return switch (secretChat?.obj('state')?.type) {
      'secretChatStatePending' => SecretChatReadiness.pending,
      'secretChatStateReady' => SecretChatReadiness.ready,
      'secretChatStateClosed' => SecretChatReadiness.closed,
      _ => SecretChatReadiness.unknown,
    };
  }

  static Future<Map<String, dynamic>> get(
    int secretChatId, {
    SecretChatQuery? query,
  }) {
    if (secretChatId <= 0) {
      throw ArgumentError.value(
        secretChatId,
        'secretChatId',
        'must be positive',
      );
    }
    return (query ?? TdClient.shared.query)({
      '@type': 'getSecretChat',
      'secret_chat_id': secretChatId,
    });
  }

  static Future<SecretChatDestination> create(
    int userId, {
    SecretChatQuery? query,
  }) async {
    if (userId <= 0) {
      throw ArgumentError.value(userId, 'userId', 'must be positive');
    }
    final response = await (query ?? TdClient.shared.query)({
      '@type': 'createNewSecretChat',
      'user_id': userId,
    });
    final chatId = response.int64('id');
    if (chatId == null || TDParse.chatKind(response) != ChatKind.secret) {
      throw const FormatException('TDLib did not return a secret chat');
    }
    return SecretChatDestination(
      id: chatId,
      title: response.str('title')?.trim() ?? '',
    );
  }
}
