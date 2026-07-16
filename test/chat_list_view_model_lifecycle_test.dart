import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view_model.dart';

void main() {
  test('late chat-list resort is ignored after disposal', () async {
    final model = ChatListViewModel();
    model.dispose();

    expect(() => model.meId = 42, returnsNormally);
    expect(model.scheduleResortForTesting, returnsNormally);
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });
}
