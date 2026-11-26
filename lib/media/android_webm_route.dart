//
//  android_webm_route.dart
//
//  Byte-for-byte the routing of cineplay_fvp's Android wrapper, except the
//  decision is per file instead of per extension.
//
//  MDK (fvp) is registered for every `file://*.webm` there, because an alpha
//  sticker only decodes on its software decoder. But MDK also loops a
//  video-only clip at its last frame's timestamp instead of the container
//  duration, so it drops that frame's hold on every pass: 25% of a five-frame
//  0.4 s sticker, 1% of a three-second one. That is the whole "short stickers
//  play too fast" bug, and no playback-rate correction survives MDK's loop (the
//  rate compounds at every restart).
//
//  A sticker without alpha does not need MDK at all: the platform player decodes
//  it and loops it at its authored duration. So the header decides which player
//  a file gets.
//

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'webm_header.dart';

final class AndroidWebmRouteVideoPlayerPlatform extends VideoPlayerPlatform {
  AndroidWebmRouteVideoPlayerPlatform({
    required this.primaryBackend,
    required this.alphaWebmBackend,
  });

  final VideoPlayerPlatform primaryBackend;
  final VideoPlayerPlatform alphaWebmBackend;
  final Map<int, _RoutedVideoPlayer> _players = <int, _RoutedVideoPlayer>{};
  final Map<String, bool> _alphaByPath = <String, bool>{};
  int _nextPlayerId = 1;

  @override
  Future<void> init() async {
    _players.clear();
    await primaryBackend.init();
    await alphaWebmBackend.init();
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
    final backend = await _decodesHere(options.dataSource)
        ? alphaWebmBackend
        : primaryBackend;
    final backendPlayerId = await backend.createWithOptions(options);
    if (backendPlayerId == null) return null;
    final playerId = _nextPlayerId++;
    _players[playerId] = _RoutedVideoPlayer(backend, backendPlayerId);
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
    await alphaWebmBackend.setMixWithOthers(mixWithOthers);
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

  /// Alpha stickers only decode on MDK's software decoder. A sticker without
  /// alpha belongs on the platform player, which loops it at the container
  /// duration; MDK loops a video-only clip at its last frame's timestamp and
  /// drops that frame's hold every pass, which is invisible on a three-second
  /// sticker and 25% on a five-frame one.
  Future<bool> _decodesHere(DataSource dataSource) async {
    final path = _localWebmPath(dataSource);
    if (path == null) return false;
    final cached = _alphaByPath[path];
    if (cached != null) return cached;
    var alpha = false;
    try {
      alpha = webmHasAlpha(await File(path).readAsBytes());
    } catch (_) {
      // Unreadable now (still downloading): route it the way a sticker of its
      // kind is usually routed and decide again on the next create.
      return true;
    }
    if (_alphaByPath.length > 256) _alphaByPath.clear();
    return _alphaByPath[path] = alpha;
  }

  static String? _localWebmPath(DataSource dataSource) {
    if (dataSource.sourceType != DataSourceType.file) return null;
    final uri = Uri.tryParse(dataSource.uri ?? '');
    if (uri == null || uri.scheme != 'file') return null;
    final path = uri.path;
    return path.toLowerCase().endsWith('.webm') ? path : null;
  }

  _RoutedVideoPlayer _player(int playerId) {
    final player = _players[playerId];
    if (player == null) {
      throw StateError('Unknown routed video player: $playerId');
    }
    return player;
  }

  _RoutedVideoPlayer _takePlayer(int playerId) {
    final player = _players.remove(playerId);
    if (player == null) {
      throw StateError('Unknown routed video player: $playerId');
    }
    return player;
  }
}

bool isAndroidAlphaWebmDataSource(DataSource dataSource) {
  if (dataSource.sourceType != DataSourceType.file) return false;
  final uri = Uri.tryParse(dataSource.uri ?? '');
  if (uri == null || uri.scheme != 'file') return false;
  final path = uri.path.toLowerCase();
  return path.endsWith('.webm');
}

final class _RoutedVideoPlayer {
  const _RoutedVideoPlayer(this.backend, this.backendPlayerId);

  final VideoPlayerPlatform backend;
  final int backendPlayerId;
}

/// Routes local WebM stickers per file on Android: alpha stickers keep MDK's
/// software decoder, everything else stays on the platform player.
void installAndroidWebmRoute() {
  if (!Platform.isAndroid) return;
  final primary = VideoPlayerPlatform.instance;
  fvp.registerWith(
    options: <String, Object>{
      'platforms': <String>['android'],
      'video.decoders': <String>['FFmpeg'],
      'maxWidth': 512,
      'maxHeight': 512,
    },
  );
  final alphaWebm = VideoPlayerPlatform.instance;
  VideoPlayerPlatform.instance = AndroidWebmRouteVideoPlayerPlatform(
    primaryBackend: primary,
    alphaWebmBackend: alphaWebm,
  );
}
