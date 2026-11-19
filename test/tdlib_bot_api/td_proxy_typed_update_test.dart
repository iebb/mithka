import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/tdlib/td_client.dart';

void main() {
  test(
    'proxy windows dispatch typed updates for both account scopes',
    () async {
      final updates = StreamController<Map<String, dynamic>>(sync: true);
      final client = TdClient.shared;
      client.configureProxy(
        TdClientProxyTransport(
          accountSlot: 7,
          query: (_) async => {'@type': 'ok'},
          send: (_) async {},
          updates: updates.stream,
        ),
      );
      final activeEvents = <Map<String, dynamic>>[];
      final allEvents = <Map<String, dynamic>>[];
      final active = client.updatesOf('updateFile').listen(activeEvents.add);
      final all = client
          .updatesOf('updateFile', allAccounts: true)
          .listen(allEvents.add);
      addTearDown(() async {
        await active.cancel();
        await all.cancel();
        await client.closeProxy();
        await updates.close();
      });

      updates.add({'@type': 'updateChatPosition'});
      updates.add({
        '@type': 'updateFile',
        'file': {'id': 42},
      });
      expect(activeEvents, hasLength(1));
      expect(allEvents, hasLength(1));
      expect(allEvents.single, same(activeEvents.single));
      expect(allEvents.single['@client_id'], client.activeClientId);
      expect(client.slotForClient(client.activeClientId), 7);
    },
  );
}
