import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// A compact video timeline without Material or Cupertino slider assets.
class MithkaVideoSlider extends StatefulWidget {
  const MithkaVideoSlider({
    super.key,
    required this.value,
    required this.trackHeight,
    required this.thumbRadius,
    required this.activeColor,
    required this.inactiveColor,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.bufferedValue,
    this.bufferedColor,
  });

  final double value;
  final double? bufferedValue;
  final double trackHeight;
  final double thumbRadius;
  final Color activeColor;
  final Color inactiveColor;
  final Color? bufferedColor;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  State<MithkaVideoSlider> createState() => _MithkaVideoSliderState();
}

class _MithkaVideoSliderState extends State<MithkaVideoSlider> {
  double? _interactionValue;

  double _valueAt(double dx, double width) {
    final usableWidth = math.max(1.0, width - widget.thumbRadius * 2);
    return ((dx - widget.thumbRadius) / usableWidth).clamp(0.0, 1.0);
  }

  void _begin(double dx, double width) {
    final value = _valueAt(dx, width);
    setState(() => _interactionValue = value);
    widget.onChangeStart?.call(value);
    widget.onChanged?.call(value);
  }

  void _update(double dx, double width) {
    final value = _valueAt(dx, width);
    setState(() => _interactionValue = value);
    widget.onChanged?.call(value);
  }

  void _end() {
    final value = _interactionValue ?? widget.value;
    widget.onChangeEnd?.call(value);
    setState(() => _interactionValue = null);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final enabled = widget.onChanged != null;
      final value = (_interactionValue ?? widget.value).clamp(0.0, 1.0);
      return Semantics(
        slider: true,
        enabled: enabled,
        value: '${(value * 100).round()}%',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: enabled
              ? (details) {
                  final next = _valueAt(
                    details.localPosition.dx,
                    constraints.maxWidth,
                  );
                  widget.onChangeStart?.call(next);
                  widget.onChanged?.call(next);
                  widget.onChangeEnd?.call(next);
                }
              : null,
          onHorizontalDragStart: enabled
              ? (details) =>
                    _begin(details.localPosition.dx, constraints.maxWidth)
              : null,
          onHorizontalDragUpdate: enabled
              ? (details) =>
                    _update(details.localPosition.dx, constraints.maxWidth)
              : null,
          onHorizontalDragEnd: enabled ? (_) => _end() : null,
          onHorizontalDragCancel: enabled ? _end : null,
          child: CustomPaint(
            painter: _MithkaVideoSliderPainter(
              value: value,
              bufferedValue: widget.bufferedValue,
              trackHeight: widget.trackHeight,
              thumbRadius: widget.thumbRadius,
              activeColor: widget.activeColor,
              inactiveColor: widget.inactiveColor,
              bufferedColor: widget.bufferedColor,
              enabled: enabled,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      );
    },
  );
}

class _MithkaVideoSliderPainter extends CustomPainter {
  const _MithkaVideoSliderPainter({
    required this.value,
    required this.bufferedValue,
    required this.trackHeight,
    required this.thumbRadius,
    required this.activeColor,
    required this.inactiveColor,
    required this.bufferedColor,
    required this.enabled,
  });

  final double value;
  final double? bufferedValue;
  final double trackHeight;
  final double thumbRadius;
  final Color activeColor;
  final Color inactiveColor;
  final Color? bufferedColor;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final left = thumbRadius;
    final right = math.max(left, size.width - thumbRadius);
    final centerY = size.height / 2;
    final thumbX = left + (right - left) * value;
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        left,
        centerY - trackHeight / 2,
        right,
        centerY + trackHeight / 2,
      ),
      Radius.circular(trackHeight / 2),
    );
    if (inactiveColor.a > 0) {
      canvas.drawRRect(trackRect, Paint()..color = inactiveColor);
    }
    final buffered = bufferedValue?.clamp(0.0, 1.0);
    if (buffered != null && buffered > 0 && bufferedColor != null) {
      _paintRange(
        canvas,
        trackRect,
        left,
        right,
        centerY,
        buffered,
        bufferedColor!,
      );
    }
    if (value > 0) {
      _paintRange(canvas, trackRect, left, right, centerY, value, activeColor);
    }
    canvas.drawCircle(
      Offset(thumbX, centerY),
      thumbRadius,
      Paint()
        ..color = enabled ? activeColor : activeColor.withValues(alpha: 0.7),
    );
  }

  void _paintRange(
    Canvas canvas,
    RRect clip,
    double left,
    double right,
    double centerY,
    double value,
    Color color,
  ) {
    canvas.save();
    canvas.clipRRect(clip);
    canvas.drawRect(
      Rect.fromLTRB(
        left,
        centerY - trackHeight / 2,
        left + (right - left) * value,
        centerY + trackHeight / 2,
      ),
      Paint()..color = color,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MithkaVideoSliderPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.bufferedValue != bufferedValue ||
      oldDelegate.trackHeight != trackHeight ||
      oldDelegate.thumbRadius != thumbRadius ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.inactiveColor != inactiveColor ||
      oldDelegate.bufferedColor != bufferedColor ||
      oldDelegate.enabled != enabled;
}
