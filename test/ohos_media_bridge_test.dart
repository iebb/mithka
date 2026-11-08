import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:flutter_sound_platform_interface/flutter_sound_player_platform_interface.dart';
import 'package:flutter_sound_platform_interface/flutter_sound_recorder_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:logger/logger.dart' show Level;
import 'package:mithka/media/app_asset_picker.dart';
import 'package:mithka/platform/ohos_media_bridge.dart';
import 'package:mithka/platform/ohos_support.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

/// Plays the native side of `mithka/ohos_media`, recording every call.
class _FakeNative {
  _FakeNative() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridge.channel, _handle);
  }

  final bridge = const OhosMediaBridge(MethodChannel('test/ohos_media'));
  final calls = <MethodCall>[];
  final answers = <String, Object? Function(MethodCall)>{};

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call);
    final answer = answers[call.method];
    return answer?.call(call);
  }

  List<String> get methods => [for (final call in calls) call.method];

  void dispose() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridge.channel, null);
  }
}

class _RecordingPermissionHandler extends PermissionHandlerPlatform {
  final requested = <Permission>[];

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async =>
      PermissionStatus.restricted;

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async {
    requested.addAll(permissions);
    return {for (final p in permissions) p: PermissionStatus.limited};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeNative native;
  setUp(() => native = _FakeNative());
  tearDown(() => native.dispose());

  test('the system picker returns cached copies as files', () async {
    native.answers['pickMedia'] = (_) => ['/cache/a.jpg', '/cache/b.gif'];
    final selection = await AppAssetPicker.pickWithOhosSystemPicker(
      type: AppAssetPickerType.imageAndVideo,
      maxAssets: 9,
      bridge: native.bridge,
    );
    expect(native.calls.single.arguments, {
      'kind': 'imageAndVideo',
      'maxCount': 9,
    });
    expect(
      [for (final a in selection.assets) a.file.path],
      ['/cache/a.jpg', '/cache/b.gif'],
    );
    expect(
      [for (final a in selection.assets) a.isAnimatedImage],
      [false, true],
    );
    expect(selection.failedCount, 0);
  });

  test(
    'image_picker routes gallery to the picker and camera to capture',
    () async {
      native.answers['pickMedia'] = (_) => <String>[];
      native.answers['capture'] = (_) => '/cache/capture.jpg';
      final picker = OhosImagePicker(bridge: native.bridge);

      expect(
        await picker.getImageFromSource(source: ImageSource.gallery),
        isNull,
      );
      final shot = await picker.getImageFromSource(source: ImageSource.camera);
      final video = await picker.getVideo(source: ImageSource.camera);

      expect(shot?.path, '/cache/capture.jpg');
      expect(video?.path, '/cache/capture.jpg');
      expect(native.calls.map((c) => [c.method, c.arguments]), [
        [
          'pickMedia',
          {'kind': 'image', 'maxCount': 1},
        ],
        [
          'capture',
          {'allowPhoto': true, 'allowVideo': false},
        ],
        [
          'capture',
          {'allowPhoto': false, 'allowVideo': true},
        ],
      ]);
    },
  );

  test('only the microphone goes through the bridge', () async {
    native.answers['microphoneStatus'] = (_) => 'denied';
    native.answers['requestMicrophone'] = (_) => 'permanentlyDenied';
    native.answers['openAppSettings'] = (_) => true;
    final fallback = _RecordingPermissionHandler();
    final handler = OhosPermissionHandler(
      fallback: fallback,
      bridge: native.bridge,
    );

    expect(
      await handler.checkPermissionStatus(Permission.microphone),
      PermissionStatus.denied,
    );
    expect(
      await handler.checkPermissionStatus(Permission.camera),
      PermissionStatus.restricted,
    );
    expect(
      await handler.requestPermissions([
        Permission.microphone,
        Permission.camera,
      ]),
      {
        Permission.microphone: PermissionStatus.permanentlyDenied,
        Permission.camera: PermissionStatus.limited,
      },
    );
    expect(fallback.requested, [Permission.camera]);
    expect(await handler.openAppSettings(), isTrue);
    expect(native.methods, [
      'microphoneStatus',
      'requestMicrophone',
      'openAppSettings',
    ]);
  });

  group('flutter_sound recorder', () {
    late FlutterSoundRecorderPlatform previous;
    setUp(() => previous = FlutterSoundRecorderPlatform.instance);
    tearDown(() => FlutterSoundRecorderPlatform.instance = previous);

    test('a real FlutterSoundRecorder records AAC/M4A end to end', () async {
      var amplitude = 32767;
      native.answers['recorderStop'] = (_) => '/tmp/voice.m4a';
      native.answers['recorderAmplitude'] = (_) => amplitude;
      FlutterSoundRecorderPlatform.instance = OhosFlutterSoundRecorder(
        bridge: native.bridge,
      );
      final recorder = FlutterSoundRecorder(logLevel: Level.off);
      await recorder.openRecorder();
      await recorder.setSubscriptionDuration(const Duration(milliseconds: 10));

      expect(await recorder.isEncoderSupported(Codec.opusOGG), isFalse);
      expect(await recorder.isEncoderSupported(Codec.aacMP4), isTrue);

      final levels = <double?>[];
      final progress = recorder.onProgress!.listen(
        (e) => levels.add(e.decibels),
      );
      await recorder.startRecorder(
        toFile: '/tmp/voice.m4a',
        codec: Codec.aacMP4,
        sampleRate: 48000,
        bitRate: 32000,
      );
      expect(recorder.isRecording, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      amplitude = 0;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await recorder.pauseRecorder();
      expect(recorder.isPaused, isTrue);
      await recorder.resumeRecorder();
      expect(await recorder.stopRecorder(), '/tmp/voice.m4a');
      expect(recorder.isStopped, isTrue);
      await progress.cancel();
      await recorder.closeRecorder();

      final start = native.calls.firstWhere((c) => c.method == 'recorderStart');
      expect(start.arguments, {
        'path': '/tmp/voice.m4a',
        'sampleRate': 48000,
        'bitRate': 32000,
        'numChannels': 1,
      });
      expect(levels, contains(0.0));
      expect(levels, contains(-120.0));
      expect(native.methods.where((m) => m != 'recorderAmplitude'), [
        'recorderStart',
        'recorderPause',
        'recorderResume',
        'recorderStop',
      ]);
    });

    test('a rejected codec fails the start without a stuck recorder', () async {
      FlutterSoundRecorderPlatform.instance = OhosFlutterSoundRecorder(
        bridge: native.bridge,
      );
      final recorder = FlutterSoundRecorder(logLevel: Level.off);
      await recorder.openRecorder();
      await expectLater(
        recorder.startRecorder(toFile: '/tmp/v.ogg', codec: Codec.opusOGG),
        throwsA(anything),
      );
      // The composer unwinds a failed attempt with a stop; it must not hang.
      await recorder.stopRecorder();
      await recorder.closeRecorder();
      expect(native.methods, isEmpty);
    });

    test('a native start failure surfaces as a platform exception', () async {
      native.answers['recorderStart'] = (_) =>
          throw PlatformException(code: 'ohos_media', message: 'busy');
      FlutterSoundRecorderPlatform.instance = OhosFlutterSoundRecorder(
        bridge: native.bridge,
      );
      final recorder = FlutterSoundRecorder(logLevel: Level.off);
      await recorder.openRecorder();
      await expectLater(
        recorder.startRecorder(toFile: '/tmp/v.m4a', codec: Codec.aacMP4),
        throwsA(isA<PlatformException>()),
      );
      await recorder.stopRecorder();
      await recorder.closeRecorder();
      expect(native.methods, ['recorderStart']);
    });
  });

  test('dBFS conversion pins full scale, silence and a half-scale peak', () {
    expect(OhosFlutterSoundRecorder.decibelsFor(32767), 0);
    expect(OhosFlutterSoundRecorder.decibelsFor(0), -120);
    expect(OhosFlutterSoundRecorder.decibelsFor(16384), closeTo(-6.02, 0.01));
  });

  group('flutter_sound player', () {
    late FlutterSoundPlayerPlatform previous;
    setUp(() => previous = FlutterSoundPlayerPlatform.instance);
    tearDown(() => FlutterSoundPlayerPlatform.instance = previous);

    test('a real FlutterSoundPlayer plays a voice note to the end', () async {
      var position = 0;
      var completed = false;
      native.answers['playerStart'] = (_) => 3000;
      native.answers['playerProgress'] = (_) => {
        'position': position,
        'duration': 3000,
        'completed': completed,
      };
      FlutterSoundPlayerPlatform.instance = OhosFlutterSoundPlayer(
        bridge: native.bridge,
        finishPollInterval: const Duration(milliseconds: 10),
      );
      final player = FlutterSoundPlayer(logLevel: Level.off);
      await player.openPlayer();
      await player.setSubscriptionDuration(const Duration(milliseconds: 10));
      expect(await player.isDecoderSupported(Codec.opusOGG), isTrue);

      final positions = <Duration>[];
      final progress = player.onProgress!.listen(
        (e) => positions.add(e.position),
      );
      final finished = Completer<void>();
      final duration = await player.startPlayer(
        fromURI: '/tmp/voice.oga',
        codec: Codec.opusOGG,
        whenFinished: finished.complete,
      );
      expect(duration, const Duration(seconds: 3));
      expect(player.isPlaying, isTrue);
      position = 1200;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      // A late sample from before a seek never moves progress backwards.
      position = 900;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await player.setSpeed(1.5);
      await player.setVolume(0.5);
      await player.pausePlayer();
      expect(player.isPaused, isTrue);
      position = 1500;
      await player.seekToPlayer(const Duration(milliseconds: 500));
      await player.resumePlayer();
      expect(player.isPlaying, isTrue);
      completed = true;
      await finished.future.timeout(const Duration(seconds: 2));
      expect(player.isStopped, isTrue);
      await progress.cancel();
      await player.closePlayer();

      expect(positions, contains(const Duration(milliseconds: 1200)));
      expect(positions, isNot(contains(const Duration(milliseconds: 900))));
      final start = native.calls.firstWhere((c) => c.method == 'playerStart');
      final id = (start.arguments as Map)['id'];
      expect(start.arguments, {'id': id, 'path': '/tmp/voice.oga'});
      expect(
        native.calls.firstWhere((c) => c.method == 'playerSeek').arguments,
        {'id': id, 'position': 500},
      );
      expect(native.methods.where((m) => m != 'playerProgress'), [
        'playerStart',
        'playerSetSpeed',
        'playerSetVolume',
        'playerPause',
        'playerSeek',
        'playerResume',
        'playerRelease',
      ]);
    });

    test('whenFinished fires without a progress subscription', () async {
      native.answers['playerStart'] = (_) => 1000;
      native.answers['playerProgress'] = (_) => {
        'position': 1000,
        'duration': 1000,
        'completed': true,
      };
      FlutterSoundPlayerPlatform.instance = OhosFlutterSoundPlayer(
        bridge: native.bridge,
        finishPollInterval: const Duration(milliseconds: 10),
      );
      final player = FlutterSoundPlayer(logLevel: Level.off);
      await player.openPlayer();
      final finished = Completer<void>();
      await player.startPlayer(
        fromURI: '/tmp/draft.m4a',
        whenFinished: finished.complete,
      );
      await finished.future.timeout(const Duration(seconds: 2));
      await player.closePlayer();
    });

    test('stopping restarts cleanly and a buffer source is refused', () async {
      native.answers['playerStart'] = (_) => 1000;
      FlutterSoundPlayerPlatform.instance = OhosFlutterSoundPlayer(
        bridge: native.bridge,
        finishPollInterval: const Duration(hours: 1),
      );
      final player = FlutterSoundPlayer(logLevel: Level.off);
      await player.openPlayer();
      // A stop with nothing loaded must not hang on its completer.
      await player.stopPlayer();
      await player.startPlayer(fromURI: '/tmp/a.m4a');
      await player.startPlayer(fromURI: '/tmp/b.m4a');
      await expectLater(
        player.startPlayer(fromDataBuffer: Uint8List(4)),
        throwsA(anything),
      );
      await player.closePlayer();
      expect(native.methods, [
        'playerStart',
        'playerStop',
        'playerStart',
        'playerStop',
        'playerRelease',
      ]);
    });
  });

  test('HarmonyOS installs the bridge behind all four interfaces', () {
    final image = ImagePickerPlatform.instance;
    final permission = PermissionHandlerPlatform.instance;
    final recorder = FlutterSoundRecorderPlatform.instance;
    final player = FlutterSoundPlayerPlatform.instance;
    addTearDown(() {
      ImagePickerPlatform.instance = image;
      PermissionHandlerPlatform.instance = permission;
      FlutterSoundRecorderPlatform.instance = recorder;
      FlutterSoundPlayerPlatform.instance = player;
    });
    registerOhosDartPluginFallbacks(onOhos: true);
    expect(ImagePickerPlatform.instance, isA<OhosImagePicker>());
    expect(PermissionHandlerPlatform.instance, isA<OhosPermissionHandler>());
    expect(
      (PermissionHandlerPlatform.instance as OhosPermissionHandler).fallback,
      same(permission),
    );
    expect(
      FlutterSoundRecorderPlatform.instance,
      isA<OhosFlutterSoundRecorder>(),
    );
    expect(FlutterSoundPlayerPlatform.instance, isA<OhosFlutterSoundPlayer>());
  });
}
