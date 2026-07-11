import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';

enum MediaLibrarySaveResult { saved, permissionDenied, unsupported, failed }

class MediaLibrarySaveTarget {
  const MediaLibrarySaveTarget({
    required this.fileId,
    required this.isVideo,
    required this.creationDate,
  });

  final int fileId;
  final bool isVideo;
  final DateTime creationDate;

  static MediaLibrarySaveTarget? fromMessage(ChatMessage message) {
    final video = message.video;
    if (video != null) {
      return MediaLibrarySaveTarget(
        fileId: video.id,
        isVideo: true,
        creationDate: _messageDate(message),
      );
    }
    final image = message.image;
    if (message.isPhoto && image != null) {
      return MediaLibrarySaveTarget(
        fileId: image.id,
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

  static Future<MediaLibrarySaveResult> save(ChatMessage message) async {
    final target = MediaLibrarySaveTarget.fromMessage(message);
    if (target == null || (!Platform.isIOS && !Platform.isAndroid)) {
      return MediaLibrarySaveResult.unsupported;
    }

    try {
      if (!await _requestWritePermission()) {
        return MediaLibrarySaveResult.permissionDenied;
      }

      final path = await TdFileCenter.shared.path(target.fileId);
      if (path == null || path.isEmpty) return MediaLibrarySaveResult.failed;
      final file = File(path);
      if (!await file.exists()) return MediaLibrarySaveResult.failed;

      final title = file.uri.pathSegments.isEmpty
          ? null
          : file.uri.pathSegments.last;
      if (target.isVideo) {
        await PhotoManager.editor.saveVideo(
          file,
          title: title,
          creationDate: target.creationDate,
        );
      } else {
        await PhotoManager.editor.saveImageWithPath(
          path,
          title: title,
          creationDate: target.creationDate,
        );
      }
      return MediaLibrarySaveResult.saved;
    } catch (_) {
      return MediaLibrarySaveResult.failed;
    }
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
