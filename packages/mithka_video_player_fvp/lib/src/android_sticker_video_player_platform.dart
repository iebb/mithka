import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Keeps normal Android video on the platform backend while sending Telegram
/// video stickers to FVP's alpha-capable software decoder.
final class AndroidStickerVideoPlayerPlatform extends VideoPlayerPlatform {
  AndroidStickerVideoPlayerPlatform({
    required this.primaryBackend,
    required this.stickerBackend,
  });

  final VideoPlayerPlatform primaryBackend;
  final VideoPlayerPlatform stickerBackend;
  final Map<int, _RoutedPlayer> _players = <int, _RoutedPlayer>{};
  int _nextPlayerId = 1;

  @override
  Future<void> init() async {
    _players.clear();
    await primaryBackend.init();
    await stickerBackend.init();
  }

  @override
  Future<int?> create(DataSource dataSource) => createWithOptions(
    VideoCreationOptions(
      dataSource: dataSource,
      viewType: VideoViewType.textureView,
    ),
  );

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final backend = isAndroidStickerDataSource(options.dataSource)
        ? stickerBackend
        : primaryBackend;
    final backendPlayerId = await backend.createWithOptions(options);
    if (backendPlayerId == null) return null;
    final playerId = _nextPlayerId++;
    _players[playerId] = _RoutedPlayer(backend, backendPlayerId);
    return playerId;
  }

  @override
  Future<void> dispose(int playerId) async {
    final player = _takePlayer(playerId);
    await player.backend.dispose(player.backendPlayerId);
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    final player = _player(playerId);
    return player.backend.videoEventsFor(player.backendPlayerId);
  }

  @override
  Future<void> setLooping(int playerId, bool looping) {
    final player = _player(playerId);
    return player.backend.setLooping(player.backendPlayerId, looping);
  }

  @override
  Future<void> play(int playerId) {
    final player = _player(playerId);
    return player.backend.play(player.backendPlayerId);
  }

  @override
  Future<void> pause(int playerId) {
    final player = _player(playerId);
    return player.backend.pause(player.backendPlayerId);
  }

  @override
  Future<void> setVolume(int playerId, double volume) {
    final player = _player(playerId);
    return player.backend.setVolume(player.backendPlayerId, volume);
  }

  @override
  Future<void> seekTo(int playerId, Duration position) {
    final player = _player(playerId);
    return player.backend.seekTo(player.backendPlayerId, position);
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) {
    final player = _player(playerId);
    return player.backend.setPlaybackSpeed(player.backendPlayerId, speed);
  }

  @override
  Future<Duration> getPosition(int playerId) {
    final player = _player(playerId);
    return player.backend.getPosition(player.backendPlayerId);
  }

  @override
  Widget buildView(int playerId) =>
      buildViewWithOptions(VideoViewOptions(playerId: playerId));

  @override
  Widget buildViewWithOptions(VideoViewOptions options) {
    final player = _player(options.playerId);
    return player.backend.buildViewWithOptions(
      VideoViewOptions(playerId: player.backendPlayerId),
    );
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {
    await primaryBackend.setMixWithOthers(mixWithOthers);
    await stickerBackend.setMixWithOthers(mixWithOthers);
  }

  @override
  Future<void> setAllowBackgroundPlayback(bool allowBackgroundPlayback) {
    return primaryBackend.setAllowBackgroundPlayback(allowBackgroundPlayback);
  }

  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(
    int playerId,
    bool preventsDisplaySleepDuringVideoPlayback,
  ) {
    final player = _player(playerId);
    return player.backend.setPreventsDisplaySleepDuringVideoPlayback(
      player.backendPlayerId,
      preventsDisplaySleepDuringVideoPlayback,
    );
  }

  @override
  Future<void> setWebOptions(int playerId, VideoPlayerWebOptions options) {
    final player = _player(playerId);
    return player.backend.setWebOptions(player.backendPlayerId, options);
  }

  @override
  Future<List<VideoAudioTrack>> getAudioTracks(int playerId) {
    final player = _player(playerId);
    return player.backend.getAudioTracks(player.backendPlayerId);
  }

  @override
  Future<void> selectAudioTrack(int playerId, String trackId) {
    final player = _player(playerId);
    return player.backend.selectAudioTrack(player.backendPlayerId, trackId);
  }

  @override
  bool isAudioTrackSupportAvailable() =>
      primaryBackend.isAudioTrackSupportAvailable();

  @override
  Future<List<VideoTrack>> getVideoTracks(int playerId) {
    final player = _player(playerId);
    return player.backend.getVideoTracks(player.backendPlayerId);
  }

  @override
  Future<void> selectVideoTrack(int playerId, VideoTrack? track) {
    final player = _player(playerId);
    return player.backend.selectVideoTrack(player.backendPlayerId, track);
  }

  @override
  bool isVideoTrackSupportAvailable() =>
      primaryBackend.isVideoTrackSupportAvailable();

  _RoutedPlayer _player(int playerId) {
    final player = _players[playerId];
    if (player == null) {
      throw StateError('Unknown routed video player: $playerId');
    }
    return player;
  }

  _RoutedPlayer _takePlayer(int playerId) {
    final player = _players.remove(playerId);
    if (player == null) {
      throw StateError('Unknown routed video player: $playerId');
    }
    return player;
  }
}

bool isAndroidStickerDataSource(DataSource dataSource) {
  if (dataSource.sourceType != DataSourceType.file) return false;
  final uri = Uri.tryParse(dataSource.uri ?? '');
  if (uri == null || uri.scheme != 'file') return false;
  final path = uri.path.toLowerCase();
  return path.contains('/tdlib/stickers/') && path.endsWith('.webm');
}

final class _RoutedPlayer {
  const _RoutedPlayer(this.backend, this.backendPlayerId);

  final VideoPlayerPlatform backend;
  final int backendPlayerId;
}
