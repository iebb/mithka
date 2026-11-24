//
//  tab_bar_label_rule_test.dart
//
//  The bottom bar's label rule, exercised on the production bar without the
//  shell around it. A host that spans the window — the compact shell, the only
//  one that reserves the home indicator's clearance — names every tab under
//  its icon and grows with the scaled label line. A host docked in the split
//  shell's sidebar column keeps the icon-only row: its slot is narrower than a
//  label line, so the selection capsule around it would reach past the tab it
//  marks.
//
//  Android takes the Flutter glass host, which is the path this rule governs.
//

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/liquid_glass_bottom_bar.dart';
import 'package:mithka/app/main_tab_view.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final android = TargetPlatformVariant.only(TargetPlatform.android);

  testWidgets(
    'full-width host names each tab and grows with the label line',
    (tester) async {
      await _pump(tester, reserveBottomInset: true);
      final bar = find.byType(LiquidGlassBottomBar);
      expect(bar, findsOneWidget);
      for (final tab in _tabs) {
        final slot = find.byKey(ValueKey('bottom-tab-${tab.index}'));
        expect(
          find.descendant(of: slot, matching: find.text(tab.label)),
          findsOneWidget,
        );
        // The name sits under the icon inside the slot's own capsule.
        final label = tester.getRect(
          find.descendant(of: slot, matching: find.text(tab.label)),
        );
        final icon = tester.getRect(
          find.descendant(of: slot, matching: find.byType(AppIcon)),
        );
        expect(label.top, greaterThanOrEqualTo(icon.bottom));
        expect(label.bottom, lessThanOrEqualTo(tester.getRect(slot).bottom));
      }
      final unscaled = tester.getRect(bar).height;
      await _pump(tester, reserveBottomInset: true, textScale: 2);
      expect(
        tester.getRect(bar).height,
        greaterThan(unscaled),
        reason: 'the label line the host reserved grows with the text scale',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: android,
  );

  testWidgets('docked host stays icon-only at every text scale', (
    tester,
  ) async {
    await _pump(tester, reserveBottomInset: false);
    final bar = find.byType(LiquidGlassBottomBar);
    expect(bar, findsOneWidget);
    for (final tab in _tabs) {
      final slot = find.byKey(ValueKey('bottom-tab-${tab.index}'));
      expect(
        find.descendant(of: slot, matching: find.text(tab.label)),
        findsNothing,
      );
      // The icon is what the slot shows, centred in the label's place, and
      // the accessible name survives on the press surface.
      expect(
        find.descendant(of: slot, matching: find.byType(AppIcon)),
        findsOneWidget,
      );
    }
    final unscaled = tester.getRect(bar).height;
    await _pump(tester, reserveBottomInset: false, textScale: 2);
    expect(
      tester.getRect(bar).height,
      unscaled,
      reason: 'the icon-only row never reserves label height',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: android);
}

/// The four tabs the bar renders, in shell order.
const _tabs = [
  (index: 0, label: 'Messages'),
  (index: 1, label: 'Channels'),
  (index: 2, label: 'Contacts'),
  (index: 3, label: 'Moments'),
];

/// Pumps the real production bar with the glass setting on.
Future<void> _pump(
  WidgetTester tester, {
  required bool reserveBottomInset,
  double textScale = 1,
}) async {
  tester.binding.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.binding.platformDispatcher.clearTextScaleFactorTestValue);
  SharedPreferences.setMockInitialValues({'liquidGlassBottomBar': true});
  final prefs = await SharedPreferences.getInstance();
  final theme = ThemeController(prefs);
  final accounts = AccountStore(prefs);
  addTearDown(theme.dispose);
  addTearDown(accounts.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<AccountStore>.value(value: accounts),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppColors.light]),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Builder(
              builder: (context) => mainBottomBarForTesting(
                selection: 0,
                onSelect: (_) {},
                onClearUnread: () {},
                reserveBottomInset: reserveBottomInset,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
