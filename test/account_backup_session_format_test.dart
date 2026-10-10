import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/account_backup_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('account backup offers both session string formats', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'mithka.accountBackup.explicitConsentMigration.v1': true,
    });
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          locale: const Locale('en'),
          theme: ThemeData(extensions: [AppColors.light]),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AccountBackupView(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    String label(String key) => AppStrings.tForLocale('en', key);

    expect(
      find.widgetWithText(
        SettingsRow,
        label(AppStringKeys.accountBackupCopyPyrogramSession),
      ),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(
        SettingsRow,
        label(AppStringKeys.accountBackupCopyGramJsSession),
      ),
      findsOneWidget,
    );
    // The import entry is format-neutral: one sheet accepts either string.
    expect(
      find.widgetWithText(
        SettingsRow,
        label(AppStringKeys.accountBackupLoadSession),
      ),
      findsOneWidget,
    );
    expect(
      label(AppStringKeys.accountBackupLoadSessionMessage),
      allOf(contains('Pyrogram'), contains('GramJS')),
    );
  });
}
