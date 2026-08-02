import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

/// Paints immediate, touch-positioned feedback without taking part in the
/// gesture arena, so the wrapped control keeps its tap, long-press, and swipe
/// behavior.
class AppPressRipple extends StatefulWidget {
  const AppPressRipple({
    super.key,
    required this.child,
    this.color,
    this.borderRadius = BorderRadius.zero,
    this.cancelDistance = 12,
  }) : assert(cancelDistance >= 0);

  static const rippleLayerKey = ValueKey<String>('app-press-ripple-layer');

  final Widget child;
  final Color? color;
  final BorderRadiusGeometry borderRadius;
  final double cancelDistance;

  @override
  State<AppPressRipple> createState() => _AppPressRippleState();
}

class _AppPressRippleState extends State<AppPressRipple>
    with TickerProviderStateMixin {
  late final AnimationController _expansionController;
  late final AnimationController _opacityController;
  late final Listenable _animation;

  int? _pointer;
  Offset? _origin;
  Offset? _downPosition;
  bool _cancelled = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _expansionController = AnimationController(
      vsync: this,
      duration: AppMotion.deliberate,
    );
    _opacityController = AnimationController(
      vsync: this,
      duration: AppMotion.quick,
    );
    _animation = Listenable.merge([_expansionController, _opacityController]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _expansionController.duration = AppMotion.duration(
      context,
      AppMotion.deliberate,
    );
    _opacityController.duration = AppMotion.duration(context, AppMotion.quick);
  }

  @override
  void dispose() {
    _expansionController.dispose();
    _opacityController.dispose();
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _downPosition = event.localPosition;
    _cancelled = false;
    _generation++;
    setState(() => _origin = event.localPosition);

    _opacityController.stop();
    _opacityController.value = 1;
    if (AppMotion.isReduced(context)) {
      _expansionController.value = 1;
    } else {
      _expansionController.forward(from: 0);
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer || _cancelled) return;
    final downPosition = _downPosition;
    if (downPosition == null ||
        (event.localPosition - downPosition).distance <=
            widget.cancelDistance) {
      return;
    }
    _cancelled = true;
    _hideRipple();
  }

  void _handlePointerEnd(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _downPosition = null;
    if (!_cancelled) _hideRipple();
  }

  void _hideRipple() {
    if (!mounted) return;
    final generation = _generation;
    if (AppMotion.isReduced(context)) {
      _opacityController.value = 0;
      if (mounted && generation == _generation) {
        setState(() => _origin = null);
      }
      return;
    }
    _opacityController.reverse().whenCompleteOrCancel(() {
      if (!mounted || generation != _generation) return;
      setState(() => _origin = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final origin = _origin;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerEnd,
      onPointerCancel: _handlePointerEnd,
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (origin != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _animation,
                    builder: (context, _) => CustomPaint(
                      key: AppPressRipple.rippleLayerKey,
                      painter: _AppPressRipplePainter(
                        origin: origin,
                        color: widget.color ?? context.colors.textPrimary,
                        progress: AppMotion.standard.transform(
                          _expansionController.value,
                        ),
                        opacity: _opacityController.value,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AppPressRipplePainter extends CustomPainter {
  const _AppPressRipplePainter({
    required this.origin,
    required this.color,
    required this.progress,
    required this.opacity,
  });

  final Offset origin;
  final Color color;
  final double progress;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0 || size.isEmpty) return;

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = color.withValues(alpha: 0.025 * opacity),
    );

    final farthestX = math.max(origin.dx, size.width - origin.dx);
    final farthestY = math.max(origin.dy, size.height - origin.dy);
    final radius = math.sqrt(farthestX * farthestX + farthestY * farthestY);
    canvas.drawCircle(
      origin,
      radius * progress,
      Paint()..color = color.withValues(alpha: 0.10 * opacity),
    );
  }

  @override
  bool shouldRepaint(covariant _AppPressRipplePainter oldDelegate) =>
      oldDelegate.origin != origin ||
      oldDelegate.color != color ||
      oldDelegate.progress != progress ||
      oldDelegate.opacity != opacity;
}
