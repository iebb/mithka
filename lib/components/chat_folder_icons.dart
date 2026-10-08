import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'app_icons.dart';

const chatFolderIconNames = [
  'Custom',
  'All',
  'Unread',
  'Unmuted',
  'Bots',
  'Channels',
  'Groups',
  'Private',
  'Setup',
  'Cat',
  'Crown',
  'Favorite',
  'Flower',
  'Game',
  'Home',
  'Love',
  'Mask',
  'Party',
  'Sport',
  'Study',
  'Trade',
  'Travel',
  'Work',
  'Airplane',
  'Book',
  'Light',
  'Like',
  'Money',
  'Note',
  'Palette',
];

/// TDLib folder icon names rendered with the app's owned icon vocabulary.
AppIconData chatFolderIcon(String name) => switch (name) {
  'All' => HeroAppIcons.inbox,
  'Unread' => HeroAppIcons.message,
  'Unmuted' => HeroAppIcons.bell,
  'Bots' => HeroAppIcons.code,
  'Channels' => HeroAppIcons.towerBroadcast,
  'Groups' => HeroAppIcons.users,
  'Private' => HeroAppIcons.circleUser,
  'Setup' => HeroAppIcons.gear,
  'Favorite' => HeroAppIcons.star,
  'Game' => HeroAppIcons.puzzle,
  'Home' => HeroAppIcons.home,
  'Love' => HeroAppIcons.heart,
  'Party' => HeroAppIcons.gift,
  'Sport' => HeroAppIcons.trophy,
  'Study' => HeroAppIcons.academicCap,
  'Trade' => HeroAppIcons.arrowsRightLeft,
  'Travel' => HeroAppIcons.globe,
  'Work' => HeroAppIcons.briefcase,
  'Airplane' => HeroAppIcons.paperPlane,
  'Book' => HeroAppIcons.book,
  'Light' => HeroAppIcons.lightbulb,
  'Like' => HeroAppIcons.thumbsUp,
  'Money' => HeroAppIcons.banknotes,
  'Note' => HeroAppIcons.music,
  'Palette' => HeroAppIcons.palette,
  _ => HeroAppIcons.folder,
};

/// Folder-specific glyphs missing from the shared font are drawn as owned paths.
class ChatFolderIcon extends StatelessWidget {
  const ChatFolderIcon(
    this.name, {
    super.key,
    required this.size,
    required this.color,
    this.badgeCount = 0,
    this.badgeAccent = false,
  });
  final String name;
  final double size;
  final Color color;

  /// Unread-chat count drawn as a pill on the glyph's top-right corner.
  /// Zero draws nothing. [badgeAccent] picks the accent fill; otherwise the
  /// badge is grey, matching Telegram's all-muted folder badges.
  final int badgeCount;
  final bool badgeAccent;

  @override
  Widget build(BuildContext context) {
    Widget icon;
    if (!const {'Cat', 'Crown', 'Flower', 'Mask'}.contains(name)) {
      icon = AppIcon(chatFolderIcon(name), size: size, color: color);
    } else {
      icon = CustomPaint(
        size: Size.square(size),
        painter: _FolderGlyphPainter(name, color),
      );
    }
    if (badgeCount <= 0) return icon;
    final c = context.colors;
    return _FolderBadgeIcon(
      icon: icon,
      glyphSize: size,
      label: badgeCount > 99 ? '99+' : '$badgeCount',
      color: badgeAccent ? AppTheme.brand : c.textTertiary,
      textColor: c.badgeText,
    );
  }
}

/// The folder glyph with its unread badge pinned to the glyph's top-right.
class _FolderBadgeIcon extends StatelessWidget {
  const _FolderBadgeIcon({
    required this.icon,
    required this.glyphSize,
    required this.label,
    required this.color,
    required this.textColor,
  });

  final Widget icon;
  final double glyphSize;
  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final badgeHeight = math.max(13.0, glyphSize * 0.58);
    final overhang = badgeHeight * 0.42;
    return SizedBox(
      width: glyphSize + overhang,
      height: glyphSize + overhang,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(left: 0, top: 0, child: icon),
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              constraints: BoxConstraints(
                minWidth: badgeHeight,
                minHeight: badgeHeight,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: label.length > 1 ? 4 : 0,
              ),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(badgeHeight / 2),
              ),
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: (badgeHeight * 0.62).clamp(9.0, 11.0),
                  fontWeight: FontWeight.w600,
                  color: textColor,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderGlyphPainter extends CustomPainter {
  const _FolderGlyphPainter(this.name, this.color);
  final String name;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (name) {
      case 'Cat':
        canvas.drawPath(
          Path()
            ..moveTo(4, 10)
            ..lineTo(4, 3)
            ..lineTo(9, 7)
            ..quadraticBezierTo(12, 6, 15, 7)
            ..lineTo(20, 3)
            ..lineTo(20, 10)
            ..cubicTo(24, 21, 0, 21, 4, 10)
            ..close(),
          stroke,
        );
        final fill = Paint()..color = color;
        canvas.drawCircle(const Offset(8, 12), 0.9, fill);
        canvas.drawCircle(const Offset(16, 12), 0.9, fill);
        canvas.drawPath(
          Path()
            ..moveTo(11, 14)
            ..lineTo(13, 14)
            ..lineTo(12, 15)
            ..close(),
          fill,
        );
        canvas.drawPath(
          Path()
            ..moveTo(12, 15)
            ..quadraticBezierTo(10.5, 17, 9, 15.5)
            ..moveTo(12, 15)
            ..quadraticBezierTo(13.5, 17, 15, 15.5)
            ..moveTo(6, 14)
            ..lineTo(1, 13)
            ..moveTo(6, 16)
            ..lineTo(1, 17)
            ..moveTo(18, 14)
            ..lineTo(23, 13)
            ..moveTo(18, 16)
            ..lineTo(23, 17),
          stroke,
        );
      case 'Crown':
        canvas.drawPath(
          Path()
            ..moveTo(4, 17)
            ..lineTo(2, 6)
            ..lineTo(8, 10)
            ..lineTo(12, 3)
            ..lineTo(16, 10)
            ..lineTo(22, 6)
            ..lineTo(20, 17)
            ..close()
            ..moveTo(5, 21)
            ..lineTo(19, 21),
          stroke,
        );
      case 'Flower':
        for (var i = 0; i < 6; i++) {
          final angle = i * math.pi / 3;
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(
                12 + 6 * math.cos(angle),
                12 + 6 * math.sin(angle),
              ),
              width: 6,
              height: 6,
            ),
            stroke,
          );
        }
        canvas.drawCircle(const Offset(12, 12), 3, stroke);
      case 'Mask':
        canvas.drawPath(
          Path()
            ..moveTo(2, 7)
            ..quadraticBezierTo(7, 4, 12, 8)
            ..quadraticBezierTo(17, 4, 22, 7)
            ..lineTo(21, 15)
            ..quadraticBezierTo(17, 20, 12, 14)
            ..quadraticBezierTo(7, 20, 3, 15)
            ..close(),
          stroke,
        );
        canvas.drawOval(const Rect.fromLTWH(5, 9, 4, 3), stroke);
        canvas.drawOval(const Rect.fromLTWH(15, 9, 4, 3), stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FolderGlyphPainter oldDelegate) =>
      name != oldDelegate.name || color != oldDelegate.color;
}
