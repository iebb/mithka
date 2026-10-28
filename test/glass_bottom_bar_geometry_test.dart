//
//  glass_bottom_bar_geometry_test.dart
//
//  iOS 26+ native-control tests use mocked native metrics below. The existing
//  geometry tests explicitly select the preserved pre-26 fallback.
//  That fallback uses a single native host for outer/selected material; Flutter owns
//  controls and semantics. Mocked widget tests verify the configuration and
//  row containment, NOT the native material's appearance or rendered frame.
//
//  The native host keeps the same window containment as the Flutter glass bar:
//  the surface stops inside the bottom safe area instead of reaching under the
//  home indicator, and the row keeps the shared lateral, top, and capsule
//  insets, so both hosts draw the bar at the same rect.
//
//  Under flutter test the real UIKit view never exists, so the whole file
//  installs a mock for the platform-view creation channel and the per-view
//  method channel; the mock only records and answers the way the native side
//  would (nothing to answer).
//

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heroicons_flutter/heroicons_flutter.dart';
import 'package:mithka/app/chat_deep_link_controller.dart';
import 'package:mithka/app/liquid_glass_bottom_bar.dart';
import 'package:mithka/app/main_tab_view.dart';
import 'package:mithka/app/native_glass_surface.dart';
import 'package:mithka/app/native_tab_bar.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/app_interactive_surface.dart';
import 'package:mithka/components/app_press_ripple.dart';
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
import 'helpers/native_tab_bar_mock.dart';

const _surfaceKey = ValueKey('native-glass-surface');
const _barKey = _surfaceKey;
const _indicatorKey = ValueKey('liquid-glass-selection');
const _firstSlotKey = ValueKey('bottom-tab-0');

/// An iPhone 14-style window: 390x844 with the 34px home-indicator inset.
const _phoneSize = Size(390, 844);
const _phoneBottomInset = 34.0;

/// The bar geometry both glass hosts share: the 62px control row inside a 5px
/// capsule inset, with 14px lateral and 8px top margins, and a 10px gap above
/// the surface's own bottom (the Flutter bar's `minimum` for the safe area).
const _rowHeight = 62.0;
const _capsuleInset = 5.0;
const _surfaceHeight = _rowHeight + 2 * _capsuleInset;
const _surfaceBottomGap = 10.0;
const _sideMargin = 14.0;

