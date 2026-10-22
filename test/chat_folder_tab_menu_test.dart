import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/chat/chat_picker_view.dart';
import 'package:mithka/chats/chat_folder_tab_menu.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/components/drawer_controller.dart' as dc;
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/chat_folder_management_view.dart';
import 'package:mithka/settings/chat_folder_service.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Packed ids: TDLib server ids carry `server_id << 20` in the low bits.
const int _shift = 20;

/// Set by the reorder-failure test so the fake transport can reject a save.
var _failReorder = false;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<Map<String, dynamic>> updates;
  final requests = <Map<String, dynamic>>[];

  setUpAll(() async {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          requests.add({...request});
          return _response(request);
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
    updates.add({
      '@type': 'updateConnectionState',
      'state': {'@type': 'connectionStateReady'},
    });
    await Future<void>.delayed(Duration.zero);
  });

  setUp(() async {
    requests.clear();
    _failReorder = false;
    updates.add(_foldersUpdate);
    await Future<void>.delayed(Duration.zero);
  });

  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  testWidgets('long press opens the four folder actions', (tester) async {
    await _pumpChatList(tester);

    await tester.longPress(find.text('Work'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('chat-folder-action-sheet')),
      findsOneWidget,
    );
    for (final key in const ['edit', 'add-chat', 'mark-read', 'reorder']) {
      expect(
        find.byKey(ValueKey('chat-folder-action-$key')),
        findsOneWidget,
        reason: 'the folder sheet always offers every folder command',
      );
    }
    expect(find.text('Edit folder'), findsOneWidget);
    expect(find.text('Add chat'), findsOneWidget);
    expect(find.text('Mark all as read'), findsOneWidget);
    expect(find.text('Reorder folders'), findsOneWidget);

    // Dismissing the sheet leaves the strip's tap-to-select intact.
    await tester.tapAt(const Offset(12, 12));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('chat-folder-action-sheet')),
      findsNothing,
    );
    await tester.tap(find.text('Family'));
    await tester.pumpAndSettle();
    expect(
      requests.any(
        (request) =>
            request['@type'] == 'getChats' &&
            (request['chat_list'] as Map?)?['chat_folder_id'] == 8,
      ),
      isTrue,
      reason: 'a tap still switches the selected folder',
    );
    await _disposeShell(tester);
  });

  testWidgets('the all chats tab offers only mark all read and reorder', (
    tester,
  ) async {
    await _pumpChatList(tester);

    await tester.longPress(find.text('All'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('chat-folder-action-mark-read')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chat-folder-action-reorder')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chat-folder-action-edit')), findsNothing);
    expect(
      find.byKey(const ValueKey('chat-folder-action-add-chat')),
      findsNothing,
    );
    await _disposeShell(tester);
  });

  testWidgets('edit folder opens the full folder editor', (tester) async {
    await _pumpChatList(tester);

    await tester.longPress(find.text('Work'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-folder-action-edit')));
    await tester.pumpAndSettle();

    expect(find.byType(ChatFolderEditorView), findsOneWidget);
    expect(
      requests
          .where((request) => request['@type'] == 'getChatFolder')
          .map((request) => request['chat_folder_id']),
      contains(7),
    );
    await _disposeShell(tester);
  });

  testWidgets('add chat merges the picked chat into included ids', (
    tester,
  ) async {
    await _pumpChatList(tester);

    await tester.longPress(find.text('Work'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-folder-action-add-chat')));
    await tester.pumpAndSettle();
    expect(find.byType(ChatPickerView), findsOneWidget);

    await tester.tap(find.text('Picked chat'));
    await tester.pumpAndSettle();

    final edit = requests.singleWhere(
      (request) => request['@type'] == 'editChatFolder',
    );
    expect(edit['chat_folder_id'], 7);
    final folder = edit['folder'] as Map;
    expect(folder['included_chat_ids'], [301, 501]);
    expect(
      folder['excluded_chat_ids'],
      isEmpty,
      reason: 'an included chat stops being explicitly excluded',
    );
    await _disposeShell(tester);
  });

  testWidgets(
    'mark all read reads the folder through getChats and viewMessages',
    (tester) async {
      await _pumpChatList(tester);

      await tester.longPress(find.text('Work'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('chat-folder-action-mark-read')),
      );
      await tester.pumpAndSettle();

      expect(
        requests.any((request) {
          final list = request['chat_list'];
          return request['@type'] == 'getChats' &&
              list is Map &&
              list['@type'] == 'chatListFolder' &&
              list['chat_folder_id'] == 7;
        }),
        isTrue,
        reason: 'the folder is enumerated, not the selected chat list',
      );
      expect(
        requests
            .where((request) => request['@type'] == 'viewMessages')
            .toList(),
        [
          {
            '@type': 'viewMessages',
            'chat_id': 201,
            'message_ids': [5 << _shift],
            'force_read': true,
          },
        ],
        reason: 'only the unread chat is read, at its own newest message',
      );
      await _disposeShell(tester);
    },
  );

  testWidgets(
    'the all chats tab clears main-list chats the selected folder hides',
    (tester) async {
      await _pumpChatList(tester);

      // Look at Work first: the All-tab command must not inherit its scope.
      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('All'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('chat-folder-action-mark-read')),
      );
      await tester.pumpAndSettle();

      final reads = requests
          .where((request) => request['@type'] == 'viewMessages')
          .toList();
      expect(
        reads.map((request) => request['chat_id']),
        [301],
        reason: 'All is the account main list, not the folder on screen',
      );
      expect(reads.single['message_ids'], [9 << _shift]);
      await _disposeShell(tester);
    },
  );

  testWidgets('reorder saves the folder order with the main list position', (
    tester,
  ) async {
    await _pumpChatList(tester);

    await tester.longPress(find.text('Work'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-folder-action-reorder')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('chat-folder-reorder-sheet')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chat-folder-order-7')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chat-folder-order-main')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chat-folder-order-8')), findsOneWidget);
    expect(find.text('All chats'), findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('chat-folder-order-8'))),
    );
    await tester.pump();
    for (var step = 0; step < 6; step++) {
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 20));
    }

    // Mid-drag the lifted row rides an owned proxy: a DecoratedBox carrying the
    // sheet's shadow, never a Material surface that would paint its own
    // elevation over it.
    final proxy = find.byKey(const ValueKey('chat-folder-reorder-proxy'));
    expect(proxy, findsOneWidget);
    expect(
      find.descendant(of: proxy, matching: find.byType(Material)),
      findsNothing,
      reason: 'the drag proxy must not be Material chrome',
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(proxy, findsNothing);

    final reorder = requests.singleWhere(
      (request) => request['@type'] == 'reorderChatFolders',
    );
    expect(reorder['chat_folder_ids'], [8, 7]);
    expect(reorder['main_chat_list_position'], 2);
    await _disposeShell(tester);
  });

  testWidgets('a reorder from a sheet whose account is gone saves nothing', (
    tester,
  ) async {
    final reorders = <Map<String, dynamic>>[];
    var ownerCurrent = false;
    final service = ChatFolderService(
      query: (request) async {
        reorders.add({...request});
        return {'@type': 'ok'};
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatFolderReorderSheet(
            folders: const [
              ChatFolderRecord(
                id: 7,
                title: 'Work',
                raw: <String, dynamic>{},
                hasInviteLinks: false,
              ),
              ChatFolderRecord(
                id: 8,
                title: 'Family',
                raw: <String, dynamic>{},
                hasInviteLinks: false,
              ),
            ],
            mainListPosition: 0,
            service: service,
            canSave: () => ownerCurrent,
          ),
        ),
      ),
    );

    Future<void> drag() async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('chat-folder-order-8'))),
      );
      await tester.pump();
      for (var step = 0; step < 6; step++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    await drag();
    expect(
      reorders,
      isEmpty,
      reason: 'an account that is gone takes no folder order with it',
    );
    final restoredFirst = tester.getTopLeft(
      find.byKey(const ValueKey('chat-folder-order-7')),
    );
    final restoredSecond = tester.getTopLeft(
      find.byKey(const ValueKey('chat-folder-order-8')),
    );
    expect(
      restoredFirst.dy,
      lessThan(restoredSecond.dy),
      reason: 'the drop is reverted like a rejected save',
    );

    // The same sheet saves once its account is current again.
    ownerCurrent = true;
    await drag();
    expect(reorders.single['chat_folder_ids'], [8, 7]);
  });

  testWidgets('a failed reorder restores the previous row order', (
    tester,
  ) async {
    _failReorder = true;
    await _pumpChatList(tester);

    await tester.longPress(find.text('Work'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-folder-action-reorder')));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('chat-folder-order-8'))),
    );
    await tester.pump();
    for (var step = 0; step < 6; step++) {
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final first = tester.getTopLeft(
      find.byKey(const ValueKey('chat-folder-order-7')),
    );
    final second = tester.getTopLeft(
      find.byKey(const ValueKey('chat-folder-order-8')),
    );
    expect(
      first.dy,
      lessThan(second.dy),
      reason: 'the failed save puts Work back above Family',
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await _disposeShell(tester);
  });
}

Future<void> _pumpChatList(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'showChannelsTab': false,
    'showMomentsTab': false,
    'communitiesEnabled': false,
    'chatFolderDisplayMode': 'tabs',
  });
  final prefs = await SharedPreferences.getInstance();
  final theme = ThemeController(prefs);
  final accounts = AccountStore(prefs);
  final auth = AuthManager();
  final drawer = dc.DrawerController();
  addTearDown(theme.dispose);
  addTearDown(accounts.dispose);
  addTearDown(auth.dispose);
  addTearDown(drawer.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<AccountStore>.value(value: accounts),
        ChangeNotifierProvider<AuthManager>.value(value: auth),
        ChangeNotifierProvider<dc.DrawerController>.value(value: drawer),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: [AppColors.light],
        ),
        home: const Scaffold(body: ChatListView()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _disposeShell(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // The chat list schedules delayed cache warm-ups after disposal.
  await tester.pump(const Duration(seconds: 6));
  await tester.pump();
}

final Map<String, dynamic> _foldersUpdate = {
  '@type': 'updateChatFolders',
  'chat_folders': [_folderInfo(7, 'Work'), _folderInfo(8, 'Family')],
  'main_chat_list_position': 1,
  'are_tags_enabled': false,
};

Map<String, dynamic> _folderInfo(int id, String title) => {
  '@type': 'chatFolderInfo',
  'id': id,
  'name': {
    '@type': 'chatFolderName',
    'text': {'@type': 'formattedText', 'text': title},
    'animate_custom_emoji': false,
  },
  'icon': {'@type': 'chatFolderIcon', 'name': 'Custom'},
  'color_id': -1,
  'is_shareable': false,
  'has_my_invite_links': false,
};

Map<String, dynamic> _folderRaw(int id) => {
  '@type': 'chatFolder',
  'name': {
    '@type': 'chatFolderName',
    'text': {'@type': 'formattedText', 'text': id == 7 ? 'Work' : 'Family'},
    'animate_custom_emoji': false,
  },
  'icon': {'@type': 'chatFolderIcon', 'name': 'Custom'},
  'color_id': -1,
  'is_shareable': false,
  'pinned_chat_ids': <int>[],
  'included_chat_ids': id == 7 ? const <int>[501] : const <int>[],
  'excluded_chat_ids': id == 7 ? const <int>[301] : const <int>[],
  'exclude_muted': false,
  'exclude_read': false,
  'exclude_archived': false,
  'include_contacts': false,
  'include_non_contacts': false,
  'include_bots': false,
  'include_groups': false,
  'include_channels': false,
};

Map<String, dynamic> _chat(
  int id,
  String title, {
  int unread = 0,
  int lastMessageId = 0,
  bool inFolder = false,
}) => {
  '@type': 'chat',
  'id': id,
  'title': title,
  'type': {'@type': 'chatTypePrivate', 'user_id': id + 1000},
  'unread_count': unread,
  'is_marked_as_unread': false,
  'last_read_inbox_message_id': 0,
  'positions': [
    {
      '@type': 'chatPosition',
      'list': {'@type': 'chatListMain'},
      'order': 1700000000,
    },
    if (inFolder)
      {
        '@type': 'chatPosition',
        'list': {'@type': 'chatListFolder', 'chat_folder_id': 7},
        'order': 1700000000,
      },
  ],
  'notification_settings': {
    '@type': 'chatNotificationSettings',
    'use_default_mute_for': true,
    'use_default_sound': true,
    'use_default_show_preview': true,
    'use_default_mute_stories': true,
    'use_default_story_sound': true,
    'use_default_show_story_poster': true,
    'use_default_disable_pinned_message_notifications': true,
    'use_default_disable_mention_notifications': true,
  },
  if (lastMessageId > 0)
    'last_message': {
      '@type': 'message',
      'id': lastMessageId,
      'chat_id': id,
      'date': 1700000000,
      'is_outgoing': false,
      'sender_id': {'@type': 'messageSenderUser', 'user_id': 42},
      'content': {
        '@type': 'messageText',
        'text': {'@type': 'formattedText', 'text': 'Hello'},
      },
    },
};

Map<String, dynamic> _response(Map<String, dynamic> request) {
  switch (request['@type']) {
    case 'loadChats':
      // As in production: TDLib answers 404 once the list is fully loaded.
      throw TdError({'code': 404, 'message': 'Not Found'});
    case 'getChats':
      final list = request['chat_list'];
      final type = list is Map ? list['@type'] : null;
      if (type == 'chatListFolder') {
        final ids = list['chat_folder_id'] == 7
            ? const <int>[201, 202]
            : const <int>[];
        return {'@type': 'chats', 'total_count': ids.length, 'chat_ids': ids};
      }
      if (type == 'chatListArchive') {
        return {'@type': 'chats', 'total_count': 0, 'chat_ids': const <int>[]};
      }
      return {
        '@type': 'chats',
        'total_count': 1,
        'chat_ids': const <int>[301],
      };
    case 'getChat':
      final id = request['chat_id'] as int;
      return switch (id) {
        201 => _chat(
          201,
          'Unread chat',
          unread: 2,
          lastMessageId: 5 << _shift,
          inFolder: true,
        ),
        202 => _chat(202, 'Read chat', inFolder: true),
        301 => _chat(301, 'Picked chat', unread: 1, lastMessageId: 9 << _shift),
        _ => _chat(id, 'Chat $id'),
      };
    case 'getChatFolder':
      return _folderRaw(request['chat_folder_id'] as int);
    case 'getContacts':
      return {'@type': 'users', 'user_ids': const <int>[]};
    case 'getMe':
      return {'@type': 'user', 'id': 1, 'first_name': 'Test'};
    case 'reorderChatFolders':
      if (_failReorder) throw StateError('offline');
      return {'@type': 'ok'};
    default:
      return {'@type': 'ok'};
  }
}
