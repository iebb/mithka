import 'package:flutter/services.dart';

abstract final class VideoTrimService {
  static const _channel = MethodChannel('mithka/media_editor');

  static Future<String> trim({
    required String path,
    required Duration start,
    required Duration end,
  }) async {
    if (path.trim().isEmpty || start.isNegative || end <= start) {
      throw const FormatException('The video trim range is invalid.');
    }
    final output = await _channel.invokeMethod<String>('trimVideo', {
      'path': path,
      'startMs': start.inMilliseconds,
      'endMs': end.inMilliseconds,
    });
    if (output == null || output.isEmpty) {
      throw PlatformException(
        code: 'video_trim_failed',
        message: 'The trimmed video was not created.',
      );
    }
    return output;
  }
}
