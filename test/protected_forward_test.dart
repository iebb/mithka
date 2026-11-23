import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/protected_forward.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/history/message_history_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Forward-from-protected-chats (the reference client ForwardProtectedAsCopy parity):
/// the copy path re-sends text/media instead of calling forwardMessages,
/// skips uncopiable kinds, and defers media whose file has not finished
/// downloading. The server's can_be_copied probe is NOT consulted — inside a
/// protected chat TDLib answers it from the protection flag itself (is_copy
/// grants no exemption), so gating on it would block every copy.

Map<String, dynamic> mediaSpread(Map<String, dynamic>? media) =>
    media ?? const <String, dynamic>{};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> message({
    required int id,
    String type = 'messageText',
    String text = 'hello',
    Map<String, dynamic>? media,
  }) => <String, dynamic>{
    '@type': 'message',
    'id': id,
    'chat_id': 100,
    'content': <String, dynamic>{
      '@type': type,
      if (type == 'messageText')
        'text': {
          '@type': 'formattedText',
          'text': text,
          'entities': <Map<String, dynamic>>[
            {
              '@type': 'textEntity',
              'offset': 0,
              'length': 2,
              'type': {'@type': 'textEntityTypeBold'},
            },
          ],
        },
      if (type != 'messageText' && text.isNotEmpty)
        'caption': {
          '@type': 'formattedText',
          'text': text,
          'entities': <Map<String, dynamic>>[
            {
              '@type': 'textEntity',
              'offset': 0,
              'length': 2,
              'type': {'@type': 'textEntityTypeBold'},
            },
          ],
        },
      ...mediaSpread(media),
    },
  };

  ProtectedForwardQuery responses(List<Map<String, dynamic>> messages) {
    final byId = {for (final m in messages) m['id'] as int: m};
    return (request) async {
      switch (request['@type']) {
        case 'getMessage':
          final id = request['message_id'] as int;
          return byId[id] ?? {'@type': 'error', 'code': 400, 'message': 'x'};
        case 'getFile':
          return {
            '@type': 'file',
            'id': request['file_id'],
            'local': {
              '@type': 'localFile',
              'path': '/data/telegram/files/${request['file_id']}.bin',
              'is_downloading_completed': true,
            },
          };
        case 'sendMessage':
          return {
            '@type': 'message',
            'id': 9000 + (request['chat_id'] as int),
            'chat_id': request['chat_id'],
          };
      }
      throw StateError('unexpected ${request['@type']}');
    };
  }

  test('text with entities re-sends as a fresh authored message', () async {
    final sent = <Map<String, dynamic>>[];
    final messages = [message(id: 1)];
    final query = responses(messages);
    final plan = await forwardProtectedAsCopy(
      query: (request) async {
        if (request['@type'] == 'sendMessage') sent.add(request);
        return query(request);
      },
      fromChatId: 100,
      messageIds: [1],
      targetChatId: 200,
    );
    expect(plan.copiedCount, 1);
    expect(plan.skippedIds, isEmpty);
    expect(plan.missingMediaIds, isEmpty);
    // Failing-first: the old path threw ForwardBlockedException from
    // forwardMany; the copy path must never issue forwardMessages.
    expect(sent, hasLength(1));
    expect(sent.single['@type'], 'sendMessage');
    expect(sent.single['chat_id'], 200);
    final content =
        sent.single['input_message_content'] as Map<String, dynamic>;
    expect(content['@type'], 'inputMessageText');
    final formatted = content['text'] as Map<String, dynamic>;
    expect(formatted['text'], 'hello');
    // Entities ride along so bold/links survive the copy.
    expect(formatted['entities'], isNotEmpty);
  });

  test(
    'photo with a finished local file uploads from the local path',
    () async {
      final sent = <Map<String, dynamic>>[];
      final messages = [
        message(
          id: 2,
          type: 'messagePhoto',
          media: {
            'photo': {
              '@type': 'photo',
              'sizes': [
                {
                  '@type': 'photoSize',
                  'width': 100,
                  'height': 100,
                  'photo': {'@type': 'file', 'id': 77},
                },
              ],
            },
          },
        ),
      ];
      final query = responses(messages);
      await forwardProtectedAsCopy(
        query: (request) async {
          if (request['@type'] == 'sendMessage') sent.add(request);
          return query(request);
        },
        fromChatId: 100,
        messageIds: [2],
        targetChatId: 200,
      );
      expect(sent, hasLength(1));
      final content =
          sent.single['input_message_content'] as Map<String, dynamic>;
      expect(content['@type'], 'inputMessagePhoto');
      final photo = content['photo'] as Map<String, dynamic>;
      final input = photo['photo'] as Map<String, dynamic>;
      expect(input['@type'], 'inputFileLocal');
      expect(input['path'], contains('77'));
    },
  );

  test('uncopiable kinds are skipped and reported', () async {
    final messages = [message(id: 3, type: 'messagePoll'), message(id: 4)];
    final plan = await forwardProtectedAsCopy(
      query: responses(messages),
      fromChatId: 100,
      messageIds: [3, 4],
      targetChatId: 200,
    );
    expect(plan.copiedCount, 1);
    expect(plan.skippedIds, [3]);
  });

  test('media missing its local file is deferred, not skipped', () async {
    final messages = [
      message(
        id: 5,
        type: 'messageVideo',
        media: {
          'video': {
            '@type': 'video',
            'duration': 4,
            'video': {'@type': 'file', 'id': 88},
          },
        },
      ),
    ];
    final base = responses(messages);
    final plan = await forwardProtectedAsCopy(
      query: (request) async {
        if (request['@type'] == 'getFile') {
          return {
            '@type': 'file',
            'id': request['file_id'],
            'local': {
              '@type': 'localFile',
              'path': '',
              'is_downloading_completed': false,
            },
          };
        }
        return base(request);
      },
      fromChatId: 100,
      messageIds: [5],
      targetChatId: 200,
    );
    expect(plan.copiedCount, 0);
    expect(plan.skippedIds, isEmpty);
    expect(plan.missingMediaIds, [5]);
  });

  test('can_be_copied=false no longer blocks the copy (regression)', () async {
    // TDLib derives can_be_copied from has_protected_content itself —
    // inside a protected chat the probe is false for EVERY message. The
    // old gate fail-closed on it and killed the whole copy path; the
    // probe is now deliberately ignored (permission lives in the user's
    // opt-in toggle that routed the selection here).
    final sent = <Map<String, dynamic>>[];
    final messages = [message(id: 6)];
    final base = responses(messages);
    final plan = await forwardProtectedAsCopy(
      query: (request) async {
        if (request['@type'] == 'getMessageProperties') {
          return {'@type': 'messageProperties', 'can_be_copied': false};
        }
        if (request['@type'] == 'sendMessage') sent.add(request);
        return base(request);
      },
      fromChatId: 100,
      messageIds: [6],
      targetChatId: 200,
    );
    expect(plan.copiedCount, 1);
    expect(plan.skippedIds, isEmpty);
    expect(sent, hasLength(1));
  });

  group('settings', () {
    test('ships ON and persists the opt-out', () async {
      final previous = MessageHistorySettings.shared;
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      // The shared singleton was initialized against the real prefs earlier;
      // re-initialize it against the mock for this test.
      previous.initialize(prefs);
      expect(previous.forwardProtectedAsCopy, allowTelegramTosViolations);
      previous.setForwardProtectedAsCopy(false);
      // The setter is a no-op while the self-build gate is off, so the stored
      // preference only changes in a gated build.
      expect(previous.forwardProtectedAsCopy, isFalse);
      expect(
        prefs.getBool('message_history.forward_protected_as_copy'),
        allowTelegramTosViolations ? isFalse : isNull,
      );
    });
  });
}
