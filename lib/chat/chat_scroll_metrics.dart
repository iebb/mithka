import 'package:flutter/widgets.dart' show ScrollMetrics;

/// Distance from the viewport to the oldest loaded chat content.
///
/// Chat history is ordered so that the oldest edge is represented by
/// [ScrollMetrics.minScrollExtent]. The returned distance is zero while
/// overscrolling beyond that edge.
double distanceToOldest(ScrollMetrics metrics) => metrics.extentBefore;

/// Distance from the viewport to the latest loaded chat content.
///
/// Chat history is ordered so that the latest edge is represented by
/// [ScrollMetrics.maxScrollExtent]. The returned distance is zero while
/// overscrolling beyond that edge.
double distanceToLatest(ScrollMetrics metrics) => metrics.extentAfter;

/// Whether the viewport is within [threshold] pixels of the oldest edge.
bool isNearOldest(ScrollMetrics metrics, {required double threshold}) {
  assert(threshold >= 0);
  return distanceToOldest(metrics) <= threshold;
}

/// Whether the viewport is within [threshold] pixels of the latest edge.
bool isNearLatest(ScrollMetrics metrics, {required double threshold}) {
  assert(threshold >= 0);
  return distanceToLatest(metrics) <= threshold;
}

/// Clamps [offset] to the complete scroll range described by [metrics].
///
/// Unlike clamping to `0..maxScrollExtent`, this also supports viewports whose
/// content before a center sliver gives them a negative minimum extent.
double clampScrollOffset(ScrollMetrics metrics, double offset) =>
    offset.clamp(metrics.minScrollExtent, metrics.maxScrollExtent);

/// Returns the normalized position of [offset] in the complete scroll range.
///
/// When [offset] is omitted, [ScrollMetrics.pixels] is used. Values outside
/// the range are clamped to `0..1`. A range with no scrollable extent is at
/// fraction zero.
double scrollFraction(ScrollMetrics metrics, {double? offset}) {
  final extent = metrics.maxScrollExtent - metrics.minScrollExtent;
  if (extent <= 0) return 0;
  final clampedOffset = clampScrollOffset(metrics, offset ?? metrics.pixels);
  return (clampedOffset - metrics.minScrollExtent) / extent;
}

/// Converts [fraction] in `0..1` to an offset in the complete scroll range.
///
/// Fractions outside the range are clamped. A range with no scrollable extent
/// always resolves to its single available offset.
double scrollOffsetForFraction(ScrollMetrics metrics, double fraction) {
  final extent = metrics.maxScrollExtent - metrics.minScrollExtent;
  if (extent <= 0) return metrics.minScrollExtent;
  final clampedFraction = fraction.clamp(0.0, 1.0);
  return metrics.minScrollExtent + extent * clampedFraction;
}
