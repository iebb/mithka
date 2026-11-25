//
//  bot_topic_send_test.dart
//
//  A bot topic chat has no General topic, so the "All" view has nowhere to
//  put a new message: the send must start a topic named after the message,
//  land inside it and hand the id to the transcript host (the reference client
//  `BotForumHelper.beforeSendingFinalRequest` does the same). Topics the
//  loaded page predates must also join the tab strip and topic list live.
//

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/channels/topic_list_actions.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/forum_topic_index.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chatId = 42;

Map<String, dynamic> _rawMessage({required int id, int? topicId}) => {
  '@type': 'message',
  'id': id,
  'chat_id': _chatId,
  'date': id,
  'is_outgoing': false,
  'sender_id': {'@type': 'messageSenderUser', 'user_id': 7},
  if (topicId != null)
    'topic_id': {'@type': 'messageTopicForum', 'forum_topic_id': topicId},
  'content': {
    '@type': 'messageText',
    'text': {'@type': 'formattedText', 'text': 'hi'},
  },
};

Map<String, dynamic> _topicInfo(
  int topicId,
  String name, {
  int chatId = _chatId,
}) => {
  '@type': 'updateForumTopicInfo',
  'info': {
    '@type': 'forumTopicInfo',
    'chat_id': chatId,
    'forum_topic_id': topicId,
    'name': name,
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<String, dynamic>> requests;
  late Future<Map<String, dynamic>> Function(Map<String, dynamic>) handler;

  setUpAll(() async {
    await AppStrings.ensureLoaded(const Locale('en'));
    // In-memory transport only: these tests never touch a Telegram account.
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) {
          requests.add(request);
          return handler(request);
        },
        send: (_) async {},
        updates: const Stream.empty(),
      ),
    );
  });
  tearDownAll(TdClient.shared.closeProxy);

  setUp(() {
    requests = [];
    SharedPreferences.setMockInitialValues({});
    handler = (request) async => switch (request['@type']) {
      'createForumTopic' => {
        '@type': 'forumTopicInfo',
        'chat_id': _chatId,
        'forum_topic_id': 777,
        'name': 'started',
      },
      'sendMessage' || 'sendMessageAlbum' => {'@type': 'message', 'id': 99},
      'getForumTopic' => {
        '@type': 'forumTopic',
        'info': {
          '@type': 'forumTopicInfo',
          'chat_id': _chatId,
          'forum_topic_id': 20,
          'name': 'Fresh topic',
          'icon': {
            '@type': 'forumTopicIcon',
            'color': 0x6FB9F0,
            'custom_emoji_id': 0,
          },
        },
      },
      _ => {'@type': 'ok'},
    };
  });

  ChatViewModel model({int? forumTopicId}) {
    final vm = ChatViewModel(
      chatId: _chatId,
      title: 'Topic bot',
      markReadOnOpen: false,
      forumTopicId: forumTopicId,
    )..supportsBotTopicsForTesting(true);
    addTearDown(vm.dispose);
    return vm;
  }

  Map<String, dynamic>? createRequest() {
    for (final request in requests) {
      if (request['@type'] == 'createForumTopic') return request;
    }
    return null;
  }

  List<Map<String, dynamic>> sends() => [
    for (final request in requests)
      if (request['@type'] == 'sendMessage') request,
  ];

  group('implicit topic titles', () {
    test('take the first sixteen characters, ellipsised when trimmed', () {
      expect(botTopicTitleForMessage('Short one'), 'Short one');
      expect(botTopicTitleForMessage('Exactly16Chars!!'), 'Exactly16Chars!!');
      expect(
        botTopicTitleForMessage('Hello bot forum world'),
        'Hello bot forum...',
      );
    });

    test('collapse whitespace and empty out for media-only messages', () {
      expect(botTopicTitleForMessage('  Hello\n\n  world  '), 'Hello world');
      expect(botTopicTitleForMessage('   '), '');
    });
  });

  test('a send from All starts a topic named after the message', () async {
    final vm = model();

    expect(await vm.sendFormatted('Hello bot forum world', const []), isTrue);

    final create = createRequest();
    expect(create, isNotNull);
    expect(create!['chat_id'], _chatId);
    expect(create['name'], 'Hello bot forum...');
    expect(
      create['is_name_implicit'],
      isTrue,
      reason: 'the title previews the first message; the server owns it',
    );

    final message = sends().single;
    expect(
      (message['topic_id'] as Map<String, dynamic>)['forum_topic_id'],
      777,
    );
    expect(vm.consumePendingBotTopicOpen(), 777);
    expect(
      vm.consumePendingBotTopicOpen(),
      isNull,
      reason: 'the host follows a created topic once',
    );
  });

  test('a media-only send names its topic with the generic title', () async {
    final vm = model();

    expect(await vm.sendFormatted('🎲', const []), isTrue);

    expect(createRequest()!['name'], 'Topic');
    final message = sends().single;
    expect(
      (message['topic_id'] as Map<String, dynamic>)['forum_topic_id'],
      777,
    );
  });

  test(
    'a rich message from All starts a topic from its first text run',
    () async {
      final vm = model();

      await vm.sendRichMessageHtml(
        '<b>Hello rich world</b>',
        blocks: [
          {
            '@type': 'inputPageBlockParagraph',
            'text': {'@type': 'richTextPlain', 'text': 'Hello rich world'},
          },
        ],
      );

      final create = createRequest();
      expect(create, isNotNull, reason: 'rich text is still a new message');
      expect(create!['name'], 'Hello rich world');

      final message = sends().single;
      expect(
        (message['input_message_content'] as Map<String, dynamic>)['@type'],
        'inputMessageRichMessage',
      );
      expect(
        (message['topic_id'] as Map<String, dynamic>)['forum_topic_id'],
        777,
      );
      expect(vm.consumePendingBotTopicOpen(), 777);
    },
  );

  test('multi-segment rich sends land in one topic', () async {
    final vm = model();

    for (final part in ['Part one', 'Part two']) {
      await vm.sendRichMessageHtml(
        '<p>$part</p>',
        blocks: [
          {
            '@type': 'inputPageBlockParagraph',
            'text': {'@type': 'richTextPlain', 'text': part},
          },
        ],
      );
    }

    expect(
      requests.where((request) => request['@type'] == 'createForumTopic'),
      hasLength(1),
      reason: 'a rich document splits into segments; they share its topic',
    );
    expect(sends(), hasLength(2));
    for (final message in sends()) {
      expect(
        (message['topic_id'] as Map<String, dynamic>)['forum_topic_id'],
        777,
      );
    }
  });

  test('concurrent All sends share one topic creation', () async {
    final vm = model();

    final first = vm.sendFormatted('First message', const []);
    final second = vm.sendFormatted('Second message', const []);
    expect(await first, isTrue);
    expect(await second, isTrue);

    expect(
      requests.where((request) => request['@type'] == 'createForumTopic'),
      hasLength(1),
      reason: 'two quick sends must not open two topics',
    );
    expect(sends(), hasLength(2));
    for (final message in sends()) {
      expect(
        (message['topic_id'] as Map<String, dynamic>)['forum_topic_id'],
        777,
      );
    }
  });

  test('a topic transcript send never starts another topic', () async {
    final vm = model(forumTopicId: 55);

    expect(await vm.sendFormatted('Inside a topic', const []), isTrue);

    expect(createRequest(), isNull);
    expect(
      (sends().single['topic_id'] as Map<String, dynamic>)['forum_topic_id'],
      55,
    );
    expect(vm.consumePendingBotTopicOpen(), isNull);
  });

  test('a reply keeps resolving its own topic', () async {
    final vm = model()
      ..setReply(
        ChatMessage(
          id: 31,
          chatId: _chatId,
          isOutgoing: false,
          text: 'earlier',
          date: 5,
          contentType: 'messageText',
        ),
      );

    expect(await vm.sendFormatted('Answering you', const []), isTrue);

    expect(
      createRequest(),
      isNull,
      reason: 'the reply header already names the topic it answers in',
    );
    final message = sends().single;
    expect(message.containsKey('topic_id'), isFalse);
    expect(message.containsKey('reply_to'), isTrue);
  });

  test('a failed topic creation still sends the message unscoped', () async {
    handler = (request) async {
      if (request['@type'] == 'createForumTopic') {
        throw StateError('TOPIC_CREATE_FAILED');
      }
      return request['@type'] == 'sendMessage'
          ? {'@type': 'message', 'id': 99}
          : {'@type': 'ok'};
    };
    final vm = model();

    expect(await vm.sendFormatted('No topic for me', const []), isTrue);

    final message = sends().single;
    expect(message.containsKey('topic_id'), isFalse);
    expect(vm.consumePendingBotTopicOpen(), isNull);
  });

  test('the index gains a topic announced after its page loaded', () {
    const slot = 3;
    const chatId = 900;
    final index = ForumTopicIndex.shared;
    index.storeAll(slot, chatId, [
      const ForumTopicIndexEntry(id: 10, name: 'Old topic'),
    ]);
    addTearDown(() => index.storeAll(slot, chatId, const []));

    index.observe(slot, _topicInfo(20, 'Fresh topic', chatId: chatId));

    expect(
      [for (final entry in index.topicsFor(slot, chatId)) entry.id],
      [20, 10],
      reason: 'a new topic carries the newest activity and leads the list',
    );
    expect(index.knowsTopics(slot, chatId), isTrue);
  });

  test('the index ignores announcements before its page lands', () {
    const slot = 4;
    const chatId = 901;
    final index = ForumTopicIndex.shared;

    index.observe(slot, _topicInfo(30, 'Too early', chatId: chatId));

    expect(
      index.topicsFor(slot, chatId),
      isEmpty,
      reason:
          'the page is authoritative for membership it has not answered yet',
    );
  });

  test('traffic in a new topic asks TDLib and the strip gains it', () async {
    final vm = model()
      ..forumTopicsLoadedForTesting([
        const ForumTopicIndexEntry(id: 5, name: 'Old topic'),
      ]);

    vm.applyLiveUpdateForTesting({
      '@type': 'updateNewMessage',
      'message': _rawMessage(id: 60, topicId: 20),
    });
    await pumpEventQueue();

    expect(
      requests.where((request) => request['@type'] == 'getForumTopic'),
      hasLength(1),
    );
    expect([for (final topic in vm.forumTopics) topic.id], contains(20));
    expect([for (final topic in vm.forumTopics) topic.id].first, 20);
  });
}
