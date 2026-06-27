//
//  sf_symbols.dart
//
//  The Swift app uses SF Symbols (`Image(systemName:)`). SF Symbols are an
//  Apple-proprietary font that can't ship on Android, so we map each symbol used
//  across the app to its closest Font Awesome/Material equivalent. This keeps the
//  iconography consistent on both platforms while staying call-site-readable:
//
//      Icon(sfIcon('chevron.left'))
//

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

const Map<String, Object> _map = {
  // Navigation / chrome
  'chevron.left': FontAwesomeIcons.chevronLeft,
  'chevron.right': FontAwesomeIcons.chevronRight,
  'chevron.up': FontAwesomeIcons.chevronUp,
  'chevron.down': FontAwesomeIcons.chevronDown,
  'xmark': FontAwesomeIcons.xmark,
  'clock': FontAwesomeIcons.clock,
  'timer': FontAwesomeIcons.stopwatch,
  'ellipsis': FontAwesomeIcons.ellipsis,
  'plus': FontAwesomeIcons.plus,
  'plus.circle': FontAwesomeIcons.circlePlus,
  'magnifyingglass': FontAwesomeIcons.magnifyingGlass,
  'line.3.horizontal': Icons.menu,
  'arrow.left': Icons.arrow_back,
  'arrow.up': FontAwesomeIcons.arrowUp,
  'arrow.down.to.line': Icons.vertical_align_bottom_rounded,
  'slash.circle': FontAwesomeIcons.ban,

  // Tabs
  'message.fill': FontAwesomeIcons.solidMessage,
  'message': FontAwesomeIcons.message,
  'number': Icons.tag_rounded,
  'number.circle.fill': Icons.tag_rounded,
  'person.2.fill': FontAwesomeIcons.users,
  'person.2': FontAwesomeIcons.users,
  'circle.dashed': FontAwesomeIcons.circleNotch,
  'person.crop.circle': FontAwesomeIcons.circleUser,
  'person.crop.circle.fill': FontAwesomeIcons.solidCircleUser,
  'square.and.pencil': FontAwesomeIcons.penToSquare,
  'pencil': FontAwesomeIcons.pen,
  'square.grid.2x2': FontAwesomeIcons.tableCells,

  // Appearance / settings
  'circle.lefthalf.filled': Icons.contrast,
  'sun.max': Icons.wb_sunny_outlined,
  'sun.max.fill': Icons.light_mode,
  'moon': Icons.nightlight_outlined,
  'moon.fill': Icons.dark_mode,
  'rectangle.split.3x1.fill': Icons.view_week,
  'rectangle.split.2x1': Icons.splitscreen,
  'pip.enter': Icons.picture_in_picture_alt,
  'sparkles': Icons.auto_awesome_outlined,
  'tshirt': Icons.checkroom_outlined,
  'gearshape.fill': FontAwesomeIcons.gear,
  'gearshape': FontAwesomeIcons.gear,
  'bell.fill': FontAwesomeIcons.solidBell,
  'lock.fill': FontAwesomeIcons.lock,
  'nosign': Icons.block,
  'lock.shield.fill': FontAwesomeIcons.shieldHalved,
  'iphone': FontAwesomeIcons.mobileScreenButton,
  'globe': FontAwesomeIcons.globe,
  'character.book.closed': Icons.translate,
  'questionmark.circle': FontAwesomeIcons.circleQuestion,
  'info.circle': FontAwesomeIcons.circleInfo,
  'trash': FontAwesomeIcons.trash,
  'trash.fill': FontAwesomeIcons.trash,
  'star': FontAwesomeIcons.star,
  'star.fill': FontAwesomeIcons.solidStar,
  'folder': FontAwesomeIcons.folder,
  'folder.fill': FontAwesomeIcons.solidFolder,
  'qrcode': FontAwesomeIcons.qrcode,
  'qrcode.viewfinder': FontAwesomeIcons.qrcode,
  'antenna.radiowaves.left.and.right': FontAwesomeIcons.towerBroadcast,
  'square.and.arrow.up': FontAwesomeIcons.shareFromSquare,

  // Conversation / input
  'paperplane.fill': FontAwesomeIcons.solidPaperPlane,
  'mic.fill': FontAwesomeIcons.microphone,
  'face.smiling': FontAwesomeIcons.solidFaceSmile,
  'plus.circle.fill': FontAwesomeIcons.circlePlus,
  'photo': FontAwesomeIcons.image,
  'photo.fill': FontAwesomeIcons.solidImage,
  'camera.fill': FontAwesomeIcons.camera,
  'camera.rotate': FontAwesomeIcons.rotate,
  'phone.fill': FontAwesomeIcons.phone,
  'phone.down.fill': FontAwesomeIcons.phoneSlash,
  'video.fill': FontAwesomeIcons.video,
  'doc.fill': FontAwesomeIcons.solidFile,
  'doc': FontAwesomeIcons.file,
  'location.fill': FontAwesomeIcons.locationDot,
  'location': FontAwesomeIcons.locationDot,
  'arrowshape.turn.up.left': FontAwesomeIcons.reply,
  'arrowshape.turn.up.left.fill': FontAwesomeIcons.reply,
  'arrowshape.turn.up.right': FontAwesomeIcons.share,
  'hand.thumbsup': FontAwesomeIcons.thumbsUp,
  'bubble.left': FontAwesomeIcons.comment,
  'quote.bubble': Icons.format_quote,
  'checkmark.circle': FontAwesomeIcons.circleCheck,
  'scissors': FontAwesomeIcons.scissors,
  'speaker.wave.2.fill': FontAwesomeIcons.volumeHigh,
  'play.fill': FontAwesomeIcons.play,
  'pause.fill': FontAwesomeIcons.pause,
  'checkmark': FontAwesomeIcons.check,
  'link': FontAwesomeIcons.link,
  'mappin.and.ellipse': FontAwesomeIcons.locationPin,
  'music.note': FontAwesomeIcons.music,
  'checklist': Icons.checklist,
  'circle': FontAwesomeIcons.circle,
  'eye': FontAwesomeIcons.eye,
  'eye.slash': FontAwesomeIcons.eyeSlash,

  // Misc
  'person.badge.plus': FontAwesomeIcons.userPlus,
  'person.2.square.stack': FontAwesomeIcons.objectGroup,
  'square.grid.2x2.fill': FontAwesomeIcons.grip,
  'arrow.right.square': FontAwesomeIcons.rightFromBracket,
  'bell.slash.fill': FontAwesomeIcons.bellSlash,
  'pin.fill': FontAwesomeIcons.thumbtack,
  'archivebox.fill': FontAwesomeIcons.boxArchive,
  'circle.fill': FontAwesomeIcons.solidCircle,
};

/// Resolve an SF Symbol name to the closest Flutter icon. Unknown names fall
/// back to a neutral circle so a missing mapping is visible but harmless.
IconData sfIcon(String name) {
  final icon = _map[name];
  return switch (icon) {
    FaIconData(:final data) => data,
    IconData() => icon,
    _ => FontAwesomeIcons.circle.data,
  };
}
