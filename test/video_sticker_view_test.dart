import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/video_sticker_view.dart';

void main() {
  test('uses the static video-sticker fallback on Android 14 and newer', () {
    expect(shouldUseStaticAndroidVideoStickerFallback(34), isTrue);
    expect(shouldUseStaticAndroidVideoStickerFallback(36), isTrue);
  });

  test('keeps animated video stickers on supported Android releases', () {
    expect(shouldUseStaticAndroidVideoStickerFallback(33), isFalse);
  });

  test('fails safely when the Android version is unavailable', () {
    expect(shouldUseStaticAndroidVideoStickerFallback(null), isTrue);
  });
}
