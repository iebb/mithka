import 'dart:typed_data';

import 'video_source.dart';

import 'video_thumbnail_backend_stub.dart'
    if (dart.library.io) 'video_thumbnail_backend_io.dart'
    as backend;

class MithkaVideoThumbnailRequest {
  const MithkaVideoThumbnailRequest({
    required this.source,
    required this.position,
    this.maxWidth = 240,
    this.quality = 72,
  }) : assert(maxWidth > 0),
       assert(quality >= 0 && quality <= 100);

  final MithkaVideoSource source;
  final Duration position;
  final int maxWidth;
  final int quality;
}

/// A host-supplied thumbnail implementation for platforms or media sources
/// that need a custom decoder, authenticated requests, or an existing cache.
typedef MithkaVideoThumbnailProvider =
    Future<Uint8List?> Function(MithkaVideoThumbnailRequest request);

/// Thumbnail generation used by both [MithkaVideoPlayer] and host apps.
abstract final class MithkaVideoThumbnail {
  static Future<Uint8List?> generate({
    required String source,
    required Duration position,
    int maxWidth = 240,
    int quality = 72,
  }) {
    final uri = Uri.tryParse(source);
    final windowsPath = RegExp(r'^[A-Za-z]:[\\/]').hasMatch(source);
    final videoSource = !windowsPath && uri != null && uri.hasScheme
        ? MithkaVideoSource.uri(uri)
        : MithkaVideoSource.file(source);
    return generateRequest(
      MithkaVideoThumbnailRequest(
        source: videoSource,
        position: position,
        maxWidth: maxWidth,
        quality: quality,
      ),
    );
  }

  static Future<Uint8List?> generateRequest(
    MithkaVideoThumbnailRequest request,
  ) {
    if (request.position.isNegative) {
      throw ArgumentError.value(
        request.position,
        'request.position',
        'must not be negative',
      );
    }
    if (request.maxWidth <= 0) {
      throw ArgumentError.value(
        request.maxWidth,
        'request.maxWidth',
        'must be greater than zero',
      );
    }
    if (request.quality < 0 || request.quality > 100) {
      throw ArgumentError.value(
        request.quality,
        'request.quality',
        'must be between zero and 100',
      );
    }
    return backend.generateThumbnail(
      source: request.source,
      position: request.position,
      maxWidth: request.maxWidth,
      quality: request.quality,
    );
  }
}
