import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/chat_deep_link_controller.dart';
import 'package:mithka/app/main_tab_view.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/components/app_interactive_surface.dart';
import 'package:mithka/components/app_press_ripple.dart';
import 'package:mithka/components/drawer_controller.dart' as dc;
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _barKey = ValueKey('classic-bottom-bar');

/// The bar's divider is a [Border], so it lives inside the container's box.
const _dividerWidth = 0.5;

/// The row's own height; the bottom inset is added on top in the compact
/// shell only.
const _rowHeight = 62.0;

void main() {
  testWidgets('Android compact labels clear the whole system navigation bar', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final probe = await _pumpBar(
        tester,
        const Size(390, 844),
        48,
        platform: TargetPlatform.android,
      );
      expect(
        probe.bar.height,
        moreOrLessEquals(_rowHeight + 48 + _dividerWidth),
      );
      for (final tab in probe.tabs) {
        expect(tab.rect.bottom, probe.window.bottom);
        expect(
          tab.labelRect.bottom,
          lessThanOrEqualTo(probe.window.bottom - 48),
        );
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
      debugDefaultTargetPlatformOverride = null;
    }
  });

  for (final cell in const [
    (name: 'iPad landscape 1366x1024', size: Size(1366, 1024), inset: 20.0),
    (name: 'iPad landscape 1194x834', size: Size(1194, 834), inset: 20.0),
  ]) {
    testWidgets(
      '${cell.name}: the split shell keeps no bottom band and every tab fills '
      'the bar',
      (tester) => _onIOS(tester, () async {
        final probe = await _pumpBar(tester, cell.size, cell.inset);
        expect(probe.bar.bottom, probe.window.bottom);
        // 62pt of controls + the 0.5pt divider, and NOT the 20pt inset: the
        // split shell docks the bar in its sidebar column, where the system
        // home indicator never reaches, so no clearance is reserved.
        expect(probe.bar.height, moreOrLessEquals(_rowHeight + _dividerWidth));
        for (final tab in probe.tabs) {
          expect(tab.rect.bottom, probe.bar.bottom);
          expect(tab.rect.top, probe.bar.top + _dividerWidth);
        }
        // The tabs tile the bar's width with no strip left over on either end.
        expect(probe.tabs.first.rect.left, probe.bar.left);
        expect(
          probe.tabs.fold<double>(0, (sum, tab) => sum + tab.rect.width),
          moreOrLessEquals(probe.bar.width, epsilon: 0.05),
        );
        expect(probe.tabs.last.rect.right, moreOrLessEquals(probe.bar.right));
        // Measured 10.5pt of clearance on both cells: the centred content keeps
        // its margin even though no clearance is reserved.
        final lastTab = probe.tabs.last;
        expect(
          probe.window.bottom - lastTab.labelRect.bottom,
          moreOrLessEquals(10.5),
        );
      }),
    );
  }

  testWidgets(
    'iPad landscape 1366x1024: a reported bottom inset changes nothing in the '
    'split shell',
    (tester) => _onIOS(tester, () async {
      final probe = await _pumpBar(tester, const Size(1366, 1024), 0);
      // Same bar height and same content positions as the 20pt cell above: the
      // split bar reads no bottom inset at all.
      expect(probe.bar.height, moreOrLessEquals(_rowHeight + _dividerWidth));
      final tab = probe.tabs.first;
      expect(tab.iconRect.center.dy, moreOrLessEquals(986.5));
      expect(tab.labelRect.center.dy, moreOrLessEquals(1008.0));
      expect(
        probe.window.bottom - tab.labelRect.bottom,
        moreOrLessEquals(10.5),
      );
    }),
  );

  testWidgets(
    '390x844 phone (34pt inset): the compact shell reserves only the home '
    'indicator and every tab fills the bar',
    (tester) => _onIOS(tester, () async {
      final probe = await _pumpBar(tester, const Size(390, 844), 34);
      expect(probe.bar.bottom, probe.window.bottom);
      // 62pt of controls + the 14pt the home indicator occupies + the 0.5pt
      // divider. The rest of the platform's 34pt safe area is gesture band the
      // bar does not use, so it stays with the content above.
      expect(
        probe.bar.height,
        moreOrLessEquals(_rowHeight + kHomeIndicatorClearance + _dividerWidth),
      );
      for (final tab in probe.tabs) {
        expect(tab.rect.bottom, probe.bar.bottom);
        expect(tab.rect.top, probe.bar.top + _dividerWidth);
      }
    }),
  );

  testWidgets(
    '390x844 phone (34pt inset): the centred label clears the home indicator '
    'pill',
    (tester) => _onIOS(tester, () async {
      final probe = await _pumpBar(tester, const Size(390, 844), 34);
      final tab = probe.tabs.first;
      expect(tab.iconRect.size, const Size(36, 28));
      // The content block is centred in the 76.5pt bar: icon centre 799.5,
      // label centre 821.0, label bottom 826.5, i.e. 17.5pt above the window
      // edge. The pill's top edge is 13pt up, so the label clears it and keeps
      // its own margin without any band nobody owns.
      expect(tab.iconRect.center.dy, moreOrLessEquals(799.5));
      expect(tab.labelRect.center.dy, moreOrLessEquals(821.0));
      expect(
        probe.window.bottom - tab.labelRect.bottom,
        moreOrLessEquals(17.5),
      );
      expect(
        probe.window.bottom - tab.labelRect.bottom,
        greaterThanOrEqualTo(13),
      );
      expect(tab.iconRect.center.dx, moreOrLessEquals(tab.rect.center.dx));
      expect(tab.labelRect.center.dx, moreOrLessEquals(tab.rect.center.dx));
    }),
  );

  testWidgets(
    '390x844 phone (no inset): a device without a home indicator reserves '
    'nothing',
    (tester) => _onIOS(tester, () async {
      final probe = await _pumpBar(tester, const Size(390, 844), 0);
      expect(probe.bar.bottom, probe.window.bottom);
      // Exactly the control row and the divider: no clearance at all.
      expect(probe.bar.height, moreOrLessEquals(_rowHeight + _dividerWidth));
      for (final tab in probe.tabs) {
        expect(tab.rect.bottom, probe.bar.bottom);
        expect(tab.rect.top, probe.bar.top + _dividerWidth);
      }
      final tab = probe.tabs.first;
      // The centred content still leaves the label 10.5pt above the edge.
      expect(
        probe.window.bottom - tab.labelRect.bottom,
        moreOrLessEquals(10.5),
      );
      expect(
        probe.window.bottom - tab.labelRect.bottom,
        greaterThanOrEqualTo(8),
      );
    }),
  );

  for (final cell in const [
    (
      name: 'narrow window 700x900 (34pt inset)',
      size: Size(700, 900),
      inset: 34.0,
      band: kHomeIndicatorClearance,
    ),
    (
      name: 'narrow window 700x900 (no inset)',
      size: Size(700, 900),
      inset: 0.0,
      band: 0.0,
    ),
  ]) {
    testWidgets(
      '${cell.name}: the compact bar reserves the indicator only when one is '
      'reported',
      (tester) => _onIOS(tester, () async {
        final probe = await _pumpBar(tester, cell.size, cell.inset);
        expect(probe.bar.bottom, probe.window.bottom);
        expect(
          probe.bar.height,
          moreOrLessEquals(_rowHeight + cell.band + _dividerWidth),
        );
        for (final tab in probe.tabs) {
          expect(tab.rect.bottom, probe.bar.bottom);
          expect(tab.rect.top, probe.bar.top + _dividerWidth);
        }
      }),
    );
  }

  for (final cell in const [
    (name: 'iPad landscape 1366x1024', size: Size(1366, 1024), inset: 20.0),
    (name: '390x844 phone (34pt inset)', size: Size(390, 844), inset: 34.0),
    (name: '390x844 phone (no inset)', size: Size(390, 844), inset: 0.0),
  ]) {
    testWidgets(
      '${cell.name}: tapping 4pt above the window edge selects that tab',
      (tester) => _onIOS(tester, () async {
        final probe = await _pumpBar(tester, cell.size, cell.inset);
        final target = probe.tabs[1];
        final tapPoint = Offset(target.rect.center.dx, probe.window.bottom - 4);
        // The point is inside the bar, at the very bottom of the window.
        expect(tapPoint.dy, lessThan(probe.bar.bottom));
        expect(_selected(tester, probe.tabs), [true, false]);

        await tester.tapAt(tapPoint);
        await tester.pump(const Duration(milliseconds: 250));

        expect(_selected(tester, probe.tabs), [false, true]);
      }),
    );

    testWidgets(
      '${cell.name}: the pressed tab paints feedback down to the bar bottom '
      'edge',
      (tester) => _onIOS(tester, () async {
        final probe = await _pumpBar(tester, cell.size, cell.inset);
        final tab = probe.tabs.first;
        final ripple = find.descendant(
          of: find.byKey(tab.key),
          matching: find.byKey(AppPressRipple.rippleLayerKey),
        );

        final gesture = await tester.startGesture(tab.rect.center);
        await tester.pump(const Duration(milliseconds: 120));

        final rippleRect = tester.getRect(ripple.first);
        // The press surface and its ripple are the tab's own box: no inset
        // short-fall between the highlight and the bar's bottom edge.
        expect(rippleRect, tab.rect);
        expect(rippleRect.bottom, probe.bar.bottom);

        await gesture.up();
        await tester.pump(const Duration(milliseconds: 350));
      }),
    );
  }
}

