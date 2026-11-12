import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/bot_platform_service.dart';
import 'package:mithka/tdlib/td_client.dart';

void main() {
  test(
    'a chat-scoped service keeps sending its inline traffic to that account',
    () async {
      final routed = <(int, Map<String, dynamic>)>[];
      TdClient.shared.configureProxy(
        TdClientProxyTransport(
          accountSlot: 0,
          query: (request) async {
            routed.add((-1, request));
            return {'@type': 'ok'};
          },
          queryForSlot: (request, slot) async {
            routed.add((slot, request));
            return {'@type': 'ok'};
          },
          send: (_) async {},
          updates: const Stream.empty(),
        ),
      );
      addTearDown(TdClient.shared.closeProxy);

      // The composer builds this for its own transcript, which belongs to the
      // account that supplied the chat id.
      final service = BotPlatformService(queryForSlot: 4);
      await service.inlineResults(botUserId: 10, chatId: 20, query: 'cats');
      await service.sendInlineResult(
        chatId: 20,
        queryId: 30,
        resultId: 'result-1',
      );

      expect(routed.map((entry) => entry.$1).toSet(), {4});
      expect(routed.map((entry) => entry.$2['@type']), [
        'getInlineQueryResults',
        'sendInlineQueryResultMessage',
      ]);
    },
  );
}
