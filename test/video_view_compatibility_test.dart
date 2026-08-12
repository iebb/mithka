import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/media/video_view_compatibility.dart';
import 'package:video_player/video_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mithka/app_info');

  setUp(resetCompatibleVideoViewType);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('needsDirectVideoSurface', () {
    test('targets the A142 MediaTek decoder combination', () {
      expect(
        needsDirectVideoSurface(
          manufacturer: 'Nothing',
          model: 'A142',
          hardware: 'mt6886',
        ),
        isTrue,
      );
      expect(
        needsDirectVideoSurface(
          manufacturer: 'Nothing',
          model: 'A142',
          hardware: 'qcom',
        ),
        isFalse,
      );
      expect(
        needsDirectVideoSurface(
          manufacturer: 'Other',
          model: 'A142',
          hardware: 'mt6886',
        ),
        isFalse,
      );
    });

    test('normalizes Android build property casing and whitespace', () {
      expect(
        needsDirectVideoSurface(
          manufacturer: ' NOTHING ',
          model: 'a142',
          hardware: ' MT6886 ',
        ),
        isTrue,
      );
    });
  });

  test('bootstrap selects the direct surface on A142', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'info');
          return <String, Object?>{
            'manufacturer': 'Nothing',
            'model': 'A142',
            'hardware': 'mt6886',
          };
        });

    await initializeCompatibleVideoViewType();

    expect(preferredCompatibleVideoViewType, VideoViewType.platformView);
  });

  test('bootstrap keeps the texture surface on other devices', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          return <String, Object?>{
            'manufacturer': 'Other',
            'model': 'generic',
            'hardware': 'qcom',
          };
        });

    await initializeCompatibleVideoViewType();

    expect(preferredCompatibleVideoViewType, VideoViewType.textureView);
  });
}
