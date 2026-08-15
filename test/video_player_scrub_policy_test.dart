import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/chat/video_player_view.dart').readAsStringSync();

  test('redesigned chrome delegates scrub actions to the player package', () {
    expect(source, contains('FVideoPlayer('));
    expect(source, contains('MithkaDesktopVideoChrome'));
    expect(source, contains('FVideoChromeScope'));
    expect(source, contains('scope.actions.beginScrub('));
    expect(source, contains('scope.actions.updateScrub('));
    expect(source, contains('scope.actions.endScrub('));
    expect(source, isNot(contains('Widget _scrubber(')));
    expect(source, isNot(contains('Future<void> _finishScrub(')));
    expect(source, isNot(contains('_scrubPreviewOverlay')));
    expect(source, isNot(contains('Overlay.of(scrubberContext)')));
  });

  test('custom scrub chrome does not remove TDLib recovery', () {
    expect(source, contains('TdVideoStreamServer('));
    expect(source, contains('_recoverFromCompletedFile('));
    expect(source, contains('_recoverStreamingPlayback('));
  });
}
