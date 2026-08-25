//
//  ipad_window_chrome.dart
//
//  iPadOS 26 draws persistent traffic-light window controls over the top-left
//  corner of floating windows while reporting no matching safe-area inset.
//  This helper reserves extra top clearance so headers keep their leading
//  content (e.g. the chat-list avatar) below the controls.
//

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Extra top inset, in logical pixels, reserved for the iPadOS window
/// controls shown over the top-left corner of a floating window.
const double iPadWindowControlsTopInset = 40;

/// First iPadOS major version that shows the traffic-light window controls.
const int _windowControlsMinimumMajorVersion = 26;

/// Comparison tolerance, in physical pixels, for the floating-window check.
const double _sizeTolerance = 2;

final RegExp _versionPattern = RegExp(r'Version (\d+)');

int? _cachedHostMajorVersion;

/// Extra top inset that clears the iPadOS window controls for the view
/// owning [context]; returns 0 whenever the controls are not shown.
double iPadWindowChromeInsetOf(BuildContext context) {
  final view = View.of(context);
  return iPadWindowChromeInset(
    viewSize: view.physicalSize,
    displaySize: view.display.size,
    paddingTop: MediaQuery.of(context).padding.top,
  );
}

/// Pure variant of [iPadWindowChromeInsetOf].
///
/// The controls only exist on iPadOS 26+ floating windows; fullscreen
/// windows and every other platform keep a zero inset. Two signals detect
/// a floating window:
///
/// * The view is smaller than its display in both dimensions. Sizes are
///   compared orientation-independent because `Display.size` keeps the
///   panel's native portrait orientation while `FlutterView.physicalSize`
///   follows the current interface orientation.
/// * The top safe-area inset is the small window-chrome margin (~10pt)
///   instead of the fullscreen menu-bar inset (~32pt). iPhone landscape
///   reports 0 there, so only a strictly positive inset counts.
double iPadWindowChromeInset({
  required Size viewSize,
  required Size displaySize,
  required double paddingTop,
  TargetPlatform? platform,
  bool isWeb = kIsWeb,
  String? operatingSystemVersion,
}) {
  if (isWeb) return 0;
  if ((platform ?? defaultTargetPlatform) != TargetPlatform.iOS) return 0;
  if (!_supportsWindowControls(operatingSystemVersion)) return 0;
  final floating = paddingTop > 0 && paddingTop <= 16 ||
      _isSmallerInBothDimensions(viewSize, displaySize);
  return floating ? iPadWindowControlsTopInset : 0;
}

bool _isSmallerInBothDimensions(Size size, Size other) {
  final sides = [size.width, size.height]..sort();
  final otherSides = [other.width, other.height]..sort();
  return sides[0] < otherSides[0] - _sizeTolerance &&
      sides[1] < otherSides[1] - _sizeTolerance;
}

bool _supportsWindowControls(String? operatingSystemVersion) {
  final major = operatingSystemVersion == null
      ? _hostMajorVersion()
      : _parseMajorVersion(operatingSystemVersion);
  return major != null && major >= _windowControlsMinimumMajorVersion;
}

int? _hostMajorVersion() {
  return _cachedHostMajorVersion ??= _parseMajorVersion(
    _safeOperatingSystemVersion(),
  );
}

String _safeOperatingSystemVersion() {
  try {
    return Platform.operatingSystemVersion;
  } catch (_) {
    return '';
  }
}

int? _parseMajorVersion(String operatingSystemVersion) {
  final match = _versionPattern.firstMatch(operatingSystemVersion);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}
