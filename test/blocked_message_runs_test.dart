import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/blocked_message_runs.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  ChatMessage message(int id, {bool blocked = false}) => ChatMessage(
    id: id,
    isOutgoing: false,
    text: 'message $id',
    date: id,
    blockedByUser: blocked,
  );

  test('consecutive blocked messages collapse into one run', () {
    final messages = [
      message(1, blocked: true),
      message(2, blocked: true),
      message(3, blocked: true),
      message(4),
    ];

    expect(
      blockedMessageRunEnd(messages, 0, startsNewSection: (_) => false),
      3,
    );
  });

  test('date or unread boundaries split blocked runs', () {
    final messages = [
      message(1, blocked: true),
      message(2, blocked: true),
      message(3, blocked: true),
    ];

    expect(
      blockedMessageRunEnd(
        messages,
        0,
        startsNewSection: (index) => index == 2,
      ),
      2,
    );
  });
}
