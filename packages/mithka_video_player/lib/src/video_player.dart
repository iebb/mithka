import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'video_slider.dart';
import 'video_thumbnail.dart';

enum MithkaVideoSourceKind { network, file, asset }

class MithkaVideoSource {
  const MithkaVideoSource.network(this.location)
    : kind = MithkaVideoSourceKind.network,
      package = null;

  const MithkaVideoSource.file(this.location)
    : kind = MithkaVideoSourceKind.file,
      package = null;

  const MithkaVideoSource.asset(this.location, {this.package})
    : kind = MithkaVideoSourceKind.asset;

  factory MithkaVideoSource.uri(Uri uri) => uri.scheme == 'file'
      ? MithkaVideoSource.file(uri.toFilePath())
      : MithkaVideoSource.network(uri.toString());

  final MithkaVideoSourceKind kind;
  final String location;
  final String? package;

  String? get thumbnailLocation => switch (kind) {
    MithkaVideoSourceKind.network || MithkaVideoSourceKind.file => location,
    MithkaVideoSourceKind.asset => null,
  };

  VideoPlayerController createController() => switch (kind) {
    MithkaVideoSourceKind.network => VideoPlayerController.networkUrl(
      Uri.parse(location),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    ),
    MithkaVideoSourceKind.file => VideoPlayerController.file(
      File(location),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    ),
    MithkaVideoSourceKind.asset => VideoPlayerController.asset(
      location,
      package: package,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    ),
  };
}

class MithkaVideoPlayerLabels {
  const MithkaVideoPlayerLabels({
    this.play = 'Play',
    this.pause = 'Pause',
    this.mute = 'Mute',
    this.unmute = 'Unmute',
    this.fullscreen = 'Fullscreen',
    this.close = 'Close',
    this.loading = 'Loading video',
    this.failed = 'This video could not be played',
    this.speed = 'Playback speed',
  });

  final String play;
  final String pause;
  final String mute;
  final String unmute;
  final String fullscreen;
  final String close;
  final String loading;
  final String failed;
  final String speed;
}

class MithkaVideoPlayer extends StatefulWidget {
  const MithkaVideoPlayer({
    super.key,
    required this.source,
    this.width,
    this.height,
    this.autoplay = true,
    this.looping = false,
    this.initialMuted = false,
    this.initialPosition,
    this.onClose,
    this.onToggleFullscreen,
    this.onReady,
    this.onEnded,
    this.onPositionChanged,
    this.labels = const MithkaVideoPlayerLabels(),
    this.accentColor = const Color(0xFFFFFFFF),
    this.backgroundColor = const Color(0xFF000000),
    this.controller,
  });

  final MithkaVideoSource source;
  final int? width;
  final int? height;
  final bool autoplay;
  final bool looping;
  final bool initialMuted;
  final Duration? initialPosition;
  final VoidCallback? onClose;
  final VoidCallback? onToggleFullscreen;
  final ValueChanged<VideoPlayerController>? onReady;
  final VoidCallback? onEnded;
  final ValueChanged<Duration>? onPositionChanged;
  final MithkaVideoPlayerLabels labels;
  final Color accentColor;
  final Color backgroundColor;

  /// Optional preconfigured controller, primarily for custom platform backends.
  /// The caller retains ownership when supplied.
  final VideoPlayerController? controller;

  @override
  State<MithkaVideoPlayer> createState() => _MithkaVideoPlayerState();
}

class _MithkaVideoPlayerState extends State<MithkaVideoPlayer> {
  VideoPlayerController? _controller;
  Timer? _hideTimer;
  Timer? _previewTimer;
  Timer? _positionRefreshTimer;
  bool _controlsVisible = true;
  bool _failed = false;
  bool _ended = false;
  bool _ownsController = false;
  bool _resumeAfterScrub = false;
  double _volume = 1;
  double _lastAudibleVolume = 1;
  double _speed = 1;
  Duration? _scrubPosition;
  Uint8List? _previewBytes;
  int _previewGeneration = 0;
  bool _previewLoading = false;
  int? _pendingPreviewBucket;
  VideoPlayerValue? _lastRenderedValue;
  Duration _lastReportedPosition = Duration.zero;
  final Map<int, Uint8List> _previewCache = {};
  final FocusNode _focusNode = FocusNode(debugLabel: 'mithka-video-player');

  static const _speeds = <double>[0.5, 0.75, 1, 1.25, 1.5, 2];

  @override
  void initState() {
    super.initState();
    _volume = widget.initialMuted ? 0 : 1;
    _lastAudibleVolume = widget.initialMuted ? 1 : _volume;
    unawaited(_initialize());
  }

