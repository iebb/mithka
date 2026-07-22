import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/api_credentials_view.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'TDLib user-agent fields stay editable without enabling custom API keys',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'mithka.api_credentials.enabled': false,
        'mithka.api_credentials.api_id': '12345',
        'mithka.api_credentials.api_hash': 'hash',
        'mithka.api_credentials.device_model': 'Pixel 10',
      });
      final preferences = await SharedPreferences.getInstance();
      final theme = ThemeController(preferences);
      addTearDown(theme.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: const MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: ApiCredentialsView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('TDLib User Agent'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('telegramApiIdField')))
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('tdlibDeviceModelField')),
            )
            .enabled,
        isTrue,
      );

      await tester.enterText(
        find.byKey(const ValueKey('tdlibDeviceModelField')),
        'Galaxy S30',
      );
      await tester.enterText(
        find.byKey(const ValueKey('tdlibSystemVersionField')),
        'Android 18',
      );
      await tester.enterText(
        find.byKey(const ValueKey('tdlibApplicationVersionField')),
        'Mithka 0.9',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        preferences.getString('mithka.api_credentials.device_model'),
        'Galaxy S30',
      );
      expect(
        preferences.getString('mithka.api_credentials.system_version'),
        'Android 18',
      );
      expect(
        preferences.getString('mithka.api_credentials.application_version'),
        'Mithka 0.9',
      );
      expect(preferences.getBool('mithka.api_credentials.enabled'), isFalse);
    },
  );
}
