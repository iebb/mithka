import 'dart:io';

import 'package:video_player/video_player.dart';

VideoPlayerController createFileVideoController({
  required String path,
  required Map<String, String> httpHeaders,
  required Future<ClosedCaptionFile>? closedCaptionFile,
  required VideoPlayerOptions? videoPlayerOptions,
}) => VideoPlayerController.file(
  File(path),
  httpHeaders: httpHeaders,
  closedCaptionFile: closedCaptionFile,
  videoPlayerOptions: videoPlayerOptions,
);
