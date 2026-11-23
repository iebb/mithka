//
//  topic_selector_sheet_test.dart
//
//  The topic list behind the header's # button reads the same ordered list as
//  the strip above the transcript: newest activity first (pinned first when
//  any), live while the sheet is open — and it marks the transcript the user
//  is already in, so a forum with many topics shows "you are here".
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _forumChatId = -1005678;

Map<String, dynamic> _topic(int id, String name, {int lastMessageId = 0}) => {
  '@type': 'forumTopic',
  'info': {
    '@type': 'forumTopicInfo',
    'forum_topic_id': id,
    'name': name,
    'icon': {'@type': 'forumTopicIcon', 'color': 0x6FB9F0},
  },
  'unread_count': 0,
  'is_pinned': false,
  'last_message': {
    '@type': 'message',
    'id': lastMessageId,
    'chat_id': _forumChatId,
    'date': 1700000000 + lastMessageId,
    'is_outgoing': false,
    'sender_id': {'@type': 'messageSenderUser', 'user_id': 5},
    'content': {
      '@type': 'messageText',
      'text': {'@type': 'formattedText', 'text': 'last in $name'},
    },
  },
};

Finder _row(String id) => find.byKey(ValueKey('topic-selector-row-$id'));

Finder _checkIn(Finder row) =>
    find.descendant(of: row, matching: find.byIcon(HeroAppIcons.check.data));

Finder _railIn(Finder row) => find.descendant(
  of: row,
  matching: find.byKey(ChatListSelectionHighlight.railKey),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final updates = StreamController<Map<String, dynamic>>.broadcast();

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          switch (request['@type']) {
            case 'getChat':
              return {
                '@type': 'chat',
                'id': _forumChatId,
                'type': {'@type': 'chatTypeSupergroup', 'supergroup_id': 5678},
                'title': 'Forum Group',
                'unread_count': 0,
                'permissions': {'can_send_basic_messages': true},
              };
            case 'getSupergroup':
              return {
                '@type': 'supergroup',
                'id': 5678,
                'is_forum': true,
                'status': {'@type': 'chatMemberStatusMember'},
              };
            case 'getSupergroupFullInfo':
              return {'@type': 'supergroupFullInfo', 'member_count': 8};
            case 'getForumTopics':
              return {
                '@type': 'forumTopics',
                'topics': [
                  _topic(1, 'General', lastMessageId: 10),
                  _topic(50, 'Announcements', lastMessageId: 500),
                ],
                'total_count': 2,
              };
            case 'getMe':
              return {'@type': 'user', 'id': 1, 'first_name': 'Test'};
            default:
              return {'@type': 'ok'};
          }
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  testWidgets('the topic list orders live and marks the open topic', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'communitiesEnabled': false});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    final accounts = AccountStore(prefs);
    final auth = AuthManager();
    final translation = TranslationController(prefs);
    addTearDown(theme.dispose);
    addTearDown(accounts.dispose);
    addTearDown(auth.dispose);
    addTearDown(translation.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>.value(value: theme),
          ChangeNotifierProvider<AccountStore>.value(value: accounts),
          ChangeNotifierProvider<AuthManager>.value(value: auth),
          ChangeNotifierProvider<TranslationController>.value(
            value: translation,
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppColors.light]),
          home: const Scaffold(body: ChatListView()),
        ),
      ),
    );

    updates.add({
      '@type': 'updateConnectionState',
      'state': {'@type': 'connectionStateReady'},
    });
    updates.add({
      '@type': 'updateNewChat',
      'chat': {
        '@type': 'chat',
        'id': _forumChatId,
        'type': {'@type': 'chatTypeSupergroup', 'supergroup_id': 5678},
        'title': 'Forum Group',
        'is_forum': true,
        'positions': [
          {
            '@type': 'chatPosition',
            'list': {'@type': 'chatListMain'},
            'order': 100,
          },
        ],
      },
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Forum Group'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // The # button opens the topic list sheet.
    await tester.tap(find.byKey(const ValueKey('chatHeaderTopics')));
    await tester.pumpAndSettle();

    expect(_row('all'), findsOneWidget);
    expect(_row('1'), findsOneWidget);
    expect(_row('50'), findsOneWidget);

    // Newest activity first: Announcements (last message 500) above General
    // (10); the All pseudo-row always leads the sheet.
    expect(
      tester.getTopLeft(_row('all')).dy,
      lessThan(tester.getTopLeft(_row('50')).dy),
    );
    expect(
      tester.getTopLeft(_row('50')).dy,
      lessThan(tester.getTopLeft(_row('1')).dy),
    );

    // The forum opened on All, so All is the marked row.
    expect(_checkIn(_row('all')), findsOneWidget);
    expect(_railIn(_row('all')), findsOneWidget);
    expect(_checkIn(_row('50')), findsNothing);
    expect(_railIn(_row('50')), findsNothing);

    // Switching into a topic closes the sheet; reopening marks that topic.
    await tester.tap(_row('50'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('topic-selector-list')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('chatHeaderTopics')));
    await tester.pumpAndSettle();
    expect(_checkIn(_row('50')), findsOneWidget);
    expect(_railIn(_row('50')), findsOneWidget);
    expect(_checkIn(_row('all')), findsNothing);

    // A message in General moves it above Announcements while the sheet is
    // open, and the marked row stays on the open topic.
    updates.add({
      '@type': 'updateNewMessage',
      'message': {
        '@type': 'message',
        'id': 9000,
        'chat_id': _forumChatId,
        'date': 1700009999,
        'is_outgoing': false,
        'sender_id': {'@type': 'messageSenderUser', 'user_id': 5},
        'topic_id': {'@type': 'messageTopicForum', 'forum_topic_id': 1},
        'content': {
          '@type': 'messageText',
          'text': {'@type': 'formattedText', 'text': 'fresh'},
        },
      },
    });
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(_row('1')).dy,
      lessThan(tester.getTopLeft(_row('50')).dy),
      reason: 'the sheet keeps the strip order as traffic lands',
    );
    expect(_checkIn(_row('50')), findsOneWidget);
    expect(_checkIn(_row('1')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
  });
}
