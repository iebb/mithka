import 'package:flutter/foundation.dart';

import 'desktop_video_window_arguments.dart';

abstract interface class MithkaDesktopVideoWindowsPlatform {
  bool get isSupported;

  MithkaDesktopWindowErrorHandler? get onError;
  set onError(MithkaDesktopWindowErrorHandler? value);

  Set<int> get activeWindowIds;
  ValueListenable<bool> get currentWindowFullscreen;

  Future<MithkaDesktopVideoWindowArguments?> initialize(
    List<String> arguments, {
    required String windowType,
  });

  Future<int?> open(
    MithkaDesktopVideoWindowArguments arguments, {
    MithkaDesktopWindowClosed? onClosed,
    required Duration timeout,
  });

  Future<void> configureCurrentWindow({
    required String title,
    int? videoWidth,
    int? videoHeight,
  });

  Future<void> closeCurrentWindow();
  Future<void> close(int windowId);
  Future<void> closeAll();
  Future<bool> setCurrentWindowFullscreen(bool fullscreen);
  Future<void> toggleCurrentWindowFullscreen();
}
