import 'package:video_player/video_player.dart';

VideoPlayerController createFileVideoController({
  required String path,
  required Map<String, String> httpHeaders,
  required Future<ClosedCaptionFile>? closedCaptionFile,
  required VideoPlayerOptions? videoPlayerOptions,
}) => throw UnsupportedError(
  'MithkaVideoSource.file is not supported on this platform. '
  'Supply a VideoPlayerController or controllerBuilder to MithkaVideoPlayer.',
);
