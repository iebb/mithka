import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/message_bubble_background.dart';

/// Paints either a normal color bubble or a center-sliced PNG bubble.
///
/// [MessageBubbleBackgroundSpec.centerSlice] protects all four decorated corner
/// quadrants. Flutter stretches only the middle rows and columns to fill the
/// final message size.
class StretchableMessageBubbleBackground extends StatelessWidget {
  const StretchableMessageBubbleBackground({
    super.key,
    required this.background,
    required this.fallbackColor,
    required this.fallbackBorderRadius,
    required this.fallbackPadding,
    required this.child,
    this.constraints = const BoxConstraints(),
    this.fallbackBorder,
    this.clipBehavior = Clip.none,
  });

  final MessageBubbleBackgroundSpec background;
  final Color fallbackColor;
  final BorderRadiusGeometry fallbackBorderRadius;
  final EdgeInsetsGeometry fallbackPadding;
  final BoxConstraints constraints;
  final BoxBorder? fallbackBorder;
  final Clip clipBehavior;
  final Widget child;

  BoxConstraints get _effectiveConstraints {
    if (!background.isDecorative) return constraints;
    final minimum = background.minimumSize;
    return constraints.copyWith(
      minWidth: math.min(
        constraints.maxWidth,
        math.max(constraints.minWidth, minimum.width),
      ),
      minHeight: math.min(
        constraints.maxHeight,
        math.max(constraints.minHeight, minimum.height),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final decorative = background.isDecorative;
    if (decorative) {
      final overflow = background.visualOverflow;
      final content = Container(
        constraints: _effectiveConstraints,
        padding: background.contentPadding,
        child: child,
      );
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -overflow.left,
            top: -overflow.top,
            right: -overflow.right,
            bottom: -overflow.bottom,
            child: DecoratedBox(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: background.image!,
                  centerSlice: background.centerSlice,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ),
          content,
        ],
      );
    }
    return Container(
      constraints: _effectiveConstraints,
      padding: fallbackPadding,
      clipBehavior: clipBehavior,
      decoration: BoxDecoration(
        color: fallbackColor,
        borderRadius: fallbackBorderRadius,
        border: fallbackBorder,
      ),
      child: child,
    );
  }
}
