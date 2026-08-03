import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mithka/chat/add_members_view.dart';
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

  test('contact tools resolve entirely through Telegram Android keys', () {
    final controller = TelegramLanguageController.test(
      strings: const {
        'Done': 'tg done',
        'VoipGroupInviteMember': 'tg invite members',
        'SearchChats': 'tg search chats',
        'SearchPeopleByUsername': 'tg search people',
        'NoResult': 'tg no result',
        'NoSuchUsers': 'tg no users',
        'AccDescrGroup': 'tg group',
        'EnterChannelName': 'tg channel name',
        'ChannelAlertCreate2': 'tg create channel',
        'ErrorOccurred': 'tg error',
        'NewGroup': 'tg new group',
        'ChatYourSelfName': 'tg you',
        'ChannelBots': 'tg bots',
        'Contacts': 'tg contacts',
        'Loading': 'tg loading',
        'NoChannelsTitle': 'tg no channels',
        'NoContacts': 'tg no contacts',
        'NoSuchGroups': 'tg no groups',
        'Cancel': 'tg cancel',
        'DescriptionOptionalPlaceholder': 'tg optional description',
        'GroupName': 'tg group name',
        'Channel': 'tg channel',
        'Search': 'tg search',
      },
    );

    const expected = <String, String>{
      AppStringKeys.addMembersDone: 'tg done',
      AppStringKeys.addMembersDoneWithCount: 'tg done',
      AppStringKeys.addMembersInviteMembersTitle: 'tg invite members',
      AppStringKeys.addMembersInvitePermissionError: 'tg error',
      AppStringKeys.addPeopleFindGroups: 'tg search chats',
      AppStringKeys.addPeopleFindPeople: 'tg search people',
      AppStringKeys.addPeopleGroupNameOrLinkPlaceholder: 'tg search chats',
      AppStringKeys.addPeopleNoGroupsOrChannelsFound: 'tg no result',
      AppStringKeys.addPeopleNoUsersFound: 'tg no users',
      AppStringKeys.addPeopleUsernameOrPhonePlaceholder: 'tg search people',
      AppStringKeys.chatInfoGroupChat: 'tg group',
      AppStringKeys.chatListChannelName: 'tg channel name',
      AppStringKeys.chatListCreateChannel: 'tg create channel',
      AppStringKeys.chatListCreateChannelFailed: 'tg error',
      AppStringKeys.chatListCreateGroup: 'tg new group',
      AppStringKeys.chatMeLabel: 'tg you',
      AppStringKeys.chatsSearchBots: 'tg bots',
      AppStringKeys.contactsFriends: 'tg contacts',
      AppStringKeys.contactsLoading: 'tg loading',
      AppStringKeys.contactsNoBots: 'tg no result',
      AppStringKeys.contactsNoChannels: 'tg no channels',
      AppStringKeys.contactsNoContacts: 'tg no contacts',
      AppStringKeys.contactsNoGroupChats: 'tg no groups',
      AppStringKeys.countryPickerCancel: 'tg cancel',
      AppStringKeys.createGroupFailed: 'tg error',
      AppStringKeys.createGroupOptionalLabel: 'tg optional description',
      AppStringKeys.createGroupStartGroupChat: 'tg new group',
      AppStringKeys.groupManagementGroupName: 'tg group name',
      AppStringKeys.linkHandlerGroupLabel: 'tg group',
      AppStringKeys.tabChannels: 'tg channel',
      AppStringKeys.tabContacts: 'tg contacts',
      AppStringKeys.topicChatSearch: 'tg search',
    };

    for (final entry in expected.entries) {
      expect(controller.text(entry.key), entry.value, reason: entry.key);
    }
    expect(
      addMembersDoneLabel(controller.text(AppStringKeys.addMembersDone), 0),
      'tg done',
    );
    expect(
      addMembersDoneLabel(controller.text(AppStringKeys.addMembersDone), 3),
      'tg done (3)',
    );
  });

  test('contact management uses matching Telegram Android labels', () {
    final controller = TelegramLanguageController.test(
      strings: const {
        'AddContactTitle': 'tg add contact',
        'ActionYouSuggestBirthday': 'tg birthday sent',
        'NowInContacts': '%1\$s tg added',
        'AccDescrIVDetails': 'tg details',
        'Contacts': 'tg contacts',
        'ProfileNotes': 'tg notes',
        'DeletedFromYourContacts': '%s tg deleted',
        'FilterContact': 'tg contact',
        'DateDay': 'tg day',
        'EditContact': 'tg edit contact',
        'DateMonth': 'tg month',
        'AddNotesInfo': 'tg private notes',
        'ProfileNotesInfo': 'tg only you',
        'FolderLinkPreviewRight': 'tg personal',
        'TypePublic': 'tg public',
        'SharePhoneNumberWith': 'tg visible to %1\$s',
        'DeleteContactTitle': 'tg delete contact title',
        'DeleteContactSubtitle': 'tg delete contact message',
        'DeleteContact': 'tg delete contact',
        'ResetToOriginalPhoto': 'tg reset photo',
        'ResetToOriginalPhotoMessage': 'tg reset %s photo',
        'UserSetPhoto': 'tg set photo for %s',
        'ShareMyPhoneNoCaps': 'tg share phone',
        'AreYouSureShareMyContactInfo': 'tg share phone question',
        'ShareYouPhoneNumberTitle': 'tg share phone title',
        'UserSuggestBirthday': 'tg suggest birthday',
        'UserSuggestBirthdayTitle': 'tg birthday for %s',
        'SuggestPhotoFor': 'tg photo for %s',
        'DateYear': 'tg year',
      },
    );

    const directExpected = <String, String>{
      AppStringKeys.profileContactManagementAddContact: 'tg add contact',
      AppStringKeys.profileContactManagementBirthdateSuggestionSent:
          'tg birthday sent',
      AppStringKeys.profileContactManagementContactDetails: 'tg details',
      AppStringKeys.profileContactManagementContactListSection: 'tg contacts',
      AppStringKeys.profileContactManagementContactNote: 'tg notes',
      AppStringKeys.profileContactManagementContactSection: 'tg contact',
      AppStringKeys.profileContactManagementDay: 'tg day',
      AppStringKeys.profileContactManagementEditContact: 'tg edit contact',
      AppStringKeys.profileContactManagementMonth: 'tg month',
      AppStringKeys.profileContactManagementNoteVisibleOnly: 'tg private notes',
      AppStringKeys.profileContactManagementOnlyYouCanSeeIt: 'tg only you',
      AppStringKeys.profileContactManagementPhotoPersonal: 'tg personal',
      AppStringKeys.profileContactManagementPhotoPublic: 'tg public',
      AppStringKeys.profileContactManagementPrivateNote: 'tg notes',
      AppStringKeys.profileContactManagementRemoveContact:
          'tg delete contact title',
      AppStringKeys.profileContactManagementRemoveContactMessage:
          'tg delete contact message',
      AppStringKeys.profileContactManagementRemoveContactRow:
          'tg delete contact',
      AppStringKeys.profileContactManagementRemovePersonalPhoto:
          'tg reset photo',
      AppStringKeys.profileContactManagementSharePhone: 'tg share phone',
      AppStringKeys.profileContactManagementSharePhoneMessage:
          'tg share phone question',
      AppStringKeys.profileContactManagementShareYourPhoneNumber:
          'tg share phone title',
      AppStringKeys.profileContactManagementSuggestBirthdate:
          'tg suggest birthday',
      AppStringKeys.profileContactManagementYear: 'tg year',
    };
    for (final entry in directExpected.entries) {
      expect(controller.text(entry.key), entry.value, reason: entry.key);
    }

    const namedExpected = <String, String>{
      AppStringKeys.profileContactManagementContactAddedValue1: 'Natu tg added',
      AppStringKeys.profileContactManagementContactRemovedValue1:
          'Natu tg deleted',
      AppStringKeys.profileContactManagementPrivacyExceptionSubtitleValue1:
          'tg visible to Natu',
      AppStringKeys.profileContactManagementReturnOriginalPhotoValue1:
          'tg reset Natu photo',
      AppStringKeys.profileContactManagementSetPersonalPhotoValue1:
          'tg set photo for Natu',
      AppStringKeys.profileContactManagementSharePhonePrivacyExceptionValue1:
          'tg visible to Natu',
      AppStringKeys.profileContactManagementSuggestBirthdateDescriptionValue1:
          'tg birthday for Natu',
      AppStringKeys.profileContactManagementSuggestProfilePhotoValue1:
          'tg photo for Natu',
    };
    for (final entry in namedExpected.entries) {
      expect(
        controller.text(entry.key, placeholders: const {'value1': 'Natu'}),
        entry.value,
        reason: entry.key,
      );
    }
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
