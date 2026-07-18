import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/saved_messages_service.dart';

Map<String, dynamic> _message({
  int id = 100,
  Map<String, dynamic>? forwardInfo,
}) => {
  '@type': 'message',
  'id': id,
  'chat_id': 42,
  'is_outgoing': true,
  'date': 1000,
  'topic_id': {
    '@type': 'messageTopicSavedMessages',
    'saved_messages_topic_id': 77,
  },
  'forward_info': forwardInfo,
  'content': {
    '@type': 'messageText',
    'text': {
      '@type': 'formattedText',
      'text': 'saved text',
      'entities': <Map<String, dynamic>>[],
    },
  },
};

void main() {
  test('current user lookup is available for bookmark avatars', () async {
    late Map<String, dynamic> request;
    final service = SavedMessagesService(
      query: (value) async {
        request = value;
        return {'@type': 'user', 'id': 9, 'first_name': 'Natu'};
      },
    );

    final user = await service.currentUser();

    expect(request, {'@type': 'getMe'});
    expect(user['id'], 9);
  });

  test('all-messages history resolves the Saved Messages chat', () async {
    final requests = <Map<String, dynamic>>[];
    final service = SavedMessagesService(
      query: (request) async {
        requests.add(request);
        return switch (request['@type']) {
          'getOption' => {'@type': 'optionValueInteger', 'value': 9},
          'createPrivateChat' => {'@type': 'chat', 'id': 42},
          'getChatHistory' => {
            '@type': 'messages',
            'total_count': 1,
            'messages': [_message()],
          },
          _ => throw StateError('Unexpected request $request'),
        };
      },
    );

    final page = await service.messages(
      topicId: 0,
      query: '',
      tag: null,
      fromMessageId: 0,
    );

    expect(requests.map((request) => request['@type']), [
      'getOption',
      'createPrivateChat',
      'getChatHistory',
    ]);
    expect(requests.last['chat_id'], 42);
    expect(page.messages.single.topicId, 77);
    expect(page.nextFromMessageId, 100);
  });

  test('search sends the exact saved topic, tag and query', () async {
    late Map<String, dynamic> request;
    final service = SavedMessagesService(
      query: (value) async {
        request = value;
        return {
          '@type': 'foundChatMessages',
          'total_count': 0,
          'messages': <Map<String, dynamic>>[],
          'next_from_message_id': 0,
        };
      },
    );
    const tag = SavedMessagesTagRecord(
      type: {'@type': 'reactionTypeEmoji', 'emoji': '⭐'},
      label: 'Later',
      count: 3,
    );

    await service.messages(
      topicId: 77,
      query: 'receipt',
      tag: tag,
      fromMessageId: 200,
    );

    expect(request['@type'], 'searchSavedMessages');
    expect(request['saved_messages_topic_id'], 77);
    expect(request['tag'], tag.type);
    expect(request['query'], 'receipt');
    expect(request['from_message_id'], 200);
  });

  test('original message navigation prefers forward source identifiers', () {
    final record = SavedMessageRecord.fromRaw(
      _message(
        forwardInfo: {
          '@type': 'messageForwardInfo',
          'origin': {
            '@type': 'messageOriginChannel',
            'chat_id': -1001,
            'message_id': 12,
          },
          'source': {
            '@type': 'forwardSource',
            'chat_id': -1002,
            'message_id': 34,
          },
        },
      ),
    );

    expect(record.originalChatId, -1002);
    expect(record.originalMessageId, 34);
  });

  test('topic history uses getSavedMessagesTopicHistory', () async {
    late Map<String, dynamic> request;
    final service = SavedMessagesService(
      query: (value) async {
        request = value;
        return {
          '@type': 'messages',
          'total_count': 0,
          'messages': <Map<String, dynamic>>[],
        };
      },
    );

    await service.messages(topicId: 88, query: '', tag: null, fromMessageId: 0);

    expect(request['@type'], 'getSavedMessagesTopicHistory');
    expect(request['saved_messages_topic_id'], 88);
  });

  test('text search falls back for accounts without premium tags', () async {
    final requests = <Map<String, dynamic>>[];
    final service = SavedMessagesService(
      query: (request) async {
        requests.add(request);
        return switch (request['@type']) {
          'searchSavedMessages' => throw StateError('premium required'),
          'getOption' => {'@type': 'optionValueInteger', 'value': 9},
          'createPrivateChat' => {'@type': 'chat', 'id': 42},
          'searchChatMessages' => {
            '@type': 'foundChatMessages',
            'total_count': 0,
            'messages': <Map<String, dynamic>>[],
            'next_from_message_id': 0,
          },
          _ => throw StateError('Unexpected request $request'),
        };
      },
    );

    await service.messages(
      topicId: 77,
      query: 'hello',
      tag: null,
      fromMessageId: 0,
    );

    expect(requests.last['@type'], 'searchChatMessages');
    expect(requests.last['chat_id'], 42);
    expect(requests.last['topic_id'], {
      '@type': 'messageTopicSavedMessages',
      'saved_messages_topic_id': 77,
    });
  });
}
