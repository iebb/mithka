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
}
