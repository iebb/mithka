//
//  Mithka X settings hub: the fork feature switches answer taps immediately
//  (rows rebuild from the store's own notifications) and the local premium
//  knob flips without any outside setState. Regression: the original rows in
//  Advanced/Privacy were stateless and looked dead until an unrelated row
//  triggered a page rebuild.
//

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/history/message_history_settings.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/local_premium.dart';
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
    final prefs = await SharedPreferences.getInstance();
    MessageHistorySettings.shared.initialize(prefs);
    LocalPremium.shared.initialize(prefs);
  });

  testWidgets('history switches flip on tap', (tester) async {
    await _pump(tester, const MithkaXSettingsView());
    final row = find.byKey(const ValueKey('history-record-deleted'));
    await tester.scrollUntilVisible(row, 200);
    expect(row, findsOneWidget);

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(
      MessageHistorySettings.shared.recordDeleted,
      _enabled ? isTrue : isFalse,
    );

    // The row's knob reflects the new value with no outside rebuild: the
    // rebuilt AppSwitch aligns its handle right when on.
    if (_enabled) {
      final handle = find.descendant(
        of: row,
        matching: find.byType(AnimatedAlign),
      );
      expect(handle, findsOneWidget);
      expect(
        tester.widget<AnimatedAlign>(handle).alignment,
        Alignment.centerRight,
      );
    }
  });

  testWidgets('local premium knob answers its own tap', (tester) async {
    await _pump(tester, const MithkaXSettingsView());
    final row = find.byKey(const ValueKey('mithkax-local-premium'));
    await tester.scrollUntilVisible(row, 200);
    expect(row, findsOneWidget);

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(LocalPremium.shared.enabled, _enabled ? isTrue : isFalse);
  });
}
