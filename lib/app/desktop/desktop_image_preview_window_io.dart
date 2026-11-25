import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:multi_window_manager/multi_window_manager.dart';

import 'desktop_image_preview_window_models.dart';

const _pathReadyMethod = 'mithka.image-preview.path-ready';
const _brightnessChangedMethod = 'mithka.image-preview.brightness-changed';
const _actionMethod = 'mithka.image-preview.action';
const _windowSize = Size(860, 640);
const _minimumWindowSize = Size(420, 320);

bool get supportsDesktopImagePreviewWindows =>
    Platform.isLinux || Platform.isMacOS || Platform.isWindows;

final _childPathBridge = _DesktopImagePreviewChildPathBridge();
final _originActionBridge = _DesktopImagePreviewOriginActionBridge();

Stream<DesktopImagePreviewPathUpdate> get desktopImagePreviewPathUpdates {
  _childPathBridge.attach();
  return _childPathBridge.paths;
}

Stream<bool> get desktopImagePreviewBrightnessUpdates {
  _childPathBridge.attach();
  return _childPathBridge.brightness;
}

Future<void> broadcastDesktopImagePreviewBrightness(bool dark) async {
  if (!supportsDesktopImagePreviewWindows ||
      MultiWindowManager.current.id != 0) {
    return;
  }
  try {
    final active = await MultiWindowManager.current.getActiveWindowIds();
    for (final windowId in active.where((id) => id > 0)) {
      try {
        await MultiWindowManager.current.invokeMethodToWindow(
          windowId,
          _brightnessChangedMethod,
          dark,
        );
      } on Object {
        // Other child-window types do not subscribe to this event.
      }
    }
  } on Object {
    // Native multi-window support can disappear during app termination.
  }
}

Future<int?> openDesktopImagePreviewWindow(
  DesktopImagePreviewWindowArguments arguments,
) async {
  if (!supportsDesktopImagePreviewWindows) return null;
  MultiWindowManager? window;
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await MultiWindowManager.ensureInitialized(0);
    window = await MultiWindowManager.createWindow([arguments.encode()]);
    if (window == null || window.id <= 0) return null;
    await window.waitUntilReadyToShow(
      WindowOptions(
        size: _windowSize,
        minimumSize: _minimumWindowSize,
        center: true,
        alwaysOnTop: false,
        backgroundColor: arguments.dark
            ? const Color(0xFF0C0D0F)
            : const Color(0xFFF0F1F3),
        skipTaskbar: false,
        title: arguments.title,
        titleBarStyle: TitleBarStyle.normal,
        windowButtonVisibility: true,
      ),
    );
    await window.show();
    await window.focus();
    return window.id;
  } on Object {
    if (window != null && window.id > 0) {
      try {
        await window.close();
      } on Object {
        // The native child may already have closed during startup.
      }
    }
    return null;
  }
}

/// Raises an open preview window. Returns false when it is already gone, which
/// tells the caller the image needs a new window.
Future<bool> focusDesktopImagePreviewWindow(int windowId) async {
  if (!supportsDesktopImagePreviewWindows || windowId <= 0) return false;
  try {
    final active = await MultiWindowManager.current.getActiveWindowIds();
    if (!active.contains(windowId)) return false;
    final window = MultiWindowManager.fromWindowId(windowId);
    if (!await window.isVisible()) await window.show();
    if (await window.isMinimized()) await window.restore();
    await window.focus();
    return true;
  } on Object {
    return false;
  }
}

Future<void> publishDesktopImagePreviewPath(
  int windowId,
  int index,
  String path,
) async {
  final safePath = normalizeDesktopImagePath(path);
  if (windowId <= 0 || index < 0 || safePath == null) return;
  try {
    await MultiWindowManager.current.invokeMethodToWindow(
      windowId,
      _pathReadyMethod,
      DesktopImagePreviewPathUpdate(index: index, path: safePath).toJson(),
    );
  } on Object {
    // The preview may have been closed while its image was downloading.
  }
}

Future<void> closeCurrentDesktopImagePreviewWindow() async {
  if (!supportsDesktopImagePreviewWindows) return;
  await MultiWindowManager.current.close();
}

