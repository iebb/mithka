//
//  forum_topic_bulk_read_rollback_test.dart
//
//  Bulk mark-all-read must never resurrect a counter that an authoritative
//  update or a successful read already cleared. These are the two production
//  reproductions from review: a pending batch overtaken by updateForumTopic,
//  and a partial batch followed by a stale getForumTopics page.
//

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/tdlib/forum_topic_index.dart';
import 'package:mithka/tdlib/td_client.dart';

const _chatId = -10042;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<Map<String, dynamic>> updates;
  late _ForumServer server;

  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    server = _ForumServer();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: server.query,
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });
  setUp(() {
    server.reset();
    ForumTopicIndex.shared.clear();
  });
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  ChatViewModel model() =>
      ChatViewModel(chatId: _chatId, title: 'Forum', markReadOnOpen: false)
        ..isForum = true;

  int unread(ChatViewModel model, int topicId) =>
      model.forumTopics.firstWhere((topic) => topic.id == topicId).unreadCount;

  for (final success in [true, false]) {
    test(
      'disposing a bulk read cancels late ${success ? "success" : "failure"} and the remaining topics',
      () async {
        server
          ..addTopic(id: 1, lastMessageId: 90, unread: 2)
          ..addTopic(id: 2, lastMessageId: 85, unread: 3);
        final viewModel = model();
        await viewModel.loadForumTopics();
        final pending = server.holdTopic(1);
        final batch = viewModel.markForumTopicsRead([1, 2]);
        await pumpEventQueue();
        viewModel.dispose();
        // Account/cache replacement must not be mutated by the old pane.
        ForumTopicIndex.shared.clear();
        ForumTopicIndex.shared.storeAll(0, _chatId, const [
          ForumTopicIndexEntry(
            id: 1,
            name: 'Replacement topic',
            unreadCount: 7,
            lastMessageId: 90,
          ),
        ]);
        if (success) {
          pending.complete({'@type': 'ok'});
        } else {
          pending.completeError(StateError('old read failed'));
        }
        await batch;
        expect(server.viewMessages, hasLength(1));
        expect(ForumTopicIndex.shared.entryFor(0, _chatId, 1)?.unreadCount, 7);
      },
    );
  }

  test('a pending batch failure must not restore a counter an authoritative '
      'read already cleared', () async {
    server.addTopic(id: 1, lastMessageId: 90, unread: 2);
    final viewModel = model();
    await viewModel.loadForumTopics();
    expect(unread(viewModel, 1), 2);

    // The page the batch's refresh would return is the pre-read snapshot:
    // a stale page must not be able to undo the authoritative zero either.
    server.freezePage();
    final read = server.holdTopic(1);
    final batch = viewModel.markForumTopicsRead([1]);
    await pumpEventQueue();

    // While viewMessages is in flight, TDLib confirms topic 1 is read to
    // its newest message and its badge is cleared.
    updates.add({
      '@type': 'updateForumTopic',
      'chat_id': _chatId,
      'forum_topic_id': 1,
      'last_read_inbox_message_id': 90,
      'is_pinned': false,
      'notification_settings': {'@type': 'chatNotificationSettings'},
    });
    await pumpEventQueue();
    expect(unread(viewModel, 1), 0);

    // The batch request then fails; the old count must not come back.
    read.completeError(StateError('offline'));
    await expectLater(batch, throwsA(isA<StateError>()));

    expect(
      unread(viewModel, 1),
      0,
      reason: 'the authoritative watermark cleared topic 1',
    );
    expect(
      ForumTopicIndex.shared.entryFor(0, _chatId, 1)?.unreadCount,
      0,
      reason: 'the index must keep the authoritative zero too',
    );

    // The stale page refresh that follows must not resurrect it.
    await viewModel.loadForumTopics();
    expect(
      unread(viewModel, 1),
      0,
      reason: 'a page older than the known read must not regress it',
    );
  });

  test('a successful topic survives a stale page while only the failed topic '
      'rolls back', () async {
    server
      ..addTopic(id: 1, lastMessageId: 90, unread: 2)
      ..addTopic(id: 2, lastMessageId: 85, unread: 3);
    final viewModel = model();
    await viewModel.loadForumTopics();
    expect(unread(viewModel, 1), 2);
    expect(unread(viewModel, 2), 3);

    // Every page from here on is the pre-batch snapshot: exactly what a
    // getForumTopics response fetched before the successful read returns.
    server
      ..freezePage()
      ..failTopic(2);

    await viewModel.markForumTopicsRead([1, 2]);

    expect(unread(viewModel, 1), 0, reason: 'topic 1 was read successfully');
    expect(
      unread(viewModel, 2),
      3,
      reason: 'only the failed topic regains its own counter',
    );
    expect(
      viewModel.takeBulkReadFailure(),
      isTrue,
      reason: 'a partial failure still asks the surface for its toast',
    );

    // A later stale page must keep topic 1 read and topic 2's real count.
    await viewModel.loadForumTopics();
    expect(unread(viewModel, 1), 0);
    expect(unread(viewModel, 2), 3);

    final reads = server.viewMessages;
    expect(reads, hasLength(2), reason: 'exactly one read per topic');
    expect(
      [for (final request in reads) (request['message_ids'] as List).single],
      [90, 85],
    );
    for (final request in reads) {
      expect(request['chat_id'], _chatId);
      expect(request['force_read'], isTrue);
      expect(
        (request['source'] as Map)['@type'],
        'messageSourceForumTopicHistory',
      );
    }
    expect(ForumTopicIndex.shared.entryFor(0, _chatId, 1)?.unreadCount, 0);
    expect(ForumTopicIndex.shared.entryFor(0, _chatId, 2)?.unreadCount, 3);
  });
}

