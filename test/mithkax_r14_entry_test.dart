//
//  r14: the Ayu hub moved under 设置 › 高级 as a second-level page named
//  「Ayu 功能」, and the top-level Mithka X row is gone.
//
//  1) AdvancedSettingsView shows the Ayu entry only in opted-in builds, and
//     tapping it opens MithkaXSettingsView.
//  2) The settings root no longer carries a mithkax destination: the hub is
//     reachable only through 高级.
//

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/advanced_settings_view.dart';
import 'package:mithka/settings/mithkax_settings_view.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabled = allowTelegramTosViolations;

Future<void> _pump(WidgetTester tester, Widget home) async {
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
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
  });

  testWidgets('Advanced hosts the Ayu entry and it opens the hub', (
    tester,
  ) async {
    await _pump(tester, const AdvancedSettingsView());
    final entry = find.byKey(const ValueKey('mithkax-features'));
    if (!_enabled) {
      expect(entry, findsNothing);
      return;
    }
    await tester.scrollUntilVisible(entry, 300);
    expect(entry, findsOneWidget);
    expect(
      find.text(AppStrings.t(AppStringKeys.mithkaxSettingsTitle)),
      findsWidgets,
    );
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(MithkaXSettingsView), findsOneWidget);
  });
}