/// The id of the window this engine draws, which a preview sends its message
/// actions back to. Null when native multi-window support is unavailable.
Future<int?> currentDesktopImagePreviewOriginWindowId() async {
  if (!supportsDesktopImagePreviewWindows) return null;
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await MultiWindowManager.ensureInitialized(0);
    return MultiWindowManager.current.id;
  } on Object {
    return null;
  }
}

Future<Set<int>> activeDesktopImagePreviewWindowIds() async {
  try {
    return (await MultiWindowManager.current.getActiveWindowIds()).toSet();
  } on Object {
    return const {};
  }
}

/// Routes action requests from preview windows to [handler] in this engine.
void setDesktopImagePreviewActionHandler(
  DesktopImagePreviewActionHandler handler,
) {
  _originActionBridge.attach(handler);
}

/// Asks the opener in [originWindowId] to run [request]. True once it ran.
Future<bool> requestDesktopImagePreviewAction(
  int originWindowId,
  DesktopImagePreviewActionRequest request,
) async {
  if (!supportsDesktopImagePreviewWindows || originWindowId < 0) return false;
  try {
    final result = await MultiWindowManager.current.invokeMethodToWindow(
      originWindowId,
      _actionMethod,
      request.toJson(),
    );
    return result == true;
  } on Object {
    // The opener may have closed while the preview stayed up.
    return false;
  }
}

/// Raises this engine's own window, so a jump to a message lands in view.
Future<void> focusCurrentDesktopImagePreviewOrigin() async {
  if (!supportsDesktopImagePreviewWindows) return;
  try {
    final window = MultiWindowManager.current;
    if (!await window.isVisible()) await window.show();
    if (await window.isMinimized()) await window.restore();
    await window.focus();
  } on Object {
    // A window that is closing has nothing left to raise.
  }
}

void detachDesktopImagePreviewBridgeIfIdle() {
  _childPathBridge.detachIfIdle();
}

class _DesktopImagePreviewChildPathBridge with WindowListener {
  final StreamController<DesktopImagePreviewPathUpdate> _paths =
      StreamController.broadcast();
  final StreamController<bool> _brightness = StreamController.broadcast();
  bool _attached = false;

  Stream<DesktopImagePreviewPathUpdate> get paths => _paths.stream;
  Stream<bool> get brightness => _brightness.stream;

  void attach() {
    if (_attached) return;
    try {
      final window = MultiWindowManager.current;
      if (window.id <= 0) return;
      window.addListener(this);
      _attached = true;
    } on Object {
      // Widget tests and early startup can build before native window
      // registration. The child process calls attach again when subscribing.
    }
  }

  void detachIfIdle() {
    if (!_attached || _paths.hasListener || _brightness.hasListener) return;
    try {
      MultiWindowManager.current.removeListener(this);
    } on Object {
      // Ignore teardown races if the native window is already gone.
    } finally {
      _attached = false;
    }
  }

  @override
  Future<dynamic> onEventFromWindow(
    String eventName,
    int fromWindowId,
    dynamic arguments,
  ) async {
    if (eventName == _brightnessChangedMethod &&
        fromWindowId == 0 &&
        arguments is bool) {
      _brightness.add(arguments);
      return true;
    }
    if (eventName != _pathReadyMethod || fromWindowId < 0) return null;
    final update = DesktopImagePreviewPathUpdate.tryParse(arguments);
    if (update != null) _paths.add(update);
    return update != null;
  }
}

class _DesktopImagePreviewOriginActionBridge with WindowListener {
  DesktopImagePreviewActionHandler? _handler;
  bool _attached = false;

  void attach(DesktopImagePreviewActionHandler handler) {
    _handler = handler;
    if (_attached) return;
    try {
      MultiWindowManager.current.addListener(this);
      _attached = true;
    } on Object {
      // Native multi-window support is unavailable; previews stay in-app.
    }
  }

  @override
  Future<dynamic> onEventFromWindow(
    String eventName,
    int fromWindowId,
    dynamic arguments,
  ) async {
    // Other window types share this listener list; leave their events alone.
    if (eventName != _actionMethod) return null;
    final handler = _handler;
    final request = DesktopImagePreviewActionRequest.tryParse(arguments);
    if (handler == null || request == null || fromWindowId <= 0) return false;
    return handler(fromWindowId, request);
  }
}
