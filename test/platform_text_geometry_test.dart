import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/theme/theme_controller.dart';

/// Material 3's type scale is Roboto's. Outside Android its added tracking and
/// fixed line heights made system faces read wider and airier than the
/// platform's own controls, so the theme drops both there.
void main() {
  final material = Typography.material2021().englishLike;

  test('desktop and Apple targets drop Material tracking and line height', () {
    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.iOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      final body = platformTextGeometry(material.bodyMedium!, platform);
      final field = platformTextGeometry(material.bodyLarge!, platform);
      expect(body.letterSpacing, 0, reason: '$platform');
      expect(body.height, isNull, reason: '$platform');
      expect(field.letterSpacing, 0, reason: '$platform');
      expect(field.height, isNull, reason: '$platform');
      // Only the geometry moves: size and weight stay the scale's.
      expect(body.fontSize, material.bodyMedium!.fontSize);
      expect(body.fontWeight, material.bodyMedium!.fontWeight);
    }
  });

  test('Android keeps Material geometry, which is native there', () {
    final body = platformTextGeometry(
      material.bodyMedium!,
      TargetPlatform.android,
    );
    expect(body, same(material.bodyMedium));
  });

  test('every other style property survives the rebuild', () {
    const style = TextStyle(
      color: Color(0xFF123456),
      fontSize: 15,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
      height: 1.5,
      fontFamily: 'Example',
      fontFamilyFallback: ['PingFang SC'],
      decoration: TextDecoration.none,
    );
    final result = platformTextGeometry(style, TargetPlatform.macOS);
    expect(result.color, style.color);
    expect(result.fontSize, 15);
    expect(result.fontWeight, FontWeight.w500);
    expect(result.fontFamily, 'Example');
    expect(result.fontFamilyFallback, ['PingFang SC']);
    expect(result.decoration, TextDecoration.none);
    expect(result.letterSpacing, 0);
    expect(result.height, isNull);
  });
}
