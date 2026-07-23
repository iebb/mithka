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
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:fvp/fvp.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail_gen/video_thumbnail_gen.dart';

import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../platform/player_brightness.dart';
import '../platform/screen_wakelock.dart';
import '../platform/system_picture_in_picture.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';
import 'chat_picker_view.dart';
import 'forward_options.dart';
import 'video_playback_preferences.dart';
import 'video_playback_queue.dart';

class _TdVideoStreamServer {
  _TdVideoStreamServer(this.fileId);

  final int fileId;
  HttpServer? _server;
  String? _path;
  int _total = 0;
  int _downloadOffset = 0;
  int _downloadedPrefixSize = 0;
  bool _downloadComplete = false;
  int? _continuousDownloadOffset;
  Future<void> _downloadQueue = Future<void>.value();

  static const _chunkSize = 2 * 1024 * 1024;
  static const _streamChunkSize = 512 * 1024;
  static const _nativeMetadataChunkSize = 4 * 1024 * 1024;

  Future<Uri?> start() async {
    try {
      final file = await TdClient.shared.query({
        '@type': 'getFile',
        'file_id': fileId,
      });
      _updateFileInfo(file);
    } catch (_) {}

    if (_path == null || _path!.isEmpty || _total <= 0) {
      await _startContinuousDownload(0);
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
    if (_total <= 0) return null;
    if (!_downloadComplete && _continuousDownloadOffset == null) {
      await _startContinuousDownload(0);
    }

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

  /// Prefetch MP4 metadata at the end of a partially downloaded file so the
  /// player can read its index without waiting for preceding video bytes.
  Future<String?> prepareNativeFile() async {
    if (_total <= 0) return null;
    final prefixEnd = math.min(_total - 1, _chunkSize - 1);
    if (!await _ensureRange(0, prefixEnd)) return null;

    final tailStart = math.max(0, _total - _nativeMetadataChunkSize);
    final tail = await _downloadPlaybackRange(tailStart, _total - tailStart);
    if (tail == null) return null;
    _updateFileInfo(tail);

    final path = _path;
    if (path == null || path.isEmpty) return null;
    final localFile = File(path);
    return await localFile.exists() ? path : null;
  }

  void startBackgroundDownload() {
    unawaited(_startContinuousDownload(0));
  }

  void _updateFileInfo(Map<String, dynamic> file) {
    final expected = file.integer('expected_size') ?? 0;
    final size = file.integer('size') ?? 0;
    if (expected > 0 || size > 0) {
      _total = expected > 0 ? expected : size;
    }
    final path = file.obj('local')?.str('path');
    if (path != null && path.isNotEmpty) _path = path;
    final local = file.obj('local');
    _downloadOffset = local?.integer('download_offset') ?? _downloadOffset;
    final prefix = local?.integer('downloaded_prefix_size') ?? 0;
    _downloadedPrefixSize = prefix;
    _downloadComplete =
        local?.boolean('is_downloading_completed') == true && _total > 0;
    if (_downloadComplete) {
      _downloadOffset = 0;
      _downloadedPrefixSize = _total;
      _continuousDownloadOffset = null;
    }
  }

  Future<void> _startContinuousDownload(int offset) async {
    if (_downloadComplete) return;
    _continuousDownloadOffset = offset;
    try {
      final file = await TdClient.shared.query({
        '@type': 'downloadFile',
        'file_id': fileId,
        'priority': 32,
        'offset': offset,
        'limit': 0,
        'synchronous': false,
      });
      _updateFileInfo(file);
    } catch (_) {
      if (_continuousDownloadOffset == offset) {
        _continuousDownloadOffset = null;
      }
    }
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

      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      final range = rangeHeader == null ? null : _requestedRange(rangeHeader);
      if (rangeHeader != null && range == null) {
        request.response
          ..statusCode = HttpStatus.requestedRangeNotSatisfiable
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$_total');
        await request.response.close();
        return;
      }
      final (start, end) = range ?? (0, _total - 1);
      final partial = range != null;
      if (request.method == 'HEAD') {
        _writeRangeHeaders(request.response, start, end, partial);
        await request.response.close();
        return;
      }

      await _streamRange(request, start, end, partial: partial);
    } catch (_) {
      // The player may cancel a range request after headers were sent. Do not
      // attempt to mutate that response again; just finish it if it is open.
      try {
        request.response.statusCode = HttpStatus.internalServerError;
      } on StateError {
        // Headers were already sent.
      }
      try {
        await request.response.close();
      } on StateError {
        // The client already closed the response.
      }
    }
  }

  void _writeRangeHeaders(
    HttpResponse response,
    int start,
    int end,
    bool partial,
  ) {
    response
      ..statusCode = partial ? HttpStatus.partialContent : HttpStatus.ok
      ..contentLength = end - start + 1;
    if (partial) {
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$_total',
      );
    }
  }

  /// Delivers exactly the range advertised in the response header. AVFoundation
  /// validates it strictly, so a smaller response must never be used as a
  /// shortcut for a larger requested range.
  Future<void> _streamRange(
    HttpRequest request,
    int start,
    int end, {
    required bool partial,
  }) async {
    _writeRangeHeaders(request.response, start, end, partial);
    var offset = start;
    while (offset <= end) {
      final chunkEnd = math.min(end, offset + _streamChunkSize - 1);
      final ok = await _ensureRange(offset, chunkEnd);
      if (!ok || _path == null) {
        throw const HttpException('Video bytes are not available');
      }
      final bytes = await _readRange(offset, chunkEnd);
      if (bytes.length != chunkEnd - offset + 1) {
        throw const HttpException('Video range was only partially downloaded');
      }
      request.response.add(bytes);
      await request.response.flush();
      offset += bytes.length;
    }
    await request.response.close();
  }

  (int, int)? _requestedRange(String header) {
    if (!header.startsWith('bytes=')) return null;
    var start = 0;
    int? requestedEnd;
    final value = header.substring('bytes='.length).split(',').first.trim();
    final parts = value.split('-');
    if (parts.length != 2) return null;
    if (parts.first.isEmpty) {
      final suffixLength = int.tryParse(parts[1]) ?? 0;
      if (suffixLength <= 0) return null;
      start = math.max(0, _total - suffixLength);
      requestedEnd = _total - 1;
    } else {
      start = int.tryParse(parts.first) ?? -1;
      if (start < 0 || start >= _total) return null;
      if (parts[1].isNotEmpty) {
        requestedEnd = int.tryParse(parts[1]);
      }
    }
    final end = math.min(
      math.max(start, requestedEnd ?? (_total - 1)),
      _total - 1,
    );
    return (start, end);
  }

