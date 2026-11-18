//
//  app_icon_switch_test.dart
//
//  Pins the icon-switch mechanics that keep the post-switch cold start alive
//  and the switch UX honest:
//
//  - the native bridge answers currentIcon/setIcon OFF the platform main
//    thread (the crash-once signature: up to 61 serialized PackageManager
//    binder calls on the loading page's UI thread, right after 60 component
//    writes and their PACKAGE_CHANGED broadcast storm);
//  - re-selecting the shipped default routes through the manifest-disabled
//    LetterMNeutralAlt clone, so only the first explicit choice ever
//    transitions the manifest-enabled alias ENABLED -> DISABLED (the one
//    transition Android answers by closing the task);
//  - non-target aliases return to STATE_DEFAULT, not DISABLED — off the kill
//    path for manifest-disabled aliases;
//  - the controller's firstChangePending follows real choice state, so the
//    one-time "app will close once" note appears exactly before the first
//    switch and never again.
//

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/app_icon_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('controller firstChangePending', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('mithka/app_icon'), (
            call,
          ) async {
            return switch (call.method) {
              'isSupported' => true,
              'currentIcon' => 'letter_m_neutral',
              'setIcon' => null,
              _ => throw MissingPluginException(),
            };
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('mithka/app_icon'),
            null,
          );
    });

    test('pending on a fresh install, cleared by the first switch', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = AppIconController(prefs);
      addTearDown(controller.dispose);
      await controller.initialize();

      expect(
        controller.firstChangePending,
        isTrue,
        reason: 'no explicit choice yet: the note must show',
      );

      expect(await controller.setVariant(AppIconVariant.blue), isTrue);
      expect(
        controller.firstChangePending,
        isFalse,
        reason: 'the one-time close is behind us now',
      );
    });

    test(
      'a saved explicit choice is already behind the one-time close',
      () async {
        SharedPreferences.setMockInitialValues({'selected_app_icon': 'blue'});
        final prefs = await SharedPreferences.getInstance();
        final controller = AppIconController(prefs);
        addTearDown(controller.dispose);
        await controller.initialize();

        expect(controller.firstChangePending, isFalse);
      },
    );

    test('a foreign native current (imported state) also counts', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('mithka/app_icon'), (
            call,
          ) async {
            return switch (call.method) {
              'isSupported' => true,
              'currentIcon' => 'blue',
              'setIcon' => null,
              _ => throw MissingPluginException(),
            };
          });
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = AppIconController(prefs);
      addTearDown(controller.dispose);
      await controller.initialize();

      expect(
        controller.firstChangePending,
        isFalse,
        reason:
            'native current differs from the shipped default, so the '
            'manifest-enabled alias was already disabled once',
      );
    });
  });

  group('native icon bridge (source scan)', () {
    final kt = File(
      'android/app/src/main/kotlin/x/empty/mithka/MainActivity.kt',
    ).readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    test('currentIcon and setIcon never run on the platform main thread', () {
      expect(
        kt.contains('"currentIcon" -> Thread {'),
        isTrue,
        reason:
            'the up-to-61 PMS reads must leave the UI thread; a freeze '
            'there is the crash-once signature on the first post-switch cold '
            'start',
      );
      expect(
        kt.contains('fun applyIcon() {\n                            // All 61'),
        isTrue,
        reason: 'the 61 component writes must run on the worker thread',
      );
    });

    test('re-selecting the shipped default uses the Alt clone', () {
      expect(
        kt.contains(
          '"letter_m_neutral" to "\$packageName.MainActivityLetterMNeutralAlt"',
        ),
        isTrue,
        reason:
            'switching back to the neutral default must go through the '
            'manifest-disabled clone, or leaving it again force-closes the app',
      );
      expect(
        manifest.contains('android:name=".MainActivityLetterMNeutralAlt"'),
        isTrue,
        reason: 'the clone alias must exist in the manifest',
      );
      // The clone must ship disabled like every other alternative.
      final cloneBlock = manifest.substring(
        manifest.indexOf('.MainActivityLetterMNeutralAlt'),
      );
      expect(
        cloneBlock.contains('android:enabled="false"'),
        isTrue,
        reason: 'a manifest-enabled clone would show two launcher icons',
      );
    });

    test('non-target aliases return to STATE_DEFAULT, not DISABLED', () {
      expect(
        kt.contains(
          'component,\n                PackageManager.COMPONENT_ENABLED_STATE_DEFAULT,',
        ),
        isTrue,
        reason:
            'STATE_DEFAULT on a manifest-disabled alias is the same '
            'disabled component without the ENABLED->DISABLED runtime '
            'transition that closes the task',
      );
    });
  });
}
