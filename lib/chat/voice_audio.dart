//
//  voice_audio.dart
//
//  Voice-note playback for the bubble's play/pause + draggable scrubber.
//  Telegram voice notes are Opus-in-OGG (flutter_sound bundles libopus so it
//  plays on iOS too). Resolves the file via TDFileCenter, plays it, exposes
//  position/duration for the seek bar, supports pause/resume and drag-to-seek.
//

import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:logger/logger.dart' show Level;

import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';

class VoicePlayer extends ChangeNotifier {
  static Future<void>? _audioSessionFuture;

  FlutterSoundPlayer? _player;
  bool isPlaying = false;
  bool isLoading = false;
  Duration position = Duration.zero;
  Duration total = Duration.zero;
  double speed = 1;
  void Function(int fileId)? onFinished;

  int? _fileId;
  String? _path;
  bool _opened = false;
  bool _disposed = false;
  StreamSubscription<PlaybackDisposition>? _progress;

  FlutterSoundPlayer get _sound =>
      _player ??= FlutterSoundPlayer(logLevel: Level.warning);

  static Future<void> _configureAudioSession() {
    return _audioSessionFuture ??= (() async {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    })();
  }

  /// True when this player is the one bound to [file] (playing or paused).
  bool isActive(TdFileRef? file) => file != null && _fileId == file.id;

  Future<void> _ensureOpen() async {
    if (_opened) return;
    await _configureAudioSession();
    final player = _sound;
    await player.openPlayer();
    await player.setSubscriptionDuration(const Duration(milliseconds: 60));
    _opened = true;
  }

  Future<void> toggleVoice(TdFileRef? file) =>
      _toggle(file, codec: Codec.opusOGG);

  Future<void> toggleAudio(TdFileRef? file) =>
      _toggle(file, codec: Codec.defaultCodec);

  Future<void> stop() async {
    final player = _player;
    if (player != null && (player.isPlaying || player.isPaused)) {
      try {
        await player.stopPlayer();
      } catch (_) {}
    }
    unawaited(_progress?.cancel());
    _progress = null;
    _fileId = null;
    _path = null;
    isPlaying = false;
    isLoading = false;
    position = Duration.zero;
    total = Duration.zero;
    notifyListeners();
  }

  Future<void> _toggle(TdFileRef? file, {required Codec codec}) async {
    if (file == null) return;

    // Same note already loaded → pause / resume.
    final player = _player;
    if (_fileId == file.id &&
        player != null &&
        (player.isPlaying || player.isPaused)) {
      if (player.isPlaying) {
        await player.pausePlayer();
        isPlaying = false;
      } else {
        await player.resumePlayer();
        isPlaying = true;
      }
      notifyListeners();
      return;
    }

    if (player != null && (player.isPlaying || player.isPaused)) {
      try {
        await player.stopPlayer();
      } catch (_) {}
    }

    _fileId = file.id;
    position = Duration.zero;
    total = Duration.zero;
    isPlaying = false;
    isLoading = true;
    notifyListeners();
    final path = await TdFileCenter.shared.pathFor(file);
    if (_disposed) return;
    // The user may have tapped another note while this file resolved —
    // don't clobber the newer load's state or start the stale file.
    if (_fileId != file.id) return;
    isLoading = false;
    if (path == null) {
      _fileId = null;
      notifyListeners();
      return;
    }
    _path = path;
    await _start(0, codec: codec);
  }

  Future<void> _start(int fromMs, {required Codec codec}) async {
    try {
      await _ensureOpen();
      final session = await AudioSession.instance;
      await session.setActive(true);
      final player = _sound;
      unawaited(_progress?.cancel());
      _progress = player.onProgress?.listen((e) {
        position = e.position;
        if (e.duration.inMilliseconds > 0) total = e.duration;
        notifyListeners();
      });
      isPlaying = true;
      position = Duration(milliseconds: fromMs);
      notifyListeners();
      await player.startPlayer(
        fromURI: _path,
        codec: codec,
        whenFinished: () {
          // The platform can deliver this after dispose(); notifying a
          // disposed ChangeNotifier throws.
          if (_disposed) return;
          final finishedFileId = _fileId;
          isPlaying = false;
          position = Duration.zero;
          notifyListeners();
          if (finishedFileId != null) onFinished?.call(finishedFileId);
        },
      );
      await player.setSpeed(speed);
      if (fromMs > 0) {
        await player.seekToPlayer(Duration(milliseconds: fromMs));
      }
    } catch (_) {
      if (_disposed) return;
      isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> cycleSpeed() async {
    speed = switch (speed) {
      < 1.25 => 1.5,
      < 1.75 => 2,
      _ => 1,
    };
    final player = _player;
    if (_opened && player != null && (player.isPlaying || player.isPaused)) {
      try {
        await player.setSpeed(speed);
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Drag-to-seek. [fraction] in 0..1; [fallbackSeconds] is the note's known
  /// duration (used before playback has reported a duration).
  Future<void> seekFraction(double fraction, int fallbackSeconds) async {
    final f = fraction.clamp(0.0, 1.0);
    final dur = total.inMilliseconds > 0
        ? total
        : Duration(seconds: fallbackSeconds);
    final target = Duration(milliseconds: (dur.inMilliseconds * f).round());
    position = target;
    notifyListeners();
    final player = _player;
    if (_opened && player != null && (player.isPlaying || player.isPaused)) {
      try {
        await player.seekToPlayer(target);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _progress?.cancel();
    if (_opened) _player?.closePlayer();
    super.dispose();
  }
}
