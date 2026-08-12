import 'dart:async';

import 'package:f_videoplayer_pip/f_video_picture_in_picture.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/app_navigator.dart';
import 'package:mithka/chat/video_playback_queue.dart';
import 'package:mithka/chat/video_player_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';

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

  test(
    'snapshot volume is normalized and supports legacy mute-only data',
    () async {
      final snapshots = <FVideoPictureInPictureSnapshot>[];
      FVideoPictureInPicture.debugRegisterSession(
        id: 'normalized-volume',
        onRestoreRequested: (snapshot) {
          snapshots.add(snapshot);
          return true;
        },
      );
      await FVideoPictureInPicture.debugHandleNativeCallback(
        const MethodCall('restoreRequested', {
          'id': 'normalized-volume',
          'volume': 2.5,
          'muted': false,
        }),
      );
      FVideoPictureInPicture.debugRegisterSession(
        id: 'legacy-muted',
        onRestoreRequested: (snapshot) {
          snapshots.add(snapshot);
          return true;
        },
      );
      await FVideoPictureInPicture.debugHandleNativeCallback(
        const MethodCall('restoreRequested', {
          'id': 'legacy-muted',
          'muted': true,
        }),
      );

      expect(snapshots[0].volume, 1.0);
      expect(snapshots[0].muted, isFalse);
      expect(snapshots[1].volume, 0.0);
      expect(snapshots[1].muted, isTrue);
    },
  );

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

  test(
    'Android enter, actions, restore, and dismissal retain one session',
    () async {
      final events = <String>[];
      final snapshots = <FVideoPictureInPictureSnapshot>[];
      final actions = <FVideoPictureInPictureAction>[];
      FVideoPictureInPicture.debugRegisterSession(
        id: 'android-video',
        usesActivePlayer: false,
        onEntered: (snapshot) {
          events.add('entered');
          snapshots.add(snapshot);
        },
        onRestored: (snapshot) {
          events.add('restored');
          snapshots.add(snapshot);
        },
        onActionRequested: (action) {
          events.add('action');
          actions.add(action);
        },
        onStop: (_) => events.add('stopped'),
      );
      const started = MethodCall('didStart', {
        'id': 'android-video',
        'positionMs': 1200,
        'playing': true,
        'speed': 1.25,
        'volume': 0.62,
        'muted': false,
      });

      await FVideoPictureInPicture.debugHandleNativeCallback(
        started,
        fromActivePlayer: false,
      );
      await FVideoPictureInPicture.debugHandleNativeCallback(
        started,
        fromActivePlayer: false,
      );
      await FVideoPictureInPicture.debugHandleNativeCallback(
        const MethodCall('actionRequested', {
          'id': 'android-video',
          'action': 'pause',
        }),
        fromActivePlayer: false,
      );
      await FVideoPictureInPicture.debugHandleNativeCallback(
        const MethodCall('didRestore', {
          'id': 'android-video',
          'positionMs': 2400,
          'playing': false,
          'speed': 1.25,
          'volume': 0.48,
          'muted': false,
        }),
        fromActivePlayer: false,
      );
      await FVideoPictureInPicture.debugHandleNativeCallback(
        started,
        fromActivePlayer: false,
      );
      await FVideoPictureInPicture.debugHandleNativeCallback(
        const MethodCall('didStop', {
          'id': 'android-video',
          'positionMs': 3600,
        }),
        fromActivePlayer: false,
      );

      expect(events, ['entered', 'action', 'restored', 'entered', 'stopped']);
      expect(actions, [FVideoPictureInPictureAction.pause]);
      expect(snapshots[0].position, const Duration(milliseconds: 1200));
      expect(snapshots[1].position, const Duration(milliseconds: 2400));
      expect(snapshots[0].volume, 0.62);
      expect(snapshots[1].volume, 0.48);

      await FVideoPictureInPicture.debugHandleNativeCallback(
        started,
        fromActivePlayer: false,
      );
      expect(events, ['entered', 'action', 'restored', 'entered', 'stopped']);
    },
  );

  testWidgets('accepted restore inserts the exact queue and snapshot', (
    tester,
  ) async {
    final queue = VideoPlaybackQueue(
      items: [
        VideoPlaybackItem(video: TdFileRef(id: 40), messageId: 400),
        VideoPlaybackItem(video: TdFileRef(id: 41), messageId: 410),
      ],
      index: 1,
      revision: 7,
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigatorKey,
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SizedBox.shrink(),
      ),
    );

    final accepted = await restoreVideoPlaybackFromPictureInPicture(
      queue: queue,
      snapshot: const FVideoPictureInPictureSnapshot(
        position: Duration(seconds: 37),
        playing: false,
        speed: 1.5,
        volume: 0.28,
        muted: true,
      ),
      streamQuery: (_) async => {
        '@type': 'file',
        'id': 41,
        'size': 0,
        'expected_size': 0,
        'local': {
          '@type': 'localFile',
          'path': '',
          'download_offset': 0,
          'downloaded_prefix_size': 0,
          'downloaded_size': 0,
          'is_downloading_active': false,
          'is_downloading_completed': false,
        },
      },
    );
    expect(accepted, isTrue);
    await tester.pump();

    final restored = tester.widget<VideoPlaylistPlayerView>(
      find.byType(VideoPlaylistPlayerView),
    );
    expect(restored.queue, same(queue));
    expect(restored.initialPosition, const Duration(seconds: 37));
    expect(restored.initialPlaying, isFalse);
    expect(restored.initialSpeed, 1.5);
    expect(restored.initialVolume, 0.28);
    expect(restored.initialMuted, isTrue);

    appNavigatorKey.currentState!.pop();
    await tester.pump();
  });
}
