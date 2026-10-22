import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view_model.dart';
import 'package:mithka/tdlib/td_client.dart';

/// Packed ids: TDLib server ids carry `server_id << 20` in the low bits.
const int _shift = 20;

void main() {
  test(
    'markFolderRead reads each unread chat and its newest message',
    () async {
      final requests = <Map<String, dynamic>>[];
      var loadPasses = 0;
      final model = ChatListViewModel(
        queryForTesting: (request) async {
          requests.add({...request});
          return switch (request['@type']) {
            // One growing pass, then TDLib's "list complete" answer.
            'loadChats' =>
              ++loadPasses > 1
                  ? throw TdError({'code': 404, 'message': 'Not Found'})
                  : {'@type': 'ok'},
            'getChats' => {
              '@type': 'chats',
              'total_count': 3,
              'chat_ids': const <int>[11, 12, 13],
            },
            'getChat' => switch (request['chat_id']) {
              11 => _chat(11, unread: 2, lastMessageId: 7 << _shift),
              12 => _chat(12),
              13 => _chat(13, markedUnread: true, lastMessageId: 4 << _shift),
              _ => _chat(request['chat_id'] as int),
            },
            _ => {'@type': 'ok'},
          };
        },
      );
      addTearDown(model.dispose);

      await model.markFolderRead(7);

      expect(requests.first, {
        '@type': 'loadChats',
        'chat_list': {'@type': 'chatListFolder', 'chat_folder_id': 7},
        'limit': 1000,
      });
      expect(loadPasses, 2, reason: 'a 404 ends the load drain');
      expect(
        requests.where((request) => request['@type'] == 'getChats').single,
        {
          '@type': 'getChats',
          'chat_list': {'@type': 'chatListFolder', 'chat_folder_id': 7},
          'limit': 1000,
        },
      );
      expect(
        requests
            .where((request) => request['@type'] == 'getChat')
            .map((request) => request['chat_id']),
        [11, 12, 13],
      );
      expect(
        requests
            .where((request) => request['@type'] == 'viewMessages')
            .toList(),
        [
          {
            '@type': 'viewMessages',
            'chat_id': 11,
            'message_ids': [7 << _shift],
            'force_read': true,
          },
        ],
        reason:
            'a read chat gets no viewMessages, and the unread one is read '
            'at its own newest message id',
      );
      expect(
        requests
            .where(
              (request) => request['@type'] == 'toggleChatIsMarkedAsUnread',
            )
            .toList(),
        [
          {
            '@type': 'toggleChatIsMarkedAsUnread',
            'chat_id': 13,
            'is_marked_as_unread': false,
          },
        ],
        reason: 'a chat marked unread without unread messages loses that mark',
      );
    },
  );

  test('markFolderRead keeps reading the rest when one chat fails', () async {
    final requests = <Map<String, dynamic>>[];
    final model = ChatListViewModel(
      queryForTesting: (request) async {
        requests.add({...request});
        return switch (request['@type']) {
          'getChats' => {
            '@type': 'chats',
            'total_count': 2,
            'chat_ids': const <int>[21, 22],
          },
          'getChat' => switch (request['chat_id']) {
            21 => throw StateError('gone'),
            22 => _chat(22, unread: 1, lastMessageId: 9 << _shift),
            _ => _chat(request['chat_id'] as int),
          },
          _ => {'@type': 'ok'},
        };
      },
    );
    addTearDown(model.dispose);

    await model.markFolderRead(9);

    expect(
      requests.where((request) => request['@type'] == 'viewMessages').single,
      {
        '@type': 'viewMessages',
        'chat_id': 22,
        'message_ids': [9 << _shift],
        'force_read': true,
      },
    );
  });
  test('a bulk read covers a list longer than one page', () async {
    const total = 1500;
    final requests = <Map<String, dynamic>>[];
    final model = ChatListViewModel(
      queryForTesting: (request) async {
        requests.add({...request});
        return switch (request['@type']) {
          // TDLib's "nothing left to load" answer.
          'loadChats' => throw TdError({'code': 404, 'message': 'Not Found'}),
          // `getChats` answers from the beginning of the list, capped by the
          // requested limit — exactly the contract the action must paginate.
          'getChats' => {
            '@type': 'chats',
            'total_count': total,
            'chat_ids': [
              for (
                var id = 1;
                id <= (request['limit'] as int).clamp(0, total);
                id++
              )
                id,
            ],
          },
          'getChat' => _chat(
            request['chat_id'] as int,
            unread: 1,
            lastMessageId: 9 << _shift,
          ),
          _ => {'@type': 'ok'},
        };
      },
    );
    addTearDown(model.dispose);

    await model.markFolderRead(7);

    expect(
      requests
          .where((request) => request['@type'] == 'getChats')
          .map((request) => request['limit']),
      [1000, 1500],
      reason: 'the page grows until the reported total is in hand',
    );
    final read = requests
        .where((request) => request['@type'] == 'viewMessages')
        .map((request) => request['chat_id'])
        .toList();
    expect(read.length, total);
    expect(
      read.contains(total),
      isTrue,
      reason: 'the chat beyond the first page must not be left unread',
    );
  });

  test('a failed page ends the growth and keeps what was read', () async {
    const total = 1500;
    final requests = <Map<String, dynamic>>[];
    final model = ChatListViewModel(
      queryForTesting: (request) async {
        requests.add({...request});
        return switch (request['@type']) {
          'loadChats' => throw TdError({'code': 404, 'message': 'Not Found'}),
          'getChats' =>
            request['limit'] == 1500
                ? throw TdError({'code': 420, 'message': 'Too Many Requests'})
                : {
                    '@type': 'chats',
                    'total_count': total,
                    'chat_ids': [for (var id = 1; id <= 1000; id++) id],
                  },
          'getChat' => _chat(
            request['chat_id'] as int,
            unread: 1,
            lastMessageId: 9 << _shift,
          ),
          _ => {'@type': 'ok'},
        };
      },
    );
    addTearDown(model.dispose);

    await model.markFolderRead(7);

    final read = requests
        .where((request) => request['@type'] == 'viewMessages')
        .toList();
    expect(
      read.length,
      1000,
      reason: 'the chats of the page that arrived are still read',
    );
  });

  test('a slow loader is drilled until the whole list is read', () async {
    const total = 1001;
    final requests = <Map<String, dynamic>>[];
    var loaded = 0;
    final model = ChatListViewModel(
      queryForTesting: (request) async {
        requests.add({...request});
        return switch (request['@type']) {
          // TDLib may load far less than it was asked for without being
          // done; only the 404 proves exhaustion.
          'loadChats' => () {
            if (loaded >= total) {
              throw TdError({'code': 404, 'message': 'Not Found'});
            }
            loaded = (loaded + 100).clamp(0, total);
            return {
              '@type': 'ok',
              'total_count': total,
              'loaded_count': loaded,
            };
          }(),
          'getChats' => () {
            final limit = request['limit'] as int;
            final count = limit < loaded ? limit : loaded;
            return {
              '@type': 'chats',
              'total_count': total,
              'chat_ids': [for (var id = 1; id <= count; id++) id],
            };
          }(),
          'getChat' => _chat(
            request['chat_id'] as int,
            unread: request['chat_id'] == total ? 1 : 0,
            lastMessageId: 9 << _shift,
          ),
          _ => {'@type': 'ok'},
        };
      },
    );
    addTearDown(model.dispose);

    await model.markFolderRead(7);

    expect(
      requests
          .where((request) => request['@type'] == 'viewMessages')
          .map((request) => request['chat_id']),
      [total],
      reason: 'the last chat of a slowly loaded list is still read',
    );
    expect(
      requests.where((request) => request['@type'] == 'loadChats').length,
      greaterThan(8),
      reason:
          'the drain keeps loading past the eight passes that used to '
          'be treated as the end',
    );
  });

  test('an 8001-chat list loaded 1000 at a time is read to the end', () async {
    const total = 8001;
    final requests = <Map<String, dynamic>>[];
    var loaded = 0;
    final model = ChatListViewModel(
      queryForTesting: (request) async {
        requests.add({...request});
        return switch (request['@type']) {
          'loadChats' => () {
            if (loaded >= total) {
              throw TdError({'code': 404, 'message': 'Not Found'});
            }
            loaded = (loaded + 1000).clamp(0, total);
            return {
              '@type': 'ok',
              'total_count': total,
              'loaded_count': loaded,
            };
          }(),
          'getChats' => () {
            final limit = request['limit'] as int;
            final count = limit < loaded ? limit : loaded;
            return {
              '@type': 'chats',
              'total_count': total,
              'chat_ids': [for (var id = 1; id <= count; id++) id],
            };
          }(),
          'getChat' => _chat(
            request['chat_id'] as int,
            unread: request['chat_id'] == total ? 1 : 0,
            lastMessageId: 9 << _shift,
          ),
          _ => {'@type': 'ok'},
        };
      },
    );
    addTearDown(model.dispose);

    await model.markFolderRead(7);

    expect(
      requests
          .where((request) => request['@type'] == 'viewMessages')
          .map((request) => request['chat_id']),
      [total],
    );
  });

  test('a disposal while loading continues stops the whole drain', () async {
    final requests = <Map<String, dynamic>>[];
    final hold = Completer<void>();
    var loads = 0;
    final model = ChatListViewModel(
      queryForTesting: (request) async {
        requests.add({...request});
        if (request['@type'] == 'loadChats') {
          // The second load is held while the list is disposed and switched.
          if (++loads == 2) await hold.future;
          return {'@type': 'ok', 'total_count': 5000, 'loaded_count': loads};
        }
        return switch (request['@type']) {
          'getChats' => {
            '@type': 'chats',
            'total_count': 5000,
            'chat_ids': const <int>[],
          },
          _ => {'@type': 'ok'},
        };
      },
    );

    final run = model.markFolderRead(7);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    model.dispose();
    hold.complete();
    await run;

    expect(
      requests.where((request) => request['@type'] == 'loadChats'),
      hasLength(2),
      reason: 'no further load is issued after the list is gone',
    );
    expect(
      requests.where((request) => request['@type'] == 'getChats'),
      isEmpty,
      reason: 'the read that would have followed the held load never happens',
    );
    expect(
      requests.where((request) => request['@type'] == 'viewMessages'),
      isEmpty,
    );
  });

  test('a load failure that is not 404 reads the prefix and stops', () async {
    var loads = 0;
    final requests = <Map<String, dynamic>>[];
    final model = ChatListViewModel(
      queryForTesting: (request) async {
        requests.add({...request});
        return switch (request['@type']) {
          // A flood wait is not "the list ended": loading stops, but the
          // chats already loaded must still be read.
          'loadChats' => () {
            if (++loads == 1) {
              return {'@type': 'ok', 'total_count': 3000};
            }
            throw TdError({'code': 429, 'message': 'Too Many Requests'});
          }(),
          'getChats' => {
            '@type': 'chats',
            'total_count': 3000,
            'chat_ids': const <int>[41, 42],
          },
          'getChat' => _chat(
            request['chat_id'] as int,
            unread: 1,
            lastMessageId: 9 << _shift,
          ),
          _ => {'@type': 'ok'},
        };
      },
    );
    addTearDown(model.dispose);

    await model.markFolderRead(7);

    expect(
      requests
          .where((request) => request['@type'] == 'viewMessages')
          .map((request) => request['chat_id']),
      [41, 42],
      reason: 'what was loaded is read even though loading could not finish',
    );
    expect(
      requests.where((request) => request['@type'] == 'loadChats'),
      hasLength(2),
      reason: 'a stalled drain stops instead of retrying in a loop',
    );
  });
}

Map<String, dynamic> _chat(
  int id, {
  int unread = 0,
  int lastMessageId = 0,
  bool markedUnread = false,
}) => {
  '@type': 'chat',
  'id': id,
  'title': 'Chat $id',
  'type': {'@type': 'chatTypePrivate', 'user_id': id + 1000},
  'unread_count': unread,
  'is_marked_as_unread': markedUnread,
  'last_read_inbox_message_id': 0,
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
