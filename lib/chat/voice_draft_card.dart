import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../media/media_metadata.dart';
import '../theme/app_theme.dart';
import 'message_send_options.dart';
import 'voice_note_trimmer.dart';

String encodeTelegramWaveform(List<double> decibels) {
  if (decibels.isEmpty) return '';
  const maxSamples = 100;
  final buckets = <double>[];
  final step = decibels.length / maxSamples;
  if (step <= 1) {
    buckets.addAll(decibels);
  } else {
    for (var index = 0; index < maxSamples; index++) {
      final start = (index * step).floor();
      final end = ((index + 1) * step).ceil().clamp(start + 1, decibels.length);
      var peak = -120.0;
      for (var sample = start; sample < end; sample++) {
        if (decibels[sample] > peak) peak = decibels[sample];
      }
      buckets.add(peak);
    }
  }
  final packed = Uint8List((buckets.length * 5 + 7) ~/ 8);
  for (var index = 0; index < buckets.length; index++) {
    final normalized = ((buckets[index].clamp(-60.0, 0.0) + 60) / 60 * 31)
        .round()
        .clamp(0, 31);
    final bitOffset = index * 5;
    final byteOffset = bitOffset ~/ 8;
    final shift = bitOffset % 8;
    packed[byteOffset] |= (normalized << shift) & 0xff;
    if (shift > 3 && byteOffset + 1 < packed.length) {
      packed[byteOffset + 1] |= normalized >> (8 - shift);
    }
  }
  return base64Encode(packed);
}

/// A finished desktop recording, ready for [ChatViewModel.sendVoice].
class VoiceNoteDraft {
  const VoiceNoteDraft({
    required this.path,
    required this.duration,
    required this.waveform,
    required this.sendConfiguration,
  });

  final String path;
  final int duration;
  final String waveform;
  final MessageSendConfiguration sendConfiguration;
}

/// The spoken form of [seconds], as minutes and seconds.
String spokenVoiceDuration(int seconds) {
  final total = math.max(0, seconds);
  final minutes = total ~/ 60;
  final remainder = total % 60;
  if (minutes == 0) {
    return AppStrings.t(AppStringKeys.tdMessageSecondsDuration, {
      'value1': remainder,
    });
  }
  if (remainder == 0) {
    return AppStrings.t(AppStringKeys.tdMessageMinutesDuration, {
      'value1': minutes,
    });
  }
  return AppStrings.t(AppStringKeys.shortVideoMinutesSeconds, {
    'value1': minutes,
    'value2': remainder,
  });
}

/// A finished phone recording that waits in the composer until it is sent or
/// deleted: its file, the kept (trimmed) range, playback and send state.
///
/// The composer owns the file. Disposing this releases the player only.
class ComposerVoiceDraft extends ChangeNotifier {
  ComposerVoiceDraft({
    required this.path,
    required this.duration,
    required List<double> levels,
    FlutterSoundPlayer Function()? playerFactory,
  }) : levels = List<double>.unmodifiable(levels),
       _trimEnd = duration.toDouble(),
       _playerFactory = playerFactory ?? FlutterSoundPlayer.new;

  /// The shortest part trimming may keep.
  static const minimumKeptSeconds = 1.0;

  final String path;

  /// Whole seconds, as recorded.
  final int duration;

  /// Recorded meter levels in dBFS, oldest first.
  final List<double> levels;

  final FlutterSoundPlayer Function() _playerFactory;
  double _trimStart = 0;
  double _trimEnd;
  FlutterSoundPlayer? _player;
  Future<void>? _opening;
  StreamSubscription<PlaybackDisposition>? _progress;

  /// Stops playback at a trimmed end, which the progress stream would only
  /// notice up to one interval late.
  Timer? _endTimer;

  /// Bumped by every play request, pause, stop and send, so a play request
  /// still waiting on the player can tell it has been overtaken.
  int _playRequest = 0;

