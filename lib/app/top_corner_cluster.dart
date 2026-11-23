import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
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
    this.scale = 1,
  });

  /// The window's top safe-area inset.
  final double safeTop;

  /// Bottom of the full-width status bar; near zero when the system shows
  /// its status items as a corner cluster instead.
  final double statusBarBottom;

  final double windowWidth;

  /// Active occlusion regions inside the top band, in window coordinates.
  final List<Rect> regions;

  /// Window points per unit of these lengths. The platform reports window
  /// points (1); inside an interface-size view the lengths are divided by its
  /// rendered scale so they compare directly with that view's layout.
  final double scale;

  /// Top band every pane keeps when the cluster leaves the rest of the edge
  /// free: clears the screen's rounded corner, as on iPad. Window points.
  static const double paneTop = 24;

  /// Space between a header's controls and the cluster. Window points.
  static const double controlGap = 8;

  /// [paneTop] in this data's units, so it stays 24 window points at every
  /// interface size.
  double get bandTop => paneTop / scale;

  /// [controlGap] in this data's units.
  double get gap => controlGap / scale;

  /// One window point in this data's units: how far two measurements may
  /// disagree and still mean the same edge.
  double get tolerance => 1 / scale;

  /// The same geometry measured in a view that renders [viewScale] window
  /// points per unit, such as [ScaledAppView] at an interface size.
  TopOcclusionData inViewScale(double viewScale) {
    if (!viewScale.isFinite || viewScale <= 0 || viewScale == 1) return this;
    return TopOcclusionData(
      safeTop: safeTop / viewScale,
      statusBarBottom: statusBarBottom / viewScale,
      windowWidth: windowWidth / viewScale,
      regions: List.unmodifiable([
        for (final region in regions)
          Rect.fromLTRB(
            region.left / viewScale,
            region.top / viewScale,
            region.right / viewScale,
            region.bottom / viewScale,
          ),
      ]),
      scale: scale * viewScale,
    );
  }

  /// The shared top band for side-by-side panes, or null when the top inset
  /// comes from something that spans the edge and must be kept.
  double? get compactTop {
    if (regions.isEmpty || !safeTop.isFinite || safeTop <= bandTop) {
      return null;
    }
    if (!windowWidth.isFinite || windowWidth <= 0) return null;
    // A full-width status bar is real content along the whole edge.
    if (!statusBarBottom.isFinite || statusBarBottom > bandTop) return null;
    // The inset must be the cluster's own height, not a deeper system bar.
    final clusterBottom = regions.map((r) => r.bottom).reduce(math.max);
    if ((clusterBottom - safeTop).abs() > tolerance) return null;
    // The cluster must leave most of the edge free. Regions nest (the closed
    // iPhone Duo reports its camera inside the status cluster), so measure
    // the edge they cover together rather than adding their widths.
    if (_coveredWidth > windowWidth / 2) return null;
    return bandTop;
  }

  double get _coveredWidth {
    final spans = [
      for (final r in regions)
        (
          r.left.clamp(0.0, windowWidth).toDouble(),
          r.right.clamp(0.0, windowWidth).toDouble(),
        ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    var covered = 0.0;
    var end = double.negativeInfinity;
    for (final (left, right) in spans) {
      if (right <= end) continue;
      covered += right - math.max(left, end);
      end = right;
    }
    return covered;
  }

  /// Room a header row inside [pane] leaves for the cluster: the side of the
  /// pane the cluster meets keeps the cluster plus [gap] free. Both rects are
  /// in this data's units. Never more than half of the pane.
  EdgeInsets headerInsetsFor(Rect pane, {required double top}) {
    var left = 0.0;
    var right = 0.0;
    for (final region in regions) {
      if (region.bottom <= top) continue;
      final start = region.left - gap;
      final end = region.right + gap;
      if (end <= pane.left || start >= pane.right) continue;
      if (region.center.dx >= pane.center.dx) {
        right = math.max(right, pane.right - start);
      } else {
        left = math.max(left, end - pane.left);
      }
    }
    final limit = pane.width / 2;
    return EdgeInsets.only(
      left: left.clamp(0, limit).toDouble(),
      right: right.clamp(0, limit).toDouble(),
    );
  }

  /// Where a header row at the very top of the window can sit beside the
  /// cluster instead of below it, or null when no cluster runs along the top
  /// edge above [header] (a centred island, a cluster on another pane, a
  /// full-width status bar) or it leaves the row too little room.
  TopClusterRowSlot? rowSlotBeside(Rect header) {
    if (compactTop == null || header.isEmpty) return null;
    if (header.top.abs() > tolerance) return null;
    Rect? cluster;
    var left = 0.0;
    var right = 0.0;
    for (final region in regions) {
      // Only what hangs from the top edge itself shares the row's band.
      if (region.top > bandTop) continue;
      final start = region.left - gap;
      final end = region.right + gap;
      if (end <= header.left || start >= header.right) continue;
      if (region.center.dx >= header.center.dx) {
        right = math.max(right, header.right - start);
      } else {
        left = math.max(left, end - header.left);
      }
      cluster = cluster?.expandToInclude(region) ?? region;
    }
    if (cluster == null) return null;
    if (left + right > header.width / 2) return null;
    // The row shares the line of the status items themselves. The cluster's
    // region runs down to the full inset; a region nested in it (the camera
    // beside the clock on a closed iPhone Duo) marks that line, so the row
    // centres on the innermost one and only needs to clear its bottom.
    var line = cluster;
    for (final region in regions) {
      if (region.height < line.height && cluster.overlaps(region)) {
        line = region;
      }
    }
    return TopClusterRowSlot(
      centerY: line.center.dy - header.top,
      bottom: line.bottom - header.top,
      insets: EdgeInsets.only(left: left, right: right),
    );
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
      other.scale == scale &&
      listEquals(other.regions, regions);

  @override
  int get hashCode => Object.hash(
    safeTop,
    statusBarBottom,
    windowWidth,
    scale,
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
      final pane = _rectInViewUnits(box, data.scale);
      final next = data.headerInsetsFor(pane, top: top);
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
            (media.padding.top - data.safeTop).abs() <= data.tolerance
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

/// Where a header row beside the corner cluster sits, in the header's own
/// coordinates and [TopOcclusionData] units.
@immutable
class TopClusterRowSlot {
  const TopClusterRowSlot({
    required this.centerY,
    required this.bottom,
    required this.insets,
  });

  /// The vertical centre of the status items' line, which the row's content
  /// shares.
  final double centerY;

  /// Bottom of that line: whatever follows the row starts at least here.
  final double bottom;

  /// Horizontal room kept for the cluster plus [TopOcclusionData.gap].
  final EdgeInsets insets;

  @override
  bool operator ==(Object other) =>
      other is TopClusterRowSlot &&
      other.centerY == centerY &&
      other.bottom == bottom &&
      other.insets == insets;

  @override
  int get hashCode => Object.hash(centerY, bottom, insets);
}

/// Lets a header at the very top of the window move its first row up beside
/// a corner status cluster that hangs from the top edge above it, as on a
/// closed iPhone Duo. [builder] gets null wherever the header keeps the
/// window's full top inset: no cluster, a cluster elsewhere, or a header that
/// no longer owns the top inset (inside a [TopClusterPane] band).
class TopClusterRowBeside extends StatefulWidget {
  const TopClusterRowBeside({super.key, required this.builder});

  final Widget Function(BuildContext context, TopClusterRowSlot? slot) builder;

  @override
  State<TopClusterRowBeside> createState() => _TopClusterRowBesideState();
}

class _TopClusterRowBesideState extends State<TopClusterRowBeside> {
  TopClusterRowSlot? _slot;
  bool _measureScheduled = false;

  void _scheduleMeasure(TopOcclusionData data) {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return;
      // The slot depends only on where the header starts and how wide it is,
      // never on the height it then takes, so this settles in one pass.
      final next = data.rowSlotBeside(_rectInViewUnits(box, data.scale));
      if (next != _slot) setState(() => _slot = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = TopOcclusionGeometry.maybeOf(context);
    final media = MediaQuery.of(context);
    final owns =
        data != null &&
        data.compactTop != null &&
        (media.padding.top - data.safeTop).abs() <= data.tolerance;
    if (!owns) {
      _slot = null;
    } else {
      // Re-measure after every build: a header can be built mid-transition
      // and only reach its resting place later.
      _scheduleMeasure(data);
    }
    return widget.builder(context, _slot);
  }
}

/// Lays a header row out on a [TopClusterRowSlot]: the row's vertical centre
/// on the status items' line, then [bottomGap] below the row, and never
/// shorter than that line, so whatever follows starts clear of it.
class TopClusterRow extends SingleChildRenderObjectWidget {
  const TopClusterRow({
    super.key,
    required this.slot,
    this.bottomGap = 0,
    super.child,
  });

  final TopClusterRowSlot slot;
  final double bottomGap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderTopClusterRow(slot, bottomGap);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTopClusterRow renderObject,
  ) {
    renderObject
      ..slot = slot
      ..bottomGap = bottomGap;
  }
}

/// Render object for [TopClusterRow].
class RenderTopClusterRow extends RenderShiftedBox {
  RenderTopClusterRow(this._slot, this._bottomGap) : super(null);

  TopClusterRowSlot _slot;
  set slot(TopClusterRowSlot value) {
    if (value == _slot) return;
    _slot = value;
    markNeedsLayout();
  }

  double _bottomGap;
  set bottomGap(double value) {
    if (value == _bottomGap) return;
    _bottomGap = value;
    markNeedsLayout();
  }

  BoxConstraints _childConstraints(BoxConstraints constraints) =>
      BoxConstraints(
        minWidth: constraints.minWidth,
        maxWidth: constraints.maxWidth,
      );

  Size _sizeFor(BoxConstraints constraints, Size child) {
    final top = math.max(0.0, _slot.centerY - child.height / 2);
    return constraints.constrain(
      Size(
        child.width,
        math.max(_slot.bottom, top + child.height + _bottomGap),
      ),
    );
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final child = this.child;
    if (child == null) {
      return constraints.constrain(Size(constraints.minWidth, _slot.bottom));
    }
    return _sizeFor(
      constraints,
      child.getDryLayout(_childConstraints(constraints)),
    );
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(Size(constraints.minWidth, _slot.bottom));
      return;
    }
    child.layout(_childConstraints(constraints), parentUsesSize: true);
    final top = math.max(0.0, _slot.centerY - child.size.height / 2);
    (child.parentData! as BoxParentData).offset = Offset(0, top);
    size = _sizeFor(constraints, child.size);
  }
}

/// [box]'s window rect in units of [scale] window points. The render tree
/// reports window points, the box's own size is already in those units, and
/// an interface-size view scales about the window's origin.
Rect _rectInViewUnits(RenderBox box, double scale) {
  final origin = box.localToGlobal(Offset.zero);
  return Rect.fromLTWH(
    origin.dx / scale,
    origin.dy / scale,
    box.size.width,
    box.size.height,
  );
}
