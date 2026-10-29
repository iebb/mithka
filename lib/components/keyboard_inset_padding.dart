import 'package:flutter/widgets.dart';

/// Keeps content above the keyboard while continuing its surface behind it.
///
/// Rounded, translucent keyboards reveal the inset area. Painting only that
/// area preserves the child's shape and layout, including fractional heights.
class KeyboardInsetPadding extends StatelessWidget {
  const KeyboardInsetPadding({
    super.key,
    required this.backgroundColor,
    required this.child,
    this.paintBehindKeyboard = true,
  });

  final Color backgroundColor;
  final Widget child;

  /// Centered dialogs keep their surrounding space transparent.
  final bool paintBehindKeyboard;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return CustomPaint(
      painter: _KeyboardInsetPainter(
        backgroundColor,
        paintBehindKeyboard ? inset : 0,
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: child,
      ),
    );
  }
}

class _KeyboardInsetPainter extends CustomPainter {
  const _KeyboardInsetPainter(this.color, this.inset);

  final Color color;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    if (inset <= 0) return;
    final height = inset < size.height ? inset : size.height;
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - height, size.width, height),
      Paint()..color = color,
    );
  }

  // The backdrop is visual only; transparent padding did not intercept taps.
  @override
  bool hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_KeyboardInsetPainter oldDelegate) =>
      color != oldDelegate.color || inset != oldDelegate.inset;
}
