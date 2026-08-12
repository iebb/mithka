import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/message_reaction_availability.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<Map<String, dynamic>> updates;
  late List<Map<String, dynamic>> requests;
  late Map<String, dynamic> availability;
  late bool availabilityUnsupported;

  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          requests.add(Map<String, dynamic>.from(request));
          if (request['@type'] == 'getMessageAvailableReactions' &&
              availabilityUnsupported) {
            throw StateError('Unsupported Bot API request');
          }
          return switch (request['@type']) {
            'getMessageAvailableReactions' => availability,
            'getOption' => <String, dynamic>{
              '@type': 'optionValueBoolean',
              'value': false,
            },
            'addMessageReaction' ||
            'removeMessageReaction' => <String, dynamic>{'@type': 'ok'},
            _ => throw StateError('Unexpected TDLib request: $request'),
          };
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });

  setUp(() {
    requests = [];
    availabilityUnsupported = false;
    availability = {
      '@type': 'availableReactions',
      'top_reactions': <Map<String, dynamic>>[],
      'recent_reactions': <Map<String, dynamic>>[],
      'popular_reactions': <Map<String, dynamic>>[],
      'allow_custom_emoji': false,
      'are_tags': false,
      'unavailability_reason': null,
    };
  });

  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  ChatViewModel model() {
    final value = ChatViewModel(
      chatId: 42,
      title: 'Reactions',
      markReadOnOpen: false,
    );
    addTearDown(value.dispose);
    return value;
  }

  test('adds only a server-approved canonical reaction', () async {
    availability['top_reactions'] = [
      {
        '@type': 'availableReaction',
        'type': {'@type': 'reactionTypeEmoji', 'emoji': '❤'},
        'needs_premium': false,
      },
    ];

    await model().addReaction(7, '❤️');

    expect(requests.map((request) => request['@type']), [
      'getMessageAvailableReactions',
      'getOption',
      'addMessageReaction',
    ]);
    expect(requests.last['reaction_type'], {
      '@type': 'reactionTypeEmoji',
      'emoji': '❤',
    });
  });

  test('does not send a reaction excluded for the message', () async {
    availability['top_reactions'] = [
      {
        '@type': 'availableReaction',
        'type': {'@type': 'reactionTypeEmoji', 'emoji': '👍'},
        'needs_premium': false,
      },
    ];

    await expectLater(
      model().addReaction(7, '🔥'),
      throwsA(isA<MessageReactionUnavailableException>()),
    );
    expect(
      requests.where((request) => request['@type'] == 'addMessageReaction'),
      isEmpty,
    );
  });

  test(
    'chosen reactions remain removable without an availability query',
    () async {
      final message = ChatMessage(
        id: 7,
        isOutgoing: false,
        text: 'Message',
        date: 1,
      );
      const reaction = MessageReaction(emoji: '🔥', count: 1, chosen: true);

      await model().toggleReaction(message, reaction);

      expect(requests, [
        {
          '@type': 'removeMessageReaction',
          'chat_id': 42,
          'message_id': 7,
          'reaction_type': {'@type': 'reactionTypeEmoji', 'emoji': '🔥'},
        },
      ]);
    },
  );

  test(
    'Bot API picker fails closed without per-message availability',
    () async {
      availabilityUnsupported = true;
      final value = model()..isBotApiAccount = true;

      final result = await value.messageReactionAvailability(7);

      expect(result.canAdd, isFalse);
      expect(result.choices, isEmpty);
      expect(result.allowArbitraryCustom, isFalse);
    },
  );

  test('Bot API can add an existing custom-emoji reaction bucket', () async {
    availabilityUnsupported = true;
    final value = model()..isBotApiAccount = true;
    final message = ChatMessage(
      id: 7,
      isOutgoing: false,
      text: 'Message',
      date: 1,
    );
    const reaction = MessageReaction(
      customEmojiId: 998877,
      count: 1,
      chosen: false,
    );

    await value.toggleReaction(message, reaction);

    expect(requests, [
      {
        '@type': 'addMessageReaction',
        'chat_id': 42,
        'message_id': 7,
        'reaction_type': {
          '@type': 'reactionTypeCustomEmoji',
          'custom_emoji_id': 998877,
        },
        'is_big': false,
        'update_recent_reactions': true,
      },
    ]);
  });
}
