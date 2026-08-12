import 'dart:async';
import 'dart:io';

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

  const cases =
      <
        ({
          String name,
          TargetPlatform platform,
          VideoPlayerPresentation presentation,
        })
      >[
        (
          name: 'Android fullscreen',
          platform: TargetPlatform.android,
          presentation: VideoPlayerPresentation.fullscreen,
        ),
        (
          name: 'iOS fullscreen',
          platform: TargetPlatform.iOS,
          presentation: VideoPlayerPresentation.fullscreen,
        ),
        (
          name: 'mobile embedded',
          platform: TargetPlatform.iOS,
          presentation: VideoPlayerPresentation.embedded,
        ),
        (
          name: 'mobile picture in picture',
          platform: TargetPlatform.iOS,
          presentation: VideoPlayerPresentation.pictureInPicture,
        ),
        (
          name: 'macOS fullscreen',
          platform: TargetPlatform.macOS,
          presentation: VideoPlayerPresentation.fullscreen,
        ),
        (
          name: 'Windows fullscreen',
          platform: TargetPlatform.windows,
          presentation: VideoPlayerPresentation.fullscreen,
        ),
        (
          name: 'Linux fullscreen',
          platform: TargetPlatform.linux,
          presentation: VideoPlayerPresentation.fullscreen,
        ),
      ];

  for (final surface in cases) {
    testWidgets('${surface.name} uses FVideoPlayer default chrome', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 600);
      final previousPlatform = VideoPlayerPlatform.instance;
      final fakePlatform = _ReusableSurfaceVideoPlatform();
      VideoPlayerPlatform.instance = fakePlatform;
      debugDefaultTargetPlatformOverride = surface.platform;
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
                video: TdFileRef(id: 910, localPath: sourcePath),
                width: 1920,
                height: 1080,
                presentation: surface.presentation,
                currentMode: switch (surface.presentation) {
                  VideoPlayerPresentation.pictureInPicture =>
                    VideoDisplayMode.pictureInPicture,
                  _ => VideoDisplayMode.fullscreen,
                },
                previousVideo: VideoPlaybackItem(video: TdFileRef(id: 909)),
                nextVideo: VideoPlaybackItem(video: TdFileRef(id: 911)),
                onNavigate: (_) {},
                onSwitchMode: (_) {},
                onVolumeChanged: (_) {},
                onClose: () {},
                streamQuery: _completedVideoQuery(sourcePath),
              ),
            ),
          ),
        );
        await _pumpUntilInitialized(tester, fakePlatform);

        final playerFinder = find.byType(FVideoPlayer);
        expect(playerFinder, findsOneWidget);
        final player = tester.widget<FVideoPlayer>(playerFinder);
        expect(player.chromeBuilder, isNull);
        expect(player.interactionMode, FVideoInteractionMode.builtIn);
        expect(player.autofocus, switch (surface.platform) {
          TargetPlatform.linux ||
          TargetPlatform.macOS ||
          TargetPlatform.windows => true,
          _ => false,
        });
        expect(player.showScrubPreview, isTrue);
        expect(player.showPictureInPictureButton, isFalse);
        expect(player.showFullscreenButton, isFalse);
        expect(player.bottomTrailingBuilder, isNotNull);
        expect(
          player.isFullscreen,
          surface.presentation == VideoPlayerPresentation.fullscreen,
        );
        expect(
          player.isPictureInPicture,
          surface.presentation == VideoPlayerPresentation.pictureInPicture,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      }
    });
  }

  testWidgets('default player retains queue and host action adapters', (
    tester,
  ) async {
    final previousPlatform = VideoPlayerPlatform.instance;
    final fakePlatform = _ReusableSurfaceVideoPlatform();
    VideoPlayerPlatform.instance = fakePlatform;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      SharedPreferences.setMockInitialValues(const {});
      final sourcePath = File('pubspec.yaml').absolute.path;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: VideoPlayerView(
            video: TdFileRef(id: 920, localPath: sourcePath),
            previousVideo: VideoPlaybackItem(video: TdFileRef(id: 919)),
            nextVideo: VideoPlaybackItem(video: TdFileRef(id: 921)),
            onNavigate: (_) {},
            onSwitchMode: (_) {},
            onVolumeChanged: (_) {},
            onClose: () {},
            streamQuery: _completedVideoQuery(sourcePath),
          ),
        ),
      );
      await _pumpUntilInitialized(tester, fakePlatform);

      final player = tester.widget<FVideoPlayer>(find.byType(FVideoPlayer));
      expect(player.onPrevious, isNotNull);
      expect(player.onNext, isNotNull);
      expect(player.onVolumeChanged, isNotNull);
      expect(player.onPictureInPictureChanged, isNotNull);
      expect(player.topTrailingBuilder, isNotNull);
      expect(player.bottomTrailingBuilder, isNotNull);
      expect(player.showPictureInPictureButton, isFalse);
      expect(player.showFullscreenButton, isFalse);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      VideoPlayerPlatform.instance = previousPlatform;
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'desktop menus own keyboard navigation without leaking player shortcuts',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 620);
      final previousPlatform = VideoPlayerPlatform.instance;
      final fakePlatform = _ReusableSurfaceVideoPlatform();
      VideoPlayerPlatform.instance = fakePlatform;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      var closeCalls = 0;
      var fullscreenCalls = 0;
      final selectedModes = <VideoDisplayMode>[];
      final reportedVolumes = <double>[];
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
                video: TdFileRef(id: 930, localPath: sourcePath),
                width: 1920,
                height: 1080,
                onClose: () => closeCalls++,
                onToggleFullscreen: () => fullscreenCalls++,
                onSwitchMode: selectedModes.add,
                onVolumeChanged: reportedVolumes.add,
                streamQuery: _completedVideoQuery(sourcePath),
              ),
            ),
          ),
        );
        await _pumpUntilInitialized(tester, fakePlatform);

        final player = tester.widget<FVideoPlayer>(find.byType(FVideoPlayer));
        expect(player.autofocus, isTrue);
        expect(FocusManager.instance.primaryFocus, isNotNull);

        // With no app menu open, the package player retains its shortcuts.
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.pump();
        expect(fullscreenCalls, 1);
        expect(closeCalls, 0);

        await tester.tap(_semanticsWidget('More'));
        await tester.pump(const Duration(milliseconds: 180));
        expect(
          find.byKey(const ValueKey('video-more-menu-surface')),
          findsOneWidget,
        );
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'video-more-menu-action-0',
        );
        final volumeWritesBeforeMenu = reportedVolumes.length;
        final pauseCallsBeforeMenu = fakePlatform.pauseCalls;
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'video-more-menu-action-2',
          reason: 'ArrowUp wraps from the first to the last visible action',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'video-more-menu-action-0',
          reason: 'ArrowDown wraps from the last to the first action',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'video-more-menu-action-1',
        );
        expect(reportedVolumes, hasLength(volumeWritesBeforeMenu));
        expect(fakePlatform.pauseCalls, pauseCallsBeforeMenu);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('video-more-menu-surface')),
          findsNothing,
        );
        expect(closeCalls, 0);
        expect(fullscreenCalls, 1);

        await tester.tap(_semanticsWidget('Switch display mode'));
        await tester.pump(const Duration(milliseconds: 160));
        expect(
          find.byKey(const ValueKey('video-mode-menu-surface')),
          findsOneWidget,
        );
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'video-mode-menu-fullscreen',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'video-mode-menu-pictureInPicture',
          reason: 'ArrowUp wraps from the first to the last mode',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'video-mode-menu-fullscreen',
          reason: 'ArrowDown wraps from the last to the first mode',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('video-mode-menu-surface')),
          findsNothing,
        );
        expect(selectedModes, isEmpty);
        expect(closeCalls, 0);
        expect(fullscreenCalls, 1);

        await tester.tap(_semanticsWidget('Switch display mode'));
        await tester.pump(const Duration(milliseconds: 160));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'video-mode-menu-split',
        );
        expect(reportedVolumes, hasLength(volumeWritesBeforeMenu));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(selectedModes, [VideoDisplayMode.split]);
        expect(
          find.byKey(const ValueKey('video-mode-menu-surface')),
          findsNothing,
        );

        await tester.tap(_semanticsWidget('Switch display mode'));
        await tester.pump(const Duration(milliseconds: 160));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(selectedModes, [VideoDisplayMode.split, VideoDisplayMode.split]);
        expect(closeCalls, 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      }
    },
  );
}

