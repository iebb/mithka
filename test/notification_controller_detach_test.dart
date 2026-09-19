import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/notifications/notification_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('detach stops the pipeline for the current owner only', () async {
    final controller = NotificationController.shared;
    final owner = Object();
    final stranger = Object();

    controller.attach(owner);
    final before = controller.stoppedAt;

    // A non-owner cannot tear the singleton down.
    await controller.detach(stranger);
    expect(controller.stoppedAt, same(before));

    await controller.detach(owner);
    expect(controller.stoppedAt, isNot(same(before)));
  });

  test('detach twice only stops once', () async {
    final controller = NotificationController.shared;
    final owner = Object();

    controller.attach(owner);
    await controller.detach(owner);
    final afterFirst = controller.stoppedAt;
    expect(afterFirst, isNotNull);

    // Ownership was released; a repeated detach must not run stop() again.
    await controller.detach(owner);
    expect(controller.stoppedAt, same(afterFirst));
  });
}
