import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:heroicons_flutter/heroicons_flutter.dart';

class AppIconData {
  const AppIconData(this.data);

  final IconData data;
}

class AppIcon extends StatelessWidget {
  const AppIcon(this.icon, {super.key, this.size, this.color});

  final AppIconData icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Icon(icon.data, size: size, color: color);
  }
}

/// Owned ten-second seek glyph used by video transport controls.
///
/// The bundled Heroicons set has generic U-turn and fast-forward symbols but
/// no ten-second seek icon. Drawing the arc and numeral here keeps the control
/// visually precise without falling back to a platform icon set.
class AppSeekTenIcon extends StatelessWidget {
  const AppSeekTenIcon({
    super.key,
    required this.backwards,
    this.size = 32,
    this.color,
  });

  final bool backwards;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        color ?? IconTheme.of(context).color ?? const Color(0xFF000000);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _AppSeekTenIconPainter(
          backwards: backwards,
          color: resolvedColor,
        ),
      ),
    );
  }
}

class _AppSeekTenIconPainter extends CustomPainter {
  const _AppSeekTenIconPainter({required this.backwards, required this.color});

  final bool backwards;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final extent = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = extent * 0.37;
    final strokeWidth = (extent * 0.075).clamp(1.5, 3.4);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.save();
    if (backwards) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final arcBounds = Rect.fromCircle(center: center, radius: radius);
    const startAngle = math.pi * 0.22;
    const sweepAngle = math.pi * 1.48;
    canvas.drawArc(arcBounds, startAngle, sweepAngle, false, paint);

    const endAngle = startAngle + sweepAngle;
    final tip = Offset(
      center.dx + math.cos(endAngle) * radius,
      center.dy + math.sin(endAngle) * radius,
    );
    final tangent = Offset(-math.sin(endAngle), math.cos(endAngle));
    final perpendicular = Offset(-tangent.dy, tangent.dx);
    final arrowLength = extent * 0.17;
    final arrowWidth = extent * 0.095;
    final arrowBase = tip - tangent * arrowLength;
    canvas.drawPath(
      Path()
        ..moveTo(
          arrowBase.dx + perpendicular.dx * arrowWidth,
          arrowBase.dy + perpendicular.dy * arrowWidth,
        )
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(
          arrowBase.dx - perpendicular.dx * arrowWidth,
          arrowBase.dy - perpendicular.dy * arrowWidth,
        ),
      paint,
    );
    canvas.restore();

    final numeral = TextPainter(
      text: TextSpan(
        text: '10',
        style: TextStyle(
          color: color,
          fontSize: extent * 0.31,
          fontWeight: FontWeight.w400,
          height: 1,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    numeral.paint(
      canvas,
      Offset(
        center.dx - numeral.width / 2,
        center.dy - numeral.height / 2 + extent * 0.025,
      ),
    );
  }

  @override
  bool shouldRepaint(_AppSeekTenIconPainter oldDelegate) =>
      oldDelegate.backwards != backwards || oldDelegate.color != color;
}

/// Owned push-pin glyph for pinned-item status.
///
/// Heroicons does not include a push pin; using its bookmark glyph made pinned
/// chats look like Saved Messages. This compact outline keeps the visual
/// language of the owned icon set without falling back to platform icons.
class AppPinIcon extends StatelessWidget {
  const AppPinIcon({super.key, this.size = 16, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        color ?? IconTheme.of(context).color ?? const Color(0xFF000000);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _AppPinIconPainter(color: resolvedColor)),
    );
  }
}

class _AppPinIconPainter extends CustomPainter {
  const _AppPinIconPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = (size.shortestSide * 0.11).clamp(1.1, 1.7);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final body = Path()
      ..moveTo(size.width * 0.30, size.height * 0.14)
      ..lineTo(size.width * 0.70, size.height * 0.14)
      ..lineTo(size.width * 0.64, size.height * 0.42)
      ..lineTo(size.width * 0.78, size.height * 0.57)
      ..lineTo(size.width * 0.22, size.height * 0.57)
      ..lineTo(size.width * 0.36, size.height * 0.42)
      ..close();
    canvas.drawPath(body, paint);
    canvas.drawLine(
      Offset(size.width * 0.50, size.height * 0.57),
      Offset(size.width * 0.50, size.height * 0.90),
      paint,
    );
  }

