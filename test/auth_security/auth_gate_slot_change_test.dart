import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/content_view.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/l10n_fixtures.dart';

/// The auth gate must survive an account slot change: 添加账号 flips the
/// active slot while the gate crossfades login → ready, and tearing the gate
/// down at that exact moment (the old main.dart KeyedSubtree keyed on the
/// slot) is what killed the add-account transition.
void main() {
  setUpAll(() => L10nFixtures.load().install());

  testWidgets('gate switcher survives an account slot change', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final auth = AuthManager();
    addTearDown(auth.dispose);
    final accounts = AccountStore(prefs);
    addTearDown(accounts.dispose);

    late StateSetter rebuildHost;
    var ready = false;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthManager>.value(value: auth),
          ChangeNotifierProvider<AccountStore>.value(value: accounts),
        ],
        child: StatefulBuilder(
          builder: (context, setState) {
            rebuildHost = setState;
            return MaterialApp(
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
                body: ready ? const ContentView() : const SizedBox.shrink(),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();

    // Mount ContentView through a login-family step, then flip the account
    // identity the way addAccount does. Failing-first: with the gate keyed on
    // the slot from main.dart, this flip replaced the whole subtree and the
    // AnimatedSwitcher (with its crossfade) died.
    rebuildHost(() => ready = true);
    await tester.pump();
    expect(find.byType(AnimatedSwitcher), findsOneWidget);
    final switcherBefore = tester.state(find.byType(AnimatedSwitcher));

    // addAccount: a fresh slot + notifyListeners while the login surface is
    // showing. The store rekeys internally; the gate only reads the slot.
    accounts.debugSetActiveSlotForTesting(7);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AnimatedSwitcher), findsOneWidget);
    final switcherAfter = tester.state(find.byType(AnimatedSwitcher));
    expect(
      identical(switcherBefore, switcherAfter),
      isTrue,
      reason: 'the account flip must rekey the ready child, not the gate',
    );
    expect(tester.takeException(), isNull);
  });
}
