import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import 'video_controller_factory.dart';

enum MithkaVideoSourceKind { network, file, asset }

/// A platform-neutral description of media consumed by [MithkaVideoPlayer].
///
/// A file source can be described on every platform, but its built-in
/// controller factory is unavailable on the web. Web applications should use
/// a network/asset source or inject a controller/controller builder.
class MithkaVideoSource {
  const MithkaVideoSource.network(
    this.location, {
    this.httpHeaders = const {},
    this.closedCaptionFile,
    this.videoPlayerOptions,
  }) : kind = MithkaVideoSourceKind.network,
       package = null;

  const MithkaVideoSource.file(
    this.location, {
    this.httpHeaders = const {},
    this.closedCaptionFile,
    this.videoPlayerOptions,
  }) : kind = MithkaVideoSourceKind.file,
       package = null;

  const MithkaVideoSource.asset(
    this.location, {
    this.package,
    this.closedCaptionFile,
    this.videoPlayerOptions,
  }) : kind = MithkaVideoSourceKind.asset,
       httpHeaders = const {};

  factory MithkaVideoSource.uri(
    Uri uri, {
    Map<String, String> httpHeaders = const {},
    Future<ClosedCaptionFile>? closedCaptionFile,
    VideoPlayerOptions? videoPlayerOptions,
  }) => uri.scheme == 'file'
      ? MithkaVideoSource.file(
          uri.toFilePath(),
          httpHeaders: httpHeaders,
          closedCaptionFile: closedCaptionFile,
          videoPlayerOptions: videoPlayerOptions,
        )
      : MithkaVideoSource.network(
          uri.toString(),
          httpHeaders: httpHeaders,
          closedCaptionFile: closedCaptionFile,
          videoPlayerOptions: videoPlayerOptions,
        );

  final MithkaVideoSourceKind kind;
  final String location;
  final String? package;

  /// Headers used for controller creation.
  ///
  /// Treat this map as immutable after constructing the source. Controller
  /// creation takes an unmodifiable snapshot before handing it to a backend.
  final Map<String, String> httpHeaders;
  final Future<ClosedCaptionFile>? closedCaptionFile;
  final VideoPlayerOptions? videoPlayerOptions;

  String? get thumbnailLocation => switch (kind) {
    MithkaVideoSourceKind.network || MithkaVideoSourceKind.file => location,
    MithkaVideoSourceKind.asset => null,
  };

  /// Creates the official video_player controller for this source.
  ///
  /// [videoPlayerOptionsOverride] is used by [MithkaVideoPlayer] when it needs
  /// to own app lifecycle behavior. Direct callers normally leave it null.
  VideoPlayerController createController({
    VideoPlayerOptions? videoPlayerOptionsOverride,
  }) {
    final options =
        videoPlayerOptionsOverride ??
        videoPlayerOptions ??
        VideoPlayerOptions(mixWithOthers: true);
    final headers = Map<String, String>.unmodifiable(httpHeaders);
    return switch (kind) {
      MithkaVideoSourceKind.network => VideoPlayerController.networkUrl(
        Uri.parse(location),
        httpHeaders: headers,
        closedCaptionFile: closedCaptionFile,
        videoPlayerOptions: options,
      ),
      MithkaVideoSourceKind.file => createFileVideoController(
        path: location,
        httpHeaders: headers,
        closedCaptionFile: closedCaptionFile,
        videoPlayerOptions: options,
      ),
      MithkaVideoSourceKind.asset => VideoPlayerController.asset(
        location,
        package: package,
        closedCaptionFile: closedCaptionFile,
        videoPlayerOptions: options,
      ),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MithkaVideoSource &&
          kind == other.kind &&
          location == other.location &&
          package == other.package &&
          mapEquals(httpHeaders, other.httpHeaders) &&
          identical(closedCaptionFile, other.closedCaptionFile) &&
          identical(videoPlayerOptions, other.videoPlayerOptions);

  @override
  int get hashCode => Object.hash(
    kind,
    location,
    package,
    Object.hashAllUnordered(
      httpHeaders.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    identityHashCode(closedCaptionFile),
    identityHashCode(videoPlayerOptions),
  );
}
