import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view_model.dart';

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
}
