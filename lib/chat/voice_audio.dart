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

/// Keeps track of whether an active player should resume after an audio
/// interruption. iOS reports the equivalent of AVAudioSession's
/// `shouldResume` option as a pause interruption ending event; Android's
/// transient audio-focus loss uses the same event shape.
@visibleForTesting
class AudioInterruptionResumePolicy {
  bool _resumeAfterInterruption = false;

  void onBegin(AudioInterruptionEvent event, {required bool wasPlaying}) {
    if (event.type == AudioInterruptionType.duck) return;
    _resumeAfterInterruption = wasPlaying;
  }

  bool onEnd(AudioInterruptionEvent event) {
    if (event.begin) return false;
    final shouldResume =
        event.type == AudioInterruptionType.pause && _resumeAfterInterruption;
    _resumeAfterInterruption = false;
    return shouldResume;
  }

  void clear() => _resumeAfterInterruption = false;
}

/// Reads the native playback position on a fixed cadence while playing.
///
/// flutter_sound's `onProgress` stream is driven by a native timer that does
/// not fire reliably on every device (Android MediaPlayer sessions can go
/// silent after prepare, upstream issue #1155), which froze the scrubber and
/// elapsed time. Polling the same native position keeps progress moving no
/// matter which source delivers it. A read that started before a seek is
/// discarded, so a stale position never snaps the scrubber back.
@visibleForTesting
class PlaybackProgressPoller {
  PlaybackProgressPoller({
    required this.read,
    required this.onProgress,
    this.interval = const Duration(milliseconds: 250),
  });

  final Future<({Duration position, Duration duration})?> Function() read;
  final void Function(Duration position, Duration duration) onProgress;
  final Duration interval;

  Timer? _timer;
  int _generation = 0;
  bool _reading = false;

  bool get isRunning => _timer != null;

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(interval, (_) => unawaited(_tick()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _generation++;
  }

  /// Drops any read already in flight. Call when the position jumps (seek).
  void invalidate() => _generation++;

  Future<void> _tick() async {
    if (_reading) return;
    _reading = true;
    final generation = _generation;
    try {
      final value = await read();
      if (value == null || generation != _generation || _timer == null) {
        return;
      }
      onProgress(value.position, value.duration);
    } catch (_) {
      // The player may be between tracks; the next tick reads again.
    } finally {
      _reading = false;
    }
  }
}

class VoicePlayer extends ChangeNotifier {
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
  StreamSubscription<AudioInterruptionEvent>? _interruption;
  StreamSubscription<void>? _becomingNoisy;
  final _interruptionPolicy = AudioInterruptionResumePolicy();
  late final PlaybackProgressPoller _poller = PlaybackProgressPoller(
    read: _readProgress,
    onProgress: _applyProgress,
  );

  FlutterSoundPlayer get _sound =>
      _player ??= FlutterSoundPlayer(logLevel: Level.warning);

  Future<({Duration position, Duration duration})?> _readProgress() async {
    final player = _player;
    if (_disposed || player == null || !player.isPlaying) return null;
    // ignore: deprecated_member_use
    final progress = await player.getProgress();
    final position = progress['progress'];
    if (position == null) return null;
    return (position: position, duration: progress['duration'] ?? total);
  }

  void _applyProgress(Duration nextPosition, Duration duration) {
    if (_disposed || !isPlaying) return;
    final nextTotal = duration.inMilliseconds > 0 ? duration : total;
    if (nextPosition == position && nextTotal == total) return;
    position = nextPosition;
    total = nextTotal;
    notifyListeners();
  }

  void _syncPolling() {
    if (isPlaying && !_disposed) {
      _poller.start();
    } else {
      _poller.stop();
    }
  }

  Future<AudioSession> _prepareAudioSession() async {
    // Re-apply the music category before every new track. Calls and other
    // audio plugins may temporarily change the shared AVAudioSession; the
    // official Telegram client restores its playback holder before resuming.
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _interruption ??= session.interruptionEventStream.listen((event) {
      unawaited(_handleInterruption(event));
    });
    _becomingNoisy ??= session.becomingNoisyEventStream.listen((_) {
      unawaited(_pauseForBecomingNoisy());
    });
    return session;
  }

  /// True when this player is the one bound to [file] (playing or paused).
  bool isActive(TdFileRef? file) => file != null && _fileId == file.id;

  /// True when a loaded track is paused (not stopped or finished).
  bool get isPaused => _fileId != null && _player?.isPaused == true;

  Future<void>? _opening;

  /// Opens the native player once. Rapid taps start several loads at the
  /// same time; they share one open instead of racing a second openPlayer.
  Future<void> _ensureOpen() {
    if (_opened) return Future.value();
    return _opening ??= () async {
      try {
        final player = _sound;
        await player.openPlayer();
        await player.setSubscriptionDuration(const Duration(milliseconds: 60));
        _opened = true;
      } finally {
        _opening = null;
      }
    }();
  }

  Future<void> toggleVoice(TdFileRef? file) =>
      _toggle(file, codec: Codec.opusOGG);

  Future<void> toggleAudio(TdFileRef? file) =>
      _toggle(file, codec: Codec.defaultCodec);

