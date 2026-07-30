import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../platform/adaptive_platform.dart';

export '../platform/adaptive_platform.dart' show isDesktopTargetPlatform;

const double splitSidebarMinWidth = 300;
const double splitSidebarDefaultMinWidth = 320;
const double splitSidebarDefaultMaxWidth = 420;
const double splitDetailMinWidth = 440;
const double splitResizeHandleWidth = 8;

bool usesAdaptiveSplitLayout(
  Size size, {
  TargetPlatform? platform,
  bool isWeb = kIsWeb,
}) {
  final target = platform ?? defaultTargetPlatform;
  final hasSplitWidth =
      size.width >= splitSidebarMinWidth + splitDetailMinWidth;
  if (!isWeb && isDesktopTargetPlatform(target)) return hasSplitWidth;
  return hasSplitWidth &&
      size.width > size.height &&
      math.min(size.width, size.height) >= 600;
}

double defaultSplitSidebarWidth(double totalWidth) {
  return (totalWidth * 0.32)
      .clamp(splitSidebarDefaultMinWidth, splitSidebarDefaultMaxWidth)
      .toDouble();
}

double constrainSplitSidebarWidth({
  required double requestedWidth,
  required double totalWidth,
}) {
  final maxWidth = math.max(
    splitSidebarMinWidth,
    totalWidth - splitDetailMinWidth,
  );
  return requestedWidth.clamp(splitSidebarMinWidth, maxWidth).toDouble();
}
