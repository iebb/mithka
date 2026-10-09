import 'dart:async';

import 'package:flutter_sound/flutter_sound.dart' show PlayerState;
// The fake native stack extends the platform interface's method-channel
// implementation; it is a transitive dependency of flutter_sound.
// ignore: depend_on_referenced_packages
import 'package:flutter_sound_platform_interface/flutter_sound_player_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_sound_platform_interface/method_channel_flutter_sound_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/voice_audio.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_image_loader.dart';
import 'package:mithka/tdlib/td_models.dart';

// Drives the production VoicePlayer against a fake native audio stack.
//
// The fake replaces the platform-interface transport: outbound verbs are
// answered inline (and recorded), while the reverse callbacks a real
// platform delivers (openPlayerCompleted, startPlayerCompleted,
// stopPlayerCompleted, ...) are fired on the session callback object. The
// app's FlutterSoundPlayer — its operation lock, its start/open completers,
// its state machine — all run for real. The tests reproduce the failure
// shapes reported on device: a startPlayer whose completion never arrives
// (Android MediaPlayer prepare that never reports prepared, an iOS session
// that never activates) and the recovery that must follow without ever
// touching the wedged instance again.

/// What the fake native side does with one outbound verb.
enum _Behavior {
  /// Answers and fires the matching completion callback.
  ok,

  /// Answers the invoke but never fires the completion callback. The Dart
  /// future hangs forever — this is the on-device hang under test.
  silent,

  /// Throws a platform error back.
  error,
}

class _FakeNative {
  final behaviors = <String, List<_Behavior>>{};
  final calls = <String>[];

  /// Behaviors per method name; the nth call uses list[n-1] (1-based,
  /// including the call about to be served), clamped to the last entry.
  /// Defaults to [_Behavior.ok].
  _Behavior nextBehavior(String method) {
    final nth = calls.where((c) => c == method).length + 1;
    final list = behaviors[method];
    if (list == null || list.isEmpty) return _Behavior.ok;
    return list[(nth - 1).clamp(0, list.length - 1)];
  }

  void plan(String method, List<_Behavior> list) => behaviors[method] = list;
}