  Future<bool> _ensureRange(int start, int end) async {
    if (await _rangeIsReadable(start, end)) return true;

    final readableEnd = _downloadOffset + _downloadedPrefixSize - 1;
    final continuousOffset = _continuousDownloadOffset;
    final continuousDownloadCanReachRange =
        continuousOffset != null &&
        continuousOffset <= start &&
        start <= readableEnd + _chunkSize;
    if (continuousDownloadCanReachRange &&
        await _waitForReadableRange(start, end)) {
      return true;
    }

    final length = end - start + 1;
    try {
      final file = await _downloadPlaybackRange(start, length);
      if (file != null) _updateFileInfo(file);
      if (_path == null || _path!.isEmpty) {
        await _startContinuousDownload(start);
      }
      final readable = await _waitForReadableRange(start, end);
      if (!_downloadComplete && start != 0) {
        unawaited(_startContinuousDownload(0));
      }
      return readable;
    } catch (_) {
      return _waitForReadableRange(start, end);
    }
  }

  Future<Map<String, dynamic>?> _downloadPlaybackRange(int offset, int length) {
    final task = _downloadQueue.then((_) async {
      _continuousDownloadOffset = null;
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
      if (await _rangeIsReadable(start, end)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  Future<bool> _rangeIsReadable(int start, int end) async {
    if (_downloadComplete) return true;
    try {
      final prefix = await TdClient.shared.query({
        '@type': 'getFileDownloadedPrefixSize',
        'file_id': fileId,
        'offset': start,
      });
      return (prefix.integer('size') ?? 0) >= end - start + 1;
    } catch (_) {
      return false;
    }
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

enum _PlayerGesture { brightness, volume, seek, changeVideo, skipTenSeconds }

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
    this.previousVideo,
    this.nextVideo,
    this.onNavigate,
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
  final VideoPlaybackItem? previousVideo;
  final VideoPlaybackItem? nextVideo;
  final ValueChanged<int>? onNavigate;

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

typedef VideoPlaylistModeCallback =
    void Function(VideoPlaybackQueue queue, VideoDisplayMode mode);

class VideoPlaylistPlayerView extends StatefulWidget {
  const VideoPlaylistPlayerView({
    super.key,
    required this.queue,
    this.presentation = VideoPlayerPresentation.fullscreen,
    this.onClose,
    this.compactControls = false,
    this.currentMode = VideoDisplayMode.fullscreen,
    this.onSwitchMode,
    this.onQueueChanged,
    this.initialMuted = false,
  });

  final VideoPlaybackQueue queue;
  final VideoPlayerPresentation presentation;
  final VoidCallback? onClose;
  final bool compactControls;
  final VideoDisplayMode currentMode;
  final VideoPlaylistModeCallback? onSwitchMode;
  final ValueChanged<VideoPlaybackQueue>? onQueueChanged;
  final bool initialMuted;

  @override
  State<VideoPlaylistPlayerView> createState() =>
      _VideoPlaylistPlayerViewState();
}

class _VideoPlaylistPlayerViewState extends State<VideoPlaylistPlayerView> {
  late VideoPlaybackQueue _queue = widget.queue;

  @override
  void didUpdateWidget(covariant VideoPlaylistPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.queue.current.video.id != _queue.current.video.id ||
        widget.queue.items.length != _queue.items.length) {
      _queue = widget.queue;
    }
  }

  void _navigate(int delta) {
    final next = _queue.moveBy(delta);
    if (next == null) return;
    setState(() => _queue = next);
    widget.onQueueChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final item = _queue.current;
    return VideoPlayerView(
      key: ValueKey('${item.video.id}:${item.messageId ?? 0}'),
      video: item.video,
      thumb: item.thumb,
      width: item.width,
      height: item.height,
      presentation: widget.presentation,
      onClose: widget.onClose,
      compactControls: widget.compactControls,
      sourceChatId: item.sourceChatId,
      messageId: item.messageId,
      currentMode: widget.currentMode,
      onSwitchMode: widget.onSwitchMode == null
          ? null
          : (mode) => widget.onSwitchMode!(_queue, mode),
      initialMuted: widget.initialMuted,
      previousVideo: _queue.previous,
      nextVideo: _queue.next,
      onNavigate: _navigate,
    );
  }
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
  bool _systemPiPHandoff = false;
  bool _systemPiPUsesActivePlayer = false;
  bool _systemPiPSupported = false;
  bool _systemPiPPrepared = false;
  String? _systemPiPId;
  int _lastSystemPiPSyncMs = -1;
  bool _wakelockActive = false;
  _PlayerGesture? _activeGesture;
  Offset? _gestureOrigin;
  double _gestureStartValue = 0;
  double _gestureValue = 0;
  bool _gestureBrightnessReady = false;
  Duration _gestureStartPosition = Duration.zero;
  Duration _gestureSeekPosition = Duration.zero;
  int _gestureNavigationDelta = 0;
  VideoHorizontalSwipeAction _horizontalSwipeAction =
      VideoHorizontalSwipeAction.adjustProgress;
  VideoCompletionAction _completionAction = VideoCompletionAction.prompt;
  bool _completionHandled = false;
  bool _showCompletionPrompt = false;
  final GlobalKey _scrubberKey = GlobalKey(debugLabel: 'video-scrubber');
  final Map<int, Uint8List> _scrubPreviewCache = {};
  OverlayEntry? _scrubPreviewOverlay;
  Timer? _scrubPreviewTimer;
  Duration? _scrubPosition;
  Duration? _pendingScrubPreviewPosition;
  Uint8List? _scrubPreviewBytes;
  bool _scrubPreviewLoading = false;
  bool _resumeAfterScrub = false;
  bool _scrubPreviewCompact = false;
  Future<void>? _scrubPause;
  int _scrubPreviewGeneration = 0;

  static const _speeds = <double>[0.5, 0.75, 1, 1.25, 1.5, 2];
  static const _resumePrefix = 'mithka.video.resume.';
  static const _resumeSaveStep = Duration(seconds: 2);
  static const _resumeMinimum = Duration(seconds: 3);
  static const _resumeEndSlack = Duration(seconds: 8);

  @override
  void initState() {
    super.initState();
    if (widget.initialMuted) _volume = 0;
    unawaited(_loadPlaybackPreferences());
    _load();
  }

  Future<void> _loadPlaybackPreferences() async {
    final preferences = await VideoPlaybackPreferences.load();
    if (!mounted) return;
    setState(() {
      _horizontalSwipeAction = preferences.horizontalSwipeAction;
      _completionAction = preferences.completionAction;
    });
  }

  Future<void> _load() async {
    final sourcePath = widget.video.localPath;
    if (sourcePath != null && sourcePath.isNotEmpty) {
      final source = File(sourcePath);
      if (await source.exists()) {
        final length = await source.length();
        if (length > 0) {
          _localPath = sourcePath;
          _openedCompletedLocalFile = true;
          _progress = TdFileProgress(
            fileId: widget.video.id,
            downloaded: length,
            prefixDownloaded: length,
            total: length,
            isActive: false,
            isCompleted: true,
          );
          final initialized = await _initializeFromFile(sourcePath);
          if (initialized || !mounted) return;
          _openedCompletedLocalFile = false;
        }
      }
    }
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
    if (Platform.isIOS) {
      final nativePath = await server.prepareNativeFile();
      if (!mounted) {
        unawaited(server.close());
        return;
      }
      if (nativePath != null) {
        server.startBackgroundDownload();
        _localPath = nativePath;
        final initialized = await _initializeFromFile(nativePath);
        if (initialized || !mounted) {
          if (initialized) {
            unawaited(server.close());
            _streamServer = null;
          }
          return;
        }
      }
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
    _updateWakelock();
    unawaited(_refreshSystemPictureInPictureSupport());
    _scheduleHide();
    return true;
  }

  // Rebuild for play/pause + scrubber position changes.
  void _onTick() {
    final value = _controller?.value;
    if (value?.isCompleted == true && !_completionHandled) {
      _completionHandled = true;
      unawaited(_handlePlaybackCompleted());
    } else if (value != null && !value.isCompleted && _completionHandled) {
      _completionHandled = false;
    }
    _storePlaybackPositionIfNeeded();
    _syncSystemPictureInPictureIfNeeded();
    _updateWakelock();
    if (mounted) setState(() {});
  }

  /// Keep the screen awake while the video is actively playing; release the
  /// wakelock when paused or finished so the system idle timer resumes.
  void _updateWakelock() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final shouldKeepAwake = c.value.isPlaying;
    if (shouldKeepAwake == _wakelockActive) return;
    _wakelockActive = shouldKeepAwake;
    unawaited(
      shouldKeepAwake ? ScreenWakelock.enable() : ScreenWakelock.disable(),
    );
  }

  void _syncSystemPictureInPictureIfNeeded() {
    final id = _systemPiPId;
    final c = _controller;
    if (id == null ||
        !_systemPiPPrepared ||
        c == null ||
        !c.value.isInitialized) {
      return;
    }
    final positionMs = c.value.position.inMilliseconds;
    if ((positionMs - _lastSystemPiPSyncMs).abs() < 900 && c.value.isPlaying) {
      return;
    }
    _lastSystemPiPSyncMs = positionMs;
    unawaited(
      SystemPictureInPicture.updatePrepared(
        id: id,
        position: c.value.position,
        speed: _speed,
        muted: _volume <= 0.01,
        playing: c.value.isPlaying,
        videoSize: c.value.size,
      ),
    );
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
      if (c.value.position >= c.value.duration || c.value.isCompleted) {
        await c.seekTo(Duration.zero);
        _completionHandled = false;
      }
      await c.play();
      if (!mounted) return;
      setState(() {
        _controlsVisible = true;
        _showCompletionPrompt = false;
      });
      _scheduleHide();
    }
  }

  Future<void> _handlePlaybackCompleted() async {
    await _storePlaybackPosition(force: true);
    if (!mounted) return;
    switch (_completionAction) {
      case VideoCompletionAction.prompt:
        _hideTimer?.cancel();
        setState(() {
          _controlsVisible = false;
          _showCompletionPrompt = true;
        });
      case VideoCompletionAction.autoplayNext:
        if (widget.nextVideo != null && widget.onNavigate != null) {
          widget.onNavigate!(1);
        } else {
          _close();
        }
      case VideoCompletionAction.replay:
        await _replayFromBeginning();
      case VideoCompletionAction.returnToChat:
        _close();
    }
  }

  Future<void> _replayFromBeginning() async {
    final c = _controller;
    if (c == null) return;
    await c.seekTo(Duration.zero);
    _completionHandled = false;
    await c.play();
    if (!mounted) return;
    setState(() {
      _showCompletionPrompt = false;
      _controlsVisible = true;
    });
    _scheduleHide();
  }

  void _playNextVideo() {
    if (widget.nextVideo == null || widget.onNavigate == null) return;
    widget.onNavigate!(1);
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

  Future<bool> _startSystemPictureInPicture() async {
    final c = _controller;
    final uri = _systemPiPSourceUri();
    if (c == null || !c.value.isInitialized || uri == null) {
      debugPrint('system PiP start skipped: controller/source unavailable');
      return false;
    }
    if (!await _isSystemPictureInPictureSupported()) {
      debugPrint('system PiP start skipped: AVPictureInPicture unsupported');
      return false;
    }

    var id = _systemPiPId;
    var started = false;
    if (id != null && _systemPiPPrepared) {
      debugPrint('system PiP starting prepared source: $uri');
      started = await SystemPictureInPicture.startPrepared(
        id: id,
        position: c.value.position,
        speed: _speed,
        muted: _volume <= 0.01,
        playing: c.value.isPlaying,
        videoSize: c.value.size,
      );
    }
    if (!started) {
      if (id != null) {
        await SystemPictureInPicture.cancelPrepared(id);
        _systemPiPPrepared = false;
        _systemPiPId = null;
      }
      id = '${widget.video.id}-${DateTime.now().microsecondsSinceEpoch}';
      _systemPiPId = id;
      final server = _streamServer;
      final shouldCancelOnStop =
          !_openedCompletedLocalFile && _progress?.isCompleted != true;
      debugPrint('system PiP starting source: $uri');
      started = await SystemPictureInPicture.start(
        id: id,
        uri: uri,
        position: c.value.position,
        speed: _speed,
        muted: _volume <= 0.01,
        playing: c.value.isPlaying,
        videoSize: c.value.size,
        playerId: c.fvpPlayerId,
        onStop: () async {
          if (SystemPictureInPicture.usesActivePlayer(id!)) {
            await c.dispose();
          }
          await server?.close();
          if (shouldCancelOnStop) {
            TdFileCenter.shared.cancelDownload(widget.video.id);
          }
        },
      );
    }
    if (!started) {
      debugPrint('system PiP failed to start for source: $uri');
      if (mounted) {
        showToast(context, AppStringKeys.videoPlayerPictureInPictureFailed);
      }
      return false;
    }
    if (SystemPictureInPicture.keepsFlutterPlayerInActivity) {
      // Android PiP hosts this Activity. Keep the Flutter route and its video
      // texture mounted so the system captures the active player, not chat.
      if (mounted) setState(() => _controlsVisible = false);
      return true;
    }
    _systemPiPUsesActivePlayer =
        id != null && SystemPictureInPicture.usesActivePlayer(id);
    _systemPiPHandoff = true;
    _systemPiPPrepared = false;
    _streamServer = null;
    if (!_systemPiPUsesActivePlayer) unawaited(c.pause());
    _close();
    return true;
  }

  Uri? _systemPiPSourceUri() {
    final source = _localPath;
    if (source == null || source.isEmpty) return null;
    return source.startsWith('http://') || source.startsWith('https://')
        ? Uri.parse(source)
        : Uri.file(source);
  }

  Future<void> _prepareSystemPictureInPicture() async {
    if (_systemPiPPrepared || _systemPiPId != null) {
      return;
    }
    final c = _controller;
    final uri = _systemPiPSourceUri();
    if (c == null || !c.value.isInitialized || uri == null) return;
    if (!await _isSystemPictureInPictureSupported()) return;

    final server = _streamServer;
    final shouldCancelOnStop =
        !_openedCompletedLocalFile && _progress?.isCompleted != true;
    final id = '${widget.video.id}-${DateTime.now().microsecondsSinceEpoch}';
    _systemPiPId = id;
    final prepared = await SystemPictureInPicture.prepare(
      id: id,
      uri: uri,
      position: c.value.position,
      speed: _speed,
      muted: _volume <= 0.01,
      playing: c.value.isPlaying,
      videoSize: c.value.size,
      playerId: c.fvpPlayerId,
      onStop: () async {
        if (SystemPictureInPicture.usesActivePlayer(id)) {
          await c.dispose();
        }
        await server?.close();
        if (shouldCancelOnStop) {
          TdFileCenter.shared.cancelDownload(widget.video.id);
        }
      },
    );
    if (!mounted || _systemPiPId != id) {
      if (prepared) unawaited(SystemPictureInPicture.cancelPrepared(id));
      return;
    }
    if (prepared) {
      _systemPiPPrepared = true;
      _syncSystemPictureInPictureIfNeeded();
    } else {
      _systemPiPId = null;
    }
  }

  Future<void> _refreshSystemPictureInPictureSupport() async {
    final supported = await _isSystemPictureInPictureSupported();
    if (supported) {
      unawaited(_prepareSystemPictureInPicture());
    }
  }

  Future<bool> _isSystemPictureInPictureSupported() async {
    if (_systemPiPSupported) return true;
    final supported = await SystemPictureInPicture.isSupported();
    if (mounted && _systemPiPSupported != supported) {
      setState(() => _systemPiPSupported = supported);
    }
    return supported;
  }

  void _close() {
    if (_wakelockActive) {
      _wakelockActive = false;
      unawaited(ScreenWakelock.disable());
    }
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
    if (_wakelockActive) {
      _wakelockActive = false;
      unawaited(ScreenWakelock.disable());
    }
    _hideTimer?.cancel();
    _scrubPreviewTimer?.cancel();
    _scrubPreviewOverlay?.remove();
    _scrubPreviewOverlay = null;
    _scrubPreviewGeneration++;
    _progressSub?.cancel();
    unawaited(_storePlaybackPosition(force: true));
    _controller?.removeListener(_onTick);
    if (!_systemPiPHandoff || !_systemPiPUsesActivePlayer) {
      _controller?.dispose();
    }
    final preparedPiPId = _systemPiPId;
    if (!_systemPiPHandoff && preparedPiPId != null) {
      unawaited(SystemPictureInPicture.cancelPrepared(preparedPiPId));
    }
    unawaited(_streamServer?.close());
    if (!_systemPiPHandoff &&
        !_openedCompletedLocalFile &&
        _progress?.isCompleted != true) {
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
      onPanDown: ready && _supportsPlaybackGestures
          ? (details) => _gestureOrigin = details.localPosition
          : null,
      onPanStart: ready && _supportsPlaybackGestures
          ? (details) => _startPlaybackGesture(details, c)
          : null,
      onPanUpdate: ready && _supportsPlaybackGestures
          ? (details) => _updatePlaybackGesture(details, c)
          : null,
      onPanEnd: ready && _supportsPlaybackGestures
          ? (_) => _finishPlaybackGesture(c)
          : null,
      onPanCancel: ready && _supportsPlaybackGestures
          ? _cancelPlaybackGesture
          : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (ready) _videoFrame(c) else _loadingState(),
          if (ready && _controlsVisible) ..._controlChromeBlocks(visible: true),
          if (ready &&
              _controlsVisible &&
              widget.presentation != VideoPlayerPresentation.pictureInPicture)
            _topTechnicalInfo(_debugText(c)),
          if (ready && _controlsVisible) ..._controls(c),
          if (ready && _activeGesture != null) _gestureIndicator(c),
          if (ready && _showCompletionPrompt) _completionPrompt(),
          if (!ready || _controlsVisible)
            widget.presentation == VideoPlayerPresentation.pictureInPicture &&
                    ready
                ? _pipTopBar(c)
                : _closeButton(),
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

  bool get _supportsPlaybackGestures =>
      widget.presentation == VideoPlayerPresentation.fullscreen;

  void _startPlaybackGesture(
    DragStartDetails details,
    VideoPlayerController controller,
  ) {
    _hideTimer?.cancel();
    _gestureOrigin ??= details.localPosition;
    _gestureStartValue = _volume;
    _gestureValue = _volume;
    _gestureBrightnessReady = false;
    _gestureStartPosition = controller.value.position;
    _gestureSeekPosition = _gestureStartPosition;
    if (!_controlsVisible) setState(() => _controlsVisible = true);
  }

  void _updatePlaybackGesture(
    DragUpdateDetails details,
    VideoPlayerController controller,
  ) {
    final origin = _gestureOrigin;
    if (origin == null) return;
    final delta = details.localPosition - origin;
    final size = MediaQuery.sizeOf(context);
    var gesture = _activeGesture;
    if (gesture == null) {
      if (math.max(delta.dx.abs(), delta.dy.abs()) < 12) return;
      if (delta.dx.abs() > delta.dy.abs()) {
        gesture = switch (_horizontalSwipeAction) {
          VideoHorizontalSwipeAction.disabled => null,
          VideoHorizontalSwipeAction.adjustProgress => _PlayerGesture.seek,
          VideoHorizontalSwipeAction.changeVideo => _PlayerGesture.changeVideo,
          VideoHorizontalSwipeAction.skipTenSeconds =>
            _PlayerGesture.skipTenSeconds,
        };
        if (gesture == null) return;
      } else {
        gesture = origin.dx < size.width / 2
            ? _PlayerGesture.brightness
            : _PlayerGesture.volume;
      }
      if (gesture == _PlayerGesture.brightness) {
        unawaited(_beginBrightnessGesture());
      }
    }

    switch (gesture) {
      case _PlayerGesture.seek:
        final duration = controller.value.duration;
        final change = duration.inMilliseconds * delta.dx / size.width;
        _gestureSeekPosition = Duration(
          milliseconds: (_gestureStartPosition.inMilliseconds + change)
              .round()
              .clamp(0, duration.inMilliseconds),
        );
      case _PlayerGesture.volume:
        _gestureValue = (_gestureStartValue - delta.dy / size.height).clamp(
          0.0,
          1.0,
        );
        controller.setVolume(_gestureValue);
      case _PlayerGesture.brightness:
        if (!_gestureBrightnessReady) break;
        _gestureValue = (_gestureStartValue - delta.dy / size.height).clamp(
          0.01,
          1.0,
        );
        unawaited(PlayerBrightness.set(_gestureValue));
      case _PlayerGesture.changeVideo:
        final threshold = (size.width * 0.14).clamp(56.0, 120.0);
        _gestureNavigationDelta = delta.dx.abs() < threshold
            ? 0
            : delta.dx < 0
            ? 1
            : -1;
      case _PlayerGesture.skipTenSeconds:
        final direction = delta.dx.abs() < 24
            ? 0
            : delta.dx < 0
            ? -1
            : 1;
        final target = _gestureStartPosition.inMilliseconds + direction * 10000;
        _gestureNavigationDelta = direction;
        _gestureSeekPosition = Duration(
          milliseconds: target.clamp(
            0,
            controller.value.duration.inMilliseconds,
          ),
        );
    }
    setState(() => _activeGesture = gesture);
  }

  Future<void> _beginBrightnessGesture() async {
    final current = await PlayerBrightness.current();
    if (!mounted ||
        _activeGesture != _PlayerGesture.brightness ||
        current == null) {
      return;
    }
    setState(() {
      _gestureStartValue = current;
      _gestureValue = current;
      _gestureBrightnessReady = true;
    });
  }

  void _finishPlaybackGesture(VideoPlayerController controller) {
    final gesture = _activeGesture;
    if (gesture == _PlayerGesture.seek) {
      unawaited(controller.seekTo(_gestureSeekPosition));
    } else if (gesture == _PlayerGesture.skipTenSeconds &&
        _gestureNavigationDelta != 0) {
      unawaited(controller.seekTo(_gestureSeekPosition));
    } else if (gesture == _PlayerGesture.changeVideo &&
        _gestureNavigationDelta != 0 &&
        _canNavigate(_gestureNavigationDelta)) {
      widget.onNavigate?.call(_gestureNavigationDelta);
    } else if (gesture == _PlayerGesture.volume) {
      _volume = _gestureValue;
    }
    _cancelPlaybackGesture();
    _scheduleHide();
  }

  void _cancelPlaybackGesture() {
    if (!mounted) return;
    setState(() {
      _activeGesture = null;
      _gestureOrigin = null;
      _gestureNavigationDelta = 0;
    });
  }

  bool _canNavigate(int delta) => delta > 0
      ? widget.nextVideo != null
      : delta < 0
      ? widget.previousVideo != null
      : false;

  Widget _gestureIndicator(VideoPlayerController controller) {
    final gesture = _activeGesture!;
    final icon = switch (gesture) {
      _PlayerGesture.brightness => HeroAppIcons.sun,
      _PlayerGesture.volume =>
        _gestureValue <= 0.01
            ? HeroAppIcons.volumeXmark
            : HeroAppIcons.volumeHigh,
      _PlayerGesture.seek => HeroAppIcons.arrowsRotate,
      _PlayerGesture.changeVideo =>
        _gestureNavigationDelta >= 0
            ? HeroAppIcons.arrowRight
            : HeroAppIcons.arrowLeft,
      _PlayerGesture.skipTenSeconds =>
        _gestureNavigationDelta >= 0
            ? HeroAppIcons.arrowRight
            : HeroAppIcons.arrowLeft,
    };
    final label = switch (gesture) {
      _PlayerGesture.seek =>
        '${_fmt(_gestureSeekPosition)} / ${_fmt(controller.value.duration)}',
      _PlayerGesture.skipTenSeconds =>
        '${_gestureNavigationDelta > 0
            ? '+'
            : _gestureNavigationDelta < 0
            ? '−'
            : ''}${_gestureNavigationDelta == 0 ? '' : '10s · '}${_fmt(_gestureSeekPosition)} / ${_fmt(controller.value.duration)}',
      _PlayerGesture.changeVideo => _navigationGestureLabel(),
      _PlayerGesture.brightness ||
      _PlayerGesture.volume => '${(_gestureValue * 100).round()}%',
    };
    return Center(
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon, color: Colors.white, size: 26),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _navigationGestureLabel() {
    final delta = _gestureNavigationDelta;
    if (delta == 0) {
      return AppStringKeys.videoPlayerSwipeFurther.l10n(context);
    }
    if (!_canNavigate(delta)) {
      return (delta > 0
              ? AppStringKeys.videoPlayerNoNextVideo
              : AppStringKeys.videoPlayerNoPreviousVideo)
          .l10n(context);
    }
    return (delta > 0
            ? AppStringKeys.videoPlayerNextVideo
            : AppStringKeys.videoPlayerPreviousVideo)
        .l10n(context);
  }

  Widget _completionPrompt() {
    final next = widget.nextVideo;
    final compact =
        _usesCompactChrome(context) ||
        widget.compactControls ||
        widget.presentation == VideoPlayerPresentation.pictureInPicture;
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.92),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 12 : 48,
                vertical: compact ? 12 : 20,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      (next == null
                              ? AppStringKeys.videoPlayerFinished
                              : AppStringKeys.videoPlayerUpNext)
                          .l10n(context),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 20 : 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (next != null) ...[
                      const SizedBox(height: 16),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _playNextVideo,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: AspectRatio(
                            aspectRatio: _itemAspectRatio(next),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ColoredBox(
                                  color: const Color(0xFF18181B),
                                  child: next.thumb == null
                                      ? const SizedBox.shrink()
                                      : TDImage(photo: next.thumb),
                                ),
                                ColoredBox(
                                  color: Colors.black.withValues(alpha: 0.22),
                                ),
                                Center(
                                  child: Container(
                                    width: compact ? 58 : 72,
                                    height: compact ? 58 : 72,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.68,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: AppIcon(
                                      HeroAppIcons.play,
                                      color: Colors.white,
                                      size: compact ? 30 : 38,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 16,
                                  right: 16,
                                  bottom: 14,
                                  child: Text(
                                    next.title.trim().isEmpty
                                        ? AppStringKeys.videoPlayerNextVideo
                                              .l10n(context)
                                        : next.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      shadows: [Shadow(blurRadius: 8)],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        if (next != null)
                          _completionActionButton(
                            icon: HeroAppIcons.play,
                            label: AppStringKeys.videoPlayerPlayNext,
                            primary: true,
                            onTap: _playNextVideo,
                          ),
                        _completionActionButton(
                          icon: HeroAppIcons.arrowsRotate,
                          label: AppStringKeys.videoPlayerReplay,
                          onTap: () => unawaited(_replayFromBeginning()),
                        ),
                        _completionActionButton(
                          icon: HeroAppIcons.comments,
                          label: AppStringKeys.videoPlayerReturnToChat,
                          onTap: _close,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _itemAspectRatio(VideoPlaybackItem item) {
    final width = item.width;
    final height = item.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return 16 / 9;
    }
    return width / height;
  }

  Widget _completionActionButton({
    required AppIconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: primary ? Colors.white : const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              icon,
              size: 18,
              color: primary ? Colors.black : Colors.white,
            ),
            const SizedBox(width: 8),
            Text(
              label.l10n(context),
              style: TextStyle(
                color: primary ? Colors.black : Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
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

  Widget _pipTopBar(VideoPlayerController c) {
    return Positioned(
      top: 3,
      left: 8,
      right: 4,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Text(
              _pipStatusLine(c),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF8E8E93),
                fontSize: 9,
                height: 1.1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 4),
          _plainIconButton(HeroAppIcons.xmark.data, _close, size: 28),
        ],
      ),
    );
  }

  String _pipStatusLine(VideoPlayerController c) {
    final size = c.value.size;
    final dimensions =
        '${size.width.round()}x${size.height.round()} · ${_speedText(_speed)}';
    final p = _progress;
    if (p == null) return dimensions;
    return '$dimensions · ${_byteString(p.downloaded)} / ${_byteString(p.total)}';
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
          if (widget.presentation != VideoPlayerPresentation.pictureInPicture)
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
        if (_showsSystemPictureInPictureButton) ...[
          SizedBox(width: layout.actionGap),
          _systemPictureInPictureButton(size: layout.actionButtonSize),
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 220) {
              return _loadingScrubber(compact: true);
            }
            return Row(
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
            );
          },
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
        Text(_fmt(_displayPosition(c)), style: layout.timeStyle),
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
        if (_showsSystemPictureInPictureButton) ...[
          SizedBox(width: layout.actionGap),
          _systemPictureInPictureButton(size: layout.actionButtonSize),
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 220) {
              return _scrubber(c);
            }
            final showSystemPiP =
                !pip &&
                _showsSystemPictureInPictureButton &&
                constraints.maxWidth >= 360;
            return Row(
              children: [
                if (!pip && widget.onSwitchMode != null) ...[
                  _modeSwitchButton(size: 34),
                  const SizedBox(width: 8),
                ],
                if (showSystemPiP) ...[
                  _systemPictureInPictureButton(size: 34),
                  const SizedBox(width: 8),
                ],
                Text(
                  _fmt(_displayPosition(c)),
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                const SizedBox(width: 8),
                Expanded(child: _scrubber(c)),
                const SizedBox(width: 8),
                if (pip)
                  _muteButton(size: 34)
                else if (constraints.maxWidth >= 320)
                  SizedBox(width: 104, child: _volumeSlider(compact: true)),
                if (constraints.maxWidth >= 320) const SizedBox(width: 8),
                if (constraints.maxWidth >= 280)
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
            );
          },
        ),
      ),
    ];
  }

  Widget _scrubber(VideoPlayerController c, {bool compact = false}) {
    final value = c.value;
    final duration = value.duration.inMilliseconds;
    final position = _displayPosition(c).inMilliseconds.clamp(0, duration);
    final loaded = _loadedFraction(value);
    return SizedBox(
      key: _scrubberKey,
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
          _OwnedVideoSlider(
            value: duration <= 0 ? 0 : position / duration,
            trackHeight: compact ? 2.5 : 4,
            thumbRadius: compact ? 5 : 8,
            activeColor: Colors.white,
            inactiveColor: Colors.transparent,
            onChangeStart: duration <= 0
                ? null
                : (fraction) =>
                      _beginScrub(c, fraction * duration, compact: compact),
            onChanged: duration <= 0
                ? null
                : (fraction) => _updateScrub(c, fraction * duration),
            onChangeEnd: duration <= 0
                ? null
                : (fraction) => unawaited(_finishScrub(c, fraction * duration)),
          ),
        ],
      ),
    );
  }

  Duration _displayPosition(VideoPlayerController controller) {
    final scrubPosition = _scrubPosition;
    if (scrubPosition != null) return scrubPosition;
    return switch (_activeGesture) {
      _PlayerGesture.seek ||
      _PlayerGesture.skipTenSeconds => _gestureSeekPosition,
      _ => controller.value.position,
    };
  }

  void _beginScrub(
    VideoPlayerController controller,
    double value, {
    required bool compact,
  }) {
    _hideTimer?.cancel();
    _resumeAfterScrub = controller.value.isPlaying;
    _scrubPause = _resumeAfterScrub ? controller.pause() : null;
    _scrubPreviewCompact = compact;
    _scrubPreviewBytes = null;
    _scrubPreviewGeneration++;
    final position = Duration(milliseconds: value.round());
    setState(() => _scrubPosition = position);
    _showScrubPreviewOverlay();
    _queueScrubPreview(position, immediate: true);
  }

  void _updateScrub(VideoPlayerController controller, double value) {
    final position = Duration(milliseconds: value.round());
    setState(() => _scrubPosition = position);
    unawaited(controller.seekTo(position));
    _scrubPreviewOverlay?.markNeedsBuild();
    _queueScrubPreview(position);
  }

  Future<void> _finishScrub(
    VideoPlayerController controller,
    double value,
  ) async {
    final position = Duration(milliseconds: value.round());
    _scrubPreviewTimer?.cancel();
    _pendingScrubPreviewPosition = null;
    _scrubPreviewGeneration++;
    await _scrubPause;
    _scrubPause = null;
    await controller.seekTo(position);
    if (_resumeAfterScrub) await controller.play();
    _resumeAfterScrub = false;
    if (!mounted) return;
    setState(() => _scrubPosition = null);
    _hideScrubPreviewOverlay();
    _scheduleHide();
  }

  void _queueScrubPreview(Duration position, {bool immediate = false}) {
    final bucketMs = (position.inMilliseconds ~/ 500) * 500;
    final cached = _scrubPreviewCache[bucketMs];
    if (cached != null) {
      _scrubPreviewBytes = cached;
      _scrubPreviewOverlay?.markNeedsBuild();
      return;
    }
    _pendingScrubPreviewPosition = Duration(milliseconds: bucketMs);
    _scrubPreviewTimer?.cancel();
    if (immediate) {
      unawaited(_drainScrubPreviewQueue());
    } else {
      _scrubPreviewTimer = Timer(
        const Duration(milliseconds: 120),
        () => unawaited(_drainScrubPreviewQueue()),
      );
    }
  }

  Future<void> _drainScrubPreviewQueue() async {
    if (_scrubPreviewLoading || _scrubPosition == null) return;
    final position = _pendingScrubPreviewPosition;
    final source = _localPath;
    if (position == null || source == null || source.isEmpty) return;
    _pendingScrubPreviewPosition = null;
    _scrubPreviewLoading = true;
    _scrubPreviewOverlay?.markNeedsBuild();
    final generation = _scrubPreviewGeneration;
    Uint8List? bytes;
    try {
      bytes = await VideoThumbnail.thumbnailData(
        video: source,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 240,
        timeMs: position.inMilliseconds,
        quality: 72,
      );
    } catch (_) {
      bytes = null;
    } finally {
      _scrubPreviewLoading = false;
    }
    if (!mounted ||
        generation != _scrubPreviewGeneration ||
        _scrubPosition == null) {
      return;
    }
    if (bytes != null && bytes.isNotEmpty) {
      final bucketMs = position.inMilliseconds;
      _scrubPreviewCache[bucketMs] = bytes;
      while (_scrubPreviewCache.length > 24) {
        _scrubPreviewCache.remove(_scrubPreviewCache.keys.first);
      }
      _scrubPreviewBytes = bytes;
    }
    _scrubPreviewOverlay?.markNeedsBuild();
    if (_pendingScrubPreviewPosition != null) {
      unawaited(_drainScrubPreviewQueue());
    }
  }

  void _showScrubPreviewOverlay() {
    if (_scrubPreviewOverlay != null) return;
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(builder: _buildScrubPreviewOverlay);
    _scrubPreviewOverlay = entry;
    overlay.insert(entry);
  }

  void _hideScrubPreviewOverlay() {
    _scrubPreviewOverlay?.remove();
    _scrubPreviewOverlay = null;
    _scrubPreviewBytes = null;
  }

  Widget _buildScrubPreviewOverlay(BuildContext overlayContext) {
    final scrubberContext = _scrubberKey.currentContext;
    final position = _scrubPosition;
    if (scrubberContext == null || position == null) {
      return const SizedBox.shrink();
    }
    final scrubberBox = scrubberContext.findRenderObject();
    final overlayBox = overlayContext.findRenderObject();
    if (scrubberBox is! RenderBox || overlayBox is! RenderBox) {
      return const SizedBox.shrink();
    }
    final durationMs = _controller?.value.duration.inMilliseconds ?? 0;
    final fraction = durationMs <= 0
        ? 0.0
        : (position.inMilliseconds / durationMs).clamp(0.0, 1.0);
    final trackInset = _scrubPreviewCompact ? 0.0 : 24.0;
    final trackWidth = math.max(0.0, scrubberBox.size.width - trackInset * 2);
    final target = scrubberBox.localToGlobal(
      Offset(trackInset + trackWidth * fraction, 0),
      ancestor: overlayBox,
    );
    final previewWidth = _scrubPreviewCompact ? 128.0 : 160.0;
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
    final left = (target.dx - previewWidth / 2)
        .clamp(8.0, math.max(8.0, overlayBox.size.width - previewWidth - 8))
        .toDouble();
    final top = math.max(8.0, target.dy - previewHeight - 14);
    final bytes = _scrubPreviewBytes;
    return Positioned(
      left: left,
      top: top,
      width: previewWidth,
      height: previewHeight,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF111113),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
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
                if (bytes != null)
                  Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
                else if (widget.thumb != null)
                  TDImage(photo: widget.thumb)
                else
                  const ColoredBox(color: Color(0xFF111113)),
                if (bytes == null && _scrubPreviewLoading)
                  const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
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
                        colors: [Colors.transparent, Color(0xCC000000)],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 12, 6, 5),
                      child: Text(
                        _fmt(position),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
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
            child: _OwnedVideoSlider(
              value: _volume,
              trackHeight: compact ? 2.5 : 3,
              thumbRadius: compact ? 5 : 7,
              activeColor: Colors.white,
              inactiveColor: Colors.white.withValues(alpha: 0.22),
              onChangeStart: (_) => _hideTimer?.cancel(),
              onChanged: _setVolume,
              onChangeEnd: (_) => _scheduleHide(),
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

  bool get _showsSystemPictureInPictureButton =>
      (widget.onSwitchMode != null ||
          _systemPiPSupported ||
          SystemPictureInPicture.isSupportedPlatform) &&
      widget.presentation != VideoPlayerPresentation.pictureInPicture;

  Widget _systemPictureInPictureButton({required double size}) {
    if (!_showsSystemPictureInPictureButton) return const SizedBox.shrink();
    return _roundIconButton(HeroAppIcons.pictureInPicture.data, () {
      debugPrint('picture in picture button tapped');
      unawaited(_enterPictureInPicture());
      _scheduleHide();
    }, size: size);
  }

  Future<void> _enterPictureInPicture() async {
    if (SystemPictureInPicture.isSupportedPlatform) {
      await _startSystemPictureInPicture();
      return;
    }
    final callback = widget.onSwitchMode;
    if (callback != null) {
      callback(VideoDisplayMode.pictureInPicture);
    }
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
        if (mode != widget.currentMode) {
          unawaited(_selectDisplayMode(mode, callback));
        }
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

  Future<void> _selectDisplayMode(
    VideoDisplayMode mode,
    ValueChanged<VideoDisplayMode> callback,
  ) async {
    if (mode == VideoDisplayMode.pictureInPicture) {
      await _enterPictureInPicture();
      return;
    }
    if (!mounted) return;
    callback(mode);
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
    final result = await Navigator.of(context).push<ChatPickerResult>(
      MaterialPageRoute(
        builder: (_) => const ChatPickerView(
          title: AppStringKeys.chatForwardToTitle,
          showForwardOptions: true,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final target = result.chat;
    try {
      await forwardMessagesWithOptions(
        client: TdClient.shared,
        targetChatId: target.id,
        fromChatId: sourceChatId,
        messageIds: [messageId],
        options: result.forwardOptions,
      );
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
          isForwardProtectedError(e)
              ? AppStringKeys.chatForwardProtected
              : AppStrings.t(AppStringKeys.chatForwardFailed, {'value1': e}),
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

class _OwnedVideoSlider extends StatefulWidget {
  const _OwnedVideoSlider({
    required this.value,
    required this.trackHeight,
    required this.thumbRadius,
    required this.activeColor,
    required this.inactiveColor,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
  });

  final double value;
  final double trackHeight;
  final double thumbRadius;
  final Color activeColor;
  final Color inactiveColor;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  State<_OwnedVideoSlider> createState() => _OwnedVideoSliderState();
}

class _OwnedVideoSliderState extends State<_OwnedVideoSlider> {
  double? _interactionValue;

  double _valueAt(double dx, double width) {
    final usableWidth = math.max(1.0, width - widget.thumbRadius * 2);
    return ((dx - widget.thumbRadius) / usableWidth).clamp(0.0, 1.0);
  }

  void _begin(double dx, double width) {
    final value = _valueAt(dx, width);
    setState(() => _interactionValue = value);
    widget.onChangeStart?.call(value);
    widget.onChanged?.call(value);
  }

  void _update(double dx, double width) {
    final value = _valueAt(dx, width);
    setState(() => _interactionValue = value);
    widget.onChanged?.call(value);
  }

  void _end() {
    final value = _interactionValue ?? widget.value;
    widget.onChangeEnd?.call(value);
    setState(() => _interactionValue = null);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final enabled = widget.onChanged != null;
      final value = (_interactionValue ?? widget.value).clamp(0.0, 1.0);
      return Semantics(
        slider: true,
        enabled: enabled,
        value: '${(value * 100).round()}%',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: enabled
              ? (details) {
                  final next = _valueAt(
                    details.localPosition.dx,
                    constraints.maxWidth,
                  );
                  widget.onChangeStart?.call(next);
                  widget.onChanged?.call(next);
                  widget.onChangeEnd?.call(next);
                }
              : null,
          onHorizontalDragStart: enabled
              ? (details) =>
                    _begin(details.localPosition.dx, constraints.maxWidth)
              : null,
          onHorizontalDragUpdate: enabled
              ? (details) =>
                    _update(details.localPosition.dx, constraints.maxWidth)
              : null,
          onHorizontalDragEnd: enabled ? (_) => _end() : null,
          onHorizontalDragCancel: enabled ? _end : null,
          child: CustomPaint(
            painter: _OwnedVideoSliderPainter(
              value: value,
              trackHeight: widget.trackHeight,
              thumbRadius: widget.thumbRadius,
              activeColor: widget.activeColor,
              inactiveColor: widget.inactiveColor,
              enabled: enabled,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      );
    },
  );
}

class _OwnedVideoSliderPainter extends CustomPainter {
  const _OwnedVideoSliderPainter({
    required this.value,
    required this.trackHeight,
    required this.thumbRadius,
    required this.activeColor,
    required this.inactiveColor,
    required this.enabled,
  });

  final double value;
  final double trackHeight;
  final double thumbRadius;
  final Color activeColor;
  final Color inactiveColor;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final left = thumbRadius;
    final right = math.max(left, size.width - thumbRadius);
    final centerY = size.height / 2;
    final thumbX = left + (right - left) * value;
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        left,
        centerY - trackHeight / 2,
        right,
        centerY + trackHeight / 2,
      ),
      Radius.circular(trackHeight / 2),
    );
    if (inactiveColor.a > 0) {
      canvas.drawRRect(trackRect, Paint()..color = inactiveColor);
    }
    if (thumbX > left) {
      canvas.save();
      canvas.clipRRect(trackRect);
      canvas.drawRect(
        Rect.fromLTRB(
          left,
          centerY - trackHeight / 2,
          thumbX,
          centerY + trackHeight / 2,
        ),
        Paint()..color = activeColor,
      );
      canvas.restore();
    }
    canvas.drawCircle(
      Offset(thumbX, centerY),
      thumbRadius,
      Paint()
        ..color = enabled ? activeColor : activeColor.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(_OwnedVideoSliderPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.trackHeight != trackHeight ||
      oldDelegate.thumbRadius != thumbRadius ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.inactiveColor != inactiveColor ||
      oldDelegate.enabled != enabled;
}
