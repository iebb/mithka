import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view_model.dart';
import 'package:mithka/tdlib/json_helpers.dart';

void main() {
  testWidgets('chat-list update bursts produce one batched notification', (
    tester,
  ) async {
    final model = ChatListViewModel();
    addTearDown(model.dispose);
    var notifications = 0;
    model.addListener(() => notifications++);

    model.scheduleResortForTesting();
    model.scheduleResortForTesting();
    model.scheduleResortForTesting();
    await tester.pump(const Duration(milliseconds: 49));
    expect(notifications, 0);

    await tester.pump(const Duration(milliseconds: 1));
    expect(notifications, 1);
  });

  test('late chat-list resort is ignored after disposal', () async {
    final model = ChatListViewModel();
    model.dispose();

    expect(() => model.meId = 42, returnsNormally);
    expect(model.scheduleResortForTesting, returnsNormally);
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });

  testWidgets(
    'startup hydrates the newest page before accepting older-page pagination',
    (tester) async {
      final firstLoad = Completer<Map<String, dynamic>>();
      final requestTypes = <String>[];
      final model = ChatListViewModel(
        queryForTesting: (request) {
          requestTypes.add(request.type ?? 'unknown');
          return switch (request.type) {
            'loadChats' => firstLoad.future,
            'getChats' => Future.value({
              '@type': 'chats',
              'chat_ids': const <int>[],
            }),
            _ => Future.value({'@type': 'ok'}),
          };
        },
      );

      model.onAppear();
      model.loadMore();
      await tester.pump();

      expect(
        requestTypes,
        ['loadChats'],
        reason: 'pagination must not read a stale list during the first load',
      );

      firstLoad.complete({'@type': 'ok'});
      await tester.pump();
      await tester.pump();

      expect(requestTypes, ['loadChats', 'getChats']);

      model.dispose();
      await tester.pump(const Duration(seconds: 6));
    },
  );
}
