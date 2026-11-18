import 'dart:async';

import 'desktop_image_preview_window_models.dart';

bool get supportsDesktopImagePreviewWindows => false;

Stream<DesktopImagePreviewPathUpdate> get desktopImagePreviewPathUpdates =>
    const Stream.empty();

Stream<bool> get desktopImagePreviewBrightnessUpdates => const Stream.empty();

Future<void> broadcastDesktopImagePreviewBrightness(bool dark) async {}

Future<int?> openDesktopImagePreviewWindow(
  DesktopImagePreviewWindowArguments arguments,
) async => null;

Future<bool> focusDesktopImagePreviewWindow(int windowId) async => false;

Future<void> publishDesktopImagePreviewPath(
  int windowId,
  int index,
  String path,
) async {}

Future<void> closeCurrentDesktopImagePreviewWindow() async {}

Future<int?> currentDesktopImagePreviewOriginWindowId() async => null;

Future<Set<int>> activeDesktopImagePreviewWindowIds() async => const {};

void setDesktopImagePreviewActionHandler(
  DesktopImagePreviewActionHandler handler,
) {}

Future<bool> requestDesktopImagePreviewAction(
  int originWindowId,
  DesktopImagePreviewActionRequest request,
) async => false;

Future<void> focusCurrentDesktopImagePreviewOrigin() async {}

void detachDesktopImagePreviewBridgeIfIdle() {}
