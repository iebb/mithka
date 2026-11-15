import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Delivers images the iOS runner reads from an image-only paste, such as the
/// keyboard's copied-screenshot suggestion, to the focused composer. Flutter's
/// iOS text field only pastes text, so these never reach the field itself.
abstract final class KeyboardImagePaste {
  static const _channel = MethodChannel('mithka/keyboard_image_paste');
  static final Map<Object, _KeyboardImagePasteTarget> _targets = {};
  static bool _listening = false;

  static void register(
    Object owner, {
    required bool Function() hasFocus,
    required Future<void> Function(Uint8List data, String mimeType) onImage,
  }) {
    _targets[owner] = (hasFocus: hasFocus, onImage: onImage);
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      final arguments = call.arguments;
      if (call.method != 'pasteImage' || arguments is! Map) return false;
      final data = arguments['data'];
      final mimeType = arguments['mimeType'];
      if (data is! Uint8List || data.isEmpty || mimeType is! String) {
        return false;
      }
      return dispatch(data, mimeType);
    });
  }

  static void unregister(Object owner) => _targets.remove(owner);

  /// Hands the image to the composer whose field has focus, if any.
  @visibleForTesting
  static Future<bool> dispatch(Uint8List data, String mimeType) async {
    for (final target in _targets.values) {
      if (!target.hasFocus()) continue;
      await target.onImage(data, mimeType);
      return true;
    }
    return false;
  }
}

typedef _KeyboardImagePasteTarget = ({
  bool Function() hasFocus,
  Future<void> Function(Uint8List data, String mimeType) onImage,
});
