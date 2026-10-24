import 'dart:async';
import 'dart:io';

import 'package:f_videoplayer/f_videoplayer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/video_player_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Used only to install a deterministic fake for the public video_player API.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A hold on the playback surface plays faster while it lasts and hands the
/// previous rate back on release; a rightward swipe from the left edge leaves
/// the player.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Releasing a surface press leaves the package's double-tap tracker counting
  // down; the harness has to let that 40ms window expire before it ends.
  Future<void> settleGestureTimers(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
  }

  group('hold to speed up', () {
    test('the held rate doubles the current one up to the ceiling', () {
      expect(videoHeldSpeedRate(1), 2);
      expect(videoHeldSpeedRate(0.5), 1);
      expect(videoHeldSpeedRate(1.5), 3);
      expect(videoHeldSpeedRate(2), 4);
      // A rate above the ceiling holds at the ceiling instead of racing.
      expect(videoHeldSpeedRate(3), 4);
      // A report that never settled reads as normal speed.
      expect(videoHeldSpeedRate(double.nan), 2);
      expect(videoHeldSpeedRate(0), 2);
    });

    test('the badge formats the rate without trailing zeros', () {
      expect(formatVideoPlayerSpeed(2), '2x');
      expect(formatVideoPlayerSpeed(1.5), '1.5x');
      expect(formatVideoPlayerSpeed(1.25), '1.25x');
      expect(formatVideoPlayerSpeed(double.nan), '1x');
    });

    testWidgets('a hold raises the rate and release restores it', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeVideoPlatform();
      VideoPlayerPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        SharedPreferences.setMockInitialValues(const {});
        final sourcePath = File('pubspec.yaml').absolute.path;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: VideoPlayerView(
              video: TdFileRef(id: 910, localPath: sourcePath),
              onClose: () {},
              streamQuery: _completedVideoQuery(sourcePath, fileId: 910),
            ),
          ),
        );
        await _pumpUntilPlayerReady(tester);
        final pausesBefore = platform.pauseCalls;

        final hold = await tester.startGesture(const Offset(195, 420));
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('video-held-speed-indicator')),
          findsOneWidget,
        );
        expect(find.text('2x'), findsOneWidget);
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
        expect(platform.playbackSpeeds.last, 2.0);
        // A hold is an acceleration, not a pause.
        expect(platform.pauseCalls, pausesBefore);

        await hold.up();
        await tester.pump();
        expect(
          find.byKey(const ValueKey('video-held-speed-indicator')),
          findsNothing,
        );
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
        expect(platform.playbackSpeeds.last, 1.0);
        // The hold never moved the position.
        expect(platform.seekPositions, isEmpty);

        await _pumpUntilDisposed(tester, platform);
        await settleGestureTimers(tester);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a hold on a quickened video holds the double and restores', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeVideoPlatform();
      VideoPlayerPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        SharedPreferences.setMockInitialValues(const {});
        final sourcePath = File('pubspec.yaml').absolute.path;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: VideoPlayerView(
              video: TdFileRef(id: 911, localPath: sourcePath),
              initialSpeed: 1.5,
              onClose: () {},
              streamQuery: _completedVideoQuery(sourcePath, fileId: 911),
            ),
          ),
        );
        await _pumpUntilPlayerReady(tester);

        final hold = await tester.startGesture(const Offset(195, 420));
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
        expect(find.text('3x'), findsOneWidget);
        expect(platform.playbackSpeeds.last, 3.0);

        await hold.up();
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
        expect(platform.playbackSpeeds.last, 1.5);

        await _pumpUntilDisposed(tester, platform);
        await settleGestureTimers(tester);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  /// Deferred native completions: the reviewer's boundary. The player must
  /// land the rate it intends whatever order the native futures settle in: a
  /// held request still on the wire when the press ends is followed by the
  /// restore, and a restore issued behind it is followed by nothing stale.
  group('pending speed completions', () {
    Future<_FakeVideoPlatform> pumpPlayer(
      WidgetTester tester, {
      int fileId = 920,
      double initialSpeed = 1,
      VoidCallback? onClose,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final platform = _FakeVideoPlatform();
      VideoPlayerPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues(const {});
      final sourcePath = File('pubspec.yaml').absolute.path;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: VideoPlayerView(
            video: TdFileRef(id: fileId, localPath: sourcePath),
            initialSpeed: initialSpeed,
            onClose: onClose ?? () {},
            streamQuery: _completedVideoQuery(sourcePath, fileId: fileId),
          ),
        ),
      );
      await _pumpUntilPlayerReady(tester);
      // The package's long-press tracker arms on the next real event loop turn.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      platform.holdPlaybackSpeed = true;
      // The initialization write (the player's starting rate) already landed;
      // the cases below observe only the requests the gesture issues.
      platform.nativeRates.clear();
      platform.playbackSpeeds.clear();
      return platform;
    }

    /// Lets the player's deferred continuations run against a released fake
    /// barrier; the fake needs a real turn to resume its future.
    Future<void> flushNative(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
    }

    testWidgets('release while the held rate is pending ends at the base rate, '
        'held first then restore', (tester) async {
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = await pumpPlayer(tester);
      try {
        // Both completions are queued before the press, so the test holds the
        // requests and decides which one settles first.
        platform.blockPlaybackSpeed(2.0);
        platform.blockPlaybackSpeed(1.0);
        final hold = await tester.startGesture(const Offset(195, 420));
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 60));
        await tester.pump();

        // The held rate is out, the badge is up, and nothing has settled.
        expect(platform.playbackSpeeds.last, 2.0);
        expect(platform.nativeRates, isEmpty);
        expect(find.text('2x'), findsOneWidget);

        // The press ends while its held rate is still on the wire. The restore
        // is queued behind it, not raced against it.
        await hold.up();
        await tester.pump();
        expect(find.text('2x'), findsNothing);
        expect(
          platform.playbackSpeeds.where((rate) => rate == 1.0),
          isEmpty,
          reason: 'the restore waits for the held request to settle',
        );

        // Completion order A: the held rate settles first, then the restore.
        platform.releasePlaybackSpeed(2.0);
        await flushNative(tester);
        expect(platform.nativeRates, [2.0]);
        expect(platform.pendingPlaybackSpeeds(1.0), 1);

        platform.releasePlaybackSpeed(1.0);
        await flushNative(tester);
        expect(
          platform.nativeRates.last,
          1.0,
          reason:
              'a held completion that lands after release is followed by '
              'the restore, so the native player ends at the base rate',
        );
        expect(debugVideoPlayerBaseSpeed, 1.0);
        expect(videoPlayerBaseSpeedForTesting, 1.0);
        // Reveal the chrome and read the speed it shows for the base rate.
        await tester.tapAt(const Offset(195, 420));
        await tester.pump();
        await tester.tap(_semanticsWidget('More'));
        await tester.pump();
        expect(find.text('Playback Speed 1x'), findsOneWidget);
        expect(find.text('Playback Speed 2x'), findsNothing);
        await settle(tester);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
        platform.playbackSpeedBarriers.clear();
      }
    });

    testWidgets('release while the held rate is pending ends at the base rate, '
        'restore settles first then the held one', (tester) async {
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = await pumpPlayer(tester, fileId: 922);
      try {
        platform.blockPlaybackSpeed(2.0);
        // Two completions for the base rate: the first is released while no
        // request is waiting on it, the second holds the restore the player
        // issues after the held request settles.
        platform.blockPlaybackSpeed(1.0);
        platform.blockPlaybackSpeed(1.0);
        final hold = await tester.startGesture(const Offset(195, 420));
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 60));
        await tester.pump();
        expect(find.text('2x'), findsOneWidget);
        await hold.up();
        await tester.pump();
        expect(find.text('2x'), findsNothing);

        // Both completions are queued, and the held one is still the only
        // request on the wire: the restore was not raced against it.
        expect(platform.nativeRates, isEmpty);
        expect(platform.pendingPlaybackSpeeds(2.0), 1);
        expect(platform.pendingPlaybackSpeeds(1.0), 2);
        expect(platform.playbackSpeeds.where((rate) => rate == 1.0), isEmpty);

        // Completion order B: the restore settles before the held request
        // that is still travelling. Releasing 1.0 first is exactly the order
        // that used to leave the native player at 2x.
        platform.releasePlaybackSpeed(1.0);
        await flushNative(tester);
        expect(
          platform.nativeRates,
          isEmpty,
          reason:
              'nothing applies before the held request it is queued '
              'behind has settled',
        );

        platform.releasePlaybackSpeed(2.0);
        await flushNative(tester);
        expect(
          platform.nativeRates,
          [2.0],
          reason: 'the held completion is followed by the restore',
        );
        platform.releasePlaybackSpeed(1.0);
        await flushNative(tester);
        expect(
          platform.nativeRates,
          [2.0, 1.0],
          reason:
              'the held completion cannot overtake the restore: the '
              'serializer only issues the base rate after it settles',
        );
        expect(platform.nativeRates.last, 1.0);
        expect(debugVideoPlayerBaseSpeed, 1.0);
        expect(videoPlayerBaseSpeedForTesting, 1.0);
        await tester.tapAt(const Offset(195, 420));
        await tester.pump();
        await tester.tap(_semanticsWidget('More'));
        await tester.pump();
        expect(find.text('Playback Speed 1x'), findsOneWidget);
        expect(find.text('Playback Speed 2x'), findsNothing);
        await settle(tester);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
        platform.playbackSpeedBarriers.clear();
      }
    });

    testWidgets('a cancelled press restores the base rate behind a pending '
        'held request', (tester) async {
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = await pumpPlayer(tester, fileId: 923);
      try {
        platform.blockPlaybackSpeed(2.0);
        platform.blockPlaybackSpeed(1.0);
        final hold = await tester.startGesture(const Offset(195, 420));
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 60));
        await tester.pump();
        expect(find.text('2x'), findsOneWidget);

        // A platform-level cancellation (the route losing the arena) ends the
        // press without a long-press end callback.
        await hold.cancel();
        await tester.pump();
        expect(find.text('2x'), findsNothing);

        platform.releasePlaybackSpeed(2.0);
        await flushNative(tester);
        platform.releasePlaybackSpeed(1.0);
        await flushNative(tester);
        expect(
          platform.nativeRates.last,
          1.0,
          reason: 'a cancelled hold still restores the rate it replaced',
        );
        expect(debugVideoPlayerBaseSpeed, 1.0);
        expect(find.textContaining('2x'), findsNothing);
        await settle(tester);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
        platform.playbackSpeedBarriers.clear();
      }
    });

    testWidgets('a newer speed request supersedes a pending held request', (
      tester,
    ) async {
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = await pumpPlayer(tester, fileId: 924);
      try {
        // held 2x, then the chrome's step to 1.25 (the restore is superseded).
        platform.blockPlaybackSpeed(2.0);
        platform.blockPlaybackSpeed(1.25);
        final hold = await tester.startGesture(const Offset(195, 420));
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 60));
        await tester.pump();
        expect(platform.playbackSpeeds.last, 2.0);

        // Release, then a speed change from the chrome before either native
        // write settled: the newest desired rate is 1.25, not the restore.
        await hold.up();
        await tester.pump();
        // Bring the chrome back and step the speed while the restore is still
        // on the wire.
        await tester.tapAt(const Offset(195, 420));
        await tester.pump();
        // The fullscreen chrome keeps its speed control in the overflow menu.
        await tester.tap(_semanticsWidget('More'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(find.byKey(const ValueKey('video-more-speed')));
        await tester.pump();
        // The held request still owns the wire, so the newest rate is only
        // desired: the restore and the step both wait behind it.
        expect(
          platform.playbackSpeeds,
          [2.0],
          reason: 'the chrome speed step goes through the same serializer',
        );

        // The held request settles. The restore it would have been followed by
        // is already superseded, so the next write is the chrome's 1.25 and
        // the native player never sees the 1x it was released to.
        platform.releasePlaybackSpeed(2.0);
        await flushNative(tester);
        expect(platform.playbackSpeeds, [2.0, 1.25]);
        platform.releasePlaybackSpeed(1.25);
        await flushNative(tester);
        expect(platform.nativeRates, [
          2.0,
          1.25,
        ], reason: 'the superseded restore is never written');
        expect(
          platform.nativeRates.last,
          1.25,
          reason:
              'the newest speed request wins over the restore that was '
              'queued behind the held rate',
        );
        expect(debugVideoPlayerBaseSpeed, 1.25);
        await settle(tester);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
        platform.playbackSpeedBarriers.clear();
      }
    });

    testWidgets('a second hold during a pending restore ends at its own base', (
      tester,
    ) async {
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = await pumpPlayer(tester, fileId: 925);
      try {
        // held 2x, its restore, the second hold, its restore.
        platform.blockPlaybackSpeed(2.0);
        platform.blockPlaybackSpeed(1.0);
        platform.blockPlaybackSpeed(2.0);
        platform.blockPlaybackSpeed(1.0);
        final first = await tester.startGesture(const Offset(195, 420));
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 60));
        await tester.pump();
        await first.up();
        await tester.pump();
        expect(find.text('2x'), findsNothing);

        // The first held request settles; the restore it is followed by is
        // still on the wire when the second press lands.
        platform.releasePlaybackSpeed(2.0);
        await flushNative(tester);
        expect(platform.nativeRates, [2.0]);
        expect(platform.pendingPlaybackSpeeds(1.0), 2);

        // The second press measures the base rate, not the held rate the
        // controller still reports; its request queues behind the restore.
        final second = await tester.startGesture(const Offset(195, 420));
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 60));
        await tester.pump();
        expect(
          platform.playbackSpeeds.where((rate) => rate == 2.0),
          hasLength(1),
          reason: 'the second hold waits for the restore on the wire',
        );

        platform.releasePlaybackSpeed(1.0);
        await flushNative(tester);
        platform.releasePlaybackSpeed(2.0);
        await flushNative(tester);
        expect(platform.nativeRates.last, 2.0);

        await second.up();
        await tester.pump();
        platform.releasePlaybackSpeed(1.0);
        await flushNative(tester);
        expect(
          platform.nativeRates.last,
          1.0,
          reason: 'the second hold still knows the rate it replaced',
        );
        expect(platform.nativeRates, [2.0, 1.0, 2.0, 1.0]);
        expect(debugVideoPlayerBaseSpeed, 1.0);
        await settle(tester);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
        platform.playbackSpeedBarriers.clear();
      }
    });

    testWidgets('a held rate still pending at disposal writes nothing after '
        'unmount', (tester) async {
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = await pumpPlayer(tester, fileId: 921);
      try {
        platform.blockPlaybackSpeed(2.0);
        await tester.startGesture(const Offset(195, 420));
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 60));
        await tester.pump();
        expect(find.text('2x'), findsOneWidget);

        // Tear the player down with the request pending, then complete it.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 6));
        platform.releasePlaybackSpeed(2.0);
        await flushNative(tester);
        expect(tester.takeException(), isNull);
        expect(
          platform.nativeRates,
          [2.0],
          reason:
              'the pending request settles, but nothing is issued after '
              'unmount',
        );
        expect(platform.pendingPlaybackSpeeds(1.0), 0);
        await settle(tester);
      } finally {
        platform.playbackSpeedBarriers.clear();
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('edge swipe leaves the player', () {
    testWidgets('a second finger lifting does not finish the swipe', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeVideoPlatform();
      VideoPlayerPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var closed = 0;
      try {
        SharedPreferences.setMockInitialValues(const {});
        final sourcePath = File('pubspec.yaml').absolute.path;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: VideoPlayerView(
              video: TdFileRef(id: 917, localPath: sourcePath),
              initialPlaying: false,
              onClose: () => closed++,
              streamQuery: _completedVideoQuery(sourcePath, fileId: 917),
            ),
          ),
        );
        await _pumpUntilPlayerReady(tester);

        // Finger one drives the edge swipe halfway.
        final first = await tester.startGesture(const Offset(8, 400));
        for (var step = 0; step < 4; step++) {
          await first.moveBy(const Offset(10, 0));
          await tester.pump();
        }
        expect(
          find.byKey(const ValueKey('video-dismiss-drag')),
          findsOneWidget,
        );

        // A second finger lands and lifts. It does not own the swipe, so the
        // drag keeps its offset and the player stays open.
        final second = await tester.startGesture(const Offset(200, 420));
        await second.up();
        await tester.pump();
        expect(closed, 0);
        expect(
          find.byKey(const ValueKey('video-dismiss-drag')),
          findsOneWidget,
          reason: 'the tracked pointer still owns the swipe',
        );

        // The tracked finger finishes the swipe: the player closes once.
        for (var step = 0; step < 4; step++) {
          await first.moveBy(const Offset(20, 0));
          await tester.pump();
        }
        await first.up();
        await tester.pump();
        expect(closed, 1);

        await settleGestureTimers(tester);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a second finger lifting does not end the first hold', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeVideoPlatform();
      VideoPlayerPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        SharedPreferences.setMockInitialValues(const {});
        final sourcePath = File('pubspec.yaml').absolute.path;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: VideoPlayerView(
              video: TdFileRef(id: 927, localPath: sourcePath),
              onClose: () {},
              streamQuery: _completedVideoQuery(sourcePath, fileId: 927),
            ),
          ),
        );
        await _pumpUntilPlayerReady(tester);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        // The controller's own initialization replays the starting rate
        // through play(); wait for those writes to drain so the only writes
        // observed below are the hold's and the restores the test forces.
        var quietRuns = 0;
        var observed = -1;
        while (quietRuns < 3) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 20));
          if (platform.playbackSpeeds.length == observed) {
            quietRuns++;
          } else {
            quietRuns = 0;
            observed = platform.playbackSpeeds.length;
          }
        }
        final writesBeforeSecondFinger = platform.playbackSpeeds.length;

        // The first finger holds; the hold's rate is already on the wire.
        final hold = await tester.startGesture(const Offset(195, 420));
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 60));
        await tester.pump();
        expect(find.text('2x'), findsOneWidget);
        expect(platform.playbackSpeeds.last, 2.0);

        // A second finger lands and lifts. It does not own the hold, so the
        // badge stays up and no restore is queued behind the first finger's
        // back.
        final second = await tester.startGesture(const Offset(60, 300));
        await tester.pump(const Duration(milliseconds: 40));
        await second.up();
        await tester.pump();
        expect(
          find.text('2x'),
          findsOneWidget,
          reason: 'the tracked pointer still owns the hold',
        );
        expect(
          platform.playbackSpeeds
              .skip(writesBeforeSecondFinger)
              .where((rate) => rate == 1.0),
          isEmpty,
          reason: 'a second finger lifting must not queue a restore',
        );

        // A second finger that the system cancels is equally not the owner.
        final third = await tester.startGesture(const Offset(80, 520));
        await tester.pump(const Duration(milliseconds: 40));
        await third.cancel();
        await tester.pump();
        expect(find.text('2x'), findsOneWidget);
        expect(
          platform.playbackSpeeds
              .skip(writesBeforeSecondFinger)
              .where((rate) => rate == 1.0),
          isEmpty,
        );

        // The owning finger releases: only now is the rate restored.
        await hold.up();
        await tester.pump();
        expect(find.text('2x'), findsNothing);
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
        expect(platform.playbackSpeeds.last, 1.0);

        await _pumpUntilDisposed(tester, platform);
        await settleGestureTimers(tester);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
      }
    });
    testWidgets('a second finger cancelling does not abandon the swipe', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeVideoPlatform();
      VideoPlayerPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var closed = 0;
      try {
        SharedPreferences.setMockInitialValues(const {});
        final sourcePath = File('pubspec.yaml').absolute.path;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: VideoPlayerView(
              video: TdFileRef(id: 918, localPath: sourcePath),
              initialPlaying: false,
              onClose: () => closed++,
              streamQuery: _completedVideoQuery(sourcePath, fileId: 918),
            ),
          ),
        );
        await _pumpUntilPlayerReady(tester);

        // Finger one drives the edge swipe halfway.
        final first = await tester.startGesture(const Offset(8, 400));
        for (var step = 0; step < 4; step++) {
          await first.moveBy(const Offset(10, 0));
          await tester.pump();
        }
        expect(
          find.byKey(const ValueKey('video-dismiss-drag')),
          findsOneWidget,
        );

        // A second finger lands and the system cancels it. It does not own the
        // drag, so the gesture keeps its offset and the player stays open.
        final second = await tester.startGesture(const Offset(200, 420));
        await tester.pump(const Duration(milliseconds: 20));
        await second.cancel();
        await tester.pump();
        expect(closed, 0);
        expect(
          find.byKey(const ValueKey('video-dismiss-drag')),
          findsOneWidget,
          reason:
              'the tracked pointer still owns the swipe, even when a '
              'different pointer is cancelled',
        );

        // The tracked finger finishes the swipe: the player closes once.
        for (var step = 0; step < 4; step++) {
          await first.moveBy(const Offset(20, 0));
          await tester.pump();
        }
        await first.up();
        await tester.pump();
        expect(closed, 1);

        await settleGestureTimers(tester);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a short edge swipe snaps back instead of closing', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeVideoPlatform();
      VideoPlayerPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var closed = 0;
      try {
        SharedPreferences.setMockInitialValues(const {});
        final sourcePath = File('pubspec.yaml').absolute.path;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: VideoPlayerView(
              video: TdFileRef(id: 912, localPath: sourcePath),
              initialPlaying: false,
              onClose: () => closed++,
              streamQuery: _completedVideoQuery(sourcePath, fileId: 912),
            ),
          ),
        );
        await _pumpUntilPlayerReady(tester);
        final seeksBeforeSwipe = platform.seekPositions.length;

        final drag = await tester.startGesture(const Offset(8, 400));
        for (var step = 0; step < 5; step++) {
          await drag.moveBy(const Offset(10, 0));
          await tester.pump();
        }
        expect(
          find.byKey(const ValueKey('video-dismiss-drag')),
          findsOneWidget,
        );
        await drag.up();
        await tester.pump();
        expect(closed, 0);
        expect(find.byKey(const ValueKey('video-dismiss-drag')), findsNothing);
        // An abandoned swipe never commits a seek or a navigation.
        expect(platform.seekPositions, hasLength(seeksBeforeSwipe));

        await _pumpUntilDisposed(tester, platform);
        await settleGestureTimers(tester);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a deliberate edge swipe closes the player', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeVideoPlatform();
      VideoPlayerPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var closed = 0;
      try {
        SharedPreferences.setMockInitialValues(const {});
        final sourcePath = File('pubspec.yaml').absolute.path;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: VideoPlayerView(
              video: TdFileRef(id: 913, localPath: sourcePath),
              initialPlaying: false,
              onClose: () => closed++,
              streamQuery: _completedVideoQuery(sourcePath, fileId: 913),
            ),
          ),
        );
        await _pumpUntilPlayerReady(tester);
        final seeksBeforeSwipe = platform.seekPositions.length;

        final drag = await tester.startGesture(const Offset(8, 400));
        for (var step = 0; step < 10; step++) {
          await drag.moveBy(const Offset(14, 0));
          await tester.pump();
        }
        await drag.up();
        await tester.pump();
        expect(closed, 1);
        expect(platform.seekPositions, hasLength(seeksBeforeSwipe));

        await _pumpUntilDisposed(tester, platform);
        await settleGestureTimers(tester);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // A swipe that starts away from the edge keeps its configured meaning;
    // test/mobile_fullscreen_video_player_widget_test.dart's
    // 'default horizontal swipes navigate previous and next' pins it against
    // the same shell fixtures, so it is not duplicated here.
  });
}

