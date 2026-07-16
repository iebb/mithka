import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  test('renders Telegram custom service action text as a service banner', () {
    const action =
        'Kirito Sama will become the new owner in 7 days if '
        '欧式Fifty does not return.';
    final message = TDParse.message({
      '@type': 'message',
      'id': 1,
      'chat_id': -1001,
      'date': 1,
      'sender_id': {'@type': 'messageSenderUser', 'user_id': 42},
      'content': {'@type': 'messageCustomServiceAction', 'text': action},
    });

    expect(message, isNotNull);
    expect(message!.isService, isTrue);
    expect(message.contentType, 'messageCustomServiceAction');
    expect(message.text, action);
  });
}
