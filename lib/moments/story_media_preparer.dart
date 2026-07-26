import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as image_lib;
import 'package:light_compressor_v2/light_compressor_v2.dart';
import 'package:path_provider/path_provider.dart';

import 'story_service.dart';

class StoryVideoSegment {
  const StoryVideoSegment({required this.startSecond, required this.duration});

  final int startSecond;
  final int duration;
}

List<StoryVideoSegment> planStoryVideoSegments(
  Duration duration, {
  int maximumSeconds = 60,
}) {
  if (maximumSeconds <= 0) throw ArgumentError.value(maximumSeconds);
  final totalSeconds = math.max(1, (duration.inMilliseconds / 1000).ceil());
  return [
    for (var start = 0; start < totalSeconds; start += maximumSeconds)
      StoryVideoSegment(
        startSecond: start,
        duration: math.min(maximumSeconds, totalSeconds - start),
      ),
  ];
}

class StoryMediaPreparer {
  const StoryMediaPreparer();

  LightCompressor get _videoCompressor => LightCompressor();

  Future<StoryMediaDraft> preparePhoto(
    String path, {
    List<int> addedStickerFileIds = const <int>[],
  }) async {
    final decoded = image_lib.decodeImage(await File(path).readAsBytes());
    if (decoded == null) throw StateError('The selected photo is unreadable');
    const targetRatio = 9 / 16;
    final sourceRatio = decoded.width / decoded.height;
    late image_lib.Image cropped;
    if (sourceRatio > targetRatio) {
      final width = (decoded.height * targetRatio).round();
      cropped = image_lib.copyCrop(
        decoded,
        x: (decoded.width - width) ~/ 2,
        y: 0,
        width: width,
        height: decoded.height,
      );
    } else {
      final height = (decoded.width / targetRatio).round();
      cropped = image_lib.copyCrop(
        decoded,
        x: 0,
        y: (decoded.height - height) ~/ 2,
        width: decoded.width,
        height: height,
      );
    }
    final output = image_lib.copyResize(
      cropped,
      width: 1080,
      height: 1920,
      interpolation: image_lib.Interpolation.cubic,
    );
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/mithka_story_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(image_lib.encodeJpg(output, quality: 90));
    return StoryMediaDraft.photo(
      path: file.path,
      addedStickerFileIds: addedStickerFileIds,
    );
  }

  Future<Duration> videoDuration(String path) async {
    final info = await _videoCompressor.getMediaInfo(path);
    return info.duration ?? Duration.zero;
  }

  Future<List<StoryMediaDraft>> prepareVideo(
    String path, {
    List<int> addedStickerFileIds = const <int>[],
    void Function(int completed, int total)? onProgress,
  }) async {
    final duration = await videoDuration(path);
    final segments = planStoryVideoSegments(duration);
    final result = <StoryMediaDraft>[];
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final media = await _videoCompressor.compressVideo(
        path: path,
        videoQuality: VideoQuality.high,
        android: AndroidConfig(isSharedStorage: false),
        ios: IOSConfig(saveInGallery: false),
        video: Video(
          videoName:
              'mithka_story_${DateTime.now().microsecondsSinceEpoch}_$i.mp4',
          videoWidth: 1280,
          videoHeight: 720,
          videoFps: 30,
        ),
        isMinBitrateCheckEnabled: false,
        edit: VideoEdit(
          trimStartMs: segment.startSecond * 1000,
          trimEndMs: (segment.startSecond + segment.duration) * 1000,
        ),
      );
      final outputPath = media is OnSuccess ? media.destinationPath : null;
      if (outputPath == null || outputPath.isEmpty) {
        throw StateError('Video segment ${i + 1} could not be prepared');
      }
      final outputDuration = media is OnSuccess
          ? media.duration
          : segment.duration.toDouble();
      result.add(
        StoryMediaDraft.video(
          path: outputPath,
          duration: outputDuration.clamp(0.001, 60),
          addedStickerFileIds: addedStickerFileIds,
        ),
      );
      onProgress?.call(i + 1, segments.length);
    }
    return result;
  }

  Future<void> cancel() => _videoCompressor.cancelCompression();
}
