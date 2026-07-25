import 'dart:io';

import 'package:flutter/widgets.dart';

import 'custom_message_bubble_background.dart';

/// Selectable chat-message bubble backgrounds.
///
/// Decorative presets are painted as center-sliced PNGs. The protected edge
/// bands keep each preset's corners and ornaments unchanged while the clear
/// middle rows and columns stretch with the message.
enum MessageBubbleBackground {
  standard,
  midnightAurora,
  solarPorcelain,
  berryOrbit,
  arcticBlueprint,
  emberArcade,
  lilacConstellation,
  forestFamiliar,
  inkWanderer,
  pixelCadet,
  cosmicMechanic,
  pastryPal,
  noirDetective,
  custom;

  static MessageBubbleBackground fromStorage(String? value) => switch (value) {
    // Migrate both screenshot-derived presets without retaining their assets.
    'moonlitViolet' || 'purpleFolded' => MessageBubbleBackground.midnightAurora,
    'creamCharms' => MessageBubbleBackground.solarPorcelain,
    _ => MessageBubbleBackground.values.firstWhere(
      (style) => style.name == value,
      orElse: () => MessageBubbleBackground.standard,
    ),
  };
}

/// Everything the renderer needs for either a bundled or user-provided PNG.
///
/// A nullable [image] represents the standard color bubble. Decorative images
/// always expose a one-logical-pixel [centerSlice].
@immutable
class MessageBubbleBackgroundSpec {
  const MessageBubbleBackgroundSpec({
    required this.selection,
    required this.image,
    required this.centerSlice,
    required this.minimumSize,
    required this.contentPadding,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  factory MessageBubbleBackgroundSpec.resolve(
    MessageBubbleBackground selection, {
    CustomMessageBubbleBackground? custom,
  }) => switch (selection) {
    MessageBubbleBackground.standard => standard,
    MessageBubbleBackground.midnightAurora => midnightAurora,
    MessageBubbleBackground.solarPorcelain => solarPorcelain,
    MessageBubbleBackground.berryOrbit => berryOrbit,
    MessageBubbleBackground.arcticBlueprint => arcticBlueprint,
    MessageBubbleBackground.emberArcade => emberArcade,
    MessageBubbleBackground.lilacConstellation => lilacConstellation,
    MessageBubbleBackground.forestFamiliar => forestFamiliar,
    MessageBubbleBackground.inkWanderer => inkWanderer,
    MessageBubbleBackground.pixelCadet => pixelCadet,
    MessageBubbleBackground.cosmicMechanic => cosmicMechanic,
    MessageBubbleBackground.pastryPal => pastryPal,
    MessageBubbleBackground.noirDetective => noirDetective,
    MessageBubbleBackground.custom when custom != null =>
      MessageBubbleBackgroundSpec(
        selection: MessageBubbleBackground.custom,
        image: FileImage(File(custom.filePath)),
        centerSlice: custom.centerSlice,
        minimumSize: custom.minimumSize,
        contentPadding: custom.contentPadding,
        backgroundColor: custom.backgroundColor,
        foregroundColor: custom.foregroundColor,
      ),
    MessageBubbleBackground.custom => standard,
  };

  static const standard = MessageBubbleBackgroundSpec(
    selection: MessageBubbleBackground.standard,
    image: null,
    centerSlice: null,
    minimumSize: Size.zero,
    contentPadding: EdgeInsets.zero,
    backgroundColor: null,
    foregroundColor: null,
  );

  static const midnightAurora = MessageBubbleBackgroundSpec(
    selection: MessageBubbleBackground.midnightAurora,
    image: AssetImage('assets/message_bubbles/midnight-aurora.png'),
    centerSlice: Rect.fromLTWH(24, 18, 1, 1),
    minimumSize: Size(49, 37),
    contentPadding: EdgeInsets.fromLTRB(14, 10, 14, 10),
    backgroundColor: Color(0xFF121046),
    foregroundColor: Color(0xFFF4F1FF),
  );

  static const solarPorcelain = MessageBubbleBackgroundSpec(
    selection: MessageBubbleBackground.solarPorcelain,
    image: AssetImage('assets/message_bubbles/solar-porcelain.png'),
    centerSlice: Rect.fromLTWH(24, 18, 1, 1),
    minimumSize: Size(49, 37),
    contentPadding: EdgeInsets.fromLTRB(14, 10, 14, 10),
    backgroundColor: Color(0xFFFFF8EC),
    foregroundColor: Color(0xFF1D3B63),
  );

  static const berryOrbit = MessageBubbleBackgroundSpec(
    selection: MessageBubbleBackground.berryOrbit,
    image: AssetImage('assets/message_bubbles/berry-orbit.png'),
    centerSlice: Rect.fromLTWH(24, 18, 1, 1),
    minimumSize: Size(49, 37),
    contentPadding: EdgeInsets.fromLTRB(14, 10, 14, 10),
    backgroundColor: Color(0xFFF9D7DA),
    foregroundColor: Color(0xFF67133F),
  );

  static const arcticBlueprint = MessageBubbleBackgroundSpec(
    selection: MessageBubbleBackground.arcticBlueprint,
    image: AssetImage('assets/message_bubbles/arctic-blueprint.png'),
    centerSlice: Rect.fromLTWH(24, 18, 1, 1),
    minimumSize: Size(49, 37),
    contentPadding: EdgeInsets.fromLTRB(14, 10, 14, 10),
    backgroundColor: Color(0xFFEAF5FF),
    foregroundColor: Color(0xFF174DC9),
  );

  static const emberArcade = MessageBubbleBackgroundSpec(
    selection: MessageBubbleBackground.emberArcade,
    image: AssetImage('assets/message_bubbles/ember-arcade.png'),
    centerSlice: Rect.fromLTWH(24, 18, 1, 1),
    minimumSize: Size(49, 37),
    contentPadding: EdgeInsets.fromLTRB(14, 10, 14, 10),
    backgroundColor: Color(0xFF292A2D),
    foregroundColor: Color(0xFFFFD36A),
  );

  static const lilacConstellation = MessageBubbleBackgroundSpec(
    selection: MessageBubbleBackground.lilacConstellation,
    image: AssetImage('assets/message_bubbles/lilac-constellation.png'),
    centerSlice: Rect.fromLTWH(24, 18, 1, 1),
    minimumSize: Size(49, 37),
    contentPadding: EdgeInsets.fromLTRB(14, 10, 14, 10),
    backgroundColor: Color(0xFFC8B3E5),
    foregroundColor: Color(0xFF3D2568),
  );

  static const forestFamiliar = MessageBubbleBackgroundSpec(
    selection: MessageBubbleBackground.forestFamiliar,
    image: AssetImage('assets/message_bubbles/forest-familiar.png'),
    centerSlice: Rect.fromLTWH(24, 18, 1, 1),
    minimumSize: Size(49, 37),
    contentPadding: EdgeInsets.fromLTRB(14, 10, 14, 10),
    backgroundColor: Color(0xFFFFF3D6),
    foregroundColor: Color(0xFF394416),
  );

  static const inkWanderer = MessageBubbleBackgroundSpec(
    selection: MessageBubbleBackground.inkWanderer,
    image: AssetImage('assets/message_bubbles/ink-wanderer.png'),
    centerSlice: Rect.fromLTWH(24, 18, 1, 1),
    minimumSize: Size(49, 37),
    contentPadding: EdgeInsets.fromLTRB(14, 10, 14, 10),
    backgroundColor: Color(0xFFFFF3D8),
    foregroundColor: Color(0xFF242632),
  );

  static const pixelCadet = MessageBubbleBackgroundSpec(
    selection: MessageBubbleBackground.pixelCadet,
    image: AssetImage('assets/message_bubbles/pixel-cadet.png'),
    centerSlice: Rect.fromLTWH(24, 18, 1, 1),
    minimumSize: Size(49, 37),
    contentPadding: EdgeInsets.fromLTRB(14, 10, 14, 10),
    backgroundColor: Color(0xFFDDFBFF),
    foregroundColor: Color(0xFF071C54),
  );

  static const cosmicMechanic = MessageBubbleBackgroundSpec(
    selection: MessageBubbleBackground.cosmicMechanic,
    image: AssetImage('assets/message_bubbles/cosmic-mechanic.png'),
    centerSlice: Rect.fromLTWH(24, 18, 1, 1),
    minimumSize: Size(49, 37),
    contentPadding: EdgeInsets.fromLTRB(14, 10, 14, 10),
    backgroundColor: Color(0xFF061C49),
    foregroundColor: Color(0xFFEAFBFF),
  );

  static const pastryPal = MessageBubbleBackgroundSpec(
    selection: MessageBubbleBackground.pastryPal,
    image: AssetImage('assets/message_bubbles/pastry-pal.png'),
    centerSlice: Rect.fromLTWH(24, 18, 1, 1),
    minimumSize: Size(49, 37),
    contentPadding: EdgeInsets.fromLTRB(14, 10, 14, 10),
    backgroundColor: Color(0xFFFFF5DC),
    foregroundColor: Color(0xFF5A321D),
  );

  static const noirDetective = MessageBubbleBackgroundSpec(
    selection: MessageBubbleBackground.noirDetective,
    image: AssetImage('assets/message_bubbles/noir-detective.png'),
    centerSlice: Rect.fromLTWH(24, 18, 1, 1),
    minimumSize: Size(49, 37),
    contentPadding: EdgeInsets.fromLTRB(14, 10, 14, 10),
    backgroundColor: Color(0xFFFFF8E8),
    foregroundColor: Color(0xFF252525),
  );

  final MessageBubbleBackground selection;
  final ImageProvider<Object>? image;
  final Rect? centerSlice;
  final Size minimumSize;
  final EdgeInsets contentPadding;
  final Color? backgroundColor;
  final Color? foregroundColor;

  bool get isDecorative => image != null;
}
