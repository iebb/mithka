import 'package:flutter/widgets.dart';
import 'package:multi_window_manager/multi_window_manager.dart';

/// Message actions a desktop video window asks the main window to run.
///
/// The video window's engine has no TDLib client, so saving the original file
/// and forwarding the message both run in the main window that opened it.
enum DesktopVideoWindowAction { capabilities, save, share }

const _actionMethod = 'mithka.video-window.action';

/// The main window's engine; video windows are only opened from there.
const _mainWindowId = 0;

/// Which actions the main window offers for one video window.
@immutable
class DesktopVideoWindowCapabilities {
  const DesktopVideoWindowCapabilities({
    required this.canSave,
    required this.canShare,
  });

  static const none = DesktopVideoWindowCapabilities(
    canSave: false,
    canShare: false,
  );

  final bool canSave;
  final bool canShare;

  bool get any => canSave || canShare;

  Map<String, Object?> toJson() => {'save': canSave, 'share': canShare};

  static DesktopVideoWindowCapabilities fromJson(Object? source) {
    if (source is! Map) return none;
    return DesktopVideoWindowCapabilities(
      canSave: source['save'] == true,
      canShare: source['share'] == true,
    );
  }
}

/// The outcome of a save or share request, with an already-localized message
/// for the video window to show, if any.
@immutable
class DesktopVideoWindowActionResult {
  const DesktopVideoWindowActionResult({required this.ok, this.message});

  static const failed = DesktopVideoWindowActionResult(ok: false);

  final bool ok;
  final String? message;

  Map<String, Object?> toJson() => {'ok': ok, 'message': message};

  static DesktopVideoWindowActionResult fromJson(Object? source) {
    if (source is! Map) return failed;
    final message = source['message'];
    return DesktopVideoWindowActionResult(
      ok: source['ok'] == true,
      message: message is String && message.trim().isNotEmpty ? message : null,
    );
  }
}

/// Answers one request from video window [fromWindowId]; the result must be
/// a JSON-like map.
typedef DesktopVideoWindowActionHandler =
    Future<Map<String, Object?>?> Function(
      int fromWindowId,
      DesktopVideoWindowAction action,
    );

final _bridge = _DesktopVideoWindowActionBridge();

/// Routes video-window action requests to [handler] in the main engine.
void setDesktopVideoWindowActionHandler(
  DesktopVideoWindowActionHandler handler,
) => _bridge.attach(handler);

/// Asks the main window what this video window may offer. Returns
/// [DesktopVideoWindowCapabilities.none] when the main window cannot answer.
Future<DesktopVideoWindowCapabilities>
requestDesktopVideoWindowCapabilities() async =>
    DesktopVideoWindowCapabilities.fromJson(
      await _invoke(DesktopVideoWindowAction.capabilities),
    );

/// Asks the main window to save or share this window's video.
Future<DesktopVideoWindowActionResult> requestDesktopVideoWindowAction(
  DesktopVideoWindowAction action,
) async {
  assert(action != DesktopVideoWindowAction.capabilities);
  return DesktopVideoWindowActionResult.fromJson(await _invoke(action));
}

/// Raises the window this engine draws.
Future<void> focusCurrentDesktopWindow() async {
  try {
    final window = MultiWindowManager.current;
    if (!await window.isVisible()) await window.show();
    if (await window.isMinimized()) await window.restore();
    await window.focus();
  } on Object {
    // A window that is closing has nothing left to raise.
  }
}

Future<Object?> _invoke(DesktopVideoWindowAction action) async {
  try {
    return await MultiWindowManager.current.invokeMethodToWindow(
      _mainWindowId,
      _actionMethod,
      action.name,
    );
  } on Object {
    // The main window may be gone, or this platform has no multi-window IPC.
    return null;
  }
}

class _DesktopVideoWindowActionBridge with WindowListener {
  DesktopVideoWindowActionHandler? _handler;
  bool _attached = false;

  void attach(DesktopVideoWindowActionHandler handler) {
    _handler = handler;
    if (_attached) return;
    try {
      WidgetsFlutterBinding.ensureInitialized();
      MultiWindowManager.current.addListener(this);
      _attached = true;
    } on Object {
      // Native multi-window support is unavailable.
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
    final action = DesktopVideoWindowAction.values
        .where((candidate) => candidate.name == arguments)
        .firstOrNull;
    if (handler == null || action == null || fromWindowId <= 0) return null;
    return handler(fromWindowId, action);
  }
}
