import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/chat/video_player_view.dart').readAsStringSync();

  test('package default chrome owns scrub state, seeking, and previews', () {
    expect(source, contains('FVideoPlayer('));
    expect(source, isNot(contains('showScrubPreview: false')));
    expect(source, isNot(contains('Widget _scrubber(')));
    expect(source, isNot(contains('void _beginScrub(')));
    expect(source, isNot(contains('void _updateScrub(')));
    expect(source, isNot(contains('Future<void> _finishScrub(')));
    expect(source, isNot(contains('void _queueScrubPreview(')));
    expect(source, isNot(contains('_scrubPreviewOverlay')));
  });

  test('removing app scrub chrome does not remove TDLib recovery', () {
    expect(source, contains('TdVideoStreamServer('));
    expect(source, contains('_recoverFromCompletedFile('));
    expect(source, contains('_recoverStreamingPlayback('));
  });
}
