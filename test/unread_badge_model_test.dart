import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/unread_badge_model.dart';
import 'package:mithka/theme/theme_controller.dart';

void main() {
  test('unread badge cancels its TDLib subscription on disposal', () async {
    var subscriptionCancelled = false;
    final updates = StreamController<Map<String, dynamic>>.broadcast(
      onCancel: () => subscriptionCancelled = true,
    );
    addTearDown(updates.close);
    final model = UnreadBadgeModel(updates: updates.stream)..start();

    updates.add({
      '@type': 'updateUnreadChatCount',
      'chat_list': {'@type': 'chatListMain'},
      'unread_unmuted_count': 4,
    });
    await Future<void>.delayed(Duration.zero);
    expect(model.countFor(UnreadBadgeMode.chats), 4);

    model.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(subscriptionCancelled, isTrue);
  });
}