class _NativeFailure implements Exception {
  _NativeFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class _FakePlatform extends MethodChannelFlutterSoundPlayer {
  _FakePlatform(this.native);

  final _FakeNative native;

  // The real constructor registers a MethodChannel handler; there is no
  // engine in a unit test, so skip it. Replies come from below.
  @override
  void setCallback() {}

  // Debug-mode hot restarts trigger resetPlugin before the first open;
  // bypass the channel entirely.
  @override
  Future<void>? resetPlugin(FlutterSoundPlayerCallback callback) async {}

  Future<Object?> _serve(
    FlutterSoundPlayerCallback callback,
    String method,
  ) async {
    final behavior = native.nextBehavior(method);
    native.calls.add(method);
    switch (behavior) {
      case _Behavior.error:
        if (method == 'stopPlayer') {
          callback.stopPlayerCompleted(PlayerState.isStopped.index, true);
          return PlayerState.isStopped.index;
        }
        throw _NativeFailure('native $method failed');
      case _Behavior.silent:
        // Reply to the invoke like a real platform, but never fire the
        // completion callback — that silence is the hang under test. The
        // internal `await _stop()` that precedes every startPlayer is NOT
        // part of the failure under test, so it still completes normally.
        if (method == 'stopPlayer') {
          callback.stopPlayerCompleted(PlayerState.isStopped.index, true);
        }
        return switch (method) {
          'startPlayer' => PlayerState.isPlaying.index,
          _ => PlayerState.isStopped.index,
        };
      case _Behavior.ok:
        switch (method) {
          case 'openPlayer':
            callback.openPlayerCompleted(PlayerState.isStopped.index, true);
            return PlayerState.isStopped.index;
          case 'startPlayer':
            callback.startPlayerCompleted(
              PlayerState.isPlaying.index,
              true,
              60000,
            );
            return PlayerState.isPlaying.index;
          case 'stopPlayer':
            callback.stopPlayerCompleted(PlayerState.isStopped.index, true);
            return PlayerState.isStopped.index;
          default:
            return PlayerState.isStopped.index;
        }
    }
  }

  @override
  Future<int> invokeMethod(
    FlutterSoundPlayerCallback callback,
    String methodName,
    Map<String, dynamic> call,
  ) async => (await _serve(callback, methodName)) as int;

  @override
  Future<Map> invokeMethodMap(
    FlutterSoundPlayerCallback callback,
    String methodName,
    Map<String, dynamic> call,
  ) async => <String, dynamic>{};
}

const testFileIds = [900001, 900002, 900003, 900004, 900005];

/// Runs [load] without awaiting its returned future (a wedged start never
/// returns) and polls until [condition] holds, up to [timeout].
Future<void> until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final sw = Stopwatch()..start();
  while (!condition()) {
    if (sw.elapsed > timeout) {
      throw TimeoutException('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const accountSlot = 41;
  late _FakeNative native;

  setUpAll(() {
    // A fake TDLib transport so VoicePlayer's path resolution completes
    // instantly instead of queueing on a real downloadFile round trip.
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: accountSlot,
        query: (request) async => switch (request['@type']) {
          'downloadFile' || 'getFile' => fileJson(request['file_id'] as int),
          _ => <String, dynamic>{'@type': 'ok'},
        },
        send: (_) async {},
        updates: const Stream<Never>.empty(),
      ),
    );
  });

  setUp(() {
    native = _FakeNative();
    FlutterSoundPlayerPlatform.instance = _FakePlatform(native);
    VoicePlayer.nativeCallTimeout = const Duration(milliseconds: 40);
    VoicePlayer.maxStartAttempts = 3;
    for (final id in testFileIds) {
      TdFileCenter.shared.rememberForTest(
        accountSlot,
        id,
        '/tmp/mithka-recovery-$id',
      );
    }
  });

  tearDown(() {
    FlutterSoundPlayerPlatform.instance = MethodChannelFlutterSoundPlayer();
    VoicePlayer.nativeCallTimeout = const Duration(seconds: 15);
    VoicePlayer.maxStartAttempts = 3;
  });

  TdFileRef file(int id) => TdFileRef(id: id);

  int count(String method) => native.calls.where((c) => c == method).length;

  test(
    'a startPlayer whose completion never arrives fails, and the next tap opens a fresh native player',
    () async {
      // First start is swallowed (no completion callback), like a
      // MediaPlayer stuck in prepareAsync; the retry is healthy. Every
      // attempt is swallowed until the last one, because a 40ms
      // audio-session timeout can fail an attempt before it even reaches
      // the native start (the session prepare races the timeout under
      // load); the retry budget absorbs that without masking the hang.
      native.plan('startPlayer', [
        for (var i = 0; i < 12; i++) _Behavior.silent,
        _Behavior.ok,
      ]);

      final voice = VoicePlayer();
      addTearDown(voice.dispose);

      final failures = <int>[];
      voice.onFailed = (fileId, error) => failures.add(fileId);

      unawaited(voice.toggleAudio(file(900001)));
      await until(
        () => failures.isNotEmpty,
        timeout: const Duration(seconds: 8),
      );
      expect(voice.isPlaying, isFalse, reason: 'start never completed');
      expect(voice.isLoading, isFalse, reason: 'the spinner must stop');

      var retried = false;
      var guard = 0;
      while (!voice.isPlaying) {
        guard++;
        if (guard > 30) break;
        expect(guard, lessThan(30), reason: 'retry loop never recovers');
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await voice.toggleAudio(file(900001));
        retried = true;
      }
      expect(retried, isTrue, reason: 'the hang must fail before recovery');
      expect(voice.isPlaying, isTrue, reason: 'the retry must succeed');
      expect(failures, everyElement(900001));
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'a tap during an in-flight start does not queue a second start',
    () async {
      native.plan('startPlayer', [_Behavior.silent]);

      final voice = VoicePlayer();
      unawaited(voice.toggleAudio(file(900002))); // Never completes.
      await until(() => count('startPlayer') == 1);
      await voice.toggleAudio(file(900002)); // Same track: must be dropped.
      await voice.toggleAudio(file(900003)); // Different track: dropped too.

      expect(
        count('startPlayer'),
        1,
        reason: 'a second startPlayer would queue on the wedged lock',
      );

      voice.dispose();
    },
  );

  test(
    'a thrown startPlayer error surfaces and the player stays reusable',
    () async {
      native.plan('startPlayer', [_Behavior.error, _Behavior.ok]);

      final voice = VoicePlayer();
      addTearDown(voice.dispose);

      final failures = <Object>[];
      voice.onFailed = (fileId, error) => failures.add(error);

      unawaited(voice.toggleAudio(file(900004)));
      await until(() => failures.isNotEmpty);
      expect(voice.isPlaying, isFalse);
      expect(failures, hasLength(1));

      await voice.toggleAudio(file(900004));
      expect(voice.isPlaying, isTrue);
    },
  );

  test(
    'openPlayer hangs: the load fails and a retry gets a new session',
    () async {
      native.plan('openPlayer', [_Behavior.silent, _Behavior.ok]);

      final voice = VoicePlayer();
      addTearDown(voice.dispose);

      // The wedged openPlayer times out inside _prepareOutput; the wedged
      // instance is retired and the load reports the failure (a start on an
      // unopened fresh instance would just throw). The next tap runs a full
      // load on a new native player and plays.
      final failures = <int>[];
      voice.onFailed = (fileId, error) => failures.add(fileId);
      unawaited(voice.toggleAudio(file(900005)));
      await until(() => failures.isNotEmpty);
      expect(voice.isPlaying, isFalse);

      await voice.toggleAudio(file(900005));
      expect(voice.isPlaying, isTrue);
      expect(count('openPlayer'), greaterThanOrEqualTo(2));
    },
  );
}

Map<String, dynamic> fileJson(int fileId) => <String, dynamic>{
  '@type': 'file',
  'id': fileId,
  'size': 1024,
  'local': <String, dynamic>{
    '@type': 'localFile',
    'path': '/tmp/mithka-recovery-$fileId',
    'is_downloading_completed': true,
  },
};
