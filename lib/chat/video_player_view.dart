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
import 'package:mithka/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';
import 'chat_picker_view.dart';

class _TdVideoStreamServer {
  _TdVideoStreamServer(this.fileId);

  final int fileId;
  HttpServer? _server;
  String? _path;
  int _total = 0;
  Future<void> _downloadQueue = Future<void>.value();

  static const _chunkSize = 2 * 1024 * 1024;

  Future<Uri?> start() async {
    try {
      final file = await TdClient.shared.query({
        '@type': 'getFile',
        'file_id': fileId,
      });
      _updateFileInfo(file);
    } catch (_) {}

    if (_path == null || _path!.isEmpty || _total <= 0) {
      await _primePlaybackFile();
    }
    if (_total <= 0) {
      try {
        final file = await TdClient.shared.query({
          '@type': 'getFile',
          'file_id': fileId,
        });
        _updateFileInfo(file);
      } catch (_) {}
    }
    if (_total <= 0 && _path != null && _path!.isNotEmpty) {
      try {
        final localSize = await File(_path!).length();
        if (localSize > 0) _total = localSize;
      } catch (_) {}
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

  Future<void> _primePlaybackFile() async {
    try {
      final file = await TdClient.shared.query({
        '@type': 'downloadFile',
        'file_id': fileId,
        'priority': 30,
        'offset': 0,
        'limit': _chunkSize,
        'synchronous': false,
      });
      _updateFileInfo(file);
    } catch (_) {}
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
      if (bytes.isEmpty) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
        return;
      }
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
      if (parts.first.isEmpty && parts.length > 1) {
        final suffixLength = int.tryParse(parts[1]) ?? 0;
        if (suffixLength > 0) {
          start = math.max(0, _total - suffixLength);
          requestedEnd = _total - 1;
        }
      } else {
        start = int.tryParse(parts.first) ?? 0;
        if (parts.length > 1 && parts[1].isNotEmpty) {
          requestedEnd = int.tryParse(parts[1]);
        }
      }
    }
    start = start.clamp(0, math.max(0, _total - 1));
    final end = math.min(
      math.max(start, requestedEnd ?? (start + _chunkSize - 1)),
      math.min(_total - 1, start + _chunkSize - 1),
    );
    return (start, end);
  }

  Future<bool> _ensureRange(int start, int end) async {
    final length = end - start + 1;
    try {
      final file = await _downloadPlaybackRange(start, length);
      if (file != null) _updateFileInfo(file);
      if (_path == null || _path!.isEmpty) {
        await _primePlaybackFile();
      }
      return _waitForReadableRange(start, end);
    } catch (_) {
      return _waitForReadableRange(start, end);
    }
  }

  Future<Map<String, dynamic>?> _downloadPlaybackRange(int offset, int length) {
    final task = _downloadQueue.then((_) async {
      try {
        return await TdClient.shared
            .query({
              '@type': 'downloadFile',
              'file_id': fileId,
              'priority': 32,
              'offset': offset,
              'limit': length,
              'synchronous': true,
            })
            .timeout(const Duration(seconds: 45));
      } catch (_) {
        return null;
      }
    });
    _downloadQueue = task.then<void>((_) {}, onError: (_) {});
    return task;
  }

  Future<bool> _waitForReadableRange(int start, int end) async {
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final path = _path;
        if (path != null && path.isNotEmpty) {
          final localFile = File(path);
          if (await localFile.exists()) {
            final available = await localFile.length();
            if (available > start) return true;
          }
        }
        final file = await TdClient.shared.query({
          '@type': 'getFile',
          'file_id': fileId,
        });
        _updateFileInfo(file);
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }
    return false;
  }

  Future<List<int>> _readRange(int start, int end) async {
    final path = _path;
    if (path == null || path.isEmpty) return const [];
    final file = File(path);
    final available = await file.length();
    if (available <= start) return const [];
    final readableEnd = math.min(end, available - 1);
    final raf = await file.open();
    try {
      await raf.setPosition(start);
      return await raf.read(readableEnd - start + 1);
    } finally {
      await raf.close();
    }
  }
}

enum VideoPlayerPresentation { fullscreen, embedded, pictureInPicture }

enum VideoDisplayMode { fullscreen, pictureInPicture, split }

