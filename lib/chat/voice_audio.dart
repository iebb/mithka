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
// ignore: depend_on_referenced_packages
import 'package:flutter_sound_platform_interface/flutter_sound_player_platform_interface.dart';
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
  /// How long a native startPlayer/stopPlayer call may hang before the load
  /// is treated as failed. flutter_sound can leave its start completer
  /// pending forever when the platform player never reports prepared
  /// (broken container, missing file, session errors), which used to leave
  /// the UI spinner stuck with no way to retry.
  ///
  /// Non-const so tests can shrink it instead of waiting real seconds.
  @visibleForTesting
  // ignore: prefer_const_constructors
  static Duration nativeCallTimeout = Duration(seconds: 15);

  /// The number of start attempts on one native player before the load
  /// reports a failure instead of spinning again. A hung start retires the
  /// native player anyway; this bounds the retry loop when starts fail
  /// fast.
  ///
  /// Non-const so tests can shrink it instead of waiting real seconds.
  @visibleForTesting
  static int maxStartAttempts = 3;

  /// Builds the native player. Indirect so tests can observe how many
  /// native instances were created across a recovery.
  @visibleForTesting
  FlutterSoundPlayer Function() nativePlayerFactory = () =>
      FlutterSoundPlayer(logLevel: Level.warning);

  /// Test seam: replaces the audio-session activation inside output
  /// preparation. A test can hold a start at exactly that await and
  /// release it after a stop or a dispose, exercising the ownership
  /// re-check that must cancel the start before it touches the native
  /// player. The native open still runs for real.
  @visibleForTesting
  Future<AudioSession?> Function()? audioSessionActivationOverride;

  FlutterSoundPlayer? _player;
  bool isPlaying = false;
  bool isLoading = false;
  Duration position = Duration.zero;
  Duration total = Duration.zero;
  double speed = 1;
  void Function(int fileId)? onFinished;

  /// Notified with the file id whose playback failed to start. Unlike
  /// [onFinished] the player keeps the file bound so the UI can show the
  /// failure and the next tap retries cleanly.
  void Function(int fileId, Object error)? onFailed;

  int? _fileId;
  String? _path;
  bool _opened = false;
  int _startAttempts = 0;
  bool _disposed = false;

  /// Monotonic token of the current playback. Bumped by stop, dispose and
  /// every native-player retirement, so an in-flight start or a native
  /// callback can tell whether the playback it was issued for is still the
  /// one bound to the player.
  int _playbackGeneration = 0;
  StreamSubscription<PlaybackDisposition>? _progress;
  StreamSubscription<AudioInterruptionEvent>? _interruption;
  StreamSubscription<void>? _becomingNoisy;
  final _interruptionPolicy = AudioInterruptionResumePolicy();
  late final PlaybackProgressPoller _poller = PlaybackProgressPoller(
    read: _readProgress,
    onProgress: _applyProgress,
  );

  FlutterSoundPlayer get _sound => _player ??= nativePlayerFactory();

  /// Retires the current native player and resets the open bookkeeping.
  ///
  /// flutter_sound serializes every verb (open, start, stop, close) behind
  /// one non-reentrant lock. A startPlayer whose completer never completes
  /// (Android MediaPlayer prepare that never reports prepared, a lost native
  /// reply) holds that lock forever: every later stopPlayer/closePlayer on
  /// the same instance queues behind the dead start and never runs. The only
  /// recovery is to abandon the instance — a fresh openPlayer gets a fresh
  /// lock and a fresh native session.
  /// Releases a native player instance for good.
  ///
  /// [wasOpened] tells whether the instance's openPlayer ever completed in
  /// our bookkeeping. Every path is bound to this exact instance and can
  /// never close a fresh player a later load opened.
  ///
  /// The dart-side session slot is what the platform's dispatcher routes
  /// reverse callbacks (audioPlayerFinishedPlaying, late completions)
  /// through: `closeSession` frees the slot for reuse, so it may only run
  /// AFTER the platform acknowledged the close of this exact session.
  /// Freeing it earlier would let a fresh session reuse the slot and a late
  /// event for this instance would be routed to the new owner — stopping
  /// its playback. Closing the platform session first and waiting for the
  /// acknowledgment keeps the routing table pinned while stray events
  /// still arrive; a slot whose close never gets acknowledged stays
  /// occupied forever (safe: the SDK's closePlayer verb never registers a
  /// duplicate session, so the list only grows by leaked slot).
  void _releaseNative(FlutterSoundPlayer player, {required bool wasOpened}) {
    if (wasOpened) {
      // The regular verb close queues behind the instance's operation
      // lock. A start whose completion never arrives pins that lock
      // forever, and a queued closePlayer runs the moment the late
      // completion releases it. A verb close that completes has already
      // released the native session and freed the callback slot itself —
      // no further cleanup follows. Only when it fails or times out does
      // the native session still need releasing: close it on the
      // platform interface directly. The dart-side slot stays registered
      // until that close is acknowledged, so late events keep routing to
      // this retired instance instead of a fresh one.
      unawaited(
        player
            .closePlayer()
            .timeout(nativeCallTimeout)
            .catchError((Object _) {
              _platformClose(player);
            })
            // A wedged lock releases late: the verb close then runs on an
            // instance whose platform session was already closed above,
            // and _closePlayer can throw (e.g. the platform close above
            // already answered). Keep the release silent either way: the
            // native session is released, nothing else can happen here.
            .catchError((Object _) {}),
      );
      return;
    }
    // An instance whose openPlayer never completed can never be released
    // by the verb at all — closePlayer returns early on the uninitialized
    // flag without touching the platform — so its native session goes
    // straight to the platform interface.
    _platformClose(player);
  }

  /// Closes [player]'s native session on the platform interface and frees
  /// its dart-side callback slot only after the platform acknowledged the
  /// close.
  void _platformClose(FlutterSoundPlayer player) {
    unawaited(
      FlutterSoundPlayerPlatform.instance
          .closePlayer(player)
          .timeout(nativeCallTimeout)
          .then((_) {
            // Acknowledged: no further reverse callback can be routed
            // through this slot, so freeing it is safe now.
            FlutterSoundPlayerPlatform.instance.closeSession(player);
          })
          .catchError((Object _) {
            // The platform close was not acknowledged. Keep the slot
            // occupied: recycling it now would let the next session reuse
            // it and receive this instance's late events. A leaked slot is
            // bounded — the SDK registers one slot per openPlayer call.
          }),
    );
  }

  /// Retires the current native player and resets the open bookkeeping.
  ///
  /// flutter_sound serializes every verb (open, start, stop, close) behind
  /// one non-reentrant lock. A startPlayer whose completer never completes
  /// (Android MediaPlayer prepare that never reports prepared, a lost native
  /// reply) holds that lock forever: every later stopPlayer/closePlayer on
  /// the same instance queues behind the dead start and never runs. The only
  /// recovery is to abandon the instance — a fresh openPlayer gets a fresh
  /// lock and a fresh native session. The abandoned instance still owns a
  /// native session, so its release is queued rather than forgotten.
  void _retireNativePlayer() {
    final retired = _player;
    final wasOpened = _opened;
    _player = null;
    _opened = false;
    _opening = null;
    // Callbacks still registered on the retired instance may fire at any
    // time; invalidating the generation makes them no-ops.
    _playbackGeneration++;
    if (retired == null) return;
    _releaseNative(retired, wasOpened: wasOpened);
  }

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
        await player.openPlayer().timeout(
          nativeCallTimeout,
          onTimeout: () {
            // openPlayer's future completes from the platform's reverse
            // openPlayerCompleted callback; a platform that never sends it
            // would pin this player's operation lock forever. Fail the open
            // so the load surfaces an error and the wedged instance is
            // dropped (never reused).
            throw TimeoutException('openPlayer');
          },
        );
        await player.setSubscriptionDuration(const Duration(milliseconds: 60));
        // The open may have outlived its own retirement (a stop timed out
        // on this instance's lock and dropped it while the open was still
        // pending). A late success must not mark a fresh instance open.
        if (_player == player) {
          _opened = true;
        }
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
    // Cancels any start still awaiting its audio session: it must not
    // reach the native player for a track the user just stopped.
    _playbackGeneration++;
    final player = _player;
    if (player != null && (player.isPlaying || player.isPaused)) {
      try {
        await player.stopPlayer().timeout(nativeCallTimeout);
      } catch (_) {
        // The stop never completed: this native instance may be wedged,
        // so never reuse it (see _retireNativePlayer).
        _retireNativePlayer();
      }
      // Give the shared audio session back (calls, other media apps).
      try {
        final session = await _prepareAudioSession().timeout(nativeCallTimeout);
        if (!_disposed) {
          await session
              .setActive(
                false,
                avAudioSessionSetActiveOptions:
                    AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
              )
              .timeout(const Duration(seconds: 8));
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

    // A native start that timed out leaves the shared flutter_sound lock
    // held forever. While a start attempt is in flight, the same instance
    // cannot serve a second one — queueing another tap behind the dead
    // start only queues it on the dead lock.
    if (_starting) {
      debugPrint(
        'VoicePlayer: ignoring tap on ${file.id}, a start is in flight',
      );
      return;
    }

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
        await player.stopPlayer().timeout(nativeCallTimeout);
      } catch (_) {
        _retireNativePlayer();
      }
    }

    _fileId = file.id;
    position = Duration.zero;
    total = Duration.zero;
    isPlaying = false;
    isLoading = true;
    _syncPolling();
    notifyListeners();
    if (_startAttempts >= maxStartAttempts) {
      // Fresh native player, fresh counter: the user asked to try again.
      _retireNativePlayer();
      _startAttempts = 0;
    }
    // Opening the native player and activating the audio session do not
    // depend on the file. Run them while the path resolves instead of after
    // it, so a cached track starts as soon as its path is known.
    final audioReady = _prepareOutput();
    String? path;
    Object? pathError;
    try {
      path =
          TdFileCenter.shared.cachedPath(file) ??
          await TdFileCenter.shared.pathFor(file, priority: 32);
    } catch (error) {
      pathError = error;
    }
    if (_disposed) return;
    // The user may have tapped another note while this file resolved —
    // don't clobber the newer load's state or start the stale file.
    if (_fileId != file.id) return;
    isLoading = false;
    // A session that will not activate is logged but not fatal: iOS can
    // refuse or stall activation while another audio app holds the session,
    // yet the player can still start and the interruption listener recovers
    // later. Blocking on it here used to leave the spinner stuck forever.
    if (path == null) {
      debugPrint(
        'VoicePlayer: failed to resolve ${file.id}'
        '${pathError == null ? '' : ': $pathError'}',
      );
      _fileId = null;
      notifyListeners();
      onFailed?.call(file.id, pathError ?? StateError('path unavailable'));
      return;
    }
    _path = path;
    if (_nativeOpenFailed) {
      // The open timed out and retired the native player. A start on a
      // fresh instance needs its own openPlayer round trip; report the
      // failure and let the next tap run the full load again.
      debugPrint('VoicePlayer: open timed out for ${file.id}');
      isPlaying = false;
      isLoading = false;
      _syncPolling();
      notifyListeners();
      onFailed?.call(file.id, TimeoutException('openPlayer'));
      return;
    }
    await _start(
      0,
      codec: codec,
      audioReady: audioReady,
      generation: _playbackGeneration,
      path: path,
    );
  }

  Future<AudioSession?> _prepareOutput() async {
    final activation = audioSessionActivationOverride;
    if (activation != null) {
      // Keep the native open real (retirement bookkeeping depends on it);
      // only the session activation is held by the test.
      await _ensureOpen();
      return activation();
    }
    try {
      try {
        await _ensureOpen();
      } catch (error) {
        // A wedged openPlayer pins that instance's operation lock
        // forever; drop it so nothing ever reuses it.
        _retireNativePlayer();
        rethrow;
      }
      final session = await _prepareAudioSession().timeout(nativeCallTimeout);
      try {
        await session.setActive(true).timeout(const Duration(seconds: 8));
      } catch (_) {
        // Activation refused or stalled; playback still attempts to start.
      }
      return session;
    } catch (_) {
      return null;
    }
  }

  /// True when the native player could not even be opened (wedged
  /// openPlayer). The load must fail instead of attempting a start: the
  /// flutter_sound lock of the retired instance is gone with it, but a
  /// fresh instance needs its own open round trip first.
  bool get _nativeOpenFailed => _player == null && _opening == null && !_opened;

  bool _starting = false;
  Future<void> _start(
    int fromMs, {
    required Codec codec,
    required int generation,
    required String path,
    Future<AudioSession?>? audioReady,
  }) async {
    isPlaying = true;
    position = Duration(milliseconds: fromMs);
    _syncPolling();
    notifyListeners();
    unawaited(_progress?.cancel());
    _progress = null;
    final fileId = _fileId;
    _starting = true;
    _startAttempts++;
    FlutterSoundPlayer? startOn;
    try {
      final ready = await audioReady?.timeout(nativeCallTimeout);
      if (ready == null) {
        debugPrint('VoicePlayer: audio session inactive, starting anyway');
      }
      // The await above straddles user actions and native recovery. A stop,
      // a dispose, another load or a retirement during it must cancel this
      // start before it touches the native player: the captured path may
      // already be cleared and the player replaced.
      if (_disposed || _fileId != fileId) {
        return;
      }
      if (generation != _playbackGeneration) {
        // Our own preparation retired the native player (a wedged
        // openPlayer): the load must fail, not silently vanish. Any other
        // cancellation already returned above — a stop clears the file, a
        // newer load replaces it.
        if (_nativeOpenFailed) {
          debugPrint('VoicePlayer: open timed out for $fileId');
          isPlaying = false;
          isLoading = false;
          _syncPolling();
          notifyListeners();
          onFailed?.call(fileId!, TimeoutException('openPlayer'));
        }
        return;
      }
      // _prepareOutput may have retired and replaced the native player
      // (a wedged openPlayer); always start on the current one.
      startOn = _sound;
      _progress = startOn.onProgress?.listen((e) {
        _applyProgress(e.position, e.duration);
      });
      await startOn
          .startPlayer(
            fromURI: path,
            codec: codec,
            whenFinished: () {
              // The platform can deliver this after dispose(), or from an
              // instance whose start timed out and was retired while a new
              // track already plays. Only the playback that registered the
              // callback may act on it; notifying a disposed
              // ChangeNotifier throws.
              if (_disposed ||
                  generation != _playbackGeneration ||
                  fileId == null ||
                  fileId != _fileId) {
                return;
              }
              isPlaying = false;
              position = Duration.zero;
              _syncPolling();
              notifyListeners();
              onFinished?.call(fileId);
            },
          )
          .timeout(nativeCallTimeout);
      _startAttempts = 0; // A clean start resets the retry budget.
      if (_disposed || generation != _playbackGeneration) return;
      await startOn.setSpeed(speed);
      if (fromMs > 0) {
        await startOn.seekToPlayer(Duration(milliseconds: fromMs));
      }
    } catch (error) {
      final stale = _disposed || generation != _playbackGeneration;
      if (!stale) {
        debugPrint('VoicePlayer: failed to start ${fileId ?? -1}: $error');
      }
      // The failed instance may hold the flutter_sound operation lock
      // forever (a start whose completer never completed never releases
      // it). stopPlayer on the same instance would queue behind the dead
      // start; drop the instance instead so the next tap opens a new one.
      // A stale start must not retire a player a newer playback owns.
      if (startOn != null && startOn == _player) {
        _retireNativePlayer();
      }
      if (stale) return;
      isPlaying = false;
      isLoading = false;
      _syncPolling();
      notifyListeners();
      if (fileId != null) onFailed?.call(fileId, error);
    } finally {
      _starting = false;
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
    // Any start still awaiting its audio session must not reach the native
    // player afterwards.
    _playbackGeneration++;
    _poller.stop();
    _interruptionPolicy.clear();
    _progress?.cancel();
    _interruption?.cancel();
    _becomingNoisy?.cancel();
    final player = _player;
    final wasOpened = _opened;
    _player = null;
    if (player != null) {
      // Release whatever native session the current instance owns — a
      // close on an opened instance, a direct platform close when the
      // openPlayer never completed (the verb would early-return and leak
      // it). Disposal means no later load can exist, so releasing the
      // current instance is always safe. Both paths are bounded so a
      // wedged operation lock cannot hang dispose.
      _releaseNative(player, wasOpened: wasOpened);
    }
    super.dispose();
  }
}
