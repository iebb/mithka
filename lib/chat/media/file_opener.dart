//
//  file_opener.dart
//
//  Shared file-opening helper for every entry point that hands a downloaded
//  file to the OS (file detail page, downloads list, retained downloads).
//  It supplies the MIME type explicitly because TDLib download paths do not
//  always preserve the original file extension, and it gates APK installs on
//  the Android 8+ "install unknown apps" switch: without that switch the
//  package installer finishes silently and the tap appears to do nothing.
//

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:mithka/components/app_confirm_dialog.dart';
import 'package:mithka/components/toast.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';

/// Contract for the install-packages switch so tests can drive the flow.
abstract interface class InstallPackagesGateway {
  Future<bool> isGranted();

  Future<bool> request();
}

class SystemInstallPackagesGateway implements InstallPackagesGateway {
  const SystemInstallPackagesGateway();

  @override
  Future<bool> isGranted() async =>
      (await Permission.requestInstallPackages.status).isGranted;

  @override
  Future<bool> request() async =>
      (await Permission.requestInstallPackages.request()).isGranted;
}

/// Tests replace this gateway to drive the permission flow.
InstallPackagesGateway installPackagesGateway =
    const SystemInstallPackagesGateway();

typedef DownloadedFileOpen =
    Future<OpenResult> Function(String path, {String? type});

/// Tests replace the OS boundary so they never launch external applications.
@visibleForTesting
DownloadedFileOpen downloadedFileOpen = OpenFilex.open;

const _mimeMap = <String, String>{
  'apk': 'application/vnd.android.package-archive',
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'txt': 'text/plain',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'svg': 'image/svg+xml',
  'webp': 'image/webp',
  'bmp': 'image/bmp',
  'mp3': 'audio/mpeg',
  'wav': 'audio/wav',
  'ogg': 'audio/ogg',
  'flac': 'audio/flac',
  'aac': 'audio/aac',
  'mp4': 'video/mp4',
  'avi': 'video/x-msvideo',
  'mkv': 'video/x-matroska',
  'webm': 'video/webm',
  'mov': 'video/quicktime',
  'html': 'text/html',
  'css': 'text/css',
  'js': 'application/javascript',
  'json': 'application/json',
  'xml': 'text/xml',
  'zip': 'application/zip',
  'rar': 'application/x-rar-compressed',
  '7z': 'application/x-7z-compressed',
  'tar': 'application/x-tar',
  'gz': 'application/gzip',
  'csv': 'text/csv',
};

const apkMime = 'application/vnd.android.package-archive';

/// Maps a lowercase extension (without the dot) to a MIME type, falling back
/// to null so the OS resolves the type from the file itself.
String? mimeForExtension(String ext) {
  final normalized = ext.toLowerCase();
  if (normalized.isEmpty) return null;
  return _mimeMap[normalized];
}

String? mimeForFileName(String name) => mimeForExtension(_extensionOf(name));

/// Opens [path] through the OS, waiting for the install permission when the
/// file is an APK the user has not yet allowed Mithka to install.
Future<void> openDownloadedFile(
  BuildContext context,
  String path, {
  String? mimeType,
}) async {
  if (!context.mounted) return;
  final type = mimeType ?? mimeForFileName(path);
  if (defaultTargetPlatform == TargetPlatform.android &&
      type == apkMime &&
      !await _ensureInstallPermission(context)) {
    return;
  }
  if (!context.mounted) return;
  final result = await downloadedFileOpen(path, type: type);
  if (result.type != ResultType.done && context.mounted) {
    showToast(context, AppStringKeys.fileDetailNoAppCanOpenFile);
  }
}

Future<bool> _ensureInstallPermission(BuildContext context) async {
  final alreadyGranted = await installPackagesGateway.isGranted();
  if (!context.mounted) return false;
  if (alreadyGranted) return true;
  // The dialog await can span frames, so every later use re-checks mounted.
  final proceed = await showAppConfirmDialog(
    context,
    title: AppStringKeys.fileDetailApkInstallTitle,
    message: AppStringKeys.fileDetailApkInstallMessage,
    confirmText: AppStringKeys.fileDetailApkInstallOpenSettings,
  );
  if (!proceed || !context.mounted) return false;
  final granted = await installPackagesGateway.request();
  if (!granted || !context.mounted) return false;
  showToast(context, AppStringKeys.fileDetailApkInstallGranted);
  // The special-permission screen finishes before the system re-reads the
  // switch on some devices; a short pause keeps the installer from racing.
  await Future<void>.delayed(const Duration(milliseconds: 400));
  return context.mounted;
}

String _extensionOf(String path) {
  final name = path.substring(path.lastIndexOf('/') + 1);
  final dot = name.lastIndexOf('.');
  return dot >= 0 ? name.substring(dot + 1) : '';
}
