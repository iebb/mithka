import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/appearance_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/system_font_catalog.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.supportPath);

  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const fontsChannel = MethodChannel('mithka/fonts');

  late ThemeController theme;
  late PathProviderPlatform originalPathProvider;
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    theme = ThemeController(await SharedPreferences.getInstance());
    originalPathProvider = PathProviderPlatform.instance;
    tempDir = await Directory.systemTemp.createTemp('mithka_font_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(
      '${tempDir.path}/missing',
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(fontsChannel, null);
    debugDefaultTargetPlatformOverride = null;
    PathProviderPlatform.instance = originalPathProvider;
    theme.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget wrap(Widget child) {
    return ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        home: child,
      ),
    );
  }

  test(
    'SystemFontCatalog.loadFonts trims, dedupes, and sorts families',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(fontsChannel, (call) async {
            if (call.method == 'listFonts') {
              return <String>[
                '  Segoe UI  ',
                '',
                'arial',
                'Segoe UI',
                'Consolas',
                '   ',
              ];
            }
            return null;
          });

      final fonts = await SystemFontCatalog.loadFonts();
      expect(fonts, ['arial', 'Consolas', 'Segoe UI']);
    },
  );

  test(
    'SystemFontCatalog.normalizeFamilies preserves macOS system aliases',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(fontsChannel, (call) async {
            if (call.method == 'normalizeFontFamilies') {
              return <String>['.SF NS', 'Helvetica Neue'];
            }
            return null;
          });

      final normalized = await SystemFontCatalog.normalizeFamilies([
        '.AppleSystemUIFont',
        'HelveticaNeue-Bold',
      ]);
      expect(normalized, ['.AppleSystemUIFont', 'Helvetica Neue']);
    },
  );

  for (final entry in <(TargetPlatform, List<String>)>[
    (TargetPlatform.macOS, ['Helvetica Neue', 'My Custom Mac Font']),
    (TargetPlatform.windows, ['Segoe UI', 'My Custom Windows Font']),
    (TargetPlatform.linux, ['Ubuntu', 'My Custom Linux Font']),
  ]) {
    final (platform, installedFonts) = entry;
    testWidgets(
      'FontAddView displays installed machine fonts on ${platform.name}',
      variant: TargetPlatformVariant.only(platform),
      (tester) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(fontsChannel, (call) async {
              if (call.method == 'listFonts') {
                return installedFonts;
              }
              return null;
            });

        await tester.pumpWidget(wrap(const FontAddView()));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();

        for (final font in installedFonts) {
          expect(find.text(font), findsOneWidget);
        }
      },
    );
  }

  testWidgets(
    'MonospaceFontPickerView includes desktop installed monospace fonts',
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(fontsChannel, (call) async {
            if (call.method == 'listFonts') {
              return <String>['Segoe UI', 'Consolas', 'Cascadia Code', 'Arial'];
            }
            return null;
          });

      await tester.pumpWidget(wrap(const MonospaceFontPickerView()));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Consolas'), findsOneWidget);
      expect(find.text('Cascadia Code'), findsOneWidget);
      expect(find.text('Segoe UI'), findsNothing);
      expect(find.text('Arial'), findsNothing);
    },
  );
}
