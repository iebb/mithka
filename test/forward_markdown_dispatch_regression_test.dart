import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/forward_options.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dispatched = <String>[];
  var sendTimesOut = false;
  var permissionFails = false;
  var copyAllowed = true;
  var chatProbeFails = false;
  var premium = true;
  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          switch (request['@type']) {
            case 'getMe':
              return {'@type': 'user', 'id': 1, 'is_premium': premium};
            case 'getMessageProperties':
              if (permissionFails) throw TimeoutException('permission probe');
              return {
                '@type': 'messageProperties',
                'can_be_forwarded': true,
                'can_be_copied': copyAllowed,
              };
            case 'getChat':
              if (chatProbeFails) throw TimeoutException('source chat probe');
              return {'@type': 'chat', 'id': 10};
            case 'parseMarkdown':
              return {
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
              };
            case 'sendMessage':
              dispatched.add('send');
              // The transport lost the reply; the server may have accepted it.
              if (sendTimesOut) throw TimeoutException('send acknowledgement');
              return {'@type': 'message', 'id': 900};
            case 'forwardMessages':
              dispatched.add('forward');
              return {
                '@type': 'messages',
                'messages': [
                  for (final id in request['message_ids'] as List)
                    {'@type': 'message', 'id': id},
                ],
              };
            default:
              return {'@type': 'ok'};
          }
        },
        send: (_) async {},
        updates: const Stream<Map<String, dynamic>>.empty(),
      ),
    );
  });
  tearDownAll(TdClient.shared.closeProxy);
  setUp(() {
    dispatched.clear();
    sendTimesOut = false;
    permissionFails = false;
    copyAllowed = true;
    chatProbeFails = false;
    premium = true;
  });

  ChatViewModel model({List<Map<String, dynamic>> entities = const []}) =>
      ChatViewModel(
        chatId: 10,
        title: 'Source',
        markReadOnOpen: false,
        sessionMessages: [
          TDParse.message({
            '@type': 'message',
            'id': 20,
            'date': 1,
            'content': {
              '@type': 'messageText',
              'text': {
                '@type': 'formattedText',
                'text': '**bold**',
                'entities': entities,
              },
            },
          })!,
        ],
      );

  test(
    'an ambiguous dispatched send never falls back to another send',
    () async {
      sendTimesOut = true;
      final vm = model();
      addTearDown(vm.dispose);
      Object? error;
      try {
        await vm.forwardMany(
          [20],
          77,
          options: const ForwardOptions(richText: true),
        );
      } catch (caught) {
        error = caught;
      }
      expect(dispatched, ['send']);
      expect(error, isA<TimeoutException>());
    },
  );

  test(
    'a failed permission probe still safely uses ordinary forwarding',
    () async {
      permissionFails = true;
      final vm = model();
      addTearDown(vm.dispose);
      await vm.forwardMany(
        [20],
        77,
        options: const ForwardOptions(richText: true),
      );
      expect(dispatched, ['forward']);
    },
  );

  test('denied copy permission cannot be bypassed by re-authoring', () async {
    copyAllowed = false;
    final vm = model();
    addTearDown(vm.dispose);
    await expectLater(
      vm.forwardMany(
        [20],
        77,
        options: const ForwardOptions(richText: true, removeSender: true),
      ),
      throwsA(isA<ForwardBlockedException>()),
    );
    expect(dispatched, isEmpty);
  });

  test(
    'an unavailable source chat never allows a newly authored copy',
    () async {
      chatProbeFails = true;
      final vm = model();
      addTearDown(vm.dispose);
      await vm.forwardMany(
        [20],
        77,
        options: const ForwardOptions(richText: true),
      );
      expect(dispatched, ['forward']);
    },
  );

  test(
    'existing hidden-link entities preserve the ordinary forward path',
    () async {
      final vm = model(
        entities: [
          {
            '@type': 'textEntity',
            'offset': 0,
            'length': 4,
            'type': {
              '@type': 'textEntityTypeTextUrl',
              'url': 'https://example.com',
            },
          },
        ],
      );
      addTearDown(vm.dispose);
      await vm.forwardMany(
        [20],
        77,
        options: const ForwardOptions(richText: true),
      );
      expect(dispatched, ['forward']);
    },
  );

  test(
    'non-Premium entry points cannot activate Markdown re-authoring',
    () async {
      premium = false;
      final vm = model();
      addTearDown(vm.dispose);
      await vm.forwardMany(
        [20],
        77,
        options: const ForwardOptions(richText: true),
      );
      expect(dispatched, ['forward']);
    },
  );
}
