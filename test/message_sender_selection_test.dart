import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';

void main() {
  const user = MessageSenderOption(
    sender: {'@type': 'messageSenderUser', 'user_id': 1},
    id: 1,
    title: 'Me',
  );
  const channel = MessageSenderOption(
    sender: {'@type': 'messageSenderChat', 'chat_id': 2},
    id: 2,
    title: 'Channel',
  );

  test('restores the sender reported by the chat instead of list order', () {
    expect(
      preferredMessageSenderOption([
        user,
        channel,
      ], preferredSender: channel.sender),
      same(channel),
    );
  });

  test('keeps a current selection when available after refresh', () {
    expect(
      preferredMessageSenderOption([user, channel], current: channel),
      same(channel),
    );
  });
}
