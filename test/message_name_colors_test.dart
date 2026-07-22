import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/message_name_colors.dart';
import 'package:mithka/theme/telegram_cloud_theme.dart';

void main() {
  test('sender name colors prefer Android variables over platform aliases', () {
    const theme = TelegramCloudTheme(
      slug: 'test',
      rawTitle: 'Test',
      baseTheme: 'builtInThemeNight',
      accentColorValue: 0,
      outgoingColors: [],
      palette: {
        'avatar_nameInMessageRed': 0x112233,
        'chat.message.incoming.authorName.red': 0x445566,
        'chat_messageNameRed': 0x778899,
        'historyPeer1NameFg': 0xAABBCC,
        'historyPeer6NameFg': 0x102030,
      },
    );

    final colors = messageNameColorsForTheme(theme);

    expect(colors, hasLength(7));
    expect(colors[0].toARGB32(), 0xFF112233);
    expect(colors[5].toARGB32(), 0xFF102030);
  });

  test(
    'sender name colors retain semantic fallbacks when variables are absent',
    () {
      final colors = messageNameColorsForTheme(null);

      expect(
        colors.map((color) => color.toARGB32()),
        AppTheme.avatarPalette.take(7).map((color) => color.toARGB32()),
      );
    },
  );

  test('normal users use their assigned theme-palette color', () {
    final color = messageNameColorForSender(
      theme: null,
      accentColorId: 5,
      showNameColors: true,
      nameColorsDisabledFallback: const Color(0xFF010101),
    );

    expect(color, AppTheme.avatarPalette[5]);
  });

  test('extended accent IDs wrap through the active theme palette', () {
    const theme = TelegramCloudTheme(
      slug: 'test',
      rawTitle: 'Test',
      baseTheme: 'builtInThemeNight',
      accentColorValue: 0,
      outgoingColors: [],
      palette: {
        'avatar_nameInMessageRed': 0x110000,
        'avatar_nameInMessageOrange': 0x220000,
        'avatar_nameInMessageViolet': 0x330000,
        'avatar_nameInMessageGreen': 0x440000,
        'avatar_nameInMessageCyan': 0x550000,
        'avatar_nameInMessageBlue': 0x660000,
        'avatar_nameInMessagePink': 0x770000,
      },
    );

    final color = messageNameColorForSender(
      theme: theme,
      accentColorId: 9,
      showNameColors: true,
      nameColorsDisabledFallback: const Color(0xFF010101),
    );

    expect(color.toARGB32(), 0xFF330000);
  });

  test('name-color opt-out uses the theme sender-name color', () {
    const theme = TelegramCloudTheme(
      slug: 'test',
      rawTitle: 'Test',
      baseTheme: 'builtInThemeNight',
      accentColorValue: 0x123456,
      outgoingColors: [],
      palette: {},
    );

    final color = messageNameColorForSender(
      theme: theme,
      accentColorId: 5,
      showNameColors: false,
      nameColorsDisabledFallback: theme.senderNameColor,
    );

    expect(color, theme.senderNameColor);
  });
}
