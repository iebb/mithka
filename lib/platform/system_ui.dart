//
//  system_ui.dart
//
//  Edge-to-edge / immersive system bars for status bar and navigation bar.
//

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'ohos_support.dart';

/// The cold-start background, per brightness.
///
/// Three runtimes paint the launch in sequence — the Android starting window /
/// iOS launch storyboard, the native window behind the Flutter view, and
/// Flutter's first frame. Every one of them has to resolve to this colour for
/// the appearance the system reports, or the seam between them is a visible
/// flash. The native side hardcodes the same two values
/// (`res/values{,-night}/colors.xml` and `Assets.xcassets/LaunchBackground`);
/// [launchBackgroundColorFor] is the Dart half of that contract, and
/// `test/launch_background_test.dart` pins all three together.
Color launchBackgroundColorFor(Brightness brightness) =>
    brightness == Brightness.dark
    ? AppColors.dark.background
    : AppColors.light.background;

/// Draw content under transparent system bars on Android and iOS.
void configureImmersiveSystemUI() {
  // Keep edge-to-edge even when Flutter's platform default changes.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Follow the system appearance: the launch window this style sits on is
  // dark in dark mode, so light-brightness (dark) icons would be invisible
  // for the whole cold start. The app's own AnnotatedRegion takes over on the
  // first frame.
  SystemChrome.setSystemUIOverlayStyle(
    systemUiOverlayStyleFor(platformBrightness),
  );
}

/// The appearance the platform reports, without requiring a [BuildContext].
///
/// Readable before the first frame, which is when the launch chrome is styled.
/// Goes through [WidgetsBinding] rather than `PlatformDispatcher.instance` so
/// the binding's test overrides apply.
Brightness get platformBrightness =>
    WidgetsBinding.instance.platformDispatcher.platformBrightness;

/// Transparent bars with icons that contrast against [brightness] backgrounds.
SystemUiOverlayStyle systemUiOverlayStyleFor(Brightness brightness) {
  final light = brightness == Brightness.light;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    // iOS status bar text/icons.
    statusBarBrightness: light ? Brightness.light : Brightness.dark,
    // Android status bar icons.
    statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: light
        ? Brightness.dark
        : Brightness.light,
    // Avoid OS painting opaque scrims over transparent bars.
    systemStatusBarContrastEnforced: false,
    systemNavigationBarContrastEnforced: false,
  );
}

/// Transparent system bars whose icon treatment follows an actual semantic
/// surface color rather than the app's coarse light/dark mode.
///
/// Telegram themes can pair a light app mode with a dark navigation surface
/// (and vice versa), so the active top bar is the reliable contrast source.
SystemUiOverlayStyle systemUiOverlayStyleForSurface(Color surface) {
  return systemUiOverlayStyleFor(ThemeData.estimateBrightnessForColor(surface));
}

/// Convenience for tests and call sites that only have a [ThemeData].
SystemUiOverlayStyle systemUiOverlayStyleForTheme(ThemeData theme) {
  return systemUiOverlayStyleFor(theme.brightness);
}

/// Whether the current platform should treat system bars as edge-to-edge.
bool get supportsImmersiveSystemUI {
  // HarmonyOS reports a TargetPlatform the stock SDK's switch below cannot
  // name, and it shares the Android windowing model (transparent, edge-to-edge
  // system bars), so it is decided by operating system here.
  if (isOhos) return true;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return true;
    default:
      return false;
  }
}
