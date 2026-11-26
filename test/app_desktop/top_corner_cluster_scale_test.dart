import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/horizontal_safe_viewport.dart';
import 'package:mithka/app/scaled_app_view.dart';
import 'package:mithka/app/top_corner_cluster.dart';

/// iPhone Duo geometry as the platform reports it, in window points.
/// The closed screen reports the camera as its own region inside the status
/// cluster.
const _closedDuo = TopOcclusionData(
  safeTop: 82,
  statusBarBottom: 2,
  windowWidth: 466,
  regions: [Rect.fromLTWH(266, 0, 200, 82), Rect.fromLTWH(399.7, 29.3, 37, 37)],
);
const _openedDuo = TopOcclusionData(
  safeTop: 82,
  statusBarBottom: 2,
  windowWidth: 951,
  regions: [Rect.fromLTWH(807, 0, 144, 82)],
);

/// Rendered interface scales: 100%, 90% and 220%.
const _scales = [1.0, 0.9487, 1.483];

void main() {
  group('TopOcclusionData in an interface-size view', () {
    for (final s in _scales) {
      test('keeps the band and gap in window points at s=$s', () {
        final data = _openedDuo.inViewScale(s);
        expect(data.scale, s);
        expect(data.safeTop * s, moreOrLessEquals(82));
        expect(data.compactTop, isNotNull);
        expect(data.hasCornerStatusCluster, isTrue);
        expect(
          data.compactTop! * s,
          moreOrLessEquals(TopOcclusionData.paneTop),
        );
        expect(data.gap * s, moreOrLessEquals(TopOcclusionData.controlGap));
        expect(data.regions.single.left * s, moreOrLessEquals(807));
      });

      test('the opened right pane ends 8pt before the cluster at s=$s', () {
        final data = _openedDuo.inViewScale(s);
        final pane = Rect.fromLTRB(320 / s, 0, 951 / s, 669 / s);
        final insets = data.headerInsetsFor(pane, top: data.compactTop!);
        expect(insets.left, 0);
        expect(insets.right * s, moreOrLessEquals(951 - (807 - 8)));
        // The list pane on the left never meets the cluster.
        final list = Rect.fromLTRB(0, 0, 320 / s, 669 / s);
        expect(
          data.headerInsetsFor(list, top: data.compactTop!),
          EdgeInsets.zero,
        );
        expect(data.rowSlotBeside(list), isNull);
      });

      test('a closed header row sits beside the cluster at s=$s', () {
        final data = _closedDuo.inViewScale(s);
        final slot = data.rowSlotBeside(Rect.fromLTWH(0, 0, 466 / s, 200));
        expect(data.compactTop, isNotNull);
        expect(data.hasCornerStatusCluster, isTrue);
        expect(slot, isNotNull);
        // On the clock and camera line, not the middle of the 82pt inset.
        expect(slot!.centerY * s, moreOrLessEquals(47.8));
        expect(slot.bottom * s, moreOrLessEquals(66.3));
        expect(slot.insets.left, 0);
        // The row ends 8 window points before the cluster at x=266.
        expect((466 / s - slot.insets.right) * s, moreOrLessEquals(258));
      });
    }

    test('nested regions count the covered edge once', () {
      // 200 + 37 would pass half of the 466pt edge; together they cover 200.
      expect(_closedDuo.compactTop, TopOcclusionData.paneTop);
      const wide = TopOcclusionData(
        safeTop: 82,
        statusBarBottom: 2,
        windowWidth: 466,
        regions: [Rect.fromLTWH(0, 0, 120, 82), Rect.fromLTWH(300, 0, 166, 82)],
      );
      expect(wide.compactTop, isNull);
    });

    test('scale 1 returns the same data', () {
      expect(identical(_closedDuo.inViewScale(1), _closedDuo), isTrue);
    });

    test('a full-width status bar keeps the safe-area top', () {
      // A regular iPhone with a centred island under a full status bar.
      const phone = TopOcclusionData(
        safeTop: 62,
        statusBarBottom: 54,
        windowWidth: 440,
        regions: [Rect.fromLTWH(157, 11, 126, 37)],
      );
      for (final s in _scales) {
        final data = phone.inViewScale(s);
        expect(data.compactTop, isNull);
        expect(data.rowSlotBeside(Rect.fromLTWH(0, 0, 440 / s, 100)), isNull);
        expect(data.hasCornerStatusCluster, isFalse);
      }
    });

    test('a centred island cannot be a Duo cluster without a status bar', () {
      const island = TopOcclusionData(
        safeTop: 62,
        statusBarBottom: 0,
        windowWidth: 440,
        regions: [Rect.fromLTWH(157, 0, 126, 62)],
      );
      for (final s in _scales) {
        final data = island.inViewScale(s);
        // The geometry alone frees the edge; the island touches no side.
        expect(data.compactTop, isNotNull);
        expect(data.hasCornerStatusCluster, isFalse);
      }
    });

    test('a header below the window top keeps its layout', () {
      expect(
        _closedDuo.rowSlotBeside(const Rect.fromLTWH(0, 60, 466, 100)),
        isNull,
      );
    });
  });

  group('rowSlotInBand on an opened Duo', () {
    for (final s in _scales) {
      test('both columns share the clock line at s=$s', () {
        final data = _openedDuo.inViewScale(s);
        final width = 951 / s;
        // Left column, away from the cluster: on the line, own spacing below.
        final left = data.rowSlotInBand(Rect.fromLTWH(0, 0, 400 / s, 120));
        expect(left, isNotNull);
        expect(left!.centerY * s, moreOrLessEquals(41));
        expect(left.bottom, 0);
        expect(left.insets, EdgeInsets.zero);
        // Right column, under the cluster: on the line and clear of it.
        final right = data.rowSlotInBand(
          Rect.fromLTWH(401 / s, 0, width - 401 / s, 120),
          room: EdgeInsets.only(right: 152 / s),
        );
        expect(right, isNotNull);
        expect(right!.centerY * s, moreOrLessEquals(41));
        expect(right.bottom * s, moreOrLessEquals(82));
      });
    }

    test('keeps today\'s header when the row has no room or starts lower', () {
      expect(
        _openedDuo.rowSlotInBand(
          const Rect.fromLTWH(651, 0, 300, 120),
          room: const EdgeInsets.only(right: 152),
        ),
        isNull,
      );
      expect(
        _openedDuo.rowSlotInBand(const Rect.fromLTWH(0, 24, 400, 120)),
        isNull,
      );
    });

    test('a full-width status bar never moves the row', () {
      const phone = TopOcclusionData(
        safeTop: 59,
        statusBarBottom: 54,
        windowWidth: 402,
        regions: [Rect.fromLTWH(140, 11, 122, 37)],
      );
      expect(phone.rowSlotInBand(const Rect.fromLTWH(0, 0, 402, 120)), isNull);
      expect(phone.rowSlotBeside(const Rect.fromLTWH(0, 0, 402, 120)), isNull);
    });
  });

  group('TopClusterPane under ScaledAppView', () {
    for (final s in _scales) {
      testWidgets('both opened panes start 24 window points down at s=$s', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(951, 669);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 82);
        addTearDown(tester.view.reset);
        final probes = <String, (double, EdgeInsets, bool)>{};
        Widget probe(String name) => Builder(
          builder: (context) {
            probes[name] = (
              MediaQuery.paddingOf(context).top,
              TopClusterInsets.of(context),
              TopClusterInsets.bandActiveOf(context),
            );
            return const SizedBox.expand();
          },
        );
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData.fromView(tester.view),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: ScaledAppView(
                textScale: 1,
                interfaceScale: s,
                child: Builder(
                  builder: (context) => TopOcclusionGeometry(
                    data: _openedDuo.inViewScale(
                      ScaledAppView.scaleOf(context),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 320 / s,
                          child: TopClusterPane(child: probe('list')),
                        ),
                        Expanded(child: TopClusterPane(child: probe('detail'))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final (listTop, listInsets, listBand) = probes['list']!;
        final (detailTop, detailInsets, detailBand) = probes['detail']!;
        expect(listBand, isTrue);
        expect(detailBand, isTrue);
        expect(listTop * s, moreOrLessEquals(24));
        expect(detailTop * s, moreOrLessEquals(24));
        expect(listInsets, EdgeInsets.zero);
        expect(detailInsets.right * s, moreOrLessEquals(152, epsilon: 0.01));
      });
    }
  });

  testWidgets(
    'HorizontalSafeViewport hands out geometry in view units',
    (tester) async {
      tester.view.physicalSize = const Size(466, 1000);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 82);
      addTearDown(tester.view.reset);
      const channel = MethodChannel('mithka/window_geometry');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        return switch (call.method) {
          'sideNavigationGeometry' => {'topFraction': 0.5},
          'topOcclusionGeometry' => {
            'safeTop': 82.0,
            'statusBarBottom': 2.0,
            'width': 466.0,
            'regions': [
              [266.0, 0.0, 200.0, 82.0],
            ],
          },
          _ => null,
        };
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      const s = 1.483;
      TopOcclusionData? seen;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData.fromView(tester.view),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ScaledAppView(
              textScale: 1,
              interfaceScale: s,
              child: HorizontalSafeViewport(
                sideNavigation: true,
                child: Builder(
                  builder: (context) {
                    seen = TopOcclusionGeometry.maybeOf(context);
                    return const SizedBox.expand();
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(seen, isNotNull);
      expect(seen!.scale, s);
      expect(seen!.safeTop, moreOrLessEquals(82 / s));
      expect(seen!.compactTop! * s, moreOrLessEquals(24));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
