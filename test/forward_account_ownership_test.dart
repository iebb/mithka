import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/forward_markdown.dart';
import 'package:mithka/chat/forward_options.dart';
import 'package:mithka/tdlib/td_client.dart';

class _Accounts implements TdClient {
  @override
  int activeClientId = 9;
  final clients = <int, int>{0: 9, 1: 10};
  final routed = <int>[];
  final sent = <int>[];
  bool replaceSource = false;

  @override
  int? clientId(int slot) => clients[slot];

  @override
  Future<Map<String, dynamic>> query(
    Map<String, dynamic> request, {
    Duration timeout = const Duration(seconds: 30),
  }) => queryTo(request, activeClientId, timeout: timeout);

  @override
  Future<Map<String, dynamic>> queryTo(
    Map<String, dynamic> request,
    int clientId, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    routed.add(clientId);
    switch (request['@type']) {
      case 'getMessageProperties':
        activeClientId = 10;
        if (replaceSource) clients[0] = 10;
        return {
          '@type': 'messageProperties',
          'can_be_copied': true,
          'can_be_forwarded': true,
        };
      case 'getChat':
        return {'@type': 'chat', 'id': 42, 'has_protected_content': false};
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
        sent.add(clientId);
        return {'@type': 'message', 'id': 99};
      default:
        throw StateError('Unexpected request');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<bool> _copy(ForwardQuery query) => sendMarkdownRichTextForward(
  query: query,
  fromChatId: 42,
  messageId: 20,
  targetChatId: 77,
  text: '**bold**',
);

void main() {
  test(
    'active-account queries demonstrate the cross-account copy hazard',
    () async {
      final accounts = _Accounts();
      expect(await _copy(accounts.query), isTrue);
      expect(accounts.sent, [10]);
    },
  );

  test(
    'owned forwarding keeps probes, parsing and sending on the source',
    () async {
      final accounts = _Accounts();
      final query = forwardQueryForOwner(accounts, accountSlot: 0, clientId: 9);
      expect(await _copy(query), isTrue);
      expect(accounts.activeClientId, 10);
      expect(accounts.sent, [9]);
      expect(accounts.routed, everyElement(9));
    },
  );

  test(
    'replacing the source client prevents re-authoring or fallback',
    () async {
      final accounts = _Accounts()..replaceSource = true;
      final query = forwardQueryForOwner(accounts, accountSlot: 0, clientId: 9);
      expect(await _copy(query), isFalse);
      await expectLater(
        forwardMessagesWithOptions(
          client: accounts,
          query: query,
          fromChatId: 42,
          targetChatId: 77,
          messageIds: [20],
        ),
        throwsStateError,
      );
      expect(accounts.sent, isEmpty);
      expect(accounts.routed, [9]);
    },
  );
}
