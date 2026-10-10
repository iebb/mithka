import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/proxy_status.dart';
import 'package:mithka/tdlib/td_client.dart';

/// One saved proxy, the shape `getProxies` answers with. The pinned schema puts
/// the SOCKS/HTTP credentials and the MTProto secret inside `proxy.type`.
Map<String, dynamic> _proxy({
  required int id,
  required String server,
  required int port,
  bool enabled = false,
  String type = 'proxyTypeSocks5',
  Map<String, dynamic> credentials = const {},
  String comment = '',
}) => {
  '@type': 'addedProxy',
  'id': id,
  'last_used_date': 0,
  'is_enabled': enabled,
  'comment': comment,
  'proxy': {
    '@type': 'proxy',
    'server': server,
    'port': port,
    'type': {'@type': type, ...credentials},
  },
};

Map<String, dynamic> _proxiesAnswer(List<Map<String, dynamic>> proxies) => {
  '@type': 'proxies',
  'total_count': proxies.length,
  'proxies': proxies,
};

Map<String, dynamic> _connectionState(String state) => {'@type': state};

Map<String, dynamic> _authorizationState(String state) => {
  '@type': 'updateAuthorizationState',
  'authorization_state': {'@type': state},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('proxyIndicatorFor', () {
    test('nothing saved reads as none, whatever the link is doing', () {
      for (final state in const [
        null,
        'connectionStateReady',
        'connectionStateConnectingToProxy',
      ]) {
        expect(
          proxyIndicatorFor(
            configured: false,
            enabled: false,
            connectionState: state,
          ),
          ProxyIndicator.none,
          reason: state,
        );
      }
    });

    test('a saved but switched-off proxy reads as off in every link state', () {
      for (final state in const [
        null,
        'connectionStateReady',
        'connectionStateConnectingToProxy',
        'connectionStateWaitingForNetwork',
      ]) {
        expect(
          proxyIndicatorFor(
            configured: true,
            enabled: false,
            connectionState: state,
          ),
          ProxyIndicator.off,
          reason: state,
        );
      }
    });

    test('an enabled proxy follows the connection state TDLib pushes', () {
      ProxyIndicator for_(String? state) => proxyIndicatorFor(
        configured: true,
        enabled: true,
        connectionState: state,
      );
      // Still handshaking with the proxy server, and nothing read yet.
      expect(
        for_('connectionStateConnectingToProxy'),
        ProxyIndicator.connecting,
      );
      expect(for_(null), ProxyIndicator.connecting);
      // Past the handshake the tunnel carries traffic, whether TDLib is
      // talking, catching up or idle.
      expect(for_('connectionStateConnecting'), ProxyIndicator.connected);
      expect(for_('connectionStateUpdating'), ProxyIndicator.connected);
      expect(for_('connectionStateReady'), ProxyIndicator.connected);
      // No network at all: the proxy is on and cannot be reached.
      expect(
        for_('connectionStateWaitingForNetwork'),
        ProxyIndicator.unreachable,
      );
    });
  });

  group('proxyReadingsFrom', () {
    test('keeps the status fields and leaves every credential behind', () {
      final readings = proxyReadingsFrom(
        _proxiesAnswer([
          _proxy(
            id: 1,
            server: '10.0.0.1',
            port: 1080,
            enabled: true,
            comment: 'work',
            credentials: const {
              'username': 'socks-user',
              'password': 'socks-secret',
            },
          ),
          _proxy(
            id: 2,
            server: '10.0.0.2',
            port: 443,
            type: 'proxyTypeMtproto',
            credentials: const {'secret': 'mtproto-secret'},
          ),
        ]),
      )!;

      expect(readings, hasLength(2));
      expect(readings.first.isEnabled, isTrue);
      expect(readings.first.server, '10.0.0.1');
      expect(readings.first.port, 1080);
      expect(readings.last.isEnabled, isFalse);
      final retained = readings.toString();
      for (final value in const [
        'socks-user',
        'socks-secret',
        'mtproto-secret',
        'work',
        'addedProxy',
      ]) {
        expect(retained, isNot(contains(value)), reason: value);
      }
    });

    test('a missing or failed list reads as null, not as no proxy', () {
      expect(proxyReadingsFrom(null), isNull);
      expect(
        proxyReadingsFrom({
          '@type': 'error',
          'code': 500,
          'message': 'no list',
        }),
        isNull,
      );
      expect(proxyReadingsFrom(_proxiesAnswer(const [])), isEmpty);
    });
  });

  group('ProxyStatusController', () {
    final controller = ProxyStatusController.shared;
    final updates = StreamController<Map<String, dynamic>>.broadcast();
    var proxies = <Map<String, dynamic>>[];
    var connectionState = 'connectionStateReady';
    var failProxies = false;
    Completer<void>? gate;
    final requested = <String>[];

    setUpAll(() {
      TdClient.shared.configureProxy(
        TdClientProxyTransport(
          accountSlot: 0,
          query: (request) async {
            final type = request['@type'] as String;
            requested.add(type);
            if (type == 'getProxies') {
              // Captured before the gate: a held answer has to carry the list
              // that was current when it was asked for, or a test for the
              // stale-answer guard would compare a list against itself.
              final Map<String, dynamic> answer = failProxies
                  ? {'@type': 'error', 'code': 500, 'message': 'no list'}
                  : {'@type': 'proxies', 'proxies': proxies};
              final wait = gate;
              if (wait != null) {
                gate = null;
                await wait.future;
              }
              return answer;
            }
            if (type == 'getConnectionState') {
              return _connectionState(connectionState);
            }
            return {'@type': 'ok'};
          },
          send: (_) async {},
          updates: updates.stream,
        ),
      );
    });

    tearDownAll(() async {
      await TdClient.shared.closeProxy();
      await updates.close();
    });

    setUp(() {
      controller.debugReset();
      proxies = const [];
      connectionState = 'connectionStateReady';
      failProxies = false;
      gate = null;
      requested.clear();
      controller.ensureTracking();
    });

    test('reads the enabled proxy and names it', () async {
      proxies = [
        _proxy(id: 1, server: 'unused.example', port: 1080),
        _proxy(
          id: 2,
          server: '10.0.0.1',
          port: 443,
          enabled: true,
          type: 'proxyTypeMtproto',
        ),
      ];
      await controller.refresh();
      final snapshot = controller.snapshot;
      expect(snapshot.indicator, ProxyIndicator.connected);
      expect(snapshot.isEnabled, isTrue);
      expect(snapshot.address, '10.0.0.1:443');
      expect(snapshot.savedCount, 2);
    });

    test('a saved but disabled proxy keeps the address empty', () async {
      proxies = [_proxy(id: 1, server: '10.0.0.1', port: 1080)];
      await controller.refresh();
      expect(controller.snapshot.indicator, ProxyIndicator.off);
      expect(controller.snapshot.isEnabled, isFalse);
      expect(controller.snapshot.address, '');
      expect(controller.snapshot.savedCount, 1);
    });

    test('the process-wide cache retains no credential after a read', () async {
      proxies = [
        _proxy(
          id: 1,
          server: '10.0.0.1',
          port: 1080,
          enabled: true,
          comment: 'work',
          credentials: const {
            'username': 'socks-user',
            'password': 'socks-secret',
          },
        ),
        _proxy(
          id: 2,
          server: '10.0.0.2',
          port: 443,
          type: 'proxyTypeMtproto',
          credentials: const {'secret': 'mtproto-secret'},
        ),
      ];
      await controller.refresh();
      expect(controller.snapshot.address, '10.0.0.1:1080');
      expect(controller.snapshot.savedCount, 2);

      // What the singleton still holds once the answer has been reduced. A raw
      // `addedProxy` map would print every one of these.
      final retained = controller.debugRetainedProxies.toString();
      expect(retained, contains('10.0.0.1'));
      for (final value in const [
        'socks-user',
        'socks-secret',
        'mtproto-secret',
        'work',
        'addedProxy',
        'proxyType',
      ]) {
        expect(retained, isNot(contains(value)), reason: value);
      }
    });

    test(
      'a pushed connection state repaints the badge without a reopen',
      () async {
        proxies = [
          _proxy(id: 1, server: '10.0.0.1', port: 1080, enabled: true),
        ];
        await controller.refresh();
        expect(controller.snapshot.indicator, ProxyIndicator.connected);

        connectionState = 'connectionStateWaitingForNetwork';
        updates.add({
          '@type': 'updateConnectionState',
          'state': _connectionState('connectionStateWaitingForNetwork'),
        });
        await pumpEventQueue();
        expect(controller.snapshot.indicator, ProxyIndicator.unreachable);

        connectionState = 'connectionStateConnectingToProxy';
        updates.add({
          '@type': 'updateConnectionState',
          'state': _connectionState('connectionStateConnectingToProxy'),
        });
        await pumpEventQueue();
        expect(controller.snapshot.indicator, ProxyIndicator.connecting);
      },
    );

    test('a repeated connection state does not re-read the list', () async {
      proxies = [_proxy(id: 1, server: '10.0.0.1', port: 1080, enabled: true)];
      await controller.refresh();
      requested.clear();
      updates.add({
        '@type': 'updateConnectionState',
        'state': _connectionState('connectionStateReady'),
      });
      await pumpEventQueue();
      expect(requested, isEmpty);
    });

    test(
      'a closed authorization drops the reading a reused slot could inherit',
      () async {
        proxies = [
          _proxy(id: 1, server: '10.0.0.1', port: 1080, enabled: true),
        ];
        await controller.refresh();
        expect(controller.snapshot.isEnabled, isTrue);

        updates.add(_authorizationState('authorizationStateClosed'));
        await pumpEventQueue();
        expect(controller.snapshot, ProxyStatusSnapshot.unknown);
        expect(controller.snapshot.address, '');
        expect(controller.snapshot.savedCount, 0);

        // The next account on the same slot brings its own list.
        proxies = const [];
        updates.add(_authorizationState('authorizationStateReady'));
        await pumpEventQueue();
        expect(controller.snapshot.indicator, ProxyIndicator.none);
      },
    );

    test(
      'a failed read keeps the last one instead of claiming no proxy',
      () async {
        proxies = [
          _proxy(id: 1, server: '10.0.0.1', port: 1080, enabled: true),
        ];
        await controller.refresh();
        expect(controller.snapshot.indicator, ProxyIndicator.connected);

        failProxies = true;
        connectionState = 'connectionStateWaitingForNetwork';
        await controller.refresh();
        // The link state still moved, and the enabled proxy is still the one
        // that was read: unreachable, not "nothing is configured".
        expect(controller.snapshot.indicator, ProxyIndicator.unreachable);
        expect(controller.snapshot.address, '10.0.0.1:1080');
      },
    );

    test('a stale answer never paints over a newer one', () async {
      proxies = [
        _proxy(id: 1, server: 'slow.example', port: 1080, enabled: true),
      ];
      final held = Completer<void>();
      gate = held;
      final slow = controller.refresh();
      await pumpEventQueue();

      proxies = [
        _proxy(id: 2, server: 'fresh.example', port: 443, enabled: true),
      ];
      await controller.refresh();
      expect(controller.snapshot.address, 'fresh.example:443');

      held.complete();
      await slow;
      await pumpEventQueue();
      expect(controller.snapshot.address, 'fresh.example:443');
    });

    test('a mutation report re-reads the list', () async {
      await controller.refresh();
      expect(controller.snapshot.indicator, ProxyIndicator.none);
      requested.clear();

      proxies = [_proxy(id: 1, server: '10.0.0.1', port: 1080, enabled: true)];
      controller.proxiesChanged();
      await pumpEventQueue();
      expect(requested, contains('getProxies'));
      expect(controller.snapshot.indicator, ProxyIndicator.connected);
    });
  });

  test(
    'a disposed proxy status controller ignores a pending reading',
    () async {
      final answer = Completer<Map<String, dynamic>>();
      final controller = ProxyStatusController.forTesting(
        activeSlot: () => 1,
        queryForSlot: (request, _) => request['@type'] == 'getProxies'
            ? answer.future
            : Future.value(_connectionState('connectionStateReady')),
      );
      final pending = controller.refresh();
      controller.dispose();
      answer.complete(
        _proxiesAnswer([
          _proxy(id: 1, server: 'synthetic.example', port: 1080, enabled: true),
        ]),
      );
      await expectLater(pending, completes);
      expect(controller.snapshot, ProxyStatusSnapshot.unknown);
    },
  );

  // The TDLib proxy transport only ever carries one slot, so a real account
  // switch — including one that lands while a read is still in flight — needs a
  // controller the test drives itself.
  group('ProxyStatusController across an account switch', () {
    late int activeSlot;
    late StreamController<int> slotChanges;
    late List<Completer<Map<String, dynamic>>> pendingLists;
    late List<int> requestedSlots;
    late ProxyStatusController controller;

    setUp(() {
      activeSlot = 1;
      slotChanges = StreamController<int>.broadcast(sync: true);
      pendingLists = [];
      requestedSlots = [];
      controller = ProxyStatusController.forTesting(
        activeSlot: () => activeSlot,
        activeSlotChanges: slotChanges.stream,
        queryForSlot: (request, slot) {
          if (request['@type'] != 'getProxies') {
            return Future.value(_connectionState('connectionStateReady'));
          }
          requestedSlots.add(slot);
          final completer = Completer<Map<String, dynamic>>();
          pendingLists.add(completer);
          return completer.future;
        },
      );
      controller.ensureTracking();
    });

    tearDown(() async {
      controller.dispose();
      await slotChanges.close();
    });

    void complete(int read, String server, int port) {
      pendingLists[read].complete(
        _proxiesAnswer([
          _proxy(id: read + 1, server: server, port: port, enabled: true),
        ]),
      );
    }

    test(
      'a switch during a pending read gives the new account its own list',
      () async {
        await pumpEventQueue();
        expect(requestedSlots, [1]);

        activeSlot = 2;
        slotChanges.add(2);
        await pumpEventQueue();
        // Not even for one frame: the previous account's proxy is gone before its
        // own answer ever arrives.
        expect(controller.snapshot, ProxyStatusSnapshot.unknown);
        expect(controller.snapshot.address, '');
        expect(controller.snapshot.savedCount, 0);
        expect(requestedSlots, [1, 2]);

        complete(1, 'new.example', 443);
        await pumpEventQueue();
        expect(controller.snapshot.address, 'new.example:443');

        // The read slot 1 started for the old account lands last and must not
        // repaint the sidebar of the account that replaced it.
        complete(0, 'old.example', 1080);
        await pumpEventQueue();
        expect(controller.snapshot.address, 'new.example:443');
        expect(controller.snapshot.savedCount, 1);
      },
    );

    test('a slot reused by another account inherits no pending read', () async {
      await pumpEventQueue();
      activeSlot = 2;
      slotChanges.add(2);
      await pumpEventQueue();
      activeSlot = 1;
      slotChanges.add(1);
      await pumpEventQueue();
      expect(requestedSlots, [1, 2, 1]);
      expect(controller.snapshot, ProxyStatusSnapshot.unknown);

      // The first slot-1 read belonged to the account that has since logged
      // out of it; the second belongs to the account now on the slot.
      complete(0, 'stale.example', 1080);
      await pumpEventQueue();
      expect(controller.snapshot, ProxyStatusSnapshot.unknown);

      complete(2, 'reused.example', 443);
      await pumpEventQueue();
      expect(controller.snapshot.address, 'reused.example:443');

      complete(1, 'other.example', 8888);
      await pumpEventQueue();
      expect(controller.snapshot.address, 'reused.example:443');
    });
  });
}
