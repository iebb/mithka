import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/chat_deep_link_controller.dart';
import 'package:mithka/app/desktop_utility_window.dart';
import 'package:mithka/app/desktop_utility_window_io.dart';

void main() {
  DesktopUtilityWindowArguments arguments({
    DesktopUtilityWindowKind kind = DesktopUtilityWindowKind.files,
    int? chatId,
    int? userId,
    String title = 'Files',
    String? initialSettingsCategoryId,
    String? initialQuery,
    String? instanceId,
  }) => DesktopUtilityWindowArguments(
    kind: kind,
    accountSlot: 2,
    accountUserId: 88,
    chatId: chatId,
    userId: userId,
    title: title,
    localeTag: 'zh-Hans',
    dark: true,
    initialSettingsCategoryId: initialSettingsCategoryId,
    initialQuery: initialQuery,
    instanceId: instanceId,
  );

  test('utility arguments round-trip without TDLib session material', () {
    final original = arguments(
      kind: DesktopUtilityWindowKind.savedMessages,
      chatId: 9988,
      title: 'Saved\nMessages',
    );
    final encoded = original.encode();
    final parsed = DesktopUtilityWindowArguments.tryParse(encoded);

    expect(parsed?.kind, DesktopUtilityWindowKind.savedMessages);
    expect(parsed?.accountSlot, 2);
    expect(parsed?.accountUserId, 88);
    expect(parsed?.chatId, 9988);
    expect(parsed?.title, 'Saved Messages');
    expect(parsed?.localeTag, 'zh-Hans');
    expect(parsed?.dark, isTrue);
    expect(encoded, isNot(contains('session')));
    expect(encoded, isNot(contains('token')));
    expect(encoded, isNot(contains('phone')));
    expect(encoded, isNot(contains('database')));
  });

  test('utility child defers layout while native metrics are transient', () {
    expect(desktopUtilityWindowHasUsableMetrics(const Size(1, 1)), isFalse);
    expect(desktopUtilityWindowHasUsableMetrics(const Size(319, 700)), isFalse);
    expect(desktopUtilityWindowHasUsableMetrics(const Size(500, 199)), isFalse);
    expect(desktopUtilityWindowHasUsableMetrics(const Size(500, 700)), isTrue);
  });

  test('primary-chat IPC carries presentation only and validates input', () {
    final encoded = const ChatDeepLinkRequest(
      chatId: -10042,
      title: '  Group\nName  ',
      messageId: 77,
      accountSlot: 9,
      accountUserId: 88,
    ).toDesktopIpcJson();

    expect(encoded, {'chatId': -10042, 'title': 'Group Name', 'messageId': 77});
    expect(encoded, isNot(contains('accountSlot')));
    expect(encoded, isNot(contains('accountUserId')));

    final parsed = ChatDeepLinkRequest.tryParseDesktopIpc(encoded);
    expect(parsed?.chatId, -10042);
    expect(parsed?.title, 'Group Name');
    expect(parsed?.messageId, 77);
    expect(parsed?.accountSlot, isNull);
    expect(parsed?.accountUserId, isNull);

    expect(
      ChatDeepLinkRequest.tryParseDesktopIpc({
        'chatId': -10042,
        'title': <String>['not', 'text'],
      }),
      isNull,
    );
    expect(
      ChatDeepLinkRequest.tryParseDesktopIpc({'chatId': 0, 'title': 'Invalid'}),
      isNull,
    );
  });

  test('settings shortcut category round-trips as presentation metadata', () {
    final encoded = arguments(
      kind: DesktopUtilityWindowKind.settings,
      title: 'Appearance',
      initialSettingsCategoryId: 'appearance',
    ).encode();
    final parsed = DesktopUtilityWindowArguments.tryParse(encoded);

    expect(parsed?.initialSettingsCategoryId, 'appearance');
    expect(encoded, isNot(contains('session')));
    expect(
      DesktopUtilityWindowArguments.normalizeSettingsCategoryId('../secret'),
      isNull,
    );
  });

  test('search query round-trips and isolates full-search child windows', () {
    final first = arguments(
      kind: DesktopUtilityWindowKind.search,
      title: 'Search',
      initialQuery: '  mao\ncat  ',
      instanceId: 'search_1',
    );
    final second = arguments(
      kind: DesktopUtilityWindowKind.search,
      title: 'Search',
      initialQuery: 'another query',
      instanceId: 'search_2',
    );
    final repeatedQuery = arguments(
      kind: DesktopUtilityWindowKind.search,
      title: 'Search',
      initialQuery: 'mao cat',
      instanceId: 'search_3',
    );
    final parsed = DesktopUtilityWindowArguments.tryParse(first.encode());

    expect(parsed?.initialQuery, 'mao cat');
    expect(parsed?.key.query, 'mao cat');
    expect(parsed?.key.instanceId, 'search_1');
    expect(parsed?.toIpcJson()['query'], 'mao cat');
    expect(parsed?.toIpcJson()['instanceId'], 'search_1');
    expect(first.key, isNot(second.key));
    expect(first.key, isNot(repeatedQuery.key));
    expect(first.encode(), isNot(contains('session')));
    expect(
      DesktopUtilityWindowArguments.normalizeSearchQuery(
        List.filled(300, 'x').join(),
      ),
      hasLength(256),
    );
  });

  test('chat info and user profile arguments require stable target ids', () {
    final chatInfo = DesktopUtilityWindowArguments.tryParse(
      arguments(
        kind: DesktopUtilityWindowKind.chatInfo,
        chatId: -10042,
        title: 'Group info',
      ).encode(),
    );
    final profile = DesktopUtilityWindowArguments.tryParse(
      arguments(
        kind: DesktopUtilityWindowKind.userProfile,
        userId: 7766,
        title: 'Natu',
      ).encode(),
    );

    expect(chatInfo?.chatId, -10042);
    expect(chatInfo?.key.chatId, -10042);
    expect(profile?.userId, 7766);
    expect(profile?.key.userId, 7766);
    final unrelatedTargets = arguments(chatId: 55, userId: 66).encode();
    expect(unrelatedTargets, isNot(contains('"chatId"')));
    expect(unrelatedTargets, isNot(contains('"userId"')));
    expect(
      DesktopUtilityWindowArguments.tryParse(
        arguments(kind: DesktopUtilityWindowKind.chatInfo).encode(),
      ),
      isNull,
    );
    expect(
      DesktopUtilityWindowArguments.tryParse(
        arguments(kind: DesktopUtilityWindowKind.userProfile).encode(),
      ),
      isNull,
    );
  });

  test('composer picker arguments round-trip with their target chat', () {
    for (final kind in [
      DesktopUtilityWindowKind.audioPicker,
      DesktopUtilityWindowKind.locationPicker,
      DesktopUtilityWindowKind.contactPicker,
      DesktopUtilityWindowKind.pollComposer,
      DesktopUtilityWindowKind.checklistComposer,
      DesktopUtilityWindowKind.scheduledMessages,
      DesktopUtilityWindowKind.richTextComposer,
      DesktopUtilityWindowKind.aiEditor,
    ]) {
      final original = arguments(kind: kind, chatId: -100987, title: kind.id);
      final parsed = DesktopUtilityWindowArguments.tryParse(original.encode());

      expect(parsed?.kind, kind);
      expect(parsed?.chatId, -100987);
      expect(parsed?.key.chatId, -100987);
      expect(parsed?.toIpcJson()['chatId'], -100987);
    }
  });

  test('saved-messages child can open only same-chat composer pickers', () {
    final saved = arguments(
      kind: DesktopUtilityWindowKind.savedMessages,
      chatId: 9988,
    );

    for (final kind in [
      DesktopUtilityWindowKind.audioPicker,
      DesktopUtilityWindowKind.locationPicker,
      DesktopUtilityWindowKind.contactPicker,
      DesktopUtilityWindowKind.pollComposer,
      DesktopUtilityWindowKind.checklistComposer,
      DesktopUtilityWindowKind.scheduledMessages,
      DesktopUtilityWindowKind.richTextComposer,
      DesktopUtilityWindowKind.aiEditor,
    ]) {
      expect(
        desktopUtilityChildRequestIsAllowed(
          requestingUtility: saved,
          requestedUtility: arguments(kind: kind, chatId: 9988),
        ),
        isTrue,
        reason: kind.id,
      );
    }
    expect(
      desktopUtilityChildRequestIsAllowed(
        requestingUtility: saved,
        requestedUtility: arguments(
          kind: DesktopUtilityWindowKind.locationPicker,
          chatId: 9989,
        ),
      ),
      isFalse,
    );
    expect(
      desktopUtilityChildRequestIsAllowed(
        requestingUtility: saved,
        requestedUtility: arguments(kind: DesktopUtilityWindowKind.settings),
      ),
      isFalse,
    );
  });

  test('malformed and incomplete launch arguments are ignored', () {
    expect(
      DesktopUtilityWindowArguments.tryParseLaunchArguments(const []),
      isNull,
    );
    expect(DesktopUtilityWindowArguments.tryParse('not json'), isNull);
    expect(
      DesktopUtilityWindowArguments.tryParse(
        '{"version":1,"type":"mithka.utility","kind":"unknown",'
        '"accountSlot":0}',
      ),
      isNull,
    );
    expect(
      DesktopUtilityWindowArguments.tryParse(
        '{"version":1,"type":"mithka.utility",'
        '"kind":"saved-messages","accountSlot":0}',
      ),
      isNull,
    );
  });

  test('registry isolates each account and utility destination', () {
    final registry = DesktopUtilityWindowRegistry();
    const calls = DesktopUtilityWindowKey(
      accountSlot: 0,
      kind: DesktopUtilityWindowKind.calls,
    );
    const files = DesktopUtilityWindowKey(
      accountSlot: 0,
      kind: DesktopUtilityWindowKind.files,
    );
    const otherAccountCalls = DesktopUtilityWindowKey(
      accountSlot: 1,
      kind: DesktopUtilityWindowKind.calls,
    );

    registry.register(calls, 10);
    registry.register(files, 11);
    registry.register(otherAccountCalls, 12);
    expect(registry.activeWindowFor(calls, const [10, 11, 12]), 10);
    expect(registry.activeWindowFor(files, const [10, 11, 12]), 11);
    expect(registry.activeWindowFor(otherAccountCalls, const [10, 11, 12]), 12);

    registry.register(calls, 13);
    expect(registry.keyForWindow(10), isNull);
    expect(registry.activeWindowFor(calls, const [11, 12, 13]), 13);
    expect(registry.activeWindowFor(files, const [12, 13]), isNull);
  });

  test('registry isolates compact info windows by chat and user', () {
    final registry = DesktopUtilityWindowRegistry();
    const firstChat = DesktopUtilityWindowKey(
      accountSlot: 0,
      kind: DesktopUtilityWindowKind.chatInfo,
      chatId: -1001,
    );
    const secondChat = DesktopUtilityWindowKey(
      accountSlot: 0,
      kind: DesktopUtilityWindowKind.chatInfo,
      chatId: -1002,
    );
    const firstUser = DesktopUtilityWindowKey(
      accountSlot: 0,
      kind: DesktopUtilityWindowKind.userProfile,
      userId: 7,
    );
    const secondUser = DesktopUtilityWindowKey(
      accountSlot: 0,
      kind: DesktopUtilityWindowKind.userProfile,
      userId: 8,
    );

    registry.register(firstChat, 20);
    registry.register(secondChat, 21);
    registry.register(firstUser, 22);
    registry.register(secondUser, 23);
    expect(registry.activeWindowFor(firstChat, const [20, 21, 22, 23]), 20);
    expect(registry.activeWindowFor(secondChat, const [20, 21, 22, 23]), 21);
    expect(registry.activeWindowFor(firstUser, const [20, 21, 22, 23]), 22);
    expect(registry.activeWindowFor(secondUser, const [20, 21, 22, 23]), 23);
  });

  test('utility transport requires the original non-null account identity', () {
    expect(
      desktopUtilityAccountIdentityIsCurrent(
        kind: DesktopUtilityWindowKind.search,
        registeredAccountUserId: 88,
        currentAccountUserId: 88,
      ),
      isTrue,
    );
    expect(
      desktopUtilityAccountIdentityIsCurrent(
        kind: DesktopUtilityWindowKind.search,
        registeredAccountUserId: 88,
        currentAccountUserId: 99,
      ),
      isFalse,
    );
    expect(
      desktopUtilityAccountIdentityIsCurrent(
        kind: DesktopUtilityWindowKind.search,
        registeredAccountUserId: null,
        currentAccountUserId: 99,
      ),
      isFalse,
    );
    expect(
      desktopUtilityAccountIdentityIsCurrent(
        kind: DesktopUtilityWindowKind.files,
        registeredAccountUserId: null,
        currentAccountUserId: 99,
      ),
      isFalse,
    );
    expect(
      desktopUtilityAccountIdentityIsCurrent(
        kind: DesktopUtilityWindowKind.files,
        registeredAccountUserId: 99,
        currentAccountUserId: null,
      ),
      isFalse,
    );
    expect(
      desktopUtilityAccountIdentityIsCurrent(
        kind: DesktopUtilityWindowKind.files,
        registeredAccountUserId: 99,
        currentAccountUserId: 99,
      ),
      isTrue,
    );
  });

  test('child-facing chat entry points use the primary-window launcher', () {
    final calls = File('lib/call/calls_view.dart').readAsStringSync();
    final chat = File('lib/chat/chat_view.dart').readAsStringSync();
    final chatInfo = File('lib/chat/chat_info_view.dart').readAsStringSync();
    final links = File('lib/chat/link_handler.dart').readAsStringSync();
    final pinned = File(
      'lib/chat/pinned_messages_view.dart',
    ).readAsStringSync();
    final additionalEntryPoints = [
      'lib/contacts/contacts_view.dart',
      'lib/contacts/add_people_view.dart',
      'lib/contacts/create_group_view.dart',
      'lib/chats/public_discovery_view.dart',
      'lib/profile/profile_view.dart',
      'lib/profile/profile_detail_view.dart',
      'lib/moments/story_viewer_view.dart',
    ].map((path) => File(path).readAsStringSync());

    expect(calls, contains('openChatFromCurrentWindow('));
    expect(
      RegExp(r'openChatFromCurrentWindow\(').allMatches(chat).length,
      greaterThanOrEqualTo(3),
    );
    expect(links, contains('handoffChatToPrimaryWindow('));
    expect(links, contains("fullInfo.int64('direct_messages_chat_id')"));
    expect(links, isNot(contains('ChannelDirectMessagesView(')));
    expect(pinned, contains('openChatFromCurrentWindow('));
    expect(chatInfo, isNot(contains('ChannelDirectMessagesView(')));
    for (final source in additionalEntryPoints) {
      expect(source, contains('openChatFromCurrentWindow('));
    }
  });

  test('IPC normalizes nested codec maps and blocks lifecycle requests', () {
    final bytes = Uint8List.fromList(const [1, 2, 3]);
    final request = desktopUtilitySanitizeRequest(<Object?, Object?>{
      '@type': 'sendMessage',
      '@client_id': 999,
      '@extra': 'child-correlation',
      'input_message_content': <Object?, Object?>{
        '@type': 'inputMessageText',
        'text': <Object?, Object?>{
          '@type': 'formattedText',
          'text': 'hello',
          'entities': <Object?>[
            <Object?, Object?>{'@type': 'textEntity', 'offset': 0, 'length': 5},
          ],
        },
        'bytes': bytes,
      },
    });

    expect(request?['@client_id'], isNull);
    expect(request?['@extra'], isNull);
    final content = request?['input_message_content'];
    expect(content, isA<Map<String, dynamic>>());
    final text = (content as Map<String, dynamic>)['text'];
    expect(text, isA<Map<String, dynamic>>());
    expect((text as Map<String, dynamic>)['entities'], [
      {'@type': 'textEntity', 'offset': 0, 'length': 5},
    ]);
    expect(content['bytes'], same(bytes));

    for (final type in ['close', 'destroy', 'logOut', 'setTdlibParameters']) {
      expect(desktopUtilitySanitizeRequest({'@type': type}), isNull);
    }
    expect(desktopUtilitySanitizeRequest({'chat_id': 42}), isNull);
  });

  test('child dispatches production widgets over the primary TD proxy', () {
    final child = File(
      'lib/app/desktop_utility_window.dart',
    ).readAsStringSync();
    final io = File(
      'lib/app/desktop_utility_window_io.dart',
    ).readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final mainTabs = File('lib/app/main_tab_view.dart').readAsStringSync();

    expect(child, contains('CallsView(showBackButton: false)'));
    expect(child, contains('ChatView('));
    expect(child, contains('SharedMediaView('));
    expect(child, contains('SettingsView('));
    expect(child, contains('ChatInfoView('));
    expect(child, contains('ProfileDetailView('));
    expect(child, contains('AudioSearchView('));
    expect(child, contains('LocationPickerView('));
    expect(child, contains('ContactSharePickerView('));
    expect(child, contains('PollComposerView('));
    expect(child, contains('ChecklistComposerView('));
    expect(child, contains('ScheduledMessagesView('));
    expect(child, contains('RichTextComposerView('));
    expect(child, contains('TelegramAiEditorView('));
    expect(child, contains('SearchView('));
    expect(child, contains('initialQuery: widget.arguments.initialQuery'));
    expect(child, contains('showBackButton: false'));
    expect(child, contains('allowSessionLifecycleActions: false'));
    expect(
      child,
      contains('initialCategoryId: widget.arguments.initialSettingsCategoryId'),
    );
    expect(child, isNot(contains('DesktopPrimaryWindowFrame(')));
    expect(io, contains('invokeMethodToWindow(0, _queryMethod'));
    expect(io, contains('TdClient.shared.queryTo'));
    expect(io, contains('_clientIdByWindow'));
    expect(io, contains('_identityIsCurrent'));
    expect(io, contains('_rejectStaleWindow'));
    expect(io, contains('TdClient.shared.subscribeAll()'));
    expect(io, isNot(contains('TdClient.shared.start')));
    expect(io, contains('mithka.utility.settings.changed'));
    expect(child, contains('notifySettingsChanged'));
    expect(child, contains('attachChildPresentationReload'));
    expect(child, contains('DesktopHotkeyController.initializeShared'));
    expect(child, contains('DesktopHotkeyController.maybeShared'));
    expect(io, contains('mithka.utility.presentation.changed'));
    expect(io, contains('_broadcastPresentationChanged'));
    expect(
      main,
      contains('DesktopUtilityWindowArguments.tryParseLaunchArguments'),
    );
    expect(main, contains('configureChildProxy'));
    expect(main, contains('onSettingsChanged: _reloadDesktopSettings'));
    expect(main, contains('accountUserIdForSlot: _accountUserIdForSlot'));
    expect(main, contains('await widget.prefs.reload()'));
    expect(mainTabs, contains("id: 'appearance'"));
    expect(mainTabs, contains('_openGlobalThemeSelector'));
  });

  test(
    'utility roots use a native system title bar and no root back button',
    () {
      final io = File(
        'lib/app/desktop_utility_window_io.dart',
      ).readAsStringSync();
      final calls = File('lib/call/calls_view.dart').readAsStringSync();
      final media = File('lib/chat/shared_media_view.dart').readAsStringSync();

      expect(io, contains('titleBarStyle: TitleBarStyle.normal'));
      expect(io, contains('windowButtonVisibility: true'));
      final chatInfo = desktopUtilityWindowOptions(
        arguments(kind: DesktopUtilityWindowKind.chatInfo, chatId: -10042),
      );
      final profile = desktopUtilityWindowOptions(
        arguments(kind: DesktopUtilityWindowKind.userProfile, userId: 7),
      );
      final audio = desktopUtilityWindowOptions(
        arguments(kind: DesktopUtilityWindowKind.audioPicker, chatId: 42),
      );
      final location = desktopUtilityWindowOptions(
        arguments(kind: DesktopUtilityWindowKind.locationPicker, chatId: 42),
      );
      final contact = desktopUtilityWindowOptions(
        arguments(kind: DesktopUtilityWindowKind.contactPicker, chatId: 42),
      );
      final poll = desktopUtilityWindowOptions(
        arguments(kind: DesktopUtilityWindowKind.pollComposer, chatId: 42),
      );
      final checklist = desktopUtilityWindowOptions(
        arguments(kind: DesktopUtilityWindowKind.checklistComposer, chatId: 42),
      );
      final scheduled = desktopUtilityWindowOptions(
        arguments(kind: DesktopUtilityWindowKind.scheduledMessages, chatId: 42),
      );
      final richText = desktopUtilityWindowOptions(
        arguments(kind: DesktopUtilityWindowKind.richTextComposer, chatId: 42),
      );
      final aiEditor = desktopUtilityWindowOptions(
        arguments(kind: DesktopUtilityWindowKind.aiEditor, chatId: 42),
      );
      expect(chatInfo.size, const Size(500, 700));
      expect(chatInfo.minimumSize, const Size(420, 520));
      expect(profile.size, const Size(500, 700));
      expect(profile.minimumSize, const Size(420, 520));
      expect(audio.size, const Size(640, 720));
      expect(audio.minimumSize, const Size(480, 520));
      expect(location.size, const Size(840, 720));
      expect(location.minimumSize, const Size(600, 520));
      expect(contact.size, const Size(540, 700));
      expect(contact.minimumSize, const Size(420, 500));
      expect(poll.size, const Size(680, 760));
      expect(poll.minimumSize, const Size(520, 560));
      expect(checklist.size, const Size(680, 760));
      expect(checklist.minimumSize, const Size(520, 560));
      expect(scheduled.size, const Size(720, 720));
      expect(scheduled.minimumSize, const Size(520, 500));
      expect(richText.size, const Size(920, 780));
      expect(richText.minimumSize, const Size(680, 580));
      expect(aiEditor.size, const Size(680, 720));
      expect(aiEditor.minimumSize, const Size(520, 540));
      expect(calls, contains('this.showBackButton = true'));
      expect(calls, contains('widget.showBackButton'));
      expect(media, contains('this.showBackButton = true'));
      expect(media, contains('if (widget.showBackButton)'));
    },
  );
}
