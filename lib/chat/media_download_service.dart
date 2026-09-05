//
//  media_download_service.dart
//
//  “Save this media” on a computer. A desktop has no photo library to add to,
//  so the album path in `media_library_saver.dart` gives way to a native save
//  panel: the original file is copied out of TDLib's cache into whichever
//  folder the user picks, starting at the system Downloads directory.
//

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/app_localizations.dart';
import '../platform/adaptive_platform.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';
import 'media_library_saver.dart';

enum MediaDownloadResult { saved, cancelled, unsupported, failed }

/// [folder] is the display name of the directory the file landed in, so the
/// confirmation can answer “saved where?” without printing an absolute path.
typedef MediaDownloadOutcome = ({MediaDownloadResult result, String? folder});

class MediaDownloadService {
  const MediaDownloadService._();

  static bool get isSupported => isDesktopTargetPlatform();

  /// Saves the photo, video or GIF carried by [message]. Mirrors what
  /// `MediaLibrarySaver.save` does for phones, minus the album.
  static Future<MediaDownloadOutcome> saveMessageMedia(
    ChatMessage message, {
    int? accountSlot,
  }) async {
    final target = MediaLibrarySaveTarget.fromMessage(message);
    if (target == null) return _outcome(MediaDownloadResult.unsupported);
    return saveMedia(
      file: target.file,
      isVideo: target.isVideo,
      creationDate: target.creationDate,
      accountSlot: accountSlot,
    );
  }

  /// Downloads [file] if it is not local yet, then copies it out. The copy is
  /// streamed by the OS, so a long video never has to sit in memory first.
  static Future<MediaDownloadOutcome> saveMedia({
    required TdFileRef file,
    required bool isVideo,
    DateTime? creationDate,
    int? accountSlot,
  }) async {
    if (!isSupported) return _outcome(MediaDownloadResult.unsupported);
    try {
      final path = await TdFileCenter.shared.pathFor(
        file,
        accountSlot: accountSlot,
      );
      if (path == null || path.isEmpty) {
        return _outcome(MediaDownloadResult.failed);
      }
      final source = File(path);
      if (!await source.exists()) return _outcome(MediaDownloadResult.failed);
      return await _copyToPickedFile(
        source,
        fileName: suggestedFileName(
          file: file,
          isVideo: isVideo,
          creationDate: creationDate,
          localPath: path,
        ),
      );
    } catch (_) {
      return _outcome(MediaDownloadResult.failed);
    }
  }

  /// Confirmation copy for [outcome]; null when the user simply cancelled and
  /// nothing needs saying.
  static String? feedbackFor(MediaDownloadOutcome outcome) =>
      switch (outcome.result) {
        MediaDownloadResult.saved => AppStrings.t(
          AppStringKeys.chatSavedToFolder,
          {'value1': outcome.folder ?? ''},
        ),
        MediaDownloadResult.cancelled => null,
        MediaDownloadResult.failed || MediaDownloadResult.unsupported =>
          AppStrings.t(AppStringKeys.chatSaveToFolderFailed),
      };

  static Future<MediaDownloadOutcome> _copyToPickedFile(
    File source, {
    required String fileName,
  }) async {
    final extension = _extensionOf(fileName);
    final destination = await FilePicker.platform.saveFile(
      dialogTitle: AppStrings.t(AppStringKeys.messageActionSaveAs),
      fileName: fileName,
      initialDirectory: await _downloadsDirectory(),
      type: extension.isEmpty ? FileType.any : FileType.custom,
      allowedExtensions: extension.isEmpty ? null : [extension],
    );
    if (destination == null || destination.trim().isEmpty) {
      return _outcome(MediaDownloadResult.cancelled);
    }
    await source.copy(destination);
    return (
      result: MediaDownloadResult.saved,
      folder: folderLabel(destination),
    );
  }

  /// The name the save panel opens with. TDLib keeps its cache under opaque
  /// names like `5_1024.jpg`, so a message without an original file name gets
  /// a dated one instead of leaking the cache's numbering.
  static String suggestedFileName({
    required TdFileRef file,
    required bool isVideo,
    DateTime? creationDate,
    String? localPath,
  }) {
    final extension = _resolveExtension(
      isVideo: isVideo,
      localPath: localPath,
      mimeType: file.mimeType,
      fileName: file.fileName,
    );
    final original = _sanitizeFileName(file.fileName);
    if (original != null) {
      return _extensionOf(original).isEmpty ? '$original.$extension' : original;
    }
    final stamp = _timestamp(creationDate ?? DateTime.now());
    return '${isVideo ? 'video' : 'photo'}_$stamp.$extension';
  }

  /// Display name of the folder holding [destination]; the whole path when it
  /// sits at a filesystem root.
  static String folderLabel(String destination) {
    final parts = destination
        .split(RegExp(r'[/\\]'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    return parts.length < 2 ? destination : parts[parts.length - 2];
  }

  static Future<String?> _downloadsDirectory() async {
    try {
      return (await getDownloadsDirectory())?.path;
    } catch (_) {
      return null;
    }
  }

  static MediaDownloadOutcome _outcome(MediaDownloadResult result) =>
      (result: result, folder: null);

  static String _resolveExtension({
    required bool isVideo,
    String? localPath,
    String? mimeType,
    String? fileName,
  }) {
    for (final candidate in [fileName, localPath]) {
      final extension = _extensionOf(candidate ?? '');
      if (extension.isNotEmpty) return extension;
    }
    final mime = mimeType?.trim().toLowerCase();
    final mapped = mime == null ? null : _extensionForMimeType[mime];
    if (mapped != null) return mapped;
    return isVideo ? 'mp4' : 'jpg';
  }

  /// Lowercased extension without the dot, empty when [name] has none. Guards
  /// against a dot inside a directory name and against a whole-name suffix
  /// long enough to be prose rather than a type.
  static String _extensionOf(String name) {
    final base = name.split(RegExp(r'[/\\]')).last;
    final dot = base.lastIndexOf('.');
    if (dot <= 0 || dot == base.length - 1) return '';
    final extension = base.substring(dot + 1).toLowerCase();
    return RegExp(r'^[a-z0-9]{1,5}$').hasMatch(extension) ? extension : '';
  }

  static String? _sanitizeFileName(String? name) {
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final safe = trimmed
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'[\x00-\x1f]'), '')
        .replaceAll(RegExp(r'^\.+'), '')
        .trim();
    return safe.isEmpty ? null : safe;
  }

  static String _timestamp(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}'
        '_${two(date.hour)}-${two(date.minute)}-${two(date.second)}';
  }

  static const _extensionForMimeType = <String, String>{
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/gif': 'gif',
    'image/webp': 'webp',
    'image/heic': 'heic',
    'image/heif': 'heif',
    'video/mp4': 'mp4',
    'video/quicktime': 'mov',
    'video/webm': 'webm',
    'video/x-matroska': 'mkv',
  };
}
