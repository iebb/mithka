import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart' show PlayerState;
// ignore: depend_on_referenced_packages
import 'package:flutter_sound_platform_interface/flutter_sound_player_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_sound_platform_interface/method_channel_flutter_sound_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/voice_audio.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_image_loader.dart';
import 'package:mithka/tdlib/td_models.dart';

class _MappedNative extends MethodChannelFlutterSoundPlayer {
  final closeGate = Completer<int>();
  final calls = <(String, int)>[];
  int? abandonedSlot;
  bool firstStart = true;
  bool rejectClose = false;

  @override
  void setCallback() {}
  @override
  Future<void>? resetPlugin(FlutterSoundPlayerCallback callback) async {}

  Future<void> complete(String method, int slot, int state) async {
    await channelMethodCallHandler(
      MethodCall(method, {
        'slotNo': slot,
        'state': state,
        'success': true,
        'duration': 60000,
      }),
    );
  }

  @override
  Future<int> invokeMethod(
    FlutterSoundPlayerCallback callback,
    String method,
    Map<String, dynamic> arguments,
  ) async {
    // Keep the actual SDK slot registry and callback dispatcher. This
    // deliberately does not call a captured callback object directly.
    final slot = findSession(callback);
    calls.add((method, slot));
    if (slot < 0) throw StateError('unregistered native session');
    switch (method) {
      case 'openPlayer':
        await complete(
          'openPlayerCompleted',
          slot,
          PlayerState.isStopped.index,
        );
      case 'startPlayer':
        if (firstStart) {
          firstStart = false;
          abandonedSlot = slot;
          return PlayerState.isPlaying.index; // preparation callback lost
        }
        await complete(
          'startPlayerCompleted',
          slot,
          PlayerState.isPlaying.index,
        );
        return PlayerState.isPlaying.index;
      case 'stopPlayer':
        await complete(
          'stopPlayerCompleted',
          slot,
          PlayerState.isStopped.index,
        );
      case 'closePlayer':
        if (slot == abandonedSlot && rejectClose) {
          throw StateError('fake native close rejected');
        }
        if (slot == abandonedSlot && !closeGate.isCompleted) {
          return closeGate.future; // close acknowledgment is still pending
        }
    }
    return PlayerState.isStopped.index;
  }

  @override
  Future<Map> invokeMethodMap(
    FlutterSoundPlayerCallback callback,
    String method,
    Map<String, dynamic> arguments,
  ) async => {};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 42,
        query: (_) async => {'@type': 'ok'},
        send: (_) async {},
        updates: const Stream<Map<String, dynamic>>.empty(),
      ),
    );
  });
  tearDownAll(TdClient.shared.closeProxy);
  test(
    'a pending native close must not recycle its callback slot into a retry',
    () async {
      final original = FlutterSoundPlayerPlatform.instance;
      final platform = _MappedNative();
      FlutterSoundPlayerPlatform.instance = platform;
      VoicePlayer.nativeCallTimeout = const Duration(milliseconds: 150);
      for (final id in [910001, 910002]) {
        TdFileCenter.shared.rememberForTest(42, id, '/tmp/mithka-slot-$id');
      }
      final voice = VoicePlayer()
        ..audioSessionActivationOverride = (() async => null);
      final finished = <int>[];
      voice.onFinished = finished.add;
      try {
        await voice.toggleAudio(TdFileRef(id: 910001));
        await Future<void>.delayed(const Duration(milliseconds: 3250));
        expect(platform.calls.where((c) => c.$1 == 'closePlayer'), isNotEmpty);
        await voice.toggleAudio(TdFileRef(id: 910002));
        expect(voice.isPlaying, isTrue);
        // A can still emit an already-in-flight callback until its native
        // close is acknowledged. Route that event exactly as the SDK does:
        // through slotNo, not through A's captured Dart callback object.
        await platform.channelMethodCallHandler(
          MethodCall('audioPlayerFinishedPlaying', {
            'slotNo': platform.abandonedSlot,
            'state': PlayerState.isStopped.index,
            'arg': PlayerState.isStopped.index,
          }),
        );
        expect(
          voice.isPlaying,
          isTrue,
          reason: 'an abandoned native session must not finish the retry',
        );
        expect(finished, isEmpty);
      } finally {
        if (!platform.closeGate.isCompleted) platform.closeGate.complete(0);
        voice.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        VoicePlayer.nativeCallTimeout = const Duration(seconds: 15);
        FlutterSoundPlayerPlatform.instance = original;
      }
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
  test(
    'a rejected native close keeps late events off the replacement',
    () async {
      final original = FlutterSoundPlayerPlatform.instance;
      final platform = _MappedNative()..rejectClose = true;
      FlutterSoundPlayerPlatform.instance = platform;
      VoicePlayer.nativeCallTimeout = const Duration(milliseconds: 150);
      for (final id in [910011, 910012]) {
        TdFileCenter.shared.rememberForTest(42, id, '/tmp/mithka-slot-$id');
      }
      final voice = VoicePlayer()
        ..audioSessionActivationOverride = (() async => null);
      final finished = <int>[];
      voice.onFinished = finished.add;
      try {
        await voice.toggleAudio(TdFileRef(id: 910011));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(platform.calls.where((c) => c.$1 == 'closePlayer'), isNotEmpty);
        await voice.toggleAudio(TdFileRef(id: 910012));
        expect(voice.isPlaying, isTrue);
        await platform.channelMethodCallHandler(
          MethodCall('audioPlayerFinishedPlaying', {
            'slotNo': platform.abandonedSlot,
            'state': PlayerState.isStopped.index,
            'arg': PlayerState.isStopped.index,
          }),
        );
        expect(voice.isPlaying, isTrue);
        expect(finished, isEmpty);
      } finally {
        voice.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        VoicePlayer.nativeCallTimeout = const Duration(seconds: 15);
        FlutterSoundPlayerPlatform.instance = original;
      }
    },
  );
}
