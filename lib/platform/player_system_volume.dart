import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android media-stream volume used by fullscreen video gestures.
///
/// Other platforms retain their existing per-player volume behavior. Android
/// values are read back after each write because the media stream uses a
/// device-specific number of discrete steps.
class PlayerSystemVolume {
  PlayerSystemVolume._();

  static const _channel = MethodChannel('mithka/system_media_volume');

  static bool get _supportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<PlayerSystemVolumeState?> current() async {
    if (!_supportedPlatform) return null;
    try {
      return PlayerSystemVolumeState.fromMap(
        await _channel.invokeMapMethod<String, dynamic>('get'),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<PlayerSystemVolumeState?> setFraction(double value) async {
    if (!_supportedPlatform) return null;
    try {
      return PlayerSystemVolumeState.fromMap(
        await _channel.invokeMapMethod<String, dynamic>(
          'set',
          value.clamp(0.0, 1.0),
        ),
      );
    } catch (_) {
      return null;
    }
  }
}

@immutable
class PlayerSystemVolumeState {
  const PlayerSystemVolumeState({
    required this.index,
    required this.minimum,
    required this.maximum,
    required this.fixed,
  });

  final int index;
  final int minimum;
  final int maximum;
  final bool fixed;

  double get fraction =>
      maximum <= 0 ? 0 : (index / maximum).clamp(0.0, 1.0).toDouble();

  bool get canSet => !fixed && maximum > 0 && minimum <= maximum;

  static PlayerSystemVolumeState? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final index = map['index'];
    final minimum = map['minimum'];
    final maximum = map['maximum'];
    final fixed = map['fixed'];
    if (index is! int ||
        minimum is! int ||
        maximum is! int ||
        fixed is! bool ||
        maximum <= 0 ||
        minimum < 0 ||
        minimum > maximum ||
        index < minimum ||
        index > maximum) {
      return null;
    }
    return PlayerSystemVolumeState(
      index: index,
      minimum: minimum,
      maximum: maximum,
      fixed: fixed,
    );
  }
}
