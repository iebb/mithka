import 'package:flutter/foundation.dart';

import '../platform/adaptive_platform.dart';

/// Whether the portrait-first short-video experience belongs on this target.
bool shortVideosAvailableOnPlatform({
  TargetPlatform? platform,
  bool isWeb = kIsWeb,
}) {
  if (isWeb) return true;
  return !isDesktopTargetPlatform(platform);
}
