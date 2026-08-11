import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:multi_window_manager/multi_window_manager.dart';

import 'desktop_video_window_arguments.dart';
import 'desktop_video_window_layout.dart';
import 'desktop_video_windows_platform.dart';

MithkaDesktopVideoWindowsPlatform createDesktopWindowsPlatform() =>
    _IoDesktopVideoWindows();

class _IoDesktopVideoWindows
    with WindowListener
    implements MithkaDesktopVideoWindowsPlatform {
  final Map<int, MithkaDesktopWindowClosed> _closeCallbacks = {};
  final Map<int, MultiWindowManager> _controllers = {};
  final Set<int> _activeWindowIds = {};
  final ValueNotifier<bool> _currentWindowFullscreen = ValueNotifier(false);
  final ValueNotifier<int> _currentWindowCloseRevision = ValueNotifier(0);

  Future<void>? _initializing;
  int? _currentWindowId;
  bool _observingGlobal = false;
  bool _observingCurrent = false;
  bool _observingRegistry = false;

  @override
  bool get isSupported =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  @override
  MithkaDesktopWindowErrorHandler? onError;

  @override
  Set<int> get activeWindowIds => Set<int>.unmodifiable(_activeWindowIds);

  @override
  ValueListenable<bool> get currentWindowFullscreen => _currentWindowFullscreen;

  @override
  ValueListenable<int> get currentWindowCloseRevision =>
      _currentWindowCloseRevision;

  @override
  Future<MithkaDesktopVideoWindowArguments?> initialize(
    List<String> arguments, {
    required String windowType,
  }) async {
    if (!isSupported) return null;
    WidgetsFlutterBinding.ensureInitialized();
    final windowId = arguments.isEmpty ? 0 : int.tryParse(arguments.first) ?? 0;
    try {
      await _ensureInitialized(windowId);
    } on Object catch (error, stackTrace) {
      _report('initialize', error, stackTrace);
      return null;
    }
    if (windowId <= 0 || arguments.length < 2) return null;
    return MithkaDesktopVideoWindowArguments.tryParse(
      arguments[1],
      windowType: windowType,
    );
  }

  @override
  Future<int?> open(
    MithkaDesktopVideoWindowArguments arguments, {
    MithkaDesktopWindowClosed? onClosed,
    required Duration timeout,
  }) async {
    if (!isSupported) {
      await _runCloseCallback(onClosed);
      return null;
    }
    if (timeout <= Duration.zero) {
      _report(
        'open',
        ArgumentError.value(timeout, 'timeout', 'must be positive'),
        StackTrace.current,
      );
      await _runCloseCallback(onClosed);
      return null;
    }
    if (!arguments.uri.hasScheme) {
      _report(
        'open',
        ArgumentError.value(
          arguments.uri,
          'arguments.uri',
          'must be an absolute URI',
        ),
        StackTrace.current,
      );
      await _runCloseCallback(onClosed);
      return null;
    }

    MultiWindowManager? controller;
    Future<MultiWindowManager?>? creation;
    var callbackRegistered = false;
    final deadline = DateTime.now().add(timeout);
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await _ensureInitialized(0).timeout(_remaining(deadline));
      final encodedArguments = [arguments.encode()];
      creation = Platform.isLinux
          ? MultiWindowManager.createWindowOrReuse(args: encodedArguments)
          : MultiWindowManager.createWindow(encodedArguments);
      controller = await creation.timeout(_remaining(deadline));
      if (controller == null) {
        throw StateError('The native window manager returned no window ID.');
      }
      if (controller.id <= 0) {
        // Never issue a release command for ID zero: that is the main window.
        controller = null;
        throw StateError('The native window manager returned an invalid ID.');
      }

      final windowId = controller.id;
      _controllers[windowId] = controller;
      if (onClosed != null) {
        _closeCallbacks[windowId] = onClosed;
        callbackRegistered = true;
      }

      if (!Platform.isLinux) {
        try {
          await controller
              .waitUntilReadyToShow(
                WindowOptions(
                  size: preferredDesktopVideoWindowSize(
                    arguments.width,
                    arguments.height,
                  ),
                  minimumSize: desktopVideoMinimumWindowSize,
                  center: true,
                  title: MithkaDesktopVideoWindowArguments.normalizeTitle(
                    arguments.title,
                  ),
                ),
              )
              .timeout(_remaining(deadline));
        } on Object catch (error, stackTrace) {
          // A window manager may reject optional positioning while still
          // supporting a fully usable native window (for example, a tiler).
          _report('configureWindow', error, stackTrace);
        }
        if (!_controllers.containsKey(windowId)) {
          throw StateError('Window $windowId closed during startup.');
        }
        await controller.show().timeout(_remaining(deadline));
      } else {
        // ReusableWindow owns configuration/show on Linux. Wait for that child
        // lifecycle to finish so a successful result means a visible player,
        // not merely an allocated hidden engine.
        await _waitUntilVisible(controller, deadline);
      }
      if (!_controllers.containsKey(windowId)) {
        throw StateError('Window $windowId closed during startup.');
      }
      _activeWindowIds.add(windowId);
      return windowId;
    } on Object catch (error, stackTrace) {
      _report('open', error, stackTrace);
      if (controller != null) {
        await _releaseFailedWindow(controller);
        await _finishWindow(controller.id);
        if (!callbackRegistered) await _runCloseCallback(onClosed);
      } else {
        if (error is TimeoutException && creation != null) {
          unawaited(_releaseLateWindow(creation));
        }
        await _runCloseCallback(onClosed);
      }
      return null;
    }
  }

  @override
  Future<void> configureCurrentWindow({
    required String title,
    int? videoWidth,
    int? videoHeight,
  }) async {
    if (!isSupported || _currentWindowId == null || _currentWindowId == 0) {
      return;
    }
    try {
      final window = MultiWindowManager.current;
      await window.setMinimumSize(desktopVideoMinimumWindowSize);
      await window.setSize(
        preferredDesktopVideoWindowSize(videoWidth, videoHeight),
      );
      await window.setTitle(
        MithkaDesktopVideoWindowArguments.normalizeTitle(title),
      );
      await window.center();
    } on Object catch (error, stackTrace) {
      _report('configureCurrentWindow', error, stackTrace);
    }
  }

  @override
  Future<bool> focus(int windowId) async {
    if (!isSupported || windowId <= 0) return false;
    final controller = _controllers[windowId];
    if (controller == null || !_activeWindowIds.contains(windowId)) {
      return false;
    }
    try {
      if (!await controller.isVisible()) await controller.show();
      if (await controller.isMinimized()) await controller.restore();
      await controller.focus();
      return true;
    } on Object catch (error, stackTrace) {
      _report('focus', error, stackTrace);
      return false;
    }
  }

  @override
  Future<void> focusCurrentWindow() async {
    if (!isSupported || _currentWindowId == null || _currentWindowId == 0) {
      return;
    }
    try {
      final window = MultiWindowManager.current;
      if (!await window.isVisible()) await window.show();
      if (await window.isMinimized()) await window.restore();
      await window.focus();
    } on Object catch (error, stackTrace) {
      _report('focusCurrentWindow', error, stackTrace);
    }
  }

  @override
  Future<void> hideCurrentWindow() async {
    if (!isSupported || _currentWindowId == null || _currentWindowId == 0) {
      return;
    }
    try {
      await MultiWindowManager.current.hide();
    } on Object catch (error, stackTrace) {
      _report('hideCurrentWindow', error, stackTrace);
    }
  }

  @override
  Future<void> closeCurrentWindow() async {
    if (!isSupported || _currentWindowId == null || _currentWindowId == 0) {
      return;
    }
    try {
      await MultiWindowManager.current.close();
    } on Object catch (error, stackTrace) {
      _report('closeCurrentWindow', error, stackTrace);
    }
  }

  @override
  Future<void> close(int windowId) async {
    if (!isSupported || windowId <= 0) return;
    final controller = _controllers[windowId];
    if (controller == null) return;
    try {
      await controller.close();
    } on Object catch (error, stackTrace) {
      _report('close', error, stackTrace);
    }
  }

  @override
  Future<void> closeAll() =>
      Future.wait(List<int>.of(_controllers.keys, growable: false).map(close));

  @override
  Future<bool> setCurrentWindowFullscreen(bool fullscreen) async {
    if (!isSupported || _currentWindowId == null || _currentWindowId == 0) {
      return false;
    }
    try {
      final window = MultiWindowManager.current;
      if (await window.isFullScreen() != fullscreen) {
        await window.setFullScreen(fullscreen);
      }
      final current = Platform.isMacOS
          ? await _waitForFullscreenState(window, fullscreen)
          : await window.isFullScreen();
      _currentWindowFullscreen.value = current;
      return current == fullscreen;
    } on Object catch (error, stackTrace) {
      _report('setCurrentWindowFullscreen', error, stackTrace);
      return false;
    }
  }

  @override
  Future<void> toggleCurrentWindowFullscreen() async {
    if (!isSupported || _currentWindowId == null || _currentWindowId == 0) {
      return;
    }
    try {
      final window = MultiWindowManager.current;
      final target = !await window.isFullScreen();
      await window.setFullScreen(target);
      _currentWindowFullscreen.value = Platform.isMacOS
          ? await _waitForFullscreenState(window, target)
          : await window.isFullScreen();
    } on Object catch (error, stackTrace) {
      _report('toggleCurrentWindowFullscreen', error, stackTrace);
    }
  }

  Future<bool> _waitForFullscreenState(
    MultiWindowManager window,
    bool expected,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    var current = await window.isFullScreen();
    while (current != expected && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      current = await window.isFullScreen();
    }
    return current;
  }

  Future<void> _ensureInitialized(int windowId) async {
    if (_currentWindowId != null) {
      if (_currentWindowId != windowId) {
        throw StateError(
          'This Flutter engine is already attached to window '
          '$_currentWindowId, not $windowId.',
        );
      }
      return;
    }
    final pending = _initializing;
    if (pending != null) return pending;

    final future = _performInitialization(windowId);
    _initializing = future;
    try {
      await future;
      _currentWindowId = windowId;
    } on Object {
      if (identical(_initializing, future)) _initializing = null;
      rethrow;
    }
  }

  Future<void> _performInitialization(int windowId) async {
    if (windowId == 0) {
      await MultiWindowManager.ensureInitialized(0);
      if (!_observingGlobal) {
        MultiWindowManager.addGlobalListener(this);
        _observingGlobal = true;
      }
      if (!_observingRegistry) {
        MultiWindowManager.current.activeWindows.addListener(
          _handleActiveWindowsChanged,
        );
        _observingRegistry = true;
      }
    } else {
      if (Platform.isMacOS) {
        // multi_window_manager's macOS secondary initializer installs a
        // lifecycle observer that rewrites `hidden` to `inactive` from inside
        // the `hidden` notification. Observers registered earlier finish the
        // outer notification in `hidden`, while the binding itself ends in
        // `inactive`; the next focus event then reaches EditableText as the
        // invalid `hidden -> resumed` transition. macOS does not reuse child
        // engines here, so initialize the concrete window directly and let
        // Flutter synthesize the normal hidden/inactive/resumed sequence.
        await MultiWindowManager.ensureInitialized(windowId);
        WidgetsBinding.instance.addObserver(
          _DeferredMacOSSecondaryWindowRenderFix(),
        );
      } else {
        await MultiWindowManager.ensureInitializedSecondary(
          windowId,
          isEnabledReuse: Platform.isLinux,
        );
      }
      if (!_observingCurrent) {
        MultiWindowManager.current.addListener(this);
        _observingCurrent = true;
      }
      try {
        _currentWindowFullscreen.value = await MultiWindowManager.current
            .isFullScreen();
      } on Object catch (error, stackTrace) {
        _report('readCurrentWindowFullscreen', error, stackTrace);
      }
    }
  }

  @override
  void onWindowEnterFullScreen([int? windowId]) {
    if (_currentWindowId != null && _currentWindowId! > 0 && windowId == null) {
      _currentWindowFullscreen.value = true;
    }
  }

  @override
  void onWindowLeaveFullScreen([int? windowId]) {
    if (_currentWindowId != null && _currentWindowId! > 0 && windowId == null) {
      _currentWindowFullscreen.value = false;
    }
  }

  @override
  void onWindowClose([int? windowId]) {
    if (windowId == null && (_currentWindowId ?? 0) > 0) {
      _currentWindowCloseRevision.value++;
      return;
    }
    if (windowId != null) unawaited(_finishWindow(windowId));
  }

  void _handleActiveWindowsChanged() {
    final nativeActiveIds = MultiWindowManager.current.activeWindows.value;
    for (final windowId in List<int>.of(_controllers.keys, growable: false)) {
      if (!nativeActiveIds.contains(windowId)) {
        // Linux reuse-close is intentionally internal to multi_window_manager,
        // but its active-window registry is public and reactive. Releasing the
        // callback here closes the old URI stream while retaining the hidden
        // Flutter engine for a later createWindowOrReuse call.
        unawaited(_finishWindow(windowId));
      }
    }
  }

  Future<void> _releaseFailedWindow(MultiWindowManager controller) async {
    try {
      if (Platform.isLinux) {
        // Linux Flutter engines are retained by multi_window_manager because
        // repeatedly destroying GTK FlView/FlEngine instances is unsafe.
        await controller.close().timeout(const Duration(seconds: 3));
      } else {
        await controller.destroy().timeout(const Duration(seconds: 3));
      }
    } on Object catch (error, stackTrace) {
      _report('releaseFailedWindow', error, stackTrace);
    }
  }

  Future<void> _waitUntilVisible(
    MultiWindowManager controller,
    DateTime deadline,
  ) async {
    while (true) {
      if (!_controllers.containsKey(controller.id)) {
        throw StateError('Window ${controller.id} closed during startup.');
      }
      if (await controller.isVisible().timeout(_remaining(deadline))) return;
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw TimeoutException(
          'The reusable video window did not become visible.',
        );
      }
      await Future<void>.delayed(
        remaining < const Duration(milliseconds: 25)
            ? remaining
            : const Duration(milliseconds: 25),
      );
    }
  }

  static Duration _remaining(DateTime deadline) {
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      throw TimeoutException('The desktop window operation timed out.');
    }
    return remaining;
  }

  Future<void> _releaseLateWindow(Future<MultiWindowManager?> creation) async {
    try {
      final controller = await creation;
      if (controller != null) await _releaseFailedWindow(controller);
    } on Object {
      // The original open failure was already reported to the caller.
    }
  }

  Future<void> _finishWindow(int windowId) async {
    _activeWindowIds.remove(windowId);
    _controllers.remove(windowId);
    final callback = _closeCallbacks.remove(windowId);
    await _runCloseCallback(callback);
  }

  Future<void> _runCloseCallback(MithkaDesktopWindowClosed? callback) async {
    if (callback == null) return;
    try {
      await callback();
    } on Object catch (error, stackTrace) {
      _report('onClosed', error, stackTrace);
    }
  }

  void _report(String operation, Object cause, StackTrace stackTrace) {
    final error = MithkaDesktopWindowException(operation, cause);
    final handler = onError;
    if (handler != null) {
      try {
        handler(error, stackTrace);
        return;
      } on Object catch (handlerError) {
        assert(() {
          debugPrint('Desktop window error handler failed: $handlerError');
          return true;
        }());
      }
    }
    assert(() {
      debugPrint('$error\n$stackTrace');
      return true;
    }());
  }
}

/// Keeps macOS child engines rendering after they are hidden without mutating
/// lifecycle state recursively from inside the `hidden` notification.
///
/// Deferring the synthetic `inactive` transition lets every existing observer
/// finish `hidden` first. A later native `resumed` event is consequently valid
/// for both the binding and widgets such as [EditableText].
class _DeferredMacOSSecondaryWindowRenderFix extends WidgetsBindingObserver {
  bool _transitionScheduled = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.hidden || _transitionScheduled) return;
    _transitionScheduled = true;
    scheduleMicrotask(() {
      _transitionScheduled = false;
      final binding = SchedulerBinding.instance;
      if (binding.lifecycleState != AppLifecycleState.hidden) return;
      // ignore: invalid_use_of_protected_member
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    });
  }
}
