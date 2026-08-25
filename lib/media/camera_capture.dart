//
//  camera_capture.dart
//
//  拍照: where a capture taken inside the app is allowed to land.
//
//  The system camera app, not Mithka, decides whether a capture also lands in
//  the system album, and many Android camera apps always write one to DCIM.
//  "Don't save it" therefore cannot be honored while the shot goes through the
//  system camera at all, so the preference picks the route instead of only
//  picking a save:
//
//   * off (default) — the in-app camera runs and the capture stays in app
//     storage until it is sent, so sending a photo never grows the album.
//   * on  — the system camera runs, so its album copy is the one the user
//     sees. iOS never persists a UIImagePickerController capture, so the file
//     is written to the album here; doing the same on Android would leave a
//     duplicate next to the camera app's own copy.
//

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../chat/media_library_saver.dart';
import 'app_camera_view.dart';

/// The outcome of a capture: the photo, plus how the album write went when one
/// was attempted. `albumResult` is null when the preference is off or when the
/// system camera owns the album copy.
class CameraCapture {
  const CameraCapture(this.file, {this.albumResult});

  final XFile file;
  final MediaLibrarySaveResult? albumResult;

  bool get albumWriteFailed =>
      albumResult != null && albumResult != MediaLibrarySaveResult.saved;
}

/// Takes one photo for sending, honoring "save captured photos to the album".
///
/// Returns null when the user backs out of the camera.
Future<CameraCapture?> captureComposerPhoto(
  BuildContext context, {
  required bool saveToAlbum,
}) async {
  if (!saveToAlbum) {
    final result = await Navigator.of(context).push<AppCameraResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            const AppCameraView(allowVideo: false, allowGallery: false),
      ),
    );
    final file = result?.file;
    return file == null ? null : CameraCapture(file);
  }

  final shot = await ImagePicker().pickImage(source: ImageSource.camera);
  if (shot == null) return null;
  if (!Platform.isIOS) return CameraCapture(shot);
  return CameraCapture(
    shot,
    albumResult: await MediaLibrarySaver.savePreparedFile(
      File(shot.path),
      isVideo: false,
    ),
  );
}
