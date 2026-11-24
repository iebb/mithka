//
//  forum_topic_tab_order_test.dart
//
//  The topic tabs must keep the order the reference client keeps: pinned topics first
//  in their pin order, everything else by the newest message — live, as
//  traffic lands, not only after a getForumTopics round-trip. The shared
//  index owns that order so the strip, the rail and the topic list all read
//  the same sequence.
//

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/forum_topic_index.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chatId = 421;

Map<String, dynamic> _newMessage({
  required int id,
  required int topicId,
  int chatId = _chatId,
  bool outgoing = false,
}) => {
  '@type': 'updateNewMessage',
  'message': {
    '@type': 'message',
    'id': id,
    'chat_id': chatId,
    'date': id,
    'is_outgoing': outgoing,
    'sender_id': {'@type': 'messageSenderUser', 'user_id': 7},
    'topic_id': {'@type': 'messageTopicForum', 'forum_topic_id': topicId},
    'content': {
      '@type': 'messageText',
      'text': {'@type': 'formattedText', 'text': 'hi'},
    },
  },
};

Map<String, dynamic> _topicPin({
  required int topicId,
  required bool pinned,
  int chatId = _chatId,
  int lastReadInboxMessageId = 0,
}) => {
  '@type': 'updateForumTopic',
  'chat_id': chatId,
  'forum_topic_id': topicId,
  'is_pinned': pinned,
  'last_read_inbox_message_id': lastReadInboxMessageId,
  'notification_settings': {'@type': 'chatNotificationSettings', 'mute_for': 0},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await AppStrings.ensureLoaded(const Locale('en'));
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (_) async => {'@type': 'ok'},
        send: (_) async {},
        updates: const Stream.empty(),
      ),
    );
  });
  tearDownAll(TdClient.shared.closeProxy);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ForumTopicIndex order', () {
    const slot = 11;

    List<int> ids(ForumTopicIndex index, int chatId) => [
      for (final entry in index.topicsFor(slot, chatId)) entry.id,
    ];

    test('pinned topics lead in page order, then newest activity', () {
      const chatId = 701;
      final index = ForumTopicIndex.shared;
      index.storeAll(slot, chatId, [
        const ForumTopicIndexEntry(
          id: 11,
          name: 'Second pin',
          isPinned: true,
          lastMessageId: 100,
        ),
        const ForumTopicIndexEntry(
          id: 10,
          name: 'First pin',
          isPinned: true,
          lastMessageId: 500,
        ),
        const ForumTopicIndexEntry(id: 20, name: 'Older', lastMessageId: 300),
        const ForumTopicIndexEntry(id: 21, name: 'Newest', lastMessageId: 900),
      ]);
      addTearDown(() => index.storeAll(slot, chatId, const []));

      expect(
        ids(index, chatId),
        [11, 10, 21, 20],
        reason:
            'pins keep the page order (11 leads even with older traffic), '
            'the rest sort by their newest message',
      );
    });

    test('a page always replaces the pin order', () {
      const chatId = 702;
      final index = ForumTopicIndex.shared;
      index.storeAll(slot, chatId, [
        const ForumTopicIndexEntry(id: 10, name: 'A', isPinned: true),
        const ForumTopicIndexEntry(id: 11, name: 'B', isPinned: true),
      ]);
      addTearDown(() => index.storeAll(slot, chatId, const []));
      expect(ids(index, chatId), [10, 11]);

      index.storeAll(slot, chatId, [
        const ForumTopicIndexEntry(id: 11, name: 'B', isPinned: true),
        const ForumTopicIndexEntry(id: 10, name: 'A', isPinned: true),
      ]);

      expect(ids(index, chatId), [11, 10]);
    });

    test('an incoming message moves its topic up without a reload', () {
      const chatId = 703;
      final index = ForumTopicIndex.shared;
      index.storeAll(slot, chatId, [
        const ForumTopicIndexEntry(id: 20, name: 'Older', lastMessageId: 300),
        const ForumTopicIndexEntry(id: 21, name: 'Newest', lastMessageId: 900),
      ]);
      addTearDown(() => index.storeAll(slot, chatId, const []));
      expect(ids(index, chatId), [21, 20]);

      index.observe(slot, _newMessage(id: 1200, topicId: 20, chatId: chatId));

      expect(
        ids(index, chatId),
        [20, 21],
        reason: 'the new message makes topic 20 the most recent one',
      );
    });

    test('an outgoing message also moves its topic up', () {
      const chatId = 704;
      final index = ForumTopicIndex.shared;
      index.storeAll(slot, chatId, [
        const ForumTopicIndexEntry(id: 20, name: 'Mine', lastMessageId: 900),
        const ForumTopicIndexEntry(id: 21, name: 'Theirs', lastMessageId: 300),
      ]);
      addTearDown(() => index.storeAll(slot, chatId, const []));
      expect(ids(index, chatId), [20, 21]);

      index.observe(
        slot,
        _newMessage(id: 1400, topicId: 21, chatId: chatId, outgoing: true),
      );

      expect(
        ids(index, chatId),
        [21, 20],
        reason: 'our own message is that topic\'s newest activity too',
      );
    });

    test('a pin update moves the topic into the pinned block', () {
      const chatId = 705;
      final index = ForumTopicIndex.shared;
      index.storeAll(slot, chatId, [
        const ForumTopicIndexEntry(id: 20, name: 'A', lastMessageId: 300),
        const ForumTopicIndexEntry(id: 21, name: 'B', lastMessageId: 900),
      ]);
      addTearDown(() => index.storeAll(slot, chatId, const []));
      expect(ids(index, chatId), [21, 20]);

      index.observe(slot, _topicPin(topicId: 20, pinned: true, chatId: chatId));
      expect(ids(index, chatId), [20, 21]);

      index.observe(
        slot,
        _topicPin(topicId: 20, pinned: false, chatId: chatId),
      );
      expect(ids(index, chatId), [21, 20]);
    });

    test('a topic announced live leads until its traffic is known', () {
      const chatId = 706;
      final index = ForumTopicIndex.shared;
      index.storeAll(slot, chatId, [
        const ForumTopicIndexEntry(id: 20, name: 'Known', lastMessageId: 900),
      ]);
      addTearDown(() => index.storeAll(slot, chatId, const []));

      index.observe(slot, {
        '@type': 'updateForumTopicInfo',
        'info': {
          '@type': 'forumTopicInfo',
          'chat_id': chatId,
          'forum_topic_id': 30,
          'name': 'Fresh',
        },
      });

      expect(
        ids(index, chatId),
        [30, 20],
        reason: 'a new topic carries the newest activity by contract',
      );
    });
  });

  group('ChatViewModel topic order', () {
    ChatViewModel model() {
      final vm = ChatViewModel(
        chatId: _chatId,
        title: 'Forum',
        markReadOnOpen: false,
      )..isForumForTesting(true);
      addTearDown(vm.dispose);
      return vm;
    }

    List<int> ids(ChatViewModel vm) => [for (final t in vm.forumTopics) t.id];

    test('starts from the index order and follows live traffic', () {
      final vm = model();
      vm.forumTopicsLoadedForTesting(const [
        ForumTopicIndexEntry(id: 10, name: 'Older', lastMessageId: 100),
        ForumTopicIndexEntry(id: 20, name: 'Newest', lastMessageId: 200),
      ]);
      expect(ids(vm), [20, 10]);

      vm.applyLiveUpdateForTesting(_newMessage(id: 900, topicId: 10));

      expect(
        ids(vm),
        [10, 20],
        reason: 'the tab strip reads this list, so the order must move with it',
      );
    });

    test('a pin update re-sorts the strip rows', () {
      final vm = model();
      vm.forumTopicsLoadedForTesting(const [
        ForumTopicIndexEntry(id: 10, name: 'Older', lastMessageId: 100),
        ForumTopicIndexEntry(id: 20, name: 'Newest', lastMessageId: 200),
      ]);
      expect(ids(vm), [20, 10]);

      vm.applyLiveUpdateForTesting(_topicPin(topicId: 10, pinned: true));

      expect(ids(vm), [10, 20]);
      expect(
        vm.forumTopics.first.isPinned,
        isTrue,
        reason: 'the row keeps the pin the index now orders by',
      );
    });
  });
}
