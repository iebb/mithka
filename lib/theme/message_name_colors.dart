import 'package:flutter/widgets.dart';

import 'telegram_cloud_theme.dart';

/// Telegram's seven assigned sender-name colors in `accent_color_id` order:
/// red, orange, violet, green, cyan, blue, and pink.
///
/// Imported themes use the clearest available platform variables. Android
/// names are preferred, followed by iOS, macOS, and Telegram Desktop aliases.
List<Color> messageNameColorsForTheme(TelegramCloudTheme? theme) {
  const fallback = <Color>[
    Color(0xFFE2B4B4),
    Color(0xFFE5EAA8),
    Color(0xFFB39DC8),
    Color(0xFFBAE2B4),
    Color(0xFFA5E1DE),
    Color(0xFFB4C4E2),
    Color(0xFFD59EBB),
  ];
  return theme?.senderNameColors ?? fallback;
}

Color messageNameColorForSender({
  required TelegramCloudTheme? theme,
  required int accentColorId,
  required bool isPremium,
  required bool showPremiumColors,
  required Color premiumColorsDisabledFallback,
}) {
  if (isPremium && !showPremiumColors) {
    return premiumColorsDisabledFallback;
  }
  final colors = messageNameColorsForTheme(theme);
  if (accentColorId >= 0 && accentColorId < colors.length) {
    return colors[accentColorId];
  }
  return colors.first;
}
