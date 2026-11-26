//
//  unread_activity_menu_test.dart
//
//  The floating @ / reaction pills inside a chat keep their tap-to-jump
//  behavior. Long press on @ opens the narrow anchored "Mark all as read"
//  menu (the reference client's ReadAllMentionsMenu over the chat's side control, not a
//  bottom sheet); long press on the reaction pill clears reactions directly,
//  exactly like the reference client's side control.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/chat/chat_view.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/ai_translation/translation_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chatId = 990001;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final updates = StreamController<Map<String, dynamic>>.broadcast();
  final queries = <Map<String, dynamic>>[];
  var mentionCount = 2;
  var reactionCount = 1;

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          queries.add(request);
          switch (request['@type']) {
            case 'getChat':
              return {
                '@type': 'chat',
                'id': _chatId,
                'type': {'@type': 'chatTypePrivate', 'user_id': 5},
                'title': 'Alice',
                'unread_count': 0,
                'unread_mention_count': mentionCount,
                'unread_reaction_count': reactionCount,
                'permissions': {'can_send_basic_messages': true},
              };
            case 'getUser':
              return {
                '@type': 'user',
                'id': 5,
                'first_name': 'Alice',
                'status': {'@type': 'userStatusRecently'},
              };
            case 'getUserFullInfo':
              return {'@type': 'userFullInfo'};
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

  setUp(() {
    queries.clear();
    mentionCount = 2;
    reactionCount = 1;
  });

  Future<void> openChat(WidgetTester tester) async {
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
        'id': _chatId,
        'type': {'@type': 'chatTypePrivate', 'user_id': 5},
        'title': 'Alice',
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

    await tester.tap(find.text('Alice'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ChatView), findsOneWidget);
  }

  testWidgets('mention long press opens a menu, reaction long press clears', (
    tester,
  ) async {
    await openChat(tester);

    final mentionPill = find.byKey(const ValueKey('unread-mention-indicator'));
    final reactionPill = find.byKey(
      const ValueKey('unread-reaction-indicator'),
    );
    expect(mentionPill, findsOneWidget);
    expect(reactionPill, findsOneWidget);

    await tester.longPress(mentionPill);
    await tester.pumpAndSettle();
    final menu = find.byKey(const ValueKey('app-anchored-menu'));
    expect(menu, findsOneWidget);
    expect(
      find.byKey(const ValueKey('app-anchored-menu-read-all-mentions')),
      findsOneWidget,
    );
    expect(find.text('Mark all as read'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('app-anchored-menu-read-all-mentions')),
    );
    await tester.pumpAndSettle();
    final mentionRead = queries.lastWhere(
      (request) => request['@type'] == 'readAllChatMentions',
    );
    expect(mentionRead['chat_id'], _chatId);
    // Marking mentions read leaves the reaction pill untouched.
    expect(mentionPill, findsNothing);
    expect(reactionPill, findsOneWidget);

    // No menu for reactions: the long press is the command.
    await tester.longPress(reactionPill);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-anchored-menu')), findsNothing);
    final reactionRead = queries.lastWhere(
      (request) => request['@type'] == 'readAllChatReactions',
    );
    expect(reactionRead['chat_id'], _chatId);
    expect(reactionPill, findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
  });
}
