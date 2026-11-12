import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/media/looping_media_playback.dart';

void main() {
  test('muted looping media does not take external audio focus', () {
    expect(mutedLoopingVideoPlayerOptions().mixWithOthers, isTrue);
  });

  group('LoopingMediaPlayerPool', () {
    test('caps concurrent leases at the configured maximum', () {
      final pool = LoopingMediaPlayerPool(maximumPlayers: 4);
      final leases = [for (var i = 0; i < 4; i++) pool.tryAcquire()];

      expect(leases, everyElement(isNotNull));
      expect(pool.activePlayers, 4);
      expect(pool.tryAcquire(), isNull);

      for (final lease in leases) {
        lease!.release();
      }
      expect(pool.activePlayers, 0);
    });

    test('release is idempotent and makes capacity available again', () {
      final pool = LoopingMediaPlayerPool(maximumPlayers: 1);
      final first = pool.tryAcquire()!;

      first.release();
      first.release();

      expect(pool.activePlayers, 0);
      final second = pool.tryAcquire();
      expect(second, isNotNull);
      expect(pool.activePlayers, 1);
      second!.release();
    });

    test('canceled waiters are skipped without consuming capacity', () async {
      final pool = LoopingMediaPlayerPool(maximumPlayers: 1);
      final first = pool.tryAcquire()!;
      final grantedOrder = <int>[];
      final canceled = pool.waitForLease((lease) {
        grantedOrder.add(1);
        lease.release();
      });
      LoopingMediaPlayerLease? grantedLease;
      pool.waitForLease((lease) {
        grantedOrder.add(2);
        grantedLease = lease;
      });

      canceled.cancel();
      first.release();
      await Future<void>.value();

      expect(grantedOrder, [2]);
      expect(pool.activePlayers, 1);
      expect(pool.waitingRequests, 0);
      grantedLease!.release();
    });
  });
}
