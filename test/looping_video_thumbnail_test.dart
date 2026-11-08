//
//  looping_video_thumbnail_test.dart
//
//  Regression coverage for the video-thumbnail bug: the looping player's
//  surface must stay unmounted until the player has actually presented
//  frames, so a frameless-but-initialized decoder (a decoder still spinning
//  up, or a key-free MDK binary past its freshness window, which initializes
//  and then renders nothing) leaves the still thumbnail visible instead of
//  covering it with an opaque black surface.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/looping_video_view.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A video_player platform whose players initialize (metadata parsed) but
/// never advance their position until [deliverFirstFrame] is called, standing
/// in for a decoder that presents no frames.
class _FramelessVideoPlatform extends VideoPlayerPlatform {
  final Map<int, StreamController<VideoEvent>> _events = {};
  final Map<int, Duration> _positions = {};
  var _nextId = 1;
  int disposeCalls = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _nextId++;
    _events[id] = StreamController.broadcast();
    _positions[id] = Duration.zero;
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    // The map owns this controller and dispose() closes it.
    // ignore: close_sinks
    final controller = _events[playerId]!;
    scheduleMicrotask(() {
      if (!controller.isClosed) {
        controller.add(
          VideoEvent(
            eventType: VideoEventType.initialized,
            duration: const Duration(minutes: 2),
            size: const Size(1920, 1080),
          ),
        );
      }
    });
    return controller.stream;
  }

  /// Reports a position past the start for [playerId], the signal
  /// video_player only emits once the decoder has presented frames.
  void deliverFirstFrame(int playerId) {
    _positions[playerId] = const Duration(milliseconds: 240);
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      _positions[playerId] ?? Duration.zero;

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    _positions[playerId] = position;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> dispose(int playerId) async {
    disposeCalls++;
    await _events.remove(playerId)?.close();
    _positions.remove(playerId);
  }

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand(key: ValueKey('fake-frameless-video-surface'));
}

const _surface = ValueKey('fake-frameless-video-surface');

Future<void> _settleFrames(WidgetTester tester) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<_FramelessVideoPlatform> _pumpLoopingVideo(WidgetTester tester) async {
  final platform = _FramelessVideoPlatform();
  final previous = VideoPlayerPlatform.instance;
  VideoPlayerPlatform.instance = platform;
  addTearDown(() => VideoPlayerPlatform.instance = previous);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 240,
          height: 240,
          child: LoopingVideoView(
            // Both files exist in the worktree, so TdFileCenter resolves them
            // through the local-source path without TDLib waiters.
            file: TdFileRef(id: 4201, localPath: 'pubspec.yaml'),
            fallback: TdFileRef(id: 9201, localPath: 'assets/penguin.png'),
          ),
        ),
      ),
    ),
  );
  await _settleFrames(tester);
  return platform;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'frameless initialized player keeps the video surface off the thumbnail',
    (tester) async {
      final platform = await _pumpLoopingVideo(tester);
      // The still thumbnail is what must be painted: the video surface stays
      // unmounted while the player reports no position past its start.
      expect(find.byType(TDImage), findsOneWidget);
      expect(find.byKey(_surface), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleFrames(tester);
      expect(platform.disposeCalls, 1);
    },
  );

  testWidgets('video surface mounts once frames are reported', (tester) async {
    final platform = await _pumpLoopingVideo(tester);
    platform.deliverFirstFrame(1);
    await _settleFrames(tester);
    expect(find.byType(TDImage), findsOneWidget);
    expect(find.byKey(_surface), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settleFrames(tester);
    expect(platform.disposeCalls, 1);
  });

  test('messageVideo parse carries thumbnail and minithumbnail', () {
    Map<String, dynamic> videoContent({
      required bool withMinithumbnail,
      required bool withThumbnail,
    }) => {
      'width': 1280,
      'height': 720,
      'duration': 12,
      'file_name': 'clip.mp4',
      'mime_type': 'video/mp4',
      if (withMinithumbnail)
        'minithumbnail': {'width': 40, 'height': 40, 'data': base64Thumbnail},
      if (withThumbnail)
        'thumbnail': {
          'format': {'@type': 'thumbnailFormatJpeg'},
          'width': 320,
          'height': 240,
          'file': {'id': 777, 'expected_size': 8000},
        },
      'video': {'id': 888, 'size': 1200, 'expected_size': 1500},
    };

    final both = TDParse.mediaAttachment({
      '@type': 'messageVideo',
      'video': videoContent(withMinithumbnail: true, withThumbnail: true),
    });
    expect(both.image?.id, 777);
    expect(both.image?.miniThumb, isNotNull);
    expect(both.video?.id, 888);
    expect(both.videoFileSize, 1200);

    final miniOnly = TDParse.mediaAttachment({
      '@type': 'messageVideo',
      'video': videoContent(withMinithumbnail: true, withThumbnail: false),
    });
    expect(miniOnly.image, isNull);
    expect(miniOnly.video?.id, 888);

    final thumbOnly = TDParse.mediaAttachment({
      '@type': 'messageVideo',
      'video': videoContent(withMinithumbnail: false, withThumbnail: true),
    });
    expect(thumbOnly.image?.id, 777);
    expect(thumbOnly.image?.miniThumb, isNull);

    final note = TDParse.mediaAttachment({
      '@type': 'messageVideoNote',
      'video_note': {
        'duration': 6,
        'length': 240,
        'minithumbnail': {'width': 40, 'height': 40, 'data': base64Thumbnail},
        'thumbnail': {
          'format': {'@type': 'thumbnailFormatJpeg'},
          'width': 240,
          'height': 240,
          'file': {'id': 555, 'expected_size': 6000},
        },
        'video': {'id': 666, 'size': 900},
      },
    });
    expect(note.image?.id, 555);
    expect(note.image?.miniThumb, isNotNull);
    expect(note.video?.id, 666);
  });
}

// A tiny valid base64 payload (content is irrelevant to the parse).
const base64Thumbnail = 'AAAA';
