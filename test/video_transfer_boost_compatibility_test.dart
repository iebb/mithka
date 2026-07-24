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

  test('video playback primes a bounded range before starting the server', () {
    final start = section('Future<Uri?> start()', 'Future<void> close()');

    expect(start, contains('_primePlaybackRange(0, _chunkSize)'));
    expect(start, isNot(contains('_startContinuousDownload(0)')));
  });

  test('playback range changes do not restart an unlimited download', () {
    final ensureRange = section(
      'Future<bool> _ensureRange',
      'Future<Map<String, dynamic>?> _downloadPlaybackRange',
    );

    expect(ensureRange, contains('_primePlaybackRange(start, length)'));
    expect(ensureRange, isNot(contains('_startContinuousDownload')));
  });

  test('native file handoff can still finish downloading in background', () {
    final backgroundDownload = section(
      'void startBackgroundDownload()',
      'void _updateFileInfo',
    );

    expect(backgroundDownload, contains('_startContinuousDownload(0)'));
  });
}
