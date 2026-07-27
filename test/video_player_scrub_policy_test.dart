import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/chat/video_player_view.dart').readAsStringSync();

  String section(String start, String end) {
    final startIndex = source.indexOf(start);
    final endIndex = source.indexOf(end, startIndex + start.length);
    expect(startIndex, isNonNegative, reason: 'Missing section start: $start');
    expect(
      endIndex,
      greaterThan(startIndex),
      reason: 'Missing section end: $end',
    );
    return source.substring(startIndex, endIndex);
  }

  test('drag updates preview state without seeking the controller', () {
    final scrubber = section('Widget _scrubber(', 'Duration _displayPosition(');
    final update = section('void _updateScrub(', 'Future<void> _finishScrub(');

    expect(scrubber, contains('onChanged:'));
    expect(scrubber, contains('_updateScrub(fraction * duration)'));
    expect(update, contains('_scrubPosition = position'));
    expect(update, contains('_queueScrubPreview(position)'));
    expect(update, isNot(contains('seekTo(')));
  });

  test('scrub end commits exactly one seek after the pause completes', () {
    final scrubber = section('Widget _scrubber(', 'Duration _displayPosition(');
    final finish = section(
      'Future<void> _finishScrub(',
      'void _queueScrubPreview(',
    );

    expect(scrubber, contains('onChangeEnd:'));
    expect(scrubber, contains('_finishScrub(c, fraction * duration)'));
    expect(finish, contains('await _scrubPause'));
    expect(finish, contains('await controller.seekTo(position)'));
    expect(RegExp(r'controller\.seekTo\(').allMatches(finish), hasLength(1));
  });

  test('thumbnail timeout clears loading and drains the pending preview', () {
    final drain = section(
      'Future<void> _drainScrubPreviewQueue()',
      'void _showScrubPreviewOverlay()',
    );

    expect(
      drain,
      contains('.timeout(const Duration(seconds: 2), onTimeout: () => null)'),
    );
    expect(drain, contains('finally {\n      _scrubPreviewLoading = false;'));
    expect(drain, contains('_scrubPreviewOverlay?.markNeedsBuild()'));
    expect(drain, contains('if (_pendingScrubPreviewPosition != null)'));
    expect(drain, contains('unawaited(_drainScrubPreviewQueue())'));
  });
}
