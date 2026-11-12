import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/video_player_view.dart';
import 'package:video_player/video_player.dart';

void main() {
  group('isStoppedVideoPlaybackComplete', () {
    const duration = Duration(minutes: 1);

    VideoPlayerValue value({required Duration position}) => VideoPlayerValue(
      duration: duration,
      size: const Size(1920, 1080),
      isInitialized: true,
      position: position,
    );

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
  });
}
