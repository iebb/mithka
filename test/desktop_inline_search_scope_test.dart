import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/active_conversation.dart';
import 'package:mithka/chat/chat_search_query.dart';
import 'package:mithka/chats/search_view.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';

const _scope = ActiveConversationScope(chatId: 100, title: 'Needle chat');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<Map<String, dynamic>> updates;
  late List<Map<String, dynamic>> requests;

  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) {
          requests.add(Map<String, dynamic>.from(request));
          return _response(request);
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });

  setUp(() => requests = []);

  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  group('ActiveConversation', () {
    tearDown(ActiveConversation.shared.clearForTesting);

    test('reports only a visible conversation', () {
      var visible = false;
      ActiveConversation.shared.register(
        'owner',
        chatId: 7,
        title: () => 'Parked chat',
        isVisible: () => visible,
      );
      expect(ActiveConversation.shared.current, isNull);

      visible = true;
      expect(ActiveConversation.shared.current?.chatId, 7);
      expect(ActiveConversation.shared.current?.title, 'Parked chat');
    });

    test('the most recently registered visible conversation wins', () {
      ActiveConversation.shared.register(
        'first',
        chatId: 1,
        title: () => 'First',
        isVisible: () => true,
      );
      ActiveConversation.shared.register(
        'second',
        chatId: 2,
        title: () => 'Second',
        isVisible: () => true,
      );
      expect(ActiveConversation.shared.current?.chatId, 2);

      ActiveConversation.shared.unregister('second');
      expect(ActiveConversation.shared.current?.chatId, 1);
    });

    test('a title that loads late is read at lookup time', () {
      var title = 'Placeholder';
      ActiveConversation.shared.register(
        'owner',
        chatId: 3,
        title: () => title,
        isVisible: () => true,
      );
      title = 'Resolved peer';
      expect(ActiveConversation.shared.current?.title, 'Resolved peer');
    });
  });

  testWidgets('focusing from a chat scopes the query to that chat', (
    tester,
  ) async {
    final controller = DesktopInlineSearchController(
      miniAppSearch: (_) async => const [],
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_harness(controller));

    controller.focus(scope: _scope);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('desktop-title-bar-search-scope')),
      findsOneWidget,
    );
    expect(find.text('Needle chat'), findsOneWidget);

    await _type(tester, 'needle');

    expect(
      requests.where((request) => request['@type'] == 'searchMessages'),
      isEmpty,
      reason: 'a scoped search must not fan out across every chat list',
    );
    final scoped = requests
        .where((request) => request['@type'] == 'searchChatMessages')
        .toList();
    expect(scoped, isNotEmpty);
    expect(scoped.every((request) => request['chat_id'] == 100), isTrue);
    expect(
      requests.where((request) => request['@type'] == 'searchChats'),
      isEmpty,
      reason: 'a chat-scoped search has no chat hits to offer',
    );
    expect(
      find.byKey(const ValueKey('desktop-inline-search-section-chats')),
      findsNothing,
    );
  });

  testWidgets('removing the chip widens the search again', (tester) async {
    final controller = DesktopInlineSearchController(
      miniAppSearch: (_) async => const [],
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_harness(controller));

    controller.focus(scope: _scope);
    await tester.pump();
    await _type(tester, 'needle');
    requests.clear();

    await tester.tap(
      find.byKey(const ValueKey('desktop-title-bar-search-scope-remove')),
    );
    await tester.pump(const Duration(milliseconds: 241));
    await tester.pumpAndSettle();

    expect(controller.scope, isNull);
    expect(
      find.byKey(const ValueKey('desktop-title-bar-search-scope')),
      findsNothing,
    );
    expect(
      requests.where((request) => request['@type'] == 'searchMessages'),
      isNotEmpty,
    );
    expect(
      requests.where((request) => request['@type'] == 'searchChatMessages'),
      isEmpty,
    );
  });

  testWidgets('dismissing ends the scoped session', (tester) async {
    final controller = DesktopInlineSearchController(
      miniAppSearch: (_) async => const [],
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_harness(controller));

    controller.focus(scope: _scope);
    await tester.pump();
    await _type(tester, 'needle');

    controller.dismiss();
    await tester.pump();

    expect(controller.scope, isNull);
    // Re-focusing without a scope must not resurrect the old one.
    controller.focus();
    await tester.pump();
    expect(controller.scope, isNull);
  });

  testWidgets('an unscoped from: searches the chats shared with that person', (
    tester,
  ) async {
    final controller = DesktopInlineSearchController(
      miniAppSearch: (_) async => const [],
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_harness(controller));

    await _type(tester, 'from:@mao receipt');

    // TDLib cannot filter a chat-list search by sender, so it runs per chat.
    expect(
      requests.where((request) => request['@type'] == 'searchMessages'),
      isEmpty,
    );
    final scoped = requests
        .where((request) => request['@type'] == 'searchChatMessages')
        .toList();
    expect(scoped, isNotEmpty);
    final chatIds = scoped.map((request) => request['chat_id']).toSet();
    // The private chat carries the user's own id, and the groups in common
    // come from getGroupsInCommon.
    expect(chatIds, containsAll(<int>[55, 900]));
    expect(
      scoped.every(
        (request) =>
            (request['sender_id'] as Map<String, dynamic>)['user_id'] == 55,
      ),
      isTrue,
    );
    expect(scoped.every((request) => request['query'] == 'receipt'), isTrue);
    expect(
      find.byKey(const ValueKey('desktop-title-bar-search-from')),
      findsNothing,
      reason: 'typing a resolvable user must not silently commit a badge',
    );
  });

  testWidgets('an empty focused field shows filter hints only while empty', (
    tester,
  ) async {
    final controller = DesktopInlineSearchController(
      miniAppSearch: (_) async => const [],
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_harness(controller));

    controller.focus();
    await tester.pump();

    expect(find.byKey(const ValueKey('searchTokenHints')), findsOneWidget);
    expect(find.byKey(const ValueKey('searchTokenHint-from:')), findsOneWidget);
    expect(find.byKey(const ValueKey('searchTokenHint-in:')), findsOneWidget);
    expect(find.byKey(const ValueKey('searchTokenHint-has:')), findsOneWidget);

    await _type(tester, 'receipt');
    expect(find.byKey(const ValueKey('searchTokenHints')), findsNothing);

    controller.clear();
    await tester.pump();
    expect(find.byKey(const ValueKey('searchTokenHints')), findsOneWidget);

    controller.dismiss();
    await tester.pump();
    expect(find.byKey(const ValueKey('searchTokenHints')), findsNothing);
  });

  testWidgets('tapping a from suggestion commits its badge and removes text', (
    tester,
  ) async {
    final controller = DesktopInlineSearchController(
      miniAppSearch: (_) async => const [],
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_harness(controller));

    await _type(tester, 'from:@mao');
    expect(
      find.byKey(const ValueKey('desktop-title-bar-search-from')),
      findsNothing,
    );

    requests.clear();
    await tester.tap(find.byKey(const ValueKey('searchTokenSuggestion-55')));
    await tester.pump(const Duration(milliseconds: 241));
    await tester.pumpAndSettle();

    expect(controller.textController.text, isEmpty);
    expect(controller.resolvedSender?.id, 55);
    expect(
      find.byKey(const ValueKey('desktop-title-bar-search-from')),
      findsOneWidget,
    );
    expect(controller.panelVisible, isTrue);
    expect(
      find.byKey(const ValueKey('desktop-inline-search-section-posts')),
      findsOneWidget,
    );

    final senderSearches = requests
        .where((request) => request['@type'] == 'searchChatMessages')
        .toList();
    expect(senderSearches, isNotEmpty);
    expect(
      senderSearches.map((request) => request['chat_id']).toSet(),
      containsAll(<int>[55, 900]),
      reason: 'sender-only search includes the private chat and shared groups',
    );
    expect(senderSearches.every((request) => request['query'] == ''), isTrue);
    expect(
      senderSearches.every(
        (request) =>
            (request['sender_id'] as Map<String, dynamic>)['user_id'] == 55,
      ),
      isTrue,
    );
  });

  testWidgets('typing in: offers chats to pick from', (tester) async {
    final controller = DesktopInlineSearchController(
      miniAppSearch: (_) async => const [],
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_harness(controller));

    await _type(tester, 'in:need');

    expect(controller.activeToken?.kind, ChatSearchTokenKind.chat);
    expect(
      find.byKey(const ValueKey('searchTokenSuggestions')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('searchTokenSuggestion-100')));
    await tester.pumpAndSettle();

    // Picking commits the token to a badge and takes its text out of the
    // field, so the filter is stated once rather than twice.
    expect(controller.textController.text, isEmpty);
    expect(controller.activeToken, isNull);
    expect(controller.scope?.chatId, 100);
    expect(
      find.byKey(const ValueKey('desktop-title-bar-search-scope')),
      findsOneWidget,
    );
  });
}

