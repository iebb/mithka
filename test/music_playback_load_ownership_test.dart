import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_sound/flutter_sound.dart' show PlayerState;
// The fake native stack extends the platform interface's method-channel
// implementation; it is a transitive dependency of flutter_sound.
// ignore: depend_on_referenced_packages
import 'package:flutter_sound_platform_interface/flutter_sound_player_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_sound_platform_interface/method_channel_flutter_sound_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/voice_audio.dart';
import 'package:mithka/tdlib/td_bindings.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_image_loader.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A load names a TDLib file id, and file ids are PER-ACCOUNT: the same number
// means a different file in another account. The player used to resolve the
// account again after its `File.exists` stat (cachedPath / forget / pathFor all
// read `TdClient.shared.activeSlot` at call time), so a stop or an account
// switch during that stat sent the old track's downloadFile through the
// replacement account's client and evicted that account's cache entry for the
// colliding id.
//
// These cases drive the production VoicePlayer against the REAL TdClient
// account registry (two slots, two client ids, synthetic bindings), holding the
// filesystem stat open so the user's stop / pause / account switch lands exactly
// inside the window the old code mishandled.

/// Stands in for tdjson: allocates the client ids the account registry binds to
/// each slot and records what is sent to them.
class _FakeBindings implements TdBindings {
  _FakeBindings(this._client);

  final TdClient _client;
  final List<(int, Map<String, dynamic>)> sent = [];
  int _nextClientId = 100;

  @override
  int createClientId() => _nextClientId++;

  @override
  void send(int clientId, String request) {
    final decoded = jsonDecode(request) as Map<String, dynamic>;
    sent.add((clientId, decoded));
    if (decoded['@type'] == 'close') {
      // Answer the close handshake the way the receive isolate would, so slot
      // cleanup does not sit on the real 15-second timeout.
      _client.debugCompleteClientClosed(clientId);
    }
  }

  @override
  bool get supportsSessionStringBackup => false;

  @override
  bool get supportsTransferBoost => false;

  @override
  String? receive(double timeout) => throw UnimplementedError();

  @override
  Object? receiveJson(double timeout) => throw UnimplementedError();

  @override
  String? execute(String request) => throw UnimplementedError();

  @override
  String exportSessionString(
    String sourcePath, {
    required int apiId,
    required bool testMode,
    required int userId,
  }) => throw UnimplementedError();

  @override
  void importSessionString(String sessionString, String destinationPath) {
    throw UnimplementedError();
  }

  @override
  void configureTransferBoost({
    required int downloadChunkSize,
    required int downloadParallelism,
    required int uploadChunkSize,
    required int uploadParallelism,
  }) {}
}

/// Answers the native verbs inline, the way a working platform player does.
class _FakePlatform extends MethodChannelFlutterSoundPlayer {
  final calls = <String>[];
  final startedUris = <String>[];

