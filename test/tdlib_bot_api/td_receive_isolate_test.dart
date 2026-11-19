//
//  td_receive_isolate_test.dart
//
//  The release-mode receive path decodes TDLib JSON inside the receive
//  isolate and ships decoded maps to the main isolate (lib/tdlib/td_client.dart
//  _receiveEntry). Debug builds use a polling pump instead, so nothing
//  exercises that path before a profile/release run — this test proves the
//  mechanism: decoded Map<String, dynamic> objects survive the isolate
//  boundary with their runtime types and nested structure intact, and
//  malformed events fall back to the raw string.
//

import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';

/// Mirrors _receiveEntry's decode-and-send loop for a fixed set of events.
void _decodeEntry(SendPort toMain) {
  const events = [
    '{"@type":"updateAuthorizationState","@client_id":1,'
        '"authorization_state":{"@type":"authorizationStateReady"}}',
    '{"@type":"updateFile","file":{"id":42,"size":"9007199254740993",'
        '"local":{"is_downloading_completed":true,"downloaded_size":128}}}',
    '{"@type":"updateNewMessage","message":{"id":7,"content":'
        '{"@type":"messageText","text":{"text":"héllo 世界 🐢",'
        '"entities":[{"offset":0,"length":5}]}}}}',
    'not-json-at-all',
  ];
  for (final event in events) {
    try {
      final decoded = jsonDecode(event);
      if (decoded is Map<String, dynamic>) {
        toMain.send(decoded);
        continue;
      }
      toMain.send(event);
    } catch (_) {
      toMain.send(event);
    }
  }
}

void main() {
  test('receive isolate ships decoded maps across the boundary', () async {
    final port = ReceivePort();
    await Isolate.spawn(_decodeEntry, port.sendPort);
    final received = await port.take(4).toList();
    port.close();

    // Well-formed events arrive as typed maps, exactly like _route expects.
    final auth = received[0];
    expect(auth, isA<Map<String, dynamic>>());
    auth as Map<String, dynamic>;
    expect(auth['@type'], 'updateAuthorizationState');
    expect(auth['@client_id'], 1);
    expect(
      (auth['authorization_state'] as Map<String, dynamic>)['@type'],
      'authorizationStateReady',
    );

    // Nested maps/lists keep their shapes; TDLib int64-as-string survives.
    final file = received[1] as Map<String, dynamic>;
    final local = file['file'] as Map<String, dynamic>;
    expect((local['local'] as Map<String, dynamic>)['downloaded_size'], 128);
    expect(local['size'], '9007199254740993');

    // Non-ASCII text and entity lists survive the copy.
    final message = received[2] as Map<String, dynamic>;
    final content =
        (message['message'] as Map<String, dynamic>)['content']
            as Map<String, dynamic>;
    final text = content['text'] as Map<String, dynamic>;
    expect(text['text'], 'héllo 世界 🐢');
    expect(text['entities'], isA<List<dynamic>>());

    // Malformed input falls back to the raw string (main-isolate _routeRaw).
    expect(received[3], 'not-json-at-all');
  });
}
