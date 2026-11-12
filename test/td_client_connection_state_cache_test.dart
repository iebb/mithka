//
//  td_client_connection_state_cache_test.dart
//
//  The chat-list header seeds itself from TdClient's cached
//  `updateConnectionState` because TDLib pushes that update only on change and
//  the pinned build (scripts/tdjson-manifest.json, 1.8.67) has no request to
//  ask for it again — `getConnectionState` answers
//  "Unknown class \"getConnectionState\"".
//
//  This covers the native routing path (`_route`, which keys the cache by the
//  update's own `@client_id`), which the widget tests cannot reach because they
//  run through the proxy transport's `_routeProxyUpdate`.
//

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/tdlib/json_helpers.dart';
import 'package:mithka/tdlib/td_client.dart';

void main() {
  final updates = StreamController<Map<String, dynamic>>.broadcast(sync: true);

  setUpAll(() {
    // configureProxy registers the account as the active client, so the cache
    // has a real active id to answer `latestConnectionStateUpdate` against.
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (_) async => {'@type': 'ok'},
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });

  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  void routeConnectionState(int clientId, String state) {
    TdClient.shared.routeUpdateForTesting({
      '@type': 'updateConnectionState',
      '@client_id': clientId,
      'state': {'@type': state},
    });
  }

  test('an inactive account cannot overwrite the active one', () {
    final client = TdClient.shared;
    routeConnectionState(client.activeClientId, 'connectionStateReady');

    // A background account losing its network must not make the visible
    // header claim the active account is disconnected.
    const otherClientId = 99;
    routeConnectionState(otherClientId, 'connectionStateWaitingForNetwork');

    expect(
      client.latestConnectionStateUpdate?.obj('state')?.type,
      'connectionStateReady',
    );
    expect(
      client
          .latestConnectionStateUpdateForClient(otherClientId)
          ?.obj('state')
          ?.type,
      'connectionStateWaitingForNetwork',
    );
  });
}
