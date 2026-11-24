import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../platform/adaptive_platform.dart';

/// A route-owned animation driver for [FullPageBackSwipe].
///
/// Keeping the animation controller on the route allows Flutter's navigator to
/// reveal and repaint the actual previous route while the current page follows
/// the pointer.
abstract interface class FullPageBackSwipeDriver {
  bool get canStartFullPageBackSwipe;

  bool startFullPageBackSwipe();

  void updateFullPageBackSwipe(double progress);

  void cancelFullPageBackSwipe();

  void commitFullPageBackSwipe(VoidCallback? beforePop);
}

/// Marks a subtree that owns horizontal drags, such as a horizontally
/// scrollable strip: the full-page back swipe ignores pointers that land
/// inside it.
///
/// The back swipe is a raw pointer listener, so it never loses a gesture
/// arena to a nested control. Without this marker a rightward drag that
/// scrolls a strip back (the topic tabs above all) also starts the page's
/// back gesture and pops the chat. Layout and painting are untouched: the
/// marker only adds itself to the hit-test path.
class ExcludeFromBackSwipe extends SingleChildRenderObjectWidget {
  const ExcludeFromBackSwipe({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderExcludeFromBackSwipe();
}

class _RenderExcludeFromBackSwipe extends RenderProxyBox {
  // Opaque to the hit test even over a transparent gap between the strip's
  // items: the whole bar belongs to the strip, not only the painted tabs.
  @override
  bool hitTestSelf(Offset position) => true;
}

/// Observes a rightward back swipe from anywhere inside [child].
///
/// A raw pointer listener is intentional: nested horizontal controls can keep
/// handling their own gestures while the page still observes the navigation
/// gesture. Controls that must not share the drag — horizontally scrollable
/// surfaces and anything marked with [ExcludeFromBackSwipe] — are excluded at
/// pointer-down, because a raw listener cannot be cancelled by the arena.
class FullPageBackSwipe extends StatefulWidget {
  const FullPageBackSwipe({
    super.key,
    required this.enabled,
    required this.onBack,
    this.beforeRoutePop,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onBack;
  final VoidCallback? beforeRoutePop;
  final Widget child;

  @override
  State<FullPageBackSwipe> createState() => _FullPageBackSwipeState();
}

class _FullPageBackSwipeState extends State<FullPageBackSwipe> {
  // Keep a small horizontal drift from taking over the page. The back
  // gesture is available across the conversation surface, so the intent and
  // commit thresholds need to be high enough that ordinary diagonal/short
  // drags remain with the control under the finger.
  static const _intentDistance = 18.0;
  static const _commitDistance = 96.0;
  static const _longCommitDistance = 128.0;
  static const _fastCommitVelocity = 760.0;

  int? _pointer;
  double _dx = 0;
  double _dy = 0;
  VelocityTracker? _velocity;
  bool _horizontalIntent = false;
  FullPageBackSwipeDriver? _driver;
  bool _routeDriverDetected = false;

  @override
  void didUpdateWidget(FullPageBackSwipe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled && _pointer != null) {
      final driver = _driver;
      _reset();
      driver?.cancelFullPageBackSwipe();
    }
  }

  void _start(PointerDownEvent event) {
    if (_pointer != null) return;
    _reset();
    if (!widget.enabled) return;
    final desktopPointer =
        isDesktopTargetPlatform(Theme.of(context).platform) &&
        (event.kind == PointerDeviceKind.mouse ||
            event.kind == PointerDeviceKind.trackpad);
    if (desktopPointer) return;
    // The drag belongs to the control under the finger when that control
    // scrolls horizontally (the topic tab strip above all): a rightward swipe
    // there is "scroll back to earlier tabs", not "leave the chat".
    if (_ownsHorizontalDragAt(event.position, event.viewId)) return;
    _pointer = event.pointer;
    _velocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  /// True when the pointer landed on a horizontally scrollable surface or on a
  /// subtree marked [ExcludeFromBackSwipe].
  bool _ownsHorizontalDragAt(Offset position, int viewId) {
    final result = HitTestResult();
    RendererBinding.instance.hitTestInView(result, position, viewId);
    for (final entry in result.path) {
      final target = entry.target;
      if (target is _RenderExcludeFromBackSwipe) return true;
      if (target is RenderViewportBase && target.axis == Axis.horizontal) {
        return true;
      }
    }
    return false;
  }

  void _update(PointerMoveEvent event) {
    final tracker = _velocity;
    if (tracker == null || event.pointer != _pointer || !widget.enabled) return;
    _dx += event.delta.dx;
    _dy += event.delta.dy;
    tracker.addPosition(event.timeStamp, event.position);
    if (!_horizontalIntent &&
        _dx > _intentDistance &&
        _dx.abs() > _dy.abs() * 1.45) {
      _horizontalIntent = true;
      final route = ModalRoute.of(context);
      final driver = route is FullPageBackSwipeDriver
          ? route as FullPageBackSwipeDriver
          : null;
      _routeDriverDetected = driver != null;
      if (driver != null &&
          driver.canStartFullPageBackSwipe &&
          driver.startFullPageBackSwipe()) {
        _driver = driver;
      }
    }
    if (_horizontalIntent) {
      final width = MediaQuery.sizeOf(context).width;
      _driver?.updateFullPageBackSwipe((_dx / width).clamp(0.0, 1.0));
    }
  }

  void _end(PointerUpEvent event) {
    final tracker = _velocity;
    if (tracker == null || event.pointer != _pointer) return;
    final velocity = tracker.getVelocity().pixelsPerSecond.dx;
    final horizontal = _dx.abs() > _dy.abs() * 1.65;
    final shouldPop =
        widget.enabled &&
        horizontal &&
        _dx > _commitDistance &&
        (velocity > _fastCommitVelocity || _dx > _longCommitDistance);
    final driver = _driver;
    final routeDriverDetected = _routeDriverDetected;
    _reset();
    if (driver == null) {
      if (shouldPop && !routeDriverDetected) widget.onBack();
      return;
    }
    if (shouldPop) {
      driver.commitFullPageBackSwipe(widget.beforeRoutePop);
    } else {
      driver.cancelFullPageBackSwipe();
    }
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    final driver = _driver;
    _reset();
    driver?.cancelFullPageBackSwipe();
  }

  void _reset() {
    _pointer = null;
    _dx = 0;
    _dy = 0;
    _velocity = null;
    _horizontalIntent = false;
    _driver = null;
    _routeDriverDetected = false;
  }

  @override
  void dispose() {
    _driver?.cancelFullPageBackSwipe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _start,
      onPointerMove: _update,
      onPointerUp: _end,
      onPointerCancel: _cancel,
      child: widget.child,
    );
  }
}