Finder _semanticsWidget(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

Future<void> _pumpUntilInitialized(
  WidgetTester tester,
  _ReusableSurfaceVideoPlatform platform,
) async {
  for (
    var attempt = 0;
    attempt < 40 && platform.initializedEvents == 0;
    attempt++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
}

TdVideoStreamQuery _completedVideoQuery(String path) => (request) async {
  if (request['@type'] != 'getFile') {
    throw UnsupportedError('Unexpected TDLib query ${request['@type']}');
  }
  final length = await File(path).length();
  return {
    '@type': 'file',
    'id': request['file_id'],
    'size': length,
    'expected_size': length,
    'local': {
      '@type': 'localFile',
      'path': path,
      'download_offset': 0,
      'downloaded_prefix_size': length,
      'downloaded_size': length,
      'is_downloading_active': false,
      'is_downloading_completed': true,
    },
  };
};

class _ReusableSurfaceVideoPlatform extends VideoPlayerPlatform {
  final Map<int, StreamController<VideoEvent>> _events = {};
  var _nextPlayerId = 1;
  var initializedEvents = 0;
  var pauseCalls = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final playerId = _nextPlayerId++;
    // Ownership transfers to the fake platform and dispose() closes it.
    // ignore: close_sinks
    _events[playerId] = StreamController<VideoEvent>.broadcast();
    return playerId;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    final stream = _events[playerId]!.stream;
    scheduleMicrotask(() {
      // The platform fake owns and closes this controller in dispose().
      // ignore: close_sinks
      final controller = _events[playerId];
      if (controller == null) return;
      if (controller.isClosed) return;
      initializedEvents++;
      controller.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(minutes: 2),
          size: const Size(1920, 1080),
        ),
      );
    });
    return stream;
  }

  @override
  Future<void> dispose(int playerId) async {
    await _events.remove(playerId)?.close();
  }

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {
    pauseCalls++;
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand(key: ValueKey('reusable-video-surface'));
}
