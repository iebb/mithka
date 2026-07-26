import 'package:mithka_video_player/mithka_video_player.dart';

const sampleVideo =
    'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4';

/// Set with `--dart-define=MITHKA_VIDEO_ASSET=assets/sample.mp4` after adding
/// the file to this example's Flutter assets.
const configuredAssetVideo = String.fromEnvironment('MITHKA_VIDEO_ASSET');

/// Set with `--dart-define=MITHKA_VIDEO_FILE=/absolute/path/to/video.mp4`.
const configuredFileVideo = String.fromEnvironment('MITHKA_VIDEO_FILE');

enum ExampleSourceMode {
  network,
  ownedController,
  controllerBuilder,
  asset,
  file,
}

extension ExampleSourceModePresentation on ExampleSourceMode {
  String get label => switch (this) {
    ExampleSourceMode.network => 'Network',
    ExampleSourceMode.ownedController => 'Owned controller',
    ExampleSourceMode.controllerBuilder => 'Controller builder',
    ExampleSourceMode.asset => 'Asset',
    ExampleSourceMode.file => 'Local file',
  };

  String get description => switch (this) {
    ExampleSourceMode.network =>
      'The player creates, initializes, and disposes its controller.',
    ExampleSourceMode.ownedController =>
      'The host supplies a controller and remains responsible for disposal.',
    ExampleSourceMode.controllerBuilder =>
      'The host creates a custom controller; the player owns its lifetime.',
    ExampleSourceMode.asset =>
      'Uses an asset declared by the host application.',
    ExampleSourceMode.file =>
      'Uses an absolute native file path. This mode is unavailable on web.',
  };
}

bool isExampleSourceAvailable(
  ExampleSourceMode mode, {
  required bool isWeb,
  String assetPath = configuredAssetVideo,
  String filePath = configuredFileVideo,
}) => switch (mode) {
  ExampleSourceMode.network ||
  ExampleSourceMode.ownedController ||
  ExampleSourceMode.controllerBuilder => true,
  ExampleSourceMode.asset => assetPath.isNotEmpty,
  ExampleSourceMode.file => !isWeb && filePath.isNotEmpty,
};

MithkaVideoSource sourceForExampleMode(
  ExampleSourceMode mode, {
  String networkUrl = sampleVideo,
  String assetPath = configuredAssetVideo,
  String filePath = configuredFileVideo,
}) => switch (mode) {
  ExampleSourceMode.network ||
  ExampleSourceMode.ownedController ||
  ExampleSourceMode.controllerBuilder => MithkaVideoSource.network(networkUrl),
  ExampleSourceMode.asset => MithkaVideoSource.asset(assetPath),
  ExampleSourceMode.file => MithkaVideoSource.file(filePath),
};
