import 'dart:async';
import 'dart:io';

import 'package:flutter_sound/flutter_sound.dart' show PlayerState;
// The fake native stack extends the platform interface's method-channel
// implementation; it is a transitive dependency of flutter_sound.
// ignore: depend_on_referenced_packages
import 'package:flutter_sound_platform_interface/flutter_sound_player_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_sound_platform_interface/method_channel_flutter_sound_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/music_player_controller.dart';
import 'package:mithka/chat/voice_audio.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_image_loader.dart';
import 'package:mithka/tdlib/td_models.dart';

// A track that fails to start used to be reported as unplayable immediately,
// and the retry replayed the same dead end: a path TDLib had already deleted
// behind the app's back was handed to the native player again, and a start
// that lost its native instance needed a second tap from the user.
//
// These cases drive the production VoicePlayer and MusicPlayerController
// against a fake native audio stack (outbound verbs answered inline, reverse
// callbacks delivered the way a real platform delivers them) and a fake TDLib
// transport, so each failure shape is reproduced end to end: the track must
// start without a failure report, and a track the platform genuinely cannot
// decode must be reported once and leave the queue playable.

/// What the fake native side does with one outbound verb.
enum _Behavior {
  /// Answers and fires the matching completion callback.
  ok,

  /// Answers the invoke but never fires the completion callback. The Dart
  /// future hangs forever — the on-device hang under test.
  silent,
}

class _FakeNative {
  final calls = <String>[];
  final startedUris = <String>[];

  /// Paths the platform cannot decode: the start fails on every attempt.
  final undecodable = <String>{};

  /// openPlayer calls that never report completion, consumed in order.
  final openBehaviors = <_Behavior>[];

  _Behavior nextOpenBehavior() =>
      openBehaviors.isEmpty ? _Behavior.ok : openBehaviors.removeAt(0);
}

class _FakePlatform extends MethodChannelFlutterSoundPlayer {
  _FakePlatform(this.native);

  final _FakeNative native;

  // The real constructor registers a MethodChannel handler; there is no
  // engine in a unit test. Replies come from below.
  @override
  void setCallback() {}

  @override
  Future<void>? resetPlugin(FlutterSoundPlayerCallback callback) async {}

  @override
  Future<int> invokeMethod(
    FlutterSoundPlayerCallback callback,
    String methodName,
    Map<String, dynamic> call,
  ) async {
    native.calls.add(methodName);
    switch (methodName) {
      case 'openPlayer':
        if (native.nextOpenBehavior() == _Behavior.silent) {
          // A wedged open: the invoke is answered, the completion never is.
          return PlayerState.isStopped.index;
        }
        callback.openPlayerCompleted(PlayerState.isStopped.index, true);
        return PlayerState.isStopped.index;
      case 'startPlayer':
        final uri = call['fromURI'] as String?;
        native.startedUris.add(uri ?? '');
        if (uri == null || !File(uri).existsSync()) {
          // Android/iOS reject a source that is not there; the Dart verb then
          // completes with an error the app has to recover from.
          throw Exception('native startPlayer failed: file not found');
        }
        if (native.undecodable.contains(uri)) {
          throw Exception('native startPlayer failed: cannot decode');
        }
        callback.startPlayerCompleted(PlayerState.isPlaying.index, true, 60000);
        return PlayerState.isPlaying.index;
      case 'stopPlayer':
        callback.stopPlayerCompleted(PlayerState.isStopped.index, true);
        return PlayerState.isStopped.index;
      default:
        return PlayerState.isStopped.index;
    }
  }

  @override
  Future<Map> invokeMethodMap(
    FlutterSoundPlayerCallback callback,
    String methodName,
    Map<String, dynamic> call,
  ) async => <String, dynamic>{};
}

/// TDLib's side of file resolution: `downloadFile` answers with the file's
/// current local state, and a completed state carries the downloaded path.
class _FakeTdlib {
  final downloadRequests = <int, int>{};

  /// File ids whose first download request is ignored, like a request TDLib
  /// never picked up: no completion ever follows it.
  final ignoredFirstRequest = <int>{};

  /// Downloaded path per file id. A request for an id missing here stays
  /// incomplete for the whole bounded wait.
  final downloadedPaths = <int, String>{};

  void reset() {
    downloadRequests.clear();
    ignoredFirstRequest.clear();
    downloadedPaths.clear();
  }

  Future<Map<String, dynamic>> query(Map<String, dynamic> request) async {
    if (request['@type'] != 'downloadFile') {
      return <String, dynamic>{'@type': 'ok'};
    }
    final fileId = request['file_id'] as int;
    final count = (downloadRequests[fileId] ?? 0) + 1;
    downloadRequests[fileId] = count;
    if (ignoredFirstRequest.remove(fileId)) {
      return _file(fileId, path: '', completed: false);
    }
    final path = downloadedPaths[fileId];
    if (path == null) return _file(fileId, path: '', completed: false);
    return _file(fileId, path: path, completed: true);
  }

  Map<String, dynamic> _file(
    int fileId, {
    required String path,
    required bool completed,
  }) => <String, dynamic>{
    '@type': 'file',
    'id': fileId,
    'size': 1024,
    'local': <String, dynamic>{
      '@type': 'localFile',
      'path': path,
      'is_downloading_active': !completed,
      'is_downloading_completed': completed,
    },
  };
}

ChatMessage track(int fileId) => ChatMessage(
  id: fileId,
  isOutgoing: false,
  text: '',
  date: 1,
  chatId: 9,
  music: MessageMusic(
    title: 'Track $fileId',
    performer: 'Artist',
    duration: 60,
    file: TdFileRef(id: fileId),
  ),
);

