import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

import '../platform/ohos_support.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';

enum MediaLibrarySaveResult { saved, permissionDenied, unsupported, failed }

class MediaLibrarySaveTarget {
  const MediaLibrarySaveTarget({
    required this.fileId,
    required this.file,
    required this.isVideo,
    required this.creationDate,
  });

  final int fileId;
  final TdFileRef file;
  final bool isVideo;
  final DateTime creationDate;

  static MediaLibrarySaveTarget? fromMessage(ChatMessage message) {
    final video = message.video;
    if (video != null) {
      return MediaLibrarySaveTarget(
        fileId: video.id,
        file: video,
        isVideo: true,
        creationDate: _messageDate(message),
      );
    }
    final image = message.image;
    if (message.isPhoto && image != null) {
      return MediaLibrarySaveTarget(
        fileId: image.id,
        file: image,
        isVideo: false,
        creationDate: _messageDate(message),
      );
    }
    return null;
  }

  static DateTime _messageDate(ChatMessage message) =>
      DateTime.fromMillisecondsSinceEpoch(message.date * 1000);
}

class MediaLibrarySaver {
  const MediaLibrarySaver._();

  /// Saves a chat photo/video into the system gallery.
  ///
  /// Being a mobile OS does not guarantee a photo_library implementation: a
  /// host without one (HarmonyOS today) has no handler on the photo_manager
  /// channel, and [PhotoManager.systemVersion] short-circuits there without
  /// crossing the channel, so the first real round trip is the save itself.
  /// A missing channel reads as [MediaLibrarySaveResult.unsupported] — the
  /// same answer a desktop host gets — instead of a call-time crash.
  static Future<MediaLibrarySaveResult> save(ChatMessage message) async {
    final target = MediaLibrarySaveTarget.fromMessage(message);
    if (target == null || !isMobilePlatform) {
      return MediaLibrarySaveResult.unsupported;
    }

    try {
      if (!await _requestWritePermission()) {
        return MediaLibrarySaveResult.permissionDenied;
      }

      final path = await TdFileCenter.shared.pathFor(target.file);
      if (path == null || path.isEmpty) return MediaLibrarySaveResult.failed;
      final file = File(path);
      if (!await file.exists()) return MediaLibrarySaveResult.failed;

      return await _savePreparedFile(
        file,
        isVideo: target.isVideo,
        creationDate: target.creationDate,
        permissionAlreadyGranted: true,
      );
    } on MissingPluginException {
      return MediaLibrarySaveResult.unsupported;
    } catch (_) {
      return MediaLibrarySaveResult.failed;
    }
  }

  /// Saves an already-downloaded or generated image/video. Sticker export uses
  /// this so GIF/APNG/MOV output follows the same add-only Photos permission
  /// path as ordinary chat media.
  static Future<MediaLibrarySaveResult> savePreparedFile(
    File file, {
    required bool isVideo,
    DateTime? creationDate,
  }) async {
    if (!isMobilePlatform) {
      return MediaLibrarySaveResult.unsupported;
    }
    try {
      return await _savePreparedFile(
        file,
        isVideo: isVideo,
        creationDate: creationDate,
      );
    } on MissingPluginException {
      return MediaLibrarySaveResult.unsupported;
    } catch (_) {
      return MediaLibrarySaveResult.failed;
    }
  }

  static Future<MediaLibrarySaveResult> _savePreparedFile(
    File file, {
    required bool isVideo,
    DateTime? creationDate,
    bool permissionAlreadyGranted = false,
  }) async {
    if (!permissionAlreadyGranted && !await _requestWritePermission()) {
      return MediaLibrarySaveResult.permissionDenied;
    }
    if (!await file.exists()) return MediaLibrarySaveResult.failed;

    final title = file.uri.pathSegments.isEmpty
        ? null
        : file.uri.pathSegments.last;
    if (isVideo) {
      await PhotoManager.editor.saveVideo(
        file,
        title: title,
        creationDate: creationDate,
      );
    } else {
      await PhotoManager.editor.saveImageWithPath(
        file.path,
        title: title,
        creationDate: creationDate,
      );
    }
    return MediaLibrarySaveResult.saved;
  }

  static Future<bool> _requestWritePermission() async {
    if (Platform.isIOS) {
      final state = await PhotoManager.requestPermissionExtend(
        requestOption: const PermissionRequestOption(
          iosAccessLevel: IosAccessLevel.addOnly,
        ),
      );
      return state.isAuth;
    }

    final sdk = int.tryParse(await PhotoManager.systemVersion()) ?? 29;
    if (sdk > 28) return true;
    return (await Permission.storage.request()).isGranted;
  }
}
