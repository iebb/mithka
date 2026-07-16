import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/platform/system_ui.dart';

void main() {
  test('light theme uses dark system icons on transparent bars', () {
    final style = systemUiOverlayStyleFor(Brightness.light);

    expect(style.statusBarColor, Colors.transparent);
    expect(style.systemNavigationBarColor, Colors.transparent);
    expect(style.statusBarIconBrightness, Brightness.dark);
    expect(style.systemNavigationBarIconBrightness, Brightness.dark);
    expect(style.statusBarBrightness, Brightness.light);
    expect(style.systemStatusBarContrastEnforced, isFalse);
    expect(style.systemNavigationBarContrastEnforced, isFalse);
  });

  test('dark theme uses light system icons on transparent bars', () {
    final style = systemUiOverlayStyleFor(Brightness.dark);

    expect(style.statusBarColor, Colors.transparent);
    expect(style.systemNavigationBarColor, Colors.transparent);
    expect(style.statusBarIconBrightness, Brightness.light);
    expect(style.systemNavigationBarIconBrightness, Brightness.light);
    expect(style.statusBarBrightness, Brightness.dark);
  });

  test('theme helper follows ThemeData brightness', () {
    final light = systemUiOverlayStyleForTheme(
      ThemeData(brightness: Brightness.light),
    );
    final dark = systemUiOverlayStyleForTheme(
      ThemeData(brightness: Brightness.dark),
    );

    expect(light.statusBarIconBrightness, Brightness.dark);
    expect(dark.statusBarIconBrightness, Brightness.light);
  });

  test('semantic surface helper follows the actual navigation color', () {
    final paleSurface = systemUiOverlayStyleForSurface(const Color(0xFFFFC0B2));
    final darkSurface = systemUiOverlayStyleForSurface(const Color(0xFF132038));

    expect(paleSurface.statusBarIconBrightness, Brightness.dark);
    expect(paleSurface.statusBarBrightness, Brightness.light);
    expect(darkSurface.statusBarIconBrightness, Brightness.light);
    expect(darkSurface.statusBarBrightness, Brightness.dark);
  });
}
