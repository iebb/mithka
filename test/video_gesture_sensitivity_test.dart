import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final playerSource = File(
    'lib/chat/video_player_view.dart',
  ).readAsStringSync();
  final preferencesSource = File(
    'lib/chat/video_playback_preferences.dart',
  ).readAsStringSync();

  test('gesture preferences remain a host adapter on the package surface', () {
    expect(preferencesSource, contains('VideoHorizontalSwipeAction'));
    expect(preferencesSource, contains('VideoVerticalSwipeAction'));
    expect(playerSource, contains('VideoPlaybackPreferences'));
    expect(playerSource, contains('horizontalSwipeAction'));
    expect(playerSource, contains('leftVerticalSwipeAction'));
    expect(playerSource, contains('rightVerticalSwipeAction'));
    expect(playerSource, contains('surfaceInteractionBuilder:'));
    expect(playerSource, contains('_playerSurfaceInteraction'));
    expect(playerSource, contains('const _verticalGestureSensitivity = 0.5;'));
    expect(
      RegExp(
        r'delta\.dy / size\.height \* _verticalGestureSensitivity',
      ).allMatches(playerSource),
      hasLength(2),
    );
    expect(
      playerSource,
      contains(
        'chromeBuilder: widget.presentation == '
        'VideoPlayerPresentation.fullscreen',
      ),
    );
    expect(playerSource, contains('? _playerChrome'));
    expect(
      playerSource,
      isNot(contains('FVideoInteractionMode.delegateToChrome')),
    );
  });
}