/// Contract geometry only: native tests must verify UIKit's actual layout.
Rect _configuredSelectionRect(WidgetTester tester) {
  final native = find.byType(NativeGlassSurface);
  if (native.evaluate().isEmpty) {
    return tester.getRect(find.byKey(_indicatorKey));
  }
  expect(find.byKey(_indicatorKey), findsNothing);
  final widget = tester.widget<NativeGlassSurface>(native);
  final rect = tester.getRect(native).deflate(widget.selectionInset);
  final rtl = Directionality.of(tester.element(native)) == TextDirection.rtl;
  final slot = rtl
      ? widget.itemCount - 1 - widget.selection!
      : widget.selection!;
  return Rect.fromLTWH(
    rect.left + rect.width * slot / widget.itemCount,
    rect.top,
    rect.width / widget.itemCount,
    rect.height,
  );
}

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

  for (final size in [_phoneSize, const Size(900, 800)]) {
    testWidgets(
      'iOS 26+ ${size.width} uses actual-control contract and measured footer',
      (tester) async {
        await onIOS(() async {
          final nativeMock = NativeTabBarMock(
            tester.binding.defaultBinaryMessenger,
          )..install();
          addTearDown(nativeMock.dispose);
          // Warm exact DPR1/LTR keys in the real async zone BEFORE the shell
          // can cache engine futures in testWidgets' fake zone.
          await tester.runAsync(() async {
            await Future.wait([
              for (final icon in [
                HeroAppIcons.solidMessage,
                HeroAppIcons.hashtag,
                HeroAppIcons.solidHashtag,
                HeroAppIcons.users,
                HeroAppIcons.solidUsers,
                HeroAppIcons.circleNotch,
                HeroAppIcons.solidCircleNotch,
                HeroAppIcons.circleCheck,
              ])
                NativeTabIconRasterizer.png(icon.data, 1, TextDirection.ltr),
            ]);
          });
          await _pumpShell(
            tester,
            size,
            insets: const FakeViewPadding(bottom: _phoneBottomInset),
          );
          await _pumpNativeConfiguration(tester);
          expect(defaultTargetPlatform, TargetPlatform.iOS);
          expect(find.byType(NativeTabBar), findsOneWidget);
          expect(find.byType(NativeGlassSurface), findsNothing);
          expect(find.byKey(_firstSlotKey), findsNothing);
          expect(find.byKey(_indicatorKey), findsNothing);
          expect(find.byType(UiKitView), findsOneWidget);
          expect(nativeMock.created, hasLength(1));
          expect(nativeMock.updates, isNotEmpty);
          expect(
            nativeMock.latest['bottomInset'],
            size == _phoneSize ? _phoneBottomInset : 0,
          );
          expect(
            (nativeMock.latest['items'] as List).map((item) => item['label']),
            _tabs.map((tab) => tab.label),
          );
          await nativeMock.send('metrics', {'height': 95.5});
          await tester.pump();
          await tester.pump();
          expect(
            tester.getSize(find.byKey(const ValueKey('native-tab-bar'))).height,
            95.5,
          );
          await nativeMock.send('select', {'id': 2});
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          expect(
            tester.widget<NativeTabBar>(find.byType(NativeTabBar)).selectedId,
            2,
          );
          expect(tester.takeException(), isNull);
          await _dispose(tester);
        });
      },
    );
  }

  testWidgets('iOS split shell hosts the native glass with app-owned tabs', (
    tester,
  ) async {
    await onIOS(() async {
      installMockGlassSurface(tester);
      await _pumpShell(tester, const Size(900, 800));
      // The native surface is present behind the app-owned bar.
      expect(find.byKey(_surfaceKey), findsOneWidget);
      expect(find.byType(UiKitView), findsOneWidget);
      // Selected geometry is configured relative to this host, not the window.
      expect(find.byKey(_indicatorKey), findsNothing);
      final slots = find.byKey(_firstSlotKey);
      expect(_configuredSelectionRect(tester), tester.getRect(slots));
      // A window with no bell keeps the shared capsule gap below the surface
      // and draws no phantom bar of its own.
      final surface = tester.getRect(find.byKey(_surfaceKey));
      expect(surface.bottom, 800 - _surfaceBottomGap);
      expect(surface.height, _surfaceHeight);
      expect(
        tester.getRect(slots).bottom,
        800 - _surfaceBottomGap - _capsuleInset,
      );
      await _dispose(tester);
    });
  });

  testWidgets('compact iOS window hosts the native glass, taps stay alive', (
    tester,
  ) async {
    await onIOS(() async {
      installMockGlassSurface(tester);
      await _pumpShell(tester, _phoneSize);
      expect(find.byKey(_surfaceKey), findsOneWidget);
      expect(find.byType(UiKitView), findsOneWidget);
      expect(find.byKey(_indicatorKey), findsNothing);
      final slots = find.byKey(_firstSlotKey);
      expect(_configuredSelectionRect(tester), tester.getRect(slots));
      // An uninset window still leaves the shared capsule gap at its bottom.
      expect(
        tester.getRect(find.byKey(_surfaceKey)).bottom,
        _phoneSize.height - _surfaceBottomGap,
      );
      // Tapping a tab still selects it: the row above the glass owns gestures.
      await tester.tap(find.byKey(const ValueKey('bottom-tab-2')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        _configuredSelectionRect(tester),
        tester.getRect(find.byKey(const ValueKey('bottom-tab-2'))),
      );
      await _dispose(tester);
    });
  });

  // Regression: the iOS host returned the platform surface without the
  // SafeArea containment the other two bar paths apply, so on a phone window
  // the surface (and the 62px row above it) reached y=844 and drew under the
  // home indicator instead of stopping at y=810.
  testWidgets('iOS glass surface stays clear of the home indicator', (
    tester,
  ) async {
    await onIOS(() async {
      installMockGlassSurface(tester);
      final homeIndicatorTop = _phoneSize.height - _phoneBottomInset;
      await _pumpShell(
        tester,
        _phoneSize,
        insets: const FakeViewPadding(bottom: _phoneBottomInset),
      );
      final surface = find.byKey(_surfaceKey);
      expect(surface, findsOneWidget);
      final surfaceRect = tester.getRect(surface);
      // The glass stops at or above the home indicator's top edge...
      expect(surfaceRect.bottom, lessThanOrEqualTo(homeIndicatorTop));
      // ...but it is still the bottom bar, not a surface collapsed by the fix.
      expect(surfaceRect.bottom, homeIndicatorTop);
      expect(surfaceRect.height, _surfaceHeight);
      expect(surfaceRect.left, _sideMargin);
      expect(surfaceRect.right, _phoneSize.width - _sideMargin);
      expect(tester.getRect(find.byType(UiKitView)), surfaceRect);
      // The tab controls stay above the home-indicator region too.
      final slot = find.byKey(_firstSlotKey);
      expect(tester.getRect(slot).bottom, lessThanOrEqualTo(homeIndicatorTop));
      expect(tester.getRect(slot).bottom, homeIndicatorTop - _capsuleInset);
      expect(tester.getRect(slot), _configuredSelectionRect(tester));
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });
  });

  // The fix requirement in one assertion: whatever the platform host, the row
  // and the surface land on the same rect the Flutter glass bar uses.
  testWidgets('native host mirrors the Flutter glass bar geometry', (
    tester,
  ) async {
    await onIOS(() async {
      installMockGlassSurface(tester);
      const insets = FakeViewPadding(bottom: _phoneBottomInset);
      await _pumpShell(tester, _phoneSize, insets: insets);
      final nativeSurface = tester.getRect(find.byKey(_surfaceKey));
      final nativeSlot = tester.getRect(find.byKey(_firstSlotKey));

      // Same window, non-iOS target: the Flutter glass bar is the host.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await _pumpShell(tester, _phoneSize, insets: insets);
      final bar = find.byType(LiquidGlassBottomBar);
      expect(bar, findsOneWidget);
      expect(find.byKey(_surfaceKey), findsNothing);
      final stadium = find.descendant(
        of: bar,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ClipRRect &&
              widget.borderRadius == BorderRadius.circular(AppRadius.pill),
        ),
      );
      expect(stadium, findsOneWidget);
      expect(tester.getRect(stadium), nativeSurface);
      expect(tester.getRect(find.byKey(_firstSlotKey)), nativeSlot);
      expect(_configuredSelectionRect(tester), nativeSlot);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'iOS ${brightness.name} glass switches live through opaque high contrast',
      (tester) async {
        await onIOS(() async {
          final mock = installMockGlassSurface(tester);
          addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
          );
          await _pumpShell(
            tester,
            _phoneSize,
            brightness: brightness,
            insets: const FakeViewPadding(bottom: _phoneBottomInset),
          );
          expect(find.byType(UiKitView), findsOneWidget);
          expect(find.byType(LiquidGlassBottomBar), findsNothing);
          final nativeRect = tester.getRect(find.byKey(_surfaceKey));

          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(highContrast: true);
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          expect(find.byType(UiKitView), findsOneWidget);
          expect(find.byType(LiquidGlassBottomBar), findsNothing);
          expect(find.byKey(_indicatorKey), findsNothing);
          expect(tester.getRect(find.byKey(_surfaceKey)), nativeRect);
          final config = mock.calls.last.arguments as Map;
          expect(config['highContrast'], isTrue);
          expect(Color(config['opaqueBackground'] as int).a, 1);
          expect(Color(config['opaqueSelection'] as int).a, 1);
          for (final tab in _tabs) {
            expect(
              semanticLabelOf(tester, ValueKey('bottom-tab-${tab.index}')),
              tab.label,
            );
          }
          await tester.tap(find.byKey(const ValueKey('bottom-tab-2')));
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures();
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          expect(find.byType(UiKitView), findsOneWidget);
          expect(find.byType(LiquidGlassBottomBar), findsNothing);
          expect(mock.createdParams, hasLength(1));
          expect(tester.getRect(find.byKey(_surfaceKey)), nativeRect);
          expect(
            _configuredSelectionRect(tester),
            tester.getRect(find.byKey(const ValueKey('bottom-tab-2'))),
          );
          expect(tester.takeException(), isNull);
          await _dispose(tester);
        });
      },
    );
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final brightness in Brightness.values) {
      for (final size in [_phoneSize, const Size(900, 800)]) {
        testWidgets(
          '${platform.name} ${brightness.name} ${size.width} glass capsules and icon contrast',
          (tester) async {
            debugDefaultTargetPlatformOverride = platform;
            try {
              installMockGlassSurface(tester);
              await _pumpShell(
                tester,
                size,
                brightness: brightness,
                insets: const FakeViewPadding(bottom: _phoneBottomInset),
              );
              final colors = tester.element(find.byKey(_firstSlotKey)).colors;
              final surface = platform == TargetPlatform.iOS
                  ? find.byKey(_surfaceKey)
                  : find.descendant(
                      of: find.byType(LiquidGlassBottomBar),
                      matching: find.byWidgetPredicate(
                        (widget) =>
                            widget is ClipRRect &&
                            widget.borderRadius ==
                                BorderRadius.circular(AppRadius.pill),
                      ),
                    );
              final outer = tester.getRect(surface);
              final first = tester.getRect(find.byKey(_firstSlotKey));
              final last = tester.getRect(
                find.byKey(const ValueKey('bottom-tab-3')),
              );
              expect(first.expandToInclude(last), outer.deflate(_capsuleInset));
              if (platform == TargetPlatform.iOS) {
                expect(find.byKey(_indicatorKey), findsNothing);
                final native = tester.widget<NativeGlassSurface>(
                  find.byType(NativeGlassSurface),
                );
                expect(native.selectionInset, _capsuleInset);
                expect(native.itemCount, _tabs.length);
              } else {
                final selection =
                    tester
                            .widget<DecoratedBox>(find.byKey(_indicatorKey))
                            .decoration
                        as BoxDecoration;
                expect(
                  selection.borderRadius,
                  BorderRadius.circular(first.height / 2),
                );
              }
              expect(_configuredSelectionRect(tester), first);
              expect(outer.height / 2 - first.height / 2, _capsuleInset);
              for (final tab in _tabs) {
                final slot = find.byKey(ValueKey('bottom-tab-${tab.index}'));
                final control = tester.widget<AppInteractiveSurface>(slot);
                final radius = BorderRadius.circular(
                  tester.getSize(slot).height / 2,
                );
                expect(control.borderRadius, radius);
                expect(control.semanticLabel, tab.label);
                final icon = tester.widget<AppIcon>(
                  find.descendant(of: slot, matching: find.byType(AppIcon)),
                );
                expect(
                  icon.color,
                  tab.index == 0 ? AppTheme.brand : colors.textPrimary,
                );
                if (tab.index != 0) {
                  final foreground = icon.color!.computeLuminance();
                  final background = colors.navBar.computeLuminance();
                  final ratio = foreground > background
                      ? (foreground + 0.05) / (background + 0.05)
                      : (background + 0.05) / (foreground + 0.05);
                  expect(
                    ratio,
                    greaterThanOrEqualTo(4.5),
                    reason: 'nominal glass palette icon contrast',
                  );
                }
              }
              for (final index in [0, 3]) {
                final slot = find.byKey(ValueKey('bottom-tab-$index'));
                final gesture = await tester.startGesture(
                  tester.getCenter(slot),
                );
                await tester.pump(const Duration(milliseconds: 50));
                expect(
                  find.descendant(
                    of: slot,
                    matching: find.byKey(AppPressRipple.rippleLayerKey),
                  ),
                  findsOneWidget,
                );
                final clipFinder = find.descendant(
                  of: slot,
                  matching: find.byType(ClipRRect),
                );
                expect(clipFinder, findsOneWidget);
                final clip = tester.widget<ClipRRect>(clipFinder);
                expect(
                  clip.borderRadius,
                  BorderRadius.circular(tester.getSize(slot).height / 2),
                );
                expect(clip.clipBehavior, isNot(Clip.none));
                expect(tester.getRect(clipFinder), tester.getRect(slot));
                await gesture.up();
                await tester.pump();
                await tester.pump(const Duration(seconds: 1));
                expect(_configuredSelectionRect(tester), tester.getRect(slot));
                final icon = tester.widget<AppIcon>(
                  find.descendant(of: slot, matching: find.byType(AppIcon)),
                );
                expect(icon.color, AppTheme.brand);
              }
              expect(tester.takeException(), isNull);
              await _dispose(tester);
            } finally {
              debugDefaultTargetPlatformOverride = null;
            }
          },
        );
      }
    }
  }

  for (final glass in [false, true]) {
    testWidgets(
      '${glass ? 'glass selected' : 'classic unchanged'} tab glyph identities',
      (tester) async {
        await onIOS(() async {
          installMockGlassSurface(tester);
          await _pumpShell(tester, _phoneSize, liquidGlass: glass);
          const baseGlyphs = [
            HeroiconsSolid.chatBubbleLeft,
            HeroiconsOutline.hashtag,
            HeroiconsOutline.userGroup,
            HeroiconsOutline.arrowPath,
          ];
          const selectedGlyphs = [
            HeroiconsSolid.chatBubbleLeft,
            HeroiconsSolid.hashtag,
            HeroiconsSolid.userGroup,
            HeroiconsSolid.arrowPath,
          ];
          // Return to Messages so every other tab is checked after deselection.
          for (final selected in [0, 1, 2, 3, 0]) {
            await tester.tap(find.byKey(ValueKey('bottom-tab-$selected')));
            await tester.pump();
            await tester.pump(const Duration(seconds: 1));
            for (final tab in _tabs) {
              final slot = find.byKey(ValueKey('bottom-tab-${tab.index}'));
              final icon = tester.widget<AppIcon>(
                find.descendant(of: slot, matching: find.byType(AppIcon)),
              );
              expect(
                icon.icon.data,
                glass && tab.index == selected
                    ? selectedGlyphs[tab.index]
                    : baseGlyphs[tab.index],
                reason: '${tab.label}, selected=$selected, glass=$glass',
              );
              final colors = tester.element(slot).colors;
              expect(
                icon.color,
                tab.index == selected
                    ? AppTheme.brand
                    : glass
                    ? colors.textPrimary
                    : colors.textTertiary,
              );
              expect(
                semanticLabelOf(tester, ValueKey('bottom-tab-${tab.index}')),
                tab.label,
              );
            }
          }
          expect(tester.takeException(), isNull);
          await _dispose(tester);
        });
      },
    );
  }

  testWidgets('narrow phone keeps the native surface inside its insets', (
    tester,
  ) async {
    await onIOS(() async {
      installMockGlassSurface(tester);
      const size = Size(320, 568);
      await _pumpShell(
        tester,
        size,
        insets: const FakeViewPadding(top: 47, bottom: 34),
      );
      final surfaceRect = tester.getRect(find.byKey(_surfaceKey));
      expect(surfaceRect.bottom, lessThanOrEqualTo(size.height - 34));
      // The status-bar inset never leaks into the bar's own height.
      expect(surfaceRect.height, _surfaceHeight);
      // The lateral margins never push the row outside the window.
      expect(surfaceRect.left, _sideMargin);
      expect(surfaceRect.right, size.width - _sideMargin);
      final slot = find.byKey(_firstSlotKey);
      expect(tester.getRect(slot).bottom, lessThanOrEqualTo(size.height - 34));
      expect(tester.getRect(slot), _configuredSelectionRect(tester));
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });
  });

  testWidgets('split shell column honors the bottom inset too', (tester) async {
    await onIOS(() async {
      installMockGlassSurface(tester);
      // No camera inset and no usable split width, so the glass bar stays in
      // the narrow sidebar column.
      await _pumpShell(
        tester,
        const Size(900, 800),
        insets: const FakeViewPadding(bottom: 34),
      );
      final surfaceRect = tester.getRect(find.byKey(_surfaceKey));
      expect(surfaceRect.bottom, lessThanOrEqualTo(800 - 34));
      expect(surfaceRect.height, _surfaceHeight);
      final slot = find.byKey(_firstSlotKey);
      expect(tester.getRect(slot).bottom, lessThanOrEqualTo(800 - 34));
      expect(tester.getRect(slot), _configuredSelectionRect(tester));
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });
  });

  testWidgets('RTL glass host keeps containment and the channel flag', (
    tester,
  ) async {
    await onIOS(() async {
      final mock = installMockGlassSurface(tester);
      final homeIndicatorTop = _phoneSize.height - _phoneBottomInset;
      await _pumpShell(
        tester,
        _phoneSize,
        insets: const FakeViewPadding(bottom: _phoneBottomInset),
        textDirection: TextDirection.rtl,
      );
      expect(mock.createdParams, isNotEmpty);
      for (final params in mock.createdParams) {
        expect(params['rtl'], isTrue);
      }
      final surfaceRect = tester.getRect(find.byKey(_surfaceKey));
      expect(surfaceRect.bottom, lessThanOrEqualTo(homeIndicatorTop));
      expect(surfaceRect.height, _surfaceHeight);
      final slot = find.byKey(_firstSlotKey);
      expect(tester.getRect(slot).bottom, lessThanOrEqualTo(homeIndicatorTop));
      // Both the row and the pill mirror: the first slot sits on the right.
      expect(tester.getRect(slot), _configuredSelectionRect(tester));
      expect(tester.getRect(slot).left, greaterThan(_phoneSize.width / 2));
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });
  });

  // Every glass slot is an icon-only target. With the setting on no label
  // is drawn in the bar; its accessible name stays on AppInteractiveSurface.
  testWidgets('glass bar draws no tab label and keeps its semantic names', (
    tester,
  ) async {
    await onIOS(() async {
      installMockGlassSurface(tester);
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
      final unselected = find.byKey(const ValueKey('bottom-tab-1'));
      expect(
        tester.widget<AppInteractiveSurface>(unselected).borderRadius,
        BorderRadius.zero,
      );
      expect(
        tester
            .widget<AppIcon>(
              find.descendant(of: unselected, matching: find.byType(AppIcon)),
            )
            .color,
        tester.element(unselected).colors.textTertiary,
      );
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
      installMockGlassSurface(tester);
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

/// Mocks platform-view creation and the per-view channel for the whole test.
/// Under flutter test the real UIKit glass never exists, so the mock answers
/// the way the native side would (nothing to answer) while recording the
/// creation parameters each surface was configured with.
class GlassSurfaceMock {
  GlassSurfaceMock(this._messenger);

  final TestDefaultBinaryMessenger _messenger;
  final List<Map<Object?, Object?>> createdParams = [];
  final List<MethodCall> calls = [];
  final Map<int, MethodChannel> _channels = {};

  void install() {
    _messenger.setMockMethodCallHandler(
      const MethodChannel('mithka/native_tab_bar'),
      (call) async => false,
    );
    _messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        final arguments = call.arguments as Map;
        final id = arguments['id'] as int;
        createdParams.add(
          const StandardMessageCodec().decodeMessage(
                ByteData.sublistView(arguments['params'] as Uint8List),
              )
              as Map<Object?, Object?>,
        );
        final channel = MethodChannel('mithka/native_glass/$id');
        _channels[id] = channel;
        _messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
      }
      return null;
    });
  }

  void dispose() {
    _messenger.setMockMethodCallHandler(
      const MethodChannel('mithka/native_tab_bar'),
      null,
    );
    _messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    for (final channel in _channels.values) {
      _messenger.setMockMethodCallHandler(channel, null);
    }
    _channels.clear();
  }
}

/// Installs the mock for the current test and tears it down with the test.
GlassSurfaceMock installMockGlassSurface(WidgetTester tester) {
  final mock = GlassSurfaceMock(tester.binding.defaultBinaryMessenger);
  mock.install();
  addTearDown(mock.dispose);
  return mock;
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

Future<void> _pumpNativeConfiguration(WidgetTester tester) async {
  // Prewarming must stay before mount. Completed cached PNG Futures still
  // schedule listeners in runAsync's real zone; alternate real microtask turns
  // with fake pumps for item artwork, read-action artwork and the view handshake.
  for (var phase = 0; phase < 3; phase++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
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
