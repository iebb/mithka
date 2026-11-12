import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view.dart';

void main() {
  test(
    'split detail prepares the currently registered chat before removal',
    () {
      final controller = ChatViewExitController();
      var firstPrepared = 0;
      var secondPrepared = 0;

      final detachFirst = controller.register(() => firstPrepared++);
      controller.prepareExit();
      expect(firstPrepared, 1);

      final detachSecond = controller.register(() => secondPrepared++);
      detachFirst();
      controller.prepareExit();
      expect(firstPrepared, 1);
      expect(secondPrepared, 1);

      detachSecond();
      controller.prepareExit();
      expect(secondPrepared, 1);
    },
  );
}
