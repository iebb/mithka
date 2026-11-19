import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

/// Gold penguin silhouette shown next to a Telegram Premium user's name.
class VipBadge extends StatelessWidget {
  const VipBadge({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppStringKeys.vipBadgeLabel.l10n(context),
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: const CustomPaint(painter: _GoldPenguinPainter()),
      ),
    );
  }
}

/// A side-on penguin drawn on a 24 × 24 grid.
class _GoldPenguinPainter extends CustomPainter {
  const _GoldPenguinPainter();

  static const _gradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF2BC2E), Color(0xFFC98204)],
  );

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24;
    canvas.save();
    canvas.translate(
      (size.width - 24 * scale) / 2,
      (size.height - 24 * scale) / 2,
    );
    canvas.scale(scale);
    final path = Path()
      ..moveTo(12.6, 2.2)
      ..cubicTo(14.1, 2.2, 15.2, 3.2, 15.6, 4.7)
      // Beak.
      ..lineTo(18.7, 5.9)
      ..lineTo(15.5, 7.0)
      // Throat, chest and belly.
      ..cubicTo(15.3, 7.5, 15.2, 8.0, 15.3, 8.6)
      ..cubicTo(17.2, 10.6, 18.2, 14.4, 17.6, 17.6)
      ..cubicTo(17.3, 19.0, 16.7, 20.0, 15.9, 20.7)
      // Foot.
      ..lineTo(17.9, 21.2)
      ..cubicTo(18.4, 21.4, 18.3, 22.0, 17.8, 22.0)
      // Tail.
      ..lineTo(10.0, 22.0)
      ..lineTo(6.4, 22.7)
      ..lineTo(8.1, 20.7)
      // Back, then the flipper hanging behind it.
      ..cubicTo(7.1, 19.4, 6.8, 17.9, 6.8, 16.3)
      ..lineTo(4.4, 18.6)
      ..cubicTo(4.8, 14.8, 6.2, 11.6, 8.9, 9.5)
      // Nape and crown.
      ..cubicTo(9.3, 8.6, 9.5, 7.6, 9.6, 6.2)
      ..cubicTo(9.7, 3.8, 10.9, 2.2, 12.6, 2.2)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..isAntiAlias = true
        ..shader = _gradient.createShader(
          const Rect.fromLTWH(0, 2.2, 24, 20.5),
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GoldPenguinPainter oldDelegate) => false;
}
