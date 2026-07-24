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
  purpleFolded,
  creamCharms,
  custom;

  static MessageBubbleBackground fromStorage(String? value) => switch (value) {
    // Keep the value written by the first preview build of this feature.
    'moonlitViolet' => MessageBubbleBackground.purpleFolded,
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
    MessageBubbleBackground.purpleFolded => purpleFolded,
    MessageBubbleBackground.creamCharms => creamCharms,
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

  static const purpleFolded = MessageBubbleBackgroundSpec(
    selection: MessageBubbleBackground.purpleFolded,
    image: AssetImage('assets/message_bubbles/purple_folded.png'),
    centerSlice: Rect.fromLTWH(15, 14, 1, 1),
    minimumSize: Size(32, 29),
    contentPadding: EdgeInsets.fromLTRB(9.5, 11, 10, 7),
    backgroundColor: Color(0xFF47277E),
    foregroundColor: Color(0xFFFFF09B),
  );

  static const creamCharms = MessageBubbleBackgroundSpec(
    selection: MessageBubbleBackground.creamCharms,
    image: AssetImage('assets/message_bubbles/cream_charms.png'),
    centerSlice: Rect.fromLTWH(22, 15, 1, 1),
    minimumSize: Size(45, 37),
    contentPadding: EdgeInsets.fromLTRB(16.5, 12.5, 13, 14.5),
    backgroundColor: Color(0xFFFFF2A4),
    foregroundColor: Color(0xFFD35722),
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
