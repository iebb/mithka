//
//  video_player_view.dart
//
//  Fullscreen player for a `messageVideo`. Starts TDLib download on demand and
//  begins playback as soon as a readable local path exists; the scrubber marks
//  the downloaded/buffered range separately from the played range.
//

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import 'chat_picker_view.dart';
import '../components/photo_avatar.dart';
import '../components/sf_symbols.dart';
import '../components/toast.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';

class _TdVideoStreamServer {
  _TdVideoStreamServer(this.fileId);

  final int fileId;
  HttpServer? _server;
  String? _path;
  int _total = 0;

  static const _chunkSize = 2 * 1024 * 1024;

  Future<Uri?> start() async {
    try {
      final file = await TdClient.shared.query({
        '@type': 'getFile',
        'file_id': fileId,
      });
      _updateFileInfo(file);
    } catch (_) {}

    if (_path == null || _path!.isEmpty) {
      _path = await TdFileCenter.shared.playbackPath(fileId);
    }
    if (_total <= 0) return null;

    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: true,
    );
    _server!.listen(_handleRequest);
    return Uri.parse('http://127.0.0.1:${_server!.port}/video/$fileId.mp4');
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }

  void _updateFileInfo(Map<String, dynamic> file) {
    final expected = file.integer('expected_size') ?? 0;
    final size = file.integer('size') ?? 0;
    if (expected > 0 || size > 0) {
      _total = expected > 0 ? expected : size;
    }
    final path = file.obj('local')?.str('path');
    if (path != null && path.isNotEmpty) _path = path;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
      }

      request.response.headers
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..contentType = ContentType('video', 'mp4');

      if (_total <= 0) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      if (request.method == 'HEAD') {
        request.response
          ..statusCode = HttpStatus.ok
          ..contentLength = _total;
        await request.response.close();
        return;
      }

      final (start, end) = _requestedRange(request);
      final ok = await _ensureRange(start, end);
      if (!ok || _path == null) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
        return;
      }

      final bytes = await _readRange(start, end);
      request.response
        ..statusCode = HttpStatus.partialContent
        ..contentLength = bytes.length;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-${start + bytes.length - 1}/$_total',
      );
      request.response.add(bytes);
      await request.response.close();
    } catch (_) {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }

  (int, int) _requestedRange(HttpRequest request) {
    final header = request.headers.value(HttpHeaders.rangeHeader);
    var start = 0;
    int? requestedEnd;
    if (header != null && header.startsWith('bytes=')) {
      final value = header.substring('bytes='.length).split(',').first.trim();
      final parts = value.split('-');
      start = int.tryParse(parts.first) ?? 0;
      if (parts.length > 1 && parts[1].isNotEmpty) {
        requestedEnd = int.tryParse(parts[1]);
      }
    }
    start = start.clamp(0, math.max(0, _total - 1));
    final end = math.min(
      requestedEnd ?? (start + _chunkSize - 1),
      math.min(_total - 1, start + _chunkSize - 1),
    );
    return (start, end);
  }

  Future<bool> _ensureRange(int start, int end) async {
    final length = end - start + 1;
    try {
      final file = await TdClient.shared
          .query({
            '@type': 'downloadFile',
            'file_id': fileId,
            'priority': 32,
            'offset': start,
            'limit': length,
            'synchronous': true,
          })
          .timeout(const Duration(seconds: 45));
      _updateFileInfo(file);
      return _path != null && _path!.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<List<int>> _readRange(int start, int end) async {
    final path = _path;
    if (path == null || path.isEmpty) return const [];
    final file = File(path);
    final raf = await file.open();
    try {
      await raf.setPosition(start);
      return await raf.read(end - start + 1);
    } finally {
      await raf.close();
    }
  }
}

enum VideoPlayerPresentation { fullscreen, embedded, pictureInPicture }

enum VideoDisplayMode { fullscreen, pictureInPicture, split }

class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({
    super.key,
    required this.video,
    this.thumb,
    this.width,
    this.height,
    this.presentation = VideoPlayerPresentation.fullscreen,
    this.onClose,
    this.compactControls = false,
    this.sourceChatId,
    this.messageId,
    this.currentMode = VideoDisplayMode.fullscreen,
    this.onSwitchMode,
    this.initialMuted = false,
  });

  final TdFileRef video;
  final TdFileRef? thumb;
  final int? width;
  final int? height;
  final VideoPlayerPresentation presentation;
  final VoidCallback? onClose;
  final bool compactControls;
  final int? sourceChatId;
  final int? messageId;
  final VideoDisplayMode currentMode;
  final ValueChanged<VideoDisplayMode>? onSwitchMode;
  final bool initialMuted;

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  StreamSubscription<TdFileProgress>? _progressSub;
  TdFileProgress? _progress;
  double _speed = 1;
  double _volume = 1;
  String? _localPath;
  int _lastProgressBytes = 0;
  DateTime? _lastProgressAt;
  double _downloadSpeed = 0;
  int _lastSavedPositionMs = 0;
  _TdVideoStreamServer? _streamServer;

  static const _speeds = <double>[0.5, 0.75, 1, 1.25, 1.5, 2];
  static const _resumePrefix = 'mithka.video.resume.';
  static const _resumeSaveStep = Duration(seconds: 2);
  static const _resumeMinimum = Duration(seconds: 3);
  static const _resumeEndSlack = Duration(seconds: 8);

  @override
  void initState() {
    super.initState();
    if (widget.initialMuted) _volume = 0;
    _load();
  }

  Future<void> _load() async {
    _progressSub = TdFileCenter.shared.progress(widget.video.id).listen((
      progress,
    ) {
      if (!mounted) return;
      final now = DateTime.now();
      final previousAt = _lastProgressAt;
      final deltaBytes = progress.downloaded - _lastProgressBytes;
      if (previousAt != null && deltaBytes > 0) {
        final seconds =
            now.difference(previousAt).inMilliseconds /
            Duration.millisecondsPerSecond;
        if (seconds > 0) {
          _downloadSpeed = deltaBytes / seconds;
        }
      }
      _lastProgressAt = now;
      _lastProgressBytes = progress.downloaded;
      setState(() => _progress = progress);
    });
    final server = _TdVideoStreamServer(widget.video.id);
    _streamServer = server;
    final uri = await server.start();
    if (!mounted) {
      unawaited(server.close());
      return;
    }
    if (uri == null) {
      setState(() => _failed = true);
      showToast(context, '视频加载失败');
      return;
    }
    _localPath = uri.toString();
    final initialized = await _initializeFromUri(uri);
    if (initialized || !mounted) return;
    setState(() => _failed = true);
    showToast(context, '视频无法播放');
  }

  Future<bool> _initializeFromUri(Uri uri) async {
    final c = VideoPlayerController.networkUrl(uri);
    try {
      await c.initialize().timeout(const Duration(seconds: 45));
      await c.setLooping(false);
      await c.setPlaybackSpeed(_speed);
      await c.setVolume(_volume);
      final resume = await _loadResumePosition(c.value.duration);
      if (resume > Duration.zero) await c.seekTo(resume);
      await c.play();
    } catch (_) {
      await c.dispose();
      return false;
    }
    if (!mounted) {
      await c.dispose();
      return true;
    }
    c.addListener(_onTick);
    setState(() => _controller = c);
    _scheduleHide();
    return true;
  }

  // Rebuild for play/pause + scrubber position changes.
  void _onTick() {
    _storePlaybackPositionIfNeeded();
    if (mounted) setState(() {});
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  Future<void> _togglePlay() async {
    final c = _controller;
    if (c == null) return;
    if (c.value.isPlaying) {
      await c.pause();
      if (!mounted) return;
      setState(() => _controlsVisible = true);
      _hideTimer?.cancel();
    } else {
      // Restart from the beginning if it finished.
      if (c.value.position >= c.value.duration) await c.seekTo(Duration.zero);
      await c.play();
      if (!mounted) return;
      setState(() => _controlsVisible = true);
      _scheduleHide();
    }
  }

  Future<void> _setSpeed(double speed) async {
    final c = _controller;
    if (c == null) return;
    await c.setPlaybackSpeed(speed);
    if (!mounted) return;
    setState(() {
      _speed = speed;
      _controlsVisible = true;
    });
    _scheduleHide();
  }

  void _setVolume(double volume) {
    final next = volume.clamp(0.0, 1.0);
    _controller?.setVolume(next);
    if (!mounted) return;
    setState(() {
      _volume = next;
      _controlsVisible = true;
    });
  }

  String get _resumeKey {
    final chatId = widget.sourceChatId;
    final messageId = widget.messageId;
    if (chatId != null && messageId != null) {
      return '$_resumePrefix$chatId.$messageId';
    }
    return '$_resumePrefix${widget.video.id}';
  }

  Future<Duration> _loadResumePosition(Duration duration) async {
    if (duration <= _resumeMinimum + _resumeEndSlack) return Duration.zero;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_resumeKey) ?? 0;
      final position = Duration(milliseconds: ms);
      if (position < _resumeMinimum) return Duration.zero;
      if (duration - position <= _resumeEndSlack) return Duration.zero;
      return position;
    } catch (_) {
      return Duration.zero;
    }
  }

  void _storePlaybackPositionIfNeeded() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final positionMs = c.value.position.inMilliseconds;
    if ((positionMs - _lastSavedPositionMs).abs() <
        _resumeSaveStep.inMilliseconds) {
      return;
    }
    unawaited(_storePlaybackPosition(force: true));
  }

  Future<void> _storePlaybackPosition({bool force = false}) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final value = c.value;
    final duration = value.duration;
    final position = value.position;
    if (!force &&
        (position.inMilliseconds - _lastSavedPositionMs).abs() <
            _resumeSaveStep.inMilliseconds) {
      return;
    }
    _lastSavedPositionMs = position.inMilliseconds;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (position < _resumeMinimum ||
          (duration > Duration.zero &&
              duration - position <= _resumeEndSlack)) {
        await prefs.remove(_resumeKey);
      } else {
        await prefs.setInt(_resumeKey, position.inMilliseconds);
      }
    } catch (_) {}
  }

  void _close() {
    unawaited(_storePlaybackPosition(force: true));
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _progressSub?.cancel();
    unawaited(_storePlaybackPosition(force: true));
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    unawaited(_streamServer?.close());
    if (_progress?.isCompleted != true) {
      TdFileCenter.shared.cancelDownload(widget.video.id);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    final body = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: ready ? _toggleControls : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            // Scale the video to fill the screen as much as possible while
            // keeping its aspect ratio (no crop).
            Positioned.fill(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: c.value.size.width,
                  height: c.value.size.height,
                  child: VideoPlayer(c),
                ),
              ),
            )
          else
            _loadingState(),
          if (ready && _controlsVisible) ..._controls(c),
          if (!ready || _controlsVisible) _closeButton(),
        ],
      ),
    );
    if (widget.presentation == VideoPlayerPresentation.embedded) {
      return Material(color: Colors.black, child: body);
    }
    if (widget.presentation == VideoPlayerPresentation.pictureInPicture) {
      return Material(type: MaterialType.transparency, child: body);
    }
    return Scaffold(backgroundColor: Colors.black, body: body);
  }

  Widget _closeButton() {
    final pip = widget.presentation == VideoPlayerPresentation.pictureInPicture;
    final embedded = widget.presentation == VideoPlayerPresentation.embedded;
    return Positioned(
      top: pip ? 3 : (embedded ? 8 : MediaQuery.of(context).padding.top + 28),
      left: pip || embedded ? null : 30,
      right: pip ? 4 : (embedded ? 8 : null),
      child: pip || embedded
          ? _plainIconButton('xmark', _close, size: 34)
          : _roundIconButton('chevron.left', _close, size: 58),
    );
  }

  Widget _loadingState() {
    final aspect =
        (widget.width != null &&
            widget.height != null &&
            widget.width! > 0 &&
            widget.height! > 0)
        ? widget.width! / widget.height!
        : 16 / 9;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.thumb != null)
          Center(
            child: AspectRatio(
              aspectRatio: aspect,
              child: TDImage(
                photo: widget.thumb,
                fit: BoxFit.contain,
                showProgress: true,
              ),
            ),
          )
        else
          Center(
            child: AspectRatio(
              aspectRatio: aspect,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF111113),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.10),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.58),
                ],
                stops: const [0, 0.48, 1],
              ),
            ),
          ),
        ),
        if (_failed)
          const Center(
            child: Text(
              '视频加载失败',
              style: TextStyle(color: Colors.white, fontSize: 15),
            ),
          )
        else
          ..._pendingControls(),
      ],
    );
  }

  List<Widget> _pendingControls() {
    if (widget.compactControls) return _pendingCompactControls();
    final bottom = MediaQuery.of(context).padding.bottom + 24;
    return [
      Positioned(
        left: widget.presentation == VideoPlayerPresentation.embedded ? 16 : 54,
        right: widget.presentation == VideoPlayerPresentation.embedded
            ? 16
            : 38,
        bottom: bottom,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 78,
                  height: 64,
                  child: Icon(
                    sfIcon('play.fill'),
                    color: Colors.white.withValues(alpha: 0.7),
                    size: 58,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  '00:00',
                  style: TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _loadingScrubber()),
                const SizedBox(width: 12),
                const Text(
                  '--:--',
                  style: TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (widget.onSwitchMode != null) ...[
                  _modeSwitchButton(),
                  const SizedBox(width: 12),
                ],
                Expanded(child: _loadingDebugText()),
                _volumeSlider(),
                const SizedBox(width: 12),
                _speedMenu(),
                const SizedBox(width: 12),
                _roundIconButton('arrow.down.to.line', _downloadedNotice),
                const SizedBox(width: 12),
                _roundIconButton('arrowshape.turn.up.right', _forwardVideo),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _pendingCompactControls() {
    return [
      Center(
        child: SizedBox(
          width: 54,
          height: 54,
          child: Center(
            child: Icon(
              sfIcon('play.fill'),
              color: Colors.white.withValues(alpha: 0.7),
              size: 32,
            ),
          ),
        ),
      ),
      Positioned(
        left: 12,
        right: 12,
        bottom: 10,
        child: Row(
          children: [
            if (widget.onSwitchMode != null &&
                widget.presentation !=
                    VideoPlayerPresentation.pictureInPicture) ...[
              _modeSwitchButton(size: 34),
              const SizedBox(width: 8),
            ],
            const Text(
              '00:00',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
            const SizedBox(width: 8),
            Expanded(child: _loadingScrubber(compact: true)),
            const SizedBox(width: 8),
            SizedBox(width: 104, child: _volumeSlider(compact: true)),
            const SizedBox(width: 8),
            Text(
              _speedText(_speed),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _loadingScrubber({bool compact = false}) {
    final loaded = (_progress?.prefixFraction ?? _progress?.fraction ?? 0)
        .clamp(0.0, 1.0);
    return SizedBox(
      height: compact ? 28 : 34,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Positioned(
            left: compact ? 0 : 24,
            right: compact ? 0 : 24,
            child: Container(
              height: compact ? 2.5 : 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          Positioned(
            left: compact ? 0 : 24,
            right: compact ? 0 : 24,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: loaded,
              child: Container(
                height: compact ? 2.5 : 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          Positioned(
            left: compact ? 0 : 24,
            child: Container(
              width: compact ? 10 : 16,
              height: compact ? 10 : 16,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _controls(VideoPlayerController c) {
    if (widget.compactControls) return _compactControls(c);
    final value = c.value;
    final playing = value.isPlaying;
    final bottom = MediaQuery.of(context).padding.bottom + 24;
    return [
      Positioned(
        left: widget.presentation == VideoPlayerPresentation.embedded ? 16 : 54,
        right: widget.presentation == VideoPlayerPresentation.embedded
            ? 16
            : 38,
        bottom: bottom,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _togglePlay,
                  child: SizedBox(
                    width: 78,
                    height: 64,
                    child: Icon(
                      sfIcon(playing ? 'pause.fill' : 'play.fill'),
                      color: Colors.white,
                      size: 58,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _fmt(value.position),
                  style: const TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _scrubber(c)),
                const SizedBox(width: 12),
                Text(
                  _fmt(value.duration),
                  style: const TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: _debugText(c)),
                _volumeSlider(),
                const SizedBox(width: 12),
                _speedMenu(),
                const SizedBox(width: 12),
                _roundIconButton('arrow.down.to.line', _downloadedNotice),
                if (widget.onSwitchMode != null) ...[
                  const SizedBox(width: 12),
                  _modeSwitchButton(),
                ],
                const SizedBox(width: 12),
                _roundIconButton('arrowshape.turn.up.right', _forwardVideo),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _compactControls(VideoPlayerController c) {
    final value = c.value;
    return [
      Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _togglePlay,
          child: SizedBox(
            width: 54,
            height: 54,
            child: Center(
              child: Icon(
                sfIcon(value.isPlaying ? 'pause.fill' : 'play.fill'),
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ),
      ),
      Positioned(
        left: 12,
        right: 12,
        bottom: 10,
        child: Row(
          children: [
            if (widget.onSwitchMode != null &&
                widget.presentation !=
                    VideoPlayerPresentation.pictureInPicture) ...[
              _modeSwitchButton(size: 34),
              const SizedBox(width: 8),
            ],
            Text(
              _fmt(value.position),
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
            const SizedBox(width: 8),
            Expanded(child: _scrubber(c)),
            const SizedBox(width: 8),
            SizedBox(width: 104, child: _volumeSlider(compact: true)),
            const SizedBox(width: 8),
            Text(
              _speedText(_speed),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _scrubber(VideoPlayerController c) {
    final value = c.value;
    final duration = value.duration.inMilliseconds;
    final position = value.position.inMilliseconds.clamp(0, duration);
    final loaded = _loadedFraction(value);
    return SizedBox(
      height: 34,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Positioned(
            left: 24,
            right: 24,
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: loaded,
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.transparent,
              disabledInactiveTrackColor: Colors.transparent,
              thumbColor: Colors.white,
              overlayColor: Colors.white.withValues(alpha: 0.14),
            ),
            child: Slider(
              min: 0,
              max: duration <= 0 ? 1 : duration.toDouble(),
              value: duration <= 0 ? 0 : position.toDouble(),
              onChanged: duration <= 0
                  ? null
                  : (v) => c.seekTo(Duration(milliseconds: v.round())),
            ),
          ),
        ],
      ),
    );
  }

  double _loadedFraction(VideoPlayerValue value) {
    final durationMs = value.duration.inMilliseconds;
    if (_progress?.isCompleted == true) return 1;
    final downloadFraction = _progress?.prefixFraction ?? _progress?.fraction;
    var loaded = downloadFraction ?? 0.0;
    if (durationMs > 0 && value.buffered.isNotEmpty) {
      final bufferedEnd = value.buffered
          .map((r) => r.end.inMilliseconds)
          .reduce((a, b) => a > b ? a : b);
      loaded = math.max(loaded, (bufferedEnd / durationMs).clamp(0.0, 1.0));
    }
    if (durationMs > 0) {
      loaded = math.max(
        loaded,
        (value.position.inMilliseconds / durationMs).clamp(0.0, 1.0),
      );
    }
    return loaded.clamp(0.0, 1.0);
  }

  Widget _debugText(VideoPlayerController c) {
    final size = c.value.size;
    final p = _progress;
    final fileLine = p == null
        ? ''
        : '${_byteString(p.downloaded)} / ${_byteString(p.total)} · ${_speedString(_downloadSpeed)}/s';
    return DefaultTextStyle(
      style: const TextStyle(
        color: Color(0xFF8E8E93),
        fontSize: 11,
        height: 1.25,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${size.width.round()}x${size.height.round()} · ${_speedText(_speed)}',
          ),
          Text(fileLine, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _loadingDebugText() {
    final progress = _progress;
    final text = progress == null
        ? '等待视频文件'
        : '${_byteString(progress.downloaded)} / ${_byteString(progress.total)} · ${_speedString(_downloadSpeed)}/s';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _speedMenu() {
    return PopupMenuButton<double>(
      initialValue: _speed,
      tooltip: '播放速度',
      color: const Color(0xFF1C1C1E),
      onSelected: _setSpeed,
      itemBuilder: (_) => [
        for (final speed in _speeds)
          PopupMenuItem<double>(
            value: speed,
            child: Text(
              _speedText(speed),
              style: TextStyle(
                color: speed == _speed ? Colors.white : const Color(0xFFB0B0B6),
                fontWeight: speed == _speed ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
      ],
      child: SizedBox(
        height: 50,
        width: 62,
        child: Center(
          child: Text(
            _speedText(_speed),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _volumeSlider({bool compact = false}) {
    final iconSize = compact ? 14.0 : 18.0;
    return SizedBox(
      width: compact ? null : 152,
      height: compact ? 28 : 38,
      child: Row(
        mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Icon(
            sfIcon(
              _volume <= 0.01 ? 'speaker.slash.fill' : 'speaker.wave.2.fill',
            ),
            color: Colors.white,
            size: iconSize,
          ),
          SizedBox(width: compact ? 4 : 7),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: compact ? 2.5 : 3,
                thumbShape: RoundSliderThumbShape(
                  enabledThumbRadius: compact ? 5 : 7,
                ),
                overlayShape: RoundSliderOverlayShape(
                  overlayRadius: compact ? 10 : 14,
                ),
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.22),
                thumbColor: Colors.white,
                overlayColor: Colors.white.withValues(alpha: 0.14),
              ),
              child: Slider(
                min: 0,
                max: 1,
                value: _volume,
                onChangeStart: (_) => _hideTimer?.cancel(),
                onChanged: _setVolume,
                onChangeEnd: (_) => _scheduleHide(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeSwitchButton({double size = 50}) {
    final callback = widget.onSwitchMode;
    if (callback == null) return const SizedBox.shrink();
    return PopupMenuButton<VideoDisplayMode>(
      tooltip: '切换显示模式',
      color: const Color(0xFF1C1C1E),
      onOpened: () {
        setState(() => _controlsVisible = true);
        _hideTimer?.cancel();
      },
      onCanceled: _scheduleHide,
      onSelected: (mode) {
        if (mode != widget.currentMode) callback(mode);
        _scheduleHide();
      },
      itemBuilder: (_) => [
        _modeItem(VideoDisplayMode.fullscreen, '全屏播放'),
        _modeItem(VideoDisplayMode.pictureInPicture, '画中画'),
        _modeItem(VideoDisplayMode.split, '分屏'),
      ],
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Icon(
            sfIcon('rectangle.split.2x1'),
            color: Colors.white.withValues(alpha: 0.92),
            size: size * 0.5,
          ),
        ),
      ),
    );
  }

  PopupMenuItem<VideoDisplayMode> _modeItem(
    VideoDisplayMode mode,
    String label,
  ) {
    return PopupMenuItem<VideoDisplayMode>(
      value: mode,
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: mode == widget.currentMode
                ? Icon(sfIcon('checkmark'), size: 14, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _roundIconButton(String icon, VoidCallback onTap, {double size = 50}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Icon(
            sfIcon(icon),
            color: Colors.white.withValues(alpha: 0.92),
            size: size * 0.5,
          ),
        ),
      ),
    );
  }

  Widget _plainIconButton(String icon, VoidCallback onTap, {double size = 34}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(
          sfIcon(icon),
          color: Colors.white.withValues(alpha: 0.92),
          size: size * 0.58,
        ),
      ),
    );
  }

  void _downloadedNotice() {
    final path = _localPath;
    final progress = _progress;
    if (progress?.isCompleted == true) {
      showToast(context, '视频已缓存到本地');
    } else if (path != null) {
      showToast(context, '正在边下边播');
    } else {
      showToast(context, '正在加载视频');
    }
  }

  Future<void> _forwardVideo() async {
    final sourceChatId = widget.sourceChatId;
    final messageId = widget.messageId;
    if (sourceChatId == null || messageId == null) {
      showToast(context, '无法转发此视频');
      return;
    }
    final target = await Navigator.of(context).push<ChatSummary>(
      MaterialPageRoute(builder: (_) => const ChatPickerView(title: '转发到')),
    );
    if (target == null || !mounted) return;
    try {
      await TdClient.shared.query({
        '@type': 'forwardMessages',
        'chat_id': target.id,
        'from_chat_id': sourceChatId,
        'message_ids': [messageId],
        'options': {'@type': 'messageSendOptions'},
        'send_copy': false,
        'remove_caption': false,
      });
      if (mounted) showToast(context, '已转发到 ${target.title}');
    } catch (e) {
      if (mounted) showToast(context, '转发失败：$e');
    }
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  static String _speedText(double speed) =>
      speed == speed.roundToDouble() ? '${speed.toInt()}x' : '${speed}x';

  static String _byteString(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit += 1;
    }
    return '${value.toStringAsFixed(value >= 10 || unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  static String _speedString(double bytesPerSecond) {
    if (bytesPerSecond <= 0) return '0 KB';
    return _byteString(bytesPerSecond.round());
  }
}