  @override
  void didUpdateWidget(covariant MithkaVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.kind != widget.source.kind ||
        oldWidget.source.location != widget.source.location ||
        oldWidget.controller != widget.controller) {
      unawaited(_replaceController());
    }
  }

  Future<void> _replaceController() async {
    _hideTimer?.cancel();
    final old = _controller;
    final owned = _ownsController;
    _controller = null;
    _ownsController = false;
    if (owned) await old?.dispose();
    if (mounted) {
      setState(() {
        _failed = false;
        _ended = false;
      });
    }
    await _initialize();
  }

  Future<void> _initialize() async {
    final controller = widget.controller ?? widget.source.createController();
    _ownsController = widget.controller == null;
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(widget.looping);
      await controller.setVolume(_volume);
      final initialPosition = widget.initialPosition;
      if (initialPosition != null && initialPosition > Duration.zero) {
        await controller.seekTo(initialPosition);
      }
      controller.addListener(_onControllerChanged);
      if (widget.autoplay) await controller.play();
      if (!mounted || _controller != controller) return;
      _lastRenderedValue = controller.value;
      widget.onReady?.call(controller);
      setState(() {});
      _focusNode.requestFocus();
      _scheduleHide();
    } catch (_) {
      if (mounted && _controller == controller) setState(() => _failed = true);
    }
  }

  void _onControllerChanged() {
    final controller = _controller;
    if (!mounted || controller == null) return;
    final value = controller.value;
    if ((value.position - _lastReportedPosition).abs() >=
        const Duration(milliseconds: 250)) {
      _lastReportedPosition = value.position;
      widget.onPositionChanged?.call(value.position);
    }
    final completed =
        value.isInitialized &&
        value.duration > Duration.zero &&
        value.position >= value.duration - const Duration(milliseconds: 250);
    var needsImmediateRefresh = false;
    if (completed && !_ended && !widget.looping) {
      _ended = true;
      widget.onEnded?.call();
      _controlsVisible = true;
      needsImmediateRefresh = true;
    } else if (!completed && _ended) {
      _ended = false;
      needsImmediateRefresh = true;
    }
    final previous = _lastRenderedValue;
    if (previous == null ||
        previous.isPlaying != value.isPlaying ||
        previous.isBuffering != value.isBuffering ||
        previous.hasError != value.hasError ||
        previous.duration != value.duration) {
      needsImmediateRefresh = true;
    }
    _lastRenderedValue = value;
    if (needsImmediateRefresh) {
      _positionRefreshTimer?.cancel();
      _positionRefreshTimer = null;
      setState(() {});
    } else if (_controlsVisible && _positionRefreshTimer == null) {
      // The texture renders independently; controls only need a human-readable
      // position refresh rather than rebuilding for every decoded frame.
      _positionRefreshTimer = Timer(const Duration(milliseconds: 100), () {
        _positionRefreshTimer = null;
        if (mounted && _controlsVisible) setState(() {});
      });
    }
  }

  void _showControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    final playing = _controller?.value.isPlaying == true;
    if (!playing || _scrubPosition != null) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_ended) {
      await controller.seekTo(Duration.zero);
      _ended = false;
    }
    controller.value.isPlaying
        ? await controller.pause()
        : await controller.play();
    _showControls();
  }

  Future<void> _seekBy(Duration delta) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final duration = controller.value.duration;
    final target = controller.value.position + delta;
    await controller.seekTo(
      target < Duration.zero
          ? Duration.zero
          : target > duration
          ? duration
          : target,
    );
    _showControls();
  }

  Future<void> _setVolume(double value) async {
    final next = value.clamp(0.0, 1.0);
    if (next > 0) _lastAudibleVolume = next;
    _volume = next;
    await _controller?.setVolume(next);
    if (mounted) setState(() {});
    _showControls();
  }

  void _toggleMute() => unawaited(
    _setVolume(_volume > 0 ? 0 : math.max(0.2, _lastAudibleVolume)),
  );

  Future<void> _cycleSpeed() async {
    final index = _speeds.indexOf(_speed);
    _speed = _speeds[(index + 1) % _speeds.length];
    await _controller?.setPlaybackSpeed(_speed);
    if (mounted) setState(() {});
    _showControls();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
      unawaited(_togglePlayback());
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.keyJ) {
      unawaited(_seekBy(const Duration(seconds: -10)));
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyL) {
      unawaited(_seekBy(const Duration(seconds: 10)));
    } else if (key == LogicalKeyboardKey.arrowUp) {
      unawaited(_setVolume(_volume + 0.05));
    } else if (key == LogicalKeyboardKey.arrowDown) {
      unawaited(_setVolume(_volume - 0.05));
    } else if (key == LogicalKeyboardKey.keyM) {
      _toggleMute();
    } else if (key == LogicalKeyboardKey.keyF) {
      widget.onToggleFullscreen?.call();
    } else if (key == LogicalKeyboardKey.escape && widget.onClose != null) {
      widget.onClose!.call();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _beginScrub(double fraction) {
    final controller = _controller;
    if (controller == null) return;
    _hideTimer?.cancel();
    _resumeAfterScrub = controller.value.isPlaying;
    unawaited(controller.pause());
    _updateScrub(fraction);
  }

  void _updateScrub(double fraction) {
    final duration = _controller?.value.duration ?? Duration.zero;
    final position = duration * fraction;
    _queuePreview(position);
    setState(() => _scrubPosition = position);
  }

  Future<void> _endScrub(double fraction) async {
    final controller = _controller;
    if (controller == null) return;
    final position = controller.value.duration * fraction;
    await controller.seekTo(position);
    if (_resumeAfterScrub) await controller.play();
    _resumeAfterScrub = false;
    _previewGeneration++;
    _pendingPreviewBucket = null;
    if (mounted) {
      setState(() {
        _scrubPosition = null;
        _previewBytes = null;
      });
    }
    _scheduleHide();
  }

  void _queuePreview(Duration position) {
    final source = widget.source.thumbnailLocation;
    if (source == null) return;
    final bucket = (position.inMilliseconds ~/ 500) * 500;
    final cached = _previewCache[bucket];
    if (cached != null) {
      _pendingPreviewBucket = null;
      _previewBytes = cached;
      return;
    }
    _previewBytes = null;
    _pendingPreviewBucket = bucket;
    _previewTimer?.cancel();
    _previewGeneration++;
    _previewTimer = Timer(
      const Duration(milliseconds: 100),
      () => unawaited(_drainPreviewQueue(source)),
    );
  }

  Future<void> _drainPreviewQueue(String source) async {
    if (_previewLoading) return;
    final bucket = _pendingPreviewBucket;
    if (bucket == null) return;
    _pendingPreviewBucket = null;
    final generation = _previewGeneration;
    _previewLoading = true;
    Uint8List? bytes;
    try {
      bytes = await MithkaVideoThumbnail.generate(
        source: source,
        position: Duration(milliseconds: bucket),
      );
    } catch (_) {
      bytes = null;
    } finally {
      _previewLoading = false;
    }
    if (mounted &&
        generation == _previewGeneration &&
        _scrubPosition != null &&
        bytes != null) {
      _previewCache[bucket] = bytes;
      while (_previewCache.length > 24) {
        _previewCache.remove(_previewCache.keys.first);
      }
      setState(() => _previewBytes = bytes);
    }
    if (_pendingPreviewBucket != null) {
      unawaited(_drainPreviewQueue(source));
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _previewTimer?.cancel();
    _positionRefreshTimer?.cancel();
    _focusNode.dispose();
    final controller = _controller;
    controller?.removeListener(_onControllerChanged);
    if (_ownsController) unawaited(controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: MouseRegion(
        cursor: _controlsVisible
            ? SystemMouseCursors.basic
            : SystemMouseCursors.none,
        onHover: (_) => _showControls(),
        child: ColoredBox(
          color: widget.backgroundColor,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 700;
              if (_failed) return _errorView();
              if (controller == null || !controller.value.isInitialized) {
                return _loadingView();
              }
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() => _controlsVisible = !_controlsVisible);
                  if (_controlsVisible) _scheduleHide();
                },
                onDoubleTapDown: (details) {
                  final fraction =
                      details.localPosition.dx / constraints.maxWidth;
                  if (fraction < 0.42) {
                    unawaited(_seekBy(const Duration(seconds: -10)));
                  } else if (fraction > 0.58) {
                    unawaited(_seekBy(const Duration(seconds: 10)));
                  } else {
                    unawaited(_togglePlayback());
                  }
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: AspectRatio(
                        aspectRatio: _aspectRatio(controller),
                        child: VideoPlayer(controller),
                      ),
                    ),
                    if (controller.value.isBuffering)
                      const Center(
                        child: SizedBox.square(
                          dimension: 32,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Color(0xFFFFFFFF),
                          ),
                        ),
                      ),
                    IgnorePointer(
                      ignoring: !_controlsVisible,
                      child: AnimatedOpacity(
                        opacity: _controlsVisible ? 1 : 0,
                        duration: const Duration(milliseconds: 170),
                        child: _controls(controller, wide),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  double _aspectRatio(VideoPlayerController controller) {
    if (widget.width != null &&
        widget.height != null &&
        widget.width! > 0 &&
        widget.height! > 0) {
      return widget.width! / widget.height!;
    }
    final ratio = controller.value.aspectRatio;
    return ratio > 0 ? ratio : 16 / 9;
  }

  Widget _loadingView() => Center(
    child: Semantics(
      label: widget.labels.loading,
      child: const SizedBox.square(
        dimension: 34,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: Color(0xFFFFFFFF),
        ),
      ),
    ),
  );

  Widget _errorView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        widget.labels.failed,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 15),
      ),
    ),
  );

  Widget _controls(VideoPlayerController controller, bool wide) {
    final value = controller.value;
    final durationMs = math.max(1, value.duration.inMilliseconds);
    final position = _scrubPosition ?? value.position;
    final fraction = (position.inMilliseconds / durationMs).clamp(0.0, 1.0);
    final buffered = value.buffered.isEmpty
        ? 0.0
        : (value.buffered.last.end.inMilliseconds / durationMs).clamp(0.0, 1.0);
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x66000000),
                  Color(0x00000000),
                  Color(0xB8000000),
                ],
                stops: [0, 0.48, 1],
              ),
            ),
          ),
        ),
        if (widget.onClose != null)
          Positioned(
            top: 14,
            left: 14,
            child: _controlButton(
              glyph: _Glyph.close,
              label: widget.labels.close,
              onTap: widget.onClose!,
              size: 42,
            ),
          ),
        Center(
          child: _controlButton(
            glyph: value.isPlaying ? _Glyph.pause : _Glyph.play,
            label: value.isPlaying ? widget.labels.pause : widget.labels.play,
            onTap: _togglePlayback,
            size: wide ? 68 : 56,
            filled: true,
          ),
        ),
        Positioned(
          left: wide ? 24 : 14,
          right: wide ? 24 : 14,
          bottom: wide ? 20 : 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LayoutBuilder(
                builder: (context, constraints) => SizedBox(
                  height: wide ? 28 : 24,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: MithkaVideoSlider(
                          value: fraction,
                          bufferedValue: buffered,
                          trackHeight: wide ? 4 : 3,
                          thumbRadius: wide ? 7 : 6,
                          activeColor: widget.accentColor,
                          bufferedColor: const Color(0x99FFFFFF),
                          inactiveColor: const Color(0x55FFFFFF),
                          onChangeStart: _beginScrub,
                          onChanged: _updateScrub,
                          onChangeEnd: _endScrub,
                        ),
                      ),
                      if (_scrubPosition != null && _previewBytes != null)
                        _scrubPreview(
                          constraints.maxWidth,
                          fraction,
                          position,
                          wide,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  _controlButton(
                    glyph: value.isPlaying ? _Glyph.pause : _Glyph.play,
                    label: value.isPlaying
                        ? widget.labels.pause
                        : widget.labels.play,
                    onTap: _togglePlayback,
                  ),
                  const SizedBox(width: 4),
                  _controlButton(
                    glyph: _volume == 0 ? _Glyph.muted : _Glyph.volume,
                    label: _volume == 0
                        ? widget.labels.unmute
                        : widget.labels.mute,
                    onTap: _toggleMute,
                  ),
                  if (wide) ...[
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 92,
                      height: 28,
                      child: MithkaVideoSlider(
                        value: _volume,
                        trackHeight: 3,
                        thumbRadius: 5,
                        activeColor: const Color(0xFFFFFFFF),
                        inactiveColor: const Color(0x55FFFFFF),
                        onChanged: (next) => unawaited(_setVolume(next)),
                      ),
                    ),
                  ],
                  const SizedBox(width: 10),
                  Text(
                    '${_format(position)} / ${_format(value.duration)}',
                    style: TextStyle(
                      color: const Color(0xFFFFFFFF),
                      fontSize: wide ? 13 : 12,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),
                  Semantics(
                    button: true,
                    label: widget.labels.speed,
                    child: GestureDetector(
                      onTap: _cycleSpeed,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Text(
                          '${_speed.toStringAsFixed(_speed % 1 == 0 ? 0 : 2)}x',
                          style: const TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.onToggleFullscreen != null)
                    _controlButton(
                      glyph: _Glyph.fullscreen,
                      label: widget.labels.fullscreen,
                      onTap: widget.onToggleFullscreen!,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _scrubPreview(
    double trackWidth,
    double fraction,
    Duration position,
    bool wide,
  ) {
    final previewWidth = wide ? 160.0 : 128.0;
    final sourceAspect =
        widget.width != null &&
            widget.height != null &&
            widget.width! > 0 &&
            widget.height! > 0
        ? widget.width! / widget.height!
        : 16 / 9;
    final previewHeight = (previewWidth / sourceAspect)
        .clamp(72.0, 110.0)
        .toDouble();
    final left = (trackWidth * fraction - previewWidth / 2)
        .clamp(0.0, math.max(0.0, trackWidth - previewWidth))
        .toDouble();
    return Positioned(
      left: left,
      bottom: (wide ? 28 : 24) + 8,
      width: previewWidth,
      height: previewHeight,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF111113),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0x38FFFFFF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x88000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  _previewBytes!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xCC000000)],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 12, 6, 5),
                      child: Text(
                        _format(position),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFFFFFFF),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _controlButton({
    required _Glyph glyph,
    required String label,
    required VoidCallback onTap,
    double size = 40,
    bool filled = false,
  }) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
        decoration: filled
            ? const BoxDecoration(
                color: Color(0x66000000),
                shape: BoxShape.circle,
              )
            : null,
        alignment: Alignment.center,
        child: CustomPaint(
          size: Size.square(size * (filled ? 0.42 : 0.48)),
          painter: _GlyphPainter(glyph),
        ),
      ),
    ),
  );

  static String _format(Duration value) {
    final seconds = math.max(0, value.inSeconds);
    final hours = seconds ~/ 3600;
    final minutes = (seconds ~/ 60) % 60;
    final remainder = seconds % 60;
    return hours > 0
        ? '$hours:${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}'
        : '$minutes:${remainder.toString().padLeft(2, '0')}';
  }
}

