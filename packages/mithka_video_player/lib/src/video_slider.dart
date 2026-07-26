import 'dart:math' as math;

import 'package:flutter/services.dart';
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
    this.semanticLabel,
    this.semanticValue,
    this.semanticIncreasedValue,
    this.semanticDecreasedValue,
    this.keyboardStep = 0.05,
    this.autofocus = false,
    this.focusNode,
  }) : assert(keyboardStep > 0 && keyboardStep <= 1);

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

  /// A localized description of what this timeline controls.
  final String? semanticLabel;

  /// A localized value announced instead of the default percentage.
  final String? semanticValue;

  /// The value announced after an accessibility increase action.
  final String? semanticIncreasedValue;

  /// The value announced after an accessibility decrease action.
  final String? semanticDecreasedValue;

  /// Fraction applied by arrow keys and accessibility adjustment actions.
  final double keyboardStep;

  /// Whether this slider should request keyboard focus when first built.
  final bool autofocus;

  /// Optional externally owned focus node.
  final FocusNode? focusNode;

  @override
  State<MithkaVideoSlider> createState() => _MithkaVideoSliderState();
}

class _MithkaVideoSliderState extends State<MithkaVideoSlider> {
  double? _interactionValue;
  double? _keyboardValue;
  bool _focused = false;
  bool _keyboardInteractionActive = false;

  @override
  void didUpdateWidget(covariant MithkaVideoSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    final keyboardValue = _keyboardValue;
    if (keyboardValue != null &&
        ((widget.value - keyboardValue).abs() < 0.0000001 ||
            widget.value != oldWidget.value ||
            widget.onChanged == null)) {
      _keyboardValue = null;
    }
  }

  double _valueAt(double dx, double width, TextDirection textDirection) {
    final usableWidth = math.max(1.0, width - widget.thumbRadius * 2);
    final visualValue = ((dx - widget.thumbRadius) / usableWidth).clamp(
      0.0,
      1.0,
    );
    return textDirection == TextDirection.rtl ? 1 - visualValue : visualValue;
  }

  void _begin(double dx, double width, TextDirection textDirection) {
    _finishKeyboardInteraction();
    final value = _valueAt(dx, width, textDirection);
    setState(() {
      _keyboardValue = null;
      _interactionValue = value;
    });
    widget.onChangeStart?.call(value);
    widget.onChanged?.call(value);
  }

  void _update(double dx, double width, TextDirection textDirection) {
    final value = _valueAt(dx, width, textDirection);
    setState(() => _interactionValue = value);
    widget.onChanged?.call(value);
  }

  void _end() {
    final value = _interactionValue;
    if (value == null) return;
    setState(() {
      _interactionValue = null;
      _keyboardValue = value;
    });
    widget.onChangeEnd?.call(value);
  }

  double get _normalizedValue {
    final value = _interactionValue ?? _keyboardValue ?? widget.value;
    return value.isFinite ? value.clamp(0.0, 1.0) : 0;
  }

  void _adjust(double delta, {bool completeInteraction = true}) {
    if (widget.onChanged == null) return;
    final current = _normalizedValue;
    final next = (current + delta).clamp(0.0, 1.0);
    if (next == current) return;
    if (completeInteraction) widget.onChangeStart?.call(current);
    setState(() => _keyboardValue = next);
    widget.onChanged?.call(next);
    if (completeInteraction) widget.onChangeEnd?.call(next);
  }

  void _beginKeyboardInteraction() {
    if (_keyboardInteractionActive) return;
    _keyboardInteractionActive = true;
    widget.onChangeStart?.call(_normalizedValue);
  }

  void _finishKeyboardInteraction() {
    if (!_keyboardInteractionActive) return;
    _keyboardInteractionActive = false;
    widget.onChangeEnd?.call(_normalizedValue);
  }

