import 'dart:io';

import 'package:multi_window_manager/multi_window_manager.dart';

bool get usesFlutterDesktopWindowControls =>
    Platform.isWindows || Platform.isLinux;

Future<void> configurePrimaryDesktopWindowChrome() async {
  if (!usesFlutterDesktopWindowControls) return;
  try {
    await MultiWindowManager.current.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
  } on Object {
    // A portable runner may omit native window chrome support. In that case
    // its normal title bar remains usable and the Flutter controls are no-ops.
  }
}

Future<void> minimizePrimaryDesktopWindow() async {
  if (!usesFlutterDesktopWindowControls) return;
  await MultiWindowManager.current.minimize();
}

Future<void> togglePrimaryDesktopWindowMaximized() async {
  if (!usesFlutterDesktopWindowControls) return;
  final window = MultiWindowManager.current;
  if (await window.isMaximized()) {
    await window.unmaximize();
  } else {
    await window.maximize();
  }
}

Future<void> closePrimaryDesktopWindow() async {
  if (!usesFlutterDesktopWindowControls) return;
  await MultiWindowManager.current.close();
}
