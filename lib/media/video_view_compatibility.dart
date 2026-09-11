import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../chat/video_playback_preferences.dart';

VideoViewType _preferredVideoViewType = VideoViewType.textureView;

/// Avoid the texture-backed SurfaceProducer for Android 14 and newer, where
/// video frame corruption has been reported beyond the original Nothing A142
/// workaround. Corrupted frames can arrive without a decoder error, so choose
/// the direct surface before playback rather than relying on error recovery.
/// Retain the device workaround on older Android releases as well.
@visibleForTesting
bool needsDirectVideoSurface({
  int? sdkInt,
  required String? manufacturer,
  required String? model,
  required String? hardware,
}) {
  if (sdkInt != null && sdkInt >= 34) return true;

  final normalizedManufacturer = manufacturer?.trim().toLowerCase();
  final normalizedModel = model?.trim().toLowerCase();
  final normalizedHardware = hardware?.trim().toLowerCase();
  return normalizedManufacturer == 'nothing' &&
      normalizedModel == 'a142' &&
      normalizedHardware == 'mt6886';
}

/// The video surface selected at bootstrap and after compatibility changes.
VideoViewType get preferredCompatibleVideoViewType => _preferredVideoViewType;

@visibleForTesting
void resetCompatibleVideoViewType() {
  _preferredVideoViewType = VideoViewType.textureView;
}

/// Selects a video surface compatible with the current device's decoder.
///
/// This runs before the widget tree is mounted so individual player creation
/// remains synchronous up to video_player's own initialization boundary.
Future<void> initializeCompatibleVideoViewType() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    _preferredVideoViewType = VideoViewType.textureView;
    return;
  }
  try {
    final preferences = await VideoPlaybackPreferences.load();
    if (!preferences.androidVideoCompatibility) {
      _preferredVideoViewType = VideoViewType.textureView;
      return;
    }
    final info = await const MethodChannel(
      'mithka/app_info',
    ).invokeMapMethod<String, Object?>('info');
    if (needsDirectVideoSurface(
      sdkInt: info?['sdkInt'] as int?,
      manufacturer: info?['manufacturer'] as String?,
      model: info?['model'] as String?,
      hardware: info?['hardware'] as String?,
    )) {
      _preferredVideoViewType = VideoViewType.platformView;
      return;
    }
  } catch (_) {
    // Preserve the portable texture path when device information is absent.
  }
  _preferredVideoViewType = VideoViewType.textureView;
}