class _VideoControlsLayout {
  const _VideoControlsLayout({
    required this.left,
    required this.right,
    required this.playButtonSize,
    required this.playIconSize,
    required this.playGap,
    required this.timeGap,
    required this.timeStyle,
    required this.actionButtonSize,
    required this.actionGap,
    required this.bottomPadding,
    required this.timelineCompact,
    required this.timelineAtBottom,
  });

  final double left;
  final double right;
  final Size playButtonSize;
  final double playIconSize;
  final double playGap;
  final double timeGap;
  final TextStyle timeStyle;
  final double actionButtonSize;
  final double actionGap;
  final double bottomPadding;
  final bool timelineCompact;
  final bool timelineAtBottom;
}

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
  bool _openedCompletedLocalFile = false;

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
    final completedPath = await _completedLocalVideoPath();
    if (!mounted) return;
    if (completedPath != null) {
      _localPath = completedPath;
      _openedCompletedLocalFile = true;
      final initialized = await _initializeFromFile(completedPath);
      if (initialized || !mounted) return;
      _openedCompletedLocalFile = false;
    }
    final server = _TdVideoStreamServer(widget.video.id);
    _streamServer = server;
    final uri = await server.start();
    if (!mounted) {
      unawaited(server.close());
      return;
    }
    if (uri == null) {
      setState(() => _failed = true);
      showToast(context, AppStringKeys.videoPlayerLoadFailed);
      return;
    }
    _localPath = uri.toString();
    final initialized = await _initializeFromUri(uri);
    if (initialized || !mounted) return;
    setState(() => _failed = true);
    showToast(context, AppStringKeys.videoPlayerCannotPlay);
  }

  Future<String?> _completedLocalVideoPath() async {
    try {
      final file = await TdClient.shared.query({
        '@type': 'getFile',
        'file_id': widget.video.id,
      });
      final local = file.obj('local');
      if (local?.boolean('is_downloading_completed') != true) return null;
      final path = local?.str('path');
      if (path == null || path.isEmpty) return null;
      final localFile = File(path);
      if (!await localFile.exists()) return null;
      final length = await localFile.length();
      if (length <= 0) return null;
      final expected = file.integer('expected_size') ?? 0;
      final size = file.integer('size') ?? 0;
      final total = expected > 0 ? expected : size;
      if (total > 0 && length < total) return null;
      _progress = TdFileProgress(
        fileId: widget.video.id,
        downloaded: total > 0 ? total : length,
        prefixDownloaded: total > 0 ? total : length,
        total: total > 0 ? total : length,
        isActive: false,
        isCompleted: true,
      );
      return path;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _initializeFromFile(String path) async {
    final c = VideoPlayerController.file(File(path));
    return _initializeController(c);
  }

  Future<bool> _initializeFromUri(Uri uri) async {
    return _initializeController(VideoPlayerController.networkUrl(uri));
  }

  Future<bool> _initializeController(VideoPlayerController c) async {
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

  void _toggleMute() {
    _hideTimer?.cancel();
    _setVolume(_volume <= 0.01 ? 1 : 0);
    _scheduleHide();
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
    if (!_openedCompletedLocalFile && _progress?.isCompleted != true) {
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
          if (ready) _videoFrame(c) else _loadingState(),
          if (ready && _controlsVisible) ..._controlChromeBlocks(visible: true),
          if (ready && _controlsVisible) _topTechnicalInfo(_debugText(c)),
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

  bool _usesCompactChrome(BuildContext context) {
    return _usesPhoneFullscreen(context) ||
        widget.presentation == VideoPlayerPresentation.embedded;
  }

  List<Widget> _controlChromeBlocks({required bool visible}) {
    if (widget.presentation == VideoPlayerPresentation.pictureInPicture) {
      return const [];
    }
    final media = MediaQuery.of(context);
    final layout = _controlsLayout(context);
    final topInset = widget.presentation == VideoPlayerPresentation.fullscreen
        ? media.padding.top
        : 0.0;
    final bottomInset =
        widget.presentation == VideoPlayerPresentation.fullscreen
        ? media.padding.bottom
        : 0.0;
    final topHeight = topInset + (layout.timelineCompact ? 56 : 104);
    final bottomHeight = bottomInset + _bottomChromeHeight(layout);
    Widget block() {
      return IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          opacity: visible ? 1 : 0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.66),
            ),
          ),
        ),
      );
    }

    return [
      Positioned(left: 0, top: 0, right: 0, height: topHeight, child: block()),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: bottomHeight,
        child: block(),
      ),
    ];
  }

  double _bottomChromeHeight(_VideoControlsLayout layout) {
    final timelineHeight = layout.playButtonSize.height;
    final secondaryHeight = layout.actionButtonSize;
    final contentHeight = layout.timelineAtBottom
        ? secondaryHeight + layout.actionGap + timelineHeight
        : timelineHeight + 24 + secondaryHeight;
    return layout.bottomPadding + contentHeight + 14;
  }

  double _controlsBottom(_VideoControlsLayout layout) {
    final bottomInset =
        widget.presentation == VideoPlayerPresentation.fullscreen
        ? MediaQuery.of(context).padding.bottom
        : 0.0;
    return bottomInset + layout.bottomPadding;
  }

  Widget _topTechnicalInfo(Widget child) {
    final media = MediaQuery.of(context);
    final layout = _controlsLayout(context);
    final topInset = widget.presentation == VideoPlayerPresentation.fullscreen
        ? media.padding.top
        : 0.0;
    return Positioned(
      top: topInset + (layout.timelineCompact ? 10 : 36),
      right: layout.right,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: layout.timelineCompact ? 220 : 300,
        ),
        child: child,
      ),
    );
  }

  Widget _videoFrame(VideoPlayerController c) {
    final videoSize = _displayVideoSize(c);
    if (videoSize.width <= 0 || videoSize.height <= 0) {
      return const SizedBox.expand();
    }
    final alignment = _usesPhonePortraitVideoOffset(context)
        ? const Alignment(0, -0.20)
        : Alignment.center;
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fitted = _containSize(videoSize, constraints.biggest);
          return Align(
            alignment: alignment,
            child: SizedBox(
              width: fitted.width,
              height: fitted.height,
              child: ClipRect(
                child: FittedBox(
                  child: SizedBox(
                    width: videoSize.width,
                    height: videoSize.height,
                    child: VideoPlayer(c),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Size _displayVideoSize(VideoPlayerController c) {
    final metadataAspect = _metadataAspectRatio();
    if (metadataAspect != null) return Size(metadataAspect, 1);

    final controllerAspect = c.value.aspectRatio;
    if (controllerAspect.isFinite && controllerAspect > 0) {
      return Size(controllerAspect, 1);
    }

    final size = c.value.size;
    if (size.width > 0 && size.height > 0) return size;
    return Size.zero;
  }

  double? _metadataAspectRatio() {
    final width = widget.width;
    final height = widget.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return width / height;
  }

  Size _containSize(Size content, Size bounds) {
    if (bounds.width <= 0 || bounds.height <= 0) return Size.zero;
    final scale = math.min(
      bounds.width / content.width,
      bounds.height / content.height,
    );
    return Size(content.width * scale, content.height * scale);
  }

  bool _usesPhoneFullscreen(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return widget.presentation == VideoPlayerPresentation.fullscreen &&
        size.shortestSide < 600;
  }

  bool _usesPhonePortraitVideoOffset(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return _usesPhoneFullscreen(context) && size.height > size.width;
  }

  _VideoControlsLayout _controlsLayout(BuildContext context) {
    final embedded = widget.presentation == VideoPlayerPresentation.embedded;
    final compactChrome = _usesCompactChrome(context);
    return _VideoControlsLayout(
      left: embedded ? 12 : (compactChrome ? 14 : 54),
      right: embedded ? 12 : (compactChrome ? 16 : 38),
      playButtonSize: compactChrome ? const Size(44, 44) : const Size(78, 64),
      playIconSize: compactChrome ? 30 : 58,
      playGap: compactChrome ? 8 : 10,
      timeGap: compactChrome ? 8 : 12,
      timeStyle: TextStyle(
        color: const Color(0xFF8E8E93),
        fontSize: compactChrome ? 15 : 20,
        fontWeight: FontWeight.w500,
      ),
      actionButtonSize: compactChrome ? 36 : 50,
      actionGap: compactChrome ? 8 : 12,
      bottomPadding: compactChrome ? 10 : 24,
      timelineCompact: compactChrome,
      timelineAtBottom: compactChrome,
    );
  }

  Widget _closeButton() {
    final pip = widget.presentation == VideoPlayerPresentation.pictureInPicture;
    final embedded = widget.presentation == VideoPlayerPresentation.embedded;
    final phoneFullscreen = _usesPhoneFullscreen(context);
    return Positioned(
      top: pip
          ? 3
          : (embedded
                ? 8
                : MediaQuery.of(context).padding.top +
                      (phoneFullscreen ? 6 : 28)),
      left: pip || embedded ? null : (phoneFullscreen ? 8 : 30),
      right: pip ? 4 : (embedded ? 8 : null),
      child: pip || embedded
          ? _plainIconButton(HeroAppIcons.xmark.data, _close)
          : _roundIconButton(
              HeroAppIcons.chevronLeft.data,
              _close,
              size: phoneFullscreen ? 44 : 58,
            ),
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
          Center(
            child: Text(
              AppStringKeys.videoPlayerLoadFailed.l10n(context),
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          )
        else ...[
          ..._controlChromeBlocks(visible: true),
          _topTechnicalInfo(_loadingDebugText()),
          ..._pendingControls(),
        ],
      ],
    );
  }

  List<Widget> _pendingControls() {
    if (widget.compactControls) return _pendingCompactControls();
    final layout = _controlsLayout(context);
    final bottom = _controlsBottom(layout);
    final timeline = _pendingTimelineRow(layout);
    final secondary = _pendingSecondaryControls(layout);
    return [
      Positioned(
        left: layout.left,
        right: layout.right,
        bottom: bottom,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: layout.timelineAtBottom
              ? [secondary, SizedBox(height: layout.actionGap), timeline]
              : [timeline, const SizedBox(height: 24), secondary],
        ),
      ),
    ];
  }

  Widget _pendingTimelineRow(_VideoControlsLayout layout) {
    return Row(
      children: [
        SizedBox(
          width: layout.playButtonSize.width,
          height: layout.playButtonSize.height,
          child: Center(
            child: AppIcon(
              HeroAppIcons.play,
              color: Colors.white.withValues(alpha: 0.7),
              size: layout.playIconSize,
            ),
          ),
        ),
        SizedBox(width: layout.playGap),
        Text('00:00', style: layout.timeStyle),
        SizedBox(width: layout.timeGap),
        Expanded(child: _loadingScrubber(compact: layout.timelineCompact)),
        SizedBox(width: layout.timeGap),
        Text('--:--', style: layout.timeStyle),
      ],
    );
  }

  Widget _pendingSecondaryControls(_VideoControlsLayout layout) {
    return Row(
      children: [
        const Spacer(),
        _secondaryVolumeSlider(layout),
        SizedBox(width: layout.actionGap),
        _speedMenu(compact: layout.timelineCompact),
        SizedBox(width: layout.actionGap),
        _roundIconButton(
          HeroAppIcons.download.data,
          _downloadedNotice,
          size: layout.actionButtonSize,
        ),
        if (widget.onSwitchMode != null) ...[
          SizedBox(width: layout.actionGap),
          _modeSwitchButton(size: layout.actionButtonSize),
        ],
        SizedBox(width: layout.actionGap),
        _roundIconButton(
          HeroAppIcons.share.data,
          _forwardVideo,
          size: layout.actionButtonSize,
        ),
      ],
    );
  }

  List<Widget> _pendingCompactControls() {
    final pip = widget.presentation == VideoPlayerPresentation.pictureInPicture;
    return [
      Center(
        child: SizedBox(
          width: 54,
          height: 54,
          child: Center(
            child: AppIcon(
              HeroAppIcons.play,
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
            const Text(
              '00:00',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
            const SizedBox(width: 8),
            Expanded(child: _loadingScrubber(compact: true)),
            const SizedBox(width: 8),
            if (pip)
              _muteButton(size: 34)
            else
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
            if (!pip && widget.onSwitchMode != null) ...[
              const SizedBox(width: 8),
              _modeSwitchButton(size: 34),
            ],
            if (pip && widget.onSwitchMode != null) ...[
              const SizedBox(width: 8),
              _fullscreenButton(size: 34),
            ],
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
    final layout = _controlsLayout(context);
    final bottom = _controlsBottom(layout);
    final timeline = _timelineRow(c, layout);
    final secondary = _secondaryControls(c, layout);
    return [
      Positioned(
        left: layout.left,
        right: layout.right,
        bottom: bottom,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: layout.timelineAtBottom
              ? [secondary, SizedBox(height: layout.actionGap), timeline]
              : [timeline, const SizedBox(height: 24), secondary],
        ),
      ),
    ];
  }

  Widget _timelineRow(VideoPlayerController c, _VideoControlsLayout layout) {
    final value = c.value;
    final playing = value.isPlaying;
    return Row(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _togglePlay,
          child: SizedBox(
            width: layout.playButtonSize.width,
            height: layout.playButtonSize.height,
            child: Center(
              child: AppIcon(
                playing ? HeroAppIcons.pause : HeroAppIcons.play,
                color: Colors.white,
                size: layout.playIconSize,
              ),
            ),
          ),
        ),
        SizedBox(width: layout.playGap),
        Text(_fmt(value.position), style: layout.timeStyle),
        SizedBox(width: layout.timeGap),
        Expanded(child: _scrubber(c, compact: layout.timelineCompact)),
        SizedBox(width: layout.timeGap),
        Text(_fmt(value.duration), style: layout.timeStyle),
      ],
    );
  }

  Widget _secondaryControls(
    VideoPlayerController c,
    _VideoControlsLayout layout,
  ) {
    return Row(
      children: [
        const Spacer(),
        _secondaryVolumeSlider(layout),
        SizedBox(width: layout.actionGap),
        _speedMenu(compact: layout.timelineCompact),
        SizedBox(width: layout.actionGap),
        _roundIconButton(
          HeroAppIcons.download.data,
          _downloadedNotice,
          size: layout.actionButtonSize,
        ),
        if (widget.onSwitchMode != null) ...[
          SizedBox(width: layout.actionGap),
          _modeSwitchButton(size: layout.actionButtonSize),
        ],
        SizedBox(width: layout.actionGap),
        _roundIconButton(
          HeroAppIcons.share.data,
          _forwardVideo,
          size: layout.actionButtonSize,
        ),
      ],
    );
  }

  Widget _secondaryVolumeSlider(_VideoControlsLayout layout) {
    if (!layout.timelineCompact) return _volumeSlider();
    return SizedBox(width: 82, child: _volumeSlider(compact: true));
  }

  List<Widget> _compactControls(VideoPlayerController c) {
    final value = c.value;
    final pip = widget.presentation == VideoPlayerPresentation.pictureInPicture;
    return [
      Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _togglePlay,
          child: SizedBox(
            width: 54,
            height: 54,
            child: Center(
              child: AppIcon(
                value.isPlaying ? HeroAppIcons.pause : HeroAppIcons.play,
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
            if (!pip && widget.onSwitchMode != null) ...[
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
            if (pip)
              _muteButton(size: 34)
            else
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
            if (pip && widget.onSwitchMode != null) ...[
              const SizedBox(width: 8),
              _fullscreenButton(size: 34),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _scrubber(VideoPlayerController c, {bool compact = false}) {
    final value = c.value;
    final duration = value.duration.inMilliseconds;
    final position = value.position.inMilliseconds.clamp(0, duration);
    final loaded = _loadedFraction(value);
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
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: compact ? 2.5 : 4,
              thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: compact ? 5 : 8,
              ),
              overlayShape: RoundSliderOverlayShape(
                overlayRadius: compact ? 10 : 16,
              ),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.transparent,
              disabledInactiveTrackColor: Colors.transparent,
              thumbColor: Colors.white,
              overlayColor: Colors.white.withValues(alpha: 0.14),
            ),
            child: Slider(
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
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${size.width.round()}x${size.height.round()} · ${_speedText(_speed)}',
            textAlign: TextAlign.right,
          ),
          Text(
            fileLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
          ),
        ],
      ),
    );
  }

  Widget _loadingDebugText() {
    final progress = _progress;
    final text = progress == null
        ? AppStringKeys.videoPlayerWaitingForFile.l10n(context)
        : '${_byteString(progress.downloaded)} / ${_byteString(progress.total)} · ${_speedString(_downloadSpeed)}/s';
    return DefaultTextStyle(
      style: const TextStyle(
        color: Color(0xFF8E8E93),
        fontSize: 11,
        height: 1.25,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.width ?? 0}x${widget.height ?? 0} · ${_speedText(_speed)}',
            textAlign: TextAlign.right,
          ),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
          ),
        ],
      ),
    );
  }

  Widget _speedMenu({bool compact = false}) {
    return PopupMenuButton<double>(
      initialValue: _speed,
      tooltip: AppStringKeys.videoPlayerPlaybackSpeed.l10n(context),
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
        height: compact ? 36 : 50,
        width: compact ? 44 : 62,
        child: Center(
          child: Text(
            _speedText(_speed),
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 13 : 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _volumeSlider({bool compact = false}) {
    final iconSize = compact ? 15.0 : 18.0;
    return SizedBox(
      width: compact ? null : 152,
      height: compact ? 36 : 38,
      child: Row(
        mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleMute,
            child: SizedBox(
              width: compact ? 24 : 28,
              height: compact ? 36 : 38,
              child: Center(
                child: Icon(
                  _volumeIconData,
                  color: Colors.white,
                  size: iconSize,
                ),
              ),
            ),
          ),
          SizedBox(width: compact ? 0 : 7),
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

  IconData get _volumeIconData => _volume <= 0.01
      ? HeroAppIcons.volumeXmark.data
      : HeroAppIcons.volumeHigh.data;

  Widget _muteButton({required double size}) {
    return _roundIconButton(_volumeIconData, _toggleMute, size: size);
  }

  Widget _fullscreenButton({required double size}) {
    final callback = widget.onSwitchMode;
    if (callback == null) return const SizedBox.shrink();
    return _roundIconButton(HeroAppIcons.expand.data, () {
      callback(VideoDisplayMode.fullscreen);
      _scheduleHide();
    }, size: size);
  }

  Widget _modeSwitchButton({double size = 50}) {
    final callback = widget.onSwitchMode;
    if (callback == null) return const SizedBox.shrink();
    return PopupMenuButton<VideoDisplayMode>(
      tooltip: AppStringKeys.videoPlayerToggleDisplayMode.l10n(context),
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
        _modeItem(
          VideoDisplayMode.fullscreen,
          AppStringKeys.videoPlayerFullscreen,
        ),
        _modeItem(
          VideoDisplayMode.pictureInPicture,
          AppStringKeys.videoPlayerPictureInPicture,
        ),
        _modeItem(VideoDisplayMode.split, AppStringKeys.videoPlayerSplitScreen),
      ],
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: AppIcon(
            HeroAppIcons.tableColumns,
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
                ? const AppIcon(
                    HeroAppIcons.check,
                    size: 14,
                    color: Colors.white,
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Text(
            label.l10n(context),
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _roundIconButton(
    IconData icon,
    VoidCallback onTap, {
    double size = 50,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Icon(
            icon,
            color: Colors.white.withValues(alpha: 0.92),
            size: size * 0.5,
          ),
        ),
      ),
    );
  }

  Widget _plainIconButton(
    IconData icon,
    VoidCallback onTap, {
    double size = 34,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(
          icon,
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
      showToast(context, AppStringKeys.videoPlayerCachedLocally);
    } else if (path != null) {
      showToast(context, AppStringKeys.videoPlayerStreamingWhileDownloading);
    } else {
      showToast(context, AppStringKeys.videoPlayerLoading);
    }
  }

  Future<void> _forwardVideo() async {
    final sourceChatId = widget.sourceChatId;
    final messageId = widget.messageId;
    if (sourceChatId == null || messageId == null) {
      showToast(context, AppStringKeys.videoPlayerForwardUnsupported);
      return;
    }
    final target = await Navigator.of(context).push<ChatSummary>(
      MaterialPageRoute(
        builder: (_) =>
            const ChatPickerView(title: AppStringKeys.chatForwardToTitle),
      ),
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
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.chatForwardedToName, {
            'value1': target.title,
          }),
        );
      }
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.chatForwardFailed, {'value1': e}),
        );
      }
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
