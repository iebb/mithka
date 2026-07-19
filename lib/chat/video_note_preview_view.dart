import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:video_player/video_player.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';
import 'message_send_options.dart';
import 'video_trim_service.dart';

class VideoNotePreviewResult {
  const VideoNotePreviewResult({
    required this.path,
    required this.duration,
    required this.sendConfiguration,
  });

  final String path;
  final int duration;
  final MessageSendConfiguration sendConfiguration;
}

class VideoNotePreviewView extends StatefulWidget {
  const VideoNotePreviewView({
    super.key,
    required this.path,
    this.allowWhenOnline = false,
    this.effects = const [],
  });

  final String path;
  final bool allowWhenOnline;
  final List<AvailableMessageEffect> effects;

  @override
  State<VideoNotePreviewView> createState() => _VideoNotePreviewViewState();
}

class _VideoNotePreviewViewState extends State<VideoNotePreviewView> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _exporting = false;
  RangeValues _trimRange = const RangeValues(0, 0);

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path))
      ..setLooping(true)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {
          _ready = true;
          _trimRange = RangeValues(
            0,
            _controller.value.duration.inMilliseconds.toDouble(),
          );
        });
        _controller.play();
      });
    _controller.addListener(_refresh);
  }

  void _refresh() {
    if (!mounted || !_ready) return;
    if (_controller.value.position.inMilliseconds >= _trimRange.end &&
        _trimRange.end > _trimRange.start) {
      unawaited(
        _controller.seekTo(Duration(milliseconds: _trimRange.start.round())),
      );
    }
    setState(() {});
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  Future<void> _send() async {
    var configuration = const MessageSendConfiguration();
    final advanced = await showMessageSendOptionsSheet(
      context,
      initial: configuration,
      allowWhenOnline: widget.allowWhenOnline,
      mediaOptions: true,
      effects: widget.effects,
    );
    if (!mounted || advanced == null) return;
    configuration = advanced;
    setState(() => _exporting = true);
    var path = widget.path;
    var duration = _controller.value.duration.inSeconds;
    try {
      final totalMs = _controller.value.duration.inMilliseconds;
      if (_trimRange.start > 1 || _trimRange.end < totalMs - 1) {
        path = await VideoTrimService.trim(
          path: widget.path,
          start: Duration(milliseconds: _trimRange.start.round()),
          end: Duration(milliseconds: _trimRange.end.round()),
        );
        duration = ((_trimRange.end - _trimRange.start) / 1000).ceil();
      }
    } catch (_) {
      if (mounted) setState(() => _exporting = false);
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(
      VideoNotePreviewResult(
        path: path,
        duration: duration,
        sendConfiguration: configuration,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final value = _controller.value;
    final totalMs = value.duration.inMilliseconds;
    final progress = totalMs <= 0
        ? 0.0
        : (value.position.inMilliseconds / totalMs).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: colors.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.videoNotePreviewVideoMessage),
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
              child: GestureDetector(
                onTap: () =>
                    value.isPlaying ? _controller.pause() : _controller.play(),
                child: Container(
                  width: 286,
                  height: 286,
                  decoration: BoxDecoration(
                    color: colors.card,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.divider),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: !_ready
                      ? const Center(child: AppActivityIndicator())
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: value.size.width,
                                height: value.size.height,
                                child: VideoPlayer(_controller),
                              ),
                            ),
                            if (!value.isPlaying)
                              Center(
                                child: Container(
                                  width: 58,
                                  height: 58,
                                  alignment: Alignment.center,
                                  decoration: const BoxDecoration(
                                    color: Color(0x99000000),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const AppIcon(
                                    HeroAppIcons.play,
                                    size: 27,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ),
            ),
          ),
          if (_ready)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          _duration(value.position.inSeconds),
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        Expanded(
                          child: AppValueScrubber(
                            value: progress,
                            min: 0,
                            max: 1,
                            onChanged: (fraction) => _controller.seekTo(
                              Duration(
                                milliseconds: (totalMs * fraction).round(),
                              ),
                            ),
                          ),
                        ),
                        Text(
                          _duration(value.duration.inSeconds),
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          AppStrings.t(AppStringKeys.videoNotePreviewTrim),
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Expanded(
                          child: AppRangeScrubber(
                            start: _trimRange.start,
                            end: _trimRange.end,
                            min: 0,
                            max: totalMs.toDouble(),
                            minimumGap: 250,
                            onChanged: (start, end) {
                              if (!_exporting) {
                                setState(
                                  () => _trimRange = RangeValues(start, end),
                                );
                                unawaited(
                                  _controller.seekTo(
                                    Duration(milliseconds: start.round()),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        Text(
                          '${_duration((_trimRange.start / 1000).floor())}–${_duration((_trimRange.end / 1000).ceil())}',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _duration(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
