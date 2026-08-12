import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/platform/player_system_volume.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('mithka/system_media_volume');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'get' => <String, Object>{
              'index': 6,
              'minimum': 0,
              'maximum': 15,
              'fixed': false,
            },
            'set' => <String, Object>{
              'index': 8,
              'minimum': 0,
              'maximum': 15,
              'fixed': false,
            },
            _ => null,
          };
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('reads and returns Android media-volume steps', () async {
    final initial = await PlayerSystemVolume.current();
    final applied = await PlayerSystemVolume.setFraction(1.2);

    expect(initial, isNotNull);
    expect(initial!.fraction, closeTo(0.4, 0.0001));
    expect(initial.canSet, isTrue);
    expect(applied, isNotNull);
    expect(applied!.fraction, closeTo(8 / 15, 0.0001));
    expect(calls.map((call) => call.method), ['get', 'set']);
    expect(calls.last.arguments, 1.0);
  });

  test('does not invoke the Android channel on other platforms', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    expect(await PlayerSystemVolume.current(), isNull);
    expect(await PlayerSystemVolume.setFraction(0.5), isNull);
    expect(calls, isEmpty);
  });

  test('rejects invalid native states', () {
    expect(
      PlayerSystemVolumeState.fromMap(const {
        'index': 16,
        'minimum': 0,
        'maximum': 15,
        'fixed': false,
      }),
      isNull,
    );
    expect(
      const PlayerSystemVolumeState(
        index: 5,
        minimum: 0,
        maximum: 15,
        fixed: true,
      ).canSet,
      isFalse,
    );
  });

  test('Android bridge uses STREAM_MUSIC and its existing permission', () {
    final activity = File(
      'android/app/src/main/kotlin/ad/neko/mithka/MainActivity.kt',
    ).readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(activity, contains('"mithka/system_media_volume"'));
    expect(activity, contains('AudioManager.STREAM_MUSIC'));
    expect(activity, contains('getStreamMinVolume'));
    expect(activity, contains('getStreamMaxVolume'));
    expect(activity, contains('getStreamVolume'));
    expect(activity, contains('setStreamVolume'));
    expect(manifest, contains('android.permission.MODIFY_AUDIO_SETTINGS'));
  });
}
