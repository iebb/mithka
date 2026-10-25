//
//  glass_bottom_bar_geometry_test.dart
//
//  The app's glass bar is a Flutter widget on every target, iOS included:
//  BackdropFilter blurs the app's own layer tree behind the capsule, and the
//  app-owned row, its pill indicator, and every gesture stay in Flutter. One
//  path therefore serves the compact phone bottom bar and the tablet split
//  shell's sidebar column — the old "system bar paints its capsule against the
//  window, not this column" failure mode cannot recur, because nothing
//  system-drawn is positioned relative to tab slots anymore.
//
//  The bar keeps its window containment: the capsule stops inside the bottom
//  safe area instead of reaching under the home indicator, and the row keeps
//  the shared lateral, top, and capsule insets.
//

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/chat_deep_link_controller.dart';
import 'package:mithka/app/liquid_glass_bottom_bar.dart';
import 'package:mithka/app/main_tab_view.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/app_interactive_surface.dart';
import 'package:mithka/components/drawer_controller.dart' as dc;
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/glass_review_capture.dart';

const _barKey = ValueKey('liquid-glass-bottom-bar');
const _indicatorKey = ValueKey('liquid-glass-selection');
const _firstSlotKey = ValueKey('bottom-tab-0');

/// An iPhone 14-style window: 390x844 with the 34px home-indicator inset.
const _phoneSize = Size(390, 844);
const _phoneBottomInset = 34.0;

/// The bar geometry: the 62px control row inside a 5px capsule inset, with
/// 14px lateral and 8px top margins, and a 10px gap above the capsule's own
/// bottom (the bar's `minimum` for the safe area).
const _rowHeight = 62.0;
const _capsuleInset = 5.0;
const _capsuleHeight = _rowHeight + 2 * _capsuleInset;
const _bottomGap = 10.0;
const _sideMargin = 14.0;
const _topMargin = 8.0;

