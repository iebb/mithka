import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
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

class VoiceNotePreviewResult {
  const VoiceNotePreviewResult({
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

class VoiceNotePreviewView extends StatefulWidget {
  const VoiceNotePreviewView({
    super.key,
    required this.path,
    required this.duration,
    required this.levels,
    this.allowWhenOnline = false,
    this.effects = const [],
  });

  final String path;
  final int duration;
  final List<double> levels;
  final bool allowWhenOnline;
  final List<AvailableMessageEffect> effects;

  @override
  State<VoiceNotePreviewView> createState() => _VoiceNotePreviewViewState();
}

class _VoiceNotePreviewViewState extends State<VoiceNotePreviewView> {
  final _player = FlutterSoundPlayer();
  StreamSubscription<PlaybackDisposition>? _progress;
  bool _ready = false;
  bool _playing = false;
  bool _exporting = false;
  Duration _position = Duration.zero;
  late RangeValues _trimRange;

  @override
  void initState() {
    super.initState();
    _trimRange = RangeValues(0, widget.duration.toDouble());
    unawaited(_prepare());
  }

  double get _trimStart => _trimRange.start;
  double get _trimEnd => _trimRange.end;

  Future<void> _prepare() async {
    await _player.openPlayer();
    await _player.setSubscriptionDuration(const Duration(milliseconds: 60));
    _progress = _player.onProgress?.listen((event) {
      if (!mounted) return;
      if (_playing && event.position.inMilliseconds >= _trimEnd * 1000) {
        unawaited(_resetPlayback());
        return;
      }
      setState(() => _position = event.position);
    });
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _toggle() async {
    if (!_ready) return;
    if (_player.isPlaying) {
      await _player.pausePlayer();
      if (mounted) setState(() => _playing = false);
      return;
    }
    if (_player.isPaused) {
      if (_position.inMilliseconds < _trimStart * 1000 ||
          _position.inMilliseconds >= _trimEnd * 1000) {
        await _player.seekToPlayer(
          Duration(milliseconds: (_trimStart * 1000).round()),
        );
      }
      await _player.resumePlayer();
      if (mounted) setState(() => _playing = true);
      return;
    }
    setState(() => _playing = true);
    await _player.startPlayer(
      fromURI: widget.path,
      codec: Codec.defaultCodec,
      whenFinished: () {
        if (mounted) {
          setState(() {
            _playing = false;
            _position = Duration.zero;
          });
        }
      },
    );
    if (_trimStart > 0) {
      await _player.seekToPlayer(
        Duration(milliseconds: (_trimStart * 1000).round()),
      );
    }
  }

  Future<void> _resetPlayback() async {
    if (_player.isPlaying || _player.isPaused) await _player.stopPlayer();
    if (mounted) {
      setState(() {
        _playing = false;
        _position = Duration(milliseconds: (_trimStart * 1000).round());
      });
    }
  }

  Future<void> _changeTrim(RangeValues values) async {
    final start = values.start.clamp(0.0, widget.duration.toDouble());
    final end = values.end.clamp(start + 0.25, widget.duration.toDouble());
    setState(() {
      _trimRange = RangeValues(start, end);
      _position = Duration(milliseconds: (start * 1000).round());
      _playing = false;
    });
    if (_player.isPlaying || _player.isPaused) await _player.stopPlayer();
  }

  Future<void> _send() async {
    final configuration = await showMessageSendOptionsSheet(
      context,
      allowWhenOnline: widget.allowWhenOnline,
      mediaOptions: true,
      effects: widget.effects,
    );
    if (!mounted || configuration == null) return;
    setState(() => _exporting = true);
    try {
      var path = widget.path;
      var duration = widget.duration;
      if (_trimStart > 0.01 || _trimEnd < widget.duration - 0.01) {
        final trimmed = await VoiceNoteTrimmer.trim(
          inputPath: widget.path,
          startSeconds: _trimStart,
          endSeconds: _trimEnd,
        );
        path = trimmed.path;
        duration = trimmed.durationSeconds;
      }
      final levels = _trimmedLevels();
      if (!mounted) return;
      Navigator.of(context).pop(
        VoiceNotePreviewResult(
          path: path,
          duration: duration,
          waveform: encodeTelegramWaveform(levels),
          sendConfiguration: configuration,
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _exporting = false);
        showToast(context, error.toString());
      }
    }
  }

  List<double> _trimmedLevels() {
    if (widget.levels.isEmpty || widget.duration <= 0) return widget.levels;
    final start = (widget.levels.length * _trimStart / widget.duration)
        .floor()
        .clamp(0, widget.levels.length - 1);
    final end = (widget.levels.length * _trimEnd / widget.duration)
        .ceil()
        .clamp(start + 1, widget.levels.length);
    return widget.levels.sublist(start, end);
  }

  @override
  void dispose() {
    _progress?.cancel();
    _player.closePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final totalMs = widget.duration * 1000;
    final fraction = totalMs <= 0
        ? 0.0
        : (_position.inMilliseconds / totalMs).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: 'Voice message',
            onBack: () => Navigator.of(context).pop(),
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _ready && !_exporting ? _send : null,
              child: Text(
                _exporting ? 'Preparing…' : 'Send',
                style: TextStyle(
                  color: _ready
                      ? AppTheme.brand
                      : AppTheme.brand.withValues(alpha: 0.35),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Container(
                width: 330,
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: c.divider, width: 0.5),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _toggle,
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.brand,
                          shape: BoxShape.circle,
                        ),
                        child: AppIcon(
                          _playing ? HeroAppIcons.pause : HeroAppIcons.play,
                          size: 21,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 34,
                            child: CustomPaint(
                              painter: _WaveformPainter(
                                levels: widget.levels,
                                progress: fraction,
                                inactive: c.textTertiary,
                              ),
                              size: const Size(double.infinity, 34),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${_duration((_position.inMilliseconds / 1000 - _trimStart).clamp(0, _trimEnd - _trimStart).floor())} / '
                            '${_duration((_trimEnd - _trimStart).ceil())}',
                            style: TextStyle(
                              fontSize: 12,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.duration > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        'Trim',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_duration(_trimStart.floor())} – ${_duration(_trimEnd.ceil())}',
                        style: TextStyle(color: c.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                  AppRangeScrubber(
                    start: _trimRange.start,
                    end: _trimRange.end,
                    min: 0,
                    max: widget.duration.toDouble(),
                    minimumGap: 0.25,
                    onChanged: (start, end) {
                      if (!_exporting) {
                        unawaited(_changeTrim(RangeValues(start, end)));
                      }
                    },
                  ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
              child: Text(
                'Review the recording before sending. Send options include '
                'silent delivery, scheduling, effects and view-once.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: c.textTertiary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _duration(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.levels,
    required this.progress,
    required this.inactive,
  });

  final List<double> levels;
  final double progress;
  final Color inactive;

  @override
  void paint(Canvas canvas, Size size) {
    final samples = levels.isEmpty ? const [-36.0] : levels;
    final count = samples.length.clamp(1, 64);
    final stride = samples.length / count;
    final barWidth = (size.width / count * 0.55).clamp(1.5, 3.2);
    for (var index = 0; index < count; index++) {
      final sample = samples[(index * stride).floor()];
      final strength = ((sample.clamp(-60.0, 0.0) + 60) / 60).clamp(0.08, 1.0);
      final height = 4 + strength * (size.height - 4);
      final x = (index + 0.5) * size.width / count;
      final active = index / count <= progress;
      final paint = Paint()
        ..color = active ? AppTheme.brand : inactive
        ..strokeWidth = barWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.levels != levels ||
      oldDelegate.inactive != inactive;
}
