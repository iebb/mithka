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
const double desktopNavigationRailWidth = 58;
const double desktopConversationMinWidth = 440;

/// Mouse-oriented group context pane. The width leaves enough room for member
/// names while avoiding a visually empty trailing gutter beside the chat.
const double desktopInfoPaneWidth = 224;
const double desktopInfoPaneHandleWidth = 1;

@immutable
class DesktopShellGeometry {
  const DesktopShellGeometry({
    required this.showListPane,
    required this.showInfoPane,
    required this.sidebarWidth,
    required this.conversationWidth,
  });

  final bool showListPane;
  final bool showInfoPane;
  final double sidebarWidth;
  final double conversationWidth;
}

bool usesDesktopShellLayout(
  Size size, {
  TargetPlatform? platform,
  bool isWeb = kIsWeb,
}) {
  final target = platform ?? defaultTargetPlatform;
  return !isWeb && isDesktopTargetPlatform(target);
}

bool usesSplitSelectionLayout(
  Size size, {
  TargetPlatform? platform,
  bool isWeb = kIsWeb,
}) =>
    usesDesktopShellLayout(size, platform: platform, isWeb: isWeb) ||
    usesAdaptiveSplitLayout(size, platform: platform, isWeb: isWeb);

bool desktopDetailNeedsBackButton(DesktopShellGeometry geometry) =>
    !geometry.showListPane;

bool canShowDesktopListPane(double totalWidth) =>
    totalWidth >=
    desktopNavigationRailWidth +
        splitSidebarMinWidth +
        desktopConversationMinWidth;

bool canShowDesktopInfoPane({
  required double totalWidth,
  required double sidebarWidth,
  double infoPaneWidth = desktopInfoPaneWidth,
}) =>
    totalWidth >=
    desktopNavigationRailWidth +
        sidebarWidth +
        desktopConversationMinWidth +
        desktopInfoPaneHandleWidth +
        infoPaneWidth;

DesktopShellGeometry resolveDesktopShellGeometry({
  required double totalWidth,
  required double requestedSidebarWidth,
  bool infoPaneRequested = false,
  double infoPaneWidth = desktopInfoPaneWidth,
}) {
  final availableAfterRail = math.max(
    0.0,
    totalWidth - desktopNavigationRailWidth,
  );
  if (!canShowDesktopListPane(totalWidth)) {
    return DesktopShellGeometry(
      showListPane: false,
      showInfoPane: false,
      sidebarWidth: 0,
      conversationWidth: availableAfterRail,
    );
  }

  final sidebarWidth = constrainSplitSidebarWidth(
    requestedWidth: requestedSidebarWidth,
    totalWidth: availableAfterRail,
  );
  final showInfoPane =
      infoPaneRequested &&
      canShowDesktopInfoPane(
        totalWidth: totalWidth,
        sidebarWidth: sidebarWidth,
        infoPaneWidth: infoPaneWidth,
      );
  final conversationWidth =
      availableAfterRail -
      sidebarWidth -
      (showInfoPane ? desktopInfoPaneHandleWidth + infoPaneWidth : 0);
  return DesktopShellGeometry(
    showListPane: true,
    showInfoPane: showInfoPane,
    sidebarWidth: sidebarWidth,
    conversationWidth: conversationWidth,
  );
}

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
