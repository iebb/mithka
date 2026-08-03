import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:screen_capturer/screen_capturer.dart';

enum DesktopScreenshotPlatform { macOS, windows, linux, unsupported }

typedef DesktopScreenshotPermissionCheck = Future<bool> Function();
typedef DesktopScreenshotPermissionRequest = Future<void> Function();
typedef DesktopScreenshotRegionCapture =
    Future<bool> Function(String imagePath);
typedef DesktopScreenshotTemporaryDirectoryProvider =
    Future<Directory> Function();

/// Captures a user-selected desktop region into a verified temporary PNG.
///
/// The implementation deliberately goes through [screenCapturer] instead of
/// launching operating-system commands. That keeps the native region selector
/// and permission flow consistent for toolbar and keyboard-shortcut callers.
class DesktopScreenshotService {
  DesktopScreenshotService({
    DesktopScreenshotPlatform? platform,
    this.permissionCheck = _isAccessAllowed,
    this.permissionRequest = _requestAccess,
    this.regionCapture = _captureRegion,
    this.temporaryDirectoryProvider = getTemporaryDirectory,
    this.clock = DateTime.now,
  }) : platform = platform ?? currentPlatform;

  final DesktopScreenshotPlatform platform;
  final DesktopScreenshotPermissionCheck permissionCheck;
  final DesktopScreenshotPermissionRequest permissionRequest;
  final DesktopScreenshotRegionCapture regionCapture;
  final DesktopScreenshotTemporaryDirectoryProvider temporaryDirectoryProvider;
  final DateTime Function() clock;

  static DesktopScreenshotPlatform get currentPlatform {
    if (Platform.isMacOS) return DesktopScreenshotPlatform.macOS;
    if (Platform.isWindows) return DesktopScreenshotPlatform.windows;
    if (Platform.isLinux) return DesktopScreenshotPlatform.linux;
    return DesktopScreenshotPlatform.unsupported;
  }

  static Future<String?> captureInteractiveRegion() =>
      DesktopScreenshotService().capture();

  Future<String?> capture() async {
    if (platform == DesktopScreenshotPlatform.unsupported) return null;
    File? destination;
    try {
      if (platform == DesktopScreenshotPlatform.macOS &&
          !await _ensureMacOSAccess()) {
        return null;
      }
      final directory = await temporaryDirectoryProvider();
      await directory.create(recursive: true);
      destination = File(
        '${directory.path}${Platform.pathSeparator}'
        'mithka-screenshot-${clock().microsecondsSinceEpoch}.png',
      );
      await _deleteIfPresent(destination);
      final captured = await regionCapture(destination.path);
      if (!captured || !await _isUsable(destination)) {
        await _deleteIfPresent(destination);
        return null;
      }
      return destination.path;
    } catch (_) {
      // Cancellation, denied access, and native picker failures are all safe
      // no-op outcomes for the composer.
      if (destination != null) await _deleteIfPresent(destination);
      return null;
    }
  }

  Future<bool> _ensureMacOSAccess() async {
    if (await permissionCheck()) return true;
    await permissionRequest();
    return permissionCheck();
  }

  static Future<bool> _isAccessAllowed() =>
      ScreenCapturer.instance.isAccessAllowed();

  static Future<void> _requestAccess() =>
      ScreenCapturer.instance.requestAccess();

  static Future<bool> _captureRegion(String imagePath) async {
    final captured = await screenCapturer.capture(
      // ignore: avoid_redundant_argument_values
      mode: CaptureMode.region,
      imagePath: imagePath,
      copyToClipboard: false,
    );
    return captured != null;
  }

  static Future<bool> _isUsable(File file) async {
    try {
      return await file.exists() && await file.length() > 0;
    } on FileSystemException {
      return false;
    }
  }

  static Future<void> _deleteIfPresent(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // A stale or cancelled capture should never make the composer fail.
    }
  }
}
