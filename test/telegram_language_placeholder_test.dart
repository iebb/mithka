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

  test('familiar glossary always calls archived chats group assistant', () {
    final controller = TelegramLanguageController.test(
      activePackId: 'zhhanscn-qq',
      strings: const {'ArchivedChats': '归档的聊天'},
    );

    expect(controller.text(AppStringKeys.archivedChatsGroupAssistant), '群助手');
    expect(controller.text(AppStringKeys.appearanceArchivedChats), '群助手');
  });

  test('standard glossary keeps the Telegram archived chats wording', () {
    final controller = TelegramLanguageController.test(
      activePackId: 'zh-hans',
      strings: const {'ArchivedChats': '归档的聊天'},
    );

    expect(controller.text(AppStringKeys.archivedChatsGroupAssistant), '归档的聊天');
  });
}
