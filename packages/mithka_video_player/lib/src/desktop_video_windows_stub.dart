import 'package:flutter/foundation.dart';

import 'desktop_video_window_arguments.dart';
import 'desktop_video_windows_platform.dart';

MithkaDesktopVideoWindowsPlatform createDesktopWindowsPlatform() =>
    _UnsupportedDesktopVideoWindows();

class _UnsupportedDesktopVideoWindows
    implements MithkaDesktopVideoWindowsPlatform {
  final ValueNotifier<bool> _currentWindowFullscreen = ValueNotifier(false);

  @override
  bool get isSupported => false;

  @override
  MithkaDesktopWindowErrorHandler? onError;

  @override
  Set<int> get activeWindowIds => const {};

  @override
  ValueListenable<bool> get currentWindowFullscreen => _currentWindowFullscreen;

  @override
  Future<MithkaDesktopVideoWindowArguments?> initialize(
    List<String> arguments, {
    required String windowType,
  }) async => null;

  @override
  Future<int?> open(
    MithkaDesktopVideoWindowArguments arguments, {
    MithkaDesktopWindowClosed? onClosed,
    required Duration timeout,
  }) async {
    if (onClosed != null) {
      try {
        await onClosed();
      } on Object catch (error, stackTrace) {
        try {
          onError?.call(
            MithkaDesktopWindowException('onClosed', error),
            stackTrace,
          );
        } on Object {
          // Unsupported-platform cleanup remains a non-throwing no-op.
        }
      }
    }
    return null;
  }

  @override
  Future<void> configureCurrentWindow({
    required String title,
    int? videoWidth,
    int? videoHeight,
  }) async {}

  @override
  Future<void> closeCurrentWindow() async {}

  @override
  Future<void> close(int windowId) async {}

  @override
  Future<void> closeAll() async {}

  @override
  Future<bool> setCurrentWindowFullscreen(bool fullscreen) async => false;

  @override
  Future<void> toggleCurrentWindowFullscreen() async {}
}
