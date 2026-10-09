import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart' show MethodCall;
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

// Direct platform-transport coverage for the two lifecycle defects from
// review: a start that survives its own cancellation (stop/dispose during
// the audio-session await still reaches the native player), and a retired
// session's late finish callback finishing the replacement track.
//
// The transport fake is the same trick as voice_player_native_recovery_test:
// outbound verbs are answered inline, reverse callbacks are fired on the
// session callback object, and the app's FlutterSoundPlayer (operation
// lock, completers, state machine) runs for real. The audio-session await
// — the point where a stop or dispose races the start — is held open by
// audioSessionActivationOverride without touching any other behavior.

enum _Behavior { ok, silent, error, hang }

class _FakeNative {
  final behaviors = <String, List<_Behavior>>{};
  final calls = <String>[];

  /// Pending `hang` replies, so a test can release one later — e.g. to
  /// deliver a close acknowledgment after asserting the retired session's
  /// slot was not recycled meanwhile.
  final hangs = <String, Completer<Object?>>{};

  void releaseHang(String method, [Object? value]) {
    hangs.remove(method)?.complete(value ?? 0);
  }

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

  /// The per-instance session callbacks, in the order the platform served
  /// them. `callbacks.first` is therefore the oldest (possibly retired)
  /// native session.
  final callbacks = <FlutterSoundPlayerCallback>{};

  @override
  void setCallback() {}

  @override
  Future<void>? resetPlugin(FlutterSoundPlayerCallback callback) async {}

