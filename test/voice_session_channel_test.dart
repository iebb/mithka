//
//  voice_session_channel_test.dart
//
//  The production channel boundary of `SharedVoiceRecordingAudioSession`:
//  `AudioSession.configure` reaches the real `com.ryanheise.audio_session`
//  MethodChannel (setConfiguration), and the activation decision table is
//  driven through the activation seam exactly as production drives
//  `AudioSession.setActive` — restoring the playback configuration over the
//  same real channel when activation refuses or throws. The host is not iOS,
//  so `setActive`'s AVAudioSession branch cannot run here; the seam keeps the
//  activation step honest (refusal/throw/rollback failure) while configure and
//  restore both stay on the genuine channel path.
//

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, PlatformException;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/voice_recording_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.ryanheise.audio_session');
  final calls = <MethodCall>[];

  void installHandler({
    Future<Object?> Function(MethodCall)? onSetConfiguration,
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getConfiguration') return null;
          if (call.method == 'setConfiguration' && onSetConfiguration != null) {
            return await onSetConfiguration(call);
          }
          return null;
        });
  }

  setUp(() {
    calls.clear();
    installHandler();
  });

  tearDown(() {
    SharedVoiceRecordingAudioSession.activationOverrideForTest = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  AudioSessionConfiguration configurationOf(MethodCall call) {
    final args = (call.arguments as List).first as Map<Object?, Object?>;
    return AudioSessionConfiguration.fromJson(
      args.map((k, v) => MapEntry(k.toString(), v)),
    );
  }

  List<AudioSessionConfiguration> sentConfigurations() => calls
      .where((c) => c.method == 'setConfiguration')
      .map(configurationOf)
      .toList();

  test('prepareForCapture configures the real audio_session channel', () async {
    await const SharedVoiceRecordingAudioSession().prepareForCapture();

    final configs = sentConfigurations();
    expect(configs, hasLength(1));
    expect(
      configs[0].avAudioSessionCategory,
      AVAudioSessionCategory.playAndRecord,
    );
    expect(
      configs[0].avAudioSessionCategoryOptions,
      voiceRecordingAudioSessionConfiguration.avAudioSessionCategoryOptions,
    );
    expect(configs[0].avAudioSessionMode, AVAudioSessionMode.voiceChat);
  });

  test(
    'a refused activation restores playback over the real channel',
    () async {
      SharedVoiceRecordingAudioSession.activationOverrideForTest = () async =>
          false;

      await expectLater(
        const SharedVoiceRecordingAudioSession().prepareForCapture(),
        throwsStateError,
      );

      final configs = sentConfigurations();
      expect(configs, hasLength(2));
      expect(
        configs[0].avAudioSessionCategory,
        AVAudioSessionCategory.playAndRecord,
      );
      expect(configs[0].avAudioSessionMode, AVAudioSessionMode.voiceChat);
      // The restore is the playback recipe the rest of the app expects.
      expect(
        configs[1].avAudioSessionCategory,
        AVAudioSessionCategory.playback,
      );
      expect(configs[1].avAudioSessionMode, AVAudioSessionMode.defaultMode);
      expect(
        configs[1].androidAudioFocusGainType,
        const AudioSessionConfiguration.music().androidAudioFocusGainType,
      );
    },
  );

  test('a thrown activation restores playback over the real channel', () async {
    SharedVoiceRecordingAudioSession.activationOverrideForTest = () async =>
        throw StateError('interruption took the route');

    await expectLater(
      const SharedVoiceRecordingAudioSession().prepareForCapture(),
      throwsA(isA<StateError>()),
    );

    final configs = sentConfigurations();
    expect(configs, hasLength(2));
    expect(
      configs[0].avAudioSessionCategory,
      AVAudioSessionCategory.playAndRecord,
    );
    expect(configs[1].avAudioSessionCategory, AVAudioSessionCategory.playback);
    expect(configs[1].avAudioSessionMode, AVAudioSessionMode.defaultMode);
  });

  test('a failing rollback does not mask the original refusal', () async {
    SharedVoiceRecordingAudioSession.activationOverrideForTest = () async =>
        false;
    // The restore configure fails over the real channel; the refusal must
    // still surface (not the rollback failure).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    calls.clear();
    installHandler(
      onSetConfiguration: (call) async {
        if (calls.where((c) => c.method == 'setConfiguration').length > 1) {
          throw PlatformException(code: 'SESSION_GONE');
        }
        return null;
      },
    );

    await expectLater(
      const SharedVoiceRecordingAudioSession().prepareForCapture(),
      throwsStateError,
    );
    expect(
      calls.where((c) => c.method == 'setConfiguration').length,
      2,
      reason: 'the restore attempt still went through the channel',
    );
  });
}
