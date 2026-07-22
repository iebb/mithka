import 'package:flutter/widgets.dart';

import 'app_theme.dart';
import 'telegram_cloud_theme.dart';

/// Telegram's seven assigned sender-name colors in `accent_color_id` order:
/// red, orange, violet, green, cyan, blue, and pink.
///
/// Imported themes use the clearest available platform variables. Android
/// names are preferred, followed by iOS, macOS, and Telegram Desktop aliases.
List<Color> messageNameColorsForTheme(TelegramCloudTheme? theme) {
  return theme?.senderNameColors ??
      AppTheme.avatarPalette.take(7).toList(growable: false);
}

Color messageNameColorForSender({
  required TelegramCloudTheme? theme,
  required int accentColorId,
  required bool showNameColors,
  required Color nameColorsDisabledFallback,
}) {
  if (!showNameColors) {
    return nameColorsDisabledFallback;
  }
  final colors = messageNameColorsForTheme(theme);
  final paletteIndex = accentColorId < 0 ? 0 : accentColorId % colors.length;
  return colors[paletteIndex];
}
