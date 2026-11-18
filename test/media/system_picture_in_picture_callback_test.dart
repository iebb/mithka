import 'dart:async';

import 'package:f_videoplayer_pip/f_video_picture_in_picture.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(FVideoPictureInPicture.debugClearSessions);
  tearDown(FVideoPictureInPicture.debugClearSessions);

  test('restore snapshot is routed once to its registered backend', () async {
    var restoreCalls = 0;
    FVideoPictureInPictureSnapshot? restoredSnapshot;
    FVideoPictureInPicture.debugRegisterSession(
      id: 'video-1',
      usesActivePlayer: true,
      onRestoreRequested: (snapshot) {
        restoreCalls++;
        restoredSnapshot = snapshot;
        return true;
      },
    );
    const call = MethodCall('restoreRequested', {
      'id': 'video-1',
      'positionMs': 12345.4,
      'playing': false,
      'speed': 1.5,
      'volume': 0.37,
      'muted': true,
    });

    expect(
      await FVideoPictureInPicture.debugHandleNativeCallback(
        call,
        fromActivePlayer: false,
      ),
      isFalse,
    );
    expect(restoreCalls, 0);
    expect(
      await FVideoPictureInPicture.debugHandleNativeCallback(
        call,
        fromActivePlayer: true,
      ),
      isTrue,
    );
    expect(restoreCalls, 1);
    expect(restoredSnapshot?.position, const Duration(milliseconds: 12345));
    expect(restoredSnapshot?.playing, isFalse);
    expect(restoredSnapshot?.speed, 1.5);
    expect(restoredSnapshot?.volume, 0.37);
    expect(restoredSnapshot?.muted, isTrue);

    expect(
      await FVideoPictureInPicture.debugHandleNativeCallback(
        call,
        fromActivePlayer: true,
      ),
      isFalse,
      reason: 'one native PiP session can restore only one route',
    );
    expect(restoreCalls, 1);
  });

  test('didStop waits for cleanup and consumes the session once', () async {
    final cleanupGate = Completer<void>();
    final events = <String>[];
    Duration? stoppedPosition;
    FVideoPictureInPicture.debugRegisterSession(
      id: 'video-2',
      usesActivePlayer: false,
      onStop: (position) async {
        events.add('cleanup-start');
        stoppedPosition = position;
        await cleanupGate.future;
        events.add('cleanup-end');
      },
    );
    const call = MethodCall('didStop', {'id': 'video-2', 'positionMs': 45678});

    await FVideoPictureInPicture.debugHandleNativeCallback(
      call,
      fromActivePlayer: true,
    );
    expect(events, isEmpty, reason: 'a callback from another backend is stale');

    final stopping = FVideoPictureInPicture.debugHandleNativeCallback(
      call,
      fromActivePlayer: false,
    );
    await Future<void>.delayed(Duration.zero);
    expect(events, ['cleanup-start']);
    expect(stoppedPosition, const Duration(milliseconds: 45678));
    cleanupGate.complete();
    await stopping;
    expect(events, ['cleanup-start', 'cleanup-end']);

    await FVideoPictureInPicture.debugHandleNativeCallback(
      call,
      fromActivePlayer: false,
    );
    expect(events, ['cleanup-start', 'cleanup-end']);
  });

  test('invalid snapshots are safe and callback failures are denied', () async {
    FVideoPictureInPictureSnapshot? snapshot;
    FVideoPictureInPicture.debugRegisterSession(
      id: 'video-3',
      onRestoreRequested: (value) {
        snapshot = value;
        throw StateError('route is unavailable');
      },
    );

    expect(
      await FVideoPictureInPicture.debugHandleNativeCallback(
        const MethodCall('restoreRequested', {
          'id': 'video-3',
          'positionMs': -10,
          'playing': 'invalid',
          'speed': double.nan,
          'volume': double.nan,
          'muted': 1,
        }),
      ),
      isFalse,
    );
    expect(snapshot?.position, Duration.zero);
    expect(snapshot?.playing, isTrue);
    expect(snapshot?.speed, 1.0);
    expect(snapshot?.volume, 1.0);
    expect(snapshot?.muted, isFalse);
  });

  test('missing and stopped sessions reject restore', () async {
    expect(
      await FVideoPictureInPicture.debugHandleNativeCallback(
        const MethodCall('restoreRequested', {'id': 'missing'}),
      ),
      isFalse,
    );

    FVideoPictureInPicture.debugRegisterSession(id: 'video-4');
    await FVideoPictureInPicture.debugHandleNativeCallback(
      const MethodCall('didStop', {'id': 'video-4'}),
    );
    expect(
      await FVideoPictureInPicture.debugHandleNativeCallback(
        const MethodCall('restoreRequested', {'id': 'video-4'}),
      ),
      isFalse,
    );
  });
}
