import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_message_search_controller.dart';
import 'package:mithka/tdlib/td_client.dart';

const _chatId = -100200;
const _aliceId = 55;
const _debounce = Duration(milliseconds: 281);
const _suggestDebounce = Duration(milliseconds: 241);

/// Picking a person from the `from:` suggestions takes the token text out of
/// the field and keeps the sender as a badge. That badge is a search of its
/// own: it must fetch without words typed, page, and still scope later words.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<String, dynamic>> requests;
  late Future<Map<String, dynamic>> Function(Map<String, dynamic>) handler;

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) {
          requests.add(Map<String, dynamic>.from(request));
          return handler(request);
        },
        send: (_) async {},
        updates: const Stream<Map<String, dynamic>>.empty(),
      ),
    );
  });

  setUp(() {
    requests = [];
    handler = (request) async => _response(request);
  });

  tearDownAll(TdClient.shared.closeProxy);

  Future<void> commitAlice(ChatMessageSearchController controller) async {
    controller.open();
    controller.updateQuery('from:alice');
    await Future<void>.delayed(_suggestDebounce);
    await pumpEventQueue();
    expect(controller.suggestions, isNotEmpty);
    final alice = controller.suggestions.firstWhere(
      (suggestion) => suggestion.id == _aliceId,
    );
    controller.applySuggestion(alice);
    await Future<void>.delayed(_debounce);
    await pumpEventQueue();
  }

  test(
    'a picked from: sender searches and pages with no words typed',
    () async {
      final controller = ChatMessageSearchController(chatId: _chatId);
      addTearDown(controller.dispose);

      await commitAlice(controller);

      expect(controller.textController.text, isEmpty);
      expect(controller.senderUserId, _aliceId);
      expect(controller.senderName, 'Alice');
      expect(controller.hasSearch, isTrue);
      final searches = requests
          .where((request) => request['@type'] == 'searchChatMessages')
          .toList();
      expect(
        searches,
        isNotEmpty,
        reason: 'the committed sender is the only thing to search for',
      );
      final search = searches.last;
      expect(search['query'], '');
      expect(search['sender_id'], {
        '@type': 'messageSenderUser',
        'user_id': 55,
      });
      expect(controller.results.map((message) => message.id), [30, 20, 10]);
      expect(controller.matchCount, 3);
      expect(controller.hasMore, isTrue);

      // Paging must keep the committed sender: the guard reads the same search
      // state the first page did.
      await controller.loadMore();
      await pumpEventQueue();
      final paged = requests
          .where((request) => request['@type'] == 'searchChatMessages')
          .last;
      expect(paged['query'], '');
      expect(paged['from_message_id'], 15);
      expect(paged['sender_id'], {'@type': 'messageSenderUser', 'user_id': 55});
      expect(controller.results.map((message) => message.id), [30, 20, 10, 5]);
      expect(controller.hasMore, isFalse);
    },
  );

  test('clearing the sender with no words stops the search', () async {
    final controller = ChatMessageSearchController(chatId: _chatId);
    addTearDown(controller.dispose);

    await commitAlice(controller);
    requests.clear();

    controller.clearSender();
    expect(controller.hasSearch, isFalse);
    expect(controller.senderUserId, isNull);
    expect(controller.results, isEmpty);

    await Future<void>.delayed(_debounce);
    await pumpEventQueue();
    expect(
      requests.where((request) => request['@type'] == 'searchChatMessages'),
      isEmpty,
    );
  });

  test('clearing the sender drops its already pending response', () async {
    final pending = Completer<Map<String, dynamic>>();
    handler = (request) async {
      if (request['@type'] == 'searchChatMessages') return pending.future;
      return _response(request);
    };
    final controller = ChatMessageSearchController(chatId: _chatId);
    addTearDown(controller.dispose);
    await commitAlice(controller);
    expect(requests.any((r) => r['@type'] == 'searchChatMessages'), isTrue);
    controller.clearSender();
    pending.complete(
      _response({'@type': 'searchChatMessages', 'from_message_id': 0}),
    );
    await pumpEventQueue();
    expect(controller.hasSearch, isFalse);
    expect(controller.results, isEmpty);
  });

  test('words typed after a commit keep the same sender scope', () async {
    final controller = ChatMessageSearchController(chatId: _chatId);
    addTearDown(controller.dispose);

    await commitAlice(controller);
    requests.clear();

    controller.updateQuery('needle');
    await Future<void>.delayed(_debounce);
    await pumpEventQueue();

    final searches = requests
        .where((request) => request['@type'] == 'searchChatMessages')
        .toList();
    expect(searches, hasLength(1));
    expect(searches.single['query'], 'needle');
    expect(searches.single['sender_id'], {
      '@type': 'messageSenderUser',
      'user_id': 55,
    });
    expect(controller.hasSearch, isTrue);
    expect(controller.senderUserId, _aliceId);
    expect(controller.hasResults, isTrue);
  });
}

Map<String, dynamic> _response(Map<String, dynamic> request) {
  switch (request['@type']) {
    case 'searchChatMembers':
      return {
        '@type': 'chatMembers',
        'total_count': 1,
        'members': [
          {
            '@type': 'chatMember',
            'member_id': {'@type': 'messageSenderUser', 'user_id': _aliceId},
            'status': {'@type': 'chatMemberStatusMember'},
          },
        ],
      };
    case 'getUser':
      return {
        '@type': 'user',
        'id': request['user_id'],
        'first_name': 'Alice',
        'last_name': '',
        'status': {'@type': 'userStatusOffline', 'was_online': 0},
      };
    case 'searchChatMessages':
      final firstPage = request['from_message_id'] == 0;
      return {
        '@type': 'foundChatMessages',
        'total_count': 3,
        'next_from_message_id': firstPage ? 15 : 0,
        'messages': [
          for (final id in firstPage ? [30, 20, 10] : [5]) _message(id),
        ],
      };
    default:
      return {'@type': 'ok'};
  }
}

Map<String, dynamic> _message(int id) => {
  '@type': 'message',
  'id': id,
  'chat_id': _chatId,
  'date': id,
  'is_outgoing': false,
  'sender_id': {'@type': 'messageSenderUser', 'user_id': _aliceId},
  'content': {
    '@type': 'messageText',
    'text': {
      '@type': 'formattedText',
      'text': 'a needle in message $id',
      'entities': <Map<String, dynamic>>[],
    },
  },
};