  KeyEventResult _handleKey(
    FocusNode node,
    KeyEvent event,
    TextDirection textDirection,
  ) {
    if (widget.onChanged == null) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final supportedKey =
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.home ||
        key == LogicalKeyboardKey.end;
    if (!supportedKey) return KeyEventResult.ignored;
    if (event is KeyUpEvent) {
      _finishKeyboardInteraction();
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    _beginKeyboardInteraction();
    final directionalStep = textDirection == TextDirection.rtl
        ? -widget.keyboardStep
        : widget.keyboardStep;
    if (key == LogicalKeyboardKey.arrowRight) {
      _adjust(directionalStep, completeInteraction: false);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _adjust(-directionalStep, completeInteraction: false);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _adjust(widget.keyboardStep, completeInteraction: false);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _adjust(-widget.keyboardStep, completeInteraction: false);
    } else if (key == LogicalKeyboardKey.home) {
      _setFromKeyboard(0, completeInteraction: false);
    } else if (key == LogicalKeyboardKey.end) {
      _setFromKeyboard(1, completeInteraction: false);
    }
    return KeyEventResult.handled;
  }

  void _setFromKeyboard(double value, {bool completeInteraction = true}) {
    if (widget.onChanged == null || value == _normalizedValue) return;
    final current = _normalizedValue;
    if (completeInteraction) widget.onChangeStart?.call(current);
    setState(() => _keyboardValue = value);
    widget.onChanged?.call(value);
    if (completeInteraction) widget.onChangeEnd?.call(value);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final enabled = widget.onChanged != null;
      final value = _normalizedValue;
      final textDirection =
          Directionality.maybeOf(context) ?? TextDirection.ltr;
      final canIncrease = enabled && value < 1;
      final canDecrease = enabled && value > 0;
      final increasedValue =
          widget.semanticIncreasedValue ??
          '${((value + widget.keyboardStep).clamp(0.0, 1.0) * 100).round()}%';
      final decreasedValue =
          widget.semanticDecreasedValue ??
          '${((value - widget.keyboardStep).clamp(0.0, 1.0) * 100).round()}%';
      return Semantics(
        slider: true,
        enabled: enabled,
        focusable: enabled,
        focused: _focused,
        label: widget.semanticLabel,
        value: widget.semanticValue ?? '${(value * 100).round()}%',
        increasedValue: canIncrease ? increasedValue : null,
        decreasedValue: canDecrease ? decreasedValue : null,
        onIncrease: canIncrease ? () => _adjust(widget.keyboardStep) : null,
        onDecrease: canDecrease ? () => _adjust(-widget.keyboardStep) : null,
        child: Focus(
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          canRequestFocus: enabled,
          includeSemantics: false,
          onFocusChange: (focused) {
            if (!focused) _finishKeyboardInteraction();
            if (_focused != focused && mounted) {
              setState(() => _focused = focused);
            }
          },
          onKeyEvent: (node, event) => _handleKey(node, event, textDirection),
          child: Builder(
            builder: (focusContext) => MouseRegion(
              cursor: enabled
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: enabled
                    ? (_) => Focus.of(focusContext).requestFocus()
                    : null,
                onTapUp: enabled
                    ? (details) {
                        final next = _valueAt(
                          details.localPosition.dx,
                          constraints.maxWidth,
                          textDirection,
                        );
                        setState(() => _keyboardValue = next);
                        widget.onChangeStart?.call(next);
                        widget.onChanged?.call(next);
                        widget.onChangeEnd?.call(next);
                      }
                    : null,
                onHorizontalDragStart: enabled
                    ? (details) {
                        Focus.of(focusContext).requestFocus();
                        _begin(
                          details.localPosition.dx,
                          constraints.maxWidth,
                          textDirection,
                        );
                      }
                    : null,
                onHorizontalDragUpdate: enabled
                    ? (details) => _update(
                        details.localPosition.dx,
                        constraints.maxWidth,
                        textDirection,
                      )
                    : null,
                onHorizontalDragEnd: enabled ? (_) => _end() : null,
                // Once a horizontal drag is accepted Flutter reports pointer
                // cancellation through onHorizontalDragEnd. Before that there
                // is no active slider interaction to clean up.
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
                    focused: _focused,
                    textDirection: textDirection,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
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
    required this.focused,
    required this.textDirection,
  });

  final double value;
  final double? bufferedValue;
  final double trackHeight;
  final double thumbRadius;
  final Color activeColor;
  final Color inactiveColor;
  final Color? bufferedColor;
  final bool enabled;
  final bool focused;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final left = thumbRadius;
    final right = math.max(left, size.width - thumbRadius);
    final centerY = size.height / 2;
    final thumbX = textDirection == TextDirection.ltr
        ? left + (right - left) * value
        : right - (right - left) * value;
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
        textDirection,
      );
    }
    if (value > 0) {
      _paintRange(
        canvas,
        trackRect,
        left,
        right,
        centerY,
        value,
        activeColor,
        textDirection,
      );
    }
    if (focused) {
      canvas.drawCircle(
        Offset(thumbX, centerY),
        thumbRadius + 4,
        Paint()
          ..color = activeColor.withValues(alpha: 0.26)
          ..style = PaintingStyle.fill,
      );
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
    TextDirection textDirection,
  ) {
    canvas.save();
    canvas.clipRRect(clip);
    final rangeWidth = (right - left) * value;
    canvas.drawRect(
      Rect.fromLTRB(
        textDirection == TextDirection.ltr ? left : right - rangeWidth,
        centerY - trackHeight / 2,
        textDirection == TextDirection.ltr ? left + rangeWidth : right,
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
      oldDelegate.enabled != enabled ||
      oldDelegate.focused != focused ||
      oldDelegate.textDirection != textDirection;
}
