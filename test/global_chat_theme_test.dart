import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_wallpaper.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Map<String, dynamic> settings({
    required int background,
    required int outgoing,
    required bool dark,
  }) => {
    '@type': 'themeSettings',
    'base_theme': {'@type': dark ? 'builtInThemeNight' : 'builtInThemeClassic'},
    'background': {
      '@type': 'background',
      'id': background,
      'type': {
        '@type': 'backgroundTypeFill',
        'fill': {'@type': 'backgroundFillSolid', 'color': background},
      },
    },
    'outgoing_message_fill': {
      '@type': 'backgroundFillSolid',
      'color': outgoing,
    },
    'outgoing_message_accent_color': outgoing,
  };

  Map<String, dynamic> update() {
    const emoji = ['🏠', '🐣', '⛄', '💎', '🧑‍🏫', '🌷', '💜', '🎄', '🎮'];
    return {
      '@type': 'updateEmojiChatThemes',
      'chat_themes': [
        for (var index = 0; index < emoji.length; index++)
          {
            '@type': 'emojiChatTheme',
            'name': emoji[index],
            'light_settings': settings(
              background: 0xE0F0F0 + index,
              outgoing: 0x3698D8 + index,
              dark: false,
            ),
            'dark_settings': settings(
              background: 0x111820 + index,
              outgoing: 0x285278 + index,
              dark: true,
            ),
          },
      ],
    };
  }

  ChatWallpaperController controller() => ChatWallpaperController(
    activeSlot: () => 3,
    hasActiveClient: () => false,
    latestEmojiChatThemes: update,
    listenForUpdates: false,
  );

  test('lists Classic and every official emoji chat theme', () async {
    SharedPreferences.setMockInitialValues({});
    final value = controller();
    addTearDown(value.dispose);

    await value.loadGlobalChatThemes();
    final light = value.globalThemeOptions(dark: false);
    final dark = value.globalThemeOptions(dark: true);

    expect(light.length, 10);
    expect(light.first.label, 'Classic');
    expect(dark.first.label, 'Night');
    expect(light.skip(1).map((theme) => theme.emoji), [
      '🏠',
      '🐣',
      '⛄',
      '💎',
      '🧑‍🏫',
      '🌷',
      '💜',
      '🎄',
      '🎮',
    ]);
    expect(light.skip(1).every((theme) => theme.isOfficialEmoji), isTrue);
    expect(light[1].wallpaper?.colors, [0xE0F0F0]);
    expect(dark[1].wallpaper?.colors, [0x111820]);
    expect(value.stockGlobalThemeOptions().map((theme) => theme.label), [
      'Classic',
      'Dark',
      'Day',
      'Night',
    ]);
    expect(
      value
          .stockGlobalThemeOptions(autoNightModeTriggered: true)
          .map((theme) => theme.label),
      ['Dark', 'Night'],
    );
  });

  test('persists separate light and dark global chat-theme choices', () async {
    SharedPreferences.setMockInitialValues({});
    final first = controller();
    await first.loadGlobalChatThemes();

    expect(
      first.globalThemeSelectionFor(dark: false).stock,
      GlobalChatThemeStock.classic,
    );
    expect(
      first.globalThemeSelectionFor(dark: true).stock,
      GlobalChatThemeStock.night,
    );

    await first.setGlobalChatTheme('🐣', dark: false);
    await first.setGlobalChatTheme('🎮', dark: true);
    expect(first.globalThemeSelectionFor(dark: false).emoji, '🐣');
    expect(first.globalThemeSelectionFor(dark: true).emoji, '🎮');
    first.dispose();

    final restored = controller();
    addTearDown(restored.dispose);
    await restored.loadGlobalChatThemes();

    expect(restored.globalThemeSelectionFor(dark: false).emoji, '🐣');
    expect(restored.globalThemeSelectionFor(dark: true).emoji, '🎮');
    expect(restored.globalThemeWallpaperFor(dark: false)?.colors, [0xE0F0F1]);
    expect(restored.globalThemeStyleFor(dark: false).outgoingColors, [
      0x3698D9,
    ]);
  });

  test(
    'live emoji-theme updates replace the global picker candidates',
    () async {
      SharedPreferences.setMockInitialValues({});
      final updates = StreamController<Map<String, dynamic>>();
      addTearDown(updates.close);
      final value = ChatWallpaperController(
        activeSlot: () => 0,
        hasActiveClient: () => false,
        latestEmojiChatThemes: () => null,
        subscribe: () => updates.stream,
      );
      addTearDown(value.dispose);
      await value.loadGlobalChatThemes();
      expect(value.globalThemeOptions(dark: false), hasLength(1));

      updates.add(update());
      await pumpEventQueue();

      expect(value.globalThemeOptions(dark: false), hasLength(10));
      expect(value.globalThemeOptions(dark: false).last.emoji, '🎮');
    },
  );
}