void main() {
  final updates = StreamController<Map<String, dynamic>>.broadcast();
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });
  setUpAll(() async {
    await loadGlassReviewIconFonts();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => _response(request),
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });

  testWidgets('iOS split shell draws the glass bar with app-owned tabs', (
    tester,
  ) async {
    await onIOS(() async {
      await _pumpShell(tester, const Size(900, 800));
      // The Flutter glass bar is present, with no platform view behind it.
      expect(find.byKey(_barKey), findsOneWidget);
      expect(find.byType(LiquidGlassBottomBar), findsOneWidget);
      expect(find.byType(UiKitView), findsNothing);
      // The selection pill and the tab slots are all Flutter-drawn, so the
      // pill still covers the selected tab exactly inside the narrow sidebar
      // column — the geometry no longer depends on where UIKit thinks the
      // window-bottom bar is.
      final indicator = find.byKey(_indicatorKey);
      expect(indicator, findsOneWidget);
      final slots = find.byKey(_firstSlotKey);
      expect(tester.getRect(indicator), tester.getRect(slots));
      // The capsule keeps the shared gap below it and draws no phantom bar.
      final capsule = _capsuleRect(tester);
      expect(capsule.bottom, 800 - _bottomGap);
      expect(capsule.height, _capsuleHeight);
      final barRect = tester.getRect(find.byKey(_barKey));
      expect(capsule.left, barRect.left + _sideMargin);
      expect(capsule.right, barRect.right - _sideMargin);
      expect(tester.getRect(slots).bottom, 800 - _bottomGap - _capsuleInset);
      // 8px of top margin sits between the safe area's content box and the
      // capsule; the bar itself reaches the window edge.
      expect(barRect.top, capsule.top - _topMargin);
      expect(barRect.bottom, 800);
      await _dispose(tester);
    });
  });

  testWidgets('compact iOS window draws the Flutter glass, taps stay alive', (
    tester,
  ) async {
    await onIOS(() async {
      await _pumpShell(tester, _phoneSize);
      expect(find.byKey(_barKey), findsOneWidget);
      expect(find.byType(UiKitView), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(_barKey),
          matching: find.byType(BackdropFilter),
        ),
        findsOneWidget,
      );
      final indicator = find.byKey(_indicatorKey);
      final slots = find.byKey(_firstSlotKey);
      expect(tester.getRect(indicator), tester.getRect(slots));
      // An uninset window still leaves the shared capsule gap at its bottom.
      expect(_capsuleRect(tester).bottom, _phoneSize.height - _bottomGap);
      // Tapping a tab still selects it: the row above the glass owns gestures.
      await tester.tap(find.byKey(const ValueKey('bottom-tab-2')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester.getRect(find.byKey(_indicatorKey)),
        tester.getRect(find.byKey(const ValueKey('bottom-tab-2'))),
      );
      await _dispose(tester);
    });
  });

  // Regression: the bar once returned a platform surface without the SafeArea
  // containment the other bar paths apply, so on a phone window the glass (and
  // the 62px row above it) reached y=844 and drew under the home indicator
  // instead of stopping at y=810.
  testWidgets('iOS glass capsule stays clear of the home indicator', (
    tester,
  ) async {
    await onIOS(() async {
      final homeIndicatorTop = _phoneSize.height - _phoneBottomInset;
      await _pumpShell(
        tester,
        _phoneSize,
        insets: const FakeViewPadding(bottom: _phoneBottomInset),
      );
      expect(find.byKey(_barKey), findsOneWidget);
      final capsule = _capsuleRect(tester);
      // The glass stops at or above the home indicator's top edge...
      expect(capsule.bottom, lessThanOrEqualTo(homeIndicatorTop));
      // ...but it is still the bottom bar, not a capsule collapsed by the fix.
      expect(capsule.bottom, homeIndicatorTop);
      expect(capsule.height, _capsuleHeight);
      expect(capsule.left, _sideMargin);
      expect(capsule.right, _phoneSize.width - _sideMargin);
      // The tab controls stay above the home-indicator region too.
      final slot = find.byKey(_firstSlotKey);
      expect(tester.getRect(slot).bottom, lessThanOrEqualTo(homeIndicatorTop));
      expect(tester.getRect(slot).bottom, homeIndicatorTop - _capsuleInset);
      expect(tester.getRect(slot), tester.getRect(find.byKey(_indicatorKey)));
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });
  });

  // The fix requirement in one assertion: whatever the target platform, the
  // row and the capsule land on the same rect.
  testWidgets('one glass geometry serves the iOS and Android hosts', (
    tester,
  ) async {
    await onIOS(() async {
      const insets = FakeViewPadding(bottom: _phoneBottomInset);
      await _pumpShell(tester, _phoneSize, insets: insets);
      final iosCapsule = _capsuleRect(tester);
      final iosSlot = tester.getRect(find.byKey(_firstSlotKey));
      final iosPill = tester.getRect(find.byKey(_indicatorKey));

      // Same window, non-iOS target: the same Flutter glass bar is the host.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await _pumpShell(tester, _phoneSize, insets: insets);
      expect(find.byType(LiquidGlassBottomBar), findsOneWidget);
      expect(_capsuleRect(tester), iosCapsule);
      expect(tester.getRect(find.byKey(_firstSlotKey)), iosSlot);
      expect(tester.getRect(find.byKey(_indicatorKey)), iosPill);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });
  });

  testWidgets('narrow phone keeps the glass capsule inside its insets', (
    tester,
  ) async {
    await onIOS(() async {
      const size = Size(320, 568);
      await _pumpShell(
        tester,
        size,
        insets: const FakeViewPadding(top: 47, bottom: 34),
      );
      final capsule = _capsuleRect(tester);
      expect(capsule.bottom, lessThanOrEqualTo(size.height - 34));
      // The status-bar inset never leaks into the bar's own height.
      expect(capsule.height, _capsuleHeight);
      // The lateral margins never push the row outside the window.
      expect(capsule.left, _sideMargin);
      expect(capsule.right, size.width - _sideMargin);
      final slot = find.byKey(_firstSlotKey);
      expect(tester.getRect(slot).bottom, lessThanOrEqualTo(size.height - 34));
      expect(tester.getRect(slot), tester.getRect(find.byKey(_indicatorKey)));
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });
  });

  testWidgets('split shell column honors the bottom inset too', (tester) async {
    await onIOS(() async {
      // No camera inset and no usable split width, so the glass bar stays in
      // the narrow sidebar column.
      await _pumpShell(
        tester,
        const Size(900, 800),
        insets: const FakeViewPadding(bottom: 34),
      );
      final capsule = _capsuleRect(tester);
      expect(capsule.bottom, lessThanOrEqualTo(800 - 34));
      expect(capsule.height, _capsuleHeight);
      final slot = find.byKey(_firstSlotKey);
      expect(tester.getRect(slot).bottom, lessThanOrEqualTo(800 - 34));
      expect(tester.getRect(slot), tester.getRect(find.byKey(_indicatorKey)));
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });
  });

  testWidgets('RTL glass bar keeps containment and mirrors its slots', (
    tester,
  ) async {
    await onIOS(() async {
      final homeIndicatorTop = _phoneSize.height - _phoneBottomInset;
      await _pumpShell(
        tester,
        _phoneSize,
        insets: const FakeViewPadding(bottom: _phoneBottomInset),
        textDirection: TextDirection.rtl,
      );
      final capsule = _capsuleRect(tester);
      expect(capsule.bottom, lessThanOrEqualTo(homeIndicatorTop));
      expect(capsule.height, _capsuleHeight);
      final slot = find.byKey(_firstSlotKey);
      expect(tester.getRect(slot).bottom, lessThanOrEqualTo(homeIndicatorTop));
      // Both the row and the pill mirror: the first slot sits on the right.
      expect(tester.getRect(slot), tester.getRect(find.byKey(_indicatorKey)));
      expect(tester.getRect(slot).left, greaterThan(_phoneSize.width / 2));
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });
  });

  // This PR's actual regression pin: the iOS bar used to be a UIKit platform
  // view whose visual effect sampled the window composite, and the bar's own
  // near-opaque surface tint made it read as a flat white strip. The bar must
  // be composited by Flutter itself — a BackdropFilter over the app's layer
  // tree, and no UiKitView at all.
  testWidgets('iOS glass bar is composited by Flutter, not a platform view', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _pumpShell(tester, _phoneSize);
      expect(find.byType(LiquidGlassBottomBar), findsOneWidget);
      final backdrop = find.descendant(
        of: find.byKey(_barKey),
        matching: find.byType(BackdropFilter),
      );
      expect(backdrop, findsOneWidget);
      final filter = tester.widget<BackdropFilter>(backdrop);
      expect(filter.enabled, isTrue);
      expect(filter.filter.toString(), contains('ImageFilter.blur(24.0, 24.0'));
      expect(find.byType(UiKitView), findsNothing);
      await _dispose(tester);
    } finally {
      // The test framework asserts this debug override is unset before the
      // test body completes, so it cannot wait for tearDown.
      debugDefaultTargetPlatformOverride = null;
    }
  });

  // Every glass slot is an icon-only target. With the setting on no label
  // is drawn in the bar; its accessible name stays on AppInteractiveSurface.
  testWidgets('glass bar draws no tab label and keeps its semantic names', (
    tester,
  ) async {
    await onIOS(() async {
      await _pumpShell(tester, _phoneSize);
      final bar = find.byKey(_barKey);
      expect(bar, findsOneWidget);
      for (final tab in _tabs) {
        // No label text inside the bar — 'Messages' only lives in the chat
        // list's empty state, which sits outside the bar.
        expect(
          find.descendant(of: bar, matching: find.text(tab.label)),
          findsNothing,
        );
        expect(
          semanticLabelOf(tester, ValueKey('bottom-tab-${tab.index}')),
          tab.label,
        );
      }
      // The icon is what the slot shows, centred in the label's place.
      expect(
        find.descendant(of: bar, matching: find.byType(AppIcon)),
        findsNWidgets(_tabs.length),
      );
      // With no label line there is nothing to grow for text scale.
      final unscaledHeight = tester.getRect(bar).height;
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      try {
        await _pumpShell(tester, _phoneSize);
        expect(
          tester.getRect(find.byKey(_barKey)).height,
          unscaledHeight,
          reason: 'the icon-only glass row never reserves label height',
        );
        expect(tester.takeException(), isNull);
      } finally {
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
      }
      await _dispose(tester);
    });
  });

  // Icon-only is deliberate for the glass bar only: the classic bar (the
  // setting off) keeps its icon + label column at the same row height.
  testWidgets('classic bar keeps its tab labels when the setting is off', (
    tester,
  ) async {
    await onIOS(() async {
      await _pumpShell(tester, _phoneSize, liquidGlass: false);
      final bar = find.byKey(const ValueKey('classic-bottom-bar'));
      expect(bar, findsOneWidget);
      expect(find.byKey(_barKey), findsNothing);
      for (final tab in _tabs) {
        expect(
          find.descendant(of: bar, matching: find.text(tab.label)),
          findsOneWidget,
        );
        expect(
          semanticLabelOf(tester, ValueKey('bottom-tab-${tab.index}')),
          tab.label,
        );
      }
      // Classic keeps the scaled label line's height: growing the text scale
      // grows the bar.
      final unscaledHeight = tester.getRect(bar).height;
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      try {
        await _pumpShell(tester, _phoneSize, liquidGlass: false);
        final scaled = find.byKey(const ValueKey('classic-bottom-bar'));
        expect(
          tester.getRect(scaled).height,
          greaterThan(unscaledHeight),
          reason: 'the classic bar still grows for the scaled label line',
        );
        expect(tester.takeException(), isNull);
      } finally {
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
      }
      await _dispose(tester);
    });
  });
  testWidgets('capture the real glass shell for visual review', (tester) async {
    await onIOS(() async {
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );
      for (final scene in [
        (name: 'phone-light', size: _phoneSize, brightness: Brightness.light),
        (name: 'phone-dark', size: _phoneSize, brightness: Brightness.dark),
        (
          name: 'tablet-light',
          size: const Size(900, 800),
          brightness: Brightness.light,
        ),
      ]) {
        tester.binding.platformDispatcher.platformBrightnessTestValue =
            scene.brightness;
        await _pumpShell(
          tester,
          scene.size,
          insets: const FakeViewPadding(bottom: _phoneBottomInset),
          brightness: scene.brightness,
        );
        await captureGlassReviewImage(tester, scene.name);
        await _dispose(tester);
      }
    });
  }, skip: !captureGlassReview);
}