  // The real constructor registers a MethodChannel handler; there is no engine
  // in a unit test. Replies come from below.
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
    calls.add(methodName);
    switch (methodName) {
      case 'openPlayer':
        callback.openPlayerCompleted(PlayerState.isStopped.index, true);
        return PlayerState.isStopped.index;
      case 'startPlayer':
        final uri = call['fromURI'] as String?;
        startedUris.add(uri ?? '');
        if (uri == null || !File(uri).existsSync()) {
          throw Exception('native startPlayer failed: file not found');
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

Map<String, dynamic> _fileJson(
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Two real accounts in the client registry: slot 1 owns client 100, slot 2
  // owns client 101. Slot 0 is the registry's unbound legacy slot.
  const oldSlot = 1;
  const newSlot = 2;
  final queries = <(int clientId, Map<String, dynamic> request)>[];
  final downloadedPaths = <int, String>{};
  final tempFiles = <File>[];
  late _FakePlatform platform;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final supportDir = Directory.systemTemp.createTempSync(
      'mithka_music_owner',
    );
    final client = TdClient.shared;
    client.prepareForTesting(
      prefs: prefs,
      supportDir: supportDir.path,
      bindings: _FakeBindings(client),
      queryOverride: (request, clientId) async {
        queries.add((clientId, request));
        if (request['@type'] == 'downloadFile') {
          final fileId = request['file_id'] as int;
          final path = downloadedPaths[fileId];
          return _fileJson(fileId, path: path ?? '', completed: path != null);
        }
        return <String, dynamic>{'@type': 'ok'};
      },
    );
    expect(client.addSlot(), oldSlot);
    expect(client.addSlot(), newSlot);
    expect(client.clientId(oldSlot), 100);
    expect(client.clientId(newSlot), 101);
  });

  setUp(() {
    queries.clear();
    downloadedPaths.clear();
    platform = _FakePlatform();
    FlutterSoundPlayerPlatform.instance = platform;
    VoicePlayer.nativeCallTimeout = const Duration(milliseconds: 200);
    // A request the fixture does not serve must fail fast instead of sitting
    // on the production 180-second path wait.
    TdFileCenter.pathWaitTimeout = const Duration(milliseconds: 150);
  });

  tearDown(() {
    FlutterSoundPlayerPlatform.instance = MethodChannelFlutterSoundPlayer();
    VoicePlayer.nativeCallTimeout = const Duration(seconds: 15);
    TdFileCenter.pathWaitTimeout = const Duration(seconds: 180);
    for (final file in tempFiles) {
      if (file.existsSync()) file.deleteSync();
    }
    tempFiles.clear();
  });

  File downloadedFile(String name) {
    final file = File('/tmp/mithka-owner-$name')..writeAsStringSync('audio');
    tempFiles.add(file);
    return file;
  }

  String missingPath(int fileId) => '/tmp/mithka-owner-missing-$fileId';

  List<Map<String, dynamic>> downloadsOn(int clientId) => [
    for (final (id, request) in queries)
      if (id == clientId && request['@type'] == 'downloadFile') request,
  ];

  List<Map<String, dynamic>> allDownloads() => [
    for (final (_, request) in queries)
      if (request['@type'] == 'downloadFile') request,
  ];

  test(
    'a stop and an account switch during the path stat cancel the download',
    () async {
      const fileId = 710001;
      TdClient.shared.setActive(oldSlot);
      // The path the player remembers from a previous session; TDLib's cache
      // optimizer has since deleted the file, so the stat says "missing".
      TdFileCenter.shared.rememberForTest(oldSlot, fileId, missingPath(fileId));

      final stat = Completer<bool>();
      final statCalled = Completer<String>();
      final voice = VoicePlayer()
        ..fileExistsOverride = (path) {
          if (!statCalled.isCompleted) statCalled.complete(path);
          return stat.future;
        };
      addTearDown(voice.dispose);

      final load = voice.toggleAudio(TdFileRef(id: fileId));
      expect(await statCalled.future, missingPath(fileId));

      // The user stopped the track and the app switched accounts while the
      // stat was still running.
      await voice.stop();
      TdClient.shared.setActive(newSlot);
      stat.complete(false);
      await load;

      expect(
        downloadsOn(TdClient.shared.clientId(newSlot)!),
        isEmpty,
        reason: 'the replacement account must never be asked to download it',
      );
      expect(
        allDownloads(),
        isEmpty,
        reason: 'the stopped load issues no download at all',
      );
      expect(
        [
          for (final (_, request) in queries)
            if (request['@type'] == 'getFile') request,
        ],
        isEmpty,
        reason: 'no getFile-driven cache work either',
      );
      expect(voice.isPlaying, isFalse);
      expect(voice.isLoading, isFalse);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'an unchanged owner still downloads on its own client and plays',
    () async {
      const fileId = 710002;
      final downloaded = downloadedFile('$fileId');
      downloadedPaths[fileId] = downloaded.path;
      TdClient.shared.setActive(oldSlot);
      TdFileCenter.shared.rememberForTest(oldSlot, fileId, missingPath(fileId));

      final voice = VoicePlayer();
      addTearDown(voice.dispose);

      await voice.toggleAudio(TdFileRef(id: fileId));

      expect(downloadsOn(100), hasLength(1));
      expect(downloadsOn(101), isEmpty);
      expect(platform.startedUris, [downloaded.path]);
      expect(voice.isPlaying, isTrue);
      // The resolved path is remembered on the owning account only.
      expect(
        TdFileCenter.shared.cachedPath(
          TdFileRef(id: fileId),
          accountSlot: oldSlot,
        ),
        downloaded.path,
      );
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'a colliding file id never evicts or resolves the other account entry',
    () async {
      const fileId = 710003;
      final otherAccountFile = downloadedFile('other-$fileId');
      // The same numeric id is a different file in the other account, and its
      // path is still valid there.
      TdClient.shared.setActive(newSlot);
      TdFileCenter.shared.rememberForTest(
        newSlot,
        fileId,
        otherAccountFile.path,
      );
      TdClient.shared.setActive(oldSlot);
      TdFileCenter.shared.rememberForTest(oldSlot, fileId, missingPath(fileId));

      final stat = Completer<bool>();
      final statCalled = Completer<void>();
      final voice = VoicePlayer()
        ..fileExistsOverride = (path) {
          if (!statCalled.isCompleted) statCalled.complete();
          return stat.future;
        };
      addTearDown(voice.dispose);

      final load = voice.toggleAudio(TdFileRef(id: fileId));
      await statCalled.future;

      await voice.stop();
      TdClient.shared.setActive(newSlot);
      stat.complete(false);
      await load;

      expect(
        TdFileCenter.shared.cachedPath(
          TdFileRef(id: fileId),
          accountSlot: newSlot,
        ),
        otherAccountFile.path,
        reason: "the other account's entry for the same id must survive",
      );
      expect(downloadsOn(101), isEmpty);
      expect(allDownloads(), isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'a pause during the path stat cancels the download',
    () async {
      const fileId = 710004;
      TdClient.shared.setActive(oldSlot);
      TdFileCenter.shared.rememberForTest(oldSlot, fileId, missingPath(fileId));

      final stat = Completer<bool>();
      final statCalled = Completer<void>();
      final voice = VoicePlayer()
        ..fileExistsOverride = (path) {
          if (!statCalled.isCompleted) statCalled.complete();
          return stat.future;
        };
      addTearDown(voice.dispose);

      final load = voice.toggleAudio(TdFileRef(id: fileId));
      await statCalled.future;

      await voice.pause();
      final loadingAfterPause = voice.isLoading;
      stat.complete(false);
      await load;

      expect(allDownloads(), isEmpty);
      expect(platform.startedUris, isEmpty);
      expect(voice.isPlaying, isFalse);
      expect(
        loadingAfterPause,
        isFalse,
        reason: 'a paused load must not leave its spinner behind',
      );
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'an account switch during native preparation cancels the start',
    () async {
      const fileId = 710005;
      final local = downloadedFile('$fileId');
      TdClient.shared.setActive(oldSlot);
      TdFileCenter.shared.rememberForTest(oldSlot, fileId, local.path);
      final activation = Completer<AudioSession?>();
      final voice = VoicePlayer()
        ..audioSessionActivationOverride = (() => activation.future);
      addTearDown(voice.dispose);
      final load = voice.toggleAudio(TdFileRef(id: fileId));
      for (var turn = 0; turn < 100 && !voice.isPlaying; turn++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(voice.isPlaying, isTrue, reason: 'native preparation is pending');
      expect(platform.startedUris, isEmpty);

      TdClient.shared.setActive(newSlot);
      activation.complete(null);
      await load;

      expect(platform.startedUris, isEmpty);
      expect(allDownloads(), isEmpty);
      await voice.stop();
    },
  );
}
