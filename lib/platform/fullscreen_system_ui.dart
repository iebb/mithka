import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Hides Android system bars for the visible fullscreen player. Ownership is
/// shared while queue entries overlap during replacement, so disposing the old
/// player cannot restore bars over the new one.
class FullscreenSystemUi extends StatefulWidget {
  const FullscreenSystemUi({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  State<FullscreenSystemUi> createState() => _FullscreenSystemUiState();
}

class _FullscreenSystemUiState extends State<FullscreenSystemUi> {
  static const _channel = MethodChannel('mithka/fullscreen_system_ui');
  static final _owners = <_FullscreenSystemUiState>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant FullscreenSystemUi oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() => _setActive(
    widget.enabled &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        (ModalRoute.of(context)?.isCurrent ?? true),
  );

  void _setActive(bool active) {
    final wasEnabled = _owners.isNotEmpty;
    if (active) {
      _owners.add(this);
    } else {
      _owners.remove(this);
    }
    if (wasEnabled != _owners.isNotEmpty) {
      unawaited(_apply(_owners.isNotEmpty));
    }
  }

  static Future<void> _apply(bool enabled) async {
    try {
      // WindowInsetsController supports immersive playback on Android 16 too,
      // where Flutter's legacy SystemUiMode fullscreen flags are ignored.
      await _channel.invokeMethod<void>('setFullscreen', enabled);
    } on MissingPluginException {
      // Widget-only hosts do not own an Android activity.
    } on PlatformException {
      // A disappearing activity must not interrupt playback teardown.
    }
  }

  @override
  void dispose() {
    _setActive(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
