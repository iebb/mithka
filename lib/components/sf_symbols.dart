//
//  sf_symbols.dart
//
//  The Swift app uses SF Symbols (`Image(systemName:)`). SF Symbols are an
//  Apple-proprietary font that can't ship on Android, so we map each symbol used
//  across the app to its closest Cupertino/Material equivalent. This keeps the
//  iconography consistent on both platforms while staying call-site-readable:
//
//      Icon(sfIcon('chevron.left'))
//

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

const Map<String, IconData> _map = {
  // Navigation / chrome
  'chevron.left': CupertinoIcons.back,
  'chevron.right': CupertinoIcons.right_chevron,
  'chevron.down': CupertinoIcons.chevron_down,
  'xmark': CupertinoIcons.xmark,
  'clock': CupertinoIcons.clock,
  'timer': CupertinoIcons.timer,
  'ellipsis': CupertinoIcons.ellipsis,
  'plus': CupertinoIcons.plus,
  'plus.circle': CupertinoIcons.plus_circle,
  'magnifyingglass': CupertinoIcons.search,
  'line.3.horizontal': Icons.menu,
  'arrow.left': Icons.arrow_back,
  'arrow.up': CupertinoIcons.arrow_up,

  // Tabs
  'message.fill': CupertinoIcons.chat_bubble_2_fill,
  'message': CupertinoIcons.chat_bubble_2,
  'person.2.fill': CupertinoIcons.person_2_fill,
  'person.2': CupertinoIcons.person_2,
  'circle.dashed': CupertinoIcons.smallcircle_circle,
  'person.crop.circle': CupertinoIcons.person_crop_circle,
  'person.crop.circle.fill': CupertinoIcons.person_crop_circle_fill,
  'square.and.pencil': CupertinoIcons.square_pencil,
  'pencil': CupertinoIcons.pencil,
  'square.grid.2x2': CupertinoIcons.square_grid_2x2,

  // Appearance / settings
  'circle.lefthalf.filled': Icons.contrast,
  'sun.max': Icons.wb_sunny_outlined,
  'sun.max.fill': Icons.light_mode,
  'moon': Icons.nightlight_outlined,
  'moon.fill': Icons.dark_mode,
  'rectangle.split.3x1.fill': Icons.view_week,
  'sparkles': Icons.auto_awesome_outlined,
  'gearshape.fill': CupertinoIcons.gear_solid,
  'gearshape': CupertinoIcons.gear,
  'bell.fill': CupertinoIcons.bell_fill,
  'lock.fill': CupertinoIcons.lock_fill,
  'nosign': Icons.block,
  'lock.shield.fill': CupertinoIcons.lock_shield_fill,
  'iphone': CupertinoIcons.device_phone_portrait,
  'globe': CupertinoIcons.globe,
  'questionmark.circle': CupertinoIcons.question_circle,
  'info.circle': CupertinoIcons.info_circle,
  'trash': CupertinoIcons.trash,
  'trash.fill': CupertinoIcons.trash_fill,
  'star': CupertinoIcons.star,
  'star.fill': CupertinoIcons.star_fill,
  'folder': CupertinoIcons.folder,
  'folder.fill': CupertinoIcons.folder_fill,
  'qrcode': CupertinoIcons.qrcode,
  'qrcode.viewfinder': CupertinoIcons.qrcode_viewfinder,
  'antenna.radiowaves.left.and.right': CupertinoIcons.dot_radiowaves_left_right,
  'square.and.arrow.up': CupertinoIcons.share,

  // Conversation / input
  'paperplane.fill': CupertinoIcons.paperplane_fill,
  'mic.fill': CupertinoIcons.mic_fill,
  'face.smiling': CupertinoIcons.smiley,
  'plus.circle.fill': CupertinoIcons.plus_circle_fill,
  'photo': CupertinoIcons.photo,
  'photo.fill': CupertinoIcons.photo_fill,
  'camera.fill': CupertinoIcons.camera_fill,
  'camera.rotate': CupertinoIcons.switch_camera_solid,
  'phone.fill': CupertinoIcons.phone_fill,
  'phone.down.fill': CupertinoIcons.phone_down_fill,
  'video.fill': CupertinoIcons.video_camera_solid,
  'doc.fill': CupertinoIcons.doc_fill,
  'doc': CupertinoIcons.doc,
  'location.fill': CupertinoIcons.location_fill,
  'location': CupertinoIcons.location,
  'arrowshape.turn.up.left': CupertinoIcons.reply,
  'arrowshape.turn.up.left.fill': CupertinoIcons.reply,
  'speaker.wave.2.fill': CupertinoIcons.speaker_2_fill,
  'play.fill': CupertinoIcons.play_fill,
  'pause.fill': CupertinoIcons.pause_fill,
  'checkmark': CupertinoIcons.checkmark_alt,
  'link': CupertinoIcons.link,
  'mappin.and.ellipse': CupertinoIcons.placemark,
  'music.note': CupertinoIcons.music_note,
  'checklist': Icons.checklist,
  'circle': CupertinoIcons.circle,

  // Misc
  'person.badge.plus': CupertinoIcons.person_add,
  'person.2.square.stack': CupertinoIcons.rectangle_stack_person_crop,
  'square.grid.2x2.fill': CupertinoIcons.square_grid_2x2_fill,
  'arrow.right.square': CupertinoIcons.square_arrow_right,
  'bell.slash.fill': CupertinoIcons.bell_slash_fill,
  'pin.fill': CupertinoIcons.pin_fill,
  'archivebox.fill': CupertinoIcons.archivebox_fill,
  'circle.fill': CupertinoIcons.circle_fill,
};

/// Resolve an SF Symbol name to the closest Flutter icon. Unknown names fall
/// back to a neutral circle so a missing mapping is visible but harmless.
IconData sfIcon(String name) => _map[name] ?? CupertinoIcons.circle;
