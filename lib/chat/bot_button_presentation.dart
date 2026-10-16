import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../tdlib/td_models.dart';
import 'custom_emoji.dart';

typedef BotButtonPalette = ({Color background, Color foreground, Color border});

AppIconData? botButtonBadgeIcon(MessageButton button) {
  if (button.isReplyKeyboard) return null;
  if (button.isWebApp) return HeroAppIcons.globe;
  if (button.url != null && button.url!.isNotEmpty) {
    return HeroAppIcons.arrowTopRight;
  }
  if (button.isSwitchInline) {
    return button.isSwitchInlineCurrentChat
        ? HeroAppIcons.at
        : HeroAppIcons.share;
  }
  if (button.copyText != null && button.copyText!.isNotEmpty) {
    return HeroAppIcons.clipboard;
  }
  return null;
}

BotButtonPalette botButtonPalette(
  MessageButtonStyle style, {
  required BotButtonPalette standard,
  required Color primary,
}) => switch (style) {
  MessageButtonStyle.primary => (
    background: primary,
    foreground: Colors.white,
    border: primary,
  ),
  MessageButtonStyle.danger => (
    background: const Color(0xFFE25555),
    foreground: Colors.white,
    border: const Color(0xFFE25555),
  ),
  MessageButtonStyle.success => (
    background: const Color(0xFF2FAF69),
    foreground: Colors.white,
    border: const Color(0xFF2FAF69),
  ),
  MessageButtonStyle.standard => standard,
};

class BotButtonLabel extends StatelessWidget {
  const BotButtonLabel({
    super.key,
    required this.button,
    required this.color,
    required this.fontSize,
    required this.fontWeight,
    this.iconSize = 18,
  });

  final MessageButton button;
  final Color color;
  final double fontSize;
  final FontWeight fontWeight;
  final double iconSize;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (button.iconCustomEmojiId != 0) ...[
        CustomEmojiView(
          id: button.iconCustomEmojiId,
          size: iconSize,
          color: color,
        ),
        const SizedBox(width: 5),
      ],
      Flexible(
        child: Text(
          button.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
          ),
        ),
      ),
    ],
  );
}
