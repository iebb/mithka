//
//  td_update_dispatch_bench_test.dart
//
//  Measures the cost of fanning TDLib updates out to UI listeners and locks
//  in the typed-dispatch win: a listener registered via updatesOf(type) runs
//  only for its own type, while a subscribe() listener runs for every event.
//
//  The benchmark emits a realistic burst mix through emitLocalUpdate (pure
//  stream dispatch — no FFI) against N filter-style listeners in both
//  registration styles and asserts typed dispatch cuts wall time by at least
//  35%. Counters double as correctness checks: both styles must observe
//  exactly the same matching updates.
//

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/tdlib/td_client.dart';

// A file-progress-heavy mix modeled on a login/download burst.
const _typeMix = <String, int>{
  'updateFile': 60,
  'updateChatLastMessage': 10,
  'updateChatPosition': 8,
  'updateUser': 8,
  'updateNewMessage': 6,
  'updateChatReadInbox': 4,
  'updateDeleteMessages': 2,
  'updateChatActiveStories': 1,
  'updateSavedAnimations': 1,
};

// One watcher per distinct type, mirroring the app's real listener census
// (most screens watch a single type; a couple of broad consumers remain).
const _rounds = 3000; // 3000 × 100 = 300k dispatched updates per style.

List<Map<String, dynamic>> _burst() {
  final burst = <Map<String, dynamic>>[];
  _typeMix.forEach((type, count) {
    for (var i = 0; i < count; i++) {
      burst.add({
        '@type': type,
        'file': {
          'id': i,
          'local': {'downloaded_size': i * 1024},
        },
      });
    }
  });
  return burst;
}

Future<void> main() async {
  test('typed dispatch cuts update fan-out cost by >=35%', () async {
    final client = TdClient.shared;
    final burst = _burst();
    final types = _typeMix.keys.toList();

    Future<(Duration, int)> run({required bool typed}) async {
      var hits = 0;
      final subs = [
        for (final type in types)
          typed
              ? client.updatesOf(type).listen((_) => hits++)
              : client.subscribe().listen((update) {
                  if (update['@type'] != type) return;
                  hits++;
                }),
      ];
      final watch = Stopwatch()..start();
      for (var round = 0; round < _rounds; round++) {
        for (final update in burst) {
          client.emitLocalUpdate(update);
        }
      }
      watch.stop();
      for (final sub in subs) {
        await sub.cancel();
      }
      return (watch.elapsed, hits);
    }

    // Warm-up to stabilize JIT before either measured pass.
    await run(typed: false);
    await run(typed: true);

    final (legacyElapsed, legacyHits) = await run(typed: false);
    final (typedElapsed, typedHits) = await run(typed: true);

    final expectedHits = burst.length * _rounds;
    expect(legacyHits, expectedHits);
    expect(typedHits, expectedHits);

    final improvement =
        (legacyElapsed.inMicroseconds - typedElapsed.inMicroseconds) /
        legacyElapsed.inMicroseconds;
    // Surfaced in the test log so CI records the measured numbers.
    // ignore: avoid_print
    print(
      'dispatch bench: subscribe()+filter=${legacyElapsed.inMilliseconds}ms '
      'updatesOf=${typedElapsed.inMilliseconds}ms '
      'improvement=${(improvement * 100).toStringAsFixed(1)}%',
    );
    expect(
      improvement,
      greaterThanOrEqualTo(0.35),
      reason:
          'typed dispatch must be at least 35% cheaper than '
          'filter-everything listeners',
    );
  });

  test(
    'typed multi-account service dispatch avoids unrelated callbacks',
    () async {
      final client = TdClient.shared;
      // Representative long-lived services: chat list, auth, badges, switcher,
      // moments, notifications, calls, sensitive content, blocked users, files.
      final watchers = <({bool allAccounts, Set<String> types})>[
        (
          allAccounts: false,
          types: {
            'updateChatLastMessage',
            'updateChatPosition',
            'updateChatReadInbox',
            'updateUser',
          },
        ),
        (
          allAccounts: false,
          types: {'updateAuthorizationState', 'updateOption'},
        ),
        (
          allAccounts: false,
          types: {
            'updateUnreadChatCount',
            'updateUnreadMessageCount',
            'mithkaUnreadDelta',
          },
        ),
        (allAccounts: false, types: {'updateAuthorizationState', 'updateUser'}),
        (
          allAccounts: false,
          types: {'updateNewMessage', 'updateDeleteMessages'},
        ),
        (allAccounts: true, types: {'updateNewMessage', 'updateChatReadInbox'}),
        (
          allAccounts: true,
          types: {'updateCall', 'updateNewCallSignalingData'},
        ),
        (allAccounts: true, types: {'updateAuthorizationState'}),
        (allAccounts: true, types: {'updateAuthorizationState'}),
        (allAccounts: true, types: {'updateFile'}),
      ];
      final activeBurst = [
        for (final update in _burst())
          {...update, '@client_id': client.activeClientId},
      ];
      final inactiveBurst = [
        for (final update in activeBurst)
          {...update, '@client_id': client.activeClientId + 100},
      ];

      Future<({int microseconds, int callbacks, int hits})> run(
        bool typed,
      ) async {
        var callbacks = 0;
        var hits = 0;
        final subscriptions = [
          for (final watcher in watchers)
            (typed
                    ? client.updatesOfAny(
                        watcher.types,
                        allAccounts: watcher.allAccounts,
                      )
                    : watcher.allAccounts
                    ? client.subscribeAll()
                    : client.subscribe())
                .listen((update) {
                  callbacks++;
                  if (watcher.types.contains(update['@type'])) hits++;
                }),
        ];
        final watch = Stopwatch()..start();
        for (var round = 0; round < 1000; round++) {
          for (final update in round.isEven ? activeBurst : inactiveBurst) {
            client.routeUpdateForTesting(update);
          }
        }
        watch.stop();
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        return (
          microseconds: watch.elapsedMicroseconds,
          callbacks: callbacks,
          hits: hits,
        );
      }

      await run(false);
      await run(true);
      final broadFirst = await run(false);
      final typedFirst = await run(true);
      final typedSecond = await run(true);
      final broadSecond = await run(false);
      // A structural assertion is stable across devices; timings are diagnostic.
      expect(typedFirst.hits, broadFirst.hits);
      expect(typedSecond.hits, broadSecond.hits);
      expect(typedFirst.hits, 93000);
      expect(typedFirst.callbacks, typedFirst.hits);
      expect(broadFirst.callbacks, 750000);
      final broadUs = (broadFirst.microseconds + broadSecond.microseconds) / 2;
      final typedUs = (typedFirst.microseconds + typedSecond.microseconds) / 2;
      // ignore: avoid_print
      print(
        'multi-account dispatch bench: broad=${(broadUs / 1000).toStringAsFixed(1)}ms '
        'typed=${(typedUs / 1000).toStringAsFixed(1)}ms '
        'callbacks=${broadFirst.callbacks}->${typedFirst.callbacks}',
      );
    },
  );
}