/// Runs [body] with the iOS target that selects the app-owned bar, then
/// disposes the shell and restores the override before the binding's
/// end-of-test invariant and pending-timer checks.
Future<void> _onIOS(WidgetTester tester, Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  try {
    await body();
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    // Chat-list cache warming uses delayed no-op guards after disposal.
    await tester.pump(const Duration(seconds: 6));
    debugDefaultTargetPlatformOverride = null;
  }
}

class _TabProbe {
  const _TabProbe({
    required this.key,
    required this.rect,
    required this.iconRect,
    required this.labelRect,
  });

  final ValueKey<String> key;
  final Rect rect;
  final Rect iconRect;
  final Rect labelRect;
}

class _BarProbe {
  const _BarProbe({
    required this.window,
    required this.bar,
    required this.tabs,
  });

  final Rect window;
  final Rect bar;
  final List<_TabProbe> tabs;
}

List<bool?> _selected(WidgetTester tester, List<_TabProbe> tabs) => [
  for (final tab in tabs) _surface(tester, tab.key).selected,
];

Future<_BarProbe> _pumpBar(
  WidgetTester tester,
  Size size,
  double bottomInset, {
  TargetPlatform platform = TargetPlatform.iOS,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.padding = FakeViewPadding(bottom: bottomInset);
  tester.view.viewPadding = FakeViewPadding(bottom: bottomInset);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);

  await _pumpShell(tester);
  await tester.pump();
  await tester.pump();

  final window = tester.getRect(find.byType(MainSplitRootView));
  final barFinder = find.byKey(_barKey);
  expect(barFinder, findsOneWidget);
  final bar = tester.getRect(barFinder);

  final tabs = <_TabProbe>[];
  for (final element
      in find
          .byWidgetPredicate(
            (w) =>
                w is AppInteractiveSurface &&
                w.key is ValueKey<String> &&
                (w.key as ValueKey<String>).value.startsWith('bottom-tab-'),
          )
          .evaluate()) {
    final key = element.widget.key! as ValueKey<String>;
    final tab = find.byKey(key);
    tabs.add(
      _TabProbe(
        key: key,
        rect: tester.getRect(tab),
        iconRect: _iconRect(tester, tab),
        labelRect: tester.getRect(
          find.descendant(of: tab, matching: find.byType(Text)).first,
        ),
      ),
    );
  }
  expect(tabs.length, 2);
  return _BarProbe(window: window, bar: bar, tabs: tabs);
}

