import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/forward_options.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';

ChatMessage _text(
  int id,
  String text, {
  List<Map<String, dynamic>>? entities,
}) => TDParse.message({
  'id': id,
  'date': 1,
  'is_outgoing': false,
  'sender_id': {'@type': 'messageSenderUser', 'user_id': 2},
  'content': {
    '@type': 'messageText',
    'text': {'@type': 'formattedText', 'text': text, 'entities': ?entities},
  },
})!;

void main() {
  test('mixed selection forwards in selection order', () async {
    final sentOrder = <String>[];
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          switch (request['@type']) {
            case 'getMe':
              return {'@type': 'user', 'id': 1, 'is_premium': true};
            case 'getMessageProperties':
              return {
                '@type': 'messageProperties',
                'can_be_forwarded': true,
                'can_be_copied': true,
              };
            case 'getChat':
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
              sentOrder.add('send:${request['message_id'] ?? 'md'}');
              return {'@type': 'message', 'id': 900 + request['chat_id']};
            case 'forwardMessages':
              sentOrder.add(
                'fwd:${(request['message_ids'] as List).join(',')}',
              );
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
    addTearDown(() async => TdClient.shared.closeProxy());

    final vm = ChatViewModel(
      chatId: 10,
      title: 'Source',
      markReadOnOpen: false,
      sessionMessages: [
        _text(10, 'plain first'),
        _text(20, '**bold** second'),
        _text(30, 'plain third'),
      ],
    );
    addTearDown(vm.dispose);

    await vm.forwardMany(
      [10, 20, 30],
      77,
      options: const ForwardOptions(richText: true, removeSender: true),
    );

    expect(sentOrder, ['fwd:10', 'send:md', 'fwd:30']);
  });
}
