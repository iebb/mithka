//
//  accent_foreground_test.dart
//
//  What sits on top of an accent fill. This is a stored token, never derived
//  from the accent — the same shape every Telegram client uses. Android keeps
//  key_chats_actionIcon / key_featuredStickers_buttonText / key_checkboxCheck,
//  each defaulting to 0xffffffff, and its theme engine contains no luminance
//  or contrast maths at all. Deriving it instead is what once produced
//  black-on-green for the WeChat accent.
//

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/telegram_cloud_theme.dart';

const white = Color(0xFFFFFFFF);

TelegramCloudTheme themeWith(Map<String, int> palette, {int? accent}) =>
    TelegramCloudTheme(
      slug: 'Probe',
      rawTitle: 'Probe',
      baseTheme: 'builtInThemeDay',
      accentColorValue: accent ?? 0xFF07C160,
      outgoingColors: const [],
      palette: palette,
    );

void main() {
  group('the shipped palettes', () {
    test('default accents carry white', () {
      expect(AppColors.light.onAccent, white);
      expect(AppColors.dark.onAccent, white);
    });
  });

  group('cloud themes', () {
    test('fall back to the stored token, not to a contrast calculation', () {
      // A saturated green accent with no on-accent key. The old luminance
      // branch is gone, so this is white because the base palette says white.
      final colors = themeWith(const {
        'list.plainBg': 0xFFFFFFFF,
      }, accent: 0xFF07C160).uiColors;
      expect(colors.onAccent, white);
    });

    test('a light accent alone does not flip the foreground', () {
      // Nothing about the accent itself moves this — only an explicit key can.
      final colors = themeWith(const {
        'list.plainBg': 0xFFFFFFFF,
      }, accent: 0xFFF3B4BD).uiColors;
      expect(colors.onAccent, white);
    });

    test('an explicit Android key wins', () {
      final colors = themeWith(const {
        'list.plainBg': 0xFFFFFFFF,
        'chats_actionIcon': 0xFF171717,
      }).uiColors;
      expect(colors.onAccent, const Color(0xFF171717));
    });

    test('reads each client key it advertises', () {
      for (final key in const [
        'chats_actionIcon',
        'featuredStickers_buttonText',
        'checkboxCheck',
        'list.itemCheckColors.foregroundColor',
        'underSelectedColor',
        'activeButtonFg',
      ]) {
        final colors = themeWith({
          'list.plainBg': 0xFFFFFFFF,
          key: 0xFF102030,
        }).uiColors;
        expect(colors.onAccent, const Color(0xFF102030), reason: key);
      }
    });

    test('prefers the Android key over lower-fidelity ones', () {
      final colors = themeWith(const {
        'list.plainBg': 0xFFFFFFFF,
        'chats_actionIcon': 0xFF111111,
        'activeButtonFg': 0xFF222222,
      }).uiColors;
      expect(colors.onAccent, const Color(0xFF111111));
    });
  });

  _dialogBadgeAndBubbleKeys();

  group('readableForeground', () {
    test('still maximises raw contrast for non-accent surfaces', () {
      expect(readableForeground(const Color(0xFFFFFFFF)), isNot(white));
      expect(readableForeground(const Color(0xFF000000)), white);
    });
  });
}

// Telegram keys the rest of the chrome binds to. Same rule as onAccent: the
// value is stored under a key each client actually ships, never derived.
void _dialogBadgeAndBubbleKeys() {
  group('dialog, badge and bubble keys', () {
    test('dialog button and text read their Android keys', () {
      final colors = themeWith(const {
        'list.plainBg': 0xFFFFFFFF,
        'dialogButton': 0xFF298ACF,
        'dialogTextBlack': 0xFF1A1D21,
      }).uiColors;
      expect(colors.dialogButton, const Color(0xFF298ACF));
      expect(colors.dialogText, const Color(0xFF1A1D21));
    });

    test('unread counter reads its own fill and label', () {
      final colors = themeWith(const {
        'list.plainBg': 0xFFFFFFFF,
        'chats_unreadCounter': 0xFF229AF0,
        'chats_unreadCounterText': 0xFF102030,
      }).uiColors;
      expect(colors.badgeBackground, const Color(0xFF229AF0));
      expect(colors.badgeText, const Color(0xFF102030));
    });

    test('a badge with no label key falls back to the on-accent token', () {
      final colors = themeWith(const {
        'list.plainBg': 0xFFFFFFFF,
        'chats_unreadCounter': 0xFF229AF0,
        'chats_actionIcon': 0xFF171717,
      }).uiColors;
      expect(colors.badgeText, const Color(0xFF171717));
    });

    test('the filled accent button keys its fill and label apart', () {
      final colors = themeWith(const {
        'list.plainBg': 0xFFFFFFFF,
        'featuredStickers_addButton': 0xFF229AF0,
        'featuredStickers_buttonText': 0xFF102030,
      }).uiColors;
      expect(colors.accentButton, const Color(0xFF229AF0));
      expect(colors.accentButtonText, const Color(0xFF102030));
    });

    test('a button with no keys falls back to accent and on-accent', () {
      final colors = themeWith(const {
        'list.plainBg': 0xFFFFFFFF,
      }, accent: 0xFF07C160).uiColors;
      expect(colors.accentButton, const Color(0xFF07C160));
      expect(colors.accentButtonText, white);
    });

    test('selected bubble fills come from their own keys', () {
      final theme = themeWith(const {
        'list.plainBg': 0xFFFFFFFF,
        'chat_inBubble': 0xFFFFFFFF,
        'chat_inBubbleSelected': 0xFFECF7FD,
        'chat_outBubble': 0xFFEFFFDE,
        'chat_outBubbleSelected': 0xFFD9F7C5,
      });
      expect(theme.incomingColor, const Color(0xFFFFFFFF));
      expect(theme.incomingSelectedColor, const Color(0xFFECF7FD));
      expect(theme.outgoingSelectedColor, const Color(0xFFD9F7C5));
    });

    test('a theme naming no selected key reports none', () {
      final theme = themeWith(const {
        'list.plainBg': 0xFFFFFFFF,
        'chat_inBubble': 0xFFFFFFFF,
      });
      expect(theme.incomingSelectedColor, isNull);
      expect(theme.outgoingSelectedColor, isNull);
    });
  });
}
