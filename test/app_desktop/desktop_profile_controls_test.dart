import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/app_navigator.dart';
import 'package:mithka/app/content_view.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/components/vip_badge.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Accounts extends AccountStore {
  _Accounts(super.prefs);

  final selectedSlots = <int>[];

  @override
  void switchTo(int slot, AuthManager auth) => selectedSlots.add(slot);
}

void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets('Premium penguin follows the desktop status control', (
    tester,
  ) async {
    await _pump(tester);
    final status = find.byKey(const ValueKey('desktop-title-bar-status'));
    final badge = find.byKey(const ValueKey('desktop-title-bar-vip'));
    expect(status, findsOneWidget);
    expect(badge, findsOneWidget);
    expect(tester.getSize(badge), const Size.square(18));
    expect(
      tester.getRect(badge).left,
      greaterThan(tester.getRect(status).right),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: desktop);

  testWidgets('non-Premium and signed-out identities have no penguin', (
    tester,
  ) async {
    await _pump(tester, premium: false);
    expect(find.byType(VipBadge), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester, ready: false);
    expect(find.byType(VipBadge), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: desktop);

  testWidgets('switch account follows edit and dispatches the chosen slot', (
    tester,
  ) async {
    final accounts = await _pump(tester, hidePhone: true);
    await tester.tap(find.byKey(const ValueKey('macos-title-bar-account')));
    await tester.pump();
    final edit = find.byKey(const ValueKey('desktop-title-bar-profile-edit'));
    final switchAccount = find.byKey(
      const ValueKey('desktop-title-bar-profile-switch-account'),
    );
    expect(edit, findsOneWidget);
    expect(switchAccount, findsOneWidget);
    expect(
      tester.getRect(switchAccount).top,
      greaterThan(tester.getRect(edit).bottom),
    );
    expect(find.text('+15550100'), findsNothing);

    await tester.tap(switchAccount);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('desktop-title-bar-profile-popup')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('account-picker-dialog')), findsOneWidget);
    expect(find.text('Alpha'), findsWidgets);
    expect(find.text('Beta'), findsOneWidget);
    final context = tester.element(
      find.byKey(const ValueKey('account-picker-dialog')),
    );
    expect(
      find.text(AppStringKeys.loginSwitchAccount.l10n(context)),
      findsOneWidget,
    );
    expect(
      find.text(AppStringKeys.accountPickerMessage.l10n(context)),
      findsNothing,
    );
    expect(find.text('+15550100'), findsNothing);
    expect(find.text('+15550101'), findsNothing);
    expect(accounts.selectedSlots, isEmpty);

    await tester.tap(find.byKey(const ValueKey('account-picker-row-1')));
    await tester.pumpAndSettle();
    expect(accounts.selectedSlots, [1]);
    expect(find.byKey(const ValueKey('account-picker-dialog')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: desktop);

  testWidgets('dismissing the switcher leaves the active account alone', (
    tester,
  ) async {
    final accounts = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('macos-title-bar-account')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('desktop-title-bar-profile-switch-account')),
    );
    await tester.pumpAndSettle();
    // The title bar sits above the Navigator's modal barrier. It must not
    // reopen the popup or stack another picker while this one is active.
    await tester.tap(find.byKey(const ValueKey('macos-title-bar-account')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('desktop-title-bar-profile-popup')),
      findsNothing,
    );
    appNavigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(accounts.selectedSlots, isEmpty);
    await tester.tap(find.byKey(const ValueKey('macos-title-bar-account')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('desktop-title-bar-profile-popup')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: desktop);
}

Future<_Accounts> _pump(
  WidgetTester tester, {
  bool premium = true,
  bool ready = true,
  bool hidePhone = false,
}) async {
  SharedPreferences.setMockInitialValues({
    'hideSidebarPhone': hidePhone,
    'drachma.accountSummaries': jsonEncode([
      AccountSummary(
        slot: 0,
        userId: 100,
        name: 'Alpha',
        phone: '+15550100',
        isPremium: premium,
      ).toJson(),
      AccountSummary(
        slot: 1,
        userId: 101,
        name: 'Beta',
        phone: '+15550101',
      ).toJson(),
    ]),
  });
  final prefs = await SharedPreferences.getInstance();
  final accounts = _Accounts(prefs);
  final auth = AuthManager();
  final theme = ThemeController(prefs);
  addTearDown(accounts.dispose);
  addTearDown(auth.dispose);
  addTearDown(theme.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AccountStore>.value(value: accounts),
        ChangeNotifierProvider<AuthManager>.value(value: auth),
        ChangeNotifierProvider<ThemeController>.value(value: theme),
      ],
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppColors.light]),
        builder: (context, child) =>
            DesktopPrimaryWindowFrame(accountReady: ready, child: child!),
        home: const SizedBox.expand(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return accounts;
}
