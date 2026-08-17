import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/media/looping_media_playback.dart';

void main() {
  test('muted looping media does not take external audio focus', () {
    expect(mutedLoopingVideoPlayerOptions().mixWithOthers, isTrue);
  });

  test('production looping media budget is four players', () {
    expect(loopingMediaPlayerPool.maximumPlayers, 4);
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

    test('release grants only the next FIFO waiter', () async {
      final pool = LoopingMediaPlayerPool(maximumPlayers: 1);
      final first = pool.tryAcquire()!;
      final grantedOrder = <int>[];
      final grantedLeases = <LoopingMediaPlayerLease>[];
      pool.waitForLease((lease) {
        grantedOrder.add(1);
        grantedLeases.add(lease);
      });
      pool.waitForLease((lease) {
        grantedOrder.add(2);
        grantedLeases.add(lease);
      });

      expect(pool.waitingRequests, 2);
      first.release();
      await Future<void>.value();
      expect(grantedOrder, [1]);
      expect(pool.activePlayers, 1);
      expect(pool.waitingRequests, 1);

      grantedLeases.removeAt(0).release();
      await Future<void>.value();
      expect(grantedOrder, [1, 2]);
      expect(pool.activePlayers, 1);
      expect(pool.waitingRequests, 0);

      grantedLeases.single.release();
      expect(pool.activePlayers, 0);
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

  group('loopingMediaPlaybackIsEligible', () {
    test('requires both a visible ticker tree and a foreground app', () {
      expect(
        loopingMediaPlaybackIsEligible(tickerEnabled: true, appIsActive: true),
        isTrue,
      );
      expect(
        loopingMediaPlaybackIsEligible(tickerEnabled: false, appIsActive: true),
        isFalse,
      );
      expect(
        loopingMediaPlaybackIsEligible(tickerEnabled: true, appIsActive: false),
        isFalse,
      );
      expect(
        loopingMediaPlaybackIsEligible(
          tickerEnabled: false,
          appIsActive: false,
        ),
        isFalse,
      );
    });
  });
}
