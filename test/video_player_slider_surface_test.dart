import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the redesigned app timeline reuses package slider behavior', () {
    final appSource = File(
      'lib/chat/video_player_view.dart',
    ).readAsStringSync();
    expect(appSource, contains("package:f_videoplayer/f_videoplayer.dart"));
    expect(appSource, contains('FVideoPlayer('));
    expect(appSource, contains('MithkaDesktopVideoChrome'));
    expect(appSource, contains('FVideoSlider('));
    expect(appSource, contains('scope.actions.beginScrub('));
    expect(appSource, contains('scope.actions.endScrub('));
    expect(appSource, isNot(contains('Widget _scrubber(')));
    expect(
      appSource,
      isNot(matches(RegExp(r'\b(?:Slider|CupertinoSlider)\('))),
    );
  });

  test('standalone story and video-note controls reuse FVideoSlider', () {
    final storySource = File(
      'lib/moments/story_viewer_view.dart',
    ).readAsStringSync();
    final videoNoteSource = File(
      'lib/chat/video_note_preview_view.dart',
    ).readAsStringSync();
    expect(storySource, contains("ValueKey('storyVolumeSlider')"));
    expect(storySource, contains('FVideoSlider('));
    expect(videoNoteSource, contains("ValueKey('videoNoteVolumeSlider')"));
    expect(videoNoteSource, contains('FVideoSlider('));
    expect(<String>[
      storySource,
      videoNoteSource,
    ], everyElement(isNot(matches(RegExp(r'\b(?:Icons|CupertinoIcons)\.')))));
  });
}
