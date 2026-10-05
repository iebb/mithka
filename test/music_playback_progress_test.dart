import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/voice_audio.dart';

void main() {
  testWidgets('polls the native position while running and stops on stop', (
    tester,
  ) async {
    var nativeMs = 0;
    final seen = <int>[];
    final poller = PlaybackProgressPoller(
      read: () async {
        nativeMs += 250;
        return (
          position: Duration(milliseconds: nativeMs),
          duration: const Duration(seconds: 200),
        );
      },
      onProgress: (position, _) => seen.add(position.inMilliseconds),
    );

    poller.start();
    await tester.pump(const Duration(seconds: 1));
    expect(seen, [250, 500, 750, 1000]);

    poller.stop();
    await tester.pump(const Duration(seconds: 1));
    expect(seen, hasLength(4));
    expect(poller.isRunning, isFalse);
  });

  testWidgets('a read that started before a seek is discarded', (tester) async {
    final pending = <Completer<({Duration position, Duration duration})?>>[];
    final seen = <Duration>[];
    final poller = PlaybackProgressPoller(
      read: () {
        final completer =
            Completer<({Duration position, Duration duration})?>();
        pending.add(completer);
        return completer.future;
      },
      onProgress: (position, _) => seen.add(position),
    );

    poller.start();
    await tester.pump(const Duration(milliseconds: 250));
    expect(pending, hasLength(1));

    // The user seeks back while the native read is in flight.
    poller.invalidate();
    pending.single.complete((
      position: const Duration(seconds: 90),
      duration: const Duration(seconds: 200),
    ));
    await tester.pump();
    expect(seen, isEmpty);

    await tester.pump(const Duration(milliseconds: 250));
    pending.last.complete((
      position: const Duration(seconds: 10),
      duration: const Duration(seconds: 200),
    ));
    await tester.pump();
    expect(seen, [const Duration(seconds: 10)]);
    poller.stop();
  });

  testWidgets('a slow read never overlaps the next tick', (tester) async {
    var reads = 0;
    final gate = Completer<({Duration position, Duration duration})?>();
    final poller = PlaybackProgressPoller(
      read: () {
        reads++;
        return gate.future;
      },
      onProgress: (_, _) {},
    );

    poller.start();
    await tester.pump(const Duration(seconds: 2));
    expect(reads, 1);

    gate.complete(null);
    await tester.pump(const Duration(milliseconds: 250));
    expect(reads, 2);
    poller.stop();
  });

  testWidgets('read failures are swallowed and polling continues', (
    tester,
  ) async {
    var reads = 0;
    final seen = <Duration>[];
    final poller = PlaybackProgressPoller(
      read: () async {
        reads++;
        if (reads == 1) throw StateError('player is between tracks');
        return (
          position: const Duration(seconds: 3),
          duration: const Duration(seconds: 200),
        );
      },
      onProgress: (position, _) => seen.add(position),
    );

    poller.start();
    await tester.pump(const Duration(milliseconds: 500));
    expect(seen, [const Duration(seconds: 3)]);
    poller.stop();
  });
}