  @override
  bool shouldRepaint(_AppPinIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class HeroAppIcons {
  const HeroAppIcons._();

  static const angleDown = AppIconData(HeroiconsOutline.chevronDown);
  static const arrowDown = AppIconData(HeroiconsOutline.arrowDown);
  static const arrowLeft = AppIconData(HeroiconsOutline.arrowLeft);
  static const arrowRight = AppIconData(HeroiconsOutline.arrowRight);
  static const arrowUp = AppIconData(HeroiconsOutline.arrowUp);
  static const arrowTopRight = AppIconData(
    HeroiconsOutline.arrowTopRightOnSquare,
  );
  static const arrowsRotate = AppIconData(HeroiconsOutline.arrowPath);
  static const arrowsRightLeft = AppIconData(HeroiconsOutline.arrowsRightLeft);
  static const arrowsUpDown = AppIconData(HeroiconsOutline.arrowsUpDown);
  static const at = AppIconData(HeroiconsOutline.atSymbol);
  static const ban = AppIconData(HeroiconsOutline.noSymbol);
  static const backspace = AppIconData(HeroiconsOutline.backspace);
  static const bars = AppIconData(HeroiconsOutline.bars3);
  static const alignLeft = AppIconData(HeroiconsOutline.bars3BottomLeft);
  static const alignCenter = AppIconData(HeroiconsOutline.bars3CenterLeft);
  static const alignRight = AppIconData(HeroiconsOutline.bars3BottomRight);
  static const alignTop = AppIconData(HeroiconsOutline.barsArrowUp);
  static const alignBottom = AppIconData(HeroiconsOutline.barsArrowDown);
  static const bell = AppIconData(HeroiconsOutline.bell);
  static const bellSlash = AppIconData(HeroiconsOutline.bellSlash);
  static const bookmark = AppIconData(HeroiconsOutline.bookmark);
  static const venue = AppIconData(HeroiconsOutline.buildingStorefront);
  static const camera = AppIconData(HeroiconsOutline.camera);
  static const check = AppIconData(HeroiconsOutline.check);
  static const checkDouble = AppIconData(HeroiconsOutline.check);
  static const chevronDown = AppIconData(HeroiconsOutline.chevronDown);
  static const chevronLeft = AppIconData(HeroiconsOutline.chevronLeft);
  static const chevronRight = AppIconData(HeroiconsOutline.chevronRight);
  static const chevronUp = AppIconData(HeroiconsOutline.chevronUp);
  static const circle = AppIconData(HeroiconsOutline.stopCircle);
  static const circleCheck = AppIconData(HeroiconsOutline.checkCircle);
  static const circleHalfStroke = AppIconData(HeroiconsOutline.moon);
  static const circleInfo = AppIconData(HeroiconsOutline.informationCircle);
  static const circleMinus = AppIconData(HeroiconsOutline.minusCircle);
  static const circleNotch = AppIconData(HeroiconsOutline.arrowPath);
  static const circlePlus = AppIconData(HeroiconsOutline.plusCircle);
  static const circleUser = AppIconData(HeroiconsOutline.userCircle);
  static const circleXmark = AppIconData(HeroiconsOutline.xCircle);
  static const clipboard = AppIconData(HeroiconsOutline.clipboard);
  static const clock = AppIconData(HeroiconsOutline.clock);
  static const code = AppIconData(HeroiconsOutline.codeBracket);
  static const cloud = AppIconData(HeroiconsOutline.cloud);
  static const cloudArrowDown = AppIconData(HeroiconsOutline.cloudArrowDown);
  static const comment = AppIconData(HeroiconsOutline.chatBubbleOvalLeft);
  static const comments = AppIconData(HeroiconsOutline.chatBubbleLeftRight);
  static const compactDisc = AppIconData(HeroiconsOutline.circleStack);
  static const crop = AppIconData(HeroiconsOutline.viewfinderCircle);
  static const cpuChip = AppIconData(HeroiconsOutline.cpuChip);

  /// Bot chats and the bot menu. Heroicons has no robot; the chip is what
  /// the app already uses for machine-driven features.
  static const bot = AppIconData(HeroiconsOutline.cpuChip);
  static const cube = AppIconData(HeroiconsOutline.cubeTransparent);
  static const download = AppIconData(HeroiconsOutline.arrowDownTray);
  static const droplet = AppIconData(HeroiconsOutline.beaker);
  static const ellipsis = AppIconData(HeroiconsOutline.ellipsisHorizontal);
  static const ellipsisVertical = AppIconData(
    HeroiconsOutline.ellipsisVertical,
  );
  static const expand = AppIconData(HeroiconsOutline.arrowsPointingOut);
  static const eye = AppIconData(HeroiconsOutline.eye);
  static const eyeSlash = AppIconData(HeroiconsOutline.eyeSlash);
  static const faceScan = AppIconData(HeroiconsOutline.viewfinderCircle);
  static const faceSmile = AppIconData(HeroiconsOutline.faceSmile);
  static const file = AppIconData(HeroiconsOutline.document);
  static const filter = AppIconData(HeroiconsOutline.funnel);
  static const fingerprint = AppIconData(HeroiconsOutline.fingerPrint);
  static const flash = AppIconData(HeroiconsOutline.bolt);
  static const folder = AppIconData(HeroiconsOutline.folder);
  static const font = AppIconData(HeroiconsOutline.documentText);

  /// Message, post, and story forwarding. Generic share/export actions keep
  /// using [share] so the two commands stay visually distinct.
  static const forward = AppIconData(HeroiconsOutline.arrowUturnRight);
  static const gear = AppIconData(HeroiconsOutline.cog6Tooth);
  static const gif = AppIconData(HeroiconsOutline.gif);
  static const globe = AppIconData(HeroiconsOutline.globeAlt);
  static const grip = AppIconData(HeroiconsOutline.squares2x2);
  static const hashtag = AppIconData(HeroiconsOutline.hashtag);
  static const heart = AppIconData(HeroiconsOutline.heart);
  static const idBadge = AppIconData(HeroiconsOutline.identification);
  static const image = AppIconData(HeroiconsOutline.photo);
  static const images = AppIconData(HeroiconsOutline.photo);
  static const inbox = AppIconData(HeroiconsOutline.inbox);
  static const language = AppIconData(HeroiconsOutline.language);
  static const key = AppIconData(HeroiconsOutline.key);
  static const link = AppIconData(HeroiconsOutline.link);
  static const listCheck = AppIconData(HeroiconsOutline.listBullet);
  static const locationDot = AppIconData(HeroiconsOutline.mapPin);
  static const locationPin = AppIconData(HeroiconsOutline.mapPin);
  static const lock = AppIconData(HeroiconsOutline.lockClosed);
  static const magnifyingGlass = AppIconData(HeroiconsOutline.magnifyingGlass);
  static const message = AppIconData(HeroiconsOutline.chatBubbleLeft);
  static const microphone = AppIconData(HeroiconsOutline.microphone);
  static const microphoneSlash = AppIconData(HeroiconsOutline.noSymbol);
  static const minus = AppIconData(HeroiconsOutline.minus);
  static const mobileScreenButton = AppIconData(
    HeroiconsOutline.devicePhoneMobile,
  );
  static const moon = AppIconData(HeroiconsOutline.moon);
  static const music = AppIconData(HeroiconsOutline.musicalNote);
  static const networkWired = AppIconData(HeroiconsOutline.serverStack);
  static const objectGroup = AppIconData(HeroiconsOutline.square3Stack3d);
  static const palette = AppIconData(HeroiconsOutline.swatch);
  static const paperPlane = AppIconData(HeroiconsOutline.paperAirplane);
  static const pause = AppIconData(HeroiconsOutline.pause);
  static const pen = AppIconData(HeroiconsOutline.pencil);
  static const penToSquare = AppIconData(HeroiconsOutline.pencilSquare);
  static const phone = AppIconData(HeroiconsOutline.phone);
  static const phoneSlash = AppIconData(HeroiconsOutline.phoneXMark);
  static const pictureInPicture = AppIconData(HeroiconsOutline.rectangleStack);
  static const play = AppIconData(HeroiconsOutline.play);
  static const plus = AppIconData(HeroiconsOutline.plus);
  static const qrcode = AppIconData(HeroiconsOutline.qrCode);
  static const questionCircle = AppIconData(
    HeroiconsOutline.questionMarkCircle,
  );
  static const quoteLeft = AppIconData(
    HeroiconsOutline.chatBubbleBottomCenterText,
  );
  static const reply = AppIconData(HeroiconsOutline.arrowUturnLeft);
  static const restore = AppIconData(HeroiconsOutline.arrowPathRoundedSquare);
  static const rightFromBracket = AppIconData(
    HeroiconsOutline.arrowRightStartOnRectangle,
  );
  static const rotate = AppIconData(HeroiconsOutline.arrowPathRoundedSquare);
  static const rotateLeft = AppIconData(HeroiconsOutline.arrowUturnLeft);
  static const rotateRight = AppIconData(HeroiconsOutline.arrowUturnRight);
  static const share = AppIconData(HeroiconsOutline.share);
  static const server = AppIconData(HeroiconsOutline.serverStack);
  static const shieldHalved = AppIconData(HeroiconsOutline.shieldCheck);
  static const solidBell = AppIconData(HeroiconsSolid.bell);
  static const solidCircle = AppIconData(HeroiconsSolid.stopCircle);
  static const solidCircleUser = AppIconData(HeroiconsSolid.userCircle);
  static const solidCircleXmark = AppIconData(HeroiconsSolid.xCircle);
  static const solidFaceSmile = AppIconData(HeroiconsSolid.faceSmile);
  static const solidFile = AppIconData(HeroiconsSolid.document);
  static const solidFileVideo = AppIconData(HeroiconsSolid.videoCamera);
  static const solidFolder = AppIconData(HeroiconsSolid.folder);
  static const solidImage = AppIconData(HeroiconsSolid.photo);
  static const solidMessage = AppIconData(HeroiconsSolid.chatBubbleLeft);
  static const solidMoon = AppIconData(HeroiconsSolid.moon);
  static const solidPaperPlane = AppIconData(HeroiconsSolid.paperAirplane);
  static const solidStar = AppIconData(HeroiconsSolid.star);
  static const solidSun = AppIconData(HeroiconsSolid.sun);
  static const square = AppIconData(HeroiconsOutline.stop);
  static const star = AppIconData(HeroiconsOutline.star);
  static const stopwatch = AppIconData(HeroiconsOutline.clock);
  static const sun = AppIconData(HeroiconsOutline.sun);
  static const tableCells = AppIconData(HeroiconsOutline.tableCells);
  static const tableColumns = AppIconData(HeroiconsOutline.rectangleGroup);
  static const tokenStack = AppIconData(HeroiconsOutline.square3Stack3d);
  static const thumbsUp = AppIconData(HeroiconsOutline.handThumbUp);
  static const thumbtack = AppIconData(HeroiconsOutline.bookmark);
  static const towerBroadcast = AppIconData(HeroiconsOutline.rss);
  static const trash = AppIconData(HeroiconsOutline.trash);
  static const triangleExclamation = AppIconData(
    HeroiconsOutline.exclamationTriangle,
  );
  static const upload = AppIconData(HeroiconsOutline.arrowUpTray);
  static const userPlus = AppIconData(HeroiconsOutline.userPlus);
  static const users = AppIconData(HeroiconsOutline.userGroup);
  static const video = AppIconData(HeroiconsOutline.videoCamera);
  static const volumeHigh = AppIconData(HeroiconsOutline.speakerWave);
  static const volumeXmark = AppIconData(HeroiconsOutline.speakerXMark);
  static const wandMagicSparkles = AppIconData(HeroiconsOutline.sparkles);
  static const xmark = AppIconData(HeroiconsOutline.xMark);
}
