import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/telegram_mini_app_recents.dart';
import 'package:mithka/chats/search_view.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<Map<String, dynamic>> updates;
  late List<Map<String, dynamic>> requests;
  late Future<Map<String, dynamic>> Function(Map<String, dynamic>) handler;

  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) {
          requests.add(Map<String, dynamic>.from(request));
          return handler(request);
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });

  setUp(() {
    requests = [];
    handler = _categorizedSearchResponse;
  });

  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  testWidgets('inline search queries and categorizes every full-search type', (
    tester,
  ) async {
    final controller = DesktopInlineSearchController(
      miniAppSearch: (_) async => const [],
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_searchHarness(controller));

    await tester.enterText(
      find.byKey(const ValueKey('desktop-title-bar-search-input')),
      'needle',
    );
    await tester.pump(const Duration(milliseconds: 241));
    await tester.pumpAndSettle();

    final messageFilters = requests
        .where((request) => request['@type'] == 'searchMessages')
        .map(
          (request) =>
              (request['filter'] as Map<String, dynamic>)['@type'] as String,
        )
        .toSet();
    expect(messageFilters, {
      'searchMessagesFilterEmpty',
      'searchMessagesFilterPhotoAndVideo',
      'searchMessagesFilterUrl',
      'searchMessagesFilterDocument',
      'searchMessagesFilterAudio',
      'searchMessagesFilterVoiceNote',
    });
    expect(
      requests.where((request) => request['@type'] == 'searchChats'),
      hasLength(1),
    );
    expect(
      requests.where((request) => request['@type'] == 'searchContacts'),
      hasLength(1),
    );
    for (final section in const ['chats', 'posts', 'media']) {
      expect(
        find.byKey(ValueKey('desktop-inline-search-section-$section')),
        findsOneWidget,
        reason: section,
      );
    }
    final results = find.byKey(const ValueKey('desktop-inline-search-results'));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('desktop-inline-search-section-voice')),
      220,
      scrollable: find.descendant(
        of: results,
        matching: find.byType(Scrollable),
      ),
    );
    expect(
      find.byKey(const ValueKey('desktop-inline-search-section-voice')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('desktop-inline-search-panel')))
          .height,
      lessThanOrEqualTo(540),
    );
    expect(
      find.byKey(const ValueKey('desktop-inline-search-all')),
      findsOneWidget,
    );
  });

  testWidgets('stale category results cannot replace a newer query', (
    tester,
  ) async {
    final oldRequests = <Completer<Map<String, dynamic>>>[];
    handler = (request) {
      if (request['@type'] == 'searchMessages' && request['query'] == 'old') {
        final completer = Completer<Map<String, dynamic>>();
        oldRequests.add(completer);
        return completer.future;
      }
      return _categorizedSearchResponse(request);
    };
    final controller = DesktopInlineSearchController(
      miniAppSearch: (_) async => const [],
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_searchHarness(controller));

    final input = find.byKey(const ValueKey('desktop-title-bar-search-input'));
    await tester.enterText(input, 'old');
    await tester.pump(const Duration(milliseconds: 241));
    await tester.pump();
    expect(oldRequests, hasLength(12));

    await tester.enterText(input, 'new');
    for (final completer in oldRequests) {
      completer.complete({
        '@type': 'foundMessages',
        'messages': [_message(9999, text: 'old:stale')],
      });
    }
    await tester.pump();
    expect(find.textContaining('old:stale'), findsNothing);

    await tester.pump(const Duration(milliseconds: 241));
    await tester.pumpAndSettle();

    expect(find.textContaining('new:'), findsWidgets);
    expect(find.textContaining('old:stale'), findsNothing);
  });

  testWidgets('Mini Apps are capped and open the exact matching recent', (
    tester,
  ) async {
    final apps = List.generate(
      4,
      (index) => TelegramMiniAppRecent(
        title: 'Mini result $index',
        url: 'https://example.com/$index',
        botUserId: 700 + index,
        chatId: 800 + index,
        updatedAt: 900 + index,
      ),
    );
    TelegramMiniAppRecent? opened;
    final controller = DesktopInlineSearchController(
      miniAppSearch: (_) async => apps,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _searchHarness(controller, onOpenMiniApp: (app) => opened = app),
    );

    await tester.enterText(
      find.byKey(const ValueKey('desktop-title-bar-search-input')),
      'mini',
    );
    await tester.pump(const Duration(milliseconds: 241));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('desktop-inline-search-section-miniApps')),
      findsOneWidget,
    );
    expect(find.text('Mini result 0'), findsOneWidget);
    expect(find.text('Mini result 2'), findsOneWidget);
    expect(find.text('Mini result 3'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('desktop-inline-search-mini-app-701-801')),
    );
    await tester.pump();
    expect(identical(opened, apps[1]), isTrue);
  });

  testWidgets('stale Mini App results cannot replace a newer query', (
    tester,
  ) async {
    final old = Completer<List<TelegramMiniAppRecent>>();
    final newApp = _miniApp('new result', botUserId: 22, chatId: 32);
    final controller = DesktopInlineSearchController(
      miniAppSearch: (query) => query == 'old'
          ? old.future
          : Future.value(<TelegramMiniAppRecent>[newApp]),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_searchHarness(controller));
    final input = find.byKey(const ValueKey('desktop-title-bar-search-input'));

    await tester.enterText(input, 'old');
    await tester.pump(const Duration(milliseconds: 241));
    await tester.enterText(input, 'new');
    await tester.pump(const Duration(milliseconds: 241));
    await tester.pumpAndSettle();
    expect(find.text('new result'), findsOneWidget);

    old.complete([_miniApp('old stale', botUserId: 21, chatId: 31)]);
    await tester.pump();
    expect(find.text('old stale'), findsNothing);
    expect(find.text('new result'), findsOneWidget);
  });

  testWidgets('deferred searches cannot notify after controller disposal', (
    tester,
  ) async {
    final pending =
        <
          ({
            Map<String, dynamic> request,
            Completer<Map<String, dynamic>> completer,
          })
        >[];
    handler = (request) {
      final completer = Completer<Map<String, dynamic>>();
      pending.add((
        request: Map<String, dynamic>.from(request),
        completer: completer,
      ));
      return completer.future;
    };
    final miniApps = Completer<List<TelegramMiniAppRecent>>();
    final controller = DesktopInlineSearchController(
      miniAppSearch: (_) => miniApps.future,
    );
    await tester.pumpWidget(_searchHarness(controller));

    await tester.enterText(
      find.byKey(const ValueKey('desktop-title-bar-search-input')),
      'deferred',
    );
    await tester.pump(const Duration(milliseconds: 241));
    expect(pending, isNotEmpty);

    controller.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    for (final item in pending) {
      item.completer.complete(_emptySearchResponse(item.request));
    }
    miniApps.complete([_miniApp('too late', botUserId: 23, chatId: 33)]);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

Widget _searchHarness(
  DesktopInlineSearchController controller, {
  FutureOr<void> Function(TelegramMiniAppRecent app)? onOpenMiniApp,
}) => MaterialApp(
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
              onOpenMiniApp: onOpenMiniApp,
            ),
          ),
        ),
      ],
    ),
  ),
);

