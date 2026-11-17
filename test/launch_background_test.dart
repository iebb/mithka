//
//  launch_background_test.dart
//
//  The cold-start surfaces are painted by three different runtimes — the
//  Android starting window, the iOS launch storyboard, and Flutter's first
//  frame — and the user sees every seam between them. These tests pin the
//  three to the same two colours so the launch screen follows the system
//  light/dark appearance instead of flashing white. The values-v31 layer
//  additionally pins the Android 12+ system splash icon to the penguin mark.
//

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/platform/system_ui.dart';
import 'package:mithka/theme/app_theme.dart';

const _androidRes = 'android/app/src/main/res';
const _iosAssets = 'ios/Runner/Assets.xcassets';
const _launchColorName = 'launch_background';
const _iosLaunchColorName = 'LaunchBackground';

String _read(String relativePath) => File(relativePath).readAsStringSync();

/// Parses `#RRGGBB` / `#AARRGGBB` from a color resource named [name].
Color _androidColor(String xml, String name) {
  final match = RegExp(
    '<color\\s+name="$name"\\s*>\\s*(#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8}))\\s*',
  ).firstMatch(xml);
  expect(
    match,
    isNotNull,
    reason: 'Expected a <color name="$name"> resource in:\n$xml',
  );
  final hex = match!.group(1)!.substring(1);
  final value = int.parse(hex, radix: 16);
  return Color(hex.length == 6 ? 0xFF000000 | value : value);
}

/// Reads one sRGB channel of the [appearance] variant of a color set.
///
/// [appearance] is `null` for the "Any Appearance" (light) variant and
/// `'dark'` for the dark-luminosity variant.
double _iosChannel(
  Map<String, dynamic> colorSet,
  String? appearance,
  String channel,
) {
  final colors = colorSet['colors'] as List<dynamic>;
  for (final entry in colors) {
    final variant = entry as Map<String, dynamic>;
    final appearances = variant['appearances'] as List<dynamic>?;
    String? luminosity;
    for (final a in appearances ?? const <dynamic>[]) {
      final map = a as Map<String, dynamic>;
      if (map['appearance'] == 'luminosity') {
        luminosity = map['value'] as String?;
      }
    }
    if (luminosity != appearance) continue;
    final components =
        ((variant['color'] as Map<String, dynamic>)['components'])
            as Map<String, dynamic>;
    return double.parse(components[channel]!.toString());
  }
  fail('No ${appearance ?? "light"} variant in $colorSet');
}

