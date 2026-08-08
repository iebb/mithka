import 'dart:async';

import 'package:flutter/foundation.dart';

import 'desktop_video_window_arguments.dart';
import 'desktop_video_windows_platform.dart';
import 'desktop_video_windows_stub.dart'
    if (dart.library.io) 'desktop_video_windows_io.dart'
    as implementation;

export 'desktop_video_window_arguments.dart';
export 'desktop_video_window_host.dart';

/// Whether independent native video windows are available on this platform.
///
/// Importing this library is safe on every Flutter platform. Unsupported
/// platforms never initialize or invoke the native desktop-window plugin.
bool get mithkaSupportsDesktopVideoWindows =>
    MithkaDesktopVideoWindows.instance.isSupported;

/// Owns independent desktop windows and their host-side resources.
class MithkaDesktopVideoWindows {
  MithkaDesktopVideoWindows._(this._platform);

  static final MithkaDesktopVideoWindows instance = MithkaDesktopVideoWindows._(
    implementation.createDesktopWindowsPlatform(),
  );

  final MithkaDesktopVideoWindowsPlatform _platform;

  bool get isSupported => _platform.isSupported;

  /// Receives recoverable native-window failures.
  ///
  /// Operations still resolve gracefully (`open` returns `null`; commands are
  /// no-ops). When unset, failures are printed only in debug builds.
  MithkaDesktopWindowErrorHandler? get onError => _platform.onError;

  set onError(MithkaDesktopWindowErrorHandler? value) {
    _platform.onError = value;
  }

  /// IDs for windows which completed initialization and were shown.
  Set<int> get activeWindowIds => _platform.activeWindowIds;

  /// Observable native fullscreen state for the current child window.
  ///
  /// It remains false in a main window or on unsupported platforms and follows
  /// both package requests and platform-native fullscreen controls.
  static ValueListenable<bool> get currentWindowFullscreen =>
      instance._platform.currentWindowFullscreen;

  /// Initializes the native-window integration for this Flutter engine.
  ///
  /// The returned arguments are non-null only for a valid child video window.
  /// On unsupported platforms this is a side-effect-free no-op.
  static Future<MithkaDesktopVideoWindowArguments?> initialize(
    List<String> arguments, {
    String windowType = mithkaDesktopVideoWindowType,
  }) => instance._platform.initialize(arguments, windowType: windowType);

  /// Opens another independent player window.
  ///
  /// Multiple calls may run concurrently and each creates an independent
  /// window. [onClosed] is called exactly once when that window closes or when
  /// opening it fails, making it suitable for releasing a retained stream.
  Future<int?> open(
    MithkaDesktopVideoWindowArguments arguments, {
    MithkaDesktopWindowClosed? onClosed,
    Duration timeout = const Duration(seconds: 20),
  }) => _platform.open(arguments, onClosed: onClosed, timeout: timeout);

  /// Configures the current child window using a video-preserving initial size.
  static Future<void> configureCurrentWindow({
    required String title,
    int? videoWidth,
    int? videoHeight,
  }) => instance._platform.configureCurrentWindow(
    title: title,
    videoWidth: videoWidth,
    videoHeight: videoHeight,
  );

  /// Brings a window owned by this host to the front.
  ///
  /// Returns false when the window is unknown or already gone, which is the
  /// caller's signal that the media needs a new window.
  Future<bool> focus(int windowId) => _platform.focus(windowId);

  /// Requests a graceful close of the current independent window.
  static Future<void> closeCurrentWindow() =>
      instance._platform.closeCurrentWindow();

  /// Requests a graceful close of a window owned by the current host.
  Future<void> close(int windowId) => _platform.close(windowId);

  /// Requests a graceful close of every window opened by this host isolate.
  Future<void> closeAll() => _platform.closeAll();

  /// Requests a specific native fullscreen state for the current child window.
  ///
  /// Returns whether the native window reached the requested state. The
  /// desired-state API avoids state drift when a player handles Escape or when
  /// the same command is delivered more than once.
  static Future<bool> setCurrentWindowFullscreen(bool fullscreen) =>
      instance._platform.setCurrentWindowFullscreen(fullscreen);

  /// Enters or leaves native fullscreen for the current child window.
  static Future<void> toggleCurrentWindowFullscreen() =>
      instance._platform.toggleCurrentWindowFullscreen();
}
