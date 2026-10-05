import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/music_now_playing.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(MusicNowPlayingBridge.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late _FakeTarget target;
  late MusicNowPlayingBridge bridge;

  ChatMessage track(int fileId, {TdFileRef? cover}) => ChatMessage(
    id: fileId,
    isOutgoing: false,
    text: '',
    date: 1,
    chatId: 7,
    music: MessageMusic(
      title: 'Track $fileId',
      performer: 'Artist',
      duration: 180,
      cover: cover,
      file: TdFileRef(id: fileId),
    ),
  );

  Future<void> pumpPlatform() => Future<void>.delayed(Duration.zero);

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    target = _FakeTarget();
    bridge = MusicNowPlayingBridge(
      target,
      enabled: true,
      resolveArtwork: (cover) async => '/tmp/cover-${cover.id}.jpg',
    );
  });

  tearDown(() {
    bridge.detach();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('publishes track metadata and play state', () async {
    target
      ..current = track(1)
      ..isPlaying = true
      ..total = const Duration(seconds: 180);
    bridge.attach();
    await pumpPlatform();

    final update = calls.single;
    expect(update.method, 'update');
    final args = update.arguments as Map;
    expect(args['title'], 'Track 1');
    expect(args['artist'], 'Artist');
    expect(args['album'], 'Source chat');
    expect(args['durationMs'], 180000);
    expect(args['playing'], isTrue);
    expect(args['labels'], isA<Map>());
  });

  test('steady progress is not republished, but a seek is', () async {
    target
      ..current = track(1)
      ..isPlaying = true;
    bridge.attach();
    await pumpPlatform();
    calls.clear();

    target.position = const Duration(milliseconds: 250);
    target.notify();
    target.position = const Duration(milliseconds: 500);
    target.notify();
    await pumpPlatform();
    expect(calls, isEmpty);

    target.position = const Duration(seconds: 120);
    target.notify();
    await pumpPlatform();
    expect(calls.single.method, 'update');
    expect((calls.single.arguments as Map)['positionMs'], 120000);
  });

  test('pause, track change and artwork each republish', () async {
    target
      ..current = track(1, cover: TdFileRef(id: 99))
      ..isPlaying = true;
    bridge.attach();
    await pumpPlatform();
    await pumpPlatform();
    expect((calls.last.arguments as Map)['artworkPath'], '/tmp/cover-99.jpg');
    calls.clear();

    target.isPlaying = false;
    target.notify();
    await pumpPlatform();
    expect((calls.single.arguments as Map)['playing'], isFalse);
    calls.clear();

    target.current = track(2);
    target.notify();
    await pumpPlatform();
    final args = calls.single.arguments as Map;
    expect(args['title'], 'Track 2');
    expect(args['artworkPath'], isNull);
  });

  test('a loading track shows as playing, not paused', () async {
    target
      ..current = track(1)
      ..isLoading = true;
    bridge.attach();
    await pumpPlatform();
    expect((calls.single.arguments as Map)['playing'], isTrue);
  });

  test('closing the player clears the system controls', () async {
    target.current = track(1);
    bridge.attach();
    await pumpPlatform();
    calls.clear();

    target.current = null;
    target.notify();
    await pumpPlatform();
    expect(calls.single.method, 'clear');
  });

  test(
    'clearing playback drops the cached cover for a reused file id',
    () async {
      target
        ..current = track(1, cover: TdFileRef(id: 99))
        ..isPlaying = true;
      bridge.attach();
      await pumpPlatform();
      await pumpPlatform();
      expect((calls.last.arguments as Map)['artworkPath'], '/tmp/cover-99.jpg');
      calls.clear();

      // Switching accounts clears playback; TDLib can later reuse the same
      // track file id on the new account with a different cover.
      target.current = null;
      target.notify();
      await pumpPlatform();
      expect(calls.single.method, 'clear');
      calls.clear();

      target.current = track(1, cover: TdFileRef(id: 100));
      target.notify();
      await pumpPlatform();
      await pumpPlatform();
      expect(
        (calls.last.arguments as Map)['artworkPath'],
        '/tmp/cover-100.jpg',
      );
    },
  );

  test('a stale in-flight cover cannot publish after a clear', () async {
    final pending = <int, Completer<String?>>{};
    bridge = MusicNowPlayingBridge(
      target,
      enabled: true,
      resolveArtwork: (cover) =>
          pending.putIfAbsent(cover.id, Completer<String?>.new).future,
    );
    target
      ..current = track(1, cover: TdFileRef(id: 99))
      ..isPlaying = true;
    bridge.attach();
    await pumpPlatform();
    expect((calls.last.arguments as Map)['artworkPath'], isNull);
    calls.clear();

    // Clear, then the same file id returns with a different cover.
    target.current = null;
    target.notify();
    await pumpPlatform();
    target.current = track(1, cover: TdFileRef(id: 100));
    target.notify();
    await pumpPlatform();
    expect((calls.last.arguments as Map)['artworkPath'], isNull);

    // The old account's cover resolves late; it must not publish.
    pending[99]!.complete('/tmp/cover-99.jpg');
    await pumpPlatform();
    await pumpPlatform();
    expect((calls.last.arguments as Map)['artworkPath'], isNull);

    pending[100]!.complete('/tmp/cover-100.jpg');
    await pumpPlatform();
    await pumpPlatform();
    expect((calls.last.arguments as Map)['artworkPath'], '/tmp/cover-100.jpg');
  });

  test('remote commands drive the player', () async {
    target.current = track(1);
    bridge.attach();

    Future<void> remote(String method, [Object? arguments]) async {
      await messenger.handlePlatformMessage(
        MusicNowPlayingBridge.channelName,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        (_) {},
      );
    }

    await remote('play');
    await remote('pause');
    await remote('toggle');
    await remote('next');
    await remote('previous');
    await remote('seek', 42000);
    await remote('stop');
    expect(target.commands, [
      'resume',
      'pause',
      'toggle',
      'next',
      'previous',
      'seek:42000',
      'close',
    ]);
  });
}

class _FakeTarget extends ChangeNotifier implements NowPlayingTarget {
  final commands = <String>[];

  @override
  ChatMessage? current;
  @override
  bool isPlaying = false;
  @override
  bool isLoading = false;
  @override
  Duration position = Duration.zero;
  @override
  Duration total = Duration.zero;
  @override
  String get playbackSourceTitle => 'Source chat';

  void notify() => notifyListeners();

  @override
  void resume() => commands.add('resume');
  @override
  void pause() => commands.add('pause');
  @override
  void toggleCurrent() => commands.add('toggle');
  @override
  void next() => commands.add('next');
  @override
  void previous() => commands.add('previous');
  @override
  void seekTo(Duration target) => commands.add('seek:${target.inMilliseconds}');
  @override
  void closeWidget() => commands.add('close');
}
