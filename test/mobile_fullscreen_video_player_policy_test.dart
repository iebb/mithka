import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/video_player_view.dart';
import 'package:video_player/video_player.dart';

void main() {
  final appPlayerSource = File(
    'lib/chat/video_player_view.dart',
  ).readAsStringSync();
  final desktopPlayerSource = File(
    'lib/app/desktop_video_window.dart',
  ).readAsStringSync();

  group('reusable video-player architecture', () {
    test('all app presentations share one FVideoPlayer path', () {
      expect(
        appPlayerSource,
        contains("package:f_videoplayer/f_videoplayer.dart"),
      );
      expect(
        RegExp(r'\bFVideoPlayer\(').allMatches(appPlayerSource),
        hasLength(1),
        reason:
            'fullscreen, embedded, PiP, mobile, web, and desktop must select '
            'one reusable player instead of parallel widget trees',
      );
      expect(appPlayerSource, isNot(matches(RegExp(r'\bVideoPlayer\('))));
      expect(appPlayerSource, isNot(contains('_legacyPlayer(')));
      expect(
        appPlayerSource,
        isNot(contains('usesReusableMobileFullscreenPlayer')),
      );
    });

    test('app player uses package default chrome', () {
      expect(appPlayerSource, isNot(contains('chromeBuilder:')));
      expect(
        appPlayerSource,
        isNot(contains('FVideoInteractionMode.delegateToChrome')),
      );
      expect(appPlayerSource, isNot(contains('_mobileFullscreenChrome(')));
      expect(appPlayerSource, isNot(contains('List<Widget> _controls(')));
      expect(appPlayerSource, isNot(contains('Widget _transportControls(')));
      expect(appPlayerSource, isNot(contains('Widget _scrubber(')));
    });

    test('host adapters remain connected to the reusable player', () {
      expect(appPlayerSource, contains('TdVideoStreamServer('));
      expect(appPlayerSource, contains('_recoverFromCompletedFile('));
      expect(appPlayerSource, contains('controller: controller'));
      expect(appPlayerSource, contains('onPrevious:'));
      expect(appPlayerSource, contains('onNext:'));
      expect(appPlayerSource, contains('onVolumeChanged:'));
      expect(appPlayerSource, contains('onPictureInPictureChanged:'));
      expect(appPlayerSource, contains('autofocus: _isDesktopPlatform'));
      expect(appPlayerSource, contains('surfaceInteractionBuilder:'));
      expect(appPlayerSource, contains('overlayBuilder:'));
      expect(appPlayerSource, contains('topTrailingBuilder:'));
      expect(appPlayerSource, contains('bottomTrailingBuilder:'));
      expect(appPlayerSource, contains('FVideoPlayerLabels('));
      expect(appPlayerSource, contains('loadingBuilder:'));
      expect(appPlayerSource, contains('onError:'));
    });

    test('desktop child windows also use package default chrome', () {
      expect(
        desktopPlayerSource,
        contains("package:f_videoplayer/f_videoplayer.dart"),
      );
      expect(
        RegExp(r'\bFVideoPlayer\(').allMatches(desktopPlayerSource),
        hasLength(1),
      );
      expect(desktopPlayerSource, isNot(matches(RegExp(r'\bVideoPlayer\('))));
      expect(desktopPlayerSource, isNot(contains('chromeBuilder:')));
      expect(
        desktopPlayerSource,
        isNot(contains('FVideoInteractionMode.delegateToChrome')),
      );
      expect(desktopPlayerSource, contains('onPictureInPictureChanged:'));
      expect(desktopPlayerSource, contains('onFullscreenChanged:'));
    });
  });

  group('isStoppedVideoPlaybackComplete', () {
    const duration = Duration(minutes: 1);

    VideoPlayerValue value({
      bool isInitialized = true,
      bool isPlaying = false,
      bool isCompleted = false,
      Duration position = Duration.zero,
    }) => VideoPlayerValue(
      duration: duration,
      size: const Size(1920, 1080),
      isInitialized: isInitialized,
      isPlaying: isPlaying,
      isCompleted: isCompleted,
      position: position,
    );

    test('does not complete while playback is still running', () {
      expect(
        isStoppedVideoPlaybackComplete(
          value(isPlaying: true, isCompleted: true, position: duration),
        ),
        isFalse,
      );
    });

    test('completes when stopped with the completed flag', () {
      expect(isStoppedVideoPlaybackComplete(value(isCompleted: true)), isTrue);
    });

    test('completes when stopped at the duration without the flag', () {
      expect(isStoppedVideoPlaybackComplete(value(position: duration)), isTrue);
    });

    test('does not complete when paused before the duration', () {
      expect(
        isStoppedVideoPlaybackComplete(
          value(position: const Duration(seconds: 59)),
        ),
        isFalse,
      );
    });

    test('does not complete before initialization', () {
      expect(
        isStoppedVideoPlaybackComplete(
          value(isInitialized: false, isCompleted: true, position: duration),
        ),
        isFalse,
      );
    });
  });
}
