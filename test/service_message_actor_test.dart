import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  test('boost and self-join service messages retain their actor user ID', () {
    for (final contentType in const [
      'messageChatBoost',
      'messageChatJoinByLink',
      'messageChatJoinByRequest',
    ]) {
      final message = TDParse.message({
        '@type': 'message',
        'id': 42,
        'chat_id': -1001,
        'date': 1,
        'sender_id': {'@type': 'messageSenderUser', 'user_id': 7001},
        'content': {'@type': contentType},
      });

      expect(message, isNotNull, reason: contentType);
      expect(message!.isService, isTrue, reason: contentType);
      expect(message.serviceUserIds, [7001], reason: contentType);
    }
  });

  test('member-add service messages retain all joined user IDs', () {
    final message = TDParse.message({
      '@type': 'message',
      'id': 43,
      'chat_id': -1001,
      'date': 1,
      'sender_id': {'@type': 'messageSenderUser', 'user_id': 7001},
      'content': {
        '@type': 'messageChatAddMembers',
        'member_user_ids': [7002, 7003],
      },
    });

    expect(message!.serviceUserIds, [7002, 7003]);
  });
}
