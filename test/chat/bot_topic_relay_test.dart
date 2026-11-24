//
//  bot_topic_relay_test.dart
//
//  The rich-message relay bot composes in the user's own chat with the bot and
//  copies the result into the target chat with a forward the view model never
//  builds. A bot topic chat's "All" view therefore has to hand the topic to the
//  relay, or the copy lands nowhere — and one rich document, which arrives as
//  several segments, must stay in the one topic it started.
//

import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/composer/rich_message_bot_relay.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chatId = 42;
const _relayToken = '123456:AAG-relay-test-token';
const _newTopicId = 777;

Map<String, dynamic> _paragraph(String text) => {
  '@type': 'inputPageBlockParagraph',
  'text': {'@type': 'richTextPlain', 'text': text},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<String, dynamic>> requests;
  late Future<Map<String, dynamic>> Function(Map<String, dynamic>) handler;
  late List<http.Request> botApiCalls;

  setUpAll(() async {
    await AppStrings.ensureLoaded(const Locale('en'));
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
    botApiCalls = [];
    SharedPreferences.setMockInitialValues({});
    handler = (request) async => switch (request['@type']) {
      'createForumTopic' => {
        '@type': 'forumTopicInfo',
        'chat_id': _chatId,
        'forum_topic_id': _newTopicId,
        'name': 'started',
      },
      'createPrivateChat' => {'@type': 'chat', 'id': 555},
      'getMessageProperties' => {
        '@type': 'messageProperties',
        'can_be_forwarded': true,
        'can_be_copied': true,
      },
      'getChatHistory' => {
        '@type': 'messages',
        // The relayed Bot API message 5 as TDLib sees it.
        'messages': [
          {'@type': 'message', 'id': 5 << 20},
        ],
      },
      'forwardMessages' => {
        '@type': 'messages',
        'messages': [
          {'@type': 'message', 'id': 9001},
        ],
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

  RichMessageBotRelay relay() {
    final client = MockClient((request) async {
      botApiCalls.add(request);
      final method = request.url.pathSegments.last;
      final result = switch (method) {
        'getMe' => {
          '@type': 'user',
          'id': 999,
          'is_bot': true,
          'first_name': 'Relay',
        },
        'sendRichMessage' => {'message_id': 5, 'date': 1700000000},
        _ => true,
      };
      return http.Response(
        jsonEncode({'ok': true, 'result': result}),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });
    return RichMessageBotRelay(
      httpClient: client,
      apiBase: Uri.parse('https://relay.test'),
    );
  }

  test('the relay copies a rich message into the topic All started', () async {
    final vm = model();
    final topicRef = await vm.botTopicRefForSend(
      html: '<b>Hello relay</b>',
      blocks: [_paragraph('Hello relay')],
    );

    expect(createRequest()!['name'], 'Hello relay');
    expect(topicRef, {
      '@type': 'messageTopicForum',
      'forum_topic_id': _newTopicId,
    });

    final bot = relay();
    await bot.sendAndCopy(
      token: _relayToken,
      html: '<b>Hello relay</b>',
      currentUserId: 7,
      targetChatId: _chatId,
      tdClient: TdClient.shared,
      blocks: [_paragraph('Hello relay')],
      topicRef: topicRef,
    );
    bot.close();
    vm.announceBotTopicRef(topicRef);

    final forward = requests.firstWhere(
      (request) => request['@type'] == 'forwardMessages',
    );
    expect(forward['chat_id'], _chatId);
    expect(
      (forward['topic_id'] as Map<String, dynamic>)['forum_topic_id'],
      _newTopicId,
      reason: 'a copy without the topic lands in no topic at all',
    );
    expect(botApiCalls.map((call) => call.url.pathSegments.last), [
      'getMe',
      'getChat',
      'sendRichMessage',
      'deleteMessage',
    ]);
    expect(vm.consumePendingBotTopicOpen(), _newTopicId);
  });

  test('every segment of one relayed document reuses its topic', () async {
    final vm = model();
    final first = await vm.botTopicRefForSend(
      html: '<b>Part one</b>',
      blocks: [_paragraph('Part one')],
    );
    final second = await vm.botTopicRefForSend(
      html: '<b>Part two</b>',
      blocks: [_paragraph('Part two')],
    );

    expect(
      requests.where((request) => request['@type'] == 'createForumTopic'),
      hasLength(1),
    );
    expect(second, first);

    final bot = relay();
    for (final part in ['Part one', 'Part two']) {
      await bot.sendAndCopy(
        token: _relayToken,
        html: '<b>$part</b>',
        currentUserId: 7,
        targetChatId: _chatId,
        tdClient: TdClient.shared,
        blocks: [_paragraph(part)],
        topicRef: second,
      );
      vm.announceBotTopicRef(second);
    }
    bot.close();

    final forwards = requests.where(
      (request) => request['@type'] == 'forwardMessages',
    );
    expect(forwards, hasLength(2));
    for (final forward in forwards) {
      expect(
        (forward['topic_id'] as Map<String, dynamic>)['forum_topic_id'],
        _newTopicId,
      );
    }
  });

  test('a topic transcript hands the relay no topic of its own', () async {
    final vm = model(forumTopicId: 5);

    expect(await vm.botTopicRefForSend(html: '<b>Inside</b>'), isNull);
    expect(createRequest(), isNull);
  });

  test('a relayed copy without a topic stays unscoped', () async {
    final bot = relay();
    await bot.sendAndCopy(
      token: _relayToken,
      html: '<b>No topic</b>',
      currentUserId: 7,
      targetChatId: _chatId,
      tdClient: TdClient.shared,
      blocks: [_paragraph('No topic')],
    );
    bot.close();

    final forward = requests.firstWhere(
      (request) => request['@type'] == 'forwardMessages',
    );
    expect(forward.containsKey('topic_id'), isFalse);
  });
}
