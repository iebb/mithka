import 'dart:io';

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
    expect(layout.blocks.length, lessThanOrEqualTo(layout.capacity));
    expect(layout.blocks.length, lessThanOrEqualTo(videoDownloadMaximumBlocks));
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
    expect(layout.blocks.length, lessThanOrEqualTo(videoDownloadMaximumBlocks));
  });

  test('a large cache pane can use more than 100 blocks', () {
    final layout = videoDownloadBlockLayout(
      totalBytes: 2048 * mebibyte,
      downloadedBytes: 640 * mebibyte,
      prefixDownloadedBytes: 512 * mebibyte,
      completed: false,
      maxWidth: 1200,
      maxHeight: 420,
    );

    expect(layout.blocks.length, greaterThan(100));
    expect(layout.blocks.length, lessThanOrEqualTo(layout.capacity));
    expect(layout.blocks.length, lessThanOrEqualTo(videoDownloadMaximumBlocks));
    expect(layout.width, lessThanOrEqualTo(1200.001));
    expect(layout.height, lessThanOrEqualTo(420.001));
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

  test('sought chunks stay at their non-contiguous byte offsets', () {
    final layout = videoDownloadBlockLayout(
      totalBytes: 200 * mebibyte,
      downloadedBytes: 16 * mebibyte,
      prefixDownloadedBytes: 4 * mebibyte,
      completed: false,
      downloadedRanges: const <TdFileByteRange>[
        TdFileByteRange(start: 0, end: 4 * mebibyte),
        TdFileByteRange(
          start: 100 * mebibyte + 512 * 1024,
          end: 112 * mebibyte,
        ),
      ],
      maxWidth: 800,
      maxHeight: 300,
    );

    expect(layout.blockSizeBytes, mebibyte);
    expect(layout.blocks[3].state, VideoDownloadBlockState.downloaded);
    expect(layout.blocks[4].state, VideoDownloadBlockState.undownloaded);
    expect(layout.blocks[50].state, VideoDownloadBlockState.undownloaded);
    expect(
      layout.blocks[100].state,
      VideoDownloadBlockState.partiallyDownloaded,
    );
    expect(layout.blocks[101].state, VideoDownloadBlockState.downloaded);
    expect(layout.blocks[111].state, VideoDownloadBlockState.downloaded);
    expect(layout.blocks[112].state, VideoDownloadBlockState.undownloaded);
  });

  testWidgets('the inspector keeps a large cache map inside a narrow panel', (
    tester,
  ) async {
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
                viewportSize: const Size(1280, 720),
                videoSize: const Size(1920, 1080),
                volume: 0.72,
                playbackSpeed: 1.25,
                bufferedAhead: const Duration(milliseconds: 4250),
                downloadBytesPerSecond: 2.5 * 1024 * 1024,
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Stream Inspector'), findsOneWidget);
    expect(find.text('Stats for nerds'), findsNothing);
    expect(find.text('Stream cache'), findsOneWidget);
    expect(find.text('DEBUG'), findsNothing);
    expect(find.text('NETWORK'), findsNothing);
    expect(find.text('CACHE'), findsNothing);
    expect(find.text('RECORD'), findsNothing);
    expect(find.text('CLEAR'), findsNothing);
    expect(find.text('EXPORT'), findsNothing);
    expect(find.bySemanticsLabel('Close'), findsOneWidget);
    expect(find.byKey(const ValueKey('video-debug-block-0')), findsOneWidget);
    final inspectorTextStyle = DefaultTextStyle.of(
      tester.element(find.text('Stream Inspector')),
    ).style;
    expect(inspectorTextStyle.fontFamily, '.AppleSystemUIFont');
    expect(
      inspectorTextStyle.fontFamilyFallback,
      containsAll(<String>['Roboto', 'Segoe UI', 'Noto Sans']),
    );
    expect(inspectorTextStyle.letterSpacing, 0);
    final inspectorRect = tester.getRect(find.byType(VideoStreamDebugger));
    final closeRect = tester.getRect(find.bySemanticsLabel('Close'));
    expect(closeRect.right, closeTo(inspectorRect.right - 10, 0.01));
    final cacheHeaderRect = tester.getRect(
      find.byKey(const ValueKey('video-debug-panel-header-Stream cache')),
    );
    final cacheSummaryRect = tester.getRect(
      find.byKey(const ValueKey('video-debug-panel-trailing-Stream cache')),
    );
    expect(cacheSummaryRect.right, closeTo(cacheHeaderRect.right, 0.01));
    final source = File(
      'lib/chat/video_stream_debugger.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('layout.width * playhead')));
    expect(source, isNot(contains('per chunk')));
    expect(source, isNot(contains("fontFamily: 'monospace'")));
    expect(tester.takeException(), isNull);
  });

  testWidgets('toggling the inspector keeps the player state mounted', (
    tester,
  ) async {
    var initializations = 0;
    var disposals = 0;

    Widget subject(bool visible) {
      return MaterialApp(
        home: SizedBox(
          width: 960,
          height: 540,
          child: VideoStreamDebuggerOverlay(
            visible: visible,
            player: _LifecycleProbe(
              key: const ValueKey('stable-video-player'),
              onInitialize: () => initializations++,
              onDispose: () => disposals++,
            ),
            inspectorBuilder: (_, _) => const ColoredBox(
              key: ValueKey('stream-inspector-overlay'),
              color: Colors.black,
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(subject(false));
    expect(initializations, 1);
    expect(disposals, 0);

    await tester.pumpWidget(subject(true));
    await tester.pump();
    expect(find.byKey(const ValueKey('stream-inspector-overlay')), findsOne);
    expect(initializations, 1);
    expect(disposals, 0);

    await tester.pumpWidget(subject(false));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('stream-inspector-overlay')),
      findsNothing,
    );
    expect(initializations, 1);
    expect(disposals, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(disposals, 1);
  });
}

class _LifecycleProbe extends StatefulWidget {
  const _LifecycleProbe({
    super.key,
    required this.onInitialize,
    required this.onDispose,
  });

  final VoidCallback onInitialize;
  final VoidCallback onDispose;

  @override
  State<_LifecycleProbe> createState() => _LifecycleProbeState();
}

class _LifecycleProbeState extends State<_LifecycleProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInitialize();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black);
}
