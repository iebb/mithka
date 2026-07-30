import 'package:flutter/foundation.dart';

/// Whether the current Flutter target uses a native desktop interaction model.
///
/// Keeping this check in one place lets responsive widgets preserve their
/// existing phone and tablet geometry while adding desktop-only affordances.
bool isDesktopTargetPlatform([TargetPlatform? platform]) {
  if (kIsWeb) return false;
  final target = platform ?? defaultTargetPlatform;
  return target == TargetPlatform.macOS ||
      target == TargetPlatform.windows ||
      target == TargetPlatform.linux;
}
