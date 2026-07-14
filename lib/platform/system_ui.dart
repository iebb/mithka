//
//  system_ui.dart
//
//  Edge-to-edge / immersive system bars for status bar and navigation bar.
//

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Draw content under transparent system bars on Android and iOS.
void configureImmersiveSystemUI() {
  // Keep edge-to-edge even when Flutter's platform default changes.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    systemUiOverlayStyleFor(Brightness.light),
  );
}

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

/// Convenience for tests and call sites that only have a [ThemeData].
SystemUiOverlayStyle systemUiOverlayStyleForTheme(ThemeData theme) {
  return systemUiOverlayStyleFor(theme.brightness);
}

/// Whether the current platform should treat system bars as edge-to-edge.
bool get supportsImmersiveSystemUI {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return true;
    default:
      return false;
  }
}
