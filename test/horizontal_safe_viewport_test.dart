import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/adaptive_split_layout.dart';
import 'package:mithka/app/horizontal_safe_viewport.dart';

void main() {
  for (final value in <Object?>[
    1.0, // Native full-edge reservation (including beyond the window).
    double.nan,
    double.infinity,
    double.negativeInfinity,
    -0.1,
    1.1,
    'invalid',
  ]) {
    testWidgets('unavailable or invalid native rail: $value', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        const channel = MethodChannel('mithka/window_geometry');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (_) async => {'topFraction': value},
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        SideNavigationGeometry? geometry;
        const railKey = ValueKey('unavailable-rail');
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: const MediaQueryData(
                size: Size(466, 678),
                padding: EdgeInsets.only(right: 84, bottom: 34),
              ),
              child: HorizontalSafeViewport(
                sideNavigation: true,
                child: Builder(
                  builder: (context) {
                    geometry = SideNavigationGeometry.of(context);
                    return const SideNavigationPortal(
                      visible: true,
                      fillSide: true,
                      child: SizedBox.expand(key: railKey),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(geometry!.sideTop, 678);
        expect(geometry!.fits(1, 56), isFalse);
        expect(find.byKey(railKey), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  test(
    'missing geometry keeps fallback; valid fractions include both edges',
    () {
      SideNavigationGeometry geometry(double? fraction) =>
          SideNavigationGeometry(
            window: const MediaQueryData(
              size: Size(466, 678),
              padding: EdgeInsets.only(right: 84),
            ),
            enabled: true,
            sideTopFraction: fraction,
            child: const SizedBox.shrink(),
          );
      expect(geometry(null).sideTop, 339);
      expect(geometry(null).fits(4, 56), isTrue);
      expect(geometry(0).sideTop, 0);
      expect(geometry(0).fits(10, 56), isTrue);
      expect(geometry(1).sideTop, 678);
      expect(geometry(1).fits(1, 56), isFalse);
      expect(geometry(double.nan).fits(1, 56), isFalse);
      expect(geometry(0).fits(1, double.infinity), isFalse);
    },
  );

  testWidgets(
    'native geometry keeps the rail in system space across Duo displays',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        const channel = MethodChannel('mithka/window_geometry');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (_) async => {'topFraction': 0.25},
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(466, 678);
        tester.view.padding = const FakeViewPadding(right: 84, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(right: 84, bottom: 34);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        const contentKey = ValueKey('retained-native-content');
        const railKey = ValueKey('native-positioned-rail');
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery.fromView(
              view: tester.view,
              child: const HorizontalSafeViewport(
                sideNavigation: true,
                child: Stack(
                  key: contentKey,
                  children: [
                    SideNavigationPortal(
                      visible: true,
                      fillSide: true,
                      child: SizedBox.expand(key: railKey),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final element = tester.element(find.byKey(contentKey));
        expect(
          tester.getRect(find.byKey(railKey)),
          const Rect.fromLTWH(382, 169.5, 84, 474.5),
        );
        tester.view.physicalSize = const Size(951, 669);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(railKey)),
          const Rect.fromLTWH(867, 167.25, 84, 467.75),
        );
        expect(
          tester.getRect(find.byKey(contentKey)),
          const Rect.fromLTWH(0, 0, 867, 669),
        );
        expect(tester.element(find.byKey(contentKey)), same(element));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('side controls remain below a full-window blocking overlay', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(466, 678);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var blocked = false;
    var taps = 0;
    late StateSetter update;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(
            size: Size(466, 678),
            padding: EdgeInsets.only(right: 84, bottom: 34),
          ),
          child: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Stack(
                children: [
                  Positioned.fill(
                    child: HorizontalSafeViewport(
                      sideNavigation: true,
                      child: SideNavigationPortal(
                        visible: true,
                        child: GestureDetector(
                          onTap: () => taps++,
                          child: const SizedBox(
                            width: 84,
                            height: 64,
                            child: ColoredBox(color: Color(0xff0000ff)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (blocked)
                    const Positioned.fill(
                      child: AbsorbPointer(
                        child: ColoredBox(color: Color(0xff000000)),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(425, 610));
    expect(taps, 1);
    update(() => blocked = true);
    await tester.pump();
    await tester.tapAt(const Offset(425, 610));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Duo reserves the side status area and preserves bottom insets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(466, 678);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    MediaQueryData? actual;
    const contentKey = ValueKey('content');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(
            size: Size(466, 678),
            padding: EdgeInsets.only(right: 84, bottom: 34),
            viewPadding: EdgeInsets.only(right: 84, bottom: 34),
          ),
          child: HorizontalSafeViewport(
            child: Builder(
              builder: (context) {
                actual = MediaQuery.of(context);
                return const SizedBox.expand(key: contentKey);
              },
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getRect(find.byKey(contentKey)),
      const Rect.fromLTWH(0, 0, 382, 678),
    );
    expect(actual!.size, const Size(382, 678));
    expect(actual!.padding, const EdgeInsets.only(bottom: 34));
    expect(actual!.viewPadding, const EdgeInsets.only(bottom: 34));
  });

  testWidgets(
    'moving system chrome preserves content and uses usable split width',
    (tester) async {
      tester.view.physicalSize = const Size(800, 650);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      MediaQueryData? actual;
      const key = ValueKey('retained');
      final content = Builder(
        key: key,
        builder: (context) {
          actual = MediaQuery.of(context);
          return const SizedBox.expand();
        },
      );
      Future<void> show(EdgeInsets insets) => tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery(
            data: MediaQueryData(
              size: const Size(800, 650),
              padding: insets,
              viewPadding: insets,
              displayFeatures: const [
                DisplayFeature(
                  bounds: Rect.fromLTWH(400, 0, 0, 650),
                  type: DisplayFeatureType.fold,
                  state: DisplayFeatureState.postureHalfOpened,
                ),
              ],
            ),
            child: HorizontalSafeViewport(sideNavigation: true, child: content),
          ),
        ),
      );
      await show(const EdgeInsets.only(right: 84));
      final element = tester.element(find.byKey(key));
      expect(actual!.size.width, 716);
      expect(
        usesAdaptiveSplitLayout(actual!.size, platform: TargetPlatform.iOS),
        isFalse,
      );
      await show(EdgeInsets.zero);
      expect(
        usesAdaptiveSplitLayout(actual!.size, platform: TargetPlatform.iOS),
        isTrue,
      );
      await show(const EdgeInsets.only(left: 84));
      expect(tester.element(find.byKey(key)), same(element));
      expect(tester.getTopLeft(find.byKey(key)).dx, 84);
      expect(actual!.displayFeatures.single.bounds.left, 316);
      expect(
        actual!.displayFeatures.single.state,
        DisplayFeatureState.postureHalfOpened,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
