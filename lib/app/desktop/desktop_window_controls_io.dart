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
    // A portable runner may omit native window chrome support. On Windows the
    // native title bar then stays up and remains usable. On Linux the runner
    // already created the window undecorated, so there is no native chrome to
    // fall back to and the caption buttons are the only way to drive it.
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