Future<void> until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final sw = Stopwatch()..start();
  while (!condition()) {
    if (sw.elapsed > timeout) {
      throw TimeoutException('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const accountSlot = 63;
  late _FakeNative native;
  late _FakeTdlib tdlib;
  final files = <int, File>{};

  setUpAll(() {
    tdlib = _FakeTdlib();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: accountSlot,
        query: tdlib.query,
        send: (_) async {},
        updates: const Stream<Never>.empty(),
      ),
    );
  });

  setUp(() {
    native = _FakeNative();
    tdlib.reset();
    FlutterSoundPlayerPlatform.instance = _FakePlatform(native);
    VoicePlayer.nativeCallTimeout = const Duration(milliseconds: 80);
    VoicePlayer.maxStartAttempts = 3;
    TdFileCenter.pathWaitTimeout = const Duration(milliseconds: 80);
  });

  tearDown(() {
    FlutterSoundPlayerPlatform.instance = MethodChannelFlutterSoundPlayer();
    VoicePlayer.nativeCallTimeout = const Duration(seconds: 15);
    VoicePlayer.maxStartAttempts = 3;
    TdFileCenter.pathWaitTimeout = const Duration(seconds: 180);
    for (final file in files.values) {
      if (file.existsSync()) file.deleteSync();
    }
    files.clear();
  });

  File downloadedFile(int fileId) {
    final file = files[fileId] ??= File('/tmp/mithka-recovery-$fileId');
    if (!file.existsSync()) file.writeAsStringSync('audio');
    return file;
  }

  test(
    'a remembered path TDLib already deleted downloads again and plays',
    () async {
      const fileId = 610001;
      final downloaded = downloadedFile(fileId);
      tdlib.downloadedPaths[fileId] = downloaded.path;
      // The player remembers a path from a previous session; TDLib's cache
      // optimizer has since removed the file.
      TdFileCenter.shared.rememberForTest(
        accountSlot,
        fileId,
        '/tmp/mithka-evicted-$fileId',
      );

      final voice = VoicePlayer();
      addTearDown(voice.dispose);
      final player = MusicPlayerController.forTest(player: voice);
      final only = track(fileId);

      player.play(only, visibleQueue: [only], toggleIfActive: false);
      await until(() => native.startedUris.isNotEmpty && player.isPlaying);

      expect(native.startedUris, [downloaded.path]);
      expect(tdlib.downloadRequests[fileId], isNotNull);
      expect(player.current?.music?.file?.id, fileId);
      expect(player.playbackFailureReports, 0);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'a download request TDLib never picked up is re-issued and plays',
    () async {
      const fileId = 610002;
      final downloaded = downloadedFile(fileId);
      tdlib.ignoredFirstRequest.add(fileId);
      tdlib.downloadedPaths[fileId] = downloaded.path;

      final voice = VoicePlayer();
      addTearDown(voice.dispose);
      final player = MusicPlayerController.forTest(player: voice);
      final only = track(fileId);

      player.play(only, visibleQueue: [only], toggleIfActive: false);
      await until(() => native.startedUris.isNotEmpty && player.isPlaying);

      expect(tdlib.downloadRequests[fileId], 2);
      expect(native.startedUris, [downloaded.path]);
      expect(player.playbackFailureReports, 0);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'a wedged native open recovers on the automatic retry with a fresh player',
    () async {
      const fileId = 610003;
      final downloaded = downloadedFile(fileId);
      tdlib.downloadedPaths[fileId] = downloaded.path;
      native.openBehaviors.add(_Behavior.silent);

      final voice = VoicePlayer();
      addTearDown(voice.dispose);
      final player = MusicPlayerController.forTest(player: voice);
      final only = track(fileId);

      player.play(only, visibleQueue: [only], toggleIfActive: false);
      await until(() => native.startedUris.isNotEmpty && player.isPlaying);

      // The wedged instance timed out, was retired, and the retry opened a
      // second one — the app never asks the user for that tap.
      expect(native.calls.where((c) => c == 'openPlayer').length, 2);
      expect(native.startedUris, [downloaded.path]);
      expect(player.current?.music?.file?.id, fileId);
      expect(player.playbackFailureReports, 0);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'a track the platform cannot decode is reported once and does not wedge the next one',
    () async {
      const brokenId = 610004;
      const nextId = 610005;
      final broken = downloadedFile(brokenId);
      final next = downloadedFile(nextId);
      tdlib.downloadedPaths[brokenId] = broken.path;
      tdlib.downloadedPaths[nextId] = next.path;
      native.undecodable.add(broken.path);

      final voice = VoicePlayer();
      addTearDown(voice.dispose);
      final player = MusicPlayerController.forTest(player: voice);
      final first = track(brokenId);
      final second = track(nextId);

      player.play(first, visibleQueue: [first, second], toggleIfActive: false);
      await until(() => player.playbackFailureReports == 1);

      // One silent recovery attempt, then the failure is reported: the track
      // is retried once before the user is told it cannot be played.
      expect(
        native.startedUris.where((uri) => uri == broken.path).length,
        2,
        reason: 'the failed load must be retried once before reporting',
      );
      expect(player.current?.music?.file?.id, brokenId);
      expect(player.isPlaying, isFalse);

      // The failed track does not wedge playback: the next one starts.
      player.next();
      await until(
        () => player.isPlaying && native.startedUris.last == next.path,
      );
      expect(player.current?.music?.file?.id, nextId);
      expect(native.startedUris.last, next.path);
      expect(player.playbackFailureReports, 1);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
}