Color _iosColor(Map<String, dynamic> colorSet, String? appearance) =>
    Color.fromRGBO(
      (_iosChannel(colorSet, appearance, 'red') * 255).round(),
      (_iosChannel(colorSet, appearance, 'green') * 255).round(),
      (_iosChannel(colorSet, appearance, 'blue') * 255).round(),
      1,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final lightLaunch = launchBackgroundColorFor(Brightness.light);
  final darkLaunch = launchBackgroundColorFor(Brightness.dark);

  group('launch background token', () {
    test('matches the app surface the first Flutter frame paints', () {
      expect(lightLaunch, AppColors.light.background);
      expect(darkLaunch, AppColors.dark.background);
      // A dark launch screen that was near-black-but-not-the-app would still
      // read as a jump; the dark surface is deliberately not pure black.
      expect(darkLaunch, isNot(Colors.black));
    });
  });

  group('Android', () {
    test('launch color is night-qualified and matches the app surfaces', () {
      expect(
        _androidColor(
          _read('$_androidRes/values/colors.xml'),
          _launchColorName,
        ),
        lightLaunch,
        reason: 'values/colors.xml must pin the light launch background',
      );
      expect(
        _androidColor(
          _read('$_androidRes/values-night/colors.xml'),
          _launchColorName,
        ),
        darkLaunch,
        reason: 'values-night/colors.xml must pin the dark launch background',
      );
    });

    test('launch drawables reference the color, never hardcoded white', () {
      for (final path in [
        '$_androidRes/drawable/launch_background.xml',
        '$_androidRes/drawable-v21/launch_background.xml',
      ]) {
        final xml = _read(path);
        expect(
          xml,
          contains('@color/$_launchColorName'),
          reason: '$path must resolve through the night-qualified color',
        );
        expect(xml, isNot(contains('@android:color/white')), reason: path);
        expect(
          xml,
          isNot(contains('?android:colorBackground')),
          reason:
              '$path resolves to AppCompat grey (#FAFAFA/#303030), which does '
              'not match the app surface and reads as a flash',
        );
      }
    });

    test('every launch and normal theme paints the same background', () {
      final styleFiles = [
        '$_androidRes/values/styles.xml',
        '$_androidRes/values-night/styles.xml',
        '$_androidRes/values-v29/styles.xml',
        '$_androidRes/values-night-v29/styles.xml',
        '$_androidRes/values-v31/styles.xml',
      ];
      for (final path in styleFiles) {
        final xml = _read(path);
        String style(String name) {
          final match = RegExp(
            '<style name="$name".*?</style>',
            dotAll: true,
          ).firstMatch(xml);
          expect(match, isNotNull, reason: '$path must define $name');
          return match!.group(0)!;
        }

        // LaunchTheme paints the splash drawable, whose bottom layer is the
        // night-qualified colour checked above (top layer: the penguin).
        final launchTheme = style('LaunchTheme');
        expect(
          launchTheme,
          contains(
            '<item name="android:windowBackground">@drawable/launch_penguin_background</item>',
          ),
          reason: 'LaunchTheme in $path must paint the penguin splash drawable',
        );
        // NormalTheme is the window behind Flutter's first frame. It must not
        // resolve to AppCompat's grey colorBackground, or removing the splash
        // changes the colour on screen.
        final normalTheme = style('NormalTheme');
        expect(
          normalTheme,
          contains(
            '<item name="android:windowBackground">@color/$_launchColorName</item>',
          ),
          reason:
              'NormalTheme in $path must use the launch colour so the window '
              'behind the first Flutter frame matches the splash',
        );
        expect(
          launchTheme + normalTheme,
          isNot(contains('?android:colorBackground')),
          reason: '$path still resolves through AppCompat grey',
        );
        // Android 12+ replaces the windowBackground drawable with the system
        // splash screen, whose background comes from this attribute instead.
        expect(
          launchTheme,
          contains(
            '<item name="android:windowSplashScreenBackground">'
            '@color/$_launchColorName</item>',
          ),
          reason: 'LaunchTheme in $path must theme the Android 12+ splash',
        );
      }
    });

    test('Android 12+ splash icon is the penguin mark', () {
      // Without windowSplashScreenAnimatedIcon the system splash falls back
      // to the launcher icon — the manifest default is the small monochrome
      // letter_m mark. The fork's splash must carry the penguin, matching
      // the in-app cold-start page.
      final xml = _read('$_androidRes/values-v31/styles.xml');
      final launchTheme = RegExp(
        '<style name="LaunchTheme".*?</style>',
        dotAll: true,
      ).firstMatch(xml)!.group(0)!;
      expect(
        launchTheme,
        contains(
          '<item name="android:windowSplashScreenAnimatedIcon">'
          '@drawable/penguin_splash</item>',
        ),
        reason: 'the Android 12+ system splash must show the penguin mark',
      );
      // The drawable exists in every density bucket.
      for (final bucket in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
        expect(
          File('$_androidRes/drawable-$bucket/penguin_splash.png').existsSync(),
          isTrue,
          reason: 'drawable-$bucket/penguin_splash.png must exist',
        );
      }
      // The source asset is the same penguin the login page shows.
      expect(File('assets/penguin.png').existsSync(), isTrue);
    });
  });

  group('iOS', () {
    late Map<String, dynamic> colorSet;

    setUpAll(() {
      colorSet =
          jsonDecode(
                _read('$_iosAssets/LaunchBackground.colorset/Contents.json'),
              )
              as Map<String, dynamic>;
    });

    test('launch color set matches the app surfaces in both appearances', () {
      expect(_iosColor(colorSet, null), lightLaunch);
      expect(_iosColor(colorSet, 'dark'), darkLaunch);
    });

    test('color set is registered by its intended name', () {
      final contents =
          jsonDecode(
                _read('$_iosAssets/LaunchBackground.colorset/Contents.json'),
              )
              as Map<String, dynamic>;
      expect(contents['info']['author'], 'xcode');
      expect(contents['colors'], isNotEmpty);
      // Guard against renaming the set without updating the storyboard.
      final storyboard = _read('ios/Runner/Base.lproj/LaunchScreen.storyboard');
      expect(storyboard, contains(_iosLaunchColorName));
    });
  });
}