enum _Glyph { play, pause, volume, muted, fullscreen, close }

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph);

  final _Glyph glyph;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = math.max(1.8, size.width * 0.09)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final w = size.width;
    final h = size.height;
    switch (glyph) {
      case _Glyph.play:
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.32, h * 0.16)
            ..lineTo(w * 0.78, h * 0.5)
            ..lineTo(w * 0.32, h * 0.84)
            ..close(),
          paint..style = PaintingStyle.fill,
        );
      case _Glyph.pause:
        paint.style = PaintingStyle.fill;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.26, h * 0.18, w * 0.16, h * 0.64),
            Radius.circular(w * 0.04),
          ),
          paint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.58, h * 0.18, w * 0.16, h * 0.64),
            Radius.circular(w * 0.04),
          ),
          paint,
        );
      case _Glyph.volume:
      case _Glyph.muted:
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.14, h * 0.4)
            ..lineTo(w * 0.34, h * 0.4)
            ..lineTo(w * 0.55, h * 0.2)
            ..lineTo(w * 0.55, h * 0.8)
            ..lineTo(w * 0.34, h * 0.6)
            ..lineTo(w * 0.14, h * 0.6)
            ..close(),
          paint,
        );
        if (glyph == _Glyph.volume) {
          canvas.drawArc(
            Rect.fromCenter(
              center: Offset(w * 0.54, h * 0.5),
              width: w * 0.56,
              height: h * 0.62,
            ),
            -math.pi / 3,
            math.pi * 2 / 3,
            false,
            paint,
          );
        } else {
          canvas.drawLine(
            Offset(w * 0.68, h * 0.35),
            Offset(w * 0.9, h * 0.65),
            paint,
          );
          canvas.drawLine(
            Offset(w * 0.9, h * 0.35),
            Offset(w * 0.68, h * 0.65),
            paint,
          );
        }
      case _Glyph.fullscreen:
        final inset = w * 0.16;
        final length = w * 0.25;
        canvas.drawPath(
          Path()
            ..moveTo(inset + length, inset)
            ..lineTo(inset, inset)
            ..lineTo(inset, inset + length)
            ..moveTo(w - inset - length, inset)
            ..lineTo(w - inset, inset)
            ..lineTo(w - inset, inset + length)
            ..moveTo(inset, h - inset - length)
            ..lineTo(inset, h - inset)
            ..lineTo(inset + length, h - inset)
            ..moveTo(w - inset - length, h - inset)
            ..lineTo(w - inset, h - inset)
            ..lineTo(w - inset, h - inset - length),
          paint,
        );
      case _Glyph.close:
        canvas.drawLine(
          Offset(w * 0.2, h * 0.2),
          Offset(w * 0.8, h * 0.8),
          paint,
        );
        canvas.drawLine(
          Offset(w * 0.8, h * 0.2),
          Offset(w * 0.2, h * 0.8),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) => oldDelegate.glyph != glyph;
}
