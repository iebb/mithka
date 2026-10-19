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

/// Largest disagreement between the view/display side ratios that still
/// counts as one uniform scale of the panel rather than a resized window.
const double _uniformScaleTolerance = 0.01;

final RegExp _versionPattern = RegExp(r'Version (\d+)');

int? _cachedHostMajorVersion;

/// Extra top inset that clears the iPadOS window controls for the view
/// owning [context]; returns 0 whenever the controls are not shown.
double iPadWindowChromeInsetOf(BuildContext context) {
  final view = View.of(context);
  return iPadWindowChromeInset(
    viewSize: view.physicalSize,
    displaySize: view.display.size,
    paddingTop: MediaQuery.paddingOf(context).top,
  );
}

/// Top safe-area inset plus [iPadWindowChromeInsetOf]: the clearance a
/// screen header needs above its first row of content.
double topChromeInsetOf(BuildContext context) =>
    MediaQuery.paddingOf(context).top + iPadWindowChromeInsetOf(context);

/// Pure variant of [iPadWindowChromeInsetOf].
///
/// The controls only exist on iPadOS 26+ floating windows; fullscreen
/// windows and every other platform keep a zero inset. Two signals detect
/// a floating window:
///
/// * The view is smaller than its display in both dimensions AND not merely
///   the same panel at a smaller scale. Sizes are compared
///   orientation-independent because `Display.size` keeps the panel's native
///   portrait orientation while `FlutterView.physicalSize` follows the
///   current interface orientation. Display Zoom (Settings > Display &
///   Brightness > Display) renders the app on a smaller canvas than the
///   panel — an iPhone whose panel is 1290x2796 reports 1179x2556, both
///   sides scaled by the same ~0.914 factor — so a view whose shortest- and
///   longest-side ratios agree is the panel itself, not a window. A resized
///   window changes the sides by different factors: 2256x1480 on a
///   2064x2752 panel is 0.717 by 0.820.
/// * The top safe-area inset is the small window-chrome margin (~10pt)
///   instead of the fullscreen menu-bar inset (~32pt). iPhone landscape
///   reports 0 there, so only a strictly positive inset counts. This signal
///   also covers the one genuinely ambiguous size, a window dragged to
///   exactly half the panel in both dimensions (uniform by construction),
///   because such a window reports the ~10pt chrome margin. A Display-Zoomed
///   app never trips it: its canvas shrinks but the status-bar inset stays
///   the full 44-59pt of a notched device.
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
  final smallWindowChrome = paddingTop > 0 && paddingTop <= 16;
  final resizedWindow =
      _isSmallerInBothDimensions(viewSize, displaySize) &&
      !_isUniformScaleOf(viewSize, displaySize);
  return smallWindowChrome || resizedWindow ? iPadWindowControlsTopInset : 0;
}

bool _isSmallerInBothDimensions(Size size, Size other) =>
    size.shortestSide < other.shortestSide - _sizeTolerance &&
    size.longestSide < other.longestSide - _sizeTolerance;

/// Whether [size] is [other] rendered at one uniform scale.
///
/// The ratios are taken over shortest and longest sides, so the result does
/// not depend on the interface orientation. A display reporting a zero side
/// cannot be compared and is never treated as uniform.
bool _isUniformScaleOf(Size size, Size other) {
  if (other.shortestSide <= 0 || other.longestSide <= 0) return false;
  final shortestRatio = size.shortestSide / other.shortestSide;
  final longestRatio = size.longestSide / other.longestSide;
  return (shortestRatio - longestRatio).abs() <= _uniformScaleTolerance;
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
