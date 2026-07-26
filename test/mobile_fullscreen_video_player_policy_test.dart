import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/video_player_view.dart';
import 'package:video_player/video_player.dart';

void main() {
  group('usesReusableMobileFullscreenPlayer', () {
    test('enables the reusable player for Android and iOS fullscreen', () {
      for (final platform in const [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ]) {
        expect(
          usesReusableMobileFullscreenPlayer(
            presentation: VideoPlayerPresentation.fullscreen,
            platform: platform,
          ),
          isTrue,
          reason: '$platform fullscreen should use the reusable player',
        );
      }
    });

    test('keeps Android and iOS embedded and PiP on the legacy player', () {
      for (final platform in const [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ]) {
        for (final presentation in const [
          VideoPlayerPresentation.embedded,
          VideoPlayerPresentation.pictureInPicture,
        ]) {
          expect(
            usesReusableMobileFullscreenPlayer(
              presentation: presentation,
              platform: platform,
            ),
            isFalse,
            reason: '$platform $presentation must remain on the legacy player',
          );
        }
      }
    });

    test('keeps desktop fullscreen on the existing platform paths', () {
      for (final platform in const [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(
          usesReusableMobileFullscreenPlayer(
            presentation: VideoPlayerPresentation.fullscreen,
            platform: platform,
          ),
          isFalse,
          reason: '$platform fullscreen must not use the mobile migration',
        );
      }
    });

    test('web always stays outside the mobile fullscreen migration', () {
      expect(
        usesReusableMobileFullscreenPlayer(
          presentation: VideoPlayerPresentation.fullscreen,
          platform: TargetPlatform.android,
          isWeb: true,
        ),
        isFalse,
      );
      expect(
        usesReusableMobileFullscreenPlayer(
          presentation: VideoPlayerPresentation.fullscreen,
          platform: TargetPlatform.iOS,
          isWeb: true,
        ),
        isFalse,
        reason: 'the web override must win even when the platform reports iOS',
      );
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
