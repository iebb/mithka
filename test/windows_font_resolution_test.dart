//
//  windows_font_resolution_test.dart
//
//  Covers P0/P1/P2 fixes for Windows font fallback ordering, BCP-47 locale
//  normalization, monospace defaults, and structured DirectWrite catalog parsing.
//

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/messages/telegram_rich_text.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/appearance/appearance_view.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/emoji_font_catalog.dart';
import 'package:mithka/theme/platform_font_defaults.dart';
import 'package:mithka/theme/system_font_catalog.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => L10nFixtures.load().install());

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    SystemFontCatalog.setKnownLocalFamiliesForTesting(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('mithka/fonts'), null);
  });

  group('PlatformFontDefaults', () {
    test('normalizes bare zh into explicit zh-Hans or zh-Hant', () {
      expect(
        PlatformFontDefaults.normalizeTypographyLocale(
          const Locale('zh'),
        )?.toLanguageTag(),
        'zh-Hans',
      );
      expect(
        PlatformFontDefaults.normalizeTypographyLocale(
          const Locale('zh', 'CN'),
        )?.toLanguageTag(),
        'zh-Hans-CN',
      );
      expect(
        PlatformFontDefaults.normalizeTypographyLocale(
          const Locale('zh', 'TW'),
        )?.toLanguageTag(),
        'zh-Hant-TW',
      );
      expect(
        PlatformFontDefaults.normalizeTypographyLocale(const Locale('und')),
        isNull,
      );
    });

    test(
      'orders Windows CJK fallback by locale without hitting Yu Gothic for SC',
      () {
        final scChain = PlatformFontDefaults.fallbackFontChain(
          platform: TargetPlatform.windows,
          appLocale: const Locale('zh'),
        );
        expect(scChain.indexOf('Microsoft YaHei UI'), greaterThanOrEqualTo(0));
        expect(
          scChain.indexOf('Microsoft YaHei UI'),
          lessThan(scChain.indexOf('Yu Gothic UI')),
        );

        final enChain = PlatformFontDefaults.fallbackFontChain(
          platform: TargetPlatform.windows,
          appLocale: const Locale('en'),
        );
        expect(
          enChain.indexOf('Microsoft YaHei UI'),
          lessThan(enChain.indexOf('Yu Gothic UI')),
        );

        final jaChain = PlatformFontDefaults.fallbackFontChain(
          platform: TargetPlatform.windows,
          appLocale: const Locale('ja'),
        );
        expect(
          jaChain.indexOf('Yu Gothic UI'),
          lessThan(jaChain.indexOf('Microsoft YaHei UI')),
        );

        final tcChain = PlatformFontDefaults.fallbackFontChain(
          platform: TargetPlatform.windows,
          appLocale: const Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hant',
          ),
        );
        expect(
          tcChain.indexOf('Microsoft JhengHei UI'),
          lessThan(tcChain.indexOf('Microsoft YaHei UI')),
        );
      },
    );

    test('provides Windows primary, monospace, and emoji defaults', () {
      expect(
        PlatformFontDefaults.primaryFontFamily(
          platform: TargetPlatform.windows,
        ),
        'Segoe UI',
      );
      expect(
        PlatformFontDefaults.monospaceFontFamily(
          platform: TargetPlatform.windows,
        ),
        'Consolas',
      );
      expect(
        PlatformFontDefaults.emojiFontFallback(
          platform: TargetPlatform.windows,
        ),
        contains('Segoe UI Emoji'),
      );

      final scPriority = PlatformFontDefaults.popularSystemFontPriority(
        platform: TargetPlatform.windows,
        appLocale: const Locale('zh', 'CN'),
      );
      expect(
        scPriority['Microsoft YaHei UI'],
        lessThan(scPriority['Yu Gothic UI']!),
      );
      expect(scPriority['Microsoft YaHei UI'], lessThan(scPriority['Arial']!));
    });
  });

  group('ThemeController Windows typography', () {
    test(
      'defaults monospace to system Consolas and places YaHei before Yu Gothic',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final theme = ThemeController(
          prefs,
          initialAppLocale: const Locale('zh', 'CN'),
        );
        addTearDown(theme.dispose);

        expect(theme.monospaceFontChoice, AppMonospaceFontChoice.system);
        expect(theme.monospaceFontChoice.fontFamily, 'Consolas');

        final chain = theme.effectiveFontFamilyChain();
        expect(chain.first, 'Segoe UI');
        expect(chain.indexOf('Microsoft YaHei UI'), greaterThan(0));
        expect(
          chain.indexOf('Microsoft YaHei UI'),
          lessThan(chain.indexOf('Yu Gothic UI')),
        );
        expect(
          EmojiFontChoice.platformEmojiFontFallback(),
          contains('Segoe UI Emoji'),
        );

        final styled = theme.applyAppTextStyle(const TextStyle(fontSize: 15));
        expect(styled.fontFamily, 'Segoe UI');
        expect(styled.locale?.toLanguageTag(), 'zh-Hans-CN');

        final codeStyle = theme.codeTextStyle(const TextStyle(fontSize: 14));
        expect(codeStyle.fontFamily, 'Consolas');
        expect(codeStyle.locale?.toLanguageTag(), 'zh-Hans-CN');
        expect(codeStyle.fontFamilyFallback, contains('Microsoft YaHei UI'));
      },
    );

    test(
      'treats bare local font name separately from google-prefixed entry',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        SystemFontCatalog.setKnownLocalFamiliesForTesting(const ['Roboto']);
        SharedPreferences.setMockInitialValues({
          'fontFallbackChain': const ['Roboto'],
        });
        final prefs = await SharedPreferences.getInstance();
        final theme = ThemeController(prefs);
        addTearDown(theme.dispose);

        final styled = theme.applyAppTextStyle(const TextStyle(fontSize: 15));
        expect(styled.fontFamily, 'Roboto');
      },
    );

    test(
      'persists explicit local font family synchronously across restart without masking google prefix',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final first = ThemeController(prefs);
        addTearDown(first.dispose);

        first.addFontToFallbackChain('Inter', isLocal: true);
        first.setCustomMonospaceFont('Roboto Mono', isLocal: true);

        expect(first.isLocalFontFamily('Inter'), isTrue);
        expect(first.isLocalFontFamily('Roboto Mono'), isTrue);
        expect(first.isLocalFontFamily('google:Inter'), isFalse);

        // Recreate without SystemFontCatalog populated: frame 1 must stay local.
        SystemFontCatalog.setKnownLocalFamiliesForTesting(null);
        final restarted = ThemeController(prefs);
        addTearDown(restarted.dispose);

        expect(restarted.isLocalFontFamily('Inter'), isTrue);
        expect(restarted.isLocalFontFamily('Roboto Mono'), isTrue);
        final restartedStyle = restarted.applyAppTextStyle(
          const TextStyle(fontSize: 15),
        );
        expect(restartedStyle.fontFamily, 'Inter');

        // Clearing the chain prunes unreferenced local markers (keeps Mono).
        restarted.setFontFallbackChain(const ['google:Inter']);
        expect(restarted.isLocalFontFamily('Inter'), isFalse);
        expect(restarted.isLocalFontFamily('google:Inter'), isFalse);
        expect(restarted.isLocalFontFamily('Roboto Mono'), isTrue);
      },
    );
  });

  group('PlatformFontDefaults rankSystemFontFamily', () {
    test(
      'ranks body faces above Yu Gothic and avoids promoting Segoe UI Emoji',
      () {
        final yaheiRank = PlatformFontDefaults.rankSystemFontFamily(
          'Microsoft YaHei UI',
          platform: TargetPlatform.windows,
          appLocale: const Locale('zh', 'CN'),
        );
        final yuRank = PlatformFontDefaults.rankSystemFontFamily(
          'Yu Gothic UI',
          platform: TargetPlatform.windows,
          appLocale: const Locale('zh', 'CN'),
        );
        final segoeVarRank = PlatformFontDefaults.rankSystemFontFamily(
          'Segoe UI Variable',
          platform: TargetPlatform.windows,
          appLocale: const Locale('zh', 'CN'),
        );
        final segoeEmojiRank = PlatformFontDefaults.rankSystemFontFamily(
          'Segoe UI Emoji',
          platform: TargetPlatform.windows,
          appLocale: const Locale('zh', 'CN'),
        );
        expect(yaheiRank, lessThan(yuRank));
        expect(segoeVarRank, lessThan(yaheiRank));
        expect(segoeEmojiRank, greaterThan(yaheiRank));
      },
    );
  });

  group('SystemFontCatalog structured and legacy payloads', () {
    test(
      'parses Windows structured entries and legacy iOS/Android string lists',
      () {
        final structured = SystemFontCatalog.parseRawFontList(const [
          {
            'family': 'Microsoft YaHei UI',
            'displayName': '微软雅黑 UI',
            'isMonospace': false,
          },
          {
            'family': 'Consolas',
            'displayName': 'Consolas',
            'isMonospace': true,
          },
        ]);
        expect(structured, hasLength(2));
        expect(structured[0].family, 'Consolas');
        expect(structured[0].isMonospace, isTrue);
        expect(structured[1].family, 'Microsoft YaHei UI');
        expect(structured[1].displayName, '微软雅黑 UI');
        expect(structured[1].isMonospace, isFalse);

        final legacy = SystemFontCatalog.parseRawFontList(const [
          'PingFang SC',
          'Arial',
          'PingFang SC',
        ]);
        expect(legacy.map((e) => e.family).toList(), ['Arial', 'PingFang SC']);
        expect(legacy.first.isMonospace, isNull);
      },
    );

    test(
      'preserves google prefix and populates known local families via channel',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('mithka/fonts'), (
              call,
            ) async {
              if (call.method == 'listFonts') {
                return const [
                  {
                    'family': 'Microsoft YaHei',
                    'displayName': '微软雅黑',
                    'isMonospace': false,
                  },
                  {
                    'family': 'Consolas',
                    'displayName': 'Consolas',
                    'isMonospace': true,
                  },
                ];
              }
              if (call.method == 'normalizeFontFamilies') {
                final args = (call.arguments as List<dynamic>).cast<String>();
                return [
                  for (final item in args)
                    item == '微软雅黑' ? 'Microsoft YaHei' : '',
                ];
              }
              return null;
            });

        final entries = await SystemFontCatalog.loadFontEntries();
        expect(entries.map((e) => e.family).toList(), [
          'Consolas',
          'Microsoft YaHei',
        ]);
        expect(SystemFontCatalog.isKnownLocalFamily('Microsoft YaHei'), isTrue);

        final normalized = await SystemFontCatalog.normalizeFamilies(const [
          '微软雅黑',
          'google:Roboto',
          '',
        ]);
        expect(normalized, const ['Microsoft YaHei', 'google:Roboto', '']);
      },
    );

    test(
      'iOS verbatim normalizeFamilies result does not poison known local families',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        SystemFontCatalog.setKnownLocalFamiliesForTesting(const [
          '.AppleSystemUIFont',
        ]);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('mithka/fonts'), (
              call,
            ) async {
              if (call.method == 'normalizeFontFamilies') {
                return (call.arguments as List<dynamic>).cast<String>();
              }
              return null;
            });

        final normalized = await SystemFontCatalog.normalizeFamilies(const [
          'Roboto',
        ]);
        expect(normalized, const ['Roboto']);
        expect(SystemFontCatalog.isKnownLocalFamily('Roboto'), isFalse);
      },
    );
  });

  testWidgets(
    'TelegramRichText renders code entities safely without ThemeController',
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          home: const Scaffold(
            body: TelegramRichText(
              text: 'print("ok")',
              entities: [
                MessageTextEntity(
                  offset: 0,
                  length: 11,
                  type: 'textEntityTypeCode',
                ),
              ],
              style: TextStyle(fontSize: 14),
            ),
          ),
        ),
      );

      final codeText = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('telegram-rich-inline-code')),
          matching: find.byType(Text),
        ),
      );
      expect(codeText.style?.fontFamily, 'Consolas');
      expect(codeText.style?.fontFamilyFallback, contains('Cascadia Mono'));
    },
  );

  Future<ThemeController> pumpMonospacePicker(
    WidgetTester tester, {
    required List<Map<String, Object?>> fonts,
  }) async {
    final tempDir = Directory.systemTemp.createTempSync('mono_picker_test');
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('mithka/fonts'), (
          call,
        ) async {
          if (call.method == 'listFonts') return fonts;
          return null;
        });

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppColors.light]),
          home: const MonospaceFontPickerView(),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.text('Consolas').evaluate().isNotEmpty ||
          find.text('Menlo').evaluate().isNotEmpty) {
        break;
      }
    }
    return theme;
  }

  testWidgets(
    'MonospaceFontPickerView shows Consolas and marks selected local font',
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    (tester) async {
      final theme = await pumpMonospacePicker(
        tester,
        fonts: const [
          {
            'family': 'Consolas',
            'displayName': 'Consolas',
            'isMonospace': true,
          },
          {
            'family': 'Fira Code',
            'displayName': 'Fira Code',
            'isMonospace': true,
          },
        ],
      );

      expect(
        find.text(AppStrings.t(AppStringKeys.themeSystemMonospace)),
        findsOneWidget,
      );
      expect(find.text('Consolas'), findsOneWidget);
      expect(find.text('Fira Code'), findsOneWidget);

      await tester.tap(find.text('Fira Code'));
      await tester.pump();
      expect(theme.monospaceFontChoice, AppMonospaceFontChoice.custom);
      expect(theme.customMonospaceFontFamily, 'Fira Code');
      expect(theme.isLocalFontFamily('Fira Code'), isTrue);
    },
  );

  testWidgets(
    'MonospaceFontPickerView includes System Monospace on macOS',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      await pumpMonospacePicker(
        tester,
        fonts: const [
          {'family': 'Menlo', 'displayName': 'Menlo', 'isMonospace': true},
        ],
      );

      expect(
        find.text(AppStrings.t(AppStringKeys.themeSystemMonospace)),
        findsOneWidget,
      );
      expect(find.text('Menlo'), findsOneWidget);
    },
  );

  testWidgets(
    'TelegramRichText applies Windows theme fallback and locale to RichText',
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(
        prefs,
        initialAppLocale: const Locale('zh'),
      );
      addTearDown(theme.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: theme,
          child: const MaterialApp(
            home: Scaffold(
              body: TelegramRichText(
                text: '中文消息测试',
                style: TextStyle(fontSize: 15),
              ),
            ),
          ),
        ),
      );

      final richText = tester.widget<RichText>(
        find.descendant(
          of: find.byType(TelegramRichText),
          matching: find.byType(RichText),
        ),
      );
      expect(richText.locale?.toLanguageTag(), 'zh-Hans');
      expect(richText.text.style?.fontFamily, 'Segoe UI');
      expect(
        richText.text.style?.fontFamilyFallback,
        contains('Microsoft YaHei UI'),
      );
    },
  );
}
