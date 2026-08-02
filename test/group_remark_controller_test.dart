import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/group_remark_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('group remarks persist trimmed values and blank clears them', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final controller = GroupRemarkController(
      preferences,
      initialAccountUserId: 101,
    );
    addTearDown(controller.dispose);

    expect(controller.remarkFor(-1001), isNull);
    expect(controller.displayTitleFor(-1001, 'Server title'), 'Server title');

    await controller.setRemark(-1001, '  Local remark  ');

    expect(controller.remarkFor(-1001), 'Local remark');
    expect(controller.displayTitleFor(-1001, 'Server title'), 'Local remark');

    final restored = GroupRemarkController(
      preferences,
      initialAccountUserId: 101,
    );
    addTearDown(restored.dispose);
    expect(restored.remarkFor(-1001), 'Local remark');

    await restored.setRemark(-1001, '   ');
    expect(restored.remarkFor(-1001), isNull);
    expect(
      restored.displayTitleFor(-1001, 'New server title'),
      'New server title',
    );
  });

  test('group remarks remain isolated by stable Telegram user id', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final controller = GroupRemarkController(
      preferences,
      initialAccountUserId: 101,
    );
    addTearDown(controller.dispose);

    await controller.setRemark(-1001, 'First account');
    controller.setActiveAccountUserId(202);
    expect(controller.remarkFor(-1001), isNull);

    await controller.setRemark(-1001, 'Second account');
    controller.setActiveAccountUserId(101);
    expect(controller.remarkFor(-1001), 'First account');

    controller.setActiveAccountUserId(202);
    expect(controller.remarkFor(-1001), 'Second account');
  });

  test('group remarks never persist without an account identity', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final controller = GroupRemarkController(preferences);
    addTearDown(controller.dispose);

    expect(controller.canPersist, isFalse);
    await controller.setRemark(-1001, 'Must not leak into a slot');

    expect(controller.remarkFor(-1001), isNull);
    expect(preferences.getKeys(), isEmpty);
  });
}
