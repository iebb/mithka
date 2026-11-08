import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:f_videoplayer/f_videoplayer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/video_player_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/media/video_playback_reporting.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Used only to install a deterministic fake for the public video_player API.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('holding a video edge raises the rate and stops on release', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final previousPlatform = VideoPlayerPlatform.instance;
    final platform = _FakeMobileVideoPlatform();
    VideoPlayerPlatform.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues(const {});
      final sourcePath = File('pubspec.yaml').absolute.path;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: VideoPlayerView(
            video: TdFileRef(id: 782, localPath: sourcePath),
            onClose: () {},
            streamQuery: _completedVideoQuery(sourcePath, fileId: 782),
          ),
        ),
      );
      await _pumpUntilPlayerReady(tester);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );

      final forward = await tester.startGesture(const Offset(360, 400));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('2x'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1000));
      expect(platform.playbackSpeeds, contains(2.0));
      await forward.up();
      await tester.pump();
      expect(find.text('2x'), findsNothing);
      final countAfterRelease = platform.playbackSpeeds.length;
      await tester.pump(const Duration(seconds: 1));
      expect(platform.playbackSpeeds.length, countAfterRelease);
      expect(platform.playbackSpeeds.last, 1.0);

      final backward = await tester.startGesture(const Offset(30, 400));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 500));
      expect(platform.playbackSpeeds.last, 2.0);
      await backward.up();
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpUntilDisposed(tester, platform);
    } finally {
      VideoPlayerPlatform.instance = previousPlatform;
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'reports initialization failure only after every fallback fails',
    (tester) async {
      final videoFailures = _captureVideoFailures();
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeMobileVideoPlatform(
        initializationFailures: 20,
        initializationFailureMessage:
            'MediaCodecVideoRenderer decoder errorCode=4003 video/hevc',
      );
      VideoPlayerPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        SharedPreferences.setMockInitialValues(const {});
        final path = File('pubspec.yaml').absolute.path;
        final query = _completedVideoQuery(path, fileId: 888);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: VideoPlayerView(
              video: TdFileRef(id: 888, localPath: path, mimeType: 'video/mp4'),
              width: 3840,
              height: 2160,
              streamQuery: (request) => query({'@type': 'getFile'}),
            ),
          ),
        );
        for (
          var i = 0;
          i < 80 && find.text('Try again').evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(find.text('Try again'), findsOneWidget);
        expect(platform.createCalls, 5);
        expect(platform.disposeCalls, 5);
        expect(videoFailures, hasLength(1));
        final event = videoFailures.single;
        expect(event.tags!['video.stage'], 'initialization');
        expect(event.tags!['video.reason'], 'decoder');
        expect(event.contexts['video_playback']['attempts'], 5);
        expect(
          event.contexts['video_playback']['completed_file_fallback'],
          isTrue,
        );
        expect(jsonEncode(event.toJson()), isNot(contains(path)));
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'closing while source lookup is pending does not report a failure',
    (tester) async {
      final videoFailures = _captureVideoFailures();
      final pending = Completer<Map<String, dynamic>>();
      SharedPreferences.setMockInitialValues(const {});
      await tester.pumpWidget(
        MaterialApp(
          home: VideoPlayerView(
            video: TdFileRef(id: 889),
            streamQuery: (_) => pending.future,
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete({'@type': 'file', 'id': 889});
      await tester.pump();
      expect(videoFailures, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Android runtime failures change surface then fall back to the completed file',
    (tester) async {
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
          'mithka-runtime-recovery-test-',
        );
        sparseFile = File('${directory.path}/sparse.mp4');
        final handle = await sparseFile.open(mode: FileMode.write);
        await handle.writeFrom(List<int>.generate(64, (index) => index));
        await handle.truncate(1024 * 1024);
        await handle.close();
      });

      final query = _SparseVideoQuery(
        fileId: 708,
        path: sparseFile.path,
        totalBytes: 1024 * 1024,
        downloadedBytes: 64,
      );
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeMobileVideoPlatform();
      VideoPlayerPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        SharedPreferences.setMockInitialValues(const {});
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: VideoPlayerView(
                video: TdFileRef(id: 708, localPath: sparseFile.path),
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
        expect(platform.createCalls, 1);
        expect(platform.initializedEvents, 1);
        expect(platform.createdPlayerIds, [1]);
        expect(platform.playCalls, 1);

        final firstPlayer = tester.widget<FVideoPlayer>(
          find.byType(FVideoPlayer),
        );
        final firstController = firstPlayer.controller!;
        const resumePosition = Duration(seconds: 37);
        await firstController.seekTo(resumePosition);
        await tester.pump();
        expect(firstController.value.position, resumePosition);
        expect(firstController.value.isPlaying, isTrue);

        firstPlayer.onError?.call(
          const FVideoPlayerError('A non-fatal command failed.'),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          platform.createCalls,
          1,
          reason: 'non-fatal command errors must retain the active controller',
        );

        platform.emitRuntimeError(
          platform.createdPlayerIds.single,
          message:
              'MediaCodecVideoRenderer error from the texture '
              'SurfaceProducer.',
        );
        await _pumpUntilReplacementPlayerReady(
          tester,
          platform,
          previousController: firstController,
        );

        expect(tester.takeException(), isNull);
        expect(platform.createCalls, 2);
        expect(platform.initializedEvents, 2);
        expect(platform.createdPlayerIds, [1, 2]);
        expect(platform.disposedPlayerIds, [1]);
        expect(platform.creationOptions, hasLength(2));
        expect(platform.creationOptions.map((options) => options.viewType), [
          VideoViewType.textureView,
          VideoViewType.platformView,
        ]);
        expect(
          platform.creationOptions[1].dataSource.uri,
          platform.creationOptions[0].dataSource.uri,
        );

        final replacementPlayer = tester.widget<FVideoPlayer>(
          find.byType(FVideoPlayer),
        );
        final replacementController = replacementPlayer.controller!;
        expect(replacementController, isNot(same(firstController)));
        expect(replacementController.value.position, resumePosition);
        expect(replacementController.value.isPlaying, isTrue);
        expect(platform.seekPositions, [resumePosition, resumePosition]);
        expect(platform.playCalls, 2);

        platform.emitRuntimeError(platform.createdPlayerIds.last);
        await _pumpUntilReplacementPlayerReady(
          tester,
          platform,
          previousController: replacementController,
          expectedCalls: 3,
        );

        expect(tester.takeException(), isNull);
        expect(platform.createCalls, 3);
        expect(platform.initializedEvents, 3);
        expect(platform.createdPlayerIds, [1, 2, 3]);
        expect(platform.disposedPlayerIds, [1, 2]);
        expect(
          platform.creationOptions[2].dataSource.sourceType,
          DataSourceType.file,
        );
        expect(
          platform.creationOptions[2].dataSource.uri,
          Uri.file(sparseFile.path).toString(),
        );
        expect(
          platform.creationOptions[2].viewType,
          VideoViewType.platformView,
        );
        expect(
          query.requests.where(
            (request) =>
                request['@type'] == 'downloadFile' &&
                request['limit'] == 0 &&
                request['synchronous'] == true,
          ),
          hasLength(1),
        );

        final completedFilePlayer = tester.widget<FVideoPlayer>(
          find.byType(FVideoPlayer),
        );
        expect(completedFilePlayer.controller?.value.position, resumePosition);
        expect(completedFilePlayer.controller?.value.isPlaying, isTrue);
        expect(platform.seekPositions, [
          resumePosition,
          resumePosition,
          resumePosition,
        ]);
        expect(platform.playCalls, 3);

        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpUntilDisposed(tester, platform, expectedCalls: 3);
        expect(platform.disposedPlayerIds, [1, 2, 3]);
      } finally {
        VideoPlayerPlatform.instance = previousPlatform;
        debugDefaultTargetPlatformOverride = null;
        await tester.runAsync(() async {
          if (await directory.exists()) await directory.delete(recursive: true);
        });
      }
    },
  );

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
      final restoredPlayer = tester.widget<FVideoPlayer>(
        find.byType(FVideoPlayer),
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
    attempt < 40 && find.byType(FVideoPlayer).evaluate().isEmpty;
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
  _FakeMobileVideoPlatform platform, {
  int expectedCalls = 1,
}) async {
  for (
    var attempt = 0;
    attempt < 40 && platform.disposeCalls < expectedCalls;
    attempt++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<void> _pumpUntilReplacementPlayerReady(
  WidgetTester tester,
  _FakeMobileVideoPlatform platform, {
  required Object previousController,
  int expectedCalls = 2,
}) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 10));
    final players = find.byType(FVideoPlayer).evaluate();
    if (platform.createCalls == expectedCalls &&
        platform.initializedEvents == expectedCalls &&
        players.length == 1 &&
        !identical(
          (players.single.widget as FVideoPlayer).controller,
          previousController,
        )) {
      return;
    }
  }
}

