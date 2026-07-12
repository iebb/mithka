import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mithka/chat/rich_message_bot_relay.dart';

void main() {
  test('replaces local rich media ids with HTTPS URLs', () {
    expect(
      replaceRichMessageMediaIds(
        '<img src="media-1"><video src=\'media-2\'></video>',
        const {
          'media-1': 'https://example.test/photo.jpg',
          'media-2': 'https://example.test/video.mp4',
        },
      ),
      '<img src="https://example.test/photo.jpg">'
      '<video src=\'https://example.test/video.mp4\'></video>',
    );
  });

  test('media fallback keeps captions and removes unsupported media tags', () {
    expect(
      stripRichMessageMediaBlocks(
        '<p>Before</p><figure><img src="x"/>'
        '<figcaption>Caption</figcaption></figure>'
        '<video src="y"></video><p>After</p>',
      ),
      '<p>Before</p><p>Caption</p><p>After</p>',
    );
  });

  group('parseRelayForwardResponse', () {
    test('rejects the null placeholder returned for an unsupported copy', () {
      expect(
        () => parseRelayForwardResponse({
          '@type': 'messages',
          'messages': [null],
        }),
        throwsA(
          isA<RichMessageRelayException>().having(
            (error) => error.code,
            'code',
            'forward_rejected',
          ),
        ),
      );
    });

    test('keeps valid forwarded messages', () {
      final messages = parseRelayForwardResponse({
        '@type': 'messages',
        'messages': [
          {'@type': 'message', 'id': 123},
        ],
      });
      expect(messages.single['id'], 123);
    });
  });

  group('relayMessageIdFromHistory', () {
    test('uses the actual TDLib message id when private-chat ids differ', () {
      final id = relayMessageIdFromHistory(
        {
          '@type': 'messages',
          'messages': [
            {
              '@type': 'message',
              'id': '998877665544',
              'date': 1002,
              'sender_id': {'@type': 'messageSenderUser', 'user_id': '42'},
              'content': {'@type': 'messageRichMessage'},
            },
          ],
        },
        botApiMessageId: 77,
        botUserId: 42,
        sentDate: 1000,
      );

      expect(id, 998877665544);
    });

    test('prefers the exact shifted Bot API id', () {
      const botApiMessageId = 77;
      const expected = botApiMessageId << 20;
      final id = relayMessageIdFromHistory(
        {
          '@type': 'messages',
          'messages': [
            {
              '@type': 'message',
              'id': expected,
              'date': 1,
              'sender_id': {'@type': 'messageSenderUser', 'user_id': 99},
              'content': {'@type': 'messageText'},
            },
          ],
        },
        botApiMessageId: botApiMessageId,
        botUserId: 42,
        sentDate: 1000,
      );

      expect(id, expected);
    });
  });

  test('validates a relay bot without exposing its token', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode({
          'ok': true,
          'result': {
            'id': 123456,
            'is_bot': true,
            'first_name': 'Relay',
            'username': 'relay_bot',
          },
        }),
        200,
      );
    });
    final relay = RichMessageBotRelay(
      httpClient: client,
      apiBase: Uri.parse('https://api.telegram.test'),
    );

    final bot = await relay.validateToken(
      '123456:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef',
    );

    expect(bot.id, 123456);
    expect(bot.username, 'relay_bot');
    expect(requests.single.url.path, contains('/getMe'));
    relay.close();
  });

  test('rejects malformed tokens without a network request', () async {
    var requested = false;
    final relay = RichMessageBotRelay(
      httpClient: MockClient((_) async {
        requested = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      relay.validateToken('not-a-token'),
      throwsA(
        isA<RichMessageRelayException>().having(
          (error) => error.code,
          'code',
          'invalid_token',
        ),
      ),
    );
    expect(requested, isFalse);
    relay.close();
  });
}
