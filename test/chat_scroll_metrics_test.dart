import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_scroll_metrics.dart';

void main() {
  group('chat scroll metrics', () {
    test('measures both edges when the minimum extent is negative', () {
      final metrics = _metrics(min: -600, max: 1400, pixels: -100);

      expect(distanceToOldest(metrics), 500);
      expect(distanceToLatest(metrics), 1500);
    });

    test('edge distances stop at zero during overscroll', () {
      final beforeOldest = _metrics(min: -600, max: 1400, pixels: -640);
      final afterLatest = _metrics(min: -600, max: 1400, pixels: 1440);

      expect(distanceToOldest(beforeOldest), 0);
      expect(distanceToLatest(afterLatest), 0);
    });

    test('near-edge checks include the threshold boundary', () {
      final nearOldest = _metrics(min: -500, max: 1500, pixels: -420);
      final nearLatest = _metrics(min: -500, max: 1500, pixels: 1470);

      expect(isNearOldest(nearOldest, threshold: 80), isTrue);
      expect(isNearOldest(nearOldest, threshold: 79), isFalse);
      expect(isNearLatest(nearLatest, threshold: 30), isTrue);
      expect(isNearLatest(nearLatest, threshold: 29), isFalse);
    });

    test('clamps offsets against the actual negative minimum', () {
      final metrics = _metrics(min: -900, max: 1100, pixels: 0);

      expect(clampScrollOffset(metrics, -2000), -900);
      expect(clampScrollOffset(metrics, -225), -225);
      expect(clampScrollOffset(metrics, 2000), 1100);
    });

    test('maps offsets to fractions across the complete extent range', () {
      final metrics = _metrics(min: -900, max: 1100, pixels: -400);

      expect(scrollFraction(metrics), closeTo(0.25, 0.0001));
      expect(scrollFraction(metrics, offset: 600), closeTo(0.75, 0.0001));
      expect(scrollFraction(metrics, offset: -2000), 0);
      expect(scrollFraction(metrics, offset: 2000), 1);
    });

    test('maps fractions to offsets across the complete extent range', () {
      final metrics = _metrics(min: -900, max: 1100, pixels: 0);

      expect(scrollOffsetForFraction(metrics, 0), -900);
      expect(scrollOffsetForFraction(metrics, 0.25), -400);
      expect(scrollOffsetForFraction(metrics, 0.5), 100);
      expect(scrollOffsetForFraction(metrics, 1), 1100);
      expect(scrollOffsetForFraction(metrics, -1), -900);
      expect(scrollOffsetForFraction(metrics, 2), 1100);
    });

    test('handles a range with no scrollable extent', () {
      final metrics = _metrics(min: -75, max: -75, pixels: -75);

      expect(clampScrollOffset(metrics, 100), -75);
      expect(scrollFraction(metrics), 0);
      expect(scrollOffsetForFraction(metrics, 0.75), -75);
      expect(isNearOldest(metrics, threshold: 0), isTrue);
      expect(isNearLatest(metrics, threshold: 0), isTrue);
    });
  });
}

FixedScrollMetrics _metrics({
  required double min,
  required double max,
  required double pixels,
}) {
  return FixedScrollMetrics(
    minScrollExtent: min,
    maxScrollExtent: max,
    pixels: pixels,
    viewportDimension: 400,
    axisDirection: AxisDirection.down,
    devicePixelRatio: 1,
  );
}
