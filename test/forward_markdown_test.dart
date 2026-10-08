import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/forward_markdown.dart';
import 'package:mithka/tdlib/td_models.dart';

ChatMessage _textMessage(String text, {List<Map<String, dynamic>>? entities}) =>
    TDParse.message({
      '@type': 'message',
      'id': 1,
      'date': 1,
      'is_outgoing': false,
      'sender_id': {'@type': 'messageSenderUser', 'user_id': 2},
      'content': {
        '@type': 'messageText',
        'text': {'@type': 'formattedText', 'text': text, 'entities': ?entities},
      },
    })!;

void main() {
  group('forwardMarkdownOfferForMessage', () {
    test('AI-style markdown is available and suggested', () {
      final offer = forwardMarkdownOfferForMessage(
        _textMessage('## Title\n\n**bold** and `code`\n\n- one\n- two'),
      );
      expect(offer.available, isTrue);
      expect(offer.suggested, isTrue);
    });

    test('a single marker pair is available but not suggested', () {
      final offer = forwardMarkdownOfferForMessage(_textMessage('a **b** c'));
      expect(offer.available, isTrue);
      expect(offer.suggested, isFalse);
    });

    test('plain text offers nothing', () {
      final offer = forwardMarkdownOfferForMessage(_textMessage('好的，没问题'));
      expect(offer.available, isFalse);
      expect(offer.suggested, isFalse);
    });

    test('media captions never qualify', () {
      final offer = forwardMarkdownOfferForMessage(
        TDParse.message({
          '@type': 'message',
          'id': 3,
          'date': 1,
          'content': {
            '@type': 'messagePhoto',
            'photo': {'@type': 'photo'},
            'caption': {'@type': 'formattedText', 'text': '**bold** `code`'},
          },
        })!,
      );
      expect(offer.available, isFalse);
    });

    test('text longer than the Telegram limit never qualifies', () {
      final long = 'x' * 4200;
      final offer = forwardMarkdownOfferForMessage(_textMessage('**$long**'));
      expect(offer.available, isFalse);
    });
  });

  group('sendMarkdownRichTextForward', () {
    test('sends parsed entities as a new message', () async {
      final requests = <Map<String, dynamic>>[];
      bool sent(String? id) => requests.any(
        (request) =>
            request['@type'] == 'sendMessage' &&
            (request['chat_id'] as int?) == int.parse(id!),
      );
      final ok = await sendMarkdownRichTextForward(
        query: (request) async {
          requests.add(request);
          return switch (request['@type']) {
            'getChat' => {'@type': 'chat', 'id': 10},
            'getMessageProperties' => {
              '@type': 'messageProperties',
              'can_be_forwarded': true,
              'can_be_copied': true,
            },
            'parseMarkdown' => {
              '@type': 'formattedText',
              'text': 'bold',
              'entities': [
                {
                  '@type': 'textEntity',
                  'offset': 0,
                  'length': 4,
                  'type': {'@type': 'textEntityTypeBold'},
                },
              ],
            },
            'sendMessage' => {'@type': 'message', 'id': 99},
            _ => throw StateError('unexpected $request'),
          };
        },
        fromChatId: 10,
        messageId: 20,
        targetChatId: 30,
        text: '**bold**',
      );

      expect(ok, isTrue);
      expect(sent('30'), isTrue);
      final send = requests.firstWhere((r) => r['@type'] == 'sendMessage');
      expect(
        ((send['input_message_content'] as Map<String, dynamic>)['text']
            as Map<String, dynamic>)['text'],
        'bold',
      );
    });

    test('falls back when nothing parses into entities', () async {
      final ok = await sendMarkdownRichTextForward(
        query: (request) async => switch (request['@type']) {
          'parseMarkdown' => {
            '@type': 'formattedText',
            'text': 'plain',
            'entities': [],
          },
          _ => throw StateError('unexpected $request'),
        },
        fromChatId: 10,
        messageId: 20,
        targetChatId: 30,
        text: 'plain text',
      );
      expect(ok, isFalse);
    });

    test('a parse failure degrades to fallback, never throws', () async {
      final ok = await sendMarkdownRichTextForward(
        query: (request) async => throw StateError('tdlib down'),
        fromChatId: 10,
        messageId: 20,
        targetChatId: 30,
        text: '**bold**',
      );
      expect(ok, isFalse);
    });

    test('protected content blocks the re-send copy', () async {
      final requests = <Map<String, dynamic>>[];
      final ok = await sendMarkdownRichTextForward(
        query: (request) async {
          requests.add(request);
          return switch (request['@type']) {
            'parseMarkdown' => {
              '@type': 'formattedText',
              'text': 'bold',
              'entities': [
                {
                  '@type': 'textEntity',
                  'offset': 0,
                  'length': 4,
                  'type': {'@type': 'textEntityTypeBold'},
                },
              ],
            },
            'getChat' => {
              '@type': 'chat',
              'id': 10,
              'has_protected_content': true,
            },
            _ => throw StateError('unexpected $request'),
          };
        },
        fromChatId: 10,
        messageId: 20,
        targetChatId: 30,
        text: '**bold**',
      );
      expect(ok, isFalse);
      expect(
        requests.any((request) => request['@type'] == 'sendMessage'),
        isFalse,
      );
    });
  });
}
