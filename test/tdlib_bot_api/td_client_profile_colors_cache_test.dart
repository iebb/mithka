import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/tdlib/td_client.dart';

void main() {
  final updates = StreamController<Map<String, dynamic>>.broadcast(sync: true);

  setUpAll(() {
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

  for (final type in ['updateAccentColors', 'updateProfileAccentColors']) {
    Map<String, dynamic>? cached() => type == 'updateAccentColors'
        ? TdClient.shared.latestAccentColorsUpdate
        : TdClient.shared.latestProfileAccentColorsUpdate;

    test('$type from an inactive client does not replace active colors', () {
      final client = TdClient.shared;
      final palette = [
        {'id': 19},
      ];
      client.routeUpdateForTesting({
        '@type': type,
        '@client_id': client.activeClientId,
        'colors': palette,
      });
      client.routeUpdateForTesting({
        '@type': type,
        '@client_id': 99,
        'colors': [
          {'id': 25},
        ],
      });
      expect(cached()?['colors'], palette);
    });

    test('$type is cached before proxy subscribers rebuild', () async {
      final palette = [
        {'id': 29},
      ];
      Map<String, dynamic>? seen;
      final subscription = TdClient.shared.updatesOf(type).listen((_) {
        seen = cached();
      });
      updates.add({'@type': type, 'colors': palette});
      expect(seen?['colors'], palette);
      expect(cached()?['colors'], palette);
      await subscription.cancel();
    });
  }
}
