import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Where the system keeps its status items along the top edge of the window.
///
/// An opened iPhone Duo gathers the clock and status icons into a cluster in
/// one corner, yet its safe area still reserves the full height of that
/// cluster across the whole top edge. Side-by-side panes would then all start
/// far below the top, although only the pane under the cluster meets it.
@immutable
class TopOcclusionData {
  const TopOcclusionData({
    required this.safeTop,
    required this.statusBarBottom,
    required this.windowWidth,
    required this.regions,
  });

  /// The window's top safe-area inset.
  final double safeTop;

  /// Bottom of the full-width status bar; near zero when the system shows
  /// its status items as a corner cluster instead.
  final double statusBarBottom;

  final double windowWidth;

  /// Active occlusion regions inside the top band, in window coordinates.
  final List<Rect> regions;

  /// Top band every pane keeps when the cluster leaves the rest of the edge
  /// free: clears the screen's rounded corner, as on iPad.
  static const double paneTop = 24;

  /// Space between a header's controls and the cluster.
  static const double controlGap = 8;

  /// The shared top band for side-by-side panes, or null when the top inset
  /// comes from something that spans the edge and must be kept.
  double? get compactTop {
    if (regions.isEmpty || !safeTop.isFinite || safeTop <= paneTop) {
      return null;
    }
    if (!windowWidth.isFinite || windowWidth <= 0) return null;
    // A full-width status bar is real content along the whole edge.
    if (!statusBarBottom.isFinite || statusBarBottom > paneTop) return null;
    // The inset must be the cluster's own height, not a deeper system bar.
    final clusterBottom = regions.map((r) => r.bottom).reduce(math.max);
    if ((clusterBottom - safeTop).abs() > 1) return null;
    // The cluster must leave most of the edge free.
    final covered = regions.fold<double>(
      0,
      (sum, r) => sum + r.width.clamp(0, windowWidth),
    );
    if (covered > windowWidth / 2) return null;
    return paneTop;
  }

  static TopOcclusionData? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    double? number(Object? value) =>
        value is num && value.isFinite ? value.toDouble() : null;
    final safeTop = number(map['safeTop']);
    final statusBarBottom = number(map['statusBarBottom']);
    final width = number(map['width']);
    final rawRegions = map['regions'];
    if (safeTop == null ||
        statusBarBottom == null ||
        width == null ||
        rawRegions is! List) {
      return null;
    }
    final regions = <Rect>[];
    for (final raw in rawRegions) {
      if (raw is! List || raw.length != 4) return null;
      final values = raw.map(number).toList();
      if (values.any((v) => v == null)) return null;
      final rect = Rect.fromLTWH(
        values[0]!,
        values[1]!,
        values[2]!,
        values[3]!,
      );
      if (rect.width <= 0 || rect.height <= 0) return null;
      regions.add(rect);
    }
    return TopOcclusionData(
      safeTop: safeTop,
      statusBarBottom: statusBarBottom,
      windowWidth: width,
      regions: List.unmodifiable(regions),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TopOcclusionData &&
      other.safeTop == safeTop &&
      other.statusBarBottom == statusBarBottom &&
      other.windowWidth == windowWidth &&
      listEquals(other.regions, regions);

  @override
  int get hashCode => Object.hash(
    safeTop,
    statusBarBottom,
    windowWidth,
    Object.hashAll(regions),
  );
}

/// Provides [TopOcclusionData] for the main window.
class TopOcclusionGeometry extends InheritedWidget {
  const TopOcclusionGeometry({
    super.key,
    required this.data,
    required super.child,
  });

  final TopOcclusionData? data;

  static TopOcclusionData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TopOcclusionGeometry>()?.data;

  @override
  bool updateShouldNotify(TopOcclusionGeometry oldWidget) =>
      data != oldWidget.data;
}

/// One pane of a side-by-side layout.
///
/// When the status items sit in a corner cluster, the pane starts at the
/// shared [TopOcclusionData.paneTop] band instead of the full cluster height,
/// so neighbouring headers line up, and headers inside it read
/// [TopClusterInsets.of] to end their controls before the cluster.
class TopClusterPane extends StatefulWidget {
  const TopClusterPane({super.key, this.enabled = true, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<TopClusterPane> createState() => _TopClusterPaneState();
}

class _TopClusterPaneState extends State<TopClusterPane> {
  EdgeInsets _headerInsets = EdgeInsets.zero;
  bool _measureScheduled = false;

  void _scheduleMeasure(TopOcclusionData data, double top) {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return;
      // Panes sit still inside their row; their window position is final
      // once laid out, unlike routes sliding in within a pane.
      final pane = box.localToGlobal(Offset.zero) & box.size;
      var left = 0.0;
      var right = 0.0;
      for (final region in data.regions) {
        if (region.bottom <= top) continue;
        final start = region.left - TopOcclusionData.controlGap;
        final end = region.right + TopOcclusionData.controlGap;
        if (end <= pane.left || start >= pane.right) continue;
        if (region.center.dx >= pane.center.dx) {
          right = math.max(right, pane.right - start);
        } else {
          left = math.max(left, end - pane.left);
        }
      }
      // Never let the cluster take more than half of a header.
      final limit = pane.width / 2;
      final next = EdgeInsets.only(
        left: left.clamp(0, limit).toDouble(),
        right: right.clamp(0, limit).toDouble(),
      );
      if (next != _headerInsets) setState(() => _headerInsets = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = TopOcclusionGeometry.maybeOf(context);
    final media = MediaQuery.of(context);
    // Only a pane that still owns the window's top inset is moved up.
    final top =
        widget.enabled &&
            data != null &&
            (media.padding.top - data.safeTop).abs() <= 1
        ? data.compactTop
        : null;
    if (top == null) _headerInsets = EdgeInsets.zero;
    // The tree keeps one shape whether or not the band applies, so opening
    // or closing the device never rebuilds the pane's routes from scratch.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (data != null && top != null) _scheduleMeasure(data, top);
        return MediaQuery(
          data: top == null
              ? media
              : media.copyWith(
                  padding: media.padding.copyWith(top: top),
                  viewPadding: media.viewPadding.copyWith(top: top),
                ),
          child: TopClusterInsets(
            insets: top == null ? EdgeInsets.zero : _headerInsets,
            bandActive: top != null,
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// Horizontal space a header row inside a [TopClusterPane] leaves free for
/// the corner cluster. Zero everywhere else.
class TopClusterInsets extends InheritedWidget {
  const TopClusterInsets({
    super.key,
    required this.insets,
    this.bandActive = false,
    required super.child,
  });

  final EdgeInsets insets;

  /// Whether the pane starts at the shared [TopOcclusionData.paneTop] band
  /// rather than below the window's full top inset.
  final bool bandActive;

  static EdgeInsets of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TopClusterInsets>()?.insets ??
      EdgeInsets.zero;

  static bool bandActiveOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<TopClusterInsets>()
          ?.bandActive ??
      false;

  @override
  bool updateShouldNotify(TopClusterInsets oldWidget) =>
      insets != oldWidget.insets || bandActive != oldWidget.bandActive;
}
