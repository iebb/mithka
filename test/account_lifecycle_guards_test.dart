import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/notifications/push_device_registrar.dart';
import 'package:mithka/settings/blocked_user_service.dart';
import 'package:mithka/settings/sensitive_content_controller.dart';
import 'package:mithka/tdlib/td_client.dart';

Map<String, dynamic> _blockedResponse(Iterable<int> userIds) => {
  '@type': 'messageSenders',
  'senders': [
    for (final userId in userIds)
      {'@type': 'messageSenderUser', 'user_id': userId},
  ],
};

void main() {
  test('TDLib responses only match the client that owns the request', () {
    expect(
      tdResponseMatchesRequestClient(responseClientId: 12, requestClientId: 12),
      isTrue,
    );
    expect(
      tdResponseMatchesRequestClient(responseClientId: 13, requestClientId: 12),
      isFalse,
    );
  });

  test('auth reload publication requires the same action and client', () {
    expect(
      authReloadIsCurrent(
        reloadAction: 7,
        currentAction: 7,
        reloadClientId: 101,
        currentClientId: 101,
      ),
      isTrue,
    );
    expect(
      authReloadIsCurrent(
        reloadAction: 7,
        currentAction: 8,
        reloadClientId: 101,
        currentClientId: 101,
      ),
      isFalse,
    );
    expect(
      authReloadIsCurrent(
        reloadAction: 7,
        currentAction: 7,
        reloadClientId: 101,
        currentClientId: 202,
      ),
      isFalse,
    );
  });

  test(
    'push registration drains one queued rerun after inputs change',
    () async {
      final drain = PushRegistrationDrain();
      final firstPass = Completer<void>();
      var passes = 0;

      Future<void> operation() async {
        passes += 1;
        if (passes == 1) await firstPass.future;
      }

      final running = drain.run(operation);
      await Future<void>.delayed(Duration.zero);
      expect(drain.isRunning, isTrue);
      expect(passes, 1);

      await drain.run(operation);
      await drain.run(operation);
      expect(drain.isQueued, isTrue);

      firstPass.complete();
      await running;
      expect(passes, 2);
      expect(drain.isRunning, isFalse);
      expect(drain.isQueued, isFalse);
    },
  );

  test(
    'blocked-user snapshots are account scoped and publish atomically',
    () async {
      var activeSlot = 1;
      final slotChanges = StreamController<int>.broadcast(sync: true);
      var failSecondPageForSlotOne = false;
      final requestedSlots = <int>[];
      final service = BlockedUserService.forTesting(
        activeSlot: () => activeSlot,
        activeSlotChanges: slotChanges.stream,
        queryForSlot: (request, slot) async {
          requestedSlots.add(slot);
          final offset = request['offset']! as int;
          if (slot == 1 && failSecondPageForSlotOne) {
            if (offset == 0) {
              return _blockedResponse(List<int>.generate(200, (i) => i + 1000));
            }
            throw StateError('offline between pages');
          }
          return _blockedResponse(slot == 1 ? const [11] : const [22]);
        },
      );
      addTearDown(() async {
        service.dispose();
        await slotChanges.close();
      });

      service.enabled = true;
      await service.loadBlockedUsers();
      expect(service.isLoaded, isTrue);
      expect(service.isBlocked(11), isTrue);
      expect(service.isBlocked(22), isFalse);

      activeSlot = 2;
      slotChanges.add(2);
      await service.loadBlockedUsers(accountSlot: 2);
      expect(service.enabled, isFalse);
      expect(service.isBlocked(11), isFalse);
      expect(service.isBlocked(22), isTrue);

      activeSlot = 1;
      slotChanges.add(1);
      await service.loadBlockedUsers(accountSlot: 1);
      expect(service.enabled, isTrue);
      expect(service.isBlocked(11), isTrue);

      failSecondPageForSlotOne = true;
      await service.loadBlockedUsers(accountSlot: 1);
      expect(service.isBlocked(11), isTrue);
      expect(service.isBlocked(1000), isFalse);
      expect(requestedSlots, containsAll(<int>[1, 2]));
    },
  );

  test(
    'blocking completion updates its initiating account after a switch',
    () async {
      var activeSlot = 1;
      final blockStarted = Completer<void>();
      final finishBlock = Completer<void>();
      final service = BlockedUserService.forTesting(
        activeSlot: () => activeSlot,
        queryForSlot: (request, slot) async {
          if (request['@type'] == 'setMessageSenderBlockList') {
            expect(slot, 1);
            blockStarted.complete();
            await finishBlock.future;
            return {'@type': 'ok'};
          }
          return _blockedResponse(slot == 1 ? const [77] : const []);
        },
      );
      addTearDown(service.dispose);

      final blocking = service.blockUser(77);
      await blockStarted.future;
      activeSlot = 2;
      finishBlock.complete();
      await blocking;
      expect(service.isBlocked(77), isFalse);

      activeSlot = 1;
      expect(service.isBlocked(77), isTrue);
    },
  );

  test(
    'stale sensitive-content refresh cannot overwrite the new account',
    () async {
      var activeClientId = 10;
      final slotChanges = StreamController<int>.broadcast(sync: true);
      final responses = <int, Map<String, Completer<Map<String, dynamic>>>>{};
      final controller = SensitiveContentController.forTesting(
        activeClientId: () => activeClientId,
        activeSlotChanges: slotChanges.stream,
        query: (request) {
          final name = request['name']! as String;
          final completer = Completer<Map<String, dynamic>>();
          responses.putIfAbsent(activeClientId, () => {})[name] = completer;
          return completer.future;
        },
      );
      addTearDown(() async {
        controller.dispose();
        await slotChanges.close();
      });

      final initial = controller.initialize();
      await Future<void>.delayed(Duration.zero);
      activeClientId = 20;
      slotChanges.add(2);
      await Future<void>.delayed(Duration.zero);

      for (final response in responses[20]!.values) {
        response.complete({'@type': 'optionValueBoolean', 'value': true});
      }
      await Future<void>.delayed(Duration.zero);
      expect(controller.enabled, isTrue);

      for (final response in responses[10]!.values) {
        response.complete({'@type': 'optionValueBoolean', 'value': false});
      }
      await initial;
      expect(controller.enabled, isTrue);
    },
  );
}
