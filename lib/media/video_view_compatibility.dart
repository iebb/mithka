import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

VideoViewType _preferredVideoViewType = VideoViewType.textureView;

/// MediaTek's AVC decoder on the Nothing A142 returns correctly sized frames
/// through a direct Android view, but corrupts them when its graphic buffers
/// are imported through Flutter's texture-backed SurfaceProducer. Keep the
/// workaround exact so other Android devices retain the cheaper texture path.
@visibleForTesting
bool needsDirectVideoSurface({
  required String? manufacturer,
  required String? model,
  required String? hardware,
}) {
  final normalizedManufacturer = manufacturer?.trim().toLowerCase();
  final normalizedModel = model?.trim().toLowerCase();
  final normalizedHardware = hardware?.trim().toLowerCase();
  return normalizedManufacturer == 'nothing' &&
      normalizedModel == 'a142' &&
      normalizedHardware == 'mt6886';
}

/// The video surface selected once during application bootstrap.
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
    final info = await const MethodChannel(
      'mithka/app_info',
    ).invokeMapMethod<String, Object?>('info');
    if (needsDirectVideoSurface(
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
