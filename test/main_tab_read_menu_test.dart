import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/main_tab_view.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/components/app_interactive_surface.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Restore the target before testWidgets checks foundation debug invariants.
  final android = TargetPlatformVariant.only(TargetPlatform.android);

  for (final glass in [false, true]) {
    testWidgets(
      '${glass ? 'custom glass' : 'classic'} whole unselected Messages body opens/cancels without selection/read',
      (tester) async {
        final state = await _pump(tester, glass: glass);
        final messages = find.byKey(const ValueKey('bottom-tab-0'));
        // Deliberately use target padding, not the badge/icon center.
        await tester.longPressAt(
          tester.getRect(messages).topLeft + const Offset(8, 8),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('tab-read-menu')), findsOneWidget);
        expect(find.text('Mark all as read'), findsOneWidget);
        expect(state.reads, 0);
        expect(state.selections, isEmpty);
        Navigator.of(
          tester.element(find.byKey(const ValueKey('tab-read-menu'))),
        ).pop();
        await tester.pumpAndSettle();
        expect(state.reads, 0);
        expect(state.selections, isEmpty);
        await tester.longPress(messages);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('tab-mark-all-read')));
        await tester.pumpAndSettle();
        expect(state.reads, 1);
        expect(state.selections, isEmpty);
        expect(
          tester.widget<AppInteractiveSurface>(messages).selected,
          isFalse,
        );
        final contacts = find.byKey(const ValueKey('bottom-tab-2'));
        expect(
          tester.widget<AppInteractiveSurface>(contacts).onLongPress,
          isNull,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: android,
    );

    testWidgets(
      '${glass ? 'custom glass' : 'classic'} covering route dismisses menu without read or selection',
      (tester) async {
        final state = await _pump(tester, glass: glass);
        await tester.longPress(find.byKey(const ValueKey('bottom-tab-0')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('tab-read-menu')), findsOneWidget);
        final menuRoute = ModalRoute.of<void>(
          tester.element(find.byKey(const ValueKey('tab-read-menu'))),
        )!;
        unawaited(
          state.navigatorKey.currentState!.push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Covering route')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(menuRoute.isActive, isFalse);
        expect(state.reads, 0);
        expect(state.selections, isEmpty);
        state.navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('tab-read-menu')), findsNothing);
        expect(state.reads, 0);
        expect(state.selections, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: android,
    );

    testWidgets(
      '${glass ? 'custom glass' : 'classic'} captured accessibility read rejects a covered source route',
      (tester) async {
        final state = await _pump(tester, glass: glass);
        final semantics = tester
            .widgetList<Semantics>(find.byType(Semantics))
            .where(
              (widget) =>
                  widget.properties.customSemanticsActions?.isNotEmpty == true,
            );
        final action =
            semantics.single.properties.customSemanticsActions!.values.single;
        unawaited(
          state.navigatorKey.currentState!.push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Covering route')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        action();
        expect(state.reads, 0);
        expect(state.selections, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: android,
    );

    testWidgets(
      '${glass ? 'custom glass' : 'classic'} custom badge drag stays enabled and read action is one-shot',
      (tester) async {
        final state = await _pump(tester, glass: glass, unread: 4);
        expect(
          tester.widget<UnreadBadge>(find.byType(UnreadBadge)).onClear,
          isNotNull,
        );
        final semantics = tester
            .widgetList<Semantics>(find.byType(Semantics))
            .where(
              (widget) =>
                  widget.properties.customSemanticsActions?.isNotEmpty == true,
            );
        final action =
            semantics.single.properties.customSemanticsActions!.values.single;
        action();
        action();
        expect(state.reads, 1);
        expect(state.selections, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: android,
    );
  }

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
