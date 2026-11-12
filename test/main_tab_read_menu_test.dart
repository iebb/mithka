import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/main_tab_view.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Restore the target before testWidgets checks foundation debug invariants.
  final android = TargetPlatformVariant.only(TargetPlatform.android);

  testWidgets(
    'account change dismisses custom menu and cannot dispatch to replacement account',
    (tester) async {
      final state = await _pump(tester);
      await tester.longPress(find.byKey(const ValueKey('bottom-tab-0')));
      await tester.pumpAndSettle();
      state.accounts.changeSlot(2);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tab-read-menu')), findsNothing);
      expect(state.reads, 0);
      expect(state.selections, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: android,
  );
}

class _Accounts extends AccountStore {
  _Accounts(super.prefs);
  int slot = 0;
  @override
  int get activeSlot => slot;
  void changeSlot(int value) {
    slot = value;
    notifyListeners();
  }
}

class _State {
  _State(this.accounts);
  final _Accounts accounts;
  final navigatorKey = GlobalKey<NavigatorState>();
  int reads = 0;
  final selections = <int>[];
}

Future<_State> _pump(
  WidgetTester tester, {
  bool glass = false,
  int unread = 0,
}) async {
  SharedPreferences.setMockInitialValues({'liquidGlassBottomBar': glass});
  final prefs = await SharedPreferences.getInstance();
  final theme = ThemeController(prefs);
  final accounts = _Accounts(prefs);
  final state = _State(accounts);
  addTearDown(theme.dispose);
  addTearDown(accounts.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<AccountStore>.value(value: accounts),
      ],
      child: MaterialApp(
        navigatorKey: state.navigatorKey,
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
                selection: 2,
                onSelect: state.selections.add,
                onClearUnread: () => state.reads++,
                unread: unread,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}
