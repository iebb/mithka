import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
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

      expect(colors.map((color) => color.toARGB32()), <int>[
        0xFFE2B4B4,
        0xFFE5EAA8,
        0xFFB39DC8,
        0xFFBAE2B4,
        0xFFA5E1DE,
        0xFFB4C4E2,
        0xFFD59EBB,
      ]);
    },
  );

  test('non-premium senders always use their assigned name color', () {
    final color = messageNameColorForSender(
      theme: null,
      accentColorId: 5,
      isPremium: false,
      showPremiumColors: false,
      premiumColorsDisabledFallback: const Color(0xFF010101),
    );

    expect(color.toARGB32(), 0xFFB4C4E2);
  });
}
