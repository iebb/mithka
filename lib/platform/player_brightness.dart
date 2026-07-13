import 'package:flutter/services.dart';

/// Brightness control used by fullscreen video gestures.
class PlayerBrightness {
  PlayerBrightness._();

  static const _channel = MethodChannel('mithka/player_brightness');

  static Future<double?> current() async {
    try {
      return await _channel.invokeMethod<double>('get');
    } catch (_) {
      return null;
    }
  }

  static Future<void> set(double value) async {
    try {
      await _channel.invokeMethod<void>('set', value.clamp(0.01, 1.0));
    } catch (_) {
      // Brightness gestures are best-effort on unsupported platforms.
    }
  }
}