Finder _semanticsWidget(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

Future<void> _pumpUntilPlayerReady(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  for (
    var attempt = 0;
    attempt < 40 && find.byType(FVideoPlayer).evaluate().isEmpty;
    attempt++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 25));
  }
}

Future<void> _pumpUntilDisposed(
  WidgetTester tester,
  _FakeVideoPlatform platform, {
  int expectedCalls = 1,
}) async {
  for (
    var attempt = 0;
    attempt < 40 && platform.disposeCalls < expectedCalls;
    attempt++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
}

TdVideoStreamQuery _completedVideoQuery(String path, {required int fileId}) =>
    (request) async {
      if (request['@type'] != 'getFile') {
        throw UnsupportedError('Unexpected TDLib query ${request['@type']}');
      }
      final length = await File(path).length();
      return {
        'id': fileId,
        'size': length,
        'expected_size': length,
        'local': {
          'is_downloading_completed': true,
          'downloaded_size': length,
          'path': path,
        },
        'remote': {'is_uploading_completed': true, 'uploaded_size': length},
      };
    };

class _FakeVideoPlatform extends VideoPlayerPlatform {
  static const duration = Duration(minutes: 2);
  final Map<int, StreamController<VideoEvent>> _events = {};
  final Map<int, Duration> _positions = {};
  var _nextPlayerId = 1;
  var pauseCalls = 0;
  var disposeCalls = 0;
  final seekPositions = <Duration>[];

  /// Every request as it was issued, before its completion.
  final playbackSpeeds = <double>[];

  /// The rate the native side has actually applied, appended when a request's
  /// barrier is released. This is what the player would really play at, so a
  /// regression can prove the completion order instead of trusting the order
  /// the requests went out in.
  final nativeRates = <double>[];

  /// The completions a test still has to release, in the order the test
  /// queued them. A request for a rate takes the oldest entry still waiting at
  /// that rate, so two requests for 1.0 settle one after the other instead of
  /// riding one completer, and a completion is never taken twice.
  final playbackSpeedBarriers = <double, List<Completer<void>>>{};
  final _takenBarriers = <Completer<void>>{};

  /// Defaults to allowing every request; a test queues a completion per
  /// request with [blockPlaybackSpeed].
  bool holdPlaybackSpeed = false;

  /// Queues one completion for the next request for [rate] and returns the
  /// completer the test releases. The player does not see the request finish
  /// until then, and the native rate only moves when it does.
  Completer<void> blockPlaybackSpeed(double rate) {
    final completer = Completer<void>();
    playbackSpeedBarriers.putIfAbsent(rate, () => []).add(completer);
    return completer;
  }

  /// Releases the oldest completion still waiting for [rate]: the test says
  /// which request settles next, in which order.
  void releasePlaybackSpeed(double rate) {
    final queue = playbackSpeedBarriers[rate];
    if (queue == null) {
      throw StateError('no playback-speed request is pending for $rate');
    }
    final barrier = queue.firstWhere(
      (completer) => !completer.isCompleted,
      orElse: () => throw StateError('no pending request for $rate'),
    );
    barrier.complete();
  }

  /// Rates the test still holds a completion for, oldest first.
  int pendingPlaybackSpeeds(double rate) =>
      playbackSpeedBarriers[rate]?.where((c) => !c.isCompleted).length ?? 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final playerId = _nextPlayerId++;
    _events[playerId] = StreamController<VideoEvent>.broadcast();
    _positions[playerId] = Duration.zero;
    return playerId;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    // The map owns this controller and dispose() closes it.
    // ignore: close_sinks
    final controller = _events[playerId]!;
    scheduleMicrotask(() {
      if (!controller.isClosed) {
        controller.add(
          VideoEvent(
            eventType: VideoEventType.initialized,
            duration: duration,
            size: const Size(1920, 1080),
          ),
        );
      }
    });
    return controller.stream;
  }

  @override
  Future<void> dispose(int playerId) async {
    disposeCalls++;
    await _events.remove(playerId)?.close();
    _positions.remove(playerId);
  }

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {
    pauseCalls++;
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    _positions[playerId] = position;
    seekPositions.add(position);
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      _positions[playerId] ?? Duration.zero;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {
    playbackSpeeds.add(speed);
    Completer<void>? barrier;
    final queue = playbackSpeedBarriers[speed];
    if (holdPlaybackSpeed && queue != null) {
      for (final candidate in queue) {
        if (!candidate.isCompleted && _takenBarriers.add(candidate)) {
          barrier = candidate;
          break;
        }
      }
    }
    if (barrier != null) await barrier.future;
    nativeRates.add(speed);
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand(key: ValueKey('fake-video-surface'));
}
