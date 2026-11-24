//
//  splash_view_icon_test.dart
//
//  The startup screen follows the chosen launcher icon. Android 12+ opens the
//  app with that icon on the launch background, so a different icon on the
//  next screen looked like the choice had not stuck.
//

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/content_view.dart' show SplashView;
import 'package:mithka/settings/app_icon_controller.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('mithka/app_icon');
  String nativeIcon = 'default';

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return switch (call.method) {
            'isSupported' => true,
            'currentIcon' => nativeIcon,
            _ => null,
          };
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pumpSplash(WidgetTester tester, {String? icon}) async {
    Widget splash = MaterialApp(
      theme: ThemeData(extensions: [AppColors.light]),
      home: const SplashView(),
    );
    if (icon != null) {
      nativeIcon = icon;
      SharedPreferences.setMockInitialValues({'selected_app_icon': icon});
      final controller = AppIconController(
        await SharedPreferences.getInstance(),
        platform: TargetPlatform.android,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      splash = ChangeNotifierProvider.value(value: controller, child: splash);
    }
    await tester.pumpWidget(splash);
  }

  String? assetOf(Image image) {
    final provider = image.image;
    final asset = provider is ResizeImage ? provider.imageProvider : provider;
    return asset is AssetImage ? asset.assetName : null;
  }

  Finder imageOf(String asset) => find.byWidgetPredicate(
    (widget) => widget is Image && assetOf(widget) == asset,
  );

  /// Android and iOS bundle only the picker artwork; the full launcher PNGs
  /// are declared for macOS alone, so the splash must never name one.
  void expectBundledEverywhere(String asset) {
    expect(asset, startsWith('assets/app_icons/picker/'));
    expect(File(asset).existsSync(), isTrue, reason: asset);
  }

  testWidgets('a chosen icon is drawn as itself on the launch background', (
    tester,
  ) async {
    await pumpSplash(tester, icon: 'aurora');

    expect(find.byKey(const ValueKey('splash-icon-aurora')), findsOneWidget);
    final asset = AppIconVariant.aurora.standardPickerAsset(Brightness.light);
    expect(imageOf(asset), findsOneWidget);
    expectBundledEverywhere(asset);
    expect(imageOf('assets/penguin.png'), findsNothing);
    final background = tester.widget<ColoredBox>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('splash-icon-aurora')),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    expect(background.color, AppColors.light.background);
  });

  testWidgets('a penguin is drawn with its background-free art', (
    tester,
  ) async {
    await pumpSplash(tester, icon: 'pilot');

    expect(find.byKey(const ValueKey('splash-icon-pilot')), findsOneWidget);
    expect(imageOf(AppIconVariant.pilot.pickerAsset), findsOneWidget);
    expectBundledEverywhere(AppIconVariant.pilot.pickerAsset);
  });

  test('every icon the splash can draw ships on every platform', () {
    for (final icon in AppIconVariant.values) {
      if (icon.isStandard) {
        for (final brightness in Brightness.values) {
          expectBundledEverywhere(icon.standardPickerAsset(brightness));
        }
      } else {
        expectBundledEverywhere(icon.pickerAsset);
      }
    }
  });

  testWidgets('the default icon keeps the gradient penguin screen', (
    tester,
  ) async {
    await pumpSplash(tester, icon: 'default');
    expect(imageOf('assets/penguin.png'), findsOneWidget);
    expect(find.byKey(const ValueKey('splash-icon-default')), findsNothing);
  });

  testWidgets('without an icon controller it shows the default screen', (
    tester,
  ) async {
    await pumpSplash(tester);
    expect(imageOf('assets/penguin.png'), findsOneWidget);
  });
}
