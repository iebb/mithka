import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

enum CameraPermissionAccess { granted, denied, blocked }

/// Runtime camera permission used before Android camera-backed views start.
///
/// Camera plugins still retain their own permission checks. This explicit gate
/// prevents an Android scanner from being mounted while the system permission
/// is unresolved and gives the app a recoverable denied state.
abstract interface class CameraPermissionGateway {
  Future<CameraPermissionAccess> check();

  Future<CameraPermissionAccess> request();

  Future<bool> openSettings();
}

class SystemCameraPermissionGateway implements CameraPermissionGateway {
  const SystemCameraPermissionGateway();

  bool get _requiresExplicitGate =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<CameraPermissionAccess> check() async {
    if (!_requiresExplicitGate) return CameraPermissionAccess.granted;
    return cameraPermissionAccessFromStatus(await Permission.camera.status);
  }

  @override
  Future<CameraPermissionAccess> request() async {
    if (!_requiresExplicitGate) return CameraPermissionAccess.granted;
    final current = await Permission.camera.status;
    final access = cameraPermissionAccessFromStatus(current);
    if (access != CameraPermissionAccess.denied) return access;
    return cameraPermissionAccessFromStatus(await Permission.camera.request());
  }

  @override
  Future<bool> openSettings() => openAppSettings();
}

@visibleForTesting
CameraPermissionAccess cameraPermissionAccessFromStatus(
  PermissionStatus status,
) {
  if (status.isGranted) return CameraPermissionAccess.granted;
  if (status.isPermanentlyDenied || status.isRestricted) {
    return CameraPermissionAccess.blocked;
  }
  return CameraPermissionAccess.denied;
}
