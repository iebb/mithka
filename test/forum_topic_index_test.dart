import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/tdlib/forum_topic_index.dart';

/// A `forumTopic` page item shaped like the pinned TDLib schema: the
/// read/message bookkeeping lives on the outer topic, `info` carries only
/// the identity fields (and its own chat_id).
Map<String, dynamic> _topic(
  int id, {
  String name = 'Topic',
  int unread = 0,
  int? lastMessageId,
  int lastReadInbox = 0,
  int muteFor = 0,
  int iconColor = 0,
}) => {
  '@type': 'forumTopic',
  'info': {
    '@type': 'forumTopicInfo',
    'chat_id': -100,
    'forum_topic_id': id,
    'name': name,
    'icon_color': iconColor,
  },
  if (lastMessageId != null)
    'last_message': {'@type': 'message', 'id': lastMessageId},
  'unread_count': unread,
  'last_read_inbox_message_id': lastReadInbox,
  'notification_settings': {
    '@type': 'chatNotificationSettings',
    'mute_for': muteFor,
  },
};

Map<String, dynamic> _newMessage(
  int id, {
  required int chatId,
  int? topicId,
  bool outgoing = false,
}) => {
  '@type': 'updateNewMessage',
  'message': {
    '@type': 'message',
    'id': id,
    'chat_id': chatId,
    'is_outgoing': outgoing,
    if (topicId != null)
      'topic_id': {'@type': 'messageTopicForum', 'forum_topic_id': topicId},
    'content': {'@type': 'messageText'},
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(ForumTopicIndex.shared.clear);

  test('parses a topic page and reports membership', () {
    ForumTopicIndex.shared.storeAll(0, -100, [
      ForumTopicIndexEntry.fromTopic(_topic(1, name: 'General', unread: 3))!,
      ForumTopicIndexEntry.fromTopic(_topic(7, name: 'Dev'))!,
    ]);
    expect(ForumTopicIndex.shared.knowsTopics(0, -100), isTrue);
    final topics = ForumTopicIndex.shared.topicsFor(0, -100);
    expect(topics.length, 2);
    expect(ForumTopicIndex.shared.entryFor(0, -100, 7)?.name, 'Dev');
    expect(ForumTopicIndex.shared.entryFor(0, -100, 9), isNull);
    expect(ForumTopicIndex.shared.topicsFor(0, -200), isEmpty);
    expect(ForumTopicIndex.shared.topicsFor(1, -100), isEmpty);
  });

  test('the read watermark is parsed from the outer topic object', () {
    // last_read_inbox_message_id is a field of the topic, not of info; a
    // page that already contains a read position must seed it.
    ForumTopicIndex.shared.storeAll(0, -100, [
      ForumTopicIndexEntry.fromTopic(
        _topic(7, unread: 2, lastMessageId: 100, lastReadInbox: 90),
      )!,
    ]);
    expect(
      ForumTopicIndex.shared.entryFor(0, -100, 7)?.lastReadInboxMessageId,
      90,
    );
  });

  test('an empty page drops the chat from the index', () {
    ForumTopicIndex.shared.storeAll(0, -100, [
      ForumTopicIndexEntry.fromTopic(_topic(1))!,
    ]);
    ForumTopicIndex.shared.storeAll(0, -100, const []);
    expect(ForumTopicIndex.shared.knowsTopics(0, -100), isFalse);
  });

  test('new messages bump only the target topic counter', () {
    ForumTopicIndex.shared.storeAll(0, -100, [
      ForumTopicIndexEntry.fromTopic(
        _topic(7, unread: 2, lastMessageId: 100, lastReadInbox: 90),
      )!,
    ]);
    ForumTopicIndex.shared.observe(
      0,
      _newMessage(101, chatId: -100, topicId: 7),
    );
    expect(ForumTopicIndex.shared.entryFor(0, -100, 7)?.unreadCount, 3);
    expect(ForumTopicIndex.shared.entryFor(0, -100, 7)?.lastMessageId, 101);

    // Outgoing traffic never inflates the counter.
    ForumTopicIndex.shared.observe(
      0,
      _newMessage(102, chatId: -100, topicId: 7, outgoing: true),
    );
    expect(ForumTopicIndex.shared.entryFor(0, -100, 7)?.unreadCount, 3);
    // But its id is still the newest known message.
    expect(ForumTopicIndex.shared.entryFor(0, -100, 7)?.lastMessageId, 102);
  });

  test('a message without a topic reference lands in General', () {
    ForumTopicIndex.shared.storeAll(0, -100, [
      ForumTopicIndexEntry.fromTopic(_topic(1, lastMessageId: 4))!,
    ]);
    ForumTopicIndex.shared.observe(0, _newMessage(5, chatId: -100));
    expect(ForumTopicIndex.shared.entryFor(0, -100, 1)?.unreadCount, 1);
  });

  test('already-read and already-counted arrivals do not invent unread', () {
    ForumTopicIndex.shared.storeAll(0, -100, [
      ForumTopicIndexEntry.fromTopic(
        _topic(7, lastMessageId: 100, lastReadInbox: 100),
      )!,
    ]);
    // A fully read topic receiving an id at its watermark stays at zero…
    ForumTopicIndex.shared.observe(
      0,
      _newMessage(100, chatId: -100, topicId: 7),
    );
    expect(
      ForumTopicIndex.shared.entryFor(0, -100, 7)?.unreadCount,
      0,
      reason: 'a message at the watermark was already read',
    );
    // …and so does an id the fetched page already represented.
    ForumTopicIndex.shared.observe(
      0,
      _newMessage(99, chatId: -100, topicId: 7),
    );
    expect(
      ForumTopicIndex.shared.entryFor(0, -100, 7)?.unreadCount,
      0,
      reason: 'a message inside the fetched page was counted there',
    );
    // Genuinely new traffic still counts.
    ForumTopicIndex.shared.observe(
      0,
      _newMessage(101, chatId: -100, topicId: 7),
    );
    expect(ForumTopicIndex.shared.entryFor(0, -100, 7)?.unreadCount, 1);
  });

  test('reading to the newest message clears the counter', () {
    ForumTopicIndex.shared.storeAll(0, -100, [
      ForumTopicIndexEntry.fromTopic(
        _topic(7, unread: 4, lastMessageId: 200, lastReadInbox: 180),
      )!,
    ]);
    ForumTopicIndex.shared.observe(0, {
      '@type': 'updateForumTopic',
      'chat_id': -100,
      'forum_topic_id': 7,
      'last_read_inbox_message_id': 200,
    });
    final entry = ForumTopicIndex.shared.entryFor(0, -100, 7);
    expect(entry?.unreadCount, 0);
    expect(entry?.lastReadInboxMessageId, 200);
  });

  test('a partial read persists its watermark without waking listeners', () {
    ForumTopicIndex.shared.storeAll(0, -100, [
      ForumTopicIndexEntry.fromTopic(
        _topic(7, unread: 4, lastMessageId: 200, lastReadInbox: 180),
      )!,
    ]);
    var notifications = 0;
    ForumTopicIndex.shared.addListener(() => notifications++);

    ForumTopicIndex.shared.observe(0, {
      '@type': 'updateForumTopic',
      'chat_id': -100,
      'forum_topic_id': 7,
      'last_read_inbox_message_id': 190,
    });
    final entry = ForumTopicIndex.shared.entryFor(0, -100, 7);
    expect(entry?.unreadCount, 4, reason: 'a partial read keeps the counter');
    expect(
      entry?.lastReadInboxMessageId,
      190,
      reason: 'but the watermark must persist for later reconciliation',
    );
    expect(notifications, 0, reason: 'nothing displayed moved');

    // The persisted watermark now recognizes replays as already read.
    ForumTopicIndex.shared.observe(
      0,
      _newMessage(185, chatId: -100, topicId: 7),
    );
    expect(
      ForumTopicIndex.shared.entryFor(0, -100, 7)?.unreadCount,
      4,
      reason: 'an id below the persisted watermark is not new unread',
    );
  });

  test('mute state follows notification settings updates', () {
    ForumTopicIndex.shared.storeAll(0, -100, [
      ForumTopicIndexEntry.fromTopic(_topic(7))!,
    ]);
    ForumTopicIndex.shared.observe(0, {
      '@type': 'updateForumTopic',
      'chat_id': -100,
      'forum_topic_id': 7,
      'notification_settings': {
        '@type': 'chatNotificationSettings',
        'mute_for': 3600,
      },
    });
    expect(ForumTopicIndex.shared.entryFor(0, -100, 7)?.isMuted, isTrue);
  });

  test('a live counter ahead of a stale page wins over the page', () {
    ForumTopicIndex.shared.storeAll(0, -100, [
      ForumTopicIndexEntry.fromTopic(
        _topic(7, unread: 1, lastMessageId: 300, lastReadInbox: 290),
      )!,
    ]);
    ForumTopicIndex.shared.observe(
      0,
      _newMessage(301, chatId: -100, topicId: 7),
    );
    // The stale page still reports the pre-bump snapshot.
    ForumTopicIndex.shared.storeAll(0, -100, [
      ForumTopicIndexEntry.fromTopic(
        _topic(7, unread: 1, lastMessageId: 300, lastReadInbox: 290),
      )!,
    ]);
    expect(ForumTopicIndex.shared.entryFor(0, -100, 7)?.unreadCount, 2);
    // A page that caught up is authoritative again.
    ForumTopicIndex.shared.storeAll(0, -100, [
      ForumTopicIndexEntry.fromTopic(
        _topic(7, unread: 5, lastMessageId: 301, lastReadInbox: 290),
      )!,
    ]);
    expect(ForumTopicIndex.shared.entryFor(0, -100, 7)?.unreadCount, 5);
  });

  test('renames through updateForumTopicInfo update the entry', () {
    ForumTopicIndex.shared.storeAll(0, -100, [
      ForumTopicIndexEntry.fromTopic(_topic(7, name: 'Old'))!,
    ]);
    ForumTopicIndex.shared.observe(0, {
      '@type': 'updateForumTopicInfo',
      'info': {
        '@type': 'forumTopicInfo',
        'chat_id': -100,
        'forum_topic_id': 7,
        'name': 'New',
        'icon': {
          '@type': 'forumTopicIcon',
          'custom_emoji_id': 55,
          'color': 0xFF1122,
        },
      },
    });
    final entry = ForumTopicIndex.shared.entryFor(0, -100, 7);
    expect(entry?.name, 'New');
    expect(entry?.iconCustomEmojiId, 55);
    expect(entry?.iconColor, 0xFF1122);
  });

  test('updateForumTopicInfo routes by its own chat identity', () {
    // Two forums reuse topic id 7; the update names chat -200.
    ForumTopicIndex.shared.storeAll(0, -100, [
      ForumTopicIndexEntry.fromTopic(_topic(7, name: 'First chat'))!,
    ]);
    ForumTopicIndex.shared.storeAll(0, -200, [
      ForumTopicIndexEntry.fromTopic(_topic(7, name: 'Second chat'))!,
    ]);
    ForumTopicIndex.shared.observe(0, {
      '@type': 'updateForumTopicInfo',
      'info': {
        '@type': 'forumTopicInfo',
        'chat_id': -200,
        'forum_topic_id': 7,
        'name': 'Renamed',
      },
    });
    expect(ForumTopicIndex.shared.entryFor(0, -100, 7)?.name, 'First chat');
    expect(ForumTopicIndex.shared.entryFor(0, -200, 7)?.name, 'Renamed');

    // An update for a chat the index never saw is ignored, not misrouted.
    ForumTopicIndex.shared.observe(0, {
      '@type': 'updateForumTopicInfo',
      'info': {
        '@type': 'forumTopicInfo',
        'chat_id': -300,
        'forum_topic_id': 7,
        'name': 'Ghost',
      },
    });
    expect(ForumTopicIndex.shared.entryFor(0, -100, 7)?.name, 'First chat');
    expect(ForumTopicIndex.shared.entryFor(0, -200, 7)?.name, 'Renamed');
  });

  test('listeners wake on counter changes, not on bookkeeping', () {
    ForumTopicIndex.shared.storeAll(0, -100, [
      ForumTopicIndexEntry.fromTopic(
        _topic(7, unread: 2, lastMessageId: 100, lastReadInbox: 90),
      )!,
    ]);
    var notifications = 0;
    ForumTopicIndex.shared.addListener(() => notifications++);

    ForumTopicIndex.shared.observe(
      0,
      _newMessage(101, chatId: -100, topicId: 7),
    );
    expect(notifications, 1);

    // A read position below the known one is bookkeeping only.
    ForumTopicIndex.shared.observe(0, {
      '@type': 'updateForumTopic',
      'chat_id': -100,
      'forum_topic_id': 7,
      'last_read_inbox_message_id': 95,
    });
    expect(notifications, 1);

    // Storing the same page again changes nothing displayed.
    ForumTopicIndex.shared.storeAll(0, -100, [
      ForumTopicIndexEntry.fromTopic(
        _topic(7, unread: 3, lastMessageId: 101, lastReadInbox: 95),
      )!,
    ]);
    expect(notifications, 1);
  });

  test('clearSlot drops only that slot', () {
    ForumTopicIndex.shared.storeAll(0, -100, [
      ForumTopicIndexEntry.fromTopic(_topic(7))!,
    ]);
    ForumTopicIndex.shared.storeAll(1, -100, [
      ForumTopicIndexEntry.fromTopic(_topic(8))!,
    ]);
    ForumTopicIndex.shared.clearSlot(0);
    expect(ForumTopicIndex.shared.knowsTopics(0, -100), isFalse);
    expect(ForumTopicIndex.shared.knowsTopics(1, -100), isTrue);
  });
}
