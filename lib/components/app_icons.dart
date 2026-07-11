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

class HeroAppIcons {
  const HeroAppIcons._();

  static const angleDown = AppIconData(HeroiconsOutline.chevronDown);
  static const arrowDown = AppIconData(HeroiconsOutline.arrowDown);
  static const arrowUp = AppIconData(HeroiconsOutline.arrowUp);
  static const arrowsRotate = AppIconData(HeroiconsOutline.arrowPath);
  static const arrowsUpDown = AppIconData(HeroiconsOutline.arrowsUpDown);
  static const at = AppIconData(HeroiconsOutline.atSymbol);
  static const ban = AppIconData(HeroiconsOutline.noSymbol);
  static const bars = AppIconData(HeroiconsOutline.bars3);
  static const bell = AppIconData(HeroiconsOutline.bell);
  static const bellSlash = AppIconData(HeroiconsOutline.bellSlash);
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
  static const clock = AppIconData(HeroiconsOutline.clock);
  static const code = AppIconData(HeroiconsOutline.codeBracket);
  static const cloudArrowDown = AppIconData(HeroiconsOutline.cloudArrowDown);
  static const comment = AppIconData(HeroiconsOutline.chatBubbleOvalLeft);
  static const comments = AppIconData(HeroiconsOutline.chatBubbleLeftRight);
  static const compactDisc = AppIconData(HeroiconsOutline.circleStack);
  static const crop = AppIconData(HeroiconsOutline.viewfinderCircle);
  static const download = AppIconData(HeroiconsOutline.arrowDownTray);
  static const droplet = AppIconData(HeroiconsOutline.beaker);
  static const ellipsis = AppIconData(HeroiconsOutline.ellipsisHorizontal);
  static const expand = AppIconData(HeroiconsOutline.arrowsPointingOut);
  static const eye = AppIconData(HeroiconsOutline.eye);
  static const eyeSlash = AppIconData(HeroiconsOutline.eyeSlash);
  static const file = AppIconData(HeroiconsOutline.document);
  static const filter = AppIconData(HeroiconsOutline.funnel);
  static const flash = AppIconData(HeroiconsOutline.bolt);
  static const folder = AppIconData(HeroiconsOutline.folder);
  static const font = AppIconData(HeroiconsOutline.documentText);
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
  static const quoteLeft = AppIconData(
    HeroiconsOutline.chatBubbleBottomCenterText,
  );
  static const reply = AppIconData(HeroiconsOutline.arrowUturnLeft);
  static const rightFromBracket = AppIconData(
    HeroiconsOutline.arrowRightStartOnRectangle,
  );
  static const rotate = AppIconData(HeroiconsOutline.arrowPathRoundedSquare);
  static const rotateLeft = AppIconData(HeroiconsOutline.arrowUturnLeft);
  static const rotateRight = AppIconData(HeroiconsOutline.arrowUturnRight);
  static const share = AppIconData(HeroiconsOutline.share);
  static const shieldHalved = AppIconData(HeroiconsOutline.shieldCheck);
  static const solidBell = AppIconData(HeroiconsSolid.bell);
  static const solidBookmark = AppIconData(HeroiconsSolid.bookmark);
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