AppInteractiveSurface _surface(WidgetTester tester, ValueKey<String> key) =>
    tester.widget<AppInteractiveSurface>(find.byKey(key));

Rect _iconRect(WidgetTester tester, Finder scope) {
  for (final element
      in find
          .descendant(of: scope, matching: find.byType(SizedBox))
          .evaluate()) {
    final widget = element.widget as SizedBox;
    if (widget.width == 36 && widget.height == 28) {
      return tester.getRect(find.byElementPredicate((e) => e == element));
    }
  }
  throw StateError('the tab has no 36x28 icon box');
}

Future<void> _pumpShell(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'showChannelsTab': false,
    'showMomentsTab': false,
    'communitiesEnabled': false,
  });
  final prefs = await SharedPreferences.getInstance();
  final theme = ThemeController(prefs);
  final accounts = AccountStore(prefs);
  final auth = AuthManager();
  final translation = TranslationController(prefs);
  final drawer = dc.DrawerController();
  final deepLinks = ChatDeepLinkController.shared;
  deepLinks.consumePending();

  addTearDown(theme.dispose);
  addTearDown(accounts.dispose);
  addTearDown(auth.dispose);
  addTearDown(translation.dispose);
  addTearDown(drawer.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<AppLocaleController>.value(
          value: AppLocaleController(prefs),
        ),
        ChangeNotifierProvider<AccountStore>.value(value: accounts),
        ChangeNotifierProvider<AuthManager>.value(value: auth),
        ChangeNotifierProvider<TranslationController>.value(value: translation),
        ChangeNotifierProvider<ChatDeepLinkController>.value(value: deepLinks),
        ChangeNotifierProvider<dc.DrawerController>.value(value: drawer),
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
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: [AppColors.light],
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: true, textScaler: TextScaler.noScaling),
          child: child!,
        ),
        home: const MainSplitRootView(),
      ),
    ),
  );
  await tester.pump();
}
