import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/moments/moments_view.dart';

const _chatId = -1001;

Map<String, dynamic> _message(
  int id, {
  int? date,
  String type = 'messageText',
}) => {
  '@type': 'message',
  'id': id,
  'chat_id': _chatId,
  'date': date ?? id,
  'is_outgoing': false,
  'media_album_id': type == 'messagePhoto' ? 77 : 0,
  'content': {
    '@type': type,
    if (type == 'messageText')
      'text': {
        '@type': 'formattedText',
        'text': 'post $id',
        'entities': <Map<String, dynamic>>[],
      },
  },
};

/// A channel whose history TDLib serves in the given page sizes, newest
/// first, starting at (and including) `from_message_id` like TDLib does.
class _FakeHistory {
  _FakeHistory(this.ids, {List<int> pageSizes = const []})
    : _pageSizes = List.of(pageSizes);

  final List<int> ids;
  final List<int> _pageSizes;
  final requests = <Map<String, dynamic>>[];
  int? failOnRequest;

  Future<Map<String, dynamic>> call(Map<String, dynamic> request) async {
    requests.add(request);
    if (failOnRequest == requests.length) throw StateError('offline');
    final from = request['from_message_id'] as int;
    final limit = request['limit'] as int;
    final size = _pageSizes.isEmpty ? limit : _pageSizes.removeAt(0);
    final newestFirst = ids.toList()..sort((a, b) => b.compareTo(a));
    final page = newestFirst
        .where((id) => from == 0 || id <= from)
        .take(size)
        .map(_message)
        .toList();
    return {'@type': 'messages', 'messages': page};
  }
}

void main() {
  group('loadChannelHistory', () {
    test('keeps paging past a one-message first page', () async {
      // TDLib's first page of an uncached channel often carries only the
      // last message; the older album must still reach the feed.
      final history = _FakeHistory(
        [for (var id = 1; id <= 40; id++) id],
        pageSizes: [1, 30],
      );
      final load = await loadChannelHistory(
        query: history.call,
        chatId: _chatId,
        fromMessageId: 0,
        wanted: 30,
      );

      expect(history.requests, hasLength(2));
      expect(history.requests[1]['from_message_id'], 40);
      // The inclusive cursor repeats message 40; it is counted once.
      expect(load.messages.map((message) => message.id), [
        40,
        for (var id = 39; id >= 11; id--) id,
      ]);
      expect(load.oldestMessageId, 11);
      expect(load.oldestDate, 11);
      expect(load.reachedStart, isFalse);
    });

    test('a refresh that runs out of pages reports the gap', () async {
      final history = _FakeHistory(
        [for (var id = 1; id <= 100; id++) id],
        pageSizes: [5, 5],
      );
      final load = await loadChannelHistory(
        query: history.call,
        chatId: _chatId,
        fromMessageId: 0,
        wanted: 30,
        knownNewestMessageId: 10,
        maxPages: 2,
      );

      expect(load.reconnected, isFalse);
      expect(load.reachedStart, isFalse);
      expect(load.oldestMessageId, 92);
    });

    test('rethrows a first-page failure and keeps later arrivals', () async {
      final failing = _FakeHistory([1, 2, 3])..failOnRequest = 1;
      await expectLater(
        loadChannelHistory(
          query: failing.call,
          chatId: _chatId,
          fromMessageId: 0,
          wanted: 30,
        ),
        throwsStateError,
      );

      final partial = _FakeHistory(
        [for (var id = 1; id <= 10; id++) id],
        pageSizes: [2, 2],
      )..failOnRequest = 2;
      final load = await loadChannelHistory(
        query: partial.call,
        chatId: _chatId,
        fromMessageId: 0,
        wanted: 30,
      );
      expect(load.messages.map((message) => message.id), [10, 9]);
      expect(load.reachedStart, isFalse);
    });

    test('stops reading once the load is cancelled', () async {
      final history = _FakeHistory(
        [for (var id = 1; id <= 40; id++) id],
        pageSizes: [1, 30],
      );
      final load = await loadChannelHistory(
        query: history.call,
        chatId: _chatId,
        fromMessageId: 0,
        wanted: 30,
        cancelled: () => true,
      );

      expect(history.requests, hasLength(1));
      expect(load.messages, isEmpty);
    });
  });
}
