import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';

void main() {
  test(
    'an unconfirmed send timeout keeps the accepted pending message',
    () async {
      final vm = ChatViewModel(chatId: 1, title: 'Test', markReadOnOpen: false);
      addTearDown(vm.dispose);

      await vm.waitForMessageSendTimeoutForTest(
        123,
        timeout: const Duration(milliseconds: 1),
      );

      expect(vm.isPendingMessageDiscardedForTest(123), isFalse);
    },
  );
}