List<SentryEvent> _captureVideoFailures() {
  final events = <SentryEvent>[];
  final previous = VideoFailureReporter.instance;
  VideoFailureReporter.instance = VideoFailureReporter(
    enabled: () => true,
    capture: (event) async => events.add(event),
  );
  addTearDown(() => VideoFailureReporter.instance = previous);
  return events;
}

Matcher closeToDuration(Duration expected) => predicate<Duration>(
  (actual) => (actual - expected).abs() <= const Duration(milliseconds: 50),
  'within 50ms of $expected',
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
  int downloadedBytes;
  bool completed = false;
  final requests = <Map<String, dynamic>>[];

  Future<Map<String, dynamic>> call(Map<String, dynamic> request) async {
    requests.add(Map<String, dynamic>.from(request));
    switch (request['@type']) {
      case 'getFile':
        return _tdFileInfo(
          fileId: fileId,
          path: path,
          totalBytes: totalBytes,
          downloadedBytes: downloadedBytes,
          completed: completed,
        );
      case 'downloadFile':
        final limit = request['limit'] as int? ?? 0;
        if (limit == 0 && request['synchronous'] == true) {
          downloadedBytes = totalBytes;
          completed = true;
        } else if (limit > 0 && request['synchronous'] == true) {
          downloadedBytes = totalBytes;
        }
        return _tdFileInfo(
          fileId: fileId,
          path: path,
          totalBytes: totalBytes,
          downloadedBytes: downloadedBytes,
          completed: completed,
        );
      case 'getFileDownloadedPrefixSize':
        final offset = request['offset'] as int? ?? 0;
        return {
          '@type': 'fileDownloadedPrefixSize',
          'size': completed
              ? (totalBytes - offset).clamp(0, totalBytes)
              : (downloadedBytes - offset).clamp(0, totalBytes),
        };
      default:
        throw UnsupportedError('Unexpected TDLib query ${request['@type']}');
    }
  }
}

