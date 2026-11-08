import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/app_icon_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('controller reads and changes the native runtime icon', () async {
    SharedPreferences.setMockInitialValues({'selected_app_icon': 'purple'});
    final calls = <MethodCall>[];
    const channel = MethodChannel('mithka/app_icon');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'isSupported' => true,
            'currentIcon' => 'blue',
            'setIcon' => null,
            _ => throw MissingPluginException(),
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final prefs = await SharedPreferences.getInstance();
    final controller = AppIconController(prefs);
    addTearDown(controller.dispose);
    await controller.initialize();

    expect(controller.supported, isTrue);
    expect(controller.variant, AppIconVariant.blue);
    // Native identity wins in memory, but initialization must remain read-only.
    expect(prefs.getString('selected_app_icon'), 'purple');
    expect(calls.where((call) => call.method == 'setIcon'), isEmpty);

    expect(await controller.setVariant(AppIconVariant.signal), isTrue);
    expect(controller.variant, AppIconVariant.signal);
    expect(prefs.getString('selected_app_icon'), 'signal');
    expect(calls.where((call) => call.method == 'setIcon').single.arguments, {
      'name': 'signal',
    });
  });
}
