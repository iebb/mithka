import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_wallpaper.dart';

void main() {
  group('wallpaperParallaxOffset', () {
    test('keeps the wallpaper centered at its calibrated attitude', () {
      expect(
        wallpaperParallaxOffset(
          gravityX: 1.5,
          gravityY: -8.5,
          baselineX: 1.5,
          baselineY: -8.5,
        ),
        Offset.zero,
      );
    });

    test('moves proportionally opposite to device tilt', () {
      expect(
        wallpaperParallaxOffset(
          gravityX: 1.75,
          gravityY: -0.875,
          baselineX: 0,
          baselineY: 0,
        ),
        const Offset(-5, 2.5),
      );
    });

    test('clamps extreme sensor readings to the overscan budget', () {
      expect(
        wallpaperParallaxOffset(
          gravityX: -20,
          gravityY: 20,
          baselineX: 0,
          baselineY: 0,
        ),
        const Offset(10, -10),
      );
    });

    test('fails closed for invalid or non-finite readings', () {
      expect(
        wallpaperParallaxOffset(
          gravityX: double.nan,
          gravityY: 0,
          baselineX: 0,
          baselineY: 0,
        ),
        Offset.zero,
      );
    });
  });
}