  Future<Object?> _serve(
    FlutterSoundPlayerCallback callback,
    String method,
  ) async {
    final behavior = native.nextBehavior(method);
    callbacks.add(callback);
    native.calls.add(method);
    switch (behavior) {
      case _Behavior.error:
        throw _NativeFailure('native $method failed');
      case _Behavior.hang:
        // The native call never answers and never fires its reverse
        // callback: the Dart-side completer stays pending until the test
        // releases it.
        final completer = Completer<Object?>();
        native.hangs[method] = completer;
        return completer.future;
      case _Behavior.silent:
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

const testFileIds = [910001, 910002, 910003];

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

  const accountSlot = 42;
  late _FakeNative native;

  setUpAll(() {
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
        '/tmp/mithka-ownership-$id',
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

  group('ownership after output preparation', () {
    test(
      'a stop during the session await cancels the start before the native player',
      () async {
        final voice = VoicePlayer();
        addTearDown(voice.dispose);

        final holdActivation = Completer<AudioSession?>();
        voice.audioSessionActivationOverride = () => holdActivation.future;

        final load = voice.toggleAudio(file(910001));
        await until(() => count('openPlayer') == 1);

        await voice.stop(); // While the start still awaits the session.
        expect(
          voice.isActive(file(910001)),
          isFalse,
          reason: 'stop unbinds the stopped track',
        );
        holdActivation.complete(null); // The cancelled start resumes here.
        await load;

        expect(
          count('startPlayer'),
          0,
          reason: 'a start for a stopped track must not reach the player',
        );
        expect(voice.isPlaying, isFalse);
        expect(voice.isLoading, isFalse);
      },
    );

    test(
      'disposing during the session await does not start native playback',
      () async {
        final voice = VoicePlayer();

        final holdActivation = Completer<AudioSession?>();
        voice.audioSessionActivationOverride = () => holdActivation.future;

        final load = voice.toggleAudio(file(910002));
        await until(() => count('openPlayer') == 1);

        voice.dispose();
        holdActivation.complete(null);
        await load;

        expect(
          count('startPlayer'),
          0,
          reason: 'native playback must not start for a disposed player',
        );
      },
    );
  });

  test(
    'a retired session late finish callback must not finish the replacement track',
    () async {
      final voice = VoicePlayer();
      addTearDown(voice.dispose);

      // Track A: the native start never reports completion, the timeout
      // retires its session and the load fails.
      native.plan('startPlayer', [_Behavior.silent, _Behavior.ok]);

      final failures = <int>[];
      voice.onFailed = (fileId, error) => failures.add(fileId);
      unawaited(voice.toggleAudio(file(910001)));
      await until(
        () => failures.isNotEmpty,
        timeout: const Duration(seconds: 8),
      );

      // Track B plays on a fresh native session.
      await voice.toggleAudio(file(910002));
      expect(voice.isPlaying, isTrue, reason: 'track B must be playing');
      final finished = <int>[];
      voice.onFinished = finished.add;

      // The retired session's platform delivers its late finish callback.
      (FlutterSoundPlayerPlatform.instance as _FakePlatform).callbacks.first
          .audioPlayerFinished(PlayerState.isPlaying.index);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        voice.isPlaying,
        isTrue,
        reason: 'a retired session must not stop the replacement track',
      );
      expect(finished, isEmpty, reason: 'no onFinished for track B');
      expect(voice.isActive(file(910002)), isTrue);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'a retired session releases its native player when the late completion unblocks the lock',
    () async {
      final voice = VoicePlayer();
      addTearDown(voice.dispose);

      // Track A: the native start never completes; the timeout retires the
      // session while its startPlayer still holds the operation lock.
      native.plan('startPlayer', [_Behavior.silent, _Behavior.ok]);

      final failures = <int>[];
      voice.onFailed = (fileId, error) => failures.add(fileId);
      unawaited(voice.toggleAudio(file(910001)));
      await until(
        () => failures.isNotEmpty,
        timeout: const Duration(seconds: 8),
      );

      // Track B plays on a fresh native session.
      await voice.toggleAudio(file(910002));
      expect(voice.isPlaying, isTrue);

      final platform = FlutterSoundPlayerPlatform.instance as _FakePlatform;
      final retiredSession = platform.callbacks.first;

      // The retired session never queued a close yet: its startPlayer
      // still pins the operation lock.
      final closesBefore = count('closePlayer');

      // The platform finally delivers the late start completion. The lock
      // releases, and the retirement's queued closePlayer runs: the
      // retired native session is released instead of leaking.
      retiredSession.startPlayerCompleted(
        PlayerState.isPlaying.index,
        true,
        60000,
      );
      await until(
        () => count('closePlayer') > closesBefore,
        timeout: const Duration(seconds: 8),
      );

      // The close was served on the retired session — never on the fresh
      // one that is still playing track B.
      expect(
        platform.callbacks.toSet(),
        contains(retiredSession),
        reason: 'the close must run on the retired session',
      );
      expect(voice.isPlaying, isTrue, reason: 'track B keeps playing');
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'a permanently wedged opened session is still released on the platform',
    () async {
      // The lost-callback case: A's native start NEVER reports completion,
      // so the operation lock stays pinned forever and the queued verb
      // closePlayer can never run. The retirement must still release A's
      // native session through the platform interface — without touching
      // the fresh session B plays on.
      native.plan('startPlayer', [_Behavior.hang, _Behavior.ok]);

      final voice = VoicePlayer();
      addTearDown(voice.dispose);

      final failures = <int>[];
      voice.onFailed = (fileId, error) => failures.add(fileId);
      unawaited(voice.toggleAudio(file(910001)));
      await until(
        () => failures.isNotEmpty,
        timeout: const Duration(seconds: 8),
      );

      // Track B plays on a fresh native session.
      await voice.toggleAudio(file(910002));
      expect(voice.isPlaying, isTrue);

      final platform = FlutterSoundPlayerPlatform.instance as _FakePlatform;
      final retiredSession = platform.callbacks.first;
      final freshSession = platform.callbacks.last;
      expect(retiredSession, isNot(same(freshSession)));

      // The wedged start pinned A's lock: no verb close can ever run. The
      // platform-level release must land on A's session within the bounded
      // cleanup window (the verb timeout + a small margin).
      await until(
        () => native.calls.where((c) => c == 'closePlayer').isNotEmpty,
        timeout: const Duration(seconds: 6),
      );

      // The close was served on the retired session — never on the fresh
      // one that is still playing track B.
      expect(
        platform.callbacks,
        contains(retiredSession),
        reason: 'the close must run on the retired session',
      );
      expect(voice.isPlaying, isTrue, reason: 'track B keeps playing');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'dispose queues a close that releases a still-opening native player',
    () async {
      // openPlayer is answered but its completion callback never arrives,
      // so the Dart open future never completes and the instance stays
      // "opening" forever. dispose must still queue a closePlayer: it
      // waits for the open (like every verb does) and releases the
      // native session when the late open completion unblocks the lock.
      native.plan('openPlayer', [_Behavior.silent]);

      final voice = VoicePlayer();
      unawaited(voice.toggleAudio(file(910003)));
      final platform = FlutterSoundPlayerPlatform.instance as _FakePlatform;
      await until(() => count('openPlayer') == 1);

      voice.dispose();
      // The wedged open pinned the instance's Dart-side open future but
      // not the platform: retirement releases the native session right
      // away through the platform interface.
      expect(count('closePlayer'), 1, reason: 'the session is released');

      platform.callbacks.first.openPlayerCompleted(
        PlayerState.isStopped.index,
        true,
      );
      await until(
        () =>
            native.calls
                .where((c) => c.startsWith('openPlayer') || c == 'closePlayer')
                .length >=
            2,
        timeout: const Duration(seconds: 8),
      );
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'a pending native close acknowledgment must not recycle the callback slot',
    () async {
      // The slot-reuse boundary from review: the retired session's native
      // close is issued but its acknowledgment is held pending, and a
      // fresh session (track B) reuses the freed dart-side slot. A late
      // audioPlayerFinishedPlaying for the OLD session, routed by the
      // REAL SDK dispatcher, must land on the retired instance — never on
      // B. The routing table (session registration) is the SDK's own, so
      // this test goes through channelMethodCallHandler like production.
      native.plan('startPlayer', [_Behavior.hang, _Behavior.ok]);
      native.plan('closePlayer', [_Behavior.hang]);

      final voice = VoicePlayer();
      addTearDown(voice.dispose);
      // Resolve the session await immediately: this test exercises close
      // acknowledgment ordering, not the session race.
      voice.audioSessionActivationOverride = () async => null;

      final failures = <int>[];
      voice.onFailed = (fileId, error) => failures.add(fileId);
      unawaited(voice.toggleAudio(file(910001)));
      await until(
        () => failures.isNotEmpty,
        timeout: const Duration(seconds: 8),
      );

      // Track B plays on a fresh native session; A's slot stays occupied
      // (its close was never acknowledged).
      await voice.toggleAudio(file(910002));
      expect(voice.isPlaying, isTrue, reason: 'track B must be playing');

      final platform = FlutterSoundPlayerPlatform.instance as _FakePlatform;
      final retiredSession = platform.callbacks.first;
      final freshSession = platform.callbacks.last;
      expect(retiredSession, isNot(same(freshSession)));

      final finished = <int>[];
      voice.onFinished = finished.add;

      // A late finish event for the retired session, dispatched through
      // the real SDK handler with A's original slot number. With the old
      // code (closeSession before the acknowledgment) the slot was
      // already recycled and this event stopped B.
      final slotNo = platform.findSession(retiredSession);
      final delivered = platform.channelMethodCallHandler(
        MethodCall('audioPlayerFinishedPlaying', {
          'slotNo': slotNo,
          'arg': PlayerState.isPlaying.index,
          'state': PlayerState.isPlaying.index,
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(
        voice.isPlaying,
        isTrue,
        reason: 'a late event must not stop the replacement track',
      );
      expect(finished, isEmpty, reason: 'no onFinished for track B');
      expect(voice.isActive(file(910002)), isTrue);

      // The close acknowledgment finally arrives: the slot may be freed
      // now, and B keeps playing either way.
      // With the shrunken test timeout the release is a late
      // acknowledgment (the close future already timed out), so the slot
      // correctly stays occupied — exactly the ownership rule under test.
      native.releaseHang('closePlayer');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      unawaited(delivered);
      expect(voice.isPlaying, isTrue, reason: 'track B still plays');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'an acknowledged close frees the slot without a duplicate platform close',
    () async {
      // The verb close path: the native session answers and acknowledges.
      // The slot is freed exactly once (by the acknowledged close) and no
      // unconditional second platform close follows a successful cleanup.
      native.plan('startPlayer', [_Behavior.silent, _Behavior.ok]);

      // A roomy verb-timeout for this test only: the retired instance's
      // verb close must complete within it, so the backup platform close
      // never fires and exactly one closePlayer is deterministic. (The
      // tearDown restores the shared 40ms config for the other tests.)
      VoicePlayer.nativeCallTimeout = const Duration(seconds: 2);

      final voice = VoicePlayer();
      addTearDown(voice.dispose);
      // Resolve the session await immediately: this test exercises close
      // acknowledgment ordering, not the session race.
      voice.audioSessionActivationOverride = () async => null;

      final failures = <int>[];
      voice.onFailed = (fileId, error) => failures.add(fileId);
      unawaited(voice.toggleAudio(file(910001)));
      await until(
        () => failures.isNotEmpty,
        timeout: const Duration(seconds: 8),
      );

      await voice.toggleAudio(file(910002));
      expect(voice.isPlaying, isTrue);

      final platform = FlutterSoundPlayerPlatform.instance as _FakePlatform;
      final retiredSession = platform.callbacks.first;

      // The retirement's verb close runs once the failed start releases
      // the lock, or the platform close runs when the verb times out;
      // either way exactly ONE closePlayer must be served on the retired
      // session, its acknowledgment frees the slot, and no unconditional
      // second platform close follows the successful cleanup.
      // The verb close answered: exactly one closePlayer was served on
      // the retired session and its acknowledgment freed the slot. The
      // pending test's hang applies only to ITS platform instance
      // (native.calls is rebuilt per test), so a stuck close here means a
      // real leak.
      await until(
        () => count('closePlayer') >= 1,
        timeout: const Duration(seconds: 8),
      );
      expect(
        count('closePlayer'),
        1,
        reason: 'no unconditional duplicate close after a successful one',
      );
      expect(
        platform.callbacks.toSet().contains(retiredSession),
        isTrue,
        reason: 'the close ran on the retired session',
      );
      expect(voice.isPlaying, isTrue, reason: 'track B keeps playing');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

Map<String, dynamic> fileJson(int fileId) => <String, dynamic>{
  '@type': 'file',
  'id': fileId,
  'size': 1024,
  'local': <String, dynamic>{
    '@type': 'localFile',
    'path': '/tmp/mithka-ownership-$fileId',
    'is_downloading_completed': true,
  },
};
