import 'dart:typed_data';

import 'package:video_thumbnail_gen/video_thumbnail_gen.dart';

/// Thumbnail generation used by both [MithkaVideoPlayer] and host apps.
abstract final class MithkaVideoThumbnail {
  static Future<Uint8List?> generate({
    required String source,
    required Duration position,
    int maxWidth = 240,
    int quality = 72,
  }) => VideoThumbnail.thumbnailData(
    video: source,
    imageFormat: ImageFormat.JPEG,
    maxWidth: maxWidth,
    timeMs: position.inMilliseconds,
    quality: quality,
  );
}
