import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:f_videoplayer/f_videoplayer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/video_playback_queue.dart';
import 'package:mithka/chat/video_player_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Used only to install a deterministic fake for the public video_player API.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'iPhone portrait fullscreen keeps controls usable and commits scrubs on release',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
      final orientationCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'SystemChrome.setPreferredOrientations') {
              orientationCalls.add(call);
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
        tester.view.resetPadding();
        tester.view.resetViewPadding();
      });

      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeMobileVideoPlatform();
      VideoPlayerPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        SharedPreferences.setMockInitialValues(const {});

        final sourcePath = File('pubspec.yaml').absolute.path;
        var previousCalls = 0;
        var nextCalls = 0;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: VideoPlayerView(
                video: TdFileRef(id: 700, localPath: sourcePath),
                width: 1920,
                height: 1080,
                sourceChatId: 1,
                messageId: 700,
                previousVideo: VideoPlaybackItem(
                  video: TdFileRef(id: 699),
                  title: 'Previous',
                ),
                nextVideo: VideoPlaybackItem(
                  video: TdFileRef(id: 701),
                  title: 'Next',
                ),
                onNavigate: (delta) {
                  if (delta < 0) {
                    previousCalls++;
                  } else {
                    nextCalls++;
                  }
                },
                onSwitchMode: (_) {},
                onClose: () {},
                streamQuery: _completedVideoQuery(sourcePath, fileId: 700),
              ),
            ),
          ),
        );
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
        expect(tester.takeException(), isNull);
        expect(File(sourcePath).existsSync(), isTrue);
        expect(find.byType(VideoPlayerView), findsOneWidget);
        expect(platform.createCalls, 1);
        expect(
          platform.creationOptions.single.dataSource.sourceType,
          DataSourceType.file,
        );
        expect(
          platform.creationOptions.single.dataSource.uri,
          Uri.file(sourcePath).toString(),
        );
        expect(platform.initializedEvents, 1);
        expect(find.byType(FVideoPlayer), findsOneWidget);
        expect(_timeline, findsOneWidget);
        expect(_volumeSlider, findsOneWidget);
        final playbackTime = find.byKey(const ValueKey('video-playback-time'));
        expect(playbackTime, findsOneWidget);
        expect(find.text('0:00 / 2:00'), findsOneWidget);

        expect(tester.takeException(), isNull);
        final playerRect = tester.getRect(find.byType(FVideoPlayer));
        final reusablePlayer = tester.widget<FVideoPlayer>(
          find.byType(FVideoPlayer),
        );
        final surfaceRect = tester.getRect(
          find.byKey(const ValueKey('fake-mobile-video-surface')),
        );
        final closeRect = tester.getRect(_semanticsWidget('Close'));
        final moreRect = tester.getRect(_semanticsWidget('More'));
        final timelineRect = tester.getRect(_timeline);
        final playbackTimeRect = tester.getRect(playbackTime);
        final previousRect = tester.getRect(_semanticsWidget('Previous video'));
        final pauseControls = _semanticsWidget('Pause');
        expect(pauseControls, findsOneWidget);
        final primaryPauseRect = tester.getRect(pauseControls);
        final nextRect = tester.getRect(_semanticsWidget('Next video'));
        final volumeRect = tester.getRect(_volumeSlider);

        expect(playerRect, const Rect.fromLTWH(0, 0, 390, 844));
        expect(reusablePlayer.alignment, Alignment.center);
        expect(reusablePlayer.autofocus, isFalse);
        expect(surfaceRect.width, closeTo(390, 0.01));
        expect(surfaceRect.height, closeTo(390 * 9 / 16, 0.01));
        expect(surfaceRect.center.dx, closeTo(playerRect.center.dx, 0.01));
        expect(surfaceRect.center.dy, closeTo(playerRect.center.dy, 0.01));
        expect(closeRect.top, greaterThanOrEqualTo(47));
        expect(moreRect.size, const Size.square(44));
        expect(playerRect.contains(closeRect.topLeft), isTrue);
        expect(playerRect.contains(closeRect.bottomRight), isTrue);
        expect(playerRect.contains(moreRect.topLeft), isTrue);
        expect(playerRect.contains(moreRect.bottomRight), isTrue);
        expect(timelineRect.bottom, lessThanOrEqualTo(844 - 34));
        expect(playbackTimeRect.top, greaterThanOrEqualTo(timelineRect.bottom));
        expect(playerRect.contains(timelineRect.bottomLeft), isTrue);
        expect(playerRect.contains(previousRect.topLeft), isTrue);
        expect(playerRect.contains(nextRect.bottomRight), isTrue);
        expect(
          previousRect.center.dy,
          closeTo(primaryPauseRect.center.dy, 0.01),
        );
        expect(nextRect.center.dy, closeTo(primaryPauseRect.center.dy, 0.01));
        expect(previousRect.right, lessThanOrEqualTo(primaryPauseRect.left));
        expect(primaryPauseRect.right, lessThanOrEqualTo(nextRect.left));
        expect(volumeRect.height, 44);
        expect(timelineRect.bottom, lessThanOrEqualTo(volumeRect.top));
        expect(playerRect.contains(volumeRect.topLeft), isTrue);
        expect(playerRect.contains(volumeRect.bottomRight), isTrue);

        final volumeWrites = platform.volumeValues.length;
        await tester.tapAt(Offset(volumeRect.left + 8, volumeRect.center.dy));
        await tester.pump();
        expect(platform.volumeValues, hasLength(volumeWrites + 1));
        final adjustedVolume = platform.volumeValues.last;
        expect(adjustedVolume, inInclusiveRange(0.0, 0.5));
        await tester.tap(_semanticsWidget('Mute'));
        await tester.pump();
        expect(platform.volumeValues.last, 0);
        await tester.tap(_semanticsWidget('Unmute'));
        await tester.pump();
        expect(
          platform.volumeValues.last,
          closeTo(math.max(0.2, adjustedVolume), 0.001),
        );

        // Orientation is a secondary action owned by the host overflow menu.
        expect(_semanticsWidget('Play horizontally'), findsNothing);

        final bareSurfacePoint = Offset(
          playerRect.left + 40,
          surfaceRect.top + 40,
        );
        await tester.tapAt(bareSurfacePoint);
        await tester.pump(const Duration(milliseconds: 400));
        expect(_playerControlOpacity(tester), 0);
        expect(_playerChromeIgnoresPointer(), isTrue);
        expect(_playerChromeExcludesSemantics(), isTrue);
        await tester.tapAt(bareSurfacePoint);
        await tester.pump(const Duration(milliseconds: 400));
        expect(_playerControlOpacity(tester), 1);
        expect(_playerChromeIgnoresPointer(), isFalse);
        expect(_playerChromeExcludesSemantics(), isFalse);
        expect(_semanticsWidget('Pause'), findsOneWidget);

        await tester.tap(_semanticsWidget('More'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 160));
        expect(tester.takeException(), isNull);
        final menuSurface = find.byKey(
          const ValueKey('video-more-menu-surface'),
        );
        final download = find.byKey(const ValueKey('video-more-download'));
        final saveToPhotos = find.byKey(
          const ValueKey('video-more-save-to-photos'),
        );
        final share = find.byKey(const ValueKey('video-more-share'));
        final orientation = find.byKey(
          const ValueKey('video-more-orientation'),
        );
        expect(menuSurface, findsOneWidget);
        expect(download, findsOneWidget);
        expect(saveToPhotos, findsOneWidget);
        expect(share, findsOneWidget);
        expect(orientation, findsOneWidget);
        expect(
          find.descendant(of: download, matching: find.text('Download')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: saveToPhotos,
            matching: find.text('Save to Photos'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: share, matching: find.text('Share')),
          findsOneWidget,
        );
        final menuRect = tester.getRect(menuSurface);
        final downloadRect = tester.getRect(download);
        final saveRect = tester.getRect(saveToPhotos);
        final shareRect = tester.getRect(share);
        expect(menuRect.width, 212);
        expect(menuRect.height, inInclusiveRange(207, 232));
        expect(menuRect.left, greaterThanOrEqualTo(8));
        expect(menuRect.right, lessThanOrEqualTo(390 - 8));
        expect(menuRect.top, greaterThanOrEqualTo(47));
        expect(menuRect.bottom, lessThanOrEqualTo(844 - 34));
        expect(downloadRect.height, greaterThanOrEqualTo(48));
        expect(saveRect.height, greaterThanOrEqualTo(48));
        expect(shareRect.height, greaterThanOrEqualTo(48));
        expect(saveRect.top - downloadRect.bottom, 1);
        expect(shareRect.top - saveRect.bottom, 1);
        expect(downloadRect.top, greaterThanOrEqualTo(menuRect.top + 6));
        expect(downloadRect.right, lessThanOrEqualTo(menuRect.right - 6));
        expect(downloadRect.left, greaterThanOrEqualTo(8));
        expect(downloadRect.bottom, lessThan(saveRect.top));
        expect(saveRect.bottom, lessThan(shareRect.top));
        expect(shareRect.bottom, lessThanOrEqualTo(844 - 34));

        await tester.tap(_semanticsWidget('Play horizontally'));
        await tester.pumpAndSettle();
        expect(orientationCalls, hasLength(1));
        expect(
          orientationCalls.single.arguments,
          containsAll(<String>[
            'DeviceOrientation.landscapeLeft',
            'DeviceOrientation.landscapeRight',
          ]),
        );
        expect(menuSurface, findsNothing);

        await tester.tap(_semanticsWidget('More'));
        await tester.pump(const Duration(milliseconds: 160));
        expect(_semanticsWidget('Use system orientation'), findsOneWidget);
        await tester.tap(_semanticsWidget('Use system orientation'));
        await tester.pumpAndSettle();
        expect(orientationCalls, hasLength(2));

        await tester.tap(_semanticsWidget('More'));
        await tester.pump(const Duration(milliseconds: 160));
        await tester.tapAt(const Offset(20, 200));
        await tester.pump();
        expect(download, findsNothing);
        expect(saveToPhotos, findsNothing);
        expect(share, findsNothing);
        expect(_playerControlOpacity(tester), 0);

        await tester.tapAt(bareSurfacePoint);
        await tester.pump(const Duration(milliseconds: 400));
        expect(_playerControlOpacity(tester), 1);
        expect(_semanticsWidget('Pause'), findsOneWidget);

        await tester.tap(_semanticsWidget('Previous video'));
        await tester.tap(_semanticsWidget('Next video'));
        expect(previousCalls, 1);
        expect(nextCalls, 1);

        final pauseCalls = platform.pauseCalls;
        await tester.tap(_semanticsWidget('Pause'));
        await tester.pump();
        expect(platform.pauseCalls, pauseCalls + 1);
        expect(_semanticsWidget('Play'), findsOneWidget);

        final playCalls = platform.playCalls;
        await tester.tap(_semanticsWidget('Play'));
        await tester.pump();
        expect(platform.playCalls, playCalls + 1);

        await tester.tapAt(timelineRect.center);
        await tester.pump();
        expect(
          platform.seekPositions.last,
          closeToDuration(const Duration(minutes: 1)),
        );
        // Keep playback paused while scrubbing so a seek to the exact end is
        // not followed by video_player's intentional replay-from-zero seek.
        await tester.tap(_semanticsWidget('Pause'));
        await tester.pump();
        expect(_semanticsWidget('Play'), findsOneWidget);

        for (final fraction in const [0.0, 0.5, 1.0]) {
          final seeksBeforeDrag = platform.seekPositions.length;
          final currentTimeline = tester.getRect(_timeline);
          final target = Offset(
            currentTimeline.left + 5 + (currentTimeline.width - 10) * fraction,
            currentTimeline.center.dy,
          );
          final start = Offset(
            target.dx + (fraction == 0 ? 26 : -26),
            target.dy,
          );
          final gesture = await tester.startGesture(start);
          await gesture.moveTo(target);
          await tester.pump();

          expect(
            platform.seekPositions,
            hasLength(seeksBeforeDrag),
            reason: 'pointer movement must only update the preview position',
          );
          expect(_compactScrubPreview, findsOneWidget);
          final previewRect = tester.getRect(_compactScrubPreview);
          final expectedLeft =
              currentTimeline.left +
              (6 + math.max(0, currentTimeline.width - 12) * fraction - 64)
                  .clamp(0.0, math.max(0, currentTimeline.width - 128))
                  .toDouble();
          expect(previewRect.left, closeTo(expectedLeft, 0.01));
          expect(previewRect.right, lessThanOrEqualTo(390 - 8));
          expect(previewRect.top, greaterThanOrEqualTo(47));
          expect(previewRect.bottom, lessThan(currentTimeline.top));
          expect(
            find.text(
              fraction == 0
                  ? '0:00'
                  : fraction == 0.5
                  ? '1:00'
                  : '2:00',
            ),
            findsOneWidget,
          );

          await gesture.up();
          await _pumpUntilPreviewGone(tester);
          expect(platform.seekPositions, hasLength(seeksBeforeDrag + 1));
          expect(
            platform.seekPositions.last,
            closeToDuration(
              Duration(
                milliseconds:
                    (_FakeMobileVideoPlatform.duration.inMilliseconds *
                            fraction)
                        .round(),
              ),
            ),
          );
          expect(_compactScrubPreview, findsNothing);
        }

        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        for (
          var attempt = 0;
          attempt < 40 && platform.disposeCalls == 0;
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(platform.disposeCalls, 1);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'Android queue uses one center transport and a separate bottom playback row',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
        tester.view.resetPadding();
        tester.view.resetViewPadding();
      });

      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeMobileVideoPlatform();
      VideoPlayerPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        SharedPreferences.setMockInitialValues(const {});
        final sourcePath = File('pubspec.yaml').absolute.path;
        var previousCalls = 0;
        var nextCalls = 0;

        Widget player({required bool withNeighbors}) => MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: VideoPlayerView(
              video: TdFileRef(id: 702, localPath: sourcePath),
              width: 1920,
              height: 1080,
              previousVideo: withNeighbors
                  ? VideoPlaybackItem(video: TdFileRef(id: 701))
                  : null,
              nextVideo: withNeighbors
                  ? VideoPlaybackItem(video: TdFileRef(id: 703))
                  : null,
              onNavigate: withNeighbors
                  ? (delta) {
                      if (delta < 0) {
                        previousCalls++;
                      } else {
                        nextCalls++;
                      }
                    }
                  : null,
              onSwitchMode: (_) {},
              onClose: () {},
              streamQuery: _completedVideoQuery(sourcePath, fileId: 702),
            ),
          ),
        );

        await tester.pumpWidget(player(withNeighbors: true));
        await _pumpUntilPlayerReady(tester);
        final queuedPauseControls = _semanticsWidget('Pause');
        expect(queuedPauseControls, findsOneWidget);
        final queuedPrimaryPause = tester.getRect(queuedPauseControls);
        final queuedTimeline = tester.getRect(_timeline);
        final queuedVolume = tester.getRect(_volumeSlider);
        final previousRect = tester.getRect(_semanticsWidget('Previous video'));
        final nextRect = tester.getRect(_semanticsWidget('Next video'));

        expect(
          previousRect.center.dy,
          closeTo(queuedPrimaryPause.center.dy, 0.01),
        );
        expect(nextRect.center.dy, closeTo(queuedPrimaryPause.center.dy, 0.01));
        expect(previousRect.right, lessThanOrEqualTo(queuedPrimaryPause.left));
        expect(queuedPrimaryPause.right, lessThanOrEqualTo(nextRect.left));
        expect(queuedTimeline.bottom, lessThanOrEqualTo(queuedVolume.top));
        await tester.tap(_semanticsWidget('Previous video'));
        await tester.tap(_semanticsWidget('Next video'));
        expect(previousCalls, 1);
        expect(nextCalls, 1);

        await tester.pumpWidget(player(withNeighbors: false));
        await tester.pump();
        final singlePauseControls = _semanticsWidget('Pause');
        expect(singlePauseControls, findsOneWidget);
        final singlePrimaryPause = tester.getRect(singlePauseControls);
        final singleTimeline = tester.getRect(_timeline);
        final singleVolume = tester.getRect(_volumeSlider);

        expect(singlePrimaryPause, queuedPrimaryPause);
        expect(singleTimeline.bottom, lessThanOrEqualTo(singleVolume.top));
        expect(_semanticsWidget('Previous video'), findsNothing);
        expect(_semanticsWidget('Next video'), findsNothing);
        expect(tester.takeException(), isNull);

        tester.view.physicalSize = const Size(270, 844);
        await tester.pumpWidget(player(withNeighbors: true));
        await tester.pump();
        expect(_semanticsWidget('Previous video'), findsOneWidget);
        expect(_semanticsWidget('Pause'), findsOneWidget);
        expect(_semanticsWidget('Next video'), findsOneWidget);
        expect(_volumeSlider, findsOneWidget);
        expect(_semanticsWidget('Switch display mode'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpUntilDisposed(tester, platform);
        expect(platform.disposeCalls, 1);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('queued loading remains dismissible before chrome is ready', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    SharedPreferences.setMockInitialValues(const {});
    final fileResponse = Completer<Map<String, dynamic>>();
    final sourcePath = File('pubspec.yaml').absolute.path;
    var closeCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: VideoPlayerView(
            video: TdFileRef(id: 709, localPath: sourcePath),
            width: 1920,
            height: 1080,
            previousVideo: VideoPlaybackItem(video: TdFileRef(id: 708)),
            nextVideo: VideoPlaybackItem(video: TdFileRef(id: 710)),
            onNavigate: (_) {},
            onClose: () => closeCalls++,
            streamQuery: (_) => fileResponse.future,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(_semanticsWidget('Loading video'), findsOneWidget);
    expect(_semanticsWidget('Close'), findsOneWidget);
    expect(find.byType(FVideoPlayer), findsNothing);
    expect(_semanticsWidget('Previous video'), findsNothing);
    expect(_semanticsWidget('Next video'), findsNothing);
    await tester.tap(_semanticsWidget('Close'));
    expect(closeCalls, 1);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    fileResponse.complete(
      _tdFileInfo(
        fileId: 709,
        path: sourcePath,
        totalBytes: 1,
        downloadedBytes: 0,
        completed: false,
      ),
    );
  });

  testWidgets(
    'single display-mode button exposes a compact stateful chooser and PiP',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
        tester.view.resetPadding();
        tester.view.resetViewPadding();
      });

      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeMobileVideoPlatform();
      VideoPlayerPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        SharedPreferences.setMockInitialValues(const {});
        final sourcePath = File('pubspec.yaml').absolute.path;
        var currentMode = VideoDisplayMode.fullscreen;
        final requestedModes = <VideoDisplayMode>[];
        var fullscreenToggleCalls = 0;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: VideoPlayerView(
                  video: TdFileRef(id: 704, localPath: sourcePath),
                  width: 1920,
                  height: 1080,
                  currentMode: currentMode,
                  onSwitchMode: (mode) {
                    requestedModes.add(mode);
                    setState(() => currentMode = mode);
                  },
                  onToggleFullscreen: () => fullscreenToggleCalls++,
                  onClose: () {},
                  streamQuery: _completedVideoQuery(sourcePath, fileId: 704),
                ),
              ),
            ),
          ),
        );
        await _pumpUntilPlayerReady(tester);

        final reusablePlayer = tester.widget<FVideoPlayer>(
          find.byType(FVideoPlayer),
        );
        expect(reusablePlayer.showPictureInPictureButton, isFalse);
        expect(reusablePlayer.showFullscreenButton, isFalse);
        expect(reusablePlayer.bottomTrailingBuilder, isNotNull);
        final modeButton = _semanticsWidget('Switch display mode');
        expect(modeButton, findsOneWidget);
        var modeButtonSemantics = tester.widget<Semantics>(modeButton);
        expect(modeButtonSemantics.properties.value, 'Fullscreen');
        expect(modeButtonSemantics.properties.expanded, isFalse);
        expect(_semanticsWidget('Fullscreen'), findsNothing);
        expect(_semanticsWidget('Split Screen'), findsNothing);
        expect(_semanticsWidget('Picture in Picture'), findsNothing);

        await tester.tap(modeButton);
        await tester.pump(const Duration(milliseconds: 140));

        expect(_selectedSemanticsWidget('Fullscreen'), findsOneWidget);
        expect(_semanticsWidget('Split Screen'), findsOneWidget);
        expect(_semanticsWidget('Picture in Picture'), findsOneWidget);
        modeButtonSemantics = tester.widget<Semantics>(modeButton);
        expect(modeButtonSemantics.properties.expanded, isTrue);
        final chooserRect = tester.getRect(
          find.byKey(const ValueKey('video-mode-menu-surface')),
        );
        final modeButtonRect = tester.getRect(modeButton);
        expect(chooserRect.bottom, closeTo(modeButtonRect.top - 8, 0.01));
        final optionBounds = <Rect>[
          tester.getRect(_semanticsWidget('Fullscreen')),
          tester.getRect(_semanticsWidget('Split Screen')),
          tester.getRect(_semanticsWidget('Picture in Picture')),
        ].reduce((bounds, option) => bounds.expandToInclude(option));
        expect(optionBounds.width, lessThanOrEqualTo(260));
        expect(optionBounds.height, lessThanOrEqualTo(180));
        expect(optionBounds.left, greaterThanOrEqualTo(8));
        expect(optionBounds.right, lessThanOrEqualTo(382));
        expect(optionBounds.top, greaterThanOrEqualTo(47));
        expect(optionBounds.bottom, lessThanOrEqualTo(810));

        await tester.tap(_semanticsWidget('Split Screen'));
        await tester.pump();
        expect(requestedModes, [VideoDisplayMode.split]);
        expect(_semanticsWidget('Split Screen'), findsNothing);

        await tester.tap(modeButton);
        await tester.pump(const Duration(milliseconds: 140));
        modeButtonSemantics = tester.widget<Semantics>(modeButton);
        expect(modeButtonSemantics.properties.value, 'Split Screen');
        expect(_selectedSemanticsWidget('Split Screen'), findsOneWidget);

        await tester.tap(_semanticsWidget('Picture in Picture'));
        await tester.pump();
        expect(requestedModes, [
          VideoDisplayMode.split,
          VideoDisplayMode.pictureInPicture,
        ]);
        expect(_semanticsWidget('Picture in Picture'), findsNothing);
        expect(fullscreenToggleCalls, 0);

        expect(modeButton, findsOneWidget);
        await tester.tap(modeButton);
        await tester.pump(const Duration(milliseconds: 140));
        expect(_selectedSemanticsWidget('Picture in Picture'), findsOneWidget);
        await tester.tapAt(const Offset(20, 200));
        await tester.pump();
        expect(_selectedSemanticsWidget('Picture in Picture'), findsNothing);
        expect(modeButton, findsOneWidget);
        modeButtonSemantics = tester.widget<Semantics>(modeButton);
        expect(modeButtonSemantics.properties.expanded, isFalse);
        expect(_playerControlOpacity(tester), 0);
        expect(modeButton.hitTestable(), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpUntilDisposed(tester, platform);
        expect(platform.disposeCalls, 1);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('default horizontal swipes navigate previous and next', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final previousPlatform = VideoPlayerPlatform.instance;
    final platform = _FakeMobileVideoPlatform();
    VideoPlayerPlatform.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      SharedPreferences.setMockInitialValues(const {});
      final sourcePath = File('pubspec.yaml').absolute.path;
      final navigation = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: VideoPlayerView(
              video: TdFileRef(id: 706, localPath: sourcePath),
              width: 1920,
              height: 1080,
              previousVideo: VideoPlaybackItem(video: TdFileRef(id: 705)),
              nextVideo: VideoPlaybackItem(video: TdFileRef(id: 707)),
              onNavigate: navigation.add,
              onSwitchMode: (_) {},
              onClose: () {},
              streamQuery: _completedVideoQuery(sourcePath, fileId: 706),
            ),
          ),
        ),
      );
      await _pumpUntilPlayerReady(tester);
      await tester.pump();

      await tester.dragFrom(const Offset(320, 355), const Offset(-90, 0));
      await tester.pump();
      expect(navigation, [1]);

      await tester.dragFrom(const Offset(70, 355), const Offset(90, 0));
      await tester.pump();
      expect(navigation, [1, -1]);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 50));

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpUntilDisposed(tester, platform);
      expect(platform.disposeCalls, 1);
    } finally {
      VideoPlayerPlatform.instance = previousPlatform;
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('pinch zooms around the video and one finger pans while zoomed', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final previousPlatform = VideoPlayerPlatform.instance;
    final platform = _FakeMobileVideoPlatform();
    VideoPlayerPlatform.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      SharedPreferences.setMockInitialValues(const {});
      final sourcePath = File('pubspec.yaml').absolute.path;
      final navigation = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: VideoPlayerView(
              video: TdFileRef(id: 715, localPath: sourcePath),
              width: 1920,
              height: 1080,
              previousVideo: VideoPlaybackItem(video: TdFileRef(id: 714)),
              nextVideo: VideoPlaybackItem(video: TdFileRef(id: 716)),
              onNavigate: navigation.add,
              onSwitchMode: (_) {},
              onClose: () {},
              streamQuery: _completedVideoQuery(sourcePath, fileId: 715),
            ),
          ),
        ),
      );
      await _pumpUntilPlayerReady(tester);
      await tester.pump();

      final zoomTransform = find.byKey(const ValueKey('video-zoom-transform'));
      final zoomTranslation = find.byKey(
        const ValueKey('video-zoom-translation'),
      );
      expect(
        tester.widget<Transform>(zoomTransform).transform.getMaxScaleOnAxis(),
        1,
      );

      final left = await tester.createGesture(pointer: 11);
      final right = await tester.createGesture(pointer: 12);
      await left.down(const Offset(145, 355));
      await right.down(const Offset(245, 355));
      await tester.pump();
      await left.moveTo(const Offset(80, 355));
      await right.moveTo(const Offset(310, 355));
      await tester.pump();

      expect(
        tester.widget<Transform>(zoomTransform).transform.getMaxScaleOnAxis(),
        greaterThan(1.2),
      );
      expect(
        find.byKey(const ValueKey('video-zoom-indicator')),
        findsOneWidget,
      );

      await left.up();
      await right.up();
      await tester.pump();
      expect(find.byKey(const ValueKey('video-zoom-indicator')), findsNothing);

      final translationBeforePan = tester
          .widget<Transform>(zoomTranslation)
          .transform
          .getTranslation()
          .x;
      await tester.dragFrom(const Offset(195, 355), const Offset(60, 0));
      await tester.pump();
      final translationAfterPan = tester
          .widget<Transform>(zoomTranslation)
          .transform
          .getTranslation()
          .x;
      expect(translationAfterPan, greaterThan(translationBeforePan));
      expect(navigation, isEmpty);

      final resetLeft = await tester.createGesture(pointer: 13);
      final resetRight = await tester.createGesture(pointer: 14);
      await resetLeft.down(const Offset(80, 355));
      await resetRight.down(const Offset(310, 355));
      await tester.pump();
      await resetLeft.moveTo(const Offset(170, 355));
      await resetRight.moveTo(const Offset(220, 355));
      await tester.pump();
      await resetLeft.up();
      await resetRight.up();
      await tester.pump();

      expect(
        tester.widget<Transform>(zoomTransform).transform.getMaxScaleOnAxis(),
        1,
      );
      expect(
        tester.widget<Transform>(zoomTranslation).transform.getTranslation().x,
        0,
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 50));

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpUntilDisposed(tester, platform);
      expect(platform.disposeCalls, 1);
    } finally {
      VideoPlayerPlatform.instance = previousPlatform;
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('on-demand navigation preserves the selected volume', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final previousPlatform = VideoPlayerPlatform.instance;
    final platform = _FakeMobileVideoPlatform();
    VideoPlayerPlatform.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      SharedPreferences.setMockInitialValues(const {});
      final sourcePath = File('pubspec.yaml').absolute.path;
      final sourceLength = File(sourcePath).lengthSync();
      final queueChanges = <VideoPlaybackQueue>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: VideoOnDemandPlayerView(
              queue: VideoPlaybackQueue(
                items: [
                  VideoPlaybackItem(
                    video: TdFileRef(id: 720, localPath: sourcePath),
                    width: 1920,
                    height: 1080,
                  ),
                  VideoPlaybackItem(
                    video: TdFileRef(id: 721, localPath: sourcePath),
                    width: 1920,
                    height: 1080,
                  ),
                ],
              ),
              onClose: () {},
              onQueueChanged: queueChanges.add,
              streamQuery: (request) async => _tdFileInfo(
                fileId: request['file_id'] as int,
                path: sourcePath,
                totalBytes: sourceLength,
                downloadedBytes: sourceLength,
                completed: true,
              ),
            ),
          ),
        ),
      );
      await _pumpUntilPlayerReady(tester);

      final sliderRect = tester.getRect(_volumeSlider);
      await tester.tapAt(
        Offset(sliderRect.left + sliderRect.width * 0.35, sliderRect.center.dy),
      );
      await tester.pump();
      final selectedVolume = platform.volumeValues.last;
      expect(selectedVolume, inInclusiveRange(0.1, 0.6));

      await tester.dragFrom(const Offset(320, 355), const Offset(-90, 0));
      for (var i = 0; i < 20 && platform.initializedEvents < 2; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(queueChanges.single.index, 1);
      expect(platform.initializedEvents, 2);
      expect(platform.volumeValues.last, closeTo(selectedVolume, 0.001));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpUntilDisposed(tester, platform);
    } finally {
      VideoPlayerPlatform.instance = previousPlatform;
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'single video uses the standalone landscape chrome without on-demand UI',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(844, 390);
      tester.view.padding = const FakeViewPadding(
        left: 59,
        right: 59,
        bottom: 21,
      );
      tester.view.viewPadding = const FakeViewPadding(
        left: 59,
        right: 59,
        bottom: 21,
      );
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
        tester.view.resetPadding();
        tester.view.resetViewPadding();
      });

      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeMobileVideoPlatform();
      VideoPlayerPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        SharedPreferences.setMockInitialValues(const {});
        final sourcePath = File('pubspec.yaml').absolute.path;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: VideoOnDemandPlayerView(
                queue: VideoPlaybackQueue.single(
                  VideoPlaybackItem(
                    video: TdFileRef(id: 729, localPath: sourcePath),
                    width: 1920,
                    height: 1080,
                    durationSeconds: 120,
                    title: 'Single video',
                  ),
                ),
                onClose: () {},
                streamQuery: _completedVideoQuery(sourcePath, fileId: 729),
              ),
            ),
          ),
        );
        await _pumpUntilPlayerReady(tester);

        final playerRect = tester.getRect(find.byType(FVideoPlayer));
        final standaloneSurface = find.byKey(
          const ValueKey('video-standalone-surface'),
        );
        final standaloneChrome = find.byKey(
          const ValueKey('video-standalone-bottom-chrome'),
        );
        expect(playerRect, const Rect.fromLTWH(0, 0, 844, 390));
        expect(standaloneSurface, findsOneWidget);
        expect(standaloneChrome, findsOneWidget);
        expect(
          find.byKey(const ValueKey('video-playback-time')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('video-on-demand-panel')),
          findsNothing,
        );
        expect(find.text('ON-DEMAND'), findsNothing);
        expect(find.text('UP NEXT'), findsNothing);
        expect(find.text('Single video'), findsOneWidget);
        expect(_semanticsWidget('Seek backward 10 seconds'), findsOneWidget);
        expect(_semanticsWidget('Seek forward 10 seconds'), findsOneWidget);
        expect(_timeline, findsOneWidget);
        expect(_volumeSlider, findsOneWidget);
        expect(
          tester.getRect(standaloneChrome).bottom,
          lessThanOrEqualTo(390 - 21),
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpUntilDisposed(tester, platform);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'on-demand queue opens only from its toggle without reloading playback',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
        tester.view.resetPadding();
        tester.view.resetViewPadding();
      });

      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeMobileVideoPlatform();
      VideoPlayerPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        SharedPreferences.setMockInitialValues(const {});
        final sourcePath = File('pubspec.yaml').absolute.path;
        final sourceLength = File(sourcePath).lengthSync();
        final queueChanges = <VideoPlaybackQueue>[];
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: VideoOnDemandPlayerView(
                queue: VideoPlaybackQueue(
                  items: [
                    VideoPlaybackItem(
                      video: TdFileRef(id: 730, localPath: sourcePath),
                      width: 1920,
                      height: 1080,
                      durationSeconds: 3723,
                      title: 'Opening scene',
                    ),
                    VideoPlaybackItem(
                      video: TdFileRef(id: 731, localPath: sourcePath),
                      width: 1920,
                      height: 1080,
                      durationSeconds: 420,
                      title: 'Repetition de la Carrera Canada Grand Prix',
                    ),
                    VideoPlaybackItem(
                      video: TdFileRef(id: 732, localPath: sourcePath),
                      width: 1920,
                      height: 1080,
                      durationSeconds: 98,
                      title: 'Closing scene',
                    ),
                  ],
                ),
                onClose: () {},
                onQueueChanged: queueChanges.add,
                streamQuery: (request) async => _tdFileInfo(
                  fileId: request['file_id'] as int,
                  path: sourcePath,
                  totalBytes: sourceLength,
                  downloadedBytes: sourceLength,
                  completed: true,
                ),
              ),
            ),
          ),
        );
        await _pumpUntilPlayerReady(tester);

        final panel = find.byKey(const ValueKey('video-on-demand-panel'));
        final surface = find.byKey(const ValueKey('video-on-demand-surface'));
        final toggle = find.byKey(const ValueKey('video-on-demand-toggle'));
        expect(find.byType(FVideoPlayer), findsOneWidget);
        expect(toggle, findsOneWidget);
        expect(panel, findsNothing);
        expect(surface, findsNothing);
        expect(find.text('ON-DEMAND'), findsNothing);
        expect(find.text('UP NEXT'), findsNothing);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                RegExp(
                  r'playlist|chapters',
                  caseSensitive: false,
                ).hasMatch(widget.data ?? ''),
          ),
          findsNothing,
        );

        final initializationsBeforePanel = platform.initializedEvents;
        await tester.tap(toggle);
        await tester.pump();

        expect(panel, findsOneWidget);
        expect(surface, findsOneWidget);
        expect(find.text('ON-DEMAND'), findsNothing);
        expect(find.text('UP NEXT'), findsNothing);
        expect(find.text('1:02:03'), findsWidgets);
        expect(platform.initializedEvents, initializationsBeforePanel);

        final portraitPanelRect = tester.getRect(panel);
        final portraitSurfaceRect = tester.getRect(surface);
        expect(portraitPanelRect.top, greaterThan(portraitSurfaceRect.bottom));
        expect(portraitPanelRect.left, closeTo(14, 0.01));
        expect(portraitPanelRect.right, closeTo(376, 0.01));
        expect(portraitPanelRect.bottom, lessThanOrEqualTo(844 - 34));
        expect(tester.takeException(), isNull);

        await tester.tap(toggle);
        await tester.pump();
        expect(panel, findsNothing);
        expect(surface, findsNothing);
        expect(platform.initializedEvents, initializationsBeforePanel);

        await tester.tap(toggle);
        await tester.pump();
        expect(panel, findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('video-on-demand-item-731')),
        );
        for (var i = 0; i < 30 && platform.initializedEvents < 2; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 25));
        }
        expect(queueChanges.single.index, 1);
        expect(
          find.text('Repetition de la Carrera Canada Grand Prix'),
          findsWidgets,
        );
        expect(find.byType(FVideoPlayer), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(toggle);
        await tester.pump();
        expect(panel, findsOneWidget);
        expect(find.text('Playing'), findsOneWidget);

        tester.view.physicalSize = const Size(1180, 820);
        tester.view.padding = const FakeViewPadding();
        tester.view.viewPadding = const FakeViewPadding();
        await tester.pump();

        final widePanelRect = tester.getRect(panel);
        final wideSurfaceRect = tester.getRect(surface);
        expect(widePanelRect.left, greaterThan(wideSurfaceRect.right));
        expect(widePanelRect.right, lessThanOrEqualTo(1180));
        expect(widePanelRect.bottom, lessThanOrEqualTo(820));
        expect(find.text('Autoplay'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpUntilDisposed(tester, platform, expectedCalls: 2);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('Android volume gesture controls the system media stream', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    const volumeChannel = MethodChannel('mithka/system_media_volume');
    final volumeCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(volumeChannel, (call) async {
          volumeCalls.add(call);
          return switch (call.method) {
            'get' => <String, Object>{
              'index': 6,
              'minimum': 0,
              'maximum': 15,
              'fixed': false,
            },
            'set' => <String, Object>{
              'index': 8,
              'minimum': 0,
              'maximum': 15,
              'fixed': false,
            },
            _ => null,
          };
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(volumeChannel, null);
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final previousPlatform = VideoPlayerPlatform.instance;
    final platform = _FakeMobileVideoPlatform();
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
          home: Scaffold(
            body: VideoPlayerView(
              video: TdFileRef(id: 708, localPath: sourcePath),
              width: 1920,
              height: 1080,
              initialVolume: 0.4,
              onClose: () {},
              streamQuery: _completedVideoQuery(sourcePath, fileId: 708),
            ),
          ),
        ),
      );
      await _pumpUntilPlayerReady(tester);
      for (
        var i = 0;
        i < 20 &&
            (platform.volumeValues.isEmpty || platform.volumeValues.last != 1);
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
      }

      expect(_volumeSlider, findsOneWidget);
      expect(volumeCalls.where((call) => call.method == 'get'), isNotEmpty);
      expect(platform.volumeValues.last, 1);
      final sliderRect = tester.getRect(_volumeSlider);
      final visibleControlPlayerWrites = platform.volumeValues.length;
      await tester.tapAt(sliderRect.center);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(volumeCalls.where((call) => call.method == 'set'), isNotEmpty);
      expect(platform.volumeValues, hasLength(visibleControlPlayerWrites));
      volumeCalls.clear();

      final playerVolumeWritesBefore = platform.volumeValues.length;
      final gesture = await tester.startGesture(const Offset(320, 420));
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -100));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -50));
      await tester.pump();

      expect(volumeCalls.first.method, 'get');
      expect(volumeCalls.where((call) => call.method == 'set'), isNotEmpty);
      expect(
        volumeCalls.last.arguments as double,
        closeTo(0.4 + 170 / 844 * 0.5, 0.001),
      );
      expect(find.text('53%'), findsOneWidget);
      expect(platform.volumeValues, hasLength(playerVolumeWritesBefore));

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 50));
      expect(platform.volumeValues, hasLength(playerVolumeWritesBefore));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpUntilDisposed(tester, platform);
    } finally {
      VideoPlayerPlatform.instance = previousPlatform;
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'Android package volume delegate recovers from controller-gain fallback',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      const volumeChannel = MethodChannel('mithka/system_media_volume');
      final volumeCalls = <MethodCall>[];
      var systemVolumeAvailable = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(volumeChannel, (call) async {
            volumeCalls.add(call);
            if (call.method == 'set' && systemVolumeAvailable) {
              final requested = call.arguments as double;
              return <String, Object>{
                'index': requested <= 0.01 ? 0 : 12,
                'minimum': 0,
                'maximum': 15,
                'fixed': false,
              };
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(volumeChannel, null);
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });

      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeMobileVideoPlatform();
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
            home: Scaffold(
              body: VideoPlayerView(
                video: TdFileRef(id: 712, localPath: sourcePath),
                width: 1920,
                height: 1080,
                initialVolume: 0.4,
                onClose: () {},
                streamQuery: _completedVideoQuery(sourcePath, fileId: 712),
              ),
            ),
          ),
        );
        await _pumpUntilPlayerReady(tester);

        expect(volumeCalls.where((call) => call.method == 'get'), isNotEmpty);
        expect(platform.volumeValues.last, 1);
        final writesBefore = platform.volumeValues.length;
        final sliderRect = tester.getRect(_volumeSlider);
        const requested = 0.25;
        await tester.tapAt(
          Offset(
            sliderRect.left + 5 + (sliderRect.width - 10) * requested,
            sliderRect.center.dy,
          ),
        );
        for (
          var attempt = 0;
          attempt < 20 && platform.volumeValues.length == writesBefore;
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump();
        }
        await tester.pump();

        final setCalls = volumeCalls.where((call) => call.method == 'set');
        expect(setCalls, isNotEmpty);
        expect(setCalls.last.arguments as double, closeTo(requested, 0.001));
        expect(platform.volumeValues, hasLength(writesBefore + 1));
        expect(platform.volumeValues.last, closeTo(requested, 0.001));
        expect(tester.widget<FVideoSlider>(_volumeSlider).value, requested);

        // A real zero returned by the system keeps the platform media stream
        // muted and must not replace the fallback gain yet.
        systemVolumeAvailable = true;
        final fallbackWrites = platform.volumeValues.length;
        await tester.tapAt(Offset(sliderRect.left + 5, sliderRect.center.dy));
        for (
          var attempt = 0;
          attempt < 20 &&
              tester.widget<FVideoSlider>(_volumeSlider).value > 0.001;
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump();
        }
        expect(platform.volumeValues, hasLength(fallbackWrites));
        expect(tester.widget<FVideoSlider>(_volumeSlider).value, 0);

        // Once system volume becomes audible again, controller gain must
        // return to unity. Otherwise the fallback gain and system volume
        // multiply and make playback permanently too quiet.
        await tester.tapAt(
          Offset(
            sliderRect.left + 5 + (sliderRect.width - 10) * 0.65,
            sliderRect.center.dy,
          ),
        );
        for (
          var attempt = 0;
          attempt < 20 && platform.volumeValues.length == fallbackWrites;
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump();
        }
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
        expect(platform.volumeValues, hasLength(fallbackWrites + 1));
        expect(platform.volumeValues.last, 1);
        expect(
          tester.widget<FVideoSlider>(_volumeSlider).value,
          closeTo(0.8, 0.001),
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpUntilDisposed(tester, platform);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'a delayed Android volume read cannot overwrite a newer package control value',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      const volumeChannel = MethodChannel('mithka/system_media_volume');
      final initialRead = Completer<Object?>();
      final volumeCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(volumeChannel, (call) {
            volumeCalls.add(call);
            if (call.method == 'get') return initialRead.future;
            if (call.method == 'set') {
              return Future<Object?>.value(<String, Object>{
                'index': 12,
                'minimum': 0,
                'maximum': 15,
                'fixed': false,
              });
            }
            return Future<Object?>.value();
          });
      addTearDown(() {
        if (!initialRead.isCompleted) initialRead.complete(null);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(volumeChannel, null);
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });

      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeMobileVideoPlatform();
      final reportedVolumes = <double>[];
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
            home: Scaffold(
              body: VideoPlayerView(
                video: TdFileRef(id: 713, localPath: sourcePath),
                width: 1920,
                height: 1080,
                initialVolume: 0.4,
                onVolumeChanged: reportedVolumes.add,
                onClose: () {},
                streamQuery: _completedVideoQuery(sourcePath, fileId: 713),
              ),
            ),
          ),
        );
        await _pumpUntilPlayerReady(tester);
        expect(volumeCalls.where((call) => call.method == 'get'), hasLength(1));

        final sliderRect = tester.getRect(_volumeSlider);
        await tester.tapAt(
          Offset(
            sliderRect.left + 5 + (sliderRect.width - 10) * 0.65,
            sliderRect.center.dy,
          ),
        );
        for (
          var attempt = 0;
          attempt < 20 && reportedVolumes.isEmpty;
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump();
        }
        await tester.pump();
        expect(volumeCalls.where((call) => call.method == 'set'), hasLength(1));
        expect(reportedVolumes.last, closeTo(0.8, 0.001));
        expect(
          tester.widget<FVideoSlider>(_volumeSlider).value,
          closeTo(0.8, 0.001),
        );
        expect(platform.volumeValues.last, 1);

        initialRead.complete(<String, Object>{
          'index': 3,
          'minimum': 0,
          'maximum': 15,
          'fixed': false,
        });
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();

        expect(reportedVolumes, hasLength(1));
        expect(reportedVolumes.single, closeTo(0.8, 0.001));
        expect(
          tester.widget<FVideoSlider>(_volumeSlider).value,
          closeTo(0.8, 0.001),
        );
        expect(platform.volumeValues.last, 1);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpUntilDisposed(tester, platform);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('iOS sparse files retain the loopback network controller', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    FVideoThumbnailRequest? thumbnailRequest;

    late Directory directory;
    late File sparseFile;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp(
        'mithka-sparse-video-test-',
      );
      sparseFile = File('${directory.path}/sparse.mp4');
      final handle = await sparseFile.open(mode: FileMode.write);
      await handle.writeFrom(List<int>.generate(64, (index) => index));
      await handle.truncate(1024 * 1024);
      await handle.close();
    });

    final query = _SparseVideoQuery(
      fileId: 702,
      path: sparseFile.path,
      totalBytes: 1024 * 1024,
      downloadedBytes: 64,
    );
    final previousPlatform = VideoPlayerPlatform.instance;
    final platform = _FakeMobileVideoPlatform();
    VideoPlayerPlatform.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      SharedPreferences.setMockInitialValues(const {});
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: VideoPlayerView(
              video: TdFileRef(id: 702, localPath: sparseFile.path),
              width: 1920,
              height: 1080,
              onClose: () {},
              streamQuery: query.call,
              thumbnailProvider: (request) async {
                thumbnailRequest = request;
                return _transparentPixelPng;
              },
            ),
          ),
        ),
      );
      await _pumpUntilPlayerReady(tester);

      expect(tester.takeException(), isNull);
      expect(platform.creationOptions, hasLength(1));
      final dataSource = platform.creationOptions.single.dataSource;
      expect(dataSource.sourceType, DataSourceType.network);
      final sourceUri = Uri.parse(dataSource.uri!);
      expect(sourceUri.scheme, 'http');
      expect(sourceUri.host, InternetAddress.loopbackIPv4.address);
      expect(sourceUri.path, '/video/702.mp4');
      expect(dataSource.uri, isNot(contains(sparseFile.path)));

      final reusablePlayer = tester.widget<FVideoPlayer>(
        find.byType(FVideoPlayer),
      );
      expect(reusablePlayer.source.kind, FVideoSourceKind.network);
      expect(reusablePlayer.source.location, dataSource.uri);
      expect(
        query.requests.where((request) => request['@type'] == 'getFile'),
        isNotEmpty,
      );
      expect(
        query.requests.where(
          (request) =>
              request['@type'] == 'downloadFile' && request['limit'] == 0,
        ),
        isNotEmpty,
      );

      final timeline = tester.getRect(_timeline);
      final gesture = await tester.startGesture(
        Offset(timeline.center.dx - 30, timeline.center.dy),
      );
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump();

      expect(thumbnailRequest?.source.kind, FVideoSourceKind.network);
      expect(thumbnailRequest?.source.location, dataSource.uri);
      expect(
        find.descendant(of: _compactScrubPreview, matching: find.byType(Image)),
        findsOneWidget,
      );

      await gesture.up();
      await _pumpUntilPreviewGone(tester);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpUntilDisposed(tester, platform);
      expect(platform.disposeCalls, 1);
    } finally {
      VideoPlayerPlatform.instance = previousPlatform;
      debugDefaultTargetPlatformOverride = null;
      await tester.runAsync(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
    }
  });

  testWidgets(
    'Android stream initialization failures fall back to one completed-file download',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });

      late Directory directory;
      late File sparseFile;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp(
          'mithka-initial-file-fallback-test-',
        );
        sparseFile = File('${directory.path}/sparse.mp4');
        final handle = await sparseFile.open(mode: FileMode.write);
        await handle.writeFrom(List<int>.generate(64, (index) => index));
        await handle.truncate(1024 * 1024);
        await handle.close();
      });

      final query = _SparseVideoQuery(
        fileId: 707,
        path: sparseFile.path,
        totalBytes: 1024 * 1024,
        downloadedBytes: 64,
      );
      const initialPosition = Duration(seconds: 23);
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeMobileVideoPlatform(
        initializationFailures: 2,
        initializationFailureMessage:
            'MediaCodecVideoRenderer error from the texture '
            'SurfaceProducer.',
      );
      VideoPlayerPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        SharedPreferences.setMockInitialValues(const {});
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: VideoPlayerView(
                video: TdFileRef(id: 707, localPath: sparseFile.path),
                width: 1920,
                height: 1080,
                onClose: () {},
                streamQuery: query.call,
                initialPosition: initialPosition,
              ),
            ),
          ),
        );
        await _pumpUntilPlayerReady(tester);

        expect(tester.takeException(), isNull);
        expect(platform.createCalls, 3);
        expect(platform.initializedEvents, 1);
        expect(platform.disposedPlayerIds, [1, 2]);
        expect(
          platform.creationOptions.map(
            (options) => options.dataSource.sourceType,
          ),
          [DataSourceType.network, DataSourceType.network, DataSourceType.file],
        );
        expect(platform.creationOptions.map((options) => options.viewType), [
          VideoViewType.textureView,
          VideoViewType.platformView,
          VideoViewType.platformView,
        ]);
        expect(
          query.requests.where(
            (request) =>
                request['@type'] == 'downloadFile' &&
                request['limit'] == 0 &&
                request['synchronous'] == true,
          ),
          hasLength(1),
        );
        expect(find.byType(FVideoPlayer), findsOneWidget);
        final completedFilePlayer = tester.widget<FVideoPlayer>(
          find.byType(FVideoPlayer),
        );
        expect(completedFilePlayer.controller?.value.position, initialPosition);

        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpUntilDisposed(tester, platform, expectedCalls: 3);
        expect(platform.disposedPlayerIds, [1, 2, 3]);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
        await tester.runAsync(() async {
          if (await directory.exists()) await directory.delete(recursive: true);
        });
      }
    },
  );

  testWidgets(
    'Android completed-file decoder errors change to the fullscreen platform view',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });

      final sourcePath = File('pubspec.yaml').absolute.path;
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeMobileVideoPlatform();
      VideoPlayerPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        SharedPreferences.setMockInitialValues(const {});
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: VideoPlayerView(
                video: TdFileRef(id: 710, localPath: sourcePath),
                width: 1920,
                height: 1080,
                onClose: () {},
                streamQuery: _completedVideoQuery(sourcePath, fileId: 710),
              ),
            ),
          ),
        );
        await _pumpUntilPlayerReady(tester);

        final firstPlayer = tester.widget<FVideoPlayer>(
          find.byType(FVideoPlayer),
        );
        final firstController = firstPlayer.controller!;
        const resumePosition = Duration(seconds: 17);
        await firstController.seekTo(resumePosition);
        await tester.pump();
        platform.emitRuntimeError(
          platform.createdPlayerIds.single,
          message:
              'MediaCodecVideoRenderer error from the texture '
              'SurfaceProducer.',
        );
        await _pumpUntilReplacementPlayerReady(
          tester,
          platform,
          previousController: firstController,
        );

        expect(tester.takeException(), isNull);
        expect(platform.createCalls, 2);
        expect(platform.disposedPlayerIds, [1]);
        expect(
          platform.creationOptions.map(
            (options) => options.dataSource.sourceType,
          ),
          [DataSourceType.file, DataSourceType.file],
        );
        expect(platform.creationOptions.map((options) => options.viewType), [
          VideoViewType.textureView,
          VideoViewType.platformView,
        ]);
        final replacement = tester.widget<FVideoPlayer>(
          find.byType(FVideoPlayer),
        );
        expect(replacement.controller?.value.position, resumePosition);
        expect(replacement.controller?.value.isPlaying, isTrue);

        platform.emitRuntimeError(
          platform.createdPlayerIds.last,
          message: 'The platform video surface could not decode this file.',
        );
        for (
          var attempt = 0;
          attempt < 40 && find.text('Try again').evaluate().isEmpty;
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(find.text('Try again'), findsOneWidget);
        expect(find.byType(FVideoPlayer), findsNothing);
        expect(platform.disposedPlayerIds, [1, 2]);

        await tester.tap(find.text('Try again'));
        await _pumpUntilPlayerReady(tester);
        expect(platform.createCalls, 3);
        final retriedPlayer = tester.widget<FVideoPlayer>(
          find.byType(FVideoPlayer),
        );
        expect(retriedPlayer.controller?.value.position, resumePosition);
        expect(retriedPlayer.controller?.value.isPlaying, isTrue);

        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpUntilDisposed(tester, platform, expectedCalls: 3);
        expect(platform.disposedPlayerIds, [1, 2, 3]);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'Android runtime failures change surface then fall back to the completed file',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });

      late Directory directory;
      late File sparseFile;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp(
          'mithka-runtime-recovery-test-',
        );
        sparseFile = File('${directory.path}/sparse.mp4');
        final handle = await sparseFile.open(mode: FileMode.write);
        await handle.writeFrom(List<int>.generate(64, (index) => index));
        await handle.truncate(1024 * 1024);
        await handle.close();
      });

      final query = _SparseVideoQuery(
        fileId: 708,
        path: sparseFile.path,
        totalBytes: 1024 * 1024,
        downloadedBytes: 64,
      );
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeMobileVideoPlatform();
      VideoPlayerPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        SharedPreferences.setMockInitialValues(const {});
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: VideoPlayerView(
                video: TdFileRef(id: 708, localPath: sparseFile.path),
                width: 1920,
                height: 1080,
                onClose: () {},
                streamQuery: query.call,
              ),
            ),
          ),
        );
        await _pumpUntilPlayerReady(tester);

        expect(tester.takeException(), isNull);
        expect(platform.createCalls, 1);
        expect(platform.initializedEvents, 1);
        expect(platform.createdPlayerIds, [1]);
        expect(platform.playCalls, 1);

        final firstPlayer = tester.widget<FVideoPlayer>(
          find.byType(FVideoPlayer),
        );
        final firstController = firstPlayer.controller!;
        const resumePosition = Duration(seconds: 37);
        await firstController.seekTo(resumePosition);
        await tester.pump();
        expect(firstController.value.position, resumePosition);
        expect(firstController.value.isPlaying, isTrue);

        firstPlayer.onError?.call(
          const FVideoPlayerError('A non-fatal command failed.'),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          platform.createCalls,
          1,
          reason: 'non-fatal command errors must retain the active controller',
        );

        platform.emitRuntimeError(
          platform.createdPlayerIds.single,
          message:
              'MediaCodecVideoRenderer error from the texture '
              'SurfaceProducer.',
        );
        await _pumpUntilReplacementPlayerReady(
          tester,
          platform,
          previousController: firstController,
        );

        expect(tester.takeException(), isNull);
        expect(platform.createCalls, 2);
        expect(platform.initializedEvents, 2);
        expect(platform.createdPlayerIds, [1, 2]);
        expect(platform.disposedPlayerIds, [1]);
        expect(platform.creationOptions, hasLength(2));
        expect(platform.creationOptions.map((options) => options.viewType), [
          VideoViewType.textureView,
          VideoViewType.platformView,
        ]);
        expect(
          platform.creationOptions[1].dataSource.uri,
          platform.creationOptions[0].dataSource.uri,
        );

        final replacementPlayer = tester.widget<FVideoPlayer>(
          find.byType(FVideoPlayer),
        );
        final replacementController = replacementPlayer.controller!;
        expect(replacementController, isNot(same(firstController)));
        expect(replacementController.value.position, resumePosition);
        expect(replacementController.value.isPlaying, isTrue);
        expect(platform.seekPositions, [resumePosition, resumePosition]);
        expect(platform.playCalls, 2);

        platform.emitRuntimeError(platform.createdPlayerIds.last);
        await _pumpUntilReplacementPlayerReady(
          tester,
          platform,
          previousController: replacementController,
          expectedCalls: 3,
        );

        expect(tester.takeException(), isNull);
        expect(platform.createCalls, 3);
        expect(platform.initializedEvents, 3);
        expect(platform.createdPlayerIds, [1, 2, 3]);
        expect(platform.disposedPlayerIds, [1, 2]);
        expect(
          platform.creationOptions[2].dataSource.sourceType,
          DataSourceType.file,
        );
        expect(
          platform.creationOptions[2].dataSource.uri,
          Uri.file(sparseFile.path).toString(),
        );
        expect(
          platform.creationOptions[2].viewType,
          VideoViewType.platformView,
        );
        expect(
          query.requests.where(
            (request) =>
                request['@type'] == 'downloadFile' &&
                request['limit'] == 0 &&
                request['synchronous'] == true,
          ),
          hasLength(1),
        );

        final completedFilePlayer = tester.widget<FVideoPlayer>(
          find.byType(FVideoPlayer),
        );
        expect(completedFilePlayer.controller?.value.position, resumePosition);
        expect(completedFilePlayer.controller?.value.isPlaying, isTrue);
        expect(platform.seekPositions, [
          resumePosition,
          resumePosition,
          resumePosition,
        ]);
        expect(platform.playCalls, 3);

        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpUntilDisposed(tester, platform, expectedCalls: 3);
        expect(platform.disposedPlayerIds, [1, 2, 3]);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
        await tester.runAsync(() async {
          if (await directory.exists()) await directory.delete(recursive: true);
        });
      }
    },
  );

  testWidgets('a loopback buffering stall automatically replaces the player', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    late Directory directory;
    late File sparseFile;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp(
        'mithka-buffering-recovery-test-',
      );
      sparseFile = File('${directory.path}/sparse.mp4');
      final handle = await sparseFile.open(mode: FileMode.write);
      await handle.writeFrom(List<int>.generate(64, (index) => index));
      await handle.truncate(1024 * 1024);
      await handle.close();
    });

    final query = _SparseVideoQuery(
      fileId: 709,
      path: sparseFile.path,
      totalBytes: 1024 * 1024,
      downloadedBytes: 64,
    );
    final previousPlatform = VideoPlayerPlatform.instance;
    final platform = _FakeMobileVideoPlatform();
    VideoPlayerPlatform.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      SharedPreferences.setMockInitialValues(const {});
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: VideoPlayerView(
              video: TdFileRef(id: 709, localPath: sparseFile.path),
              width: 1920,
              height: 1080,
              onClose: () {},
              streamQuery: query.call,
            ),
          ),
        ),
      );
      await _pumpUntilPlayerReady(tester);

      final firstPlayer = tester.widget<FVideoPlayer>(
        find.byType(FVideoPlayer),
      );
      final firstController = firstPlayer.controller!;
      platform.emitBufferingStart(platform.createdPlayerIds.single);
      platform.emitIsPlayingStateUpdate(
        platform.createdPlayerIds.single,
        isPlaying: false,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 15));
      await _pumpUntilReplacementPlayerReady(
        tester,
        platform,
        previousController: firstController,
      );

      expect(tester.takeException(), isNull);
      expect(platform.createCalls, 2);
      expect(platform.initializedEvents, 2);
      expect(platform.disposedPlayerIds, [1]);
      expect(
        platform.creationOptions.map(
          (options) => options.dataSource.sourceType,
        ),
        [DataSourceType.network, DataSourceType.network],
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpUntilDisposed(tester, platform, expectedCalls: 2);
      expect(platform.disposedPlayerIds, [1, 2]);
    } finally {
      VideoPlayerPlatform.instance = previousPlatform;
      debugDefaultTargetPlatformOverride = null;
      await tester.runAsync(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
    }
  });

  testWidgets(
    'scrub previews continue during a drag and recover after timeout',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
        tester.view.resetPadding();
        tester.view.resetViewPadding();
      });

      const thumbnailChannel = MethodChannel('fc_native_video_thumbnail');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final firstThumbnail = Completer<Object?>();
      var thumbnailRequests = 0;
      messenger.setMockMethodCallHandler(thumbnailChannel, (call) {
        expect(call.method, 'saveThumbnailToBytes');
        thumbnailRequests++;
        if (thumbnailRequests == 1) return firstThumbnail.future;
        return Future<Object?>.value(_transparentPixelPng);
      });

      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeMobileVideoPlatform();
      VideoPlayerPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        SharedPreferences.setMockInitialValues(const {});
        final sourcePath = File('pubspec.yaml').absolute.path;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: VideoPlayerView(
                video: TdFileRef(id: 703, localPath: sourcePath),
                width: 1920,
                height: 1080,
                onClose: () {},
                streamQuery: _completedVideoQuery(sourcePath, fileId: 703),
              ),
            ),
          ),
        );
        await _pumpUntilPlayerReady(tester);

        final timeline = tester.getRect(_timeline);
        final seeksBeforeDrag = platform.seekPositions.length;
        final gesture = await tester.startGesture(
          Offset(timeline.center.dx - 35, timeline.center.dy),
        );
        await gesture.moveBy(const Offset(55, 0));
        await tester.pump();

        expect(_compactScrubPreview, findsOneWidget);
        expect(thumbnailRequests, 0);
        expect(
          find.descendant(
            of: _compactScrubPreview,
            matching: find.byType(Image),
          ),
          findsNothing,
        );
        expect(platform.seekPositions, hasLength(seeksBeforeDrag));

        await gesture.moveBy(const Offset(35, 0));
        await tester.pump(const Duration(milliseconds: 79));
        expect(thumbnailRequests, 0);
        await tester.pump(const Duration(milliseconds: 1));
        expect(thumbnailRequests, 1);
        expect(platform.seekPositions, hasLength(seeksBeforeDrag));

        await tester.pump(const Duration(seconds: 2, milliseconds: 1));
        expect(thumbnailRequests, 1);
        expect(
          find.descendant(
            of: _compactScrubPreview,
            matching: find.byType(Image),
          ),
          findsNothing,
        );
        expect(platform.seekPositions, hasLength(seeksBeforeDrag));

        await gesture.up();
        await _pumpUntilPreviewGone(tester);
        expect(platform.seekPositions, hasLength(seeksBeforeDrag + 1));
        expect(_compactScrubPreview, findsNothing);

        final secondTimeline = tester.getRect(_timeline);
        final secondGesture = await tester.startGesture(
          Offset(secondTimeline.center.dx - 20, secondTimeline.center.dy),
        );
        await secondGesture.moveBy(const Offset(40, 0));
        await tester.pump(const Duration(milliseconds: 80));
        expect(thumbnailRequests, 2);
        await tester.pump();
        expect(_compactScrubPreview, findsOneWidget);
        expect(
          find.descendant(
            of: _compactScrubPreview,
            matching: find.byType(Image),
          ),
          findsOneWidget,
        );
        expect(platform.seekPositions, hasLength(seeksBeforeDrag + 1));

        await secondGesture.moveBy(const Offset(30, 0));
        await tester.pump(const Duration(milliseconds: 80));
        await tester.pump();
        expect(thumbnailRequests, 3);
        expect(platform.seekPositions, hasLength(seeksBeforeDrag + 1));

        await secondGesture.up();
        await _pumpUntilPreviewGone(tester);
        expect(platform.seekPositions, hasLength(seeksBeforeDrag + 2));
        expect(_compactScrubPreview, findsNothing);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpUntilDisposed(tester, platform);
        expect(platform.disposeCalls, 1);
      } finally {
        if (!firstThumbnail.isCompleted) firstThumbnail.complete(null);
        messenger.setMockMethodCallHandler(thumbnailChannel, null);
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('PiP restore snapshot overrides resume and remains paused', (
    tester,
  ) async {
    final previousPlatform = VideoPlayerPlatform.instance;
    final platform = _FakeMobileVideoPlatform();
    VideoPlayerPlatform.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      SharedPreferences.setMockInitialValues(const {
        'mithka.video.resume.8.802': 12000,
      });
      final sourcePath = File('pubspec.yaml').absolute.path;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: VideoPlayerView(
            video: TdFileRef(id: 802, localPath: sourcePath),
            sourceChatId: 8,
            messageId: 802,
            initialPosition: const Duration(seconds: 37),
            initialPlaying: false,
            initialSpeed: 1.5,
            initialMuted: true,
            onClose: () {},
            streamQuery: _completedVideoQuery(sourcePath, fileId: 802),
          ),
        ),
      );
      await _pumpUntilPlayerReady(tester);

      expect(platform.seekPositions, [const Duration(seconds: 37)]);
      expect(platform.playCalls, 0);
      final restoredPlayer = tester.widget<FVideoPlayer>(
        find.byType(FVideoPlayer),
      );
      expect(restoredPlayer.controller?.value.playbackSpeed, 1.5);
      expect(restoredPlayer.controller?.value.volume, 0.0);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpUntilDisposed(tester, platform);
    } finally {
      VideoPlayerPlatform.instance = previousPlatform;
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

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
  _FakeMobileVideoPlatform platform, {
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

Future<void> _pumpUntilReplacementPlayerReady(
  WidgetTester tester,
  _FakeMobileVideoPlatform platform, {
  required Object previousController,
  int expectedCalls = 2,
}) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 10));
    final players = find.byType(FVideoPlayer).evaluate();
    if (platform.createCalls == expectedCalls &&
        platform.initializedEvents == expectedCalls &&
        players.length == 1 &&
        !identical(
          (players.single.widget as FVideoPlayer).controller,
          previousController,
        )) {
      return;
    }
  }
}

