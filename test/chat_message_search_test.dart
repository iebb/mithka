import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_message_search_bar.dart';
import 'package:mithka/chat/chat_message_search_controller.dart';
import 'package:mithka/chat/chat_search_query.dart';
import 'package:mithka/chat/chat_search_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';

const _chatId = -100200;
const _debounce = Duration(milliseconds: 281);

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
    handler = (request) async => _defaultResponse(request);
  });

  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  group('layout', () {
    test('a wide conversation lists hits beside the transcript', () {
      expect(
        chatSearchUsesResultsPane(
          windowSize: const Size(1440, 900),
          conversationWidth: 900,
          platform: TargetPlatform.macOS,
          isWeb: false,
        ),
        isTrue,
      );
    });

    test('a narrow conversation keeps the full width for the transcript', () {
      // Wide window, but the conversation column itself has no room to give.
      expect(
        chatSearchUsesResultsPane(
          windowSize: const Size(1440, 900),
          conversationWidth: 600,
          platform: TargetPlatform.macOS,
          isWeb: false,
        ),
        isFalse,
      );
      expect(
        chatSearchUsesResultsPane(
          windowSize: const Size(390, 844),
          conversationWidth: 390,
          platform: TargetPlatform.iOS,
          isWeb: false,
        ),
        isFalse,
      );
    });
  });

  group('highlight spans', () {
    test('weights every occurrence of the query', () {
      final spans = chatSearchHighlightSpans(
        text: 'a Needle and a needle',
        query: 'needle',
        matchStyle: const TextStyle(fontWeight: FontWeight.w600),
      );
      final matched = spans
          .whereType<TextSpan>()
          .where((span) => span.style != null)
          .map((span) => span.text)
          .toList();
      expect(matched, ['Needle', 'needle']);
    });

    test('an unmatched snippet stays one plain span', () {
      final spans = chatSearchHighlightSpans(
        text: 'nothing here',
        query: 'needle',
        matchStyle: const TextStyle(fontWeight: FontWeight.w600),
      );
      expect(spans, hasLength(1));
      expect((spans.single as TextSpan).style, isNull);
    });
  });

  group('query tokens', () {
    test('from: is lifted out of the searched text', () {
      final tokens = parseChatSearchQuery('from:bob dinner plans');
      expect(tokens.fromQuery, 'bob');
      expect(tokens.text, 'dinner plans');
      expect(tokens.filter, isNull);
    });

    test('a quoted from: keeps a name with spaces whole', () {
      final tokens = parseChatSearchQuery('from:"Mao Contact" receipt');
      expect(tokens.fromQuery, 'Mao Contact');
      expect(tokens.text, 'receipt');
    });

    test('has: maps its aliases onto message filters', () {
      expect(parseChatSearchQuery('has:link').filter, ChatSearchFilter.links);
      expect(parseChatSearchQuery('has:file').filter, ChatSearchFilter.files);
      expect(parseChatSearchQuery('HAS:Photo').filter, ChatSearchFilter.media);
      expect(parseChatSearchQuery('has:voice').filter, ChatSearchFilter.voice);
    });

    test('an unknown has: value stays part of the search text', () {
      final tokens = parseChatSearchQuery('has:sticker');
      expect(tokens.filter, isNull);
      expect(tokens.text, 'has:sticker');
    });

    test('a token still being typed narrows nothing', () {
      final tokens = parseChatSearchQuery('from:');
      expect(tokens.fromQuery, isNull);
      expect(tokens.text, isEmpty);
    });

    test('in: is lifted out like from:', () {
      final tokens = parseChatSearchQuery('in:"Mithka Users" from:bob hello');
      expect(tokens.inQuery, 'Mithka Users');
      expect(tokens.fromQuery, 'bob');
      expect(tokens.text, 'hello');
    });

    test('the caret decides which token is being suggested for', () {
      const raw = 'in:mith from:bob report';
      // Inside `in:`.
      expect(activeChatSearchToken(raw, 5)?.kind, ChatSearchTokenKind.chat);
      // Inside `from:`.
      expect(activeChatSearchToken(raw, 15)?.kind, ChatSearchTokenKind.from);
      // Out in the plain words.
      expect(activeChatSearchToken(raw, raw.length), isNull);
    });

    test('an empty token still offers suggestions', () {
      final token = activeChatSearchToken('from:', 5);
      expect(token?.kind, ChatSearchTokenKind.from);
      expect(token?.value, isEmpty);
    });

    test('picking a suggestion rewrites only that token', () {
      const raw = 'in:mith from:bob report';
      final token = activeChatSearchToken(raw, 5)!;
      final applied = applyChatSearchToken(raw, token, 'Mithka Users');
      // Quoted because it holds a space, and the rest of the query survives.
      expect(applied.text, 'in:"Mithka Users" from:bob report');
      expect(applied.caret, 'in:"Mithka Users" '.length);
      // A token at the end of the query gains the separator it lacks.
      final trailing = applyChatSearchToken(
        'from:',
        activeChatSearchToken('from:', 5)!,
        '@bob',
      );
      expect(trailing.text, 'from:@bob ');
      expect(trailing.caret, trailing.text.length);
    });

    test('both tokens combine and leave the rest of the words', () {
      final tokens = parseChatSearchQuery('from:bob has:link the article');
      expect(tokens.fromQuery, 'bob');
      expect(tokens.filter, ChatSearchFilter.links);
      expect(tokens.text, 'the article');
    });
  });

  group('controller', () {
    test('searches only the open chat and lands on the newest hit', () async {
      final activated = <int>[];
      final controller = ChatMessageSearchController(
        chatId: _chatId,
        onActivateResult: (message, {required automatic}) =>
            activated.add(message.id),
      );
      addTearDown(controller.dispose);

      controller.open();
      controller.updateQuery('needle');
      expect(controller.isLoading, isTrue, reason: 'debounce is pending');
      await Future<void>.delayed(_debounce);
      await pumpEventQueue();

      final searches = requests
          .where((request) => request['@type'] == 'searchChatMessages')
          .toList();
      expect(searches, hasLength(1));
      expect(searches.single['chat_id'], _chatId);
      expect(searches.single['query'], 'needle');

      expect(controller.results.map((m) => m.id), [30, 20, 10]);
      // TDLib returns hits newest first, so the cursor starts at the newest.
      expect(activated, [30]);
      expect(controller.matchPosition, 1);
      expect(controller.matchCount, 3);
    });

    test('stepping walks backwards then forwards through time', () async {
      final activated = <int>[];
      final controller = ChatMessageSearchController(
        chatId: _chatId,
        onActivateResult: (message, {required automatic}) =>
            activated.add(message.id),
      );
      addTearDown(controller.dispose);

      controller.open();
      controller.updateQuery('needle');
      await Future<void>.delayed(_debounce);
      await pumpEventQueue();

      expect(controller.canStepNewer, isFalse, reason: 'already at the newest');
      await controller.stepOlder();
      expect(controller.matchPosition, 2);
      await controller.stepOlder();
      expect(controller.matchPosition, 3);
      expect(controller.canStepOlder, isFalse);
      await controller.stepOlder();
      expect(controller.matchPosition, 3, reason: 'the oldest hit is the end');

      controller.stepNewer();
      expect(controller.matchPosition, 2);
      expect(activated, [30, 20, 10, 20]);
    });

    test('stepping past the loaded page pulls the next one', () async {
      handler = (request) async {
        if (request['@type'] != 'searchChatMessages') {
          return _defaultResponse(request);
        }
        final from = request['from_message_id'] as int;
        if (from == 0) {
          return _foundMessages([30, 20], totalCount: 4, next: 20);
        }
        return _foundMessages([15, 5], totalCount: 4, next: 0);
      };
      final controller = ChatMessageSearchController(chatId: _chatId);
      addTearDown(controller.dispose);

      controller.open();
      controller.updateQuery('needle');
      await Future<void>.delayed(_debounce);
      await pumpEventQueue();
      expect(controller.results, hasLength(2));
      expect(controller.hasMore, isTrue);

      await controller.stepOlder();
      expect(controller.matchPosition, 2);
      // The cursor is on the oldest loaded hit; the next step has to page.
      await controller.stepOlder();
      await pumpEventQueue();
      expect(controller.results.map((m) => m.id), [30, 20, 15, 5]);
      expect(controller.matchPosition, 3);
      expect(controller.hasMore, isFalse);
    });

    test('a page that repeats itself ends paging instead of looping', () async {
      handler = (request) async {
        if (request['@type'] != 'searchChatMessages') {
          return _defaultResponse(request);
        }
        // A server that keeps handing back the same window with a non-zero
        // cursor would otherwise page forever.
        return _foundMessages([30, 20], totalCount: 9, next: 20);
      };
      final controller = ChatMessageSearchController(chatId: _chatId);
      addTearDown(controller.dispose);

      controller.open();
      controller.updateQuery('needle');
      await Future<void>.delayed(_debounce);
      await pumpEventQueue();
      expect(controller.hasMore, isTrue);

      await controller.loadMore();
      await pumpEventQueue();
      expect(controller.results, hasLength(2));
      expect(controller.hasMore, isFalse);
    });

    test('a query lands on its own; a step is deliberate', () async {
      final activations = <bool>[];
      final controller = ChatMessageSearchController(
        chatId: _chatId,
        onActivateResult: (message, {required automatic}) =>
            activations.add(automatic),
      );
      addTearDown(controller.dispose);

      controller.open();
      controller.updateQuery('needle');
      await Future<void>.delayed(_debounce);
      await pumpEventQueue();
      // The landing a fresh query performs happens on every pause in typing.
      expect(activations, [true]);

      await controller.stepOlder();
      controller.stepNewer();
      expect(activations, [true, false, false]);
    });

    test('a filter narrows the search to one kind of message', () async {
      final controller = ChatMessageSearchController(chatId: _chatId);
      addTearDown(controller.dispose);

      controller.open();
      controller.updateQuery('needle');
      await Future<void>.delayed(_debounce);
      await pumpEventQueue();
      expect(_filtersUsed(requests), ['searchMessagesFilterEmpty']);

      requests.clear();
      controller.setFilter(ChatSearchFilter.media);
      expect(
        controller.results,
        isEmpty,
        reason: 'hits from the old filter describe a different set',
      );
      await Future<void>.delayed(_debounce);
      await pumpEventQueue();

      expect(_filtersUsed(requests), ['searchMessagesFilterPhotoAndVideo']);
      expect(controller.filter, ChatSearchFilter.media);
      expect(controller.hasResults, isTrue);
    });

    test('a filter alone searches with nothing typed', () async {
      final controller = ChatMessageSearchController(chatId: _chatId);
      addTearDown(controller.dispose);

      controller.open();
      expect(controller.hasSearch, isFalse);

      controller.setFilter(ChatSearchFilter.voice);
      expect(controller.hasSearch, isTrue);
      await Future<void>.delayed(_debounce);
      await pumpEventQueue();

      expect(_filtersUsed(requests), ['searchMessagesFilterVoiceNote']);
      final search = requests.firstWhere(
        (request) => request['@type'] == 'searchChatMessages',
      );
      expect(search['query'], '');
      expect(controller.hasResults, isTrue);
    });

    test('closing forgets the filter as well as the query', () async {
      final controller = ChatMessageSearchController(chatId: _chatId);
      addTearDown(controller.dispose);

      controller.open();
      controller.setFilter(ChatSearchFilter.files);
      await Future<void>.delayed(_debounce);
      await pumpEventQueue();

      controller.close();
      expect(controller.filter, ChatSearchFilter.all);
      expect(controller.hasSearch, isFalse);
    });

    test('from: resolves a member and scopes the search to them', () async {
      final controller = ChatMessageSearchController(chatId: _chatId);
      addTearDown(controller.dispose);

      controller.open();
      controller.updateQuery('from:mao receipt');
      await Future<void>.delayed(_debounce);
      await pumpEventQueue();

      expect(
        requests.any((request) => request['@type'] == 'searchChatMembers'),
        isTrue,
      );
      final search = requests.firstWhere(
        (request) => request['@type'] == 'searchChatMessages',
      );
      // The token is a TDLib parameter, not a word to look for.
      expect(search['query'], 'receipt');
      expect((search['sender_id'] as Map<String, dynamic>)['user_id'], 55);
      expect(controller.senderName, 'Mao Contact');
      expect(controller.hasSearch, isTrue);
    });

    test('has: overrides the chip while it is typed', () async {
      final controller = ChatMessageSearchController(chatId: _chatId);
      addTearDown(controller.dispose);

      controller.open();
      controller.setFilter(ChatSearchFilter.music);
      controller.updateQuery('has:link report');
      await Future<void>.delayed(_debounce);
      await pumpEventQueue();

      expect(controller.filter, ChatSearchFilter.links);
      expect(_filtersUsed(requests), contains('searchMessagesFilterUrl'));
    });

    test('a stale page cannot repopulate a newer query', () async {
      final slow = Completer<Map<String, dynamic>>();
      handler = (request) async {
        if (request['@type'] != 'searchChatMessages') {
          return _defaultResponse(request);
        }
        if (request['query'] == 'old') return slow.future;
        return _foundMessages([7], totalCount: 1, next: 0);
      };
      final controller = ChatMessageSearchController(chatId: _chatId);
      addTearDown(controller.dispose);

      controller.open();
      controller.updateQuery('old');
      await Future<void>.delayed(_debounce);
      controller.updateQuery('new');
      await Future<void>.delayed(_debounce);
      await pumpEventQueue();
      expect(controller.results.map((m) => m.id), [7]);

      slow.complete(_foundMessages([99], totalCount: 1, next: 0));
      await pumpEventQueue();
      expect(controller.results.map((m) => m.id), [7]);
    });

    test('closing drops the query, the hits and the cursor', () async {
      final controller = ChatMessageSearchController(chatId: _chatId);
      addTearDown(controller.dispose);

      controller.open();
      controller.updateQuery('needle');
      await Future<void>.delayed(_debounce);
      await pumpEventQueue();
      expect(controller.hasResults, isTrue);

      controller.close();
      expect(controller.isActive, isFalse);
      expect(controller.results, isEmpty);
      expect(controller.query, isEmpty);
      expect(controller.matchPosition, 0);
      expect(controller.textController.text, isEmpty);
    });

    test('group hits resolve the sender they are attributed to', () async {
      final controller = ChatMessageSearchController(chatId: _chatId);
      addTearDown(controller.dispose);

      controller.open();
      controller.updateQuery('needle');
      await Future<void>.delayed(_debounce);
      await pumpEventQueue();

      expect(
        controller.results.map((m) => m.senderName),
        everyElement('Mao Contact'),
      );
      // One lookup per distinct sender, not one per hit.
      expect(
        requests.where((request) => request['@type'] == 'getUser'),
        hasLength(1),
      );
    });
  });

  group('surfaces', () {
    testWidgets('the header counts the cursor against the total', (
      tester,
    ) async {
      final controller = ChatMessageSearchController(chatId: _chatId);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_harness(_header(controller)));

      controller.open();
      controller.updateQuery('needle');
      await tester.pump(_debounce);
      await tester.pumpAndSettle();

      expect(find.text('1 of 3'), findsOneWidget);
      await controller.stepOlder();
      await tester.pumpAndSettle();
      expect(find.text('2 of 3'), findsOneWidget);
    });

    testWidgets('the navigator disables steps at the ends of the results', (
      tester,
    ) async {
      final controller = ChatMessageSearchController(chatId: _chatId);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _harness(
          ChatSearchNavigator(controller: controller, onShowResults: () {}),
        ),
      );

      controller.open();
      controller.updateQuery('needle');
      await tester.pump(_debounce);
      await tester.pumpAndSettle();

      expect(find.text('3 results'), findsOneWidget);
      expect(_stepperEnabled(tester, 'chatSearchStepNewer'), isFalse);
      expect(_stepperEnabled(tester, 'chatSearchStepOlder'), isTrue);

      await tester.tap(find.byKey(const ValueKey('chatSearchStepOlder')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chatSearchStepOlder')));
      await tester.pumpAndSettle();

      expect(_stepperEnabled(tester, 'chatSearchStepNewer'), isTrue);
      expect(_stepperEnabled(tester, 'chatSearchStepOlder'), isFalse);
    });

    testWidgets('a pane row moves the cursor to that hit', (tester) async {
      final controller = ChatMessageSearchController(chatId: _chatId);
      addTearDown(controller.dispose);
      ChatMessage? selected;
      await tester.pumpWidget(
        _harness(
          fill: true,
          ChatSearchResultsPane(
            controller: controller,
            peerTitle: 'Group',
            onSelect: (message) {
              selected = message;
              controller.selectResult(message);
            },
          ),
        ),
      );

      controller.open();
      controller.updateQuery('needle');
      await tester.pump(_debounce);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('chatSearchResult-20')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chatSearchResult-20')));
      await tester.pumpAndSettle();

      expect(selected?.id, 20);
      expect(controller.activeMessageId, 20);
    });

    testWidgets('a list-only surface marks no row until one is picked', (
      tester,
    ) async {
      final controller = ChatMessageSearchController(
        chatId: _chatId,
        autoActivateFirstResult: false,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _harness(
          fill: true,
          ChatSearchResultsPane(
            controller: controller,
            peerTitle: 'Group',
            onSelect: (_) {},
          ),
        ),
      );

      controller.open();
      controller.updateQuery('needle');
      await tester.pump(_debounce);
      await tester.pumpAndSettle();

      expect(controller.hasResults, isTrue);
      expect(controller.activeIndex, -1);
      expect(controller.matchPosition, 0);
    });

    testWidgets('an empty query invites one instead of reporting none', (
      tester,
    ) async {
      final controller = ChatMessageSearchController(chatId: _chatId);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _harness(
          fill: true,
          ChatSearchResultsPane(
            controller: controller,
            peerTitle: 'Group',
            onSelect: (_) {},
          ),
        ),
      );
      controller.open();
      await tester.pumpAndSettle();

      expect(
        find.text(AppStrings.t(AppStringKeys.chatSearchMessagePlaceholder)),
        findsWidgets,
      );
      expect(
        find.text(AppStrings.t(AppStringKeys.chatSearchNoMessagesFound)),
        findsNothing,
      );
    });
  });

  group('pushed search screen', () {
    testWidgets('names the sender of a group hit instead of the chat', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppColors.light]),
          home: const ChatSearchView(
            chatId: _chatId,
            title: 'The group',
            initialQuery: 'needle',
          ),
        ),
      );
      await tester.pump(_debounce);
      await tester.pumpAndSettle();

      // Search hits arrive without a resolved sender; without hydration every
      // row would be attributed to the chat itself.
      expect(find.text('Mao Contact'), findsWidgets);
      expect(find.text('The group'), findsNothing);
    });

    testWidgets('pops the picked message id to whoever opened it', (
      tester,
    ) async {
      int? picked;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppColors.light]),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    picked = await Navigator.of(context).push<int>(
                      MaterialPageRoute<int>(
                        builder: (_) => const ChatSearchView(
                          chatId: _chatId,
                          title: 'The group',
                          initialQuery: 'needle',
                        ),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.pump(_debounce);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('chatSearchResult-20')));
      await tester.pumpAndSettle();

      expect(picked, 20);
    });
  });
}

