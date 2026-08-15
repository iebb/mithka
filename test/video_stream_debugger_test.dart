import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/video_stream_debugger.dart';
import 'package:mithka/tdlib/td_image_loader.dart';

void main() {
  const mebibyte = videoDownloadMinimumBlockBytes;

  test('each block is at least one MiB and stays within the measured grid', () {
    final layout = videoDownloadBlockLayout(
      totalBytes: 512 * mebibyte,
      downloadedBytes: 147 * mebibyte,
      prefixDownloadedBytes: 96 * mebibyte,
      completed: false,
      maxWidth: 350,
      maxHeight: 150,
    );

    expect(layout.blockSizeBytes, greaterThanOrEqualTo(mebibyte));
    expect(layout.blockSizeBytes % mebibyte, 0);
    expect(layout.blocks.length, lessThanOrEqualTo(layout.capacity));
    expect(layout.width, lessThanOrEqualTo(350.001));
    expect(layout.height, lessThanOrEqualTo(150.001));
  });

  test('large videos scale the represented bytes instead of overflowing', () {
    final layout = videoDownloadBlockLayout(
      totalBytes: 64 * 1024 * mebibyte,
      downloadedBytes: 8 * 1024 * mebibyte,
      prefixDownloadedBytes: 4 * 1024 * mebibyte,
      completed: false,
      maxWidth: 360,
      maxHeight: 160,
    );

    expect(layout.blockSizeBytes, greaterThan(mebibyte));
    expect(layout.width, lessThanOrEqualTo(360.001));
    expect(layout.height, lessThanOrEqualTo(160.001));
    expect(layout.blocks.length, lessThanOrEqualTo(layout.capacity));
  });

  test('unknown size does not imply a downloaded block', () {
    final layout = videoDownloadBlockLayout(
      totalBytes: 0,
      downloadedBytes: 0,
      prefixDownloadedBytes: 0,
      completed: false,
      maxWidth: 320,
      maxHeight: 120,
    );

    expect(layout.blockSizeBytes, videoDownloadMinimumBlockBytes);
    expect(layout.blocks, isEmpty);
    expect(layout.width, lessThanOrEqualTo(320.001));
    expect(layout.height, lessThanOrEqualTo(120.001));
  });

  test(
    'download blocks expose downloaded, partial, and undownloaded states',
    () {
      expect(
        videoDownloadBlockState(
          start: 0,
          end: mebibyte,
          downloadedBytes: mebibyte,
          prefixDownloadedBytes: mebibyte,
          completed: false,
        ),
        VideoDownloadBlockState.downloaded,
      );
      expect(
        videoDownloadBlockState(
          start: mebibyte,
          end: 2 * mebibyte,
          downloadedBytes: mebibyte + 1,
          prefixDownloadedBytes: mebibyte,
          completed: false,
        ),
        VideoDownloadBlockState.partiallyDownloaded,
      );
      expect(
        videoDownloadBlockState(
          start: 2 * mebibyte,
          end: 3 * mebibyte,
          downloadedBytes: mebibyte + 1,
          prefixDownloadedBytes: mebibyte,
          completed: false,
        ),
        VideoDownloadBlockState.undownloaded,
      );
    },
  );

  testWidgets('the inspector keeps a large cache map inside a narrow panel', (
    tester,
  ) async {
    var recording = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 390,
              height: 520,
              child: VideoStreamDebugger(
                progress: const TdFileProgress(
                  fileId: 42,
                  downloaded: 147 * mebibyte,
                  prefixDownloaded: 96 * mebibyte,
                  total: 512 * mebibyte,
                  isActive: true,
                  isCompleted: false,
                ),
                position: const Duration(seconds: 2),
                duration: const Duration(seconds: 4),
                events: const ['download started'],
                isLive: true,
                isRecording: recording,
                onRecordingChanged: (value) => recording = value,
                onClear: () {},
                onExport: () {},
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Stream Inspector'), findsOneWidget);
    expect(find.text('Stream cache'), findsOneWidget);
    expect(find.byKey(const ValueKey('video-debug-block-0')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
