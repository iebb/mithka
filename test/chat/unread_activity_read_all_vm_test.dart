//
//  unread_activity_read_all_vm_test.dart
//
//  The long-press "mark all as read" commands must use TDLib's scoped
//  read-all calls: readAllChatMentions / readAllChatReactions in a chat, and
//  the forum-topic variants inside a topic transcript. A refused call leaves
//  the counters so the pill stays and the user can retry.
//

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/tdlib/td_client.dart';

const _chatId = -10042;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final updates = StreamController<Map<String, dynamic>>.broadcast();
  final queries = <Map<String, dynamic>>[];
  var failReads = false;

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          queries.add(request);
          if (failReads && (request['@type'] as String).startsWith('readAll')) {
            throw StateError('refused');
          }
          return {'@type': 'ok'};
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
    failReads = false;
  });

  ChatViewModel model({int? topicId}) => ChatViewModel(
    chatId: _chatId,
    forumTopicId: topicId,
    title: 'Forum',
    markReadOnOpen: false,
  );

  test(
    'a topic transcript reads all mentions through the topic method',
    () async {
      final viewModel = model(topicId: 50)..unreadMentionCount = 2;
      addTearDown(viewModel.dispose);

      expect(await viewModel.markAllMentionsRead(), isTrue);
      final request = queries.single;
      expect(request['@type'], 'readAllForumTopicMentions');
      expect(request['chat_id'], _chatId);
      expect(request['forum_topic_id'], 50);
      expect(viewModel.unreadMentionCount, 0);
    },
  );

  test(
    'a topic transcript reads all reactions through the topic method',
    () async {
      final viewModel = model(topicId: 50)..unreadReactionCount = 3;
      addTearDown(viewModel.dispose);

      expect(await viewModel.markAllReactionsRead(), isTrue);
      final request = queries.single;
      expect(request['@type'], 'readAllForumTopicReactions');
      expect(request['chat_id'], _chatId);
      expect(request['forum_topic_id'], 50);
      expect(viewModel.unreadReactionCount, 0);
    },
  );

  test('a plain chat uses the chat-wide methods', () async {
    final viewModel = model()
      ..unreadMentionCount = 1
      ..unreadReactionCount = 1;
    addTearDown(viewModel.dispose);

    expect(await viewModel.markAllMentionsRead(), isTrue);
    expect(await viewModel.markAllReactionsRead(), isTrue);
    expect(queries.map((request) => request['@type']), [
      'readAllChatMentions',
      'readAllChatReactions',
    ]);
    for (final request in queries) {
      expect(request.containsKey('forum_topic_id'), isFalse);
    }
  });

  test('a refused call keeps the counter for a retry', () async {
    failReads = true;
    final viewModel = model()
      ..unreadMentionCount = 4
      ..unreadReactionCount = 2;
    addTearDown(viewModel.dispose);

    expect(await viewModel.markAllMentionsRead(), isFalse);
    expect(await viewModel.markAllReactionsRead(), isFalse);
    expect(viewModel.unreadMentionCount, 4);
    expect(viewModel.unreadReactionCount, 2);
  });
}
