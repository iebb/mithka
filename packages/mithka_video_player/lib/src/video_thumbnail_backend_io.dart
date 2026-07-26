import 'dart:io';
import 'dart:typed_data';

import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail_platform_interface.dart';

import 'video_source.dart';

final _thumbnailPlugin = FcNativeVideoThumbnail();

Future<Uint8List?> generateThumbnail({
  required MithkaVideoSource source,
  required Duration position,
  required int maxWidth,
  required int quality,
}) async {
  if (source.kind == MithkaVideoSourceKind.asset ||
      source.httpHeaders.isNotEmpty) {
    return Future<Uint8List?>.value();
  }

  final network = source.kind == MithkaVideoSourceKind.network;
  if (network && (Platform.isLinux || Platform.isWindows)) return null;
  if (Platform.isWindows && position > Duration.zero) return null;

  var location = source.location;
  var sourceIsUri = network;
  if (source.kind == MithkaVideoSourceKind.file && Platform.isAndroid) {
    location = Uri.file(source.location).toString();
    sourceIsUri = true;
  }

  try {
    return await _thumbnailPlugin.saveThumbnailToBytes(
      srcFile: location,
      srcFileUri: sourceIsUri,
      width: maxWidth,
      height: (maxWidth * 9 / 16).round(),
      quality: quality,
      at: FcVideoThumbnailTime(
        position.inMilliseconds,
        FcVideoThumbnailTimeUnit.milliseconds,
      ),
    );
  } on Object {
    // A missing platform codec, an inaccessible URI, or an unsupported format
    // must not interrupt seeking. Hosts can inject a source-specific provider.
    return null;
  }
}
