//
//  webm_sticker_decoder_test.dart
//
//  iOS routes looping WebM (video stickers) through FFmpeg instead of MDK's
//  VT decoder: VT's VP9 path presents the alpha-enhanced WebM Telegram
//  stickers are encoded as faster than the media clock, so playback visibly
//  runs too fast (GIF animations and audio-bearing videos are unaffected).
//  The decoder override has to reach FVP's platform player before playback
//  starts, and must not disturb non-FVP backends.
//

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// FVP keeps its platform implementation private; only a subclass of it can
// record the decoder override the production helper forwards.
// ignore: implementation_imports
import 'package:fvp/src/video_player_mdk.dart';
import 'package:mithka/media/looping_media_playback.dart';
import 'package:video_player/video_player.dart';
// Used only to install a deterministic fake for the public video_player API.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('iOS decodes looping WebM through FFmpeg', () {
    expect(webmLoopingDecoderOverride(TargetPlatform.iOS), const <String>[
      'FFmpeg',
    ]);
  });

  test('every other platform keeps the default decoder order', () {
    for (final platform in TargetPlatform.values) {
      if (platform == TargetPlatform.iOS) continue;
      expect(
        webmLoopingDecoderOverride(platform),
        isNull,
        reason: '$platform must keep its default decoder order',
      );
    }
  });

  group('applyWebmLoopingDecoderOverride', () {
    late _RecordingFvpPlatform platform;
    late VideoPlayerPlatform previousPlatform;

    setUp(() {
      platform = _RecordingFvpPlatform();
      previousPlatform = VideoPlayerPlatform.instance;
      VideoPlayerPlatform.instance = platform;
    });

    tearDown(() {
      VideoPlayerPlatform.instance = previousPlatform;
      platform.close();
    });

    Future<VideoPlayerController> createInitializedController() async {
      final controller = VideoPlayerController.file(File('/tmp/s.webm'));
      await controller.initialize();
      return controller;
    }

    testWidgets(
      'forwards the FFmpeg preference to the FVP platform player on iOS',
      (tester) async {
        final controller = await createInitializedController();
        applyWebmLoopingDecoderOverride(controller);
        expect(platform.decoderCalls, [
          (controller.playerId, const <String>['FFmpeg']),
        ]);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    testWidgets(
      'leaves the decoder order alone on Android',
      (tester) async {
        final controller = await createInitializedController();
        applyWebmLoopingDecoderOverride(controller);
        expect(platform.decoderCalls, isEmpty);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  });
}

/// Records decoder overrides without touching libmdk: every FFI-backed
/// member the controller lifecycle can reach is replaced by a stub.
class _RecordingFvpPlatform extends MdkVideoPlayerPlatform {
  _RecordingFvpPlatform() {
    _events = StreamController<VideoEvent>.broadcast(
      onListen: _emitInitialized,
    );
  }

  late final StreamController<VideoEvent> _events;
  final List<(int, List<String>)> decoderCalls = <(int, List<String>)>[];
  bool _initializedEmitted = false;

  void _emitInitialized() {
    if (_initializedEmitted) return;
    _initializedEmitted = true;
    // The controller subscribes inside initialize() right after the player is
    // created; emitting any earlier would drop the event from the broadcast
    // stream and leave initialize() waiting forever.
    _events.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 3),
        size: const Size(512, 512),
      ),
    );
  }

  @override
  Future<int?> create(DataSource dataSource) async => 42;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events.stream;

  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(
    int playerId,
    bool preventsDisplaySleepDuringVideoPlayback,
  ) async {}

  @override
  void setVideoDecoders(int playerId, List<String> value) {
    decoderCalls.add((playerId, value));
  }

  @override
  Future<void> dispose(int playerId) async {}

  void close() {
    _events.close();
  }
}
