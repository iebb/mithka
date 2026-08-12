import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/app_icon_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('app icon picker is exposed only where a native changer exists', () {
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    ]) {
      expect(appIconPickerAvailableForPlatform(platform), isTrue);
    }
    for (final platform in [
      TargetPlatform.fuchsia,
      TargetPlatform.linux,
      TargetPlatform.windows,
    ]) {
      expect(appIconPickerAvailableForPlatform(platform), isFalse);
    }
    expect(
      appIconPickerAvailableForPlatform(TargetPlatform.macOS, isWeb: true),
      isFalse,
    );
  });

  test(
    'abstract Icon Composer variants are exposed to the app icon picker',
    () {
      final variants = {
        for (final variant in AppIconVariant.values) variant.key: variant,
      };

      for (final key in ['aurora', 'prism', 'signal']) {
        final variant = variants[key];
        expect(variant, isNotNull);
        expect(File(variant!.asset).lengthSync(), greaterThan(10 * 1024));
        expect(variant.asset, endsWith('$key.png'));
      }
    },
  );

  test('abstract variants have valid native Icon Composer packages', () {
    const nativeNames = {
      'aurora': 'MithkaAurora',
      'prism': 'MithkaPrism',
      'signal': 'MithkaSignal',
    };
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    for (final entry in nativeNames.entries) {
      final package = Directory('ios/Runner/${entry.value}.icon');
      final definition = File('${package.path}/icon.json');
      final json = jsonDecode(definition.readAsStringSync()) as Map;
      final groups = json['groups'] as List;
      final layer = (groups.single as Map)['layers'] as List;
      final imageName = (layer.single as Map)['image-name'] as String;

      expect(File('${package.path}/Assets/$imageName').existsSync(), isTrue);
      expect(
        delegate,
        contains('case "${entry.key}": return "${entry.value}"'),
      );
      expect(
        delegate,
        contains('case "${entry.value}": return "${entry.key}"'),
      );
      expect(project, contains('${entry.value}.icon in Resources'));
    }
  });

  test('abstract variants have Android launcher aliases and resources', () {
    const nativeNames = {
      'aurora': 'Aurora',
      'prism': 'Prism',
      'signal': 'Signal',
    };
    const densities = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];
    final activity = File(
      'android/app/src/main/kotlin/ad/neko/mithka/MainActivity.kt',
    ).readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    for (final entry in nativeNames.entries) {
      expect(
        activity,
        contains(
          '"${entry.key}" to "\$packageName.MainActivity${entry.value}"',
        ),
      );
      expect(manifest, contains('android:name=".MainActivity${entry.value}"'));
      expect(
        manifest,
        contains('android:icon="@mipmap/ic_launcher_${entry.key}"'),
      );
      expect(
        File(
          'android/app/src/main/res/mipmap-anydpi-v26/'
          'ic_launcher_${entry.key}.xml',
        ).existsSync(),
        isTrue,
      );
      for (final density in densities) {
        final directory = 'android/app/src/main/res/mipmap-$density';
        expect(
          File('$directory/ic_launcher_${entry.key}.png').existsSync(),
          isTrue,
        );
        expect(
          File(
            '$directory/ic_launcher_${entry.key}_background.png',
          ).existsSync(),
          isTrue,
        );
      }
    }
  });

  test(
    'unsupported platforms cannot invoke an alternate icon change',
    () async {
      SharedPreferences.setMockInitialValues({});
      final controller = AppIconController(
        await SharedPreferences.getInstance(),
      );

      await controller.initialize();

      expect(controller.supported, isFalse);
      expect(await controller.setVariant(AppIconVariant.blue), isFalse);
      expect(controller.variant, AppIconVariant.defaultIcon);
    },
  );

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
    await controller.initialize();

    expect(controller.supported, isTrue);
    expect(controller.variant, AppIconVariant.blue);
    expect(prefs.getString('selected_app_icon'), 'blue');

    expect(await controller.setVariant(AppIconVariant.signal), isTrue);
    expect(controller.variant, AppIconVariant.signal);
    expect(prefs.getString('selected_app_icon'), 'signal');
    expect(calls.where((call) => call.method == 'setIcon').single.arguments, {
      'name': 'signal',
    });
  });

  test('macOS bridge persists and reapplies rounded Dock-only icons', () {
    final source = File(
      'macos/Runner/MacOSAppIconPlugin.swift',
    ).readAsStringSync();
    final registration = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();
    final project = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    expect(source, contains('NSApplication.shared.applicationIconImage'));
    expect(source, contains('NSApplication.shared.dockTile.display()'));
    expect(source, contains('UserDefaults.standard.set(requested'));
    expect(source, contains('applyPersistedIcon()'));
    expect(source, contains('registrar.lookupKey(forAsset: asset)'));
    expect(source, contains('Bundle(identifier: "io.flutter.flutter.app")'));
    expect(source, contains('privateFrameworksPath'));
    expect(source, contains('resourceRoot.appendingPathComponent(assetKey)'));
    expect(source, contains('applicationIconImage = nil'));
    expect(source, contains('NSBezierPath('));
    expect(source, contains('roundedRect: bounds'));
    expect(source, contains("Finder's bundle icon untouched"));
    expect('MacOSAppIconPlugin.register('.allMatches(source), isEmpty);
    expect(
      'MacOSAppIconPlugin.register('.allMatches(registration),
      hasLength(2),
      reason: 'the channel must work in the main and child Flutter engines',
    );
    expect(project, contains('MacOSAppIconPlugin.swift in Sources'));

    for (final variant in AppIconVariant.values) {
      expect(File(variant.asset).existsSync(), isTrue);
    }
  });

  test(
    'macOS builds its static app icon from the owned Icon Composer source',
    () {
      final project = File(
        'macos/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      final definition =
          jsonDecode(
                File('ios/Runner/Pengram.icon/icon.json').readAsStringSync(),
              )
              as Map<String, dynamic>;

      expect(project, contains('Pengram.icon in Resources'));
      expect(project, contains('path = ../ios/Runner/Pengram.icon'));
      expect(
        RegExp(
          r'ASSETCATALOG_COMPILER_APPICON_NAME = Pengram;',
        ).allMatches(project),
        hasLength(3),
      );
      expect((definition['supported-platforms'] as Map)['squares'], 'shared');
    },
  );
}