Widget _header(ChatMessageSearchController controller) =>
    ChatSearchHeaderBar(controller: controller, height: 48, onClose: () {});

/// The stepper shows its disabled state by fading the glyph, so the icon's
/// opacity is the observable that does not depend on the surface's internals.
bool _stepperEnabled(WidgetTester tester, String key) {
  final icon = tester.widget<Icon>(
    find
        .descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Icon))
        .first,
  );
  return (icon.color?.a ?? 1) > 0.5;
}

/// [fill] gives the child the whole box, which the results pane needs for its
/// own Expanded list; the header and navigator keep their intrinsic height.
Widget _harness(Widget child, {bool fill = false}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [AppLocalizations.delegate],
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(extensions: [AppColors.light]),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 380,
        height: 520,
        child: fill
            ? child
            : Column(
                children: [
                  child,
                  const Expanded(child: SizedBox.expand()),
                ],
              ),
      ),
    ),
  ),
);

Map<String, dynamic> _defaultResponse(Map<String, dynamic> request) =>
    switch (request['@type']) {
      'searchChatMessages' => _foundMessages(
        [30, 20, 10],
        totalCount: 3,
        next: 0,
      ),
      'searchChatMembers' => {
        '@type': 'chatMembers',
        'total_count': 1,
        'members': [
          {
            '@type': 'chatMember',
            'member_id': {'@type': 'messageSenderUser', 'user_id': 55},
            'status': {'@type': 'chatMemberStatusMember'},
          },
        ],
      },
      'getUser' => {
        '@type': 'user',
        'id': request['user_id'],
        'first_name': 'Mao',
        'last_name': 'Contact',
        'status': {'@type': 'userStatusOffline', 'was_online': 0},
      },
      _ => {'@type': 'ok'},
    };

Map<String, dynamic> _foundMessages(
  List<int> ids, {
  required int totalCount,
  required int next,
}) => {
  '@type': 'foundChatMessages',
  'total_count': totalCount,
  'next_from_message_id': next,
  'messages': [for (final id in ids) _message(id)],
};

Map<String, dynamic> _message(int id) => {
  '@type': 'message',
  'id': id,
  'chat_id': _chatId,
  'date': id,
  'is_outgoing': false,
  'sender_id': {'@type': 'messageSenderUser', 'user_id': 55},
  'content': {
    '@type': 'messageText',
    'text': {
      '@type': 'formattedText',
      'text': 'a needle in message $id',
      'entities': <Map<String, dynamic>>[],
    },
  },
};

List<String> _filtersUsed(List<Map<String, dynamic>> requests) => requests
    .where((request) => request['@type'] == 'searchChatMessages')
    .map((request) => (request['filter'] as Map<String, dynamic>)['@type'])
    .cast<String>()
    .toSet()
    .toList();
