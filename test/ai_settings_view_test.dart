import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/ai_settings_controller.dart';
import 'package:mithka/settings/ai_settings_view.dart';
import 'package:mithka/settings/apple_pcc_api.dart';
import 'package:mithka/settings/openai_compatible_models_api.dart';
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
              '{"choices":[{"message":{"content":"Hello from the model"}}]}',
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
    final theme = ThemeController(preferences);
    addTearDown(settings.dispose);
    addTearDown(theme.dispose);
    await settings.initialize();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
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

    expect(find.text('AI Settings'), findsOneWidget);
    expect(find.text('Model Configuration'), findsOneWidget);
    expect(find.text('Translate using'), findsOneWidget);
    expect(find.text('Summarize using'), findsOneWidget);
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
    await tester.enterText(
      fields.at(1),
      'https://summary.example/v1/chat/completions',
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
    expect(settings.modelProfiles, isEmpty);
    expect(find.text('Summary Provider'), findsOneWidget);

    Navigator.of(tester.element(find.byType(AiProviderListView))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SettingsRow, 'Models'));
    await tester.pumpAndSettle();
    expect(find.text('Apple Private Cloud Compute'), findsOneWidget);
    expect(find.text('Apple On-Device Model'), findsOneWidget);
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
    expect(
      (modelTestPayload?['messages'] as List).single['content'],
      'Reply with a friendly greeting',
    );
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
    await tester.tap(find.text('summary-model').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SettingsRow, 'Summarize using'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apple On-Device Model').last);
    await tester.pumpAndSettle();

    expect(
      settings.translationModelCandidate.kind,
      AiModelCandidateKind.server,
    );
    expect(
      settings.summaryModelCandidate.kind,
      AiModelCandidateKind.appleOnDevice,
    );
    expect(settings.isConfiguredForFeature(AiFeature.translation), isTrue);
    expect(settings.isConfiguredForFeature(AiFeature.summary), isTrue);
    await tester.pump(const Duration(seconds: 2));
  });
}
