import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chatId = 42;
const _firstMessageId = 100000;

Map<String, dynamic> _message(int id, String text, {int? replyingTo}) => {
  '@type': 'message',
  'id': id,
  'chat_id': _chatId,
  'date': id,
  'is_outgoing': true,
  if (replyingTo != null)
    'reply_to': {
      '@type': 'messageReplyToMessage',
      'chat_id': _chatId,
      'message_id': replyingTo,
    },
  'content': {
    '@type': 'messageText',
    'text': {'@type': 'formattedText', 'text': text, 'entities': []},
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<Map<String, dynamic>> history;
  late Map<int, Map<String, dynamic>> remoteTargets;
  late List<List<int>> requestedTargets;
  final client = TdClient.shared;

  setUpAll(() {
    client.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          switch (request['@type']) {
            case 'getChatHistory':
              return {'@type': 'messages', 'messages': history};
            case 'getMessages':
              final ids = List<int>.from(request['message_ids']);
              requestedTargets.add(ids);
              return {
                '@type': 'messages',
                'messages': [for (final id in ids) remoteTargets[id]],
              };
            default:
              return {'@type': 'ok'};
          }
        },
        send: (_) async {},
        updates: const Stream.empty(),
      ),
    );
  });
  tearDownAll(client.closeProxy);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    history = [];
    remoteTargets = {};
    requestedTargets = [];
  });

  test(
    'live replies use current loaded messages without remote lookups',
    () async {
      history = [
        for (var i = 0; i < 5000; i++)
          _message(_firstMessageId + i, 'message $i'),
      ];
      final model = ChatViewModel(
        chatId: _chatId,
        title: 'Test',
        markReadOnOpen: false,
      );
      addTearDown(model.dispose);
      await model.loadLatestHistory();
      model.primeMessageIndexesForTesting();
      model.resetTranscriptScanVisitsForTesting();

      for (final (step, index) in [0, 2499, 4999].indexed) {
        model.applyLiveUpdateForTesting({
          '@type': 'updateNewMessage',
          'message': _message(
            _firstMessageId + 5000 + step,
            'reply $step',
            replyingTo: _firstMessageId + index,
          ),
        });
        final reply = model.messages.last;
        expect(reply.replyToPreview, 'message $index');
        expect(reply.replyToDate, _firstMessageId + index);
        expect(reply.replyToSender, model.meName);
      }
      expect(requestedTargets, isEmpty);
      expect(model.transcriptScanVisitsForTesting, 0);
    },
  );

  test(
    'history replies reuse loaded targets and batch missing targets',
    () async {
      history = [
        _message(100, 'loaded target'),
        _message(110, 'first reply', replyingTo: 100),
        _message(120, 'second reply', replyingTo: 100),
        _message(130, 'remote reply', replyingTo: 70),
        _message(140, 'same remote target', replyingTo: 70),
        _message(150, 'unavailable target', replyingTo: 80),
      ];
      remoteTargets[70] = _message(70, 'remote target');
      final model = ChatViewModel(
        chatId: _chatId,
        title: 'Test',
        markReadOnOpen: false,
      );
      addTearDown(model.dispose);
      await model.loadLatestHistory();
      await Future<void>.delayed(Duration.zero);

      expect(model.messages[1].replyToPreview, 'loaded target');
      expect(model.messages[2].replyToPreview, 'loaded target');
      expect(model.messages[3].replyToPreview, 'remote target');
      expect(model.messages[4].replyToPreview, 'remote target');
      expect(model.messages[5].replyToPreview, isNull);
      expect(requestedTargets, [
        [70, 80],
      ]);
    },
  );

  test('reply lookups reflect target edits and removal', () async {
    history = [_message(100, 'original')];
    final model = ChatViewModel(
      chatId: _chatId,
      title: 'Test',
      markReadOnOpen: false,
    );
    addTearDown(model.dispose);
    await model.loadLatestHistory();
    model.applyLiveUpdateForTesting({
      '@type': 'updateMessageContent',
      'chat_id': _chatId,
      'message_id': 100,
      'new_content': _message(100, 'edited')['content'],
    });
    model.applyLiveUpdateForTesting({
      '@type': 'updateNewMessage',
      'message': _message(110, 'reply', replyingTo: 100),
    });
    expect(model.messages.last.replyToPreview, 'edited');
    expect(requestedTargets, isEmpty);

    model.applyLiveUpdateForTesting({
      '@type': 'updateDeleteMessages',
      'chat_id': _chatId,
      'message_ids': [100],
      'is_permanent': true,
    });
    model.applyLiveUpdateForTesting({
      '@type': 'updateNewMessage',
      'message': _message(120, 'reply after deletion', replyingTo: 100),
    });
    await Future<void>.delayed(Duration.zero);
    expect(model.messages.last.replyToPreview, isNull);
    expect(requestedTargets, [
      [100],
    ]);
  });
}