class _FakeMobileVideoPlatform extends VideoPlayerPlatform {
  _FakeMobileVideoPlatform({
    this.initializationFailures = 0,
    this.initializationFailureMessage =
        'The loopback source could not be opened.',
  });

  static const duration = Duration(minutes: 2);
  final int initializationFailures;

  final String initializationFailureMessage;
  final Map<int, StreamController<VideoEvent>> _events = {};
  final Map<int, Duration> _positions = {};
  var _nextPlayerId = 1;
  var createCalls = 0;
  var initializedEvents = 0;
  var playCalls = 0;
  var pauseCalls = 0;
  var disposeCalls = 0;
  final creationOptions = <VideoCreationOptions>[];
  final createdPlayerIds = <int>[];
  final disposedPlayerIds = <int>[];
  final seekPositions = <Duration>[];
  final volumeValues = <double>[];
  final playbackSpeeds = <double>[];
  Completer<void>? nextSeekBarrier;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    createCalls++;
    creationOptions.add(options);
    final playerId = _nextPlayerId++;
    createdPlayerIds.add(playerId);
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
        if (playerId <= initializationFailures) {
          controller.addError(
            PlatformException(
              code: 'VideoError',
              message: initializationFailureMessage,
            ),
          );
          return;
        }
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
    disposedPlayerIds.add(playerId);
    await _events.remove(playerId)?.close();
    _positions.remove(playerId);
  }

  void emitRuntimeError(
    int playerId, {
    String message = 'The loopback stream stopped during playback.',
  }) {
    _events[playerId]!.addError(
      PlatformException(code: 'runtime_video_error', message: message),
    );
  }

  void emitBufferingStart(int playerId) {
    _events[playerId]!.add(
      VideoEvent(eventType: VideoEventType.bufferingStart),
    );
  }

  void emitIsPlayingStateUpdate(int playerId, {required bool isPlaying}) {
    _events[playerId]!.add(
      VideoEvent(
        eventType: VideoEventType.isPlayingStateUpdate,
        isPlaying: isPlaying,
      ),
    );
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
    final barrier = nextSeekBarrier;
    nextSeekBarrier = null;
    await barrier?.future;
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      _positions[playerId] ?? Duration.zero;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {
    volumeValues.add(volume);
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {
    playbackSpeeds.add(speed);
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand(key: ValueKey('fake-mobile-video-surface'));
}
