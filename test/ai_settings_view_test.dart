import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/ai_settings_controller.dart';
import 'package:mithka/settings/ai_settings_view.dart';
import 'package:mithka/settings/apple_pcc_api.dart';
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
        },
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
    await tester.tap(find.text('OpenAI-compatible Server').last);
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    expect(tester.widget<TextField>(fields.at(2)).obscureText, isTrue);
    await tester.enterText(
      fields.at(0),
      'https://summary.example/v1/chat/completions',
    );
    await tester.enterText(fields.at(1), 'summary-model');
    await tester.enterText(fields.at(2), 'sk-user-owned');
    await tester.tap(find.text('Save Configuration'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));

    expect(settings.isConfiguredForCurrentProvider, isTrue);
    expect(secureKey, 'sk-user-owned');
    expect(preferences.getKeys(), isNot(contains('mithka.ai.api_key.v1')));
  });
}
