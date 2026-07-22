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
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'translation settings keeps AI providers in a dedicated section',
    (tester) async {
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

      expect(find.text('AI Translation'), findsOneWidget);
      expect(find.text('Standard Translation'), findsOneWidget);
      expect(find.text('Use AI for Translations'), findsOneWidget);
      expect(find.text('Apple Private Cloud Compute'), findsOneWidget);
      expect(find.text('Translation Prompt'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);

      final switches = find.byType(AppSwitch);
      expect(switches, findsNWidgets(3));
      await tester.tap(switches.at(2));
      await tester.pumpAndSettle();

      expect(translation.aiTranslationEnabled, isTrue);
      expect(preferences.getBool('translation.ai.enabled'), isTrue);

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

      expect(
        translation.aiTranslationPrompt,
        defaultAiTranslationPrompt.trim(),
      );
      expect(translation.hasCustomAiTranslationPrompt, isFalse);
      expect(find.text('Default'), findsOneWidget);
    },
  );
}