TelegramMiniAppRecent _miniApp(
  String title, {
  required int botUserId,
  required int chatId,
}) => TelegramMiniAppRecent(
  title: title,
  url: 'https://example.com/$botUserId',
  botUserId: botUserId,
  chatId: chatId,
  updatedAt: botUserId,
);

Map<String, dynamic> _emptySearchResponse(Map<String, dynamic> request) =>
    switch (request['@type']) {
      'searchChats' => {'@type': 'chats', 'chat_ids': <int>[]},
      'searchMessages' => {
        '@type': 'foundMessages',
        'messages': <Map<String, dynamic>>[],
      },
      _ => {'@type': 'ok'},
    };

Future<Map<String, dynamic>> _categorizedSearchResponse(
  Map<String, dynamic> request,
) async {
  final type = request['@type'];
  final query = request['query'] as String? ?? '';
  switch (type) {
    case 'searchChats':
      return {
        '@type': 'chats',
        'chat_ids': [100],
      };
    case 'searchContacts':
      return {
        '@type': 'users',
        'user_ids': [50],
      };
    case 'getUser':
      return {
        '@type': 'user',
        'id': request['user_id'],
        'first_name': 'Mao',
        'last_name': 'Contact',
        'usernames': {
          '@type': 'usernames',
          'active_usernames': ['mao_contact'],
          'disabled_usernames': <String>[],
          'editable_username': 'mao_contact',
        },
        'status': {'@type': 'userStatusOffline', 'was_online': 0},
      };
    case 'searchPublicChats':
      return {'@type': 'chats', 'chat_ids': <int>[]};
    case 'searchPublicChat':
      return {'@type': 'error', 'code': 404, 'message': 'not found'};
    case 'searchMessages':
      final list = request['chat_list'] as Map<String, dynamic>?;
      if (list?['@type'] == 'chatListArchive') {
        return {'@type': 'foundMessages', 'messages': <Map<String, dynamic>>[]};
      }
      final filter =
          (request['filter'] as Map<String, dynamic>)['@type'] as String;
      final index = _filters.indexOf(filter);
      return {
        '@type': 'foundMessages',
        'messages': [
          _message(1000 + index, text: '$query:${_sectionNames[index]}'),
        ],
      };
    case 'getChat':
      final chatId = request['chat_id'] as int;
      return {
        '@type': 'chat',
        'id': chatId,
        'title': chatId == 100 ? 'Needle chat' : 'Search source',
        'type': {
          '@type': 'chatTypePrivate',
          'user_id': chatId == 100 ? 50 : 51,
        },
        'positions': <Map<String, dynamic>>[],
        'unread_count': 0,
      };
  }
  return {'@type': 'ok'};
}

const _filters = [
  'searchMessagesFilterEmpty',
  'searchMessagesFilterPhotoAndVideo',
  'searchMessagesFilterUrl',
  'searchMessagesFilterDocument',
  'searchMessagesFilterAudio',
  'searchMessagesFilterVoiceNote',
];

const _sectionNames = ['posts', 'media', 'links', 'files', 'music', 'voice'];

Map<String, dynamic> _message(int id, {required String text}) => {
  '@type': 'message',
  'id': id,
  'chat_id': 200,
  'date': id,
  'is_outgoing': false,
  'sender_id': {'@type': 'messageSenderUser', 'user_id': 50},
  'content': {
    '@type': 'messageText',
    'text': {
      '@type': 'formattedText',
      'text': text,
      'entities': <Map<String, dynamic>>[],
    },
  },
};