Future<void> _pumpUntilPreviewGone(WidgetTester tester) async {
  for (
    var attempt = 0;
    attempt < 20 && _compactScrubPreview.evaluate().isNotEmpty;
    attempt++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
}

final Finder _timeline = find.byWidgetPredicate(
  (widget) =>
      widget is FVideoSlider && widget.semanticLabel == 'Adjust progress',
);

final Finder _volumeSlider = find.byWidgetPredicate(
  (widget) => widget is FVideoSlider && widget.semanticLabel == 'Adjust volume',
);

final Finder _compactScrubPreview = find.byWidgetPredicate(
  (widget) =>
      widget is Positioned && widget.width == 128 && widget.height == 72,
);

final Finder _playerChromeFade = find.byWidgetPredicate(
  (widget) =>
      widget is AnimatedOpacity &&
      widget.duration == const Duration(milliseconds: 170),
);

double _playerControlOpacity(WidgetTester tester) =>
    tester.widget<AnimatedOpacity>(_playerChromeFade).opacity;

bool _playerChromeIgnoresPointer() => _playerChromeFade
    .evaluate()
    .single
    .findAncestorWidgetOfExactType<IgnorePointer>()!
    .ignoring;

bool _playerChromeExcludesSemantics() => _playerChromeFade
    .evaluate()
    .single
    .findAncestorWidgetOfExactType<ExcludeSemantics>()!
    .excluding;

Finder _semanticsWidget(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

Finder _selectedSemanticsWidget(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.label == label &&
      widget.properties.selected == true,
);

Matcher closeToDuration(Duration expected) => predicate<Duration>(
  (actual) => (actual - expected).abs() <= const Duration(milliseconds: 50),
  'within 50ms of $expected',
);

final _transparentPixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
  'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

TdVideoStreamQuery _completedVideoQuery(String path, {required int fileId}) =>
    (request) async {
      if (request['@type'] != 'getFile') {
        throw UnsupportedError('Unexpected TDLib query ${request['@type']}');
      }
      final length = await File(path).length();
      return _tdFileInfo(
        fileId: fileId,
        path: path,
        totalBytes: length,
        downloadedBytes: length,
        completed: true,
      );
    };

Map<String, dynamic> _tdFileInfo({
  required int fileId,
  required String path,
  required int totalBytes,
  required int downloadedBytes,
  required bool completed,
}) => {
  '@type': 'file',
  'id': fileId,
  'size': totalBytes,
  'expected_size': totalBytes,
  'local': {
    '@type': 'localFile',
    'path': path,
    'download_offset': 0,
    'downloaded_prefix_size': downloadedBytes,
    'downloaded_size': downloadedBytes,
    'is_downloading_active': !completed,
    'is_downloading_completed': completed,
  },
};

final class _SparseVideoQuery {
  _SparseVideoQuery({
    required this.fileId,
    required this.path,
    required this.totalBytes,
    required this.downloadedBytes,
  });

  final int fileId;
  final String path;
  final int totalBytes;
  int downloadedBytes;
  bool completed = false;
  final requests = <Map<String, dynamic>>[];

  Future<Map<String, dynamic>> call(Map<String, dynamic> request) async {
    requests.add(Map<String, dynamic>.from(request));
    switch (request['@type']) {
      case 'getFile':
        return _tdFileInfo(
          fileId: fileId,
          path: path,
          totalBytes: totalBytes,
          downloadedBytes: downloadedBytes,
          completed: completed,
        );
      case 'downloadFile':
        final limit = request['limit'] as int? ?? 0;
        if (limit == 0 && request['synchronous'] == true) {
          downloadedBytes = totalBytes;
          completed = true;
        } else if (limit > 0 && request['synchronous'] == true) {
          downloadedBytes = totalBytes;
        }
        return _tdFileInfo(
          fileId: fileId,
          path: path,
          totalBytes: totalBytes,
          downloadedBytes: downloadedBytes,
          completed: completed,
        );
      case 'getFileDownloadedPrefixSize':
        final offset = request['offset'] as int? ?? 0;
        return {
          '@type': 'fileDownloadedPrefixSize',
          'size': completed
              ? (totalBytes - offset).clamp(0, totalBytes)
              : (downloadedBytes - offset).clamp(0, totalBytes),
        };
      default:
        throw UnsupportedError('Unexpected TDLib query ${request['@type']}');
    }
  }
}

class _FakeMobileVideoPlatform extends VideoPlayerPlatform {
  _FakeMobileVideoPlatform({
    this.initializationFailures = 0,
    this.initializationFailureMessage =
        'The loopback source could not be opened.',
  });

  static const duration = Duration(minutes: 2);
  final int initializationFailures;
  final String initializationFailureMessage;
  final Map<int, StreamController<VideoEvent>> _events = {};
  final Map<int, Duration> _positions = {};
  var _nextPlayerId = 1;
  var createCalls = 0;
  var initializedEvents = 0;
  var playCalls = 0;
  var pauseCalls = 0;
  var disposeCalls = 0;
  final creationOptions = <VideoCreationOptions>[];
  final createdPlayerIds = <int>[];
  final disposedPlayerIds = <int>[];
  final seekPositions = <Duration>[];
  final volumeValues = <double>[];

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    createCalls++;
    creationOptions.add(options);
    final playerId = _nextPlayerId++;
    createdPlayerIds.add(playerId);
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
        if (playerId <= initializationFailures) {
          controller.addError(
            PlatformException(
              code: 'VideoError',
              message: initializationFailureMessage,
            ),
          );
          return;
        }
        initializedEvents++;
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
    disposedPlayerIds.add(playerId);
    await _events.remove(playerId)?.close();
    _positions.remove(playerId);
  }

  void emitRuntimeError(
    int playerId, {
    String message = 'The loopback stream stopped during playback.',
  }) {
    _events[playerId]!.addError(
      PlatformException(code: 'runtime_video_error', message: message),
    );
  }

  void emitBufferingStart(int playerId) {
    _events[playerId]!.add(
      VideoEvent(eventType: VideoEventType.bufferingStart),
    );
  }

  void emitIsPlayingStateUpdate(int playerId, {required bool isPlaying}) {
    _events[playerId]!.add(
      VideoEvent(
        eventType: VideoEventType.isPlayingStateUpdate,
        isPlaying: isPlaying,
      ),
    );
  }

  @override
  Future<void> play(int playerId) async {
    playCalls++;
  }

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
  Future<void> setVolume(int playerId, double volume) async {
    volumeValues.add(volume);
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand(key: ValueKey('fake-mobile-video-surface'));
}
