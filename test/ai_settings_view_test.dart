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
  testWidgets('AI settings configures server mode and keeps its key secure', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    String? secureKey;
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
        httpClient: MockClient(
          (request) async => http.Response(
            '{"data":[{"id":"summary-model","context_window_tokens":131072}]}',
            200,
          ),
        ),
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
    expect(find.text('Processing Mode'), findsWidgets);
    expect(find.text('Unavailable on this device'), findsOneWidget);
    expect(tester.widget<AppSwitch>(find.byType(AppSwitch)).value, isFalse);

    await tester.tap(find.byType(SettingsSwitchRow));
    await tester.pumpAndSettle();
    expect(settings.enabled, isTrue);
    expect(
      preferences.getBool(AiSettingsController.enabledPreferenceKey),
      isTrue,
    );

    await tester.tap(find.text('Apple Private Cloud Compute').first);
    await tester.pumpAndSettle();
    expect(find.text('Apple On-Device Model'), findsOneWidget);
    await tester.tap(find.text('Apple On-Device Model'));
    await tester.pumpAndSettle();
    expect(settings.provider, AiProviderMode.appleOnDevice);
    expect(find.text('4K-token context window'), findsOneWidget);

    await tester.tap(find.text('Apple On-Device Model').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom Server').last);
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

    expect(settings.isConfiguredForCurrentProvider, isFalse);
    expect(settings.serverProviders, hasLength(1));
    expect(settings.modelProfiles, isEmpty);

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Model'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Summary Provider').last);
    await tester.pumpAndSettle();
    expect(find.text('Enter Model Manually'), findsOneWidget);
    await tester.tap(find.text('summary-model'));
    await tester.pumpAndSettle();

    expect(find.text('Detected from provider'), findsOneWidget);
    final modelFields = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );
    expect(modelFields, findsNWidgets(2));
    expect(tester.widget<TextField>(modelFields.first).readOnly, isTrue);
    await tester.tap(find.text('Save Model'));
    await tester.pumpAndSettle();

    expect(settings.isConfiguredForCurrentProvider, isTrue);
    expect(settings.serverProviders, hasLength(1));
    expect(settings.activeServerProvider?.name, 'Summary Provider');
    expect(settings.modelProfiles, hasLength(1));
    expect(settings.activeModelProfile?.model, 'summary-model');
    expect(settings.activeModelProfile?.contextWindowTokens, 131072);
    expect(settings.activeModelProfile?.contextWindowDetected, isTrue);
    expect(secureKey, 'sk-user-owned');
    expect(preferences.getKeys(), isNot(contains('mithka.ai.api_key.v1')));
    await tester.pump(const Duration(seconds: 2));
  });
}