/// The four tabs the shell shows with channels and moments enabled.
const _tabs = [
  (index: 0, label: 'Messages'),
  (index: 1, label: 'Channels'),
  (index: 2, label: 'Contacts'),
  (index: 3, label: 'Moments'),
];

/// The accessible name [AppInteractiveSurface] exposes for the slot [key].
String? semanticLabelOf(WidgetTester tester, Key key) => tester
    .widget<AppInteractiveSurface>(
      find.byWidgetPredicate(
        (widget) => widget is AppInteractiveSurface && widget.key == key,
      ),
    )
    .semanticLabel;

/// The stadium the glass and the row are clipped into: the bar's pill-radius
/// ClipRRect, which is the visible capsule rect in every host.
Rect _capsuleRect(WidgetTester tester) {
  final finder = find.descendant(
    of: find.byKey(_barKey),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is ClipRRect &&
          widget.borderRadius == BorderRadius.circular(AppRadius.pill),
    ),
  );
  expect(finder, findsOneWidget);
  return tester.getRect(finder);
}

/// Runs [body] with iOS as the target platform, clearing the override before
/// the test body returns (the framework asserts it is unset at teardown).
Future<void> onIOS(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

Future<void> _pumpShell(
  WidgetTester tester,
  Size size, {
  FakeViewPadding insets = FakeViewPadding.zero,
  TextDirection textDirection = TextDirection.ltr,
  bool liquidGlass = true,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.padding = insets;
  tester.view.viewPadding = insets;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  SharedPreferences.setMockInitialValues({
    'showChannelsTab': true,
    'showMomentsTab': true,
    'communitiesEnabled': false,
    'liquidGlassBottomBar': liquidGlass,
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
          brightness: brightness,
          extensions: [
            brightness == Brightness.dark ? AppColors.dark : AppColors.light,
          ],
        ),
        builder: (context, child) =>
            Directionality(textDirection: textDirection, child: child!),
        home: glassReviewBoundary(const MainSplitRootView()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // Chat-list cache warming uses delayed no-op guards after disposal.
  await tester.pump(const Duration(seconds: 6));
}

Map<String, dynamic> _response(Map<String, dynamic> request) =>
    switch (request['@type']) {
      'getChats' => {'@type': 'chats', 'chat_ids': <int>[]},
      'getMe' => {'@type': 'user', 'id': 1, 'first_name': 'Test'},
      'getConnectionState' => {'@type': 'connectionStateReady'},
      _ => {'@type': 'ok'},
    };
