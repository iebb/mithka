import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/ai_settings_controller.dart';
import 'package:mithka/settings/ai_translation_prompt.dart';
import 'package:mithka/settings/apple_pcc_api.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/settings/translation_settings_view.dart';
import 'package:mithka/theme/app_motion.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('translation settings uses one sortable provider fallback list', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final translation = TranslationController(preferences);
    final ai = AiSettingsController(
      preferences,
      pccApi: ApplePccApi(
        invokeMethod: (_, _) async => {
          'sdkAvailable': false,
          'available': false,
          'reason': 'unavailable',
        },
      ),
      secureRead: (_) async => null,
      secureWrite: (_, _) async {},
    );
    final theme = ThemeController(preferences);
    addTearDown(translation.dispose);
    addTearDown(ai.dispose);
    addTearDown(theme.dispose);
    await ai.initialize();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: translation),
          ChangeNotifierProvider.value(value: ai),
          ChangeNotifierProvider.value(value: theme),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: TranslationSettingsView(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Translate Options'), findsOneWidget);
    expect(find.text('Standard Translation'), findsNothing);
    expect(find.text('AI Translation'), findsNothing);
    expect(find.text('Use AI for Translations'), findsNothing);
    expect(find.text('Telegram Translation'), findsOneWidget);
    expect(find.text('Telegram Cocoon'), findsOneWidget);
    expect(find.text('Apple Private Cloud Compute'), findsOneWidget);
    expect(find.text('Apple On-Device Model'), findsOneWidget);
    expect(find.text('Google Translate'), findsOneWidget);
    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(find.byType(ReorderableDragStartListener), findsWidgets);
    expect(find.text('Translation Prompt'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Translation Display'), findsOneWidget);
    expect(find.text('Quote style'), findsOneWidget);

    translation.reorderTranslationOptions(
      const [
        TranslationOptionIds.telegramTranslation,
        TranslationOptionIds.telegramCocoon,
        TranslationOptionIds.googleTranslate,
      ],
      2,
      1,
    );
    await tester.pumpAndSettle();
    expect(translation.translationOptionPriorityOverrides, isNotEmpty);

    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('translation-fallback-description')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('translation-options-reset')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('translation-options-reset')));
    await tester.pumpAndSettle();
    expect(translation.translationOptionPriorityOverrides, isEmpty);
    expect(
      find.text('Enabled options are tried from top to bottom.'),
      findsOneWidget,
    );

    await tester.drag(find.byType(ListView).first, const Offset(0, 500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Translation Display'));
    await tester.pumpAndSettle();
    expect(find.text('Translated only'), findsOneWidget);
    expect(find.text('Original and translation'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('translation-display-style-translatedOnly')),
    );
    await tester.pumpAndSettle();
    expect(translation.displayStyle, TranslationDisplayStyle.translatedOnly);
    expect(
      preferences.getString('translation.displayStyle'),
      'translated_only',
    );

    final cocoonSwitch = find.byKey(
      const ValueKey('translation-option-switch-ai:builtin:telegram_cocoon'),
    );
    await tester.ensureVisible(cocoonSwitch);
    await tester.tap(cocoonSwitch);
    await tester.pumpAndSettle();

    expect(translation.aiTranslationEnabled, isTrue);
    expect(preferences.getBool('translation.ai.enabled'), isTrue);
    expect(
      translation.enabledTranslationOptionIds,
      contains('ai:builtin:telegram_cocoon'),
    );

    final pccSwitch = tester.widget<AppSwitch>(
      find.byKey(
        const ValueKey('translation-option-switch-ai:builtin:apple_pcc'),
      ),
    );
    expect(pccSwitch.enabled, isFalse);

    await tester.drag(find.byType(ListView).first, const Offset(0, 1000));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Translation Prompt'));
    await tester.tap(find.text('Translation Prompt'));
    await tester.pumpAndSettle();
    expect(find.text('Reset to Default'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('aiTranslationPromptField')),
      'Translate casually and preserve emoji. Return translation JSON.',
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -240));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Prompt'));
    await tester.pumpAndSettle();

    expect(translation.hasCustomAiTranslationPrompt, isTrue);
    expect(find.text('Custom'), findsOneWidget);
    expect(
      preferences.getString(
        TranslationController.aiTranslationPromptPreferenceKey,
      ),
      contains('Translate casually'),
    );

    await tester.tap(find.text('Translation Prompt'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -240));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset to Default'));
    await tester.tap(find.text('Save Prompt'));
    await tester.pumpAndSettle();

    expect(translation.aiTranslationPrompt, defaultAiTranslationPrompt.trim());
    expect(translation.hasCustomAiTranslationPrompt, isFalse);
    expect(find.text('Default'), findsOneWidget);
  });

  testWidgets('desktop translation display opens beside its settings row', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final translation = TranslationController(preferences);
    final ai = AiSettingsController(
      preferences,
      pccApi: ApplePccApi(
        invokeMethod: (_, _) async => {
          'sdkAvailable': false,
          'available': false,
          'reason': 'unavailable',
        },
      ),
      secureRead: (_) async => null,
      secureWrite: (_, _) async {},
    );
    final theme = ThemeController(preferences);
    addTearDown(translation.dispose);
    addTearDown(ai.dispose);
    addTearDown(theme.dispose);
    await ai.initialize();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: translation),
          ChangeNotifierProvider.value(value: ai),
          ChangeNotifierProvider.value(value: theme),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            platform: TargetPlatform.macOS,
            extensions: [AppColors.light],
          ),
          home: const TranslationSettingsView(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final label = find.text('Translation Display');
    final row = find.ancestor(of: label, matching: find.byType(SettingsRow));
    final rowRect = tester.getRect(row);
    await tester.tap(label);
    await tester.pumpAndSettle();

    final menu = find.byKey(const ValueKey('translation-display-style-menu'));
    expect(menu, findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byKey(appCenteredModalFrameKey), findsNothing);
    final menuRect = tester.getRect(menu);
    expect(menuRect.top, greaterThanOrEqualTo(rowRect.bottom));
    expect(menuRect.right, closeTo(rowRect.right, 0.01));

    await tester.tap(
      find.byKey(const ValueKey('translation-display-style-translatedOnly')),
    );
    await tester.pumpAndSettle();
    expect(translation.displayStyle, TranslationDisplayStyle.translatedOnly);
    expect(menu, findsNothing);

    await tester.tap(find.text('Do Not Translate'));
    await tester.pumpAndSettle();
    final simplified = find.byKey(
      const ValueKey('translation-ignored-language-zh-Hans'),
    );
    final traditional = find.byKey(
      const ValueKey('translation-ignored-language-zh-Hant'),
    );
    await tester.tap(simplified);
    await tester.pump();
    expect(translation.ignoredLanguageCodes, {'zh-Hans'});
    await tester.tap(traditional);
    await tester.pump();
    expect(translation.ignoredLanguageCodes, {'zh-Hans', 'zh-Hant'});
    await tester.tap(simplified);
    await tester.pump();
    expect(translation.ignoredLanguageCodes, {'zh-Hant'});

    final russian = find.byKey(
      const ValueKey('translation-ignored-language-ru'),
    );
    await tester.scrollUntilVisible(
      russian,
      160,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('translation-ignored-languages-menu')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(russian);
    await tester.pump();
    expect(translation.ignoredLanguageCodes, {'zh-Hant', 'ru'});
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Google Cloud provider settings add and edit independent keys', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final secureValues = <String, String>{};
    final translation = TranslationController(
      preferences,
      secureRead: (key) async => secureValues[key],
      secureWrite: (key, value) async {
        if (value == null) {
          secureValues.remove(key);
        } else {
          secureValues[key] = value;
        }
      },
    );
    final existing = await translation.saveGoogleCloudProvider(
      name: 'Personal Google',
      apiKey: 'personal-test-key',
    );
    final ai = AiSettingsController(
      preferences,
      pccApi: ApplePccApi(
        invokeMethod: (_, _) async => {
          'sdkAvailable': false,
          'available': false,
          'reason': 'unavailable',
        },
      ),
      secureRead: (_) async => null,
      secureWrite: (_, _) async {},
    );
    final theme = ThemeController(preferences);
    addTearDown(translation.dispose);
    addTearDown(ai.dispose);
    addTearDown(theme.dispose);
    await ai.initialize();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: translation),
          ChangeNotifierProvider.value(value: ai),
          ChangeNotifierProvider.value(value: theme),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: TranslationSettingsView(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        ValueKey(
          'translation-option-${TranslationOptionIds.googleCloud(existing.id)}',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Personal Google'), findsOneWidget);

    final settingsRow = find.byKey(
      const ValueKey('google-cloud-providers-settings'),
    );
    await tester.scrollUntilVisible(
      settingsRow,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(settingsRow);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(ValueKey('google-cloud-provider-${existing.id}')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('google-cloud-provider-api-key')),
          )
          .controller!
          .text,
      'personal-test-key',
    );
    await tester.enterText(
      find.byKey(const ValueKey('google-cloud-provider-name')),
      'Renamed Google',
    );
    await tester.enterText(
      find.byKey(const ValueKey('google-cloud-provider-api-key')),
      'renamed-test-key',
    );
    await tester.tap(find.byKey(const ValueKey('google-cloud-provider-save')));
    await tester.pumpAndSettle();
    expect(
      translation.googleCloudProviderById(existing.id)?.name,
      'Renamed Google',
    );
    expect(
      await translation.googleCloudApiKeyForProvider(existing.id),
      'renamed-test-key',
    );

    await tester.tap(find.byKey(const ValueKey('google-cloud-provider-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('google-cloud-provider-name')),
      'Work Google',
    );
    await tester.enterText(
      find.byKey(const ValueKey('google-cloud-provider-api-key')),
      'work-test-key',
    );
    await tester.tap(find.byKey(const ValueKey('google-cloud-provider-save')));
    await tester.pumpAndSettle();

    expect(translation.googleCloudProviders.map((value) => value.name), [
      'Renamed Google',
      'Work Google',
    ]);
    expect(
      preferences.getString('translation.googleCloud.providers.v1'),
      isNot(contains('work-test-key')),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });
}
