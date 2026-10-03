import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/tdlib/td_client.dart';

void main() {
  final client = TdClient.shared;

  Map<String, dynamic> event(String type, int sequence, {int? clientId}) => {
    '@type': type,
    '@client_id': clientId ?? client.activeClientId,
    'sequence': sequence,
  };

  test('typed streams preserve arrival order and account boundaries', () async {
    final activeEvents = <int>[];
    final allEvents = <int>[];
    final broadEvents = <int>[];
    final types = ['updateChatPosition', 'updateChatReadInbox'];
    final subscriptions = [
      client.updatesOfAny(types).listen((u) => activeEvents.add(u['sequence'])),
      client
          .updatesOfAny([...types, types.first], allAccounts: true)
          .listen((u) => allEvents.add(u['sequence'])),
      client.subscribeAll().listen((u) => broadEvents.add(u['sequence'])),
    ];
    addTearDown(() async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    });

    client.routeUpdateForTesting(event(types.first, 1));
    client.routeUpdateForTesting(
      event(types.last, 2, clientId: client.activeClientId + 100),
    );
    client.routeUpdateForTesting(event('updateSavedAnimations', 3));
    client.routeUpdateForTesting(event(types.last, 4));
    client.routeUpdateForTesting(event(types.first, 5));

    // Delivery remains synchronous; nothing awaits a later frame or microtask.
    expect(activeEvents, [1, 4, 5]);
    expect(allEvents, [1, 2, 4, 5]);
    expect(broadEvents, [1, 2, 3, 4, 5]);
  });

  test('local corrections reach active typed streams only', () async {
    final activeEvents = <int>[];
    final allEvents = <int>[];
    final subscriptions = [
      client
          .updatesOf('mithkaUnreadDelta')
          .listen((u) => activeEvents.add(u['sequence'])),
      client
          .updatesOf('mithkaUnreadDelta', allAccounts: true)
          .listen((u) => allEvents.add(u['sequence'])),
    ];
    addTearDown(() async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    });

    client.emitLocalUpdate(event('mithkaUnreadDelta', 1));
    expect(activeEvents, [1]);
    expect(allEvents, isEmpty);
  });

  test(
    'merged typed streams support pause, cancellation and resubscription',
    () async {
      final events = <int>[];
      final stream = client.updatesOfAny(const [
        'updateChatPosition',
        'updateChatReadInbox',
      ], allAccounts: true);
      final first = stream.listen((u) => events.add(u['sequence']));
      final secondEvents = <int>[];
      final second = stream.listen((u) => secondEvents.add(u['sequence']));
      first.pause();
      client.routeUpdateForTesting(event('updateChatReadInbox', 1));
      client.routeUpdateForTesting(event('updateChatPosition', 2));
      expect(events, isEmpty);
      expect(secondEvents, [1, 2]);
      first.resume();
      await Future<void>.delayed(Duration.zero);
      expect(events, [1, 2]);
      await first.cancel();
      client.routeUpdateForTesting(event('updateChatReadInbox', 3));
      expect(events, [1, 2]);
      expect(secondEvents, [1, 2, 3]);
      await second.cancel();
      client.routeUpdateForTesting(event('updateChatPosition', 4));

      final freshEvents = <int>[];
      final fresh = stream.listen((u) => freshEvents.add(u['sequence']));
      client.routeUpdateForTesting(event('updateChatPosition', 5));
      expect(freshEvents, [5]);
      await fresh.cancel();
    },
  );
}