  /// Time since [_position] was last true, to place a pause between the
  /// player's progress updates.
  final Stopwatch _positionClock = Stopwatch();

  /// A fresh start is on its way to the kept start; the player's progress
  /// from before the seek is ignored.
  bool _seekingToStart = false;
  bool _playing = false;
  bool _started = false;
  Duration _position = Duration.zero;
  bool _sending = false;
  bool _failed = false;
  bool _disposed = false;

  double get trimStart => _trimStart;
  double get trimEnd => _trimEnd;
  double get keptSeconds => _trimEnd - _trimStart;

  /// Trimming needs two seconds to keep one, and a file the trimmer can cut:
  /// Ogg/Opus anywhere, and the AAC recordings on iOS through AVFoundation.
  bool get canTrim => duration >= 2 && VoiceNoteTrimmer.canTrim(path);
  bool get isTrimmed => _trimStart > 0.01 || _trimEnd < duration - 0.01;

  bool get playing => _playing;

  /// Playback has started and not been rewound: playing, or paused mid-way.
  bool get playbackStarted => _started;
  double get positionSeconds => _position.inMilliseconds / 1000;
  double get elapsedInKept =>
      (positionSeconds - _trimStart).clamp(0.0, keptSeconds).toDouble();

  bool get sending => _sending;
  set sending(bool value) {
    if (_sending == value) return;
    _sending = value;
    if (value) {
      _failed = false;
      _playRequest++;
      _cancelEndStop();
    }
    _notify();
  }

  /// The last export or send failed; the recording is kept for a retry.
  bool get failed => _failed;
  void markFailed() {
    _sending = false;
    _failed = true;
    _notify();
  }

