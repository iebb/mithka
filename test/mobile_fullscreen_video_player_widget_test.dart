import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/video_playback_queue.dart';
import 'package:mithka/chat/video_player_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka_video_player/mithka_video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Used only to install a deterministic fake for the public video_player API.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'iPhone portrait fullscreen keeps controls usable and commits scrubs on release',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
        tester.view.resetPadding();
        tester.view.resetViewPadding();
      });

      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeMobileVideoPlatform();
      VideoPlayerPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        SharedPreferences.setMockInitialValues(const {});

        final sourcePath = File('pubspec.yaml').absolute.path;
        var previousCalls = 0;
        var nextCalls = 0;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: VideoPlayerView(
                video: TdFileRef(id: 700, localPath: sourcePath),
                width: 1920,
                height: 1080,
                sourceChatId: 1,
                messageId: 700,
                previousVideo: VideoPlaybackItem(
                  video: TdFileRef(id: 699),
                  title: 'Previous',
                ),
                nextVideo: VideoPlaybackItem(
                  video: TdFileRef(id: 701),
                  title: 'Next',
                ),
                onNavigate: (delta) {
                  if (delta < 0) {
                    previousCalls++;
                  } else {
                    nextCalls++;
                  }
                },
                onSwitchMode: (_) {},
                onClose: () {},
                streamQuery: _completedVideoQuery(sourcePath, fileId: 700),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );

        for (
          var attempt = 0;
          attempt < 40 && find.byType(MithkaVideoPlayer).evaluate().isEmpty;
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 25));
        }
        expect(tester.takeException(), isNull);
        expect(File(sourcePath).existsSync(), isTrue);
        expect(find.byType(VideoPlayerView), findsOneWidget);
        expect(platform.createCalls, 1);
        expect(
          platform.creationOptions.single.dataSource.sourceType,
          DataSourceType.file,
        );
        expect(
          platform.creationOptions.single.dataSource.uri,
          Uri.file(sourcePath).toString(),
        );
        expect(platform.initializedEvents, 1);
        expect(find.byType(MithkaVideoPlayer), findsOneWidget);
        expect(_timeline, findsOneWidget);

        expect(tester.takeException(), isNull);
        final playerRect = tester.getRect(find.byType(MithkaVideoPlayer));
        final reusablePlayer = tester.widget<MithkaVideoPlayer>(
          find.byType(MithkaVideoPlayer),
        );
        final surfaceRect = tester.getRect(
          find.byKey(const ValueKey('fake-mobile-video-surface')),
        );
        final closeRect = tester.getRect(_semanticsWidget('Close'));
        final moreRect = tester.getRect(_semanticsWidget('More'));
        final timelineRect = tester.getRect(_timeline);
        final previousRect = tester.getRect(_semanticsWidget('Previous video'));
        final pauseRect = tester.getRect(_semanticsWidget('Pause'));
        final nextRect = tester.getRect(_semanticsWidget('Next video'));

        expect(playerRect, const Rect.fromLTWH(0, 0, 390, 844));
        expect(reusablePlayer.alignment, Alignment.center);
        expect(surfaceRect.width, closeTo(390, 0.01));
        expect(surfaceRect.height, closeTo(390 * 9 / 16, 0.01));
        expect(surfaceRect.center.dx, closeTo(playerRect.center.dx, 0.01));
        expect(surfaceRect.center.dy, closeTo(playerRect.center.dy, 0.01));
        expect(closeRect.top, greaterThanOrEqualTo(47));
        expect(moreRect, const Rect.fromLTWH(338, 53, 44, 44));
        expect(timelineRect.bottom, lessThanOrEqualTo(844 - 34));
        expect(playerRect.contains(timelineRect.bottomLeft), isTrue);
        expect(playerRect.contains(previousRect.topLeft), isTrue);
        expect(playerRect.contains(nextRect.bottomRight), isTrue);
        expect(previousRect.right, lessThanOrEqualTo(pauseRect.left));
        expect(pauseRect.right, lessThanOrEqualTo(nextRect.left));

        await tester.tap(_semanticsWidget('More'));
        await tester.pump();
        expect(tester.takeException(), isNull);
        final download = find.byKey(const ValueKey('video-more-download'));
        final saveToPhotos = find.byKey(
          const ValueKey('video-more-save-to-photos'),
        );
        final share = find.byKey(const ValueKey('video-more-share'));
        expect(download, findsOneWidget);
        expect(saveToPhotos, findsOneWidget);
        expect(share, findsOneWidget);
        expect(
          find.descendant(of: download, matching: find.text('Download')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: saveToPhotos,
            matching: find.text('Save to Photos'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: share, matching: find.text('Share')),
          findsOneWidget,
        );
        final downloadRect = tester.getRect(download);
        final saveRect = tester.getRect(saveToPhotos);
        final shareRect = tester.getRect(share);
        expect(downloadRect.top, greaterThanOrEqualTo(47 + 56 + 8));
        expect(downloadRect.right, lessThanOrEqualTo(390 - 10 - 8));
        expect(downloadRect.left, greaterThanOrEqualTo(8));
        expect(downloadRect.bottom, lessThanOrEqualTo(saveRect.top));
        expect(saveRect.bottom, lessThanOrEqualTo(shareRect.top));
        expect(shareRect.bottom, lessThanOrEqualTo(844 - 34));
        await tester.tapAt(const Offset(20, 200));
        await tester.pump();
        expect(download, findsNothing);
        expect(saveToPhotos, findsNothing);
        expect(share, findsNothing);

        await tester.tap(_semanticsWidget('Previous video'));
        await tester.tap(_semanticsWidget('Next video'));
        expect(previousCalls, 1);
        expect(nextCalls, 1);

        final pauseCalls = platform.pauseCalls;
        await tester.tap(_semanticsWidget('Pause'));
        await tester.pump();
        expect(platform.pauseCalls, pauseCalls + 1);
        expect(_semanticsWidget('Play'), findsOneWidget);

        final playCalls = platform.playCalls;
        await tester.tap(_semanticsWidget('Play'));
        await tester.pump();
        expect(platform.playCalls, playCalls + 1);

        await tester.tapAt(timelineRect.center);
        await tester.pump();
        expect(
          platform.seekPositions.last,
          closeToDuration(const Duration(minutes: 1)),
        );
        // Keep playback paused while scrubbing so a seek to the exact end is
        // not followed by video_player's intentional replay-from-zero seek.
        await tester.tap(_semanticsWidget('Pause'));
        await tester.pump();
        expect(_semanticsWidget('Play'), findsOneWidget);

        for (final fraction in const [0.0, 0.5, 1.0]) {
          final seeksBeforeDrag = platform.seekPositions.length;
          final currentTimeline = tester.getRect(_timeline);
          final target = Offset(
            currentTimeline.left + 5 + (currentTimeline.width - 10) * fraction,
            currentTimeline.center.dy,
          );
          final start = Offset(
            target.dx + (fraction == 0 ? 26 : -26),
            target.dy,
          );
          final gesture = await tester.startGesture(start);
          await gesture.moveTo(target);
          await tester.pump();

          expect(
            platform.seekPositions,
            hasLength(seeksBeforeDrag),
            reason: 'pointer movement must only update the preview position',
          );
          expect(_compactScrubPreview, findsOneWidget);
          final previewRect = tester.getRect(_compactScrubPreview);
          final expectedLeft =
              (currentTimeline.left + currentTimeline.width * fraction - 64)
                  .clamp(8.0, 390.0 - 128 - 8)
                  .toDouble();
          expect(previewRect.left, closeTo(expectedLeft, 0.01));
          expect(previewRect.right, lessThanOrEqualTo(390 - 8));
          expect(previewRect.top, greaterThanOrEqualTo(47));
          expect(previewRect.bottom, lessThan(currentTimeline.top));
          expect(
            find.descendant(
              of: _compactScrubPreview,
              matching: find.text(
                fraction == 0
                    ? '00:00'
                    : fraction == 0.5
                    ? '01:00'
                    : '02:00',
              ),
            ),
            findsOneWidget,
          );

          await gesture.up();
          await _pumpUntilPreviewGone(tester);
          expect(platform.seekPositions, hasLength(seeksBeforeDrag + 1));
          expect(
            platform.seekPositions.last,
            closeToDuration(
              Duration(
                milliseconds:
                    (_FakeMobileVideoPlatform.duration.inMilliseconds *
                            fraction)
                        .round(),
              ),
            ),
          );
          expect(_compactScrubPreview, findsNothing);
        }

        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        for (
          var attempt = 0;
          attempt < 40 && platform.disposeCalls == 0;
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(platform.disposeCalls, 1);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('iOS sparse files retain the loopback network controller', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    late Directory directory;
    late File sparseFile;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp(
        'mithka-sparse-video-test-',
      );
      sparseFile = File('${directory.path}/sparse.mp4');
      final handle = await sparseFile.open(mode: FileMode.write);
      await handle.writeFrom(List<int>.generate(64, (index) => index));
      await handle.truncate(1024 * 1024);
      await handle.close();
    });

    final query = _SparseVideoQuery(
      fileId: 702,
      path: sparseFile.path,
      totalBytes: 1024 * 1024,
      downloadedBytes: 64,
    );
    final previousPlatform = VideoPlayerPlatform.instance;
    final platform = _FakeMobileVideoPlatform();
    VideoPlayerPlatform.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      SharedPreferences.setMockInitialValues(const {});
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: VideoPlayerView(
              video: TdFileRef(id: 702, localPath: sparseFile.path),
              width: 1920,
              height: 1080,
              onClose: () {},
              streamQuery: query.call,
            ),
          ),
        ),
      );
      await _pumpUntilPlayerReady(tester);

      expect(tester.takeException(), isNull);
      expect(platform.creationOptions, hasLength(1));
      final dataSource = platform.creationOptions.single.dataSource;
      expect(dataSource.sourceType, DataSourceType.network);
      final sourceUri = Uri.parse(dataSource.uri!);
      expect(sourceUri.scheme, 'http');
      expect(sourceUri.host, InternetAddress.loopbackIPv4.address);
      expect(sourceUri.path, '/video/702.mp4');
      expect(dataSource.uri, isNot(contains(sparseFile.path)));

      final reusablePlayer = tester.widget<MithkaVideoPlayer>(
        find.byType(MithkaVideoPlayer),
      );
      expect(reusablePlayer.source.kind, MithkaVideoSourceKind.network);
      expect(reusablePlayer.source.location, dataSource.uri);
      expect(
        query.requests.where((request) => request['@type'] == 'getFile'),
        isNotEmpty,
      );
      expect(
        query.requests.where(
          (request) =>
              request['@type'] == 'downloadFile' && request['limit'] == 0,
        ),
        isNotEmpty,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpUntilDisposed(tester, platform);
      expect(platform.disposeCalls, 1);
    } finally {
      VideoPlayerPlatform.instance = previousPlatform;
      debugDefaultTargetPlatformOverride = null;
      await tester.runAsync(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
    }
  });

  testWidgets('app scrub preview recovers after a thumbnail timeout', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.view.resetPadding();
      tester.view.resetViewPadding();
    });

    const thumbnailChannel = MethodChannel('fc_native_video_thumbnail');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final firstThumbnail = Completer<Object?>();
    var thumbnailRequests = 0;
    messenger.setMockMethodCallHandler(thumbnailChannel, (call) {
      expect(call.method, 'saveThumbnailToBytes');
      thumbnailRequests++;
      if (thumbnailRequests == 1) return firstThumbnail.future;
      return Future<Object?>.value(_transparentPixelPng);
    });

    final previousPlatform = VideoPlayerPlatform.instance;
    final platform = _FakeMobileVideoPlatform();
    VideoPlayerPlatform.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      SharedPreferences.setMockInitialValues(const {});
      final sourcePath = File('pubspec.yaml').absolute.path;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: VideoPlayerView(
              video: TdFileRef(id: 703, localPath: sourcePath),
              width: 1920,
              height: 1080,
              onClose: () {},
              streamQuery: _completedVideoQuery(sourcePath, fileId: 703),
            ),
          ),
        ),
      );
      await _pumpUntilPlayerReady(tester);

      final timeline = tester.getRect(_timeline);
      final seeksBeforeDrag = platform.seekPositions.length;
      final gesture = await tester.startGesture(
        Offset(timeline.center.dx - 35, timeline.center.dy),
      );
      await gesture.moveBy(const Offset(55, 0));
      await tester.pump();

      expect(_compactScrubPreview, findsOneWidget);
      expect(thumbnailRequests, 1);
      expect(
        find.descendant(
          of: _compactScrubPreview,
          matching: find.byType(RotationTransition),
        ),
        findsOneWidget,
      );
      expect(platform.seekPositions, hasLength(seeksBeforeDrag));

      await gesture.moveBy(const Offset(35, 0));
      await tester.pump(const Duration(milliseconds: 120));
      expect(thumbnailRequests, 1);
      expect(platform.seekPositions, hasLength(seeksBeforeDrag));

      await tester.pump(const Duration(seconds: 2, milliseconds: 1));
      for (var attempt = 0; attempt < 10 && thumbnailRequests < 2; attempt++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(thumbnailRequests, 2);
      expect(
        find.descendant(
          of: _compactScrubPreview,
          matching: find.byType(RotationTransition),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: _compactScrubPreview, matching: find.byType(Image)),
        findsOneWidget,
      );
      expect(platform.seekPositions, hasLength(seeksBeforeDrag));

      await gesture.up();
      await _pumpUntilPreviewGone(tester);
      expect(platform.seekPositions, hasLength(seeksBeforeDrag + 1));
      expect(_compactScrubPreview, findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpUntilDisposed(tester, platform);
      expect(platform.disposeCalls, 1);
    } finally {
      if (!firstThumbnail.isCompleted) firstThumbnail.complete(null);
      messenger.setMockMethodCallHandler(thumbnailChannel, null);
      VideoPlayerPlatform.instance = previousPlatform;
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('PiP restore snapshot overrides resume and remains paused', (
    tester,
  ) async {
    final previousPlatform = VideoPlayerPlatform.instance;
    final platform = _FakeMobileVideoPlatform();
    VideoPlayerPlatform.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      SharedPreferences.setMockInitialValues(const {
        'mithka.video.resume.8.802': 12000,
      });
      final sourcePath = File('pubspec.yaml').absolute.path;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: VideoPlayerView(
            video: TdFileRef(id: 802, localPath: sourcePath),
            sourceChatId: 8,
            messageId: 802,
            initialPosition: const Duration(seconds: 37),
            initialPlaying: false,
            initialSpeed: 1.5,
            initialMuted: true,
            onClose: () {},
            streamQuery: _completedVideoQuery(sourcePath, fileId: 802),
          ),
        ),
      );
      await _pumpUntilPlayerReady(tester);

      expect(platform.seekPositions, [const Duration(seconds: 37)]);
      expect(platform.playCalls, 0);
      final restoredPlayer = tester.widget<MithkaVideoPlayer>(
        find.byType(MithkaVideoPlayer),
      );
      expect(restoredPlayer.controller?.value.playbackSpeed, 1.5);
      expect(restoredPlayer.controller?.value.volume, 0.0);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpUntilDisposed(tester, platform);
    } finally {
      VideoPlayerPlatform.instance = previousPlatform;
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Future<void> _pumpUntilPlayerReady(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  for (
    var attempt = 0;
    attempt < 40 && find.byType(MithkaVideoPlayer).evaluate().isEmpty;
    attempt++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 25));
  }
}

