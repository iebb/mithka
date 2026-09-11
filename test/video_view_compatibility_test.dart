import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/video_playback_preferences.dart';
import 'package:mithka/media/video_view_compatibility.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mithka/app_info');

  setUp(() {
    resetCompatibleVideoViewType();
    SharedPreferences.setMockInitialValues({});
  });
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

  for (final sdkInt in [33, 34, 35, 36]) {
    test(
      'bootstrap selects a compatible surface for Android SDK $sdkInt',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              channel,
              (_) async => <String, Object?>{
                'sdkInt': sdkInt,
                // SDK selection must also work without device identity fields.
              },
            );

        await initializeCompatibleVideoViewType();

        expect(
          preferredCompatibleVideoViewType,
          sdkInt >= 34 ? VideoViewType.platformView : VideoViewType.textureView,
        );
      },
    );
  }

  test('missing device channel preserves the texture fallback', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await initializeCompatibleVideoViewType();
    expect(preferredCompatibleVideoViewType, VideoViewType.textureView);
  });

  test(
    'non-Android platforms do not query Android device information',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      var queried = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            queried = true;
            return <String, Object?>{'sdkInt': 35};
          });
      await initializeCompatibleVideoViewType();
      expect(queried, isFalse);
      expect(preferredCompatibleVideoViewType, VideoViewType.textureView);
    },
  );

  test(
    'disabling compatibility persists and changes the next video surface',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => <String, Object?>{
              'sdkInt': 35,
              'manufacturer': 'Nothing',
              'model': 'A142',
              'hardware': 'mt6886',
            },
          );
      await initializeCompatibleVideoViewType();
      expect(preferredCompatibleVideoViewType, VideoViewType.platformView);
      await VideoPlaybackPreferences.saveAndroidVideoCompatibility(false);
      await initializeCompatibleVideoViewType();
      expect(preferredCompatibleVideoViewType, VideoViewType.textureView);
      resetCompatibleVideoViewType();
      await initializeCompatibleVideoViewType();
      expect(preferredCompatibleVideoViewType, VideoViewType.textureView);
      await VideoPlaybackPreferences.saveAndroidVideoCompatibility(true);
      await initializeCompatibleVideoViewType();
      expect(preferredCompatibleVideoViewType, VideoViewType.platformView);
    },
  );

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
