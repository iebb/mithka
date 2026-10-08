import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/tdlib/forum_topic_index.dart';
import 'package:mithka/tdlib/td_client.dart';

// Repeated refreshes must not stack listeners on the shared forum-topic
// index: dispose removes only one, so a duplicate registered by a refresh
// survives disposal and keeps mutating a disposed view model. Review
// observed a disposed model's topic count changing from 4 to 5 after two
// refreshes and a live update.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<Map<String, dynamic>> updates;
  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => switch (request['@type']) {
          'getForumTopics' => forumTopics(4),
          _ => <String, dynamic>{'@type': 'ok'},
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });
  setUp(ForumTopicIndex.shared.clear);
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  test('repeated refreshes keep one listener; dispose detaches it', () async {
    final model = ChatViewModel(
      chatId: -100,
      title: 'Forum',
      markReadOnOpen: false,
    )..isForum = true;

    await model.loadForumTopics();
    await model.loadForumTopics();
    expect(model.forumTopics.length, 4);

    model.dispose();

    // A live index update after disposal must not touch the dead model.
    ForumTopicIndex.shared.storeAll(0, -100, [
      ForumTopicIndexEntry.fromTopic(topic(1))!,
      ForumTopicIndexEntry.fromTopic(topic(2))!,
      ForumTopicIndexEntry.fromTopic(topic(3))!,
      ForumTopicIndexEntry.fromTopic(topic(4))!,
      ForumTopicIndexEntry.fromTopic(topic(5))!,
    ]);
    expect(
      model.forumTopics.length,
      4,
      reason: 'a disposed model must no longer follow index updates',
    );
  });
}

Map<String, dynamic> topic(int id) => {
  '@type': 'forumTopic',
  'info': {
    '@type': 'forumTopicInfo',
    'chat_id': -100,
    'forum_topic_id': id,
    'name': 'Topic $id',
  },
  'unread_count': 0,
};

Map<String, dynamic> forumTopics(int count) => {
  '@type': 'forumTopics',
  'topics': [for (var id = 1; id <= count; id++) topic(id)],
};
