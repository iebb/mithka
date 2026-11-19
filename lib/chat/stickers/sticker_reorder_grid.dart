//
//  sticker_reorder_grid.dart
//
//  A lazy, long-press drag-reorderable sticker grid, the gesture Telegram
//  clients use to reorder stickers in a pack. Flutter has no built-in
//  reorderable grid, so this pairs one SliverGrid of [LongPressDraggable]
//  cells with drop resolution computed from the live cell geometry: the drop
//  target is the cell under the pointer when the drag ends, matched against
//  each mounted cell's rectangle. The grid stays lazy — only painted cells
//  participate in the drop math, and dragging near an edge auto-scrolls so
//  off-screen rows can be reached.
//
//  Drag end paths are deliberately split. A pointer-up over a cell is the
//  only path that persists a reorder; a cancelled drag (native pointer
//  cancellation, a disabling rebuild while the drag is live, or dispose)
//  ends the drag, drops the feedback, stops the autoscroll, and writes
//  nothing. A second pointer touching during a drag never starts a
//  competing gesture (LongPressDraggable's single-flight recognizer plus
//  [_startDrag]'s guard).
//
//  Motion contract: no tickers, no AnimationControllers. Reduced motion
//  disables dragging entirely (the hosting screen keeps its non-drag
//  Move earlier / Move later actions as the fallback), so the component can
//  never start an animation on a deactivated element.
//

import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Persists a reorder; [newIndex] is the final position of the dragged item
/// after it is removed from [oldIndex] (i.e. the index of the cell it was
/// dropped on, insert-after-removal semantics).
typedef StickerReorderCallback =
    Future<void> Function(int oldIndex, int newIndex);

/// A drag-reorderable sliver grid.
///
/// [itemCount] is the number of cells in the grid; [reorderableCount] caps the
/// drop target so trailing non-sticker tiles (the add tile) can never be a
/// destination. [cellBuilder] builds cell [index]'s content; the component
/// supplies the drag wrapper.
class StickerReorderGridSliver extends StatefulWidget {
  const StickerReorderGridSliver({
    super.key,
    required this.itemCount,
    required this.reorderableCount,
    required this.cellBuilder,
    required this.onReorder,
    this.crossAxisCount = 4,
    this.spacing = 10,
    this.dragEnabled = true,
    this.scrollController,
    this.viewportKey,
    this.edgeAutoscrollInset = 56,
  });

  final int itemCount;
  final int reorderableCount;
  final Widget Function(BuildContext context, int index) cellBuilder;
  final StickerReorderCallback onReorder;
  final int crossAxisCount;
  final double spacing;
  final bool dragEnabled;

  /// Scroll controller of the hosting scroll view; when provided together
  /// with [viewportKey], dragging near the viewport edge scrolls it.
  final ScrollController? scrollController;
  final GlobalKey? viewportKey;

  /// Height band at the top and bottom of the viewport where dragging
  /// auto-scrolls.
  final double edgeAutoscrollInset;

  @override
  State<StickerReorderGridSliver> createState() =>
      _StickerReorderGridSliverState();
}

class _StickerReorderGridSliverState extends State<StickerReorderGridSliver> {
  static const _autoscrollInterval = Duration(milliseconds: 110);

  final Map<int, GlobalKey> _cellKeys = {};
  int? _draggingIndex;
  Offset? _lastPointer;
  double _cellExtent = 0;
  bool _autoscrollingUp = false;
  bool _autoscrollingDown = false;
  Timer? _autoscrollTimer;

  /// The drag was cancelled (native pointer cancellation): set by the
  /// recognizer's cancel callback before the end callback runs, so the end
  /// path can tell an aborted drag from a real drop. This grid has no
  /// [DragTarget]s (drop math is manual), so `wasAccepted` in [onDragEnd]
  /// is always false and cannot be the discriminator.
  bool _pointerCancelled = false;

  /// The pointer id that pressed each cell, captured on pointer-down so the
  /// drag's cancel/up can be matched to the exact finger that owns it. An
  /// overlapping second finger is a different id and must not abort the
  /// first drag.
  final Map<int, int> _downPointerByCell = {};

  GlobalKey _cellKey(int index) => _cellKeys.putIfAbsent(index, GlobalKey.new);

