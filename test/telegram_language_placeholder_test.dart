import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/l10n/telegram_language_controller.dart';

void main() {
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

  test('uses the selected language pack wording without app overrides', () {
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