  Future<void> stop() async {
    _interruptionPolicy.clear();
    final player = _player;
    if (player != null && (player.isPlaying || player.isPaused)) {
      try {
        await player.stopPlayer();
      } catch (_) {}
      // Give the shared audio session back (calls, other media apps).
      try {
        final session = await _prepareAudioSession();
        if (!_disposed) {
          await session.setActive(
            false,
            avAudioSessionSetActiveOptions:
                AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
          );
        }
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
    _syncPolling();
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
        _interruptionPolicy.clear();
        await player.pausePlayer();
        isPlaying = false;
      } else {
        // Calls and other audio apps can deactivate our shared audio
        // session while we are paused; re-activate it before resuming, the
        // same way interruption-end recovery does.
        _interruptionPolicy.clear();
        try {
          final session = await _prepareAudioSession();
          if (_disposed) return;
          await session.setActive(true);
        } catch (_) {}
        await player.resumePlayer();
        isPlaying = true;
      }
      _syncPolling();
      notifyListeners();
      return;
    }

    if (player != null && (player.isPlaying || player.isPaused)) {
      _interruptionPolicy.clear();
      try {
        await player.stopPlayer();
      } catch (_) {}
    }

    _fileId = file.id;
    position = Duration.zero;
    total = Duration.zero;
    isPlaying = false;
    isLoading = true;
    _syncPolling();
    notifyListeners();
    // Opening the native player and activating the audio session do not
    // depend on the file. Run them while the path resolves instead of after
    // it, so a cached track starts as soon as its path is known.
    final audioReady = _prepareOutput();
    final path =
        TdFileCenter.shared.cachedPath(file) ??
        await TdFileCenter.shared.pathFor(file, priority: 32);
    final ready = await audioReady;
    if (_disposed) return;
    // The user may have tapped another note while this file resolved —
    // don't clobber the newer load's state or start the stale file.
    if (_fileId != file.id) return;
    isLoading = false;
    if (path == null || ready == null) {
      _fileId = null;
      notifyListeners();
      return;
    }
    _path = path;
    await _start(0, codec: codec);
  }

  Future<AudioSession?> _prepareOutput() async {
    try {
      await _ensureOpen();
      final session = await _prepareAudioSession();
      await session.setActive(true);
      return session;
    } catch (_) {
      return null;
    }
  }

  Future<void> _start(int fromMs, {required Codec codec}) async {
    try {
      if (_disposed) return;
      final player = _sound;
      unawaited(_progress?.cancel());
      _progress = player.onProgress?.listen((e) {
        _applyProgress(e.position, e.duration);
      });
      isPlaying = true;
      position = Duration(milliseconds: fromMs);
      _syncPolling();
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
          _syncPolling();
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
      _syncPolling();
      notifyListeners();
    }
  }

  /// Resumes a paused track. No-op when nothing is loaded or already playing.
  Future<void> resume() async {
    final player = _player;
    if (_fileId == null || player == null || !player.isPaused) return;
    _interruptionPolicy.clear();
    // Calls and other audio apps can deactivate our shared audio session
    // while we are paused; re-activate it before resuming, the same way
    // interruption-end recovery does.
    try {
      final session = await _prepareAudioSession();
      if (_disposed) return;
      await session.setActive(true);
    } catch (_) {}
    try {
      await player.resumePlayer();
    } catch (_) {
      return;
    }
    if (_disposed) return;
    isPlaying = true;
    _syncPolling();
    notifyListeners();
  }

  /// Pauses the playing track. No-op when nothing is playing.
  Future<void> pause() async {
    final player = _player;
    if (player == null || !player.isPlaying) return;
    _interruptionPolicy.clear();
    try {
      await player.pausePlayer();
    } catch (_) {
      return;
    }
    if (_disposed) return;
    isPlaying = false;
    _syncPolling();
    notifyListeners();
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

  Future<void> _handleInterruption(AudioInterruptionEvent event) async {
    if (_disposed) return;
    final player = _player;
    if (event.begin) {
      final wasPlaying = player?.isPlaying == true;
      _interruptionPolicy.onBegin(event, wasPlaying: wasPlaying);
      if (!wasPlaying || event.type == AudioInterruptionType.duck) return;
      try {
        await player!.pausePlayer();
      } catch (_) {
        _interruptionPolicy.clear();
        return;
      }
      if (_disposed) return;
      isPlaying = false;
      _syncPolling();
      notifyListeners();
      return;
    }

    if (!_interruptionPolicy.onEnd(event) || _disposed) return;
    final current = _player;
    if (_fileId == null ||
        _path == null ||
        current == null ||
        !current.isPaused) {
      return;
    }
    try {
      final session = await _prepareAudioSession();
      if (_disposed) return;
      await session.setActive(true);
      await current.resumePlayer();
      isPlaying = true;
      _syncPolling();
      notifyListeners();
    } catch (_) {
      if (_disposed) return;
      isPlaying = false;
      _syncPolling();
      notifyListeners();
    }
  }

  Future<void> _pauseForBecomingNoisy() async {
    _interruptionPolicy.clear();
    if (_disposed || _player?.isPlaying != true) return;
    try {
      await _player!.pausePlayer();
    } catch (_) {}
    if (_disposed) return;
    isPlaying = false;
    _syncPolling();
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
    _poller.invalidate();
    position = target;
    notifyListeners();
    final player = _player;
    if (_opened && player != null && (player.isPlaying || player.isPaused)) {
      try {
        await player.seekToPlayer(target);
      } catch (_) {}
      _poller.invalidate();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _poller.stop();
    _interruptionPolicy.clear();
    _progress?.cancel();
    _interruption?.cancel();
    _becomingNoisy?.cancel();
    if (_opened) _player?.closePlayer();
    super.dispose();
  }
}
