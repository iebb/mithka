import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:multi_window_manager/multi_window_manager.dart';

const _defaultWindowType = 'mithka.video';

bool get mithkaSupportsDesktopVideoWindows =>
    !Platform.isAndroid && !Platform.isIOS && !Platform.isFuchsia;

class MithkaDesktopVideoWindowArguments {
  const MithkaDesktopVideoWindowArguments({
    required this.uri,
    required this.title,
    required this.width,
    required this.height,
    required this.muted,
    this.windowType = _defaultWindowType,
  });

  final Uri uri;
  final String title;
  final int? width;
  final int? height;
  final bool muted;
  final String windowType;

  String encode() => jsonEncode({
    'type': windowType,
    'uri': uri.toString(),
    'title': title,
    'width': width,
    'height': height,
    'muted': muted,
  });

  static MithkaDesktopVideoWindowArguments? tryParse(
    String source, {
    String windowType = _defaultWindowType,
  }) {
    if (source.isEmpty) return null;
    try {
      final value = jsonDecode(source);
      if (value is! Map || value['type'] != windowType) return null;
      final uri = Uri.tryParse(value['uri'] as String? ?? '');
      if (uri == null || !uri.hasScheme) return null;
      return MithkaDesktopVideoWindowArguments(
        uri: uri,
        title: value['title'] as String? ?? 'Video',
        width: value['width'] as int?,
        height: value['height'] as int?,
        muted: value['muted'] as bool? ?? false,
        windowType: windowType,
      );
    } catch (_) {
      return null;
    }
  }
}

typedef MithkaDesktopWindowClosed = FutureOr<void> Function();

/// Owns independent desktop windows while allowing a host to retain and clean
/// up resources, such as a loopback video stream, for each child window.
class MithkaDesktopVideoWindows with WindowListener {
  MithkaDesktopVideoWindows._();

  static final MithkaDesktopVideoWindows instance =
      MithkaDesktopVideoWindows._();

  final Map<int, MithkaDesktopWindowClosed> _closeCallbacks = {};
  bool _observing = false;

  static Future<MithkaDesktopVideoWindowArguments?> initialize(
    List<String> arguments, {
    String windowType = _defaultWindowType,
  }) async {
    if (!mithkaSupportsDesktopVideoWindows) return null;
    WidgetsFlutterBinding.ensureInitialized();
    final windowId = arguments.isEmpty ? 0 : int.tryParse(arguments.first) ?? 0;
    if (windowId == 0) {
      await MultiWindowManager.ensureInitialized(0);
    } else {
      await MultiWindowManager.ensureInitializedSecondary(windowId);
    }
    return MithkaDesktopVideoWindowArguments.tryParse(
      windowId > 0 && arguments.length > 1 ? arguments[1] : '',
      windowType: windowType,
    );
  }

  Future<int?> open(
    MithkaDesktopVideoWindowArguments arguments, {
    MithkaDesktopWindowClosed? onClosed,
  }) async {
    if (!mithkaSupportsDesktopVideoWindows) return null;
    final controller = await MultiWindowManager.createWindow([
      arguments.encode(),
    ]);
    if (controller == null) return null;
    if (onClosed != null) _closeCallbacks[controller.id] = onClosed;
    if (!_observing) {
      _observing = true;
      MultiWindowManager.addGlobalListener(this);
    }
    await controller.show();
    return controller.id;
  }

  static Future<void> configureCurrentWindow({
    required String title,
    int? videoWidth,
    int? videoHeight,
  }) async {
    final aspect =
        videoWidth != null &&
            videoHeight != null &&
            videoWidth > 0 &&
            videoHeight > 0
        ? videoWidth / videoHeight
        : 16 / 9;
    const preferredWidth = 880.0;
    final preferredHeight = (preferredWidth / aspect).clamp(420.0, 720.0);
    final window = MultiWindowManager.current;
    await window.setMinimumSize(const Size(420, 280));
    await window.setSize(Size(preferredWidth, preferredHeight));
    await window.setTitle(title);
    await window.center();
  }

  static Future<void> closeCurrentWindow() =>
      MultiWindowManager.current.close();

  static Future<void> toggleCurrentWindowFullscreen() async {
    final window = MultiWindowManager.current;
    await window.setFullScreen(!await window.isFullScreen());
  }

  @override
  void onWindowClose([int? windowId]) {
    if (windowId == null) return;
    final callback = _closeCallbacks.remove(windowId);
    if (callback != null) unawaited(Future<void>.sync(callback));
  }
}
