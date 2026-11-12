import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/safety_notice_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('safety notice opt-out defaults to off and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = SafetyNoticeController(prefs);

    expect(controller.disabled, isFalse);

    controller.disabled = true;
    await Future<void>.delayed(Duration.zero);

    expect(controller.disabled, isTrue);
    expect(SafetyNoticeController(prefs).disabled, isTrue);
  });
}
