import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/l10n/telegram_language_controller.dart';

void main() {
  test('prefers the familiar pack for Simplified Chinese', () {
    final controller = TelegramLanguageController.test();

    expect(
      controller.preferredPackIdForLocale(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      ),
      'zhhanscn-qq',
    );
    expect(controller.packs.single.displayName, '简体中文（熟悉术语）');
    expect(controller.packs.single.isOfficial, isFalse);
  });

  test('falls back when a Telegram plural placeholder has no value', () {
    final controller = TelegramLanguageController.test(
      strings: const {'Members': '％1＄d members'},
    );

    expect(
      controller.text(AppStringKeys.chatInfoGroupMembers),
      'Group members',
    );
  });

  test('interpolates Android positional placeholders when a value exists', () {
    final controller = TelegramLanguageController.test(
      strings: const {'Members': '％1＄d members'},
    );

    expect(
      controller.text(
        AppStringKeys.chatMembersTitleWithCount,
        placeholders: const {'value1': 42},
      ),
      '42 members',
    );
  });

  test('familiar glossary keeps familiar archived-chat wording', () {
    final controller = TelegramLanguageController.test(
      activePackId: 'zhhanscn-qq',
      strings: const {'ArchivedChats': '归档的聊天'},
    );

    expect(controller.text(AppStringKeys.archivedChatsGroupAssistant), '群助手');
    expect(controller.text(AppStringKeys.appearanceArchivedChats), '群助手');
  });

  test('standard glossary uses the selected language pack wording', () {
    final controller = TelegramLanguageController.test(
      activePackId: 'zh-hans',
      strings: const {'ArchivedChats': '归档的聊天'},
    );

    expect(controller.text(AppStringKeys.archivedChatsGroupAssistant), '归档的聊天');
  });

  test('keeps channel feeds and Stories as distinct app labels', () {
    final controller = TelegramLanguageController.test(
      strings: const {'NotificationsStories': '动态'},
    );

    expect(
      controller.resolveMappedText(AppStringKeys.momentsStories, const {}),
      isNull,
    );
  });

  test('uses Telegram Business bot permission wording', () {
    final controller = TelegramLanguageController.test(
      strings: const {
        'BusinessBotPermissionsMessagesReply': 'official reply permission',
        'BusinessBotPermissionsGiftsSell': 'official gift conversion',
        'BusinessBotPermissionsStories': 'official story permission',
      },
    );

    expect(
      controller.text(AppStringKeys.businessToolsRightReplyToMessages),
      'official reply permission',
    );
    expect(
      controller.text(AppStringKeys.businessToolsRightSellGifts),
      'official gift conversion',
    );
    expect(
      controller.text(AppStringKeys.businessToolsRightManageStories),
      'official story permission',
    );
  });

  test('uses Telegram Android presence keys on every platform', () {
    final controller = TelegramLanguageController.test(
      strings: const {
        'Online': 'android online',
        'Lately': 'android recently',
        'WithinAWeek': 'android week',
        'WithinAMonth': 'android month',
      },
    );

    expect(
      controller.presenceText(TelegramPresenceLabel.online),
      'android online',
    );
    expect(
      controller.presenceText(TelegramPresenceLabel.recently),
      'android recently',
    );
    expect(
      controller.presenceText(TelegramPresenceLabel.withinWeek),
      'android week',
    );
    expect(
      controller.presenceText(TelegramPresenceLabel.withinMonth),
      'android month',
    );
  });

  test('presence strings have Telegram English startup fallbacks', () {
    final controller = TelegramLanguageController.test();

    expect(controller.presenceText(TelegramPresenceLabel.online), 'online');
    expect(
      controller.presenceText(TelegramPresenceLabel.recently),
      'last seen recently',
    );
  });
}