Future<void> _pumpUntilDisposed(
  WidgetTester tester,
  _FakeMobileVideoPlatform platform,
) async {
  for (var attempt = 0; attempt < 40 && platform.disposeCalls == 0; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<void> _pumpUntilPreviewGone(WidgetTester tester) async {
  for (
    var attempt = 0;
    attempt < 20 && _compactScrubPreview.evaluate().isNotEmpty;
    attempt++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
}

final Finder _timeline = find.byWidgetPredicate(
  (widget) =>
      widget is MithkaVideoSlider && widget.semanticLabel == 'Adjust progress',
);

final Finder _compactScrubPreview = find.byWidgetPredicate(
  (widget) =>
      widget is Positioned && widget.width == 128 && widget.height == 72,
);

Finder _semanticsWidget(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

Matcher closeToDuration(Duration expected) => predicate<Duration>(
  (actual) => (actual - expected).abs() <= const Duration(milliseconds: 50),
  'within 50ms of $expected',
);

final _transparentPixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
  'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

TdVideoStreamQuery _completedVideoQuery(String path, {required int fileId}) =>
    (request) async {
      if (request['@type'] != 'getFile') {
        throw UnsupportedError('Unexpected TDLib query ${request['@type']}');
      }
      final length = await File(path).length();
      return _tdFileInfo(
        fileId: fileId,
        path: path,
        totalBytes: length,
        downloadedBytes: length,
        completed: true,
      );
    };

Map<String, dynamic> _tdFileInfo({
  required int fileId,
  required String path,
  required int totalBytes,
  required int downloadedBytes,
  required bool completed,
}) => {
  '@type': 'file',
  'id': fileId,
  'size': totalBytes,
  'expected_size': totalBytes,
  'local': {
    '@type': 'localFile',
    'path': path,
    'download_offset': 0,
    'downloaded_prefix_size': downloadedBytes,
    'downloaded_size': downloadedBytes,
    'is_downloading_active': !completed,
    'is_downloading_completed': completed,
  },
};

final class _SparseVideoQuery {
  _SparseVideoQuery({
    required this.fileId,
    required this.path,
    required this.totalBytes,
    required this.downloadedBytes,
  });

  final int fileId;
  final String path;
  final int totalBytes;
  final int downloadedBytes;
  final requests = <Map<String, dynamic>>[];

  Future<Map<String, dynamic>> call(Map<String, dynamic> request) async {
    requests.add(Map<String, dynamic>.from(request));
    switch (request['@type']) {
      case 'getFile':
      case 'downloadFile':
        return _tdFileInfo(
          fileId: fileId,
          path: path,
          totalBytes: totalBytes,
          downloadedBytes: downloadedBytes,
          completed: false,
        );
      case 'getFileDownloadedPrefixSize':
        final offset = request['offset'] as int? ?? 0;
        return {
          '@type': 'fileDownloadedPrefixSize',
          'size': (downloadedBytes - offset).clamp(0, totalBytes),
        };
      default:
        throw UnsupportedError('Unexpected TDLib query ${request['@type']}');
    }
  }
}

class _FakeMobileVideoPlatform extends VideoPlayerPlatform {
  static const duration = Duration(minutes: 2);
  final Map<int, StreamController<VideoEvent>> _events = {};
  final Map<int, Duration> _positions = {};
  var _nextPlayerId = 1;
  var createCalls = 0;
  var initializedEvents = 0;
  var playCalls = 0;
  var pauseCalls = 0;
  var disposeCalls = 0;
  final creationOptions = <VideoCreationOptions>[];
  final seekPositions = <Duration>[];

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    createCalls++;
    creationOptions.add(options);
    final playerId = _nextPlayerId++;
    _events[playerId] = StreamController<VideoEvent>.broadcast();
    _positions[playerId] = Duration.zero;
    return playerId;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    // The map owns this controller and dispose() closes it.
    // ignore: close_sinks
    final controller = _events[playerId]!;
    scheduleMicrotask(() {
      if (!controller.isClosed) {
        initializedEvents++;
        controller.add(
          VideoEvent(
            eventType: VideoEventType.initialized,
            duration: duration,
            size: const Size(1920, 1080),
          ),
        );
      }
    });
    return controller.stream;
  }

  @override
  Future<void> dispose(int playerId) async {
    disposeCalls++;
    await _events.remove(playerId)?.close();
    _positions.remove(playerId);
  }

  @override
  Future<void> play(int playerId) async {
    playCalls++;
  }

  @override
  Future<void> pause(int playerId) async {
    pauseCalls++;
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    _positions[playerId] = position;
    seekPositions.add(position);
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      _positions[playerId] ?? Duration.zero;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand(key: ValueKey('fake-mobile-video-surface'));
}