Future<void> _type(WidgetTester tester, String query) async {
  await tester.enterText(
    find.byKey(const ValueKey('desktop-title-bar-search-input')),
    query,
  );
  await tester.pump(const Duration(milliseconds: 241));
  await tester.pumpAndSettle();
}

Widget _harness(DesktopInlineSearchController controller) => MaterialApp(
  theme: ThemeData(extensions: [AppColors.light]),
  home: Scaffold(
    body: Column(
      children: [
        DesktopInlineSearchField(controller: controller, onSearchAll: (_) {}),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: DesktopInlineSearchPanel(
              controller: controller,
              onSearchAll: (_) {},
            ),
          ),
        ),
      ],
    ),
  ),
);

Future<Map<String, dynamic>> _response(Map<String, dynamic> request) async {
  switch (request['@type']) {
    case 'searchChats':
      return {
        '@type': 'chats',
        'chat_ids': [100],
      };
    case 'searchContacts':
      return {'@type': 'users', 'user_ids': <int>[]};
    case 'searchPublicChats':
      return {'@type': 'chats', 'chat_ids': <int>[]};
    case 'searchMessages':
    case 'searchChatMessages':
      return {
        '@type': 'foundMessages',
        'messages': [_message(1000)],
      };
    case 'getGroupsInCommon':
      return {
        '@type': 'chats',
        'chat_ids': [900],
      };
    case 'searchPublicChat':
      return {
        '@type': 'chat',
        'id': 55,
        'title': 'Mao Contact',
        'type': {'@type': 'chatTypePrivate', 'user_id': 55},
        'positions': <Map<String, dynamic>>[],
        'unread_count': 0,
      };
    case 'getChat':
      return {
        '@type': 'chat',
        'id': request['chat_id'],
        'title': 'Needle chat',
        'type': {'@type': 'chatTypePrivate', 'user_id': 50},
        'positions': <Map<String, dynamic>>[],
        'unread_count': 0,
      };
  }
  return {'@type': 'ok'};
}

Map<String, dynamic> _message(int id) => {
  '@type': 'message',
  'id': id,
  'chat_id': 100,
  'date': id,
  'is_outgoing': false,
  'sender_id': {'@type': 'messageSenderUser', 'user_id': 50},
  'content': {
    '@type': 'messageText',
    'text': {
      '@type': 'formattedText',
      'text': 'needle in a haystack',
      'entities': <Map<String, dynamic>>[],
    },
  },
};
