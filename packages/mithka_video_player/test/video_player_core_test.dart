import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka_video_player/mithka_video_player.dart';
import 'package:video_player/video_player.dart';

void main() {
  testWidgets('caller-owned controller follows lifecycle and is not disposed', (
    tester,
  ) async {
    final controller = _FakeVideoPlayerController(isPlaying: true);
    await tester.pumpWidget(
      _testHost(
        MithkaVideoPlayer(
          source: const MithkaVideoSource.asset('unused.mp4'),
          controller: controller,
          autoplay: false,
        ),
      ),
    );
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(controller.pauseCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(controller.playCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(controller.disposeCalls, 0);
    controller.dispose();
  });

  testWidgets('source changes do not reinitialize a supplied controller', (
    tester,
  ) async {
    final controller = _FakeVideoPlayerController();
    var readyCalls = 0;
    await tester.pumpWidget(
      _testHost(
        MithkaVideoPlayer(
          source: const MithkaVideoSource.network('https://one.invalid/a.mp4'),
          controller: controller,
          autoplay: false,
          onReady: (_) => readyCalls++,
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      _testHost(
        MithkaVideoPlayer(
          source: const MithkaVideoSource.network('https://two.invalid/b.mp4'),
          controller: controller,
          autoplay: false,
          onReady: (_) => readyCalls++,
        ),
      ),
    );
    await tester.pump();

    expect(controller.initializeCalls, 0);
    expect(readyCalls, 1);
    expect(controller.disposeCalls, 0);
    controller.dispose();
  });

  testWidgets('stale async controller creation cannot win a source race', (
    tester,
  ) async {
    final firstCompleter = Completer<VideoPlayerController>();
    final first = _FakeVideoPlayerController();
    final second = _FakeVideoPlayerController();
    VideoPlayerController? readyController;

    FutureOr<VideoPlayerController> builder(MithkaVideoSource source) =>
        source.location.contains('first') ? firstCompleter.future : second;

    await tester.pumpWidget(
      _testHost(
        MithkaVideoPlayer(
          source: const MithkaVideoSource.network(
            'https://media.invalid/first.mp4',
          ),
          controllerBuilder: builder,
          autoplay: false,
          onReady: (controller) => readyController = controller,
        ),
      ),
    );
    await tester.pumpWidget(
      _testHost(
        MithkaVideoPlayer(
          source: const MithkaVideoSource.network(
            'https://media.invalid/second.mp4',
          ),
          controllerBuilder: builder,
          autoplay: false,
          onReady: (controller) => readyController = controller,
        ),
      ),
    );
    await tester.pump();
    expect(readyController, same(second));

    firstCompleter.complete(first);
    await tester.pump();
    expect(first.disposeCalls, 1);
    expect(readyController, same(second));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(second.disposeCalls, 1);
  });

  testWidgets('controller creation errors expose safe retry UI', (
    tester,
  ) async {
    MithkaVideoPlayerError? reported;
    await tester.pumpWidget(
      _testHost(
        MithkaVideoPlayer(
          source: const MithkaVideoSource.asset('missing.mp4'),
          controllerBuilder: (_) => throw StateError('private backend detail'),
          autoplay: false,
          onError: (error) => reported = error,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('This video could not be played'), findsOneWidget);
    expect(find.text('private backend detail'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    expect(reported, isNotNull);
  });

  testWidgets('invalid zero seek interval fails before controller creation', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testHost(
        const MithkaVideoPlayer(
          source: MithkaVideoSource.asset('unused.mp4'),
          seekInterval: Duration.zero,
        ),
      ),
    );
    expect(tester.takeException(), isArgumentError);
  });
}

Widget _testHost(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: SizedBox(width: 800, height: 450, child: child),
);

class _FakeVideoPlayerController extends VideoPlayerController {
  _FakeVideoPlayerController({bool isPlaying = false}) : super.asset('fake') {
    value = VideoPlayerValue(
      duration: const Duration(minutes: 1),
      size: const Size(1920, 1080),
      isInitialized: true,
      isPlaying: isPlaying,
    );
  }

  int initializeCalls = 0;
  int playCalls = 0;
  int pauseCalls = 0;
  int disposeCalls = 0;

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<void> play() async {
    playCalls++;
    value = value.copyWith(isPlaying: true, isCompleted: false);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> seekTo(Duration moment) async {
    value = value.copyWith(position: moment, isCompleted: false);
  }

  @override
  Future<void> setLooping(bool looping) async {
    value = value.copyWith(isLooping: looping);
  }

  @override
  Future<void> setVolume(double volume) async {
    value = value.copyWith(volume: volume);
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    value = value.copyWith(playbackSpeed: speed);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await super.dispose();
  }
}