  void clearFailure() {
    if (!_failed) return;
    _failed = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Duration _at(double seconds) =>
      Duration(milliseconds: (seconds * 1000).round());

  /// The open player, opening it on first use. A failed open forgets the
  /// player, so the next Play tries a fresh one.
  Future<FlutterSoundPlayer?> _ensurePlayer() async {
    final existing = _player;
    if (existing != null) {
      await _opening;
      return _disposed || !identical(_player, existing) ? null : existing;
    }
    final player = _playerFactory();
    _player = player;
    final opening = () async {
      await player.openPlayer();
      await player.setSubscriptionDuration(const Duration(milliseconds: 60));
      _progress = player.onProgress?.listen(_onProgress);
    }();
    _opening = opening;
    try {
      await opening;
    } catch (_) {
      // dispose() closes a player it already let go of.
      if (identical(_player, player)) {
        _player = null;
        _opening = null;
        final progress = _progress;
        _progress = null;
        unawaited(progress?.cancel());
        unawaited(_closePlayer(player, null));
      }
      rethrow;
    }
    return _disposed ? null : player;
  }

  void _onProgress(PlaybackDisposition event) {
    if (_disposed || !_playing || _seekingToStart) return;
    if (event.position >= _at(_trimEnd)) {
      unawaited(stopPlayback());
      return;
    }
    _position = event.position;
    _positionClock
      ..reset()
      ..start();
    _notify();
  }

  Future<void> togglePlayback() async {
    if (_disposed || _sending) return;
    clearFailure();
    if (_playing) {
      await pause();
      return;
    }
    final request = ++_playRequest;
    bool current() => !_disposed && !_sending && request == _playRequest;
    _playing = true;
    _notify();
    FlutterSoundPlayer? player;
    try {
      player = await _ensurePlayer();
      if (player == null || !current()) return;
      if (player.isPaused) {
        if (_position < _at(_trimStart) || _position >= _at(_trimEnd)) {
          _position = _at(_trimStart);
          await player.seekToPlayer(_position);
          if (!current()) return;
        }
        _started = true;
        _notify();
        await player.resumePlayer();
      } else {
        _started = true;
        _position = _at(_trimStart);
        _notify();
        await _startAtTrimStart(player);
      }
      if (!current()) {
        // Paused, stopped or sent while the player was starting.
        await _quietStalePlayback(player);
        return;
      }
      _positionClock
        ..reset()
        ..start();
      _scheduleEndStop();
    } catch (error) {
      debugPrint('Voice draft playback failed: $error');
      if (request != _playRequest) {
        if (player != null) await _quietStalePlayback(player);
        return;
      }
      _playing = false;
      _started = false;
      _position = _at(_trimStart);
      _notify();
    }
  }

  /// Starts the file at the kept start. The player cannot start mid-file,
  /// so it is muted until the seek lands rather than playing the cut part.
  Future<void> _startAtTrimStart(FlutterSoundPlayer player) async {
    final seek = _trimStart > 0 ? _at(_trimStart) : null;
    if (seek != null) {
      _seekingToStart = true;
      await _setVolume(player, 0);
    }
    try {
      await player.startPlayer(
        fromURI: path,
        codec: Codec.defaultCodec,
        whenFinished: () {
          _cancelEndStop();
          _positionClock
            ..stop()
            ..reset();
          _playing = false;
          _started = false;
          _position = _at(_trimStart);
          _notify();
        },
      );
      if (seek != null) {
        // Again once playing, in case the volume did not carry into start.
        await _setVolume(player, 0);
        await player.seekToPlayer(seek);
      }
    } finally {
      if (seek != null) {
        _seekingToStart = false;
        await _setVolume(player, 1);
      }
    }
  }

  static Future<void> _setVolume(
    FlutterSoundPlayer player,
    double volume,
  ) async {
    try {
      await player.setVolume(volume);
    } catch (_) {}
  }

  /// A play request was overtaken after it reached the player. Nothing else
  /// wants audio now, so the player follows the pause or stop that won.
  Future<void> _quietStalePlayback(FlutterSoundPlayer player) async {
    if (_disposed || _playing) return;
    try {
      if (!_started) {
        if (player.isPlaying || player.isPaused) await player.stopPlayer();
      } else if (player.isPlaying) {
        await player.pausePlayer();
      }
    } catch (_) {}
  }

  /// Stops at a trimmed end on time. An untrimmed end is the file's own,
  /// where the player finishes by itself.
  void _scheduleEndStop() {
    _cancelEndStop();
    if (_trimEnd >= duration - 0.01) return;
    final remaining = _at(_trimEnd) - _position;
    final request = _playRequest;
    _endTimer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      _endTimer = null;
      if (_playing && request == _playRequest) unawaited(stopPlayback());
    });
  }

  void _cancelEndStop() {
    _endTimer?.cancel();
    _endTimer = null;
  }

  /// Pauses playback where it is, keeping the playhead. A Play still waiting
  /// on the player is called off.
  Future<void> pause() async {
    _playRequest++;
    _cancelEndStop();
    if (!_playing) return;
    _playing = false;
    if (_positionClock.isRunning) {
      // Where the audio is now, not at the last progress update, so a
      // resume times the trimmed end from the right place.
      final now = _position + _positionClock.elapsed;
      final end = _at(_trimEnd);
      _position = now > end ? end : now;
    }
    _positionClock
      ..stop()
      ..reset();
    _notify();
    final player = _player;
    if (player == null) return;
    try {
      if (player.isPlaying) await player.pausePlayer();
    } catch (_) {}
  }

  /// Stops playback and rewinds the playhead to the kept start.
  Future<void> stopPlayback() async {
    _playRequest++;
    _cancelEndStop();
    _positionClock
      ..stop()
      ..reset();
    final changed = _playing || _started;
    _playing = false;
    _started = false;
    _position = _at(_trimStart);
    if (changed) _notify();
    final player = _player;
    if (player == null) return;
    try {
      if (player.isPlaying || player.isPaused) await player.stopPlayer();
    } catch (_) {}
  }

  /// A trim gesture began: playback stops and the playhead returns to the
  /// kept start.
  void beginTrim() {
    clearFailure();
    unawaited(stopPlayback());
  }

  /// Keeps [start]…[end] seconds, at least [minimumKeptSeconds] long.
  void setTrim(double start, double end) {
    if (!canTrim || _sending || _disposed) return;
    final total = duration.toDouble();
    final nextStart = start.clamp(0.0, total - minimumKeptSeconds).toDouble();
    final nextEnd = end.clamp(nextStart + minimumKeptSeconds, total).toDouble();
    if (nextStart == _trimStart && nextEnd == _trimEnd) return;
    _trimStart = nextStart;
    _trimEnd = nextEnd;
    _failed = false;
    if (_playing || _started) unawaited(stopPlayback());
    _position = _at(_trimStart);
    _notify();
  }

  /// The meter levels of the kept part.
  List<double> trimmedLevels() {
    if (levels.isEmpty || duration <= 0) return levels;
    final start = (levels.length * _trimStart / duration).floor().clamp(
      0,
      levels.length - 1,
    );
    final end = (levels.length * _trimEnd / duration).ceil().clamp(
      start + 1,
      levels.length,
    );
    return levels.sublist(start, end);
  }

  /// The file to send: the recording itself, or a trimmed copy of the kept
  /// part in a new temporary file.
  Future<TrimmedVoiceNote> export() async {
    if (!isTrimmed) {
      return TrimmedVoiceNote(path: path, durationSeconds: duration);
    }
    return VoiceNoteTrimmer.trim(
      inputPath: path,
      startSeconds: _trimStart,
      endSeconds: _trimEnd,
    );
  }

  /// Safe to call more than once: a send that settles after the composer
  /// let go of the draft disposes it again.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _playing = false;
    _playRequest++;
    _cancelEndStop();
    unawaited(_progress?.cancel());
    _progress = null;
    final player = _player;
    _player = null;
    if (player != null) unawaited(_closePlayer(player, _opening));
    super.dispose();
  }

  static Future<void> _closePlayer(
    FlutterSoundPlayer player,
    Future<void>? opening,
  ) async {
    try {
      await opening;
    } catch (_) {}
    try {
      await player.closePlayer();
    } catch (_) {}
  }
}

