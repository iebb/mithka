import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/ai_endpoint_style.dart';
import 'package:mithka/settings/ai_settings_controller.dart';
import 'package:mithka/settings/ai_settings_view.dart';
import 'package:mithka/settings/ai_translation_prompt.dart';
import 'package:mithka/settings/apple_pcc_api.dart';
import 'package:mithka/settings/openai_compatible_models_api.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('AI settings uses dedicated provider and model list pages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    String? secureKey;
    Map<String, dynamic>? modelTestPayload;
    var modelListRequests = 0;
    final settings = AiSettingsController(
      preferences,
      pccApi: ApplePccApi(
        invokeMethod: (_, _) async => {
          'sdkAvailable': false,
          'available': false,
          'reason': 'requires_xcode_27',
          'onDeviceSdkAvailable': true,
          'onDeviceAvailable': true,
          'onDeviceReason': 'available',
          'onDeviceContextSize': 4096,
        },
      ),
      modelsApi: OpenAiCompatibleModelsApi(
        httpClient: MockClient((request) async {
          if (request.method == 'POST') {
            modelTestPayload = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              '{"output":[{"type":"message","content":[{"type":"output_text","text":"Hello from the model"}]}]}',
              200,
            );
          }
          modelListRequests += 1;
          return http.Response(
            '{"data":[{"id":"summary-model","context_window_tokens":131072}]}',
            200,
          );
        }),
      ),
      secureRead: (_) async => null,
      secureWrite: (_, value) async => secureKey = value,
    );
    final translation = TranslationController(preferences);
    final theme = ThemeController(preferences);
    addTearDown(settings.dispose);
    addTearDown(translation.dispose);
    addTearDown(theme.dispose);
    await settings.initialize();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: translation),
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
          home: AiSettingsView(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final replyUsingLabel = AppStrings.tForLocale(
      'en',
      AppStringKeys.aiReplyUsing,
    );
    final telegramCocoonLabel = AppStrings.tForLocale(
      'en',
      AppStringKeys.aiProviderTelegramCocoon,
    );

    expect(find.text('AI Settings'), findsOneWidget);
    expect(find.text('Model Configuration'), findsOneWidget);
    expect(find.text('Translate using'), findsOneWidget);
    expect(find.text('Summarize using'), findsOneWidget);
    expect(find.text(replyUsingLabel), findsOneWidget);
    final modelConfigurationCard = tester.widget<SettingsCard>(
      find.ancestor(
        of: find.byKey(const ValueKey('aiTranslationPromptRow')),
        matching: find.byType(SettingsCard),
      ),
    );
    expect(
      modelConfigurationCard.children.whereType<SettingsRow>().map(
        (row) => row.title,
      ),
      [
        'Translate using',
        'Translate Prompts',
        'Summarize using',
        'Summarize Prompts',
        replyUsingLabel,
        'Reply Prompts',
      ],
    );
    expect(tester.widget<AppSwitch>(find.byType(AppSwitch)).value, isFalse);

    await tester.tap(find.byType(SettingsSwitchRow));
    await tester.pumpAndSettle();
    expect(settings.enabled, isTrue);
    expect(
      preferences.getBool(AiSettingsController.enabledPreferenceKey),
      isTrue,
    );

    await tester.tap(find.widgetWithText(SettingsRow, 'Providers'));
    await tester.pumpAndSettle();
    expect(find.text('Add Provider'), findsOneWidget);
    expect(find.text('No provider selected'), findsOneWidget);

    await tester.tap(find.text('Add Provider'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    expect(tester.widget<TextField>(fields.at(2)).obscureText, isTrue);
    await tester.enterText(fields.at(0), 'Summary Provider');
    expect(find.text('OpenAI Chat Completions'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('aiEndpointStyleRow')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenAI Responses'));
    await tester.pumpAndSettle();
    await tester.enterText(
      fields.at(1),
      'https://summary.example/v1/responses',
    );
    await tester.enterText(fields.at(2), 'sk-user-owned');
    await tester.scrollUntilVisible(
      find.text('Save Provider'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Provider'));
    await tester.pumpAndSettle();

    expect(settings.serverProviders, hasLength(1));
    expect(
      settings.serverProviders.single.endpointStyle,
      AiEndpointStyle.openAiResponses,
    );
    expect(settings.modelProfiles, isEmpty);
    expect(find.text('Summary Provider'), findsOneWidget);

    Navigator.of(tester.element(find.byType(AiProviderListView))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SettingsRow, 'Models'));
    await tester.pumpAndSettle();
    expect(find.text('Apple Private Cloud Compute'), findsOneWidget);
    expect(find.text('Apple On-Device Model'), findsOneWidget);
    expect(find.text(telegramCocoonLabel), findsNothing);
    expect(find.byKey(const ValueKey('aiAddModelCard')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('aiAddModelCard')));
    await tester.pumpAndSettle();
    expect(find.text('Summary Provider'), findsOneWidget);
    expect(find.text('Load Models'), findsNothing);
    expect(modelListRequests, 1);
    expect(
      find.byKey(const ValueKey('aiDiscoveredModelSelector')),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('aiEnterModelManually')));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(3));
    await tester.tap(find.byKey(const ValueKey('aiEnterModelManually')));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('aiDiscoveredModelSelector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('summary-model'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.widgetWithText(SettingsRow, 'Model'), findsOneWidget);
    expect(find.text('Detected from provider'), findsOneWidget);
    final testPrompt = find.widgetWithText(TextField, 'Hello');
    expect(testPrompt, findsOneWidget);
    await tester.enterText(testPrompt, 'Reply with a friendly greeting');
    await tester.scrollUntilVisible(
      find.text('Test Model'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Test Model'));
    await tester.pumpAndSettle();
    expect(find.text('Response'), findsOneWidget);
    expect(find.text('Hello from the model'), findsOneWidget);
    expect(modelTestPayload?['model'], 'summary-model');
    expect(modelTestPayload?['input'], 'Reply with a friendly greeting');
    await tester.scrollUntilVisible(
      find.text('Save Model'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Save Model'));
    await tester.pumpAndSettle();

    expect(settings.serverProviders, hasLength(1));
    expect(settings.activeServerProvider?.name, 'Summary Provider');
    expect(settings.modelProfiles, hasLength(1));
    expect(settings.activeModelProfile?.model, 'summary-model');
    expect(settings.activeModelProfile?.contextWindowTokens, 131072);
    expect(settings.activeModelProfile?.contextWindowDetected, isTrue);
    expect(secureKey, 'sk-user-owned');
    expect(preferences.getKeys(), isNot(contains('mithka.ai.api_key.v1')));

    Navigator.of(tester.element(find.byType(AiModelListView))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SettingsRow, 'Translate using'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(telegramCocoonLabel),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('summary-model').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SettingsRow, 'Summarize using'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(telegramCocoonLabel),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Apple On-Device Model').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SettingsRow, replyUsingLabel));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(telegramCocoonLabel),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text(telegramCocoonLabel).last);
    await tester.pumpAndSettle();

    expect(
      settings.translationModelCandidate.kind,
      AiModelCandidateKind.server,
    );
    expect(
      settings.summaryModelCandidate.kind,
      AiModelCandidateKind.appleOnDevice,
    );
    expect(
      settings.replyModelCandidate.kind,
      AiModelCandidateKind.telegramCocoon,
    );
    expect(settings.isConfiguredForFeature(AiFeature.translation), isTrue);
    expect(settings.isConfiguredForFeature(AiFeature.summary), isTrue);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
    'AI prompt editors save and reset reply, translation, and summary',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final settings = AiSettingsController(
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
      final translation = TranslationController(preferences);
      final theme = ThemeController(preferences);
      final originalBrand = AppTheme.brand;
      addTearDown(settings.dispose);
      addTearDown(translation.dispose);
      addTearDown(theme.dispose);
      addTearDown(() => AppTheme.brand = originalBrand);
      await settings.initialize();
      AppTheme.brand = Colors.white;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: translation),
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
            home: AiSettingsView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final replyRow = find.byKey(const ValueKey('aiReplyPromptRow'));
      final translationRow = find.byKey(
        const ValueKey('aiTranslationPromptRow'),
      );
      final summaryRow = find.byKey(const ValueKey('aiSummaryPromptRow'));

      expect(replyRow, findsOneWidget);
      expect(translationRow, findsOneWidget);
      expect(summaryRow, findsOneWidget);
      expect(find.text('Reply Prompts'), findsOneWidget);
      expect(find.text('Translate Prompts'), findsOneWidget);
      expect(find.text('Summarize Prompts'), findsOneWidget);
      expect(tester.widget<SettingsRow>(replyRow).value, 'Default');
      expect(tester.widget<SettingsRow>(translationRow).value, 'Default');
      expect(tester.widget<SettingsRow>(summaryRow).value, 'Default');

      Future<void> savePrompt({
        required Finder row,
        required Key fieldKey,
        required String expectedDefault,
        required String customValue,
        int? maximumCharacters,
      }) async {
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        await tester.tap(row);
        await tester.pumpAndSettle();

        final field = find.byKey(fieldKey);
        expect(field, findsOneWidget);
        expect(
          tester.widget<TextField>(field).controller!.text,
          expectedDefault,
        );
        expect(tester.widget<TextField>(field).maxLength, maximumCharacters);
        expect(
          tester.widget<Text>(find.text('Save')).style?.color,
          readableForeground(AppTheme.brand),
        );

        await tester.enterText(field, customValue);
        await tester.scrollUntilVisible(
          find.text('Save'),
          220,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(tester.widget<SettingsRow>(row).value, 'Custom');
      }

      Future<void> resetPrompt({required Finder row}) async {
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        await tester.tap(row);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Reset to Default'),
          220,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text('Reset to Default'));
        await tester.pumpAndSettle();
        expect(tester.widget<SettingsRow>(row).value, 'Default');
      }

      const customReply = 'Reply with a warm tone and preserve emoji.';
      await savePrompt(
        row: replyRow,
        fieldKey: const ValueKey('aiReplyPromptField'),
        expectedDefault: defaultAiReplyPrompt.trim(),
        customValue: customReply,
        maximumCharacters: AiSettingsController.replyPromptMaximumCharacters,
      );
      expect(settings.aiReplyPrompt, customReply);
      expect(settings.hasCustomAiReplyPrompt, isTrue);
      expect(
        preferences.getString(AiSettingsController.replyPromptPreferenceKey),
        customReply,
      );

      const customTranslation =
          'Translate casually while preserving emoji and line breaks.';
      await savePrompt(
        row: translationRow,
        fieldKey: const ValueKey('aiTranslationPromptField'),
        expectedDefault: defaultAiTranslationPrompt.trim(),
        customValue: customTranslation,
      );
      expect(translation.aiTranslationPrompt, customTranslation);
      expect(translation.hasCustomAiTranslationPrompt, isTrue);
      expect(
        preferences.getString(
          TranslationController.aiTranslationPromptPreferenceKey,
        ),
        customTranslation,
      );

      const customSummary =
          'Lead with decisions, unanswered questions, and concrete next steps.';
      await savePrompt(
        row: summaryRow,
        fieldKey: const ValueKey('aiSummaryPromptField'),
        expectedDefault: defaultAiSummaryPrompt.trim(),
        customValue: customSummary,
        maximumCharacters: AiSettingsController.summaryPromptMaximumCharacters,
      );
      expect(settings.aiSummaryPrompt, customSummary);
      expect(settings.hasCustomAiSummaryPrompt, isTrue);
      expect(
        preferences.getString(AiSettingsController.summaryPromptPreferenceKey),
        customSummary,
      );

      await resetPrompt(row: replyRow);
      expect(settings.aiReplyPrompt, defaultAiReplyPrompt.trim());
      expect(settings.hasCustomAiReplyPrompt, isFalse);
      expect(
        preferences.containsKey(AiSettingsController.replyPromptPreferenceKey),
        isFalse,
      );

      await resetPrompt(row: translationRow);
      expect(
        translation.aiTranslationPrompt,
        defaultAiTranslationPrompt.trim(),
      );
      expect(translation.hasCustomAiTranslationPrompt, isFalse);
      expect(
        preferences.containsKey(
          TranslationController.aiTranslationPromptPreferenceKey,
        ),
        isFalse,
      );

      await resetPrompt(row: summaryRow);
      expect(settings.aiSummaryPrompt, defaultAiSummaryPrompt.trim());
      expect(settings.hasCustomAiSummaryPrompt, isFalse);
      expect(
        preferences.containsKey(
          AiSettingsController.summaryPromptPreferenceKey,
        ),
        isFalse,
      );
      await tester.pump(const Duration(seconds: 2));
    },
  );
}
