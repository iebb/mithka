import 'package:video_player/video_player.dart';

import 'video_controller_factory_stub.dart'
    if (dart.library.io) 'video_controller_factory_io.dart'
    as platform;

VideoPlayerController createFileVideoController({
  required String path,
  required Map<String, String> httpHeaders,
  required Future<ClosedCaptionFile>? closedCaptionFile,
  required VideoPlayerOptions? videoPlayerOptions,
}) => platform.createFileVideoController(
  path: path,
  httpHeaders: httpHeaders,
  closedCaptionFile: closedCaptionFile,
  videoPlayerOptions: videoPlayerOptions,
);