  bool get _effectiveDragEnabled =>
      widget.dragEnabled &&
      !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);

  @override
  void didUpdateWidget(covariant StickerReorderGridSliver old) {
    super.didUpdateWidget(old);
    if (widget.itemCount < old.itemCount) {
      _cellKeys.removeWhere((index, _) => index >= widget.itemCount);
    }
    // Losing the drag affordance mid-drag (edit mode opened, an operation
    // went in flight, reduced motion turned on) is a cancellation, not a
    // drop: the user never lifted the pointer to choose a destination.
    if (!_effectiveDragEnabled) _abortDrag();
  }

  @override
  void dispose() {
    // Never setState here: the element is being unmounted (mounted is still
    // true while the framework marks it defunct), so only cancel the timer
    // and clear the drag fields. The live-abort UI refresh belongs to
    // [_abortDrag], which runs while the widget is still built.
    _autoscrollTimer?.cancel();
    _autoscrollTimer = null;
    _autoscrollingUp = false;
    _autoscrollingDown = false;
    _lastPointer = null;
    _draggingIndex = null;
    super.dispose();
  }

  Rect? _cellRect(int index) {
    final renderObject = _cellKeys[index]?.currentContext?.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return null;
    }
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  /// The live mounted cell indexes: the keys whose render boxes are actually
  /// in the tree right now. Lazy construction keeps this sparse — after a
  /// scroll jump the mounted bottom cells are not the low indexes — so drop
  /// math must never assume indexes are dense in `0..length`.
  Iterable<int> get _mountedIndexes => _cellKeys.entries
      .map((entry) => entry.key)
      .where((index) => _cellKeys[index]?.currentContext != null);

  /// The drop target for a global pointer position: the cell whose rectangle
  /// contains it, or the nearest mounted cell's center when the pointer is
  /// off every cell (above/below the viewport, between gaps).
  int? _targetIndex(Offset global) {
    if (widget.reorderableCount <= 0) return null;
    int? containing;
    var nearestIndex = -1;
    var nearestDistance = double.infinity;
    for (final index in _mountedIndexes) {
      final rect = _cellRect(index);
      if (rect == null) continue;
      if (rect.contains(global)) {
        containing ??= index;
        continue;
      }
      final distance = (rect.center - global).distanceSquared;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = index;
      }
    }
    final resolved = containing ?? (nearestIndex >= 0 ? nearestIndex : null);
    if (resolved == null) return null;
    return resolved.clamp(0, widget.reorderableCount - 1);
  }

  void _startDrag(int index) {
    if (!_effectiveDragEnabled || _draggingIndex != null) return;
    setState(() {
      _draggingIndex = index;
      _pointerCancelled = false;
    });
  }

  /// The pointer that pressed this cell (pointer-down). Recorded per cell so
  /// the drag that this cell starts later knows which finger owns it.
  void _recordPointerDown(int index, int pointer) {
    _downPointerByCell[index] = pointer;
  }

  /// A cell's Listener saw a pointer cancelled. Matched to the pointer that
  /// pressed this cell, so an unrelated second finger lifting or being
  /// cancelled elsewhere never aborts the live drag.
  void _markPointerCancelled(int index, int pointer) {
    if (_downPointerByCell[index] != pointer) return;
    if (_draggingIndex == index) _pointerCancelled = true;
  }

  void _updateDrag(int index, DragUpdateDetails details) {
    if (_draggingIndex != index) return;
    _lastPointer = details.globalPosition;
    if (widget.scrollController == null || widget.viewportKey == null) return;
    final viewport =
        widget.viewportKey!.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null || !viewport.attached || !viewport.hasSize) return;
    final top = viewport.localToGlobal(Offset.zero).dy;
    final bottom = top + viewport.size.height;
    final y = details.globalPosition.dy;
    final up = y < top + widget.edgeAutoscrollInset;
    final down = y > bottom - widget.edgeAutoscrollInset;
    if (up == _autoscrollingUp && down == _autoscrollingDown) return;
    _autoscrollingUp = up;
    _autoscrollingDown = down;
    _syncAutoscrollTimer();
  }

  void _syncAutoscrollTimer() {
    final wantsScroll = _autoscrollingUp || _autoscrollingDown;
    if (!wantsScroll) {
      _autoscrollTimer?.cancel();
      _autoscrollTimer = null;
      return;
    }
    _autoscrollTimer ??= Timer.periodic(
      _autoscrollInterval,
      (_) => _autoscrollStep(),
    );
  }

  void _autoscrollStep() {
    final controller = widget.scrollController;
    if (controller == null ||
        !controller.hasClients ||
        _draggingIndex == null) {
      _autoscrollTimer?.cancel();
      _autoscrollTimer = null;
      return;
    }
    final position = controller.position;
    final step = _cellExtent > 0 ? _cellExtent + widget.spacing : 80.0;
    final delta = _autoscrollingUp ? -step : (_autoscrollingDown ? step : 0.0);
    if (delta == 0) return;
    final target = (controller.offset + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target != controller.offset) controller.jumpTo(target);
  }

  /// Ends any drag without writing anything: the pointer was cancelled, the
  /// affordance disappeared, or the component is going away. The autoscroll
  /// and feedback stop with it; nothing persists.
  void _abortDrag() {
    _autoscrollTimer?.cancel();
    _autoscrollTimer = null;
    _autoscrollingUp = false;
    _autoscrollingDown = false;
    _lastPointer = null;
    _pointerCancelled = false;
    if (_draggingIndex != null && mounted) {
      setState(() => _draggingIndex = null);
    } else {
      _draggingIndex = null;
    }
  }

  /// The single committing path: the user lifted the pointer over a cell.
  Future<void> _dropDrag() async {
    final oldIndex = _draggingIndex;
    final pointer = _lastPointer;
    _abortDrag();
    if (oldIndex == null || pointer == null) return;
    final target = _targetIndex(pointer);
    if (target == null || target == oldIndex) return;
    await widget.onReorder(oldIndex, target);
  }

  Widget _dragFeedback(BuildContext context, int index) {
    final border = BorderRadius.circular(12);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: border,
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: border,
        child: ColoredBox(
          color: context.colors.card,
          child: widget.cellBuilder(context, index),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.crossAxisExtent;
      final extent =
          (width - widget.spacing * (widget.crossAxisCount - 1)) /
          widget.crossAxisCount;
      _cellExtent = extent;
      return SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: widget.crossAxisCount,
          mainAxisSpacing: widget.spacing,
          crossAxisSpacing: widget.spacing,
        ),
        itemCount: widget.itemCount,
        itemBuilder: (context, index) {
          final content = widget.cellBuilder(context, index);
          final key = _cellKey(index);
          if (!_effectiveDragEnabled || index >= widget.reorderableCount) {
            return SizedBox(key: key, width: extent, child: content);
          }
          return _StickerDragKeepAlive(
            keepAlive: _draggingIndex == index,
            child: SizedBox(
              key: key,
              width: extent,
              child: Listener(
                // The cell's own Listener still receives the pointer's
                // cancel/up events for the drag it started (the recognizer
                // routes by the stored hit-test result), so a native pointer
                // cancellation is seen here before [onDragEnd] runs. This grid
                // has no DragTargets, so `wasAccepted` is always false and
                // cannot tell a real drop from a cancelled drag — this flag
                // can.
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) =>
                    _recordPointerDown(index, event.pointer),
                onPointerCancel: (event) =>
                    _markPointerCancelled(index, event.pointer),
                child: LongPressDraggable<int>(
                  data: index,
                  maxSimultaneousDrags: 1,
                  dragAnchorStrategy: pointerDragAnchorStrategy,
                  onDragStarted: () => _startDrag(index),
                  onDragUpdate: (details) => _updateDrag(index, details),
                  onDragEnd: (_) => unawaited(_endDrag()),
                  feedback: SizedBox(
                    width: extent,
                    height: extent,
                    child: _dragFeedback(context, index),
                  ),
                  childWhenDragging: IgnorePointer(
                    child: Opacity(opacity: 0.0, child: content),
                  ),
                  child: content,
                ),
              ),
            ),
          );
        },
      );
    },
  );

  /// Routes the recognizer's single end callback. A native pointer cancel
  /// (seen by the cell's Listener before this runs) aborts; otherwise the
  /// pointer was lifted over a cell and the drop commits. `wasAccepted` is
  /// not used: this grid has no DragTargets, so it is always false.
  Future<void> _endDrag() {
    if (_pointerCancelled || _draggingIndex == null) {
      _abortDrag();
      return Future<void>.value();
    }
    return _dropDrag();
  }
}

/// Flutter only reports a Draggable's end while its source State is mounted.
/// Retain just the active source cell while autoscrolling past the lazy cache.
class _StickerDragKeepAlive extends StatefulWidget {
  const _StickerDragKeepAlive({required this.keepAlive, required this.child});
  final bool keepAlive;
  final Widget child;

  @override
  State<_StickerDragKeepAlive> createState() => _StickerDragKeepAliveState();
}

class _StickerDragKeepAliveState extends State<_StickerDragKeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.keepAlive;

  @override
  void didUpdateWidget(_StickerDragKeepAlive oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keepAlive != widget.keepAlive) updateKeepAlive();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
