import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Observes a rightward back swipe from anywhere inside [child].
///
/// A raw pointer listener is intentional: nested horizontal controls can keep
/// handling their own gestures while the page still observes the navigation
/// gesture.
class FullPageBackSwipe extends StatefulWidget {
  const FullPageBackSwipe({
    super.key,
    required this.enabled,
    required this.onBack,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onBack;
  final Widget child;

  @override
  State<FullPageBackSwipe> createState() => _FullPageBackSwipeState();
}

class _FullPageBackSwipeState extends State<FullPageBackSwipe>
    with SingleTickerProviderStateMixin {
  int? _pointer;
  double _dx = 0;
  double _dy = 0;
  VelocityTracker? _velocity;
  late final AnimationController _settleController;
  Animation<double>? _settleAnimation;
  double _visualOffset = 0;
  bool _horizontalIntent = false;

  @override
  void initState() {
    super.initState();
    _settleController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          final animation = _settleAnimation;
          if (animation != null) {
            setState(() => _visualOffset = animation.value);
          }
        });
  }

  void _start(PointerDownEvent event) {
    _reset();
    if (!widget.enabled) return;
    _settleController.stop();
    _settleAnimation = null;
    _pointer = event.pointer;
    _velocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _update(PointerMoveEvent event) {
    final tracker = _velocity;
    if (tracker == null || event.pointer != _pointer || !widget.enabled) return;
    _dx += event.delta.dx;
    _dy += event.delta.dy;
    tracker.addPosition(event.timeStamp, event.position);
    if (!_horizontalIntent && _dx > 7 && _dx.abs() > _dy.abs() * 1.35) {
      _horizontalIntent = true;
    }
    if (_horizontalIntent) {
      final width = MediaQuery.sizeOf(context).width;
      final raw = _dx.clamp(0.0, width * 1.08);
      // A small amount of resistance at the far edge keeps the content
      // attached to the finger without allowing an unbounded translation.
      setState(() {
        _visualOffset = raw <= width ? raw : width + (raw - width) * 0.18;
      });
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
        _dx > 72 &&
        (velocity > 520 || _dx > 118);
    final start = _visualOffset;
    _reset(keepVisualOffset: true);
    _animateTo(shouldPop ? MediaQuery.sizeOf(context).width : 0, from: start);
    // Start navigation on release so the route's reverse transition and this
    // settle animation overlap instead of adding two serial delays.
    if (shouldPop) widget.onBack();
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    final start = _visualOffset;
    _reset(keepVisualOffset: true);
    _animateTo(0, from: start);
  }

  void _animateTo(
    double target, {
    required double from,
    VoidCallback? onComplete,
  }) {
    final distance = (target - from).abs();
    final width = MediaQuery.sizeOf(context).width;
    _settleController.duration = Duration(
      milliseconds: (120 + 120 * (distance / width).clamp(0.0, 1.0)).round(),
    );
    _settleAnimation = Tween<double>(begin: from, end: target).animate(
      CurvedAnimation(parent: _settleController, curve: Curves.easeOutCubic),
    );
    _settleController.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      _settleAnimation = null;
      if (onComplete != null) onComplete();
    });
  }

  void _reset({bool keepVisualOffset = false}) {
    _pointer = null;
    _dx = 0;
    _dy = 0;
    _velocity = null;
    _horizontalIntent = false;
    if (!keepVisualOffset) _visualOffset = 0;
  }

  @override
  void dispose() {
    _settleController.dispose();
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
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: const Color(0xFF111318),
            child: Opacity(
              opacity:
                  (0.16 *
                          (1 -
                              _visualOffset / MediaQuery.sizeOf(context).width))
                      .clamp(0.0, 0.16),
              child: const ColoredBox(color: Color(0xFF000000)),
            ),
          ),
          Transform.translate(
            offset: Offset(_visualOffset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
