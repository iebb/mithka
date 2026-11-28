import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/ai_translation/translation_fallback.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/ai_translation/ai_settings_controller.dart';
import 'package:mithka/settings/ai_translation/ai_settings_view.dart';
import 'package:mithka/settings/ai_translation/apple_pcc_api.dart';
import 'package:mithka/settings/ai_translation/translation_controller.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/l10n_fixtures.dart';

void main() {
  setUpAll(() {
    L10nFixtures.load();
  });

  group('AI settings and Translation Options consolidation (#327)', () {
    testWidgets(
      'AiSettingsView omits the redundant Translate using row and exposes local-network proxy bypass',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final theme = ThemeController(prefs);
        final ai = AiSettingsController(
          prefs,
          pccApi: _pccApi(available: false),
          secureRead: (_) async => null,
          secureWrite: (_, _) async {},
        );
        await ai.initialize();
        final translation = TranslationController(
          prefs,
          secureRead: (_) async => null,
          secureWrite: (_, _) async {},
        );

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeController>.value(value: theme),
              ChangeNotifierProvider<AiSettingsController>.value(value: ai),
              ChangeNotifierProvider<TranslationController>.value(
                value: translation,
              ),
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
              home: AiSettingsView(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(AppStrings.t(AppStringKeys.aiTranslateUsing)),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('aiTranslationPromptRow')),
          findsOneWidget,
        );
        expect(
          find.text(AppStrings.t(AppStringKeys.aiSummarizeUsing)),
          findsOneWidget,
        );
        expect(
          find.text(AppStrings.t(AppStringKeys.aiReplyUsing)),
          findsOneWidget,
        );

        final bypassRow = find.byKey(
          const ValueKey('aiBypassProxyForLocalNetworksRow'),
        );
        expect(bypassRow, findsOneWidget);
        expect(ai.bypassProxyForLocalNetworks, isTrue);

        await tester.tap(bypassRow);
        await tester.pumpAndSettle();
        expect(ai.bypassProxyForLocalNetworks, isFalse);

        theme.dispose();
        ai.dispose();
        translation.dispose();
      },
    );

    test(
      'effectiveTranslationOptionIds follows enabled order for Cocoon and Google Translate',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final ai = AiSettingsController(
          prefs,
          pccApi: _pccApi(available: false),
          secureRead: (_) async => null,
          secureWrite: (_, _) async {},
        );
        await ai.initialize();
        final translation = TranslationController(
          prefs,
          secureRead: (_) async => null,
          secureWrite: (_, _) async {},
        );

        // Default config has only Telegram Translation enabled.
        expect(
          effectiveTranslationOptionIds(
            translation: translation,
            ai: ai,
            nativeProviders: const {},
            isBotApiAccount: false,
          ),
          [TranslationOptionIds.telegramTranslation],
        );

        // Enable Cocoon and Google Translate, disable Telegram Translation,
        // and place Cocoon before Google Translate.
        translation.setTranslationOptionEnabled(
          TranslationOptionIds.telegramTranslation,
          false,
        );
        translation.setTranslationOptionEnabled(
          TranslationOptionIds.telegramCocoon,
          true,
        );
        translation.setTranslationOptionEnabled(
          TranslationOptionIds.googleTranslate,
          true,
        );
        final ordered = translation.orderedTranslationOptions([
          TranslationOptionIds.telegramTranslation,
          TranslationOptionIds.telegramCocoon,
          TranslationOptionIds.googleTranslate,
        ]);
        final cocoonIdx = ordered.indexOf(TranslationOptionIds.telegramCocoon);
        translation.reorderTranslationOptions(ordered, cocoonIdx, 0);

        expect(
          effectiveTranslationOptionIds(
            translation: translation,
            ai: ai,
            nativeProviders: const {},
            isBotApiAccount: false,
          ),
          [
            TranslationOptionIds.telegramCocoon,
            TranslationOptionIds.googleTranslate,
          ],
        );

        ai.dispose();
        translation.dispose();
      },
    );

    test(
      'migration preserves existing enabled options and only adds legacy AI model when upgrading without enabled list',
      () async {
        // Case 1: Legacy config without translation.options.enabled.v1 and AI translation enabled.
        SharedPreferences.setMockInitialValues({
          'translation.ai.enabled': true,
          AiSettingsController.translationModelCandidatePreferenceKey:
              AiSettingsController.telegramCocoonModelCandidateId,
        });
        var prefs = await SharedPreferences.getInstance();
        var translation = TranslationController(
          prefs,
          secureRead: (_) async => null,
          secureWrite: (_, _) async {},
        );
        expect(
          translation.enabledTranslationOptionIds,
          containsAll([
            TranslationOptionIds.telegramCocoon,
            TranslationOptionIds.telegramTranslation,
          ]),
        );
        translation.dispose();

        // Case 2: Existing config WITH translation.options.enabled.v1 is preserved untouched.
        SharedPreferences.setMockInitialValues({
          'translation.ai.enabled': true,
          AiSettingsController.translationModelCandidatePreferenceKey:
              AiSettingsController.telegramCocoonModelCandidateId,
          'translation.options.enabled.v1': [
            TranslationOptionIds.googleTranslate,
          ],
        });
        prefs = await SharedPreferences.getInstance();
        translation = TranslationController(
          prefs,
          secureRead: (_) async => null,
          secureWrite: (_, _) async {},
        );
        expect(
          translation.enabledTranslationOptionIds,
          equals({TranslationOptionIds.googleTranslate}),
        );
        translation.dispose();
      },
    );
  });
}

ApplePccApi _pccApi({required bool available}) => ApplePccApi(
  invokeMethod: (_, _) async => {
    'sdkAvailable': available,
    'available': available,
    'reason': available ? '' : 'unsupported',
    'contextSize': available ? 32768 : 0,
    'quotaLimitReached': false,
    'quotaApproachingLimit': false,
  },
);