class _FakeTopic {
  _FakeTopic({
    required this.id,
    required this.lastMessageId,
    required this.unread,
    this.readInbox = 0,
  });

  final int id;
  final int lastMessageId;
  int unread;
  int readInbox;

  String get name => 'Topic $id';

  Map<String, dynamic> toPageJson() => {
    '@type': 'forumTopic',
    'info': {
      '@type': 'forumTopicInfo',
      'chat_id': _chatId,
      'forum_topic_id': id,
      'name': name,
    },
    'last_message': {
      '@type': 'message',
      'id': lastMessageId,
      'chat_id': _chatId,
      'date': lastMessageId,
      'is_outgoing': true,
      'content': {
        '@type': 'messageText',
        'text': {'@type': 'formattedText', 'text': 'Post $lastMessageId'},
      },
    },
    'unread_count': unread,
    'last_read_inbox_message_id': readInbox,
    'is_pinned': false,
    'notification_settings': {'@type': 'chatNotificationSettings'},
  };
}

/// The fake TDLib forum: `viewMessages` advances a topic's watermark exactly
/// like TDLib, while pages can be frozen to the snapshot a slow request would
/// have returned.
class _ForumServer {
  final _topics = <int, _FakeTopic>{};
  final _held = <int, Completer<Map<String, dynamic>>>{};
  final _failing = <int>{};
  final viewMessages = <Map<String, dynamic>>[];

  Map<String, dynamic>? _frozenPage;

  void addTopic({
    required int id,
    required int lastMessageId,
    int unread = 0,
    int readInbox = 0,
  }) {
    _topics[id] = _FakeTopic(
      id: id,
      lastMessageId: lastMessageId,
      unread: unread,
      readInbox: readInbox,
    );
  }

  void freezePage() {
    _frozenPage = {
      '@type': 'forumTopics',
      'topics': [for (final topic in _topics.values) topic.toPageJson()],
    };
  }

  void failTopic(int topicId) => _failing.add(topicId);

  Completer<Map<String, dynamic>> holdTopic(int topicId) =>
      _held[topicId] = Completer<Map<String, dynamic>>();

  void reset() {
    _topics.clear();
    _held.clear();
    _failing.clear();
    viewMessages.clear();
    _frozenPage = null;
  }

  int? _topicForMessage(int messageId) {
    for (final topic in _topics.values) {
      if (topic.lastMessageId == messageId) return topic.id;
    }
    return null;
  }

  Future<Map<String, dynamic>> query(Map<String, dynamic> request) async {
    switch (request['@type']) {
      case 'getForumTopics':
        return _frozenPage ??
            {
              '@type': 'forumTopics',
              'topics': [
                for (final topic in _topics.values) topic.toPageJson(),
              ],
            };
      case 'viewMessages':
        viewMessages.add(Map<String, dynamic>.from(request));
        final messageId = (request['message_ids'] as List).single as int;
        final topicId = _topicForMessage(messageId);
        if (topicId == null) return {'@type': 'ok'};
        final held = _held[topicId];
        if (held != null) return held.future;
        if (_failing.contains(topicId)) {
          throw StateError('viewMessages failed for topic $topicId');
        }
        final topic = _topics[topicId]!;
        topic
          ..readInbox = topic.lastMessageId
          ..unread = 0;
        return {'@type': 'ok'};
      default:
        return {'@type': 'ok'};
    }
  }
}