/// Deletes a file [ComposerVoiceDraft.export] created, with its directory.
Future<void> deleteExportedVoiceNote(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
    // The Ogg trimmer writes into its own `mithka-voice-…` directory; the
    // iOS export lands straight in the temporary directory, which stays.
    final parent = file.parent;
    final name = parent.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (name.startsWith('mithka-voice-')) await parent.delete();
  } catch (_) {}
}

/// The waiting recording in the phone composer: play/pause, the waveform with
/// trim handles, the time and delete, plus the inline send-failure line.
class ComposerVoiceDraftCard extends StatefulWidget {
  const ComposerVoiceDraftCard({
    super.key,
    required this.draft,
    required this.onDelete,
  });

  final ComposerVoiceDraft draft;
  final VoidCallback onDelete;

  @override
  State<ComposerVoiceDraftCard> createState() => _ComposerVoiceDraftCardState();
}

enum _TrimHandle { start, end }

class _ComposerVoiceDraftCardState extends State<ComposerVoiceDraftCard> {
  _TrimHandle? _dragging;
  int _dragOrigin = 0;
  double _dragDistance = 0;

  ComposerVoiceDraft get draft => widget.draft;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) => _card(context),
    );
  }

  Widget _card(BuildContext context) {
    final c = context.colors;
    final keptSeconds = draft.keptSeconds.round();
    final time = draft.playbackStarted && _dragging == null
        ? formatMediaDuration(draft.elapsedInKept.floor())
        : formatMediaDuration(keptSeconds);
    final sending = draft.sending;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 4, 4),
        child: Row(
          children: [
            _playButton(context),
            Expanded(child: _waveform(context)),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 40),
              child: Text(
                time,
                textAlign: TextAlign.end,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: c.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 4),
            AppInteractiveSurface(
              key: const ValueKey('composerVoiceDraftDelete'),
              semanticLabel: AppStrings.t(
                AppStringKeys.composerRecordingDiscard,
              ),
              onTap: widget.onDelete,
              borderRadius: BorderRadius.circular(22),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: AppIcon(
                    HeroAppIcons.trash,
                    size: 20,
                    color: c.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Semantics(
        key: const ValueKey('composerVoiceDraftCard'),
        container: true,
        explicitChildNodes: true,
        label:
            '${AppStrings.t(AppStringKeys.voiceNotePreviewVoiceMessage)}, '
            '${spokenVoiceDuration(keptSeconds)}',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.searchFill,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Opacity(
                opacity: sending ? 0.5 : 1,
                child: IgnorePointer(ignoring: sending, child: row),
              ),
              if (draft.failed) _failureLine(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _playButton(BuildContext context) {
    final c = context.colors;
    final playing = draft.playing;
    return AppInteractiveSurface(
      key: const ValueKey('composerVoiceDraftPlay'),
      semanticLabel: AppStrings.t(
        playing
            ? AppStringKeys.musicPlayerPause
            : AppStringKeys.musicPlayerPlay,
      ),
      onTap: () => unawaited(draft.togglePlayback()),
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.brand,
              shape: BoxShape.circle,
            ),
            child: Transform.translate(
              // The play triangle's optical centre sits left of its box.
              offset: Offset(playing ? 0 : 1, 0),
              child: AppIcon(
                playing ? HeroAppIcons.solidPause : HeroAppIcons.solidPlay,
                size: 16,
                color: c.onAccent,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _waveform(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = _WaveformGeometry(constraints.maxWidth);
        final bars = geometry.bars;
        final duration = math.max(1, draft.duration);
        final startBar = (draft.trimStart / duration * bars).round().clamp(
          0,
          bars,
        );
        final endBar = (draft.trimEnd / duration * bars).round().clamp(
          startBar,
          bars,
        );
        final canTrim = draft.canTrim;
        final waveform = CustomPaint(
          size: Size(constraints.maxWidth, 44),
          painter: _DraftWaveformPainter(
            geometry: geometry,
            levels: draft.levels,
            startBar: canTrim ? startBar : 0,
            endBar: canTrim ? endBar : bars,
            showHandles: canTrim,
            playhead: draft.playbackStarted
                ? draft.positionSeconds / duration
                : null,
            kept: AppTheme.brand,
            played: AppTheme.brand,
            unplayed: c.textTertiary,
            cut: c.textTertiary.withValues(alpha: 0.35),
          ),
        );
        if (!canTrim) return SizedBox(height: 44, child: waveform);
        // Clamped in seconds against the other handle, so dragging one never
        // pushes the other.
        const minimumKept = ComposerVoiceDraft.minimumKeptSeconds;
        double secondsAt(int bar) => bar.clamp(0, bars) / bars * duration;
        return SizedBox(
          height: 44,
          child: Stack(
            children: [
              Positioned.fill(child: waveform),
              Positioned(
                left: geometry.startHandleCentre(startBar) - 16,
                top: 0,
                width: 32,
                height: 44,
                child: _handle(
                  context,
                  handle: _TrimHandle.start,
                  bar: startBar,
                  onBar: (bar) => draft.setTrim(
                    math.min(secondsAt(bar), draft.trimEnd - minimumKept),
                    draft.trimEnd,
                  ),
                ),
              ),
              Positioned(
                left: geometry.endHandleCentre(endBar) - 16,
                top: 0,
                width: 32,
                height: 44,
                child: _handle(
                  context,
                  handle: _TrimHandle.end,
                  bar: endBar,
                  onBar: (bar) => draft.setTrim(
                    draft.trimStart,
                    math.max(secondsAt(bar), draft.trimStart + minimumKept),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _handle(
    BuildContext context, {
    required _TrimHandle handle,
    required int bar,
    required ValueChanged<int> onBar,
  }) {
    final start = handle == _TrimHandle.start;
    final seconds = start ? draft.trimStart : draft.trimEnd;
    String value(double seconds) => formatMediaDuration(seconds.round());
    final increased = start
        ? math.min(seconds + 1, draft.trimEnd - 1)
        : math.min(seconds + 1, draft.duration.toDouble());
    final decreased = start
        ? math.max(seconds - 1, 0.0)
        : math.max(seconds - 1, draft.trimStart + 1);
    void adjust(double next) {
      draft.beginTrim();
      if (start) {
        draft.setTrim(next, draft.trimEnd);
      } else {
        draft.setTrim(draft.trimStart, next);
      }
    }

    return Semantics(
      key: ValueKey(
        start ? 'composerVoiceDraftTrimStart' : 'composerVoiceDraftTrimEnd',
      ),
      container: true,
      slider: true,
      label: AppStrings.t(
        start
            ? AppStringKeys.composerRecordingTrimStart
            : AppStringKeys.composerRecordingTrimEnd,
      ),
      value: value(seconds),
      increasedValue: value(increased),
      decreasedValue: value(decreased),
      onIncrease: increased > seconds ? () => adjust(increased) : null,
      onDecrease: decreased < seconds ? () => adjust(decreased) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onHorizontalDragStart: (_) {
          unawaited(HapticFeedback.selectionClick());
          draft.beginTrim();
          setState(() {
            _dragging = handle;
            _dragOrigin = bar;
            _dragDistance = 0;
          });
        },
        onHorizontalDragUpdate: (details) {
          if (_dragging != handle) return;
          _dragDistance += details.delta.dx;
          onBar(
            _dragOrigin + (_dragDistance / _WaveformGeometry.pitch).round(),
          );
        },
        onHorizontalDragEnd: (_) => setState(() => _dragging = null),
        onHorizontalDragCancel: () => setState(() => _dragging = null),
      ),
    );
  }

  Widget _failureLine(BuildContext context) {
    final c = context.colors;
    // A live region, so VoiceOver reads the failure as soon as it appears.
    // It tucks 4pt under the row; red stays on the icon.
    return Semantics(
      container: true,
      liveRegion: true,
      child: Transform.translate(
        offset: const Offset(0, -4),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(58, 0, 12, 10),
          child: Text.rich(
            TextSpan(
              children: [
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: AppIcon(
                      HeroAppIcons.triangleExclamation,
                      size: 14,
                      color: AppTheme.tagRed,
                    ),
                  ),
                ),
                TextSpan(
                  text: AppStrings.t(AppStringKeys.composerRecordingSendFailed),
                ),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: c.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Bar layout inside the waveform slot: 10pt insets each side, then 2pt bars
/// on a 4pt pitch, centred in what is left.
class _WaveformGeometry {
  factory _WaveformGeometry(double width) {
    final available = math.max(0.0, width - 2 * inset);
    final bars = math.max(1, ((available + gap) / pitch).floor());
    final used = bars * pitch - gap;
    return _WaveformGeometry._(
      bars,
      inset + math.max(0.0, available - used) / 2,
    );
  }

  const _WaveformGeometry._(this.bars, this.left);

  static const inset = 10.0;
  static const barWidth = 2.0;
  static const gap = 2.0;
  static const pitch = barWidth + gap;
  static const handleWidth = 4.0;

  final int bars;

  /// The first bar's left edge.
  final double left;

  double barLeft(int index) => left + index * pitch;

  /// The start handle sits 1pt left of the first kept bar.
  double startHandleLeft(int startBar) => barLeft(startBar) - 1 - handleWidth;
  double startHandleCentre(int startBar) =>
      startHandleLeft(startBar) + handleWidth / 2;

  /// The end handle sits 1pt right of the last kept bar.
  double endHandleLeft(int endBar) => barLeft(endBar) - gap + 1;
  double endHandleCentre(int endBar) => endHandleLeft(endBar) + handleWidth / 2;
}

class _DraftWaveformPainter extends CustomPainter {
  const _DraftWaveformPainter({
    required this.geometry,
    required this.levels,
    required this.startBar,
    required this.endBar,
    required this.showHandles,
    required this.playhead,
    required this.kept,
    required this.played,
    required this.unplayed,
    required this.cut,
  });

  final _WaveformGeometry geometry;
  final List<double> levels;
  final int startBar;
  final int endBar;
  final bool showHandles;

  /// Playback position as a fraction of the whole recording, once started.
  final double? playhead;
  final Color kept;
  final Color played;
  final Color unplayed;
  final Color cut;

  static const _height = 32.0;
  static const _handleHeight = 28.0;

  double _strength(int bar) {
    if (levels.isEmpty) return 0;
    final count = geometry.bars;
    final step = levels.length / count;
    var peak = double.negativeInfinity;
    if (step <= 1) {
      peak = levels[(bar * step).floor().clamp(0, levels.length - 1)];
    } else {
      final start = (bar * step).floor();
      final end = ((bar + 1) * step).ceil().clamp(start + 1, levels.length);
      for (var index = start; index < end; index++) {
        if (levels[index] > peak) peak = levels[index];
      }
    }
    if (!peak.isFinite) return 0;
    return ((peak.clamp(-60.0, 0.0) + 60) / 60).toDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final top = (size.height - _height) / 2;
    final centreY = size.height / 2;
    if (showHandles) {
      final left = geometry.startHandleLeft(startBar);
      final right =
          geometry.endHandleLeft(endBar) + _WaveformGeometry.handleWidth;
      canvas.drawRRect(
        RRect.fromLTRBR(
          left,
          top,
          right,
          top + _height,
          const Radius.circular(6),
        ),
        Paint()..color = kept.withValues(alpha: 0.10),
      );
    }
    final bar = Paint()
      ..strokeWidth = _WaveformGeometry.barWidth
      ..strokeCap = StrokeCap.round;
    final count = geometry.bars;
    for (var index = 0; index < count; index++) {
      final height = 4 + _strength(index) * 20;
      final x = geometry.barLeft(index) + _WaveformGeometry.barWidth / 2;
      final inKept = index >= startBar && index < endBar;
      final position = playhead;
      bar.color = !inKept
          ? cut
          : position == null || index / count < position
          ? played
          : unplayed;
      // Round caps add half the stroke width at each end.
      final half = math.max(0.0, height / 2 - _WaveformGeometry.barWidth / 2);
      canvas.drawLine(
        Offset(x, centreY - half),
        Offset(x, centreY + half),
        bar,
      );
    }
    if (showHandles) {
      final handle = Paint()..color = kept;
      for (final left in [
        geometry.startHandleLeft(startBar),
        geometry.endHandleLeft(endBar),
      ]) {
        canvas.drawRRect(
          RRect.fromLTRBR(
            left,
            centreY - _handleHeight / 2,
            left + _WaveformGeometry.handleWidth,
            centreY + _handleHeight / 2,
            const Radius.circular(_WaveformGeometry.handleWidth / 2),
          ),
          handle,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DraftWaveformPainter oldDelegate) =>
      oldDelegate.geometry.bars != geometry.bars ||
      oldDelegate.geometry.left != geometry.left ||
      oldDelegate.levels != levels ||
      oldDelegate.startBar != startBar ||
      oldDelegate.endBar != endBar ||
      oldDelegate.showHandles != showHandles ||
      oldDelegate.playhead != playhead ||
      oldDelegate.kept != kept ||
      oldDelegate.played != played ||
      oldDelegate.unplayed != unplayed ||
      oldDelegate.cut != cut;
}
