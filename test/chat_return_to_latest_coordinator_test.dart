import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_return_to_latest_coordinator.dart';

void main() {
  test('button upgrades an automatic request already in flight', () async {
    final harness = _CoordinatorHarness();

    harness.coordinator.request(ChatReturnToLatestSource.automatic);
    expect(harness.loadCalls, 1);
    expect(harness.coordinator.showProgress, isFalse);

    harness.coordinator.request(ChatReturnToLatestSource.user);
    expect(harness.loadCalls, 1);
    expect(harness.coordinator.showProgress, isTrue);

    harness.anchored = false;
    harness.loads.single.complete(true);
    await _flushCompletions();

    final intent = harness.coordinator.takeReady(pointerDown: false);
    expect(intent?.userInitiated, isTrue);
    expect(harness.loadCalls, 1);
  });

  test('a real drag invalidates and discards the old response', () async {
    final harness = _CoordinatorHarness();

    harness.coordinator.request(ChatReturnToLatestSource.user);
    harness.coordinator.cancelForUserDrag();
    expect(harness.invalidateCalls, 1);

    harness.loads.single.complete(true);
    await _flushCompletions();

    expect(harness.coordinator.pending, isFalse);
    expect(harness.coordinator.takeReady(pointerDown: false), isNull);
    expect(harness.readyNotifications, 0);
  });

  test('button after drag retries once the invalidated request ends', () async {
    final harness = _CoordinatorHarness();

    harness.coordinator.request(ChatReturnToLatestSource.automatic);
    harness.coordinator.cancelForUserDrag();
    harness.coordinator.request(ChatReturnToLatestSource.user);
    expect(harness.loadCalls, 1);

    harness.loads.first.complete(false);
    await _flushCompletions();
    expect(harness.loadCalls, 2);
    expect(harness.coordinator.showProgress, isTrue);

    harness.anchored = false;
    harness.loads.last.complete(true);
    await _flushCompletions();

    final intent = harness.coordinator.takeReady(pointerDown: false);
    expect(intent?.userInitiated, isTrue);
  });

  test(
    'explicit failure clears progress, reports failure, and can retry',
    () async {
      final harness = _CoordinatorHarness();

      harness.coordinator.request(ChatReturnToLatestSource.user);
      harness.loads.single.complete(false);
      await _flushCompletions();

      expect(harness.coordinator.pending, isFalse);
      expect(harness.coordinator.showProgress, isFalse);
      expect(harness.failures.single.userInitiated, isTrue);

      harness.coordinator.request(ChatReturnToLatestSource.user);
      expect(harness.loadCalls, 2);
    },
  );

  test('pointer hold delays but does not cancel a ready intent', () async {
    final harness = _CoordinatorHarness();

    harness.coordinator.request(ChatReturnToLatestSource.user);
    harness.anchored = false;
    harness.loads.single.complete(true);
    await _flushCompletions();

    expect(harness.coordinator.takeReady(pointerDown: true), isNull);
    expect(harness.coordinator.pending, isTrue);
    expect(
      harness.coordinator.takeReady(pointerDown: false)?.userInitiated,
      isTrue,
    );
  });

  test('automatic return stays blocked until the user drag ends', () {
    final harness = _CoordinatorHarness();

    harness.coordinator.cancelForUserDrag();
    harness.coordinator.request(ChatReturnToLatestSource.automatic);
    expect(harness.loadCalls, 0);

    harness.coordinator.userDragEnded();
    harness.coordinator.request(ChatReturnToLatestSource.automatic);
    expect(harness.loadCalls, 1);
  });

  test('request exception is reported as a failure', () async {
    final harness = _CoordinatorHarness();

    harness.coordinator.request(ChatReturnToLatestSource.user);
    harness.loads.single.completeError(StateError('offline'));
    await _flushCompletions();

    expect(harness.loadCalls, 1);
    expect(harness.coordinator.pending, isFalse);
    expect(harness.failures.single.userInitiated, isTrue);
  });
}

Future<void> _flushCompletions() => Future<void>.delayed(Duration.zero);

class _CoordinatorHarness {
  _CoordinatorHarness() {
    coordinator = ChatReturnToLatestCoordinator(
      loadLatest: () {
        loadCalls++;
        final completer = Completer<bool>();
        loads.add(completer);
        return completer.future;
      },
      invalidateLatestLoad: () => invalidateCalls++,
      needsLatestLoad: () => anchored,
      onChanged: () {
        final failure = coordinator.takeFailure();
        if (failure != null) failures.add(failure);
      },
      onReadyAvailable: () => readyNotifications++,
    );
  }

  bool anchored = true;
  int loadCalls = 0;
  int invalidateCalls = 0;
  int readyNotifications = 0;
  final List<Completer<bool>> loads = [];
  final List<ChatReturnToLatestFailure> failures = [];
  late final ChatReturnToLatestCoordinator coordinator;
}
