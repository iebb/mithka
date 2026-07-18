import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/bot_platform_service.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  test('rich bot buttons preserve style and custom emoji metadata', () {
    final danger = BotButtonPresentation.fromJson({
      'text': 'Delete',
      'icon_custom_emoji_id': '9988',
      'style': {'@type': 'buttonStyleDanger'},
      'type': {
        '@type': 'inlineKeyboardButtonTypeCallback',
        'data': base64Encode(utf8.encode('remove')),
      },
    });
    final success = BotButtonPresentation.fromJson({
      'text': 'Done',
      'style': 'buttonStyleSuccess',
      'type': {'@type': 'keyboardButtonTypeText'},
    });

    expect(danger.style, BotButtonStyle.danger);
    expect(danger.customEmojiId, 9988);
    expect(danger.type, 'inlineKeyboardButtonTypeCallback');
    expect(success.style, BotButtonStyle.success);
    expect(
      BotPlatformService.callbackData({
        'data': base64Encode(utf8.encode('remove')),
      }),
      'remove',
    );
  });

  test('TD message buttons parse rich presentation for both keyboards', () {
    final inline = TDParse.messageButtonRows({
      '@type': 'replyMarkupInlineKeyboard',
      'rows': [
        [
          {
            '@type': 'inlineKeyboardButton',
            'text': 'Delete',
            'icon_custom_emoji_id': '9988',
            'style': {'@type': 'buttonStyleDanger'},
            'type': {
              '@type': 'inlineKeyboardButtonTypeCallback',
              'data': 'remove',
            },
          },
        ],
      ],
    }).single.single;
    final reply = TDParse.messageButtonRows({
      '@type': 'replyMarkupShowKeyboard',
      'rows': [
        [
          {
            '@type': 'keyboardButton',
            'text': 'Continue',
            'icon_custom_emoji_id': 7766,
            'style': 'buttonStyleSuccess',
            'type': {'@type': 'keyboardButtonTypeText'},
          },
        ],
      ],
    }).single.single;
    final managedBot = TDParse.messageButtonRows({
      '@type': 'replyMarkupShowKeyboard',
      'rows': [
        [
          {
            '@type': 'keyboardButton',
            'text': 'Create helper',
            'type': {
              '@type': 'keyboardButtonTypeRequestManagedBot',
              'id': 42,
              'suggested_name': 'Helper',
              'suggested_username': 'helper_bot',
            },
          },
        ],
      ],
    }).single.single;

    expect(inline.style, MessageButtonStyle.danger);
    expect(inline.iconCustomEmojiId, 9988);
    expect(inline.isReplyKeyboard, isFalse);
    expect(reply.style, MessageButtonStyle.success);
    expect(reply.iconCustomEmojiId, 7766);
    expect(reply.isReplyKeyboard, isTrue);
    expect(managedBot.requestId, 42);
    expect(managedBot.suggestedName, 'Helper');
    expect(managedBot.suggestedUsername, 'helper_bot');
  });

  test('guest query updates retain message and reference context', () {
    final query = BotGuestQuery.fromUpdate({
      '@type': 'updateNewGuestQuery',
      'id': '55',
      'message': {'@type': 'message', 'id': 8},
      'reference_messages': [
        {'@type': 'message', 'id': 7},
      ],
    });

    expect(query.id, 55);
    expect(query.message['id'], 8);
    expect(query.referenceMessages.single['id'], 7);
  });

  test('inline invocation and result page retain send identifiers', () {
    final invocation = BotInlineInvocation.fromText('@toolbot red panda');
    final page = BotInlineResultsPage.fromJson({
      '@type': 'inlineQueryResults',
      'inline_query_id': '9876543210',
      'next_offset': 'next',
      'results': [
        {
          '@type': 'inlineQueryResultArticle',
          'id': 'article-1',
          'title': 'Red panda',
          'description': 'An article result',
        },
        {
          '@type': 'inlineQueryResultVenue',
          'id': 'venue-1',
          'venue': {'title': 'Zoo', 'address': 'Tokyo'},
        },
      ],
    });

    expect(invocation?.username, 'toolbot');
    expect(invocation?.query, 'red panda');
    expect(BotInlineInvocation.fromText('hello @toolbot'), isNull);
    expect(page.queryId, 9876543210);
    expect(page.nextOffset, 'next');
    expect(page.results.map((value) => value.id), ['article-1', 'venue-1']);
    expect(page.results.last.title, 'Zoo');
    expect(page.results.last.description, 'Tokyo');
  });

  test(
    'bot capabilities expose inline, guest, topic, and manager flags',
    () async {
      final requests = <Map<String, dynamic>>[];
      final service = BotPlatformService(
        query: (request) async {
          requests.add(request);
          return switch (request['@type']) {
            'searchPublicChat' => {
              '@type': 'chat',
              'type': {'@type': 'chatTypePrivate', 'user_id': 77},
            },
            'getUser' => {
              '@type': 'user',
              'id': 77,
              'usernames': {
                '@type': 'usernames',
                'active_usernames': ['toolbot'],
                'editable_username': '',
                'disabled_usernames': <String>[],
              },
              'type': {
                '@type': 'userTypeBot',
                'can_be_added_to_attachment_menu': true,
                'can_manage_bots': true,
                'has_topics': true,
                'is_inline': true,
                'inline_query_placeholder': 'Search tools',
                'supports_guest_queries': true,
                'allows_users_to_create_topics': true,
              },
            },
            _ => throw StateError('Unexpected request'),
          };
        },
      );

      final value = await service.capabilitiesForUsername('@toolbot');

      expect(requests.first['username'], 'toolbot');
      expect(value.userId, 77);
      expect(value.username, 'toolbot');
      expect(value.inlineMode, isTrue);
      expect(value.inlinePlaceholder, 'Search tools');
      expect(value.supportsGuestQueries, isTrue);
      expect(value.hasTopics, isTrue);
      expect(value.allowsUsersToCreateTopics, isTrue);
      expect(value.canManageBots, isTrue);
      expect(value.canBeAddedToAttachmentMenu, isTrue);
    },
  );

  test(
    'bot capabilities support direct user lookup and account type',
    () async {
      final requests = <Map<String, dynamic>>[];
      final service = BotPlatformService(
        query: (request) async {
          requests.add(request);
          return switch (request['@type']) {
            'getUser' => {
              '@type': 'user',
              'id': 88,
              'usernames': {
                '@type': 'usernames',
                'active_usernames': <String>[],
                'editable_username': '',
              },
              'type': {
                '@type': 'userTypeBot',
                'is_inline': true,
                'inline_query_placeholder': '',
              },
            },
            'getMe' => {
              '@type': 'user',
              'id': 99,
              'type': {'@type': 'userTypeBot'},
            },
            _ => throw StateError('Unexpected request'),
          };
        },
      );

      final capabilities = await service.capabilitiesForUserId(
        88,
        fallbackUsername: '@direct_bot',
      );

      expect(capabilities.userId, 88);
      expect(capabilities.username, 'direct_bot');
      expect(capabilities.inlineMode, isTrue);
      expect(await service.currentAccountIsBot(), isTrue);
      expect(requests.map((value) => value['@type']), ['getUser', 'getMe']);
    },
  );

  test('platform actions match pinned TDLib request shapes', () async {
    final requests = <Map<String, dynamic>>[];
    final service = BotPlatformService(
      query: (request) async {
        requests.add(request);
        return {'@type': 'ok'};
      },
    );

    await service.inlineResults(
      botUserId: 10,
      chatId: 20,
      query: 'cats',
      offset: 'next',
    );
    await service.sendInlineResult(
      chatId: 20,
      queryId: 30,
      resultId: 'result-1',
      hideViaBot: true,
    );
    await service.preparedKeyboardButton(
      botUserId: 10,
      preparedButtonId: 'button-1',
    );
    await service.createBotTopic(
      chatId: 20,
      name: ' Support ',
      iconCustomEmojiId: 44,
      isNameImplicit: true,
    );
    await service.createManagedBot(
      managerBotUserId: 10,
      name: ' Helper ',
      username: '@helper_bot',
      viaLink: true,
    );
    await service.answerGuestQuery(
      guestQueryId: 50,
      result: {'@type': 'inputCustomRequestResult', 'data': 'ok'},
    );
    await service.updateBotAutomationStatus(
      pendingUpdateCount: 3,
      errorMessage: 'retrying',
    );

    expect(requests.map((value) => value['@type']), [
      'getInlineQueryResults',
      'sendInlineQueryResultMessage',
      'getPreparedKeyboardButton',
      'createForumTopic',
      'createBot',
      'answerGuestQuery',
      'setBotUpdatesStatus',
    ]);
    expect(requests[0]['offset'], 'next');
    expect(requests[1]['options'], {'@type': 'messageSendOptions'});
    expect(requests[1]['hide_via_bot'], isTrue);
    expect(requests[3]['name'], 'Support');
    expect(requests[3]['is_name_implicit'], isTrue);
    expect((requests[3]['icon'] as Map)['custom_emoji_id'], 44);
    expect(requests[4]['username'], 'helper_bot');
    expect(requests[4]['via_link'], isTrue);
    expect(requests[5]['guest_query_id'], 50);
    expect(requests[6]['pending_update_count'], 3);
  });
}
