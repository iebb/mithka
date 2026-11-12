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
}
