import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/l10n/telegram_language_controller.dart';
import 'package:provider/provider.dart';

void main() {
  tearDown(() => Intl.defaultLocale = null);

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

  test('Mithka locale follows a Telegram pack base language', () {
    final controller = TelegramLanguageController.test(
      selectedPackId: 'custom-de',
      packs: const [
        TelegramLanguagePackOption(
          id: 'custom-de',
          baseLanguagePackId: 'de',
          name: 'Custom German',
          nativeName: 'Deutsch',
          pluralCode: 'de',
          isOfficial: false,
          isRtl: false,
          isBeta: false,
          isInstalled: true,
        ),
      ],
    );

    expect(controller.mithkaLocale, const Locale('de'));
  });

  test('all eight supported Telegram language bases map to Mithka locales', () {
    const expected = <String, Locale>{
      'zh-hans': Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      'zh-hant': Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      'ja': Locale('ja'),
      'ko': Locale('ko'),
      'en': Locale('en'),
      'fr': Locale('fr'),
      'es': Locale('es'),
      'de': Locale('de'),
    };

    for (final entry in expected.entries) {
      final controller = TelegramLanguageController.test(
        selectedPackId: entry.key,
        packs: const [],
      );
      expect(controller.mithkaLocale, entry.value, reason: entry.key);
    }
  });

  test('unsupported Telegram pack bases make Mithka use English', () {
    final controller = TelegramLanguageController.test(
      selectedPackId: 'custom-ru',
      packs: const [
        TelegramLanguagePackOption(
          id: 'custom-ru',
          baseLanguagePackId: 'ru',
          name: 'Custom Russian',
          nativeName: 'Russian',
          pluralCode: 'ru',
          isOfficial: false,
          isRtl: false,
          isBeta: false,
          isInstalled: true,
        ),
      ],
    );

    expect(controller.mithkaLocale, AppLocalizations.fallbackLocale);
  });

  test(
    'compact supported-language selection uses an official Telegram pack',
    () async {
      final controller = TelegramLanguageController.test(
        selectedPackId: 'en',
        packs: const [
          TelegramLanguagePackOption(
            id: 'custom-ja',
            baseLanguagePackId: 'ja',
            name: 'Custom Japanese',
            nativeName: 'Custom Japanese',
            pluralCode: 'ja',
            isOfficial: false,
            isRtl: false,
            isBeta: false,
            isInstalled: true,
          ),
          TelegramLanguagePackOption(
            id: 'ja',
            baseLanguagePackId: '',
            name: 'Japanese',
            nativeName: '日本語',
            pluralCode: 'ja',
            isOfficial: true,
            isRtl: false,
            isBeta: false,
            isInstalled: true,
          ),
        ],
      );

      await controller.selectSupportedLocale(const Locale('ja'));

      expect(controller.selectedPackId, 'ja');
      expect(controller.mithkaLocale, const Locale('ja'));
    },
  );

  testWidgets('Telegram pack selection rebuilds localized Mithka UI', (
    tester,
  ) async {
    final controller = TelegramLanguageController.test(
      selectedPackId: 'en',
      packs: const [
        TelegramLanguagePackOption(
          id: 'en',
          baseLanguagePackId: '',
          name: 'English',
          nativeName: 'English',
          pluralCode: 'en',
          isOfficial: true,
          isRtl: false,
          isBeta: false,
          isInstalled: true,
        ),
        TelegramLanguagePackOption(
          id: 'ja',
          baseLanguagePackId: '',
          name: 'Japanese',
          nativeName: '日本語',
          pluralCode: 'ja',
          isOfficial: true,
          isRtl: false,
          isBeta: false,
          isInstalled: true,
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => MaterialApp(
            locale: controller.mithkaLocale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: Builder(
              builder: (context) =>
                  Text(AppStringKeys.tabMessages.l10n(context)),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Messages'), findsOneWidget);

    await controller.setSelectedPack('ja');
    await tester.pumpAndSettle();

    expect(find.text('メッセージ'), findsOneWidget);
    expect(find.text('Messages'), findsNothing);
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

  test('keeps the source name in forwarded-message attribution', () {
    final controller = TelegramLanguageController.test(
      strings: const {'ForwardedFrom': 'Forwarded from'},
    );

    expect(
      controller.text(
        AppStringKeys.messageBubbleForwardedFrom,
        placeholders: const {'value1': 'Original Channel'},
      ),
      'Forwarded from Original Channel',
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

  test(
    'keeps profile and Moments music labels in natural localized casing',
    () {
      final controller = TelegramLanguageController.test(
        strings: const {'SharedMusicTab': 'MUSIC'},
      );

      expect(
        controller.resolveMappedText(
          AppStringKeys.profileDetailMusic,
          const {},
        ),
        isNull,
      );
      expect(controller.text(AppStringKeys.profileDetailMusic), 'Music');
      expect(
        controller.resolveMappedText(AppStringKeys.momentsMusic, const {}),
        isNull,
      );
      expect(controller.text(AppStringKeys.momentsMusic), 'Music');
    },
  );

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
