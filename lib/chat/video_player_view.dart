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

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fvp/fvp.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka_video_player/mithka_video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../app/app_navigator.dart';
import '../app/video_split_controller.dart';
import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../media/video_view_compatibility.dart';
import '../platform/player_brightness.dart';
import '../platform/player_system_volume.dart';
import '../platform/screen_wakelock.dart';
import '../platform/system_picture_in_picture.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'chat_picker_view.dart';
import 'forward_options.dart';
import 'media_library_saver.dart';
import 'video_playback_preferences.dart';
import 'video_playback_queue.dart';

typedef TdVideoStreamQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);
typedef VideoPictureInPictureRestoreCallback =
    FutureOr<bool> Function(SystemPictureInPictureSnapshot snapshot);

const _videoStreamExtensions = <String, String>{
  'video/mp4': 'mp4',
  'video/quicktime': 'mov',
  'video/webm': 'webm',
  'video/x-matroska': 'mkv',
  'video/mpeg': 'mpeg',
  'video/x-msvideo': 'avi',
  'video/3gpp': '3gp',
  'video/3gpp2': '3g2',
};

const _videoStreamMimeTypesByExtension = <String, String>{
  'mp4': 'video/mp4',
  'm4v': 'video/mp4',
  'mov': 'video/quicktime',
  'webm': 'video/webm',
  'mkv': 'video/x-matroska',
  'mpeg': 'video/mpeg',
  'mpg': 'video/mpeg',
  'avi': 'video/x-msvideo',
  '3gp': 'video/3gpp',
  '3g2': 'video/3gpp2',
};

String? _safeFileExtension(String? fileName) {
  final name = fileName?.trim().toLowerCase() ?? '';
  final separator = name.lastIndexOf('.');
  if (separator < 0 || separator + 1 >= name.length) return null;
  final extension = name.substring(separator + 1);
  return RegExp(r'^[a-z0-9]{1,8}$').hasMatch(extension) ? extension : null;
}

String _videoStreamMimeType(String? fileName, String? value) {
  final mimeType = value?.split(';').first.trim().toLowerCase();
  if (mimeType != null && mimeType.startsWith('video/')) return mimeType;
  final extension = _safeFileExtension(fileName);
  return _videoStreamMimeTypesByExtension[extension] ?? 'video/mp4';
}

String _videoStreamExtension(String? fileName, String mimeType) {
  final mapped = _videoStreamExtensions[mimeType];
  if (mapped != null) return mapped;
  return _safeFileExtension(fileName) ?? 'mp4';
}

TdVideoStreamQuery tdVideoStreamQueryForAccount(int? accountSlot) {
  if (accountSlot == null) return TdClient.shared.query;
  return (request) => TdClient.shared.queryForSlot(request, accountSlot);
}

/// A loopback range server for partially downloaded TDLib videos.
///
/// The class is public only so its HTTP behavior can be exercised without a
/// native media player in tests. App code should treat it as an implementation
/// detail of [VideoPlayerView].
class TdVideoStreamServer {
  TdVideoStreamServer(
    this.fileId, {
    TdVideoStreamQuery? query,
    String? fileName,
    String? mimeType,
    int maxResponseBytes = _defaultMaxResponseBytes,
    this.rangeWaitTimeout = const Duration(seconds: 45),
    this.rangePollInterval = const Duration(milliseconds: 100),
  }) : assert(maxResponseBytes > 0),
       _query = query ?? TdClient.shared.query,
       _maxResponseBytes = maxResponseBytes,
       _mimeType = _videoStreamMimeType(fileName, mimeType),
       _extension = _videoStreamExtension(
         fileName,
         _videoStreamMimeType(fileName, mimeType),
       );

  final int fileId;
  final TdVideoStreamQuery _query;
  final int _maxResponseBytes;
  final String _mimeType;
  final String _extension;
  final Duration rangeWaitTimeout;
  final Duration rangePollInterval;
  HttpServer? _server;
  String? _path;
  int _total = 0;
  int _downloadOffset = 0;
  int _downloadedPrefixSize = 0;
  bool _downloadComplete = false;
  bool _closed = false;
  bool _backgroundDownloadRequested = false;
  int _playbackPreparationCount = 0;
  Future<bool>? _pendingPreparation;
  int? _continuousDownloadOffset;
  Future<void> _downloadQueue = Future<void>.value();
  final Map<(int, int), Future<Map<String, dynamic>?>> _rangeDownloads = {};

  static const _chunkSize = 2 * 1024 * 1024;
  static const _defaultMaxResponseBytes = 2 * 1024 * 1024;
  static const _metadataTailSize = 4 * 1024 * 1024;

  Future<Uri?> start() async {
    if (_closed) return null;
    try {
      final file = await _query({'@type': 'getFile', 'file_id': fileId});
      _updateFileInfo(file);
    } catch (_) {}
    if (_closed) return null;

    if (_path == null || _path!.isEmpty || _total <= 0) {
      await _primePlaybackRange(0, _chunkSize);
    }
    if (_closed) return null;
    if (_total <= 0) {
      try {
        final file = await _query({'@type': 'getFile', 'file_id': fileId});
        _updateFileInfo(file);
      } catch (_) {}
    }
    if (_closed || _total <= 0) return null;
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: true,
    );
    if (_closed) {
      await server.close(force: true);
      return null;
    }
    _server = server;
    server.listen(_handleRequest);
    return Uri.parse(
      'http://127.0.0.1:${server.port}/video/$fileId.$_extension',
    );
  }

  Future<void> close() async {
    _closed = true;
    await _server?.close(force: true);
    _server = null;
  }

  /// Makes the MP4 header and trailing metadata readable before a native
  /// player probes the loopback URL. Many Telegram videos keep the `moov` atom
  /// at EOF; exposing the URL before both ranges exist makes a transient TDLib
  /// range miss look like an unsupported file to native media backends.
  Future<bool> prepareForPlayback() async {
    if (_closed || _total <= 0) return false;
    _playbackPreparationCount++;
    try {
      final headEnd = math.min(_total - 1, _chunkSize - 1);
      if (!await _ensureRange(0, headEnd)) return false;
      final tailStart = math.max(0, _total - _metadataTailSize);
      return await _ensureRange(tailStart, _total - 1);
    } finally {
      _playbackPreparationCount--;
      if (_playbackPreparationCount == 0 &&
          _backgroundDownloadRequested &&
          _rangeDownloads.isEmpty) {
        unawaited(_startContinuousDownload(0));
      }
    }
  }

  /// Serves nothing until [preparation] settles.
  ///
  /// A caller that hands the URL to a player before [prepareForPlayback] has
  /// finished — the desktop window opens right away so the user is not left
  /// waiting on an idle chat — uses this so the first probe waits for the
  /// bootstrap ranges instead of reading a transient range miss as an
  /// unsupported file.
  void holdRequestsUntilPrepared(Future<bool> preparation) {
    // A failed preparation must release the gate rather than fail the request:
    // the per-range download is still the authority on what can be served.
    final gate = preparation.then<bool>(
      (prepared) => prepared,
      onError: (_, _) => false,
    );
    _pendingPreparation = gate;
    unawaited(
      gate.whenComplete(() {
        if (identical(_pendingPreparation, gate)) _pendingPreparation = null;
      }),
    );
  }

  void startBackgroundDownload() {
    if (_closed || _downloadComplete) return;
    _backgroundDownloadRequested = true;
    if (_playbackPreparationCount == 0 && _rangeDownloads.isEmpty) {
      unawaited(_startContinuousDownload(0));
    }
  }

  /// Creates TDLib's partial file using a bounded request. Keeping the first
  /// request finite is important when transfer boost is enabled: an unlimited
  /// download can have many large parts in flight, and changing that same
  /// download to a playback range forces TDLib to cancel those parts before it
  /// can serve the player.
  Future<void> _primePlaybackRange(int offset, int length) async {
    if (_closed) return;
    try {
      final file = await _query({
        '@type': 'downloadFile',
        'file_id': fileId,
        'priority': 32,
        'offset': offset,
        'limit': length,
        'synchronous': false,
      });
      _updateFileInfo(file);
    } catch (_) {}
  }

  void _updateFileInfo(Map<String, dynamic> file) {
    final expected = file.integer('expected_size') ?? 0;
    final size = file.integer('size') ?? 0;
    if (size > 0 || expected > 0) {
      _total = size > 0 ? size : expected;
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
    if (_closed ||
        _downloadComplete ||
        !_backgroundDownloadRequested ||
        _playbackPreparationCount > 0 ||
        _rangeDownloads.isNotEmpty ||
        _continuousDownloadOffset == offset) {
      return;
    }
    _continuousDownloadOffset = offset;
    try {
      final file = await _query({
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
    var requestFinished = false;
    unawaited(
      request.response.done.then<void>(
        (_) => requestFinished = true,
        onError: (_, _) => requestFinished = true,
      ),
    );
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
      }

      request.response.headers
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..contentType = ContentType.parse(_mimeType);

      final preparation = _pendingPreparation;
      if (preparation != null) {
        await preparation;
        if (requestFinished || _closed) return;
      }

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
      if (request.method == 'HEAD') {
        if (range == null) {
          _writeRangeHeaders(request.response, start, end, false);
        } else {
          final boundedEnd = _boundedEnd(start, end);
          _writeRangeHeaders(request.response, start, boundedEnd, true);
        }
        await request.response.close();
        return;
      }

      final boundedEnd = _boundedEnd(start, end);
      final partial = range != null || boundedEnd < _total - 1;
      final bytes = await _loadRange(
        start,
        boundedEnd,
        isCancelled: () => requestFinished,
      );
      if (requestFinished) return;
      if (bytes == null) {
        await _closeEmptyResponse(
          request.response,
          HttpStatus.serviceUnavailable,
          retryAfter: const Duration(seconds: 1),
        );
        return;
      }
      _writeRangeHeaders(request.response, start, boundedEnd, partial);
      request.response.add(bytes);
      await request.response.close();
    } catch (_) {
      // The player may cancel a range request after headers were sent. Do not
      // attempt to mutate that response again; just finish it if it is open.
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.contentLength = 0;
      } catch (_) {
        // Headers were already sent.
      }
      try {
        await request.response.close();
      } catch (_) {
        // The client already closed the response.
      }
    }
  }

  int _boundedEnd(int start, int requestedEnd) => math.min(
    requestedEnd,
    math.min(_total - 1, start + _maxResponseBytes - 1),
  );

  Future<void> _closeEmptyResponse(
    HttpResponse response,
    int statusCode, {
    Duration? retryAfter,
  }) async {
    response
      ..statusCode = statusCode
      ..contentLength = 0;
    if (retryAfter != null) {
      response.headers.set(
        HttpHeaders.retryAfterHeader,
        retryAfter.inSeconds.toString(),
      );
    }
    await response.close();
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

  /// Loads the complete bounded response before committing its headers.
  /// AVFoundation validates `Content-Length` strictly, so an unavailable or
  /// truncated TDLib range must become an empty retryable response rather than
  /// a short successful body.
  Future<List<int>?> _loadRange(
    int start,
    int end, {
    required bool Function() isCancelled,
  }) async {
    if (isCancelled() ||
        !await _ensureRange(start, end, isCancelled: isCancelled) ||
        isCancelled() ||
        _path == null) {
      return null;
    }
    final bytes = await _readRange(start, end);
    if (isCancelled() || bytes.length != end - start + 1) return null;
    return bytes;
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
      start = math.max(0, _total - math.min(suffixLength, _maxResponseBytes));
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

  Future<bool> _ensureRange(
    int start,
    int end, {
    bool Function()? isCancelled,
  }) async {
    if (_closed || isCancelled?.call() == true) return false;
    if (await _rangeIsReadable(start, end)) return true;

    final readableEnd = _downloadOffset + _downloadedPrefixSize - 1;
    final continuousOffset = _continuousDownloadOffset;
    final continuousDownloadCanReachRange =
        continuousOffset != null &&
        continuousOffset <= start &&
        start <= readableEnd + _chunkSize;
    if (continuousDownloadCanReachRange &&
        await _waitForReadableRange(start, end, isCancelled: isCancelled)) {
      return true;
    }

    if (isCancelled?.call() == true) return false;
    final length = end - start + 1;
    try {
      final file = await _downloadPlaybackRange(start, length);
      if (file != null) _updateFileInfo(file);
      if (_path == null || _path!.isEmpty) {
        await _primePlaybackRange(start, length);
      }
      return _waitForReadableRange(start, end, isCancelled: isCancelled);
    } catch (_) {
      return _waitForReadableRange(start, end, isCancelled: isCancelled);
    }
  }

  Future<Map<String, dynamic>?> _downloadPlaybackRange(int offset, int length) {
    if (_closed) return Future<Map<String, dynamic>?>.value();
    final key = (offset, length);
    final existing = _rangeDownloads[key];
    if (existing != null) return existing;

    final task = _downloadQueue.then((_) async {
      if (_closed) return null;
      _continuousDownloadOffset = null;
      try {
        return await _query({
          '@type': 'downloadFile',
          'file_id': fileId,
          'priority': 32,
          'offset': offset,
          'limit': length,
          'synchronous': true,
        }).timeout(const Duration(seconds: 45));
      } catch (_) {
        return null;
      }
    });
    _rangeDownloads[key] = task;
    _downloadQueue = task.then<void>((_) {}, onError: (_) {});
    unawaited(
      task.whenComplete(() {
        if (identical(_rangeDownloads[key], task)) {
          _rangeDownloads.remove(key);
        }
        if (!_closed &&
            _backgroundDownloadRequested &&
            _playbackPreparationCount == 0 &&
            _rangeDownloads.isEmpty &&
            !_downloadComplete) {
          unawaited(_startContinuousDownload(0));
        }
      }),
    );
    return task;
  }

  Future<bool> _waitForReadableRange(
    int start,
    int end, {
    bool Function()? isCancelled,
  }) async {
    final deadline = DateTime.now().add(rangeWaitTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_closed || isCancelled?.call() == true) return false;
      if (await _rangeIsReadable(start, end)) return true;
      await Future<void>.delayed(rangePollInterval);
    }
    return false;
  }

  Future<bool> _rangeIsReadable(int start, int end) async {
    if (_downloadComplete) return true;
    try {
      final prefix = await _query({
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

/// Restores a native PiP handoff into the app-level navigator.
///
/// Native iOS invokes this only after the user selects PiP's restore action.
/// Returning true tells AVKit that the matching player route was scheduled.
@visibleForTesting
Future<bool> restoreVideoPlaybackFromPictureInPicture({
  required VideoPlaybackQueue queue,
  required SystemPictureInPictureSnapshot snapshot,
  @visibleForTesting TdVideoStreamQuery? streamQuery,
}) async {
  final navigator = appNavigatorKey.currentState;
  if (navigator == null || !navigator.mounted) return false;
  final restoredPosition = snapshot.position.isNegative
      ? Duration.zero
      : snapshot.position;
  final route = PageRouteBuilder<void>(
    settings: RouteSettings(
      name:
          'video-pip-restore-${queue.current.video.id}-${queue.current.messageId ?? 0}',
    ),
    fullscreenDialog: true,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (routeContext, _, _) => VideoPlaylistPlayerView(
      queue: queue,
      initialPosition: restoredPosition,
      initialPlaying: snapshot.playing,
      initialMuted: snapshot.muted,
      initialSpeed: snapshot.speed,
      streamQuery: streamQuery,
      onSwitchMode: (updatedQueue, mode) {
        switch (mode) {
          case VideoDisplayMode.fullscreen:
            break;
          case VideoDisplayMode.pictureInPicture:
            Navigator.of(routeContext).maybePop();
          case VideoDisplayMode.split:
            VideoSplitController.instance.play(
              VideoSplitSession.fromQueue(updatedQueue),
            );
            Navigator.of(routeContext).maybePop();
        }
      },
    ),
  );
  unawaited(navigator.push(route));
  return true;
}

@visibleForTesting
bool usesReusableMobileFullscreenPlayer({
  required VideoPlayerPresentation presentation,
  required TargetPlatform platform,
  bool isWeb = false,
}) {
  if (isWeb || presentation != VideoPlayerPresentation.fullscreen) {
    return false;
  }
  return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
}

/// Whether the legacy video surface should install touch-style pan gestures.
///
/// Native desktop playback keeps mouse drags free for the desktop interaction
/// model. Its keyboard shortcuts, pointer-wheel volume adjustment, taps, and
/// double-click fullscreen action are handled independently and remain active.
@visibleForTesting
bool videoPlaybackSurfaceUsesPanGestures({
  required VideoPlayerPresentation presentation,
  required TargetPlatform platform,
  bool isWeb = false,
}) {
  if (presentation != VideoPlayerPresentation.fullscreen) return false;
  if (isWeb) return true;
  return platform != TargetPlatform.macOS &&
      platform != TargetPlatform.windows &&
      platform != TargetPlatform.linux;
}

@visibleForTesting
bool isStoppedVideoPlaybackComplete(VideoPlayerValue value) {
  if (value.isPlaying || !value.isInitialized) return false;
  return value.isCompleted ||
      (value.duration > Duration.zero && value.position >= value.duration);
}

enum _PlayerGesture { brightness, volume, seek, changeVideo, skipTenSeconds }

enum _PlayerGestureSide { left, right }

// Vertical adjustments should require a deliberate drag.  Mapping one screen
// height to the full range made small phone swipes change volume and brightness
// too abruptly, especially while holding the device in one hand.
const _verticalGestureSensitivity = 0.5;

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
    this.accountSlot,
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
    this.initialPlaying = true,
    this.initialSpeed = 1,
    this.initialPosition,
    this.previousVideo,
    this.nextVideo,
    this.onNavigate,
    this.onSystemPictureInPictureRestore,
    this.onToggleFullscreen,
    this.streamQuery,
  });

  final TdFileRef video;
  final int? accountSlot;
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
  final bool initialPlaying;
  final double initialSpeed;
  final Duration? initialPosition;
  final VideoPlaybackItem? previousVideo;
  final VideoPlaybackItem? nextVideo;
  final ValueChanged<int>? onNavigate;
  final VideoPictureInPictureRestoreCallback? onSystemPictureInPictureRestore;

  final VoidCallback? onToggleFullscreen;

  /// Overrides TDLib file queries for deterministic host tests.
  @visibleForTesting
  final TdVideoStreamQuery? streamQuery;

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
    this.initialPlaying = true,
    this.initialSpeed = 1,
    this.initialPosition,
    this.streamQuery,
  });

  final VideoPlaybackQueue queue;
  final VideoPlayerPresentation presentation;
  final VoidCallback? onClose;
  final bool compactControls;
  final VideoDisplayMode currentMode;
  final VideoPlaylistModeCallback? onSwitchMode;
  final ValueChanged<VideoPlaybackQueue>? onQueueChanged;
  final bool initialMuted;
  final bool initialPlaying;
  final double initialSpeed;
  final Duration? initialPosition;
  final TdVideoStreamQuery? streamQuery;

  @override
  State<VideoPlaylistPlayerView> createState() =>
      _VideoPlaylistPlayerViewState();
}

class _VideoPlaylistPlayerViewState extends State<VideoPlaylistPlayerView> {
  late VideoPlaybackQueue _queue = widget.queue;
  late Duration? _initialPosition = widget.initialPosition;
  late bool _initialPlaying = widget.initialPlaying;

  @override
  void didUpdateWidget(covariant VideoPlaylistPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.queue != oldWidget.queue) {
      _queue = widget.queue;
      _initialPosition = widget.initialPosition;
      _initialPlaying = widget.initialPlaying;
    } else if (widget.initialPosition != oldWidget.initialPosition) {
      _initialPosition = widget.initialPosition;
    }
    if (widget.initialPlaying != oldWidget.initialPlaying) {
      _initialPlaying = widget.initialPlaying;
    }
  }

  void _navigate(int delta) {
    final next = _queue.moveBy(delta);
    if (next == null) return;
    setState(() {
      _queue = next;
      _initialPosition = null;
      _initialPlaying = true;
    });
    widget.onQueueChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final item = _queue.current;
    return VideoPlayerView(
      key: ValueKey(
        '${item.accountSlot ?? 'active'}:${item.video.id}:${item.messageId ?? 0}',
      ),
      video: item.video,
      accountSlot: item.accountSlot,
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
      initialPlaying: _initialPlaying,
      initialSpeed: widget.initialSpeed,
      initialPosition: _initialPosition,
      previousVideo: _queue.previous,
      nextVideo: _queue.next,
      onNavigate: _navigate,
      streamQuery: widget.streamQuery,
      onSystemPictureInPictureRestore: (snapshot) =>
          restoreVideoPlaybackFromPictureInPicture(
            queue: _queue,
            snapshot: snapshot,
            streamQuery: widget.streamQuery,
          ),
    );
  }
}

class _VideoPlayerViewState extends State<VideoPlayerView>
    with WidgetsBindingObserver {
  late final TdVideoStreamQuery _streamQuery =
      widget.streamQuery ?? tdVideoStreamQueryForAccount(widget.accountSlot);
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _controlsVisible = true;
  bool _moreMenuVisible = false;
  bool _modeMenuVisible = false;
  Timer? _hideTimer;
  Timer? _progressRebuildTimer;
  StreamSubscription<TdFileProgress>? _progressSub;
  TdFileProgress? _progress;
  double _speed = 1;
  double _volume = 1;
  String? _localPath;
  int _lastSavedPositionMs = 0;
  TdVideoStreamServer? _streamServer;
  bool _openedCompletedLocalFile = false;
  bool _streamRecoveryInFlight = false;
  bool _completedFileRecoveryInFlight = false;
  bool _completedFileRecoveryAttempted = false;
  Future<String?>? _completedFileDownloadOperation;
  int _automaticStreamRecoveryCount = 0;
  Object? _lastControllerInitializationError;
  Timer? _streamStallTimer;
  Duration? _streamStallPosition;
  bool _retryInFlight = false;
  bool _retryFromPlaybackSnapshot = false;
  bool _lastKnownPlaybackWasPlaying = false;
  Duration _lastKnownPlaybackPosition = Duration.zero;
  bool _systemPiPHandoff = false;
  bool _systemPiPUsesActivePlayer = false;
  bool _systemPiPSupported = false;
  bool _systemPiPBusy = false;
  bool _systemPiPPrepared = false;
  bool _systemPiPActive = false;
  String? _systemPiPId;
  Future<void>? _systemPiPPrepareOperation;
  Future<bool>? _systemPiPStartOperation;
  int _lastSystemPiPSyncMs = -1;
  bool? _lastSystemPiPPlaying;
  double? _lastSystemPiPSpeed;
  bool? _lastSystemPiPMuted;
  Rect? _lastSystemPiPSourceRect;
  MithkaVideoActions? _reusablePlayerActions;
  bool _wakelockActive = false;
  bool _landscapePlayback = false;
  bool _orientationChangeInFlight = false;
  _PlayerGesture? _activeGesture;
  _PlayerGestureSide? _activeGestureSide;
  Offset? _gestureOrigin;
  double _gestureStartValue = 0;
  double _gestureValue = 0;
  bool _gestureBrightnessReady = false;
  bool _gestureVolumeReady = false;
  bool _gestureUsesSystemVolume = false;
  int _gestureVolumeRequestGeneration = 0;
  Duration _gestureStartPosition = Duration.zero;
  Duration _gestureSeekPosition = Duration.zero;
  int _gestureNavigationDelta = 0;
  VideoHorizontalSwipeAction _horizontalSwipeAction =
      VideoHorizontalSwipeAction.changeVideo;
  VideoVerticalSwipeAction _leftVerticalSwipeAction =
      VideoVerticalSwipeAction.brightness;
  VideoVerticalSwipeAction _rightVerticalSwipeAction =
      VideoVerticalSwipeAction.volume;
  VideoCompletionAction _completionAction = VideoCompletionAction.prompt;
  late final Future<PlayerBrightnessSession?> _brightnessSession;
  bool _completionHandled = false;
  bool _showCompletionPrompt = false;
  final FocusNode _completionPromptFocusNode = FocusNode(
    debugLabel: 'video-completion-primary-action',
  );
  final FocusNode _moreButtonFocusNode = FocusNode(
    debugLabel: 'video-more-button',
  );
  final FocusNode _modeButtonFocusNode = FocusNode(
    debugLabel: 'video-display-mode-button',
  );
  final LayerLink _modeButtonLink = LayerLink();
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
  // Every step costs a full SharedPreferences serialization plus a platform
  // round trip, so the tick is coarse; the exit paths and the lifecycle hook
  // below force a save, which is what actually makes the position durable.
  static const _resumeSaveStep = Duration(seconds: 15);
  static const _resumeMinimum = Duration(seconds: 3);
  static const _resumeEndSlack = Duration(seconds: 8);
  static const _streamStallTimeout = Duration(seconds: 15);

  bool get _canUseAndroidPlatformViewFallback =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      widget.presentation == VideoPlayerPresentation.fullscreen;

  bool get _usesAndroidSystemMediaVolume =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      widget.presentation == VideoPlayerPresentation.fullscreen;

  bool _isDecoderOrSurfaceFailure(Object? error) {
    if (!_canUseAndroidPlatformViewFallback || error == null) return false;
    final message = error.toString().toLowerCase();
    return message.contains('mediacodecvideorenderer') ||
        message.contains('mediacodecvideodecoderexception') ||
        message.contains('decoderinitializationexception') ||
        message.contains('video codec error') ||
        message.contains('imagereader') ||
        message.contains('surfaceproducer') ||
        (message.contains('surface') && message.contains('released'));
  }

  @override
  void initState() {
    super.initState();
    _brightnessSession = PlayerBrightnessSession.capture();
    _lastKnownPlaybackWasPlaying = widget.initialPlaying;
    if (widget.initialMuted) _volume = 0;
    if (widget.initialSpeed.isFinite && widget.initialSpeed > 0) {
      _speed = widget.initialSpeed;
    }
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadPlaybackPreferences());
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving the app is where the resume position has to become durable: the
    // process may never be resumed, and the periodic save is coarse.
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_storePlaybackPosition(force: true));
    }
  }

  Future<void> _loadPlaybackPreferences() async {
    final preferences = await VideoPlaybackPreferences.load();
    if (!mounted) return;
    setState(() {
      _horizontalSwipeAction = preferences.horizontalSwipeAction;
      _leftVerticalSwipeAction = preferences.leftVerticalSwipeAction;
      _rightVerticalSwipeAction = preferences.rightVerticalSwipeAction;
      _completionAction = preferences.completionAction;
    });
  }

  Future<void> _load({Duration? resumeOverride, bool? playOverride}) async {
    final preferredViewType = preferredCompatibleVideoViewType;
    await _progressSub?.cancel();
    _progressSub = TdFileCenter.shared
        .progress(widget.video.id, accountSlot: widget.accountSlot)
        .listen((progress) {
          if (!mounted) return;
          _progress = progress;
          if (_usesReusableMobileFullscreenPlayer) {
            _progressRebuildTimer ??= Timer(
              const Duration(milliseconds: 250),
              () {
                _progressRebuildTimer = null;
                if (mounted) setState(() {});
              },
            );
          } else {
            setState(() {});
          }
        });
    final completedPath = await _completedLocalVideoPath();
    if (!mounted) return;
    if (completedPath != null) {
      _localPath = completedPath;
      _openedCompletedLocalFile = true;
      final initialized = await _initializeFileWithSurfaceFallback(
        completedPath,
        preferredViewType: preferredViewType,
        resumeOverride: resumeOverride,
        playOverride: playOverride,
      );
      if (initialized || !mounted) return;
      _openedCompletedLocalFile = false;
    }
    final server = TdVideoStreamServer(
      widget.video.id,
      query: _streamQuery,
      fileName: widget.video.fileName,
      mimeType: widget.video.mimeType,
    );
    _streamServer = server;
    final uri = await server.start();
    if (!mounted) {
      unawaited(server.close());
      return;
    }
    if (uri == null) {
      if (await _recoverFromCompletedFile(
        releaseActiveController: false,
        resumeOverride: resumeOverride,
        playOverride: playOverride,
      )) {
        return;
      }
      if (!mounted) return;
      _showTerminalPlaybackFailure(AppStringKeys.videoPlayerLoadFailed);
      return;
    }
    _localPath = uri.toString();
    var prepared = await server.prepareForPlayback();
    if (!mounted) return;
    var initialized =
        prepared &&
        await _initializeFromUri(
          uri,
          viewType: preferredViewType,
          resumeOverride: resumeOverride,
          playOverride: playOverride,
        );
    var attemptedPlatformView = preferredViewType == VideoViewType.platformView;
    if (!initialized && mounted) {
      // A player probe can still lose a TDLib request race to an existing
      // download from another view. Revalidate the bootstrap ranges and retry
      // inside this route instead of requiring the user to close and reopen it.
      prepared = await server.prepareForPlayback();
      if (prepared && mounted) {
        final viewType =
            preferredViewType == VideoViewType.platformView ||
                _isDecoderOrSurfaceFailure(_lastControllerInitializationError)
            ? VideoViewType.platformView
            : VideoViewType.textureView;
        attemptedPlatformView = viewType == VideoViewType.platformView;
        initialized = await _initializeFromUri(
          uri,
          viewType: viewType,
          resumeOverride: resumeOverride,
          playOverride: playOverride,
        );
      }
    }
    if (!initialized &&
        mounted &&
        !attemptedPlatformView &&
        _isDecoderOrSurfaceFailure(_lastControllerInitializationError)) {
      prepared = await server.prepareForPlayback();
      if (prepared && mounted) {
        initialized = await _initializeFromUri(
          uri,
          viewType: VideoViewType.platformView,
          resumeOverride: resumeOverride,
          playOverride: playOverride,
        );
      }
    }
    if (initialized) {
      server.startBackgroundDownload();
      return;
    }
    if (!mounted) return;
    if (await _recoverFromCompletedFile(
      releaseActiveController: false,
      resumeOverride: resumeOverride,
      playOverride: playOverride,
      preferredViewType:
          preferredViewType == VideoViewType.platformView ||
              _isDecoderOrSurfaceFailure(_lastControllerInitializationError)
          ? VideoViewType.platformView
          : VideoViewType.textureView,
    )) {
      return;
    }
    if (!mounted) return;
    _showTerminalPlaybackFailure(AppStringKeys.videoPlayerCannotPlay);
  }

  Future<String?> _completedLocalVideoPath() async {
    try {
      final file = await _streamQuery({
        '@type': 'getFile',
        'file_id': widget.video.id,
      });
      return _validatedCompletedVideoPath(file);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _downloadCompletedVideoPath() async {
    final existingOperation = _completedFileDownloadOperation;
    final operation = existingOperation ?? _requestCompletedVideoDownload();
    if (existingOperation == null) {
      _completedFileDownloadOperation = operation;
      unawaited(
        operation.whenComplete(() {
          if (identical(_completedFileDownloadOperation, operation)) {
            _completedFileDownloadOperation = null;
          }
        }),
      );
    }
    try {
      return await operation.timeout(const Duration(minutes: 5));
    } on TimeoutException {
      debugPrint(
        'VideoPlayerView full-file fallback timed out for '
        '${widget.video.id}; retaining the in-flight request.',
      );
      return null;
    }
  }

  Future<String?> _requestCompletedVideoDownload() async {
    try {
      final file = await _streamQuery({
        '@type': 'downloadFile',
        'file_id': widget.video.id,
        'priority': 32,
        'offset': 0,
        'limit': 0,
        'synchronous': true,
      });
      return _validatedCompletedVideoPath(file);
    } catch (error) {
      debugPrint(
        'VideoPlayerView full-file fallback failed for '
        '${widget.video.id}: $error',
      );
      return null;
    }
  }

  Future<String?> _validatedCompletedVideoPath(
    Map<String, dynamic> file,
  ) async {
    final responseFileId = file.integer('id');
    if (responseFileId != null && responseFileId != widget.video.id) {
      return null;
    }
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
    final total = size > 0 ? size : expected;
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
  }

  Future<bool> _initializeFileWithSurfaceFallback(
    String path, {
    VideoViewType preferredViewType = VideoViewType.textureView,
    Duration? resumeOverride,
    bool? playOverride,
  }) async {
    final initialized = await _initializeFromFile(
      path,
      viewType: preferredViewType,
      resumeOverride: resumeOverride,
      playOverride: playOverride,
    );
    if (initialized ||
        preferredViewType != VideoViewType.textureView ||
        !_isDecoderOrSurfaceFailure(_lastControllerInitializationError)) {
      return initialized;
    }
    return _initializeFromFile(
      path,
      viewType: VideoViewType.platformView,
      resumeOverride: resumeOverride,
      playOverride: playOverride,
    );
  }

  Future<bool> _initializeFromFile(
    String path, {
    required VideoViewType viewType,
    Duration? resumeOverride,
    bool? playOverride,
  }) async {
    final c = VideoPlayerController.file(File(path), viewType: viewType);
    return _initializeController(
      c,
      resumeOverride: resumeOverride,
      playOverride: playOverride,
    );
  }

  Future<bool> _initializeFromUri(
    Uri uri, {
    required VideoViewType viewType,
    Duration? resumeOverride,
    bool? playOverride,
  }) async {
    return _initializeController(
      VideoPlayerController.networkUrl(uri, viewType: viewType),
      resumeOverride: resumeOverride,
      playOverride: playOverride,
    );
  }

  Future<bool> _initializeController(
    VideoPlayerController c, {
    Duration? resumeOverride,
    bool? playOverride,
  }) async {
    _lastControllerInitializationError = null;
    try {
      await c.initialize().timeout(const Duration(seconds: 45));
      await c.setLooping(false);
      await c.setPlaybackSpeed(_speed);
      await c.setVolume(_volume);
      final resume = resumeOverride != null
          ? _clampPlaybackPosition(resumeOverride, c.value.duration)
          : widget.initialPosition == null
          ? await _loadResumePosition(c.value.duration)
          : _clampPlaybackPosition(widget.initialPosition!, c.value.duration);
      if (resume > Duration.zero) await c.seekTo(resume);
      _lastKnownPlaybackPosition = resume;
      final shouldPlay = playOverride ?? widget.initialPlaying;
      if (shouldPlay) await c.play();
      _lastKnownPlaybackWasPlaying = shouldPlay;
    } catch (error, stackTrace) {
      _lastControllerInitializationError = error;
      debugPrint(
        'VideoPlayerView failed to initialize ${c.dataSource}: $error\n'
        '$stackTrace',
      );
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

  void _handleReusablePlayerError(MithkaVideoPlayerError error) {
    _recoverAfterStreamFailure(error, requireControllerError: true);
  }

  void _recoverAfterStreamFailure(
    Object error, {
    required bool requireControllerError,
  }) {
    final controller = _controller;
    final source = _localPath;
    if (controller == null ||
        (requireControllerError && controller.value.hasError != true) ||
        _streamRecoveryInFlight ||
        _completedFileRecoveryInFlight ||
        _systemPiPHandoff ||
        _systemPiPBusy ||
        _systemPiPPrepareOperation != null ||
        _systemPiPStartOperation != null ||
        source == null) {
      return;
    }
    debugPrint('VideoPlayerView runtime error for ${widget.video.id}: $error');
    final isNetworkSource =
        source.startsWith('http://') || source.startsWith('https://');
    if (!isNetworkSource) {
      if (controller.viewType == VideoViewType.textureView &&
          _isDecoderOrSurfaceFailure(error)) {
        unawaited(_recoverCompletedLocalPlayback(source));
      } else {
        unawaited(_stopErroredLocalPlayback());
      }
      return;
    }
    if (_streamServer == null) return;
    if (_automaticStreamRecoveryCount >= 1) {
      unawaited(
        _recoverFromCompletedFile(
          releaseActiveController: true,
          preferredViewType:
              _isDecoderOrSurfaceFailure(error) ||
                  controller.viewType == VideoViewType.platformView
              ? VideoViewType.platformView
              : VideoViewType.textureView,
        ).then((recovered) {
          if (!recovered && mounted) {
            _showTerminalPlaybackFailure(
              AppStringKeys.videoPlayerCannotPlay,
              preservePlaybackSnapshot: true,
            );
          }
        }),
      );
      return;
    }
    _automaticStreamRecoveryCount++;
    final recoveryViewType = _isDecoderOrSurfaceFailure(error)
        ? VideoViewType.platformView
        : controller.viewType;
    unawaited(
      _recoverStreamingPlayback(Uri.parse(source), viewType: recoveryViewType),
    );
  }

  Future<void> _recoverCompletedLocalPlayback(String path) async {
    if (_streamRecoveryInFlight || !mounted) return;
    _streamRecoveryInFlight = true;
    try {
      final recovery = await _releaseActivePlaybackForRecovery(
        closeStreamServer: false,
      );
      if (!mounted) return;
      final initialized = await _initializeFromFile(
        path,
        viewType: VideoViewType.platformView,
        resumeOverride: recovery.$1,
        playOverride: recovery.$2,
      );
      if (!initialized && mounted) {
        _showTerminalPlaybackFailure(
          AppStringKeys.videoPlayerCannotPlay,
          preservePlaybackSnapshot: true,
        );
      }
    } finally {
      _streamRecoveryInFlight = false;
    }
  }

  Future<void> _recoverStreamingPlayback(
    Uri uri, {
    required VideoViewType viewType,
  }) async {
    if (_streamRecoveryInFlight || !mounted) return;
    final server = _streamServer;
    if (server == null) return;
    _streamRecoveryInFlight = true;

    try {
      final recovery = await _releaseActivePlaybackForRecovery(
        closeStreamServer: false,
      );
      if (!mounted) return;
      final selectedViewType = _canUseAndroidPlatformViewFallback
          ? viewType
          : VideoViewType.textureView;
      var prepared = await server.prepareForPlayback();
      if (!mounted) return;
      var initialized =
          prepared &&
          await _initializeController(
            VideoPlayerController.networkUrl(uri, viewType: selectedViewType),
            resumeOverride: recovery.$1,
            playOverride: recovery.$2,
          );
      if (!initialized &&
          selectedViewType == VideoViewType.textureView &&
          _isDecoderOrSurfaceFailure(_lastControllerInitializationError)) {
        prepared = await server.prepareForPlayback();
        if (prepared && mounted) {
          initialized = await _initializeController(
            VideoPlayerController.networkUrl(
              uri,
              viewType: VideoViewType.platformView,
            ),
            resumeOverride: recovery.$1,
            playOverride: recovery.$2,
          );
        }
      }
      if (initialized) {
        server.startBackgroundDownload();
        return;
      }
      final recovered = await _recoverFromCompletedFile(
        releaseActiveController: false,
        resumeOverride: recovery.$1,
        playOverride: recovery.$2,
        preferredViewType:
            selectedViewType == VideoViewType.platformView ||
                _isDecoderOrSurfaceFailure(_lastControllerInitializationError)
            ? VideoViewType.platformView
            : VideoViewType.textureView,
      );
      if (!recovered && mounted) {
        _showTerminalPlaybackFailure(
          AppStringKeys.videoPlayerCannotPlay,
          preservePlaybackSnapshot: true,
        );
      }
    } finally {
      _streamRecoveryInFlight = false;
    }
  }

  Future<bool> _recoverFromCompletedFile({
    required bool releaseActiveController,
    Duration? resumeOverride,
    bool? playOverride,
    VideoViewType preferredViewType = VideoViewType.textureView,
  }) async {
    if (_completedFileRecoveryInFlight ||
        _completedFileRecoveryAttempted ||
        !mounted) {
      return false;
    }
    _completedFileRecoveryInFlight = true;
    _completedFileRecoveryAttempted = true;
    _streamStallTimer?.cancel();
    _streamStallTimer = null;
    _streamStallPosition = null;
    try {
      var resume = resumeOverride;
      var shouldPlay = playOverride;
      if (releaseActiveController) {
        final recovery = await _releaseActivePlaybackForRecovery(
          closeStreamServer: true,
        );
        resume = recovery.$1;
        shouldPlay = recovery.$2;
      } else {
        final server = _streamServer;
        _streamServer = null;
        await server?.close();
      }
      if (!mounted) return false;
      final path = await _downloadCompletedVideoPath();
      if (!mounted || path == null) return false;
      _localPath = path;
      _openedCompletedLocalFile = true;
      final initialized = await _initializeFileWithSurfaceFallback(
        path,
        preferredViewType: _canUseAndroidPlatformViewFallback
            ? preferredViewType
            : VideoViewType.textureView,
        resumeOverride: resume,
        playOverride: shouldPlay,
      );
      if (!initialized) _openedCompletedLocalFile = false;
      return initialized;
    } finally {
      _completedFileRecoveryInFlight = false;
    }
  }

  Future<void> _stopErroredLocalPlayback() async {
    if (_streamRecoveryInFlight || !mounted) return;
    _streamRecoveryInFlight = true;
    try {
      await _releaseActivePlaybackForRecovery(closeStreamServer: true);
      if (!mounted) return;
      _showTerminalPlaybackFailure(
        AppStringKeys.videoPlayerCannotPlay,
        preservePlaybackSnapshot: true,
      );
    } finally {
      _streamRecoveryInFlight = false;
    }
  }

  Future<(Duration, bool)> _releaseActivePlaybackForRecovery({
    required bool closeStreamServer,
  }) async {
    final oldController = _controller;
    final resume = _lastKnownPlaybackPosition;
    final shouldPlay = _lastKnownPlaybackWasPlaying;
    oldController?.removeListener(_onTick);
    _streamStallTimer?.cancel();
    _streamStallTimer = null;
    _streamStallPosition = null;

    final preparedPiPId = _systemPiPId;
    final pendingPiPPreparation = _systemPiPPrepareOperation;
    final pendingPiPStart = _systemPiPStartOperation;
    _systemPiPId = null;
    _systemPiPPrepared = false;
    _systemPiPBusy = false;
    _systemPiPUsesActivePlayer = false;
    _systemPiPPrepareOperation = null;
    _systemPiPStartOperation = null;
    final streamServer = closeStreamServer ? _streamServer : null;
    if (closeStreamServer) _streamServer = null;
    if (mounted) {
      setState(() {
        _controller = null;
        _failed = false;
      });
    }
    _updateWakelock();

    if (oldController != null) await WidgetsBinding.instance.endOfFrame;
    await _releasePlaybackResources(
      controller: oldController,
      disposeController: true,
      preparedPiPId: preparedPiPId,
      pendingPiPPreparation: pendingPiPPreparation,
      pendingPiPStart: pendingPiPStart,
      streamServer: streamServer,
    );
    return (resume, shouldPlay);
  }

  void _showTerminalPlaybackFailure(
    String messageKey, {
    bool preservePlaybackSnapshot = false,
  }) {
    if (!mounted) return;
    if (preservePlaybackSnapshot) _retryFromPlaybackSnapshot = true;
    setState(() => _failed = true);
    showToast(context, messageKey);
  }

  Future<void> _retryPlayback() async {
    if (_retryInFlight ||
        _streamRecoveryInFlight ||
        _completedFileRecoveryInFlight) {
      return;
    }
    _retryInFlight = true;
    try {
      Duration? resumeOverride;
      bool? playOverride;
      if (_retryFromPlaybackSnapshot) {
        resumeOverride = _lastKnownPlaybackPosition;
        playOverride = _lastKnownPlaybackWasPlaying;
      }
      if (_controller != null) {
        final recovery = await _releaseActivePlaybackForRecovery(
          closeStreamServer: true,
        );
        resumeOverride = recovery.$1;
        playOverride = recovery.$2;
      } else {
        _streamStallTimer?.cancel();
        _streamStallTimer = null;
        _streamStallPosition = null;
        final server = _streamServer;
        _streamServer = null;
        await server?.close();
      }
      if (!mounted) return;
      _automaticStreamRecoveryCount = 0;
      _completedFileRecoveryAttempted = false;
      _lastControllerInitializationError = null;
      _openedCompletedLocalFile = false;
      _localPath = null;
      _retryFromPlaybackSnapshot =
          resumeOverride != null || playOverride != null;
      setState(() => _failed = false);
      await _load(resumeOverride: resumeOverride, playOverride: playOverride);
      if (_controller != null) _retryFromPlaybackSnapshot = false;
    } finally {
      _retryInFlight = false;
    }
  }

  // Rebuild for play/pause + scrubber position changes.
  void _onTick() {
    final value = _controller?.value;
    if (value != null && !value.hasError) {
      if (!value.isBuffering) {
        _lastKnownPlaybackWasPlaying = value.isPlaying;
      }
      _lastKnownPlaybackPosition = value.position;
    }
    _syncStreamStallRecovery(value);
    final completed = value != null && isStoppedVideoPlaybackComplete(value);
    if (completed && !_completionHandled) {
      _completionHandled = true;
      unawaited(_handlePlaybackCompleted());
    } else if (value != null && !completed && _completionHandled) {
      _completionHandled = false;
    }
    if (value != null) {
      _volume = value.volume.clamp(0.0, 1.0);
      _speed = value.playbackSpeed;
    }
    _storePlaybackPositionIfNeeded();
    _syncSystemPictureInPictureIfNeeded();
    _updateWakelock();
    // The reusable player throttles its own chrome refreshes while the texture
    // renders independently. Avoid rebuilding the entire TDLib host for every
    // decoded frame on mobile fullscreen playback.
    if (mounted && !_usesReusableMobileFullscreenPlayer) setState(() {});
  }

  void _syncStreamStallRecovery(VideoPlayerValue? value) {
    final controller = _controller;
    final source = _localPath;
    final shouldWatch =
        controller != null &&
        value != null &&
        value.isInitialized &&
        value.isBuffering &&
        !value.hasError &&
        _lastKnownPlaybackWasPlaying &&
        _scrubPosition == null &&
        source != null &&
        (source.startsWith('http://') || source.startsWith('https://')) &&
        _streamServer != null &&
        !_streamRecoveryInFlight &&
        !_completedFileRecoveryInFlight &&
        !_systemPiPHandoff &&
        !_systemPiPBusy;
    if (!shouldWatch) {
      _streamStallTimer?.cancel();
      _streamStallTimer = null;
      _streamStallPosition = null;
      return;
    }
    final watchedPosition = _streamStallPosition;
    if (watchedPosition != null &&
        (value.position - watchedPosition).abs() >=
            const Duration(milliseconds: 250)) {
      _streamStallTimer?.cancel();
      _streamStallTimer = null;
      _streamStallPosition = null;
    }
    if (_streamStallTimer != null) return;
    _streamStallPosition = value.position;
    _streamStallTimer = Timer(_streamStallTimeout, () {
      _streamStallTimer = null;
      final activeController = _controller;
      final activeValue = activeController?.value;
      final stalledAt = _streamStallPosition;
      _streamStallPosition = null;
      if (!mounted ||
          activeController == null ||
          activeValue == null ||
          !activeValue.isBuffering ||
          stalledAt == null ||
          (activeValue.position - stalledAt).abs() >=
              const Duration(milliseconds: 250)) {
        return;
      }
      _recoverAfterStreamFailure(
        'The loopback video stream stopped making progress.',
        requireControllerError: false,
      );
    });
  }

  /// Keep the screen awake while the video is actively playing; release the
  /// wakelock when paused or finished so the system idle timer resumes.
  void _updateWakelock() {
    final c = _controller;
    final shouldKeepAwake =
        c != null && c.value.isInitialized && c.value.isPlaying;
    if (shouldKeepAwake == _wakelockActive) return;
    _wakelockActive = shouldKeepAwake;
    unawaited(
      shouldKeepAwake ? ScreenWakelock.enable() : ScreenWakelock.disable(),
    );
  }

  void _syncSystemPictureInPictureIfNeeded() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return;
    }
    if (_usesAndroidSystemPictureInPicture &&
        _systemPiPSupported &&
        c.value.isPlaying &&
        _systemPiPId == null &&
        _systemPiPPrepareOperation == null) {
      unawaited(_prepareSystemPictureInPicture());
      return;
    }
    final id = _systemPiPId;
    if (id == null || !_systemPiPPrepared) return;
    final positionMs = c.value.position.inMilliseconds;
    final playing = c.value.isPlaying;
    final muted = _volume <= 0.01;
    final sourceRect = _systemPiPActive
        ? null
        : _systemPictureInPictureSourceRect(c);
    final sourceRectChanged =
        sourceRect != null && sourceRect != _lastSystemPiPSourceRect;
    final playbackStateChanged =
        playing != _lastSystemPiPPlaying ||
        _speed != _lastSystemPiPSpeed ||
        muted != _lastSystemPiPMuted;
    if ((positionMs - _lastSystemPiPSyncMs).abs() < 900 &&
        playing &&
        !playbackStateChanged &&
        !sourceRectChanged) {
      return;
    }
    _lastSystemPiPSyncMs = positionMs;
    _lastSystemPiPPlaying = playing;
    _lastSystemPiPSpeed = _speed;
    _lastSystemPiPMuted = muted;
    if (sourceRect != null) _lastSystemPiPSourceRect = sourceRect;
    unawaited(
      SystemPictureInPicture.updatePrepared(
        id: id,
        position: c.value.position,
        speed: _speed,
        muted: muted,
        playing: playing,
        videoSize: c.value.size,
        sourceRect: sourceRect,
        playLabel: AppStringKeys.musicPlayerPlay.l10n(context),
        pauseLabel: AppStringKeys.musicPlayerPause.l10n(context),
      ),
    );
  }

  bool get _usesAndroidSystemPictureInPicture =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Rect? _systemPictureInPictureSourceRect(VideoPlayerController controller) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return null;
    }
    final videoSize = _displayVideoSize(controller);
    if (videoSize.width <= 0 || videoSize.height <= 0) return null;
    final fitted = _containSize(videoSize, renderObject.size);
    if (fitted.width <= 0 || fitted.height <= 0) return null;
    final localOffset = Offset(
      (renderObject.size.width - fitted.width) / 2,
      (renderObject.size.height - fitted.height) / 2,
    );
    final globalOffset = renderObject.localToGlobal(localOffset);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final physicalRect = Rect.fromLTWH(
      globalOffset.dx * pixelRatio,
      globalOffset.dy * pixelRatio,
      fitted.width * pixelRatio,
      fitted.height * pixelRatio,
    );
    final logicalWindowSize = MediaQuery.sizeOf(context);
    final physicalWindowBounds = Rect.fromLTWH(
      0,
      0,
      logicalWindowSize.width * pixelRatio,
      logicalWindowSize.height * pixelRatio,
    );
    final clipped = physicalRect.intersect(physicalWindowBounds);
    return clipped.isEmpty ? null : clipped;
  }

  void _handleSystemPictureInPictureEntered(SystemPictureInPictureSnapshot _) {
    if (!mounted || _systemPiPActive) return;
    _hideTimer?.cancel();
    setState(() {
      _systemPiPActive = true;
      _controlsVisible = false;
      _moreMenuVisible = false;
      _modeMenuVisible = false;
    });
  }

  void _handleSystemPictureInPictureRestored(SystemPictureInPictureSnapshot _) {
    if (!mounted || !_systemPiPActive) return;
    _lastSystemPiPSourceRect = null;
    setState(() {
      _systemPiPActive = false;
      _controlsVisible = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reusablePlayerActions?.showControls();
    });
  }

  Future<void> _handleSystemPictureInPictureAction(
    SystemPictureInPictureAction action,
  ) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    switch (action) {
      case SystemPictureInPictureAction.play:
        await controller.play();
        return;
      case SystemPictureInPictureAction.pause:
        await controller.pause();
        return;
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (_usesReusableMobileFullscreenPlayer) return;
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted &&
          !_moreMenuVisible &&
          !_modeMenuVisible &&
          (_controller?.value.isPlaying ?? false)) {
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
      _lastKnownPlaybackWasPlaying = false;
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
      _lastKnownPlaybackWasPlaying = true;
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _showCompletionPrompt) {
            _completionPromptFocusNode.requestFocus();
          }
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
    _lastKnownPlaybackWasPlaying = true;
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

  void _navigateFromControl(int delta) {
    if (!_canNavigate(delta)) return;
    widget.onNavigate?.call(delta);
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
    final accountScope = switch (widget.accountSlot) {
      null || 0 => '',
      final slot => '$slot.',
    };
    final chatId = widget.sourceChatId;
    final messageId = widget.messageId;
    if (chatId != null && messageId != null) {
      return '$_resumePrefix$accountScope$chatId.$messageId';
    }
    return '$_resumePrefix$accountScope${widget.video.id}';
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

  Duration _clampPlaybackPosition(Duration position, Duration duration) {
    if (position.isNegative) return Duration.zero;
    if (duration > Duration.zero && position > duration) return duration;
    return position;
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
    await _storeResumePosition(position, duration);
  }

  Future<void> _storeResumePosition(
    Duration position,
    Duration duration,
  ) async {
    final normalized = _clampPlaybackPosition(position, duration);
    _lastSavedPositionMs = normalized.inMilliseconds;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (normalized < _resumeMinimum ||
          (duration > Duration.zero &&
              duration - normalized <= _resumeEndSlack)) {
        await prefs.remove(_resumeKey);
      } else {
        await prefs.setInt(_resumeKey, normalized.inMilliseconds);
      }
    } catch (_) {}
  }

  VideoPlaybackQueue _pictureInPictureRestoreQueue() {
    final current = VideoPlaybackItem(
      video: widget.video,
      accountSlot: widget.accountSlot,
      thumb: widget.thumb,
      width: widget.width,
      height: widget.height,
      sourceChatId: widget.sourceChatId,
      messageId: widget.messageId,
    );
    final items = <VideoPlaybackItem>[
      ?widget.previousVideo,
      current,
      ?widget.nextVideo,
    ];
    return VideoPlaybackQueue(
      items: items,
      index: widget.previousVideo == null ? 0 : 1,
    );
  }

  Future<bool> _restoreSystemPictureInPicture(
    SystemPictureInPictureSnapshot snapshot,
  ) {
    final c = _controller;
    final duration = c?.value.duration ?? Duration.zero;
    final normalized = _clampPlaybackPosition(snapshot.position, duration);
    final normalizedSnapshot = SystemPictureInPictureSnapshot(
      position: normalized,
      playing: snapshot.playing,
      speed: snapshot.speed,
      muted: snapshot.muted,
    );
    unawaited(_storeResumePosition(normalized, duration));
    final callback = widget.onSystemPictureInPictureRestore;
    if (callback != null) {
      return Future<bool>.value(callback(normalizedSnapshot));
    }
    return restoreVideoPlaybackFromPictureInPicture(
      queue: _pictureInPictureRestoreQueue(),
      snapshot: normalizedSnapshot,
      streamQuery: widget.streamQuery,
    );
  }

  Future<bool> _startSystemPictureInPicture() {
    final pending = _systemPiPStartOperation;
    if (pending != null) return pending;
    late final Future<bool> tracked;
    tracked =
        (() async {
          await _prepareSystemPictureInPicture();
          return _performSystemPictureInPictureStart();
        })().whenComplete(() {
          if (identical(_systemPiPStartOperation, tracked)) {
            _systemPiPStartOperation = null;
          }
        });
    _systemPiPStartOperation = tracked;
    return tracked;
  }

  Future<bool> _performSystemPictureInPictureStart() async {
    final c = _controller;
    final uri = _systemPiPSourceUri();
    if (c == null || !c.value.isInitialized || uri == null) {
      return false;
    }
    if (!await _isSystemPictureInPictureSupported()) {
      return false;
    }
    final pendingPrepare = _systemPiPPrepareOperation;
    if (pendingPrepare != null) await pendingPrepare;
    if (!mounted) return false;

    var id = _systemPiPId;
    var started = false;
    final sourceRect = _systemPictureInPictureSourceRect(c);
    if (sourceRect != null) _lastSystemPiPSourceRect = sourceRect;
    final playLabel = AppStringKeys.musicPlayerPlay.l10n(context);
    final pauseLabel = AppStringKeys.musicPlayerPause.l10n(context);
    if (id != null && _systemPiPPrepared) {
      started = await SystemPictureInPicture.startPrepared(
        id: id,
        position: c.value.position,
        speed: _speed,
        muted: _volume <= 0.01,
        playing: c.value.isPlaying,
        videoSize: c.value.size,
        sourceRect: sourceRect,
        playLabel: playLabel,
        pauseLabel: pauseLabel,
      );
      if (!mounted) {
        await SystemPictureInPicture.cancelPrepared(id);
        return false;
      }
    }
    if (!started) {
      if (id != null) {
        await SystemPictureInPicture.cancelPrepared(id);
        _systemPiPPrepared = false;
        _systemPiPId = null;
      }
      id = '${widget.video.id}-${DateTime.now().microsecondsSinceEpoch}';
      _systemPiPId = id;
      final handoffId = id;
      final server = _streamServer;
      final shouldCancelOnStop =
          !_openedCompletedLocalFile && _progress?.isCompleted != true;
      var restoreAccepted = false;
      started = await SystemPictureInPicture.start(
        id: handoffId,
        uri: uri,
        position: c.value.position,
        speed: _speed,
        muted: _volume <= 0.01,
        playing: c.value.isPlaying,
        videoSize: c.value.size,
        sourceRect: sourceRect,
        playLabel: playLabel,
        pauseLabel: pauseLabel,
        playerId: c.fvpPlayerId,
        onEntered: _handleSystemPictureInPictureEntered,
        onRestored: _handleSystemPictureInPictureRestored,
        onActionRequested: _handleSystemPictureInPictureAction,
        onRestoreRequested: (position) async {
          final accepted = await _restoreSystemPictureInPicture(position);
          restoreAccepted = accepted;
          return accepted;
        },
        onStop: (finalPosition) async {
          if (_usesAndroidSystemPictureInPicture && mounted) {
            _systemPiPPrepared = false;
            _systemPiPId = null;
            _systemPiPActive = false;
            _streamServer = null;
            try {
              await c.pause();
            } catch (_) {}
            if (mounted) _close();
          }
          if (finalPosition != null) {
            await _storeResumePosition(finalPosition, c.value.duration);
          }
          if (SystemPictureInPicture.usesActivePlayer(handoffId)) {
            await c.dispose();
          }
          await server?.close();
          if (shouldCancelOnStop && !restoreAccepted) {
            await _cancelIncompleteDownload();
          }
        },
      );
      if (!mounted) {
        await SystemPictureInPicture.cancelPrepared(id);
        return false;
      }
    }
    if (!started) {
      if (mounted) {
        showToast(context, AppStringKeys.videoPlayerPictureInPictureFailed);
      }
      return false;
    }
    if (SystemPictureInPicture.keepsFlutterPlayerInActivity) {
      // Android PiP hosts this Activity. Keep the Flutter route and its video
      // texture mounted so the system captures the active player, not chat.
      _handleSystemPictureInPictureEntered(
        SystemPictureInPictureSnapshot(
          position: c.value.position,
          playing: c.value.isPlaying,
          speed: _speed,
          muted: _volume <= 0.01,
        ),
      );
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

  Future<void> _prepareSystemPictureInPicture() {
    final pending = _systemPiPPrepareOperation;
    if (pending != null) return pending;
    late final Future<void> tracked;
    tracked = _performSystemPictureInPicturePreparation().whenComplete(() {
      if (identical(_systemPiPPrepareOperation, tracked)) {
        _systemPiPPrepareOperation = null;
      }
    });
    _systemPiPPrepareOperation = tracked;
    return tracked;
  }

  Future<void> _performSystemPictureInPicturePreparation() async {
    if (_systemPiPPrepared || _systemPiPId != null) {
      return;
    }
    final c = _controller;
    final uri = _systemPiPSourceUri();
    if (c == null || !c.value.isInitialized || uri == null) return;
    if (!await _isSystemPictureInPictureSupported()) return;
    if (!mounted) return;

    final server = _streamServer;
    final shouldCancelOnStop =
        !_openedCompletedLocalFile && _progress?.isCompleted != true;
    final id = '${widget.video.id}-${DateTime.now().microsecondsSinceEpoch}';
    _systemPiPId = id;
    final sourceRect = _systemPictureInPictureSourceRect(c);
    if (sourceRect != null) _lastSystemPiPSourceRect = sourceRect;
    var restoreAccepted = false;
    final prepared = await SystemPictureInPicture.prepare(
      id: id,
      uri: uri,
      position: c.value.position,
      speed: _speed,
      muted: _volume <= 0.01,
      playing: c.value.isPlaying,
      videoSize: c.value.size,
      sourceRect: sourceRect,
      playLabel: AppStringKeys.musicPlayerPlay.l10n(context),
      pauseLabel: AppStringKeys.musicPlayerPause.l10n(context),
      playerId: c.fvpPlayerId,
      onEntered: _handleSystemPictureInPictureEntered,
      onRestored: _handleSystemPictureInPictureRestored,
      onActionRequested: _handleSystemPictureInPictureAction,
      onRestoreRequested: (position) async {
        final accepted = await _restoreSystemPictureInPicture(position);
        restoreAccepted = accepted;
        return accepted;
      },
      onStop: (finalPosition) async {
        if (_usesAndroidSystemPictureInPicture && mounted) {
          _systemPiPPrepared = false;
          _systemPiPId = null;
          _systemPiPActive = false;
          _streamServer = null;
          try {
            await c.pause();
          } catch (_) {}
          if (mounted) _close();
        }
        if (finalPosition != null) {
          await _storeResumePosition(finalPosition, c.value.duration);
        }
        if (SystemPictureInPicture.usesActivePlayer(id)) {
          await c.dispose();
        }
        await server?.close();
        if (shouldCancelOnStop && !restoreAccepted) {
          await _cancelIncompleteDownload();
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
    if (supported &&
        mounted &&
        _usesAndroidSystemPictureInPicture &&
        (_controller?.value.isPlaying ?? false)) {
      await _prepareSystemPictureInPicture();
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
    _releaseVideoOrientation();
    unawaited(_restorePlayerBrightness());
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
    WidgetsBinding.instance.removeObserver(this);
    _releaseVideoOrientation();
    unawaited(_restorePlayerBrightness());
    if (_wakelockActive) {
      _wakelockActive = false;
      unawaited(ScreenWakelock.disable());
    }
    _hideTimer?.cancel();
    _progressRebuildTimer?.cancel();
    _streamStallTimer?.cancel();
    _scrubPreviewTimer?.cancel();
    _scrubPreviewOverlay?.remove();
    _scrubPreviewOverlay = null;
    _scrubPreviewGeneration++;
    _reusablePlayerActions = null;
    _completionPromptFocusNode.dispose();
    _moreButtonFocusNode.dispose();
    _modeButtonFocusNode.dispose();
    _progressSub?.cancel();
    unawaited(_storePlaybackPosition(force: true));
    final controller = _controller;
    controller?.removeListener(_onTick);
    final preparedPiPId = _systemPiPId;
    unawaited(
      _releasePlaybackResources(
        controller: controller,
        disposeController: !_systemPiPHandoff || !_systemPiPUsesActivePlayer,
        preparedPiPId: _systemPiPHandoff ? null : preparedPiPId,
        pendingPiPPreparation: _systemPiPPrepareOperation,
        pendingPiPStart: _systemPiPStartOperation,
        streamServer: _streamServer,
      ),
    );
    if (!_systemPiPHandoff &&
        !_openedCompletedLocalFile &&
        _progress?.isCompleted != true) {
      unawaited(_cancelIncompleteDownload());
    }
    super.dispose();
  }

  Future<void> _cancelIncompleteDownload() async {
    try {
      await _streamQuery({
        '@type': 'cancelDownloadFile',
        'file_id': widget.video.id,
        'only_if_pending': false,
      });
    } catch (_) {}
  }

  Future<void> _releasePlaybackResources({
    required VideoPlayerController? controller,
    required bool disposeController,
    required String? preparedPiPId,
    required Future<void>? pendingPiPPreparation,
    required Future<bool>? pendingPiPStart,
    required TdVideoStreamServer? streamServer,
  }) async {
    // A prepared native PiP session may still retain the player's texture.
    // Release that platform session before disposing the Flutter controller.
    if (pendingPiPPreparation != null) {
      try {
        await pendingPiPPreparation;
      } catch (_) {}
    }
    if (pendingPiPStart != null) {
      try {
        await pendingPiPStart;
      } catch (_) {}
    }
    if (preparedPiPId != null) {
      await SystemPictureInPicture.cancelPrepared(preparedPiPId);
    }
    if (disposeController) {
      try {
        await controller?.dispose();
      } catch (_) {}
    }
    try {
      await streamServer?.close();
    } catch (_) {}
  }

  Future<void> _restorePlayerBrightness() async {
    final session = await _brightnessSession;
    await session?.restore();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    if (_usesReusableMobileFullscreenPlayer && ready) {
      return ColoredBox(
        color: Colors.black,
        child: _reusableMobileFullscreenPlayer(c),
      );
    }
    return _legacyPlayer(ready ? c : null);
  }

  Widget _reusableMobileFullscreenPlayer(VideoPlayerController controller) {
    final source = _reusablePlayerSource();
    return MithkaVideoPlayer(
      key: ValueKey('mobile-fullscreen-video-${widget.video.id}'),
      source: source,
      controller: controller,
      width: widget.width,
      height: widget.height,
      autoplay: false,
      initialVolume: _volume,
      initialPlaybackSpeed: _speed,
      onClose: _close,
      onToggleFullscreen: widget.onToggleFullscreen,
      onPrevious: widget.previousVideo == null
          ? null
          : () => _navigateFromControl(-1),
      onNext: widget.nextVideo == null ? null : () => _navigateFromControl(1),
      lifecycleBehavior: MithkaVideoLifecycleBehavior.delegateToController,
      controlsAutoHideDuration: const Duration(seconds: 5),
      positionUpdateInterval: const Duration(milliseconds: 200),
      interactionMode: MithkaVideoInteractionMode.delegateToChrome,
      enableKeyboardShortcuts: !_showCompletionPrompt,
      showScrubPreview: false,
      isFullscreen: true,
      onError: _handleReusablePlayerError,
      loadingBuilder: (_) => _loadingState(),
      chromeBuilder: (_, scope) {
        _reusablePlayerActions = scope.actions;
        if (_systemPiPActive) return const SizedBox.expand();
        return _mobileFullscreenChrome(controller, scope);
      },
    );
  }

  MithkaVideoSource _reusablePlayerSource() {
    final path = _localPath;
    if (path != null &&
        (path.startsWith('http://') || path.startsWith('https://'))) {
      return MithkaVideoSource.network(path);
    }
    if (path != null && path.isNotEmpty) {
      return MithkaVideoSource.file(path);
    }
    throw StateError('An initialized mobile video must have a source');
  }

  Widget _mobileFullscreenChrome(
    VideoPlayerController controller,
    MithkaVideoChromeScope scope,
  ) {
    final controlsVisible =
        scope.snapshot.controlsVisible && !_showCompletionPrompt;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Keep the surface recognizer behind interactive chrome. A drag that
        // starts on the scrubber, volume control, or any button therefore
        // belongs to that control instead of accidentally seeking, navigating,
        // or changing a side gesture value.
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: scope.actions.toggleControls,
              onDoubleTapDown: (details) => _handleMobileDoubleTap(
                details,
                constraints.maxWidth,
                scope.actions,
              ),
              onPanDown: (details) => _gestureOrigin = details.localPosition,
              onPanStart: (details) {
                scope.actions.showControls();
                _startPlaybackGesture(details, controller);
              },
              onPanUpdate: (details) =>
                  _updatePlaybackGesture(details, controller),
              onPanEnd: (_) => _finishPlaybackGesture(controller),
              onPanCancel: _cancelPlaybackGesture,
            ),
          ),
        ),
        if (controlsVisible) ..._controlChromeBlocks(visible: true),
        if (controlsVisible) ..._controls(controller),
        if (_gestureIndicatorReady)
          _activeGesture == _PlayerGesture.brightness ||
                  _activeGesture == _PlayerGesture.volume
              ? _sideLevelIndicator()
              : _gestureIndicator(controller),
        if (_showCompletionPrompt) _completionPrompt(),
        if (controlsVisible) _closeButton(),
        if (controlsVisible) _topOverflowButton(),
        if (_moreMenuVisible)
          _moreMenuOverlay(
            onTapOutside: () => _dismissMenusAndControls(scope: scope),
          ),
        if (_modeMenuVisible)
          _modeMenuOverlay(
            onTapOutside: () => _dismissMenusAndControls(scope: scope),
          ),
      ],
    );
  }

  void _handleMobileDoubleTap(
    TapDownDetails details,
    double width,
    MithkaVideoActions actions,
  ) {
    final fraction = width <= 0 ? 0.5 : details.localPosition.dx / width;
    if (fraction < 0.42) {
      unawaited(actions.seekBy(const Duration(seconds: -10)));
    } else if (fraction > 0.58) {
      unawaited(actions.seekBy(const Duration(seconds: 10)));
    } else {
      unawaited(_togglePlay());
    }
  }

  Widget _legacyPlayer(VideoPlayerController? controller) {
    final ready = controller != null && controller.value.isInitialized;
    final body = Focus(
      autofocus: _isDesktopPlatform,
      onKeyEvent: ready
          ? (_, event) => _handleDesktopKey(event, controller)
          : null,
      child: Listener(
        onPointerSignal: ready ? _handlePointerSignal : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: ready ? _toggleControls : null,
          onDoubleTap: ready && _isDesktopPlatform
              ? widget.onToggleFullscreen
              : null,
          onPanDown: ready && _supportsPlaybackGestures
              ? (details) => _gestureOrigin = details.localPosition
              : null,
          onPanStart: ready && _supportsPlaybackGestures
              ? (details) => _startPlaybackGesture(details, controller)
              : null,
          onPanUpdate: ready && _supportsPlaybackGestures
              ? (details) => _updatePlaybackGesture(details, controller)
              : null,
          onPanEnd: ready && _supportsPlaybackGestures
              ? (_) => _finishPlaybackGesture(controller)
              : null,
          onPanCancel: ready && _supportsPlaybackGestures
              ? _cancelPlaybackGesture
              : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (ready) _videoFrame(controller) else _loadingState(),
              if (ready && _controlsVisible)
                ..._controlChromeBlocks(visible: true),
              if (ready && _controlsVisible) ..._controls(controller),
              if (ready && _gestureIndicatorReady)
                _activeGesture == _PlayerGesture.brightness ||
                        _activeGesture == _PlayerGesture.volume
                    ? _sideLevelIndicator()
                    : _gestureIndicator(controller),
              if (ready && _showCompletionPrompt) _completionPrompt(),
              if (!ready || _controlsVisible)
                widget.presentation ==
                            VideoPlayerPresentation.pictureInPicture &&
                        ready
                    ? _pipTopBar()
                    : _closeButton(),
              if (ready && _controlsVisible) _topOverflowButton(),
              if (_moreMenuVisible)
                _moreMenuOverlay(onTapOutside: _dismissMenusAndControls),
              if (_modeMenuVisible)
                _modeMenuOverlay(onTapOutside: _dismissMenusAndControls),
            ],
          ),
        ),
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

  bool get _supportsPlaybackGestures => videoPlaybackSurfaceUsesPanGestures(
    presentation: widget.presentation,
    platform: defaultTargetPlatform,
    isWeb: kIsWeb,
  );

  bool get _usesReusableMobileFullscreenPlayer =>
      usesReusableMobileFullscreenPlayer(
        presentation: widget.presentation,
        platform: defaultTargetPlatform,
        isWeb: kIsWeb,
      );

  bool get _isDesktopPlatform =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  KeyEventResult _handleDesktopKey(
    KeyEvent event,
    VideoPlayerController controller,
  ) {
    if (!_isDesktopPlatform || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (_moreMenuVisible || _modeMenuVisible) {
      if (key == LogicalKeyboardKey.escape) {
        if (_moreMenuVisible) {
          _closeMoreMenu();
        } else {
          _closeModeMenu();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        FocusScope.of(context).previousFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        FocusScope.of(context).nextFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.tab ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.space) {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
      unawaited(_togglePlay());
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.keyJ) {
      _seekBy(controller, const Duration(seconds: -10));
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyL) {
      _seekBy(controller, const Duration(seconds: 10));
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _setVolume(_volume + 0.05);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _setVolume(_volume - 0.05);
    } else if (key == LogicalKeyboardKey.keyM) {
      _toggleMute();
    } else if (key == LogicalKeyboardKey.keyF ||
        key == LogicalKeyboardKey.enter) {
      widget.onToggleFullscreen?.call();
    } else if (key == LogicalKeyboardKey.home) {
      unawaited(controller.seekTo(Duration.zero));
    } else if (key == LogicalKeyboardKey.end) {
      unawaited(controller.seekTo(controller.value.duration));
    } else if (key == LogicalKeyboardKey.escape) {
      _close();
    } else {
      return KeyEventResult.ignored;
    }
    _revealControlsTemporarily();
    return KeyEventResult.handled;
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (!_isDesktopPlatform || event is! PointerScrollEvent) return;
    _setVolume(_volume + (event.scrollDelta.dy < 0 ? 0.05 : -0.05));
    _revealControlsTemporarily();
  }

  void _seekBy(VideoPlayerController controller, Duration delta) {
    final duration = controller.value.duration;
    final target = Duration(
      milliseconds:
          (controller.value.position.inMilliseconds + delta.inMilliseconds)
              .clamp(0, duration.inMilliseconds),
    );
    unawaited(controller.seekTo(target));
  }

  void _revealControlsTemporarily() {
    if (!mounted) return;
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  bool get _gestureIndicatorReady =>
      _activeGesture != null &&
      (_activeGesture != _PlayerGesture.brightness ||
          _gestureBrightnessReady) &&
      (_activeGesture != _PlayerGesture.volume || _gestureVolumeReady);

  void _startPlaybackGesture(
    DragStartDetails details,
    VideoPlayerController controller,
  ) {
    _hideTimer?.cancel();
    _gestureOrigin ??= details.localPosition;
    _gestureStartValue = _volume;
    _gestureValue = _volume;
    _gestureBrightnessReady = false;
    _gestureVolumeReady = false;
    _gestureUsesSystemVolume = false;
    _gestureVolumeRequestGeneration++;
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
      const axisLockRatio = 1.20;
      final horizontal = delta.dx.abs() >= delta.dy.abs() * axisLockRatio;
      final vertical = delta.dy.abs() >= delta.dx.abs() * axisLockRatio;
      if (!horizontal && !vertical) return;
      if (horizontal) {
        _activeGestureSide = null;
        gesture = switch (_horizontalSwipeAction) {
          VideoHorizontalSwipeAction.disabled => null,
          VideoHorizontalSwipeAction.adjustProgress => _PlayerGesture.seek,
          VideoHorizontalSwipeAction.changeVideo => _PlayerGesture.changeVideo,
          VideoHorizontalSwipeAction.skipTenSeconds =>
            _PlayerGesture.skipTenSeconds,
        };
        if (gesture == null) return;
      } else {
        final isLeftSide = origin.dx < size.width / 2;
        _activeGestureSide = isLeftSide
            ? _PlayerGestureSide.left
            : _PlayerGestureSide.right;
        final action = isLeftSide
            ? _leftVerticalSwipeAction
            : _rightVerticalSwipeAction;
        gesture = switch (action) {
          VideoVerticalSwipeAction.disabled => null,
          VideoVerticalSwipeAction.brightness => _PlayerGesture.brightness,
          VideoVerticalSwipeAction.volume => _PlayerGesture.volume,
        };
        if (gesture == null) return;
      }
      if (gesture == _PlayerGesture.brightness) {
        unawaited(_beginBrightnessGesture());
      } else if (gesture == _PlayerGesture.volume) {
        if (_usesAndroidSystemMediaVolume) {
          unawaited(_beginSystemVolumeGesture(controller));
        } else {
          _gestureStartValue = controller.value.volume;
          _gestureValue = controller.value.volume;
          _gestureVolumeReady = true;
        }
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
        if (!_gestureVolumeReady) break;
        final target =
            (_gestureStartValue -
                    delta.dy / size.height * _verticalGestureSensitivity)
                .clamp(0.0, 1.0);
        if (_gestureUsesSystemVolume) {
          unawaited(_setSystemVolumeFromGesture(target));
        } else {
          _gestureValue = target;
          controller.setVolume(target);
        }
      case _PlayerGesture.brightness:
        if (!_gestureBrightnessReady) break;
        _gestureValue =
            (_gestureStartValue -
                    delta.dy / size.height * _verticalGestureSensitivity)
                .clamp(0.01, 1.0);
        unawaited(_setPlayerBrightness(_gestureValue));
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
    final session = await _brightnessSession;
    if (session == null) return;
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

  Future<void> _setPlayerBrightness(double value) async {
    final session = await _brightnessSession;
    await session?.set(value);
  }

  Future<void> _beginSystemVolumeGesture(
    VideoPlayerController controller,
  ) async {
    final request = ++_gestureVolumeRequestGeneration;
    final current = await PlayerSystemVolume.current();
    if (!mounted ||
        request != _gestureVolumeRequestGeneration ||
        _activeGesture != _PlayerGesture.volume) {
      return;
    }
    final useSystemVolume = current?.canSet == true;
    final start = useSystemVolume
        ? current!.fraction
        : controller.value.volume.clamp(0.0, 1.0);
    setState(() {
      _gestureStartValue = start;
      _gestureValue = start;
      _gestureUsesSystemVolume = useSystemVolume;
      _gestureVolumeReady = true;
    });
  }

  Future<void> _setSystemVolumeFromGesture(double value) async {
    final request = ++_gestureVolumeRequestGeneration;
    final current = await PlayerSystemVolume.setFraction(value);
    if (!mounted ||
        request != _gestureVolumeRequestGeneration ||
        _activeGesture != _PlayerGesture.volume ||
        !_gestureUsesSystemVolume ||
        current == null) {
      return;
    }
    setState(() => _gestureValue = current.fraction);
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
    } else if (gesture == _PlayerGesture.volume && !_gestureUsesSystemVolume) {
      _volume = _gestureValue;
    }
    _cancelPlaybackGesture();
    _scheduleHide();
  }

  void _cancelPlaybackGesture() {
    _gestureVolumeRequestGeneration++;
    if (!mounted) return;
    setState(() {
      _activeGesture = null;
      _activeGestureSide = null;
      _gestureOrigin = null;
      _gestureNavigationDelta = 0;
      _gestureVolumeReady = false;
      _gestureUsesSystemVolume = false;
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
            borderRadius: BorderRadius.circular(AppRadius.card),
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

  Widget _sideLevelIndicator() {
    final gesture = _activeGesture!;
    final side = _activeGestureSide ?? _PlayerGestureSide.right;
    final value = _gestureValue.clamp(0.0, 1.0);
    final icon = gesture == _PlayerGesture.brightness
        ? HeroAppIcons.sun
        : value <= 0.01
        ? HeroAppIcons.volumeXmark
        : HeroAppIcons.volumeHigh;
    return SafeArea(
      child: Align(
        alignment: side == _PlayerGestureSide.left
            ? Alignment.centerLeft
            : Alignment.centerRight,
        child: IgnorePointer(
          child: Container(
            width: 52,
            height: 164,
            margin: const EdgeInsets.symmetric(horizontal: 18),
            padding: const EdgeInsets.fromLTRB(10, 13, 10, 11),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(AppRadius.xxl),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Column(
              children: [
                AppIcon(icon, color: Colors.white, size: 21),
                const SizedBox(height: 10),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      width: 8,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              widthFactor: 1,
                              heightFactor: value,
                              child: const ColoredBox(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(value * 100).round()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
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
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (next != null) ...[
                      const SizedBox(height: 16),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _playNextVideo,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.card),
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
                                      fontWeight: FontWeight.w600,
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
                            focusNode: _completionPromptFocusNode,
                            onTap: _playNextVideo,
                          ),
                        _completionActionButton(
                          icon: HeroAppIcons.arrowsRotate,
                          label: AppStringKeys.videoPlayerReplay,
                          autofocus: next == null,
                          focusNode: next == null
                              ? _completionPromptFocusNode
                              : null,
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
    bool autofocus = false,
    FocusNode? focusNode,
  }) {
    return _FocusableVideoActionButton(
      icon: icon,
      label: label.l10n(context),
      onPressed: onTap,
      primary: primary,
      autofocus: autofocus || primary,
      focusNode: focusNode,
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
    final minimumSecondaryHeight =
        layout.timelineCompact && _showsNavigationControls ? 48.0 : 44.0;
    final secondaryHeight = math.max(
      minimumSecondaryHeight,
      layout.actionButtonSize,
    );
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

  Widget _videoFrame(VideoPlayerController c) {
    final videoSize = _displayVideoSize(c);
    if (videoSize.width <= 0 || videoSize.height <= 0) {
      return const SizedBox.expand();
    }
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fitted = _containSize(videoSize, constraints.biggest);
          return Align(
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
          ? _plainIconButton(
              HeroAppIcons.xmark,
              _close,
              label: AppStringKeys.musicPlayerClose.l10n(context),
            )
          : _roundIconButton(
              HeroAppIcons.chevronLeft,
              _close,
              label: AppStringKeys.musicPlayerClose.l10n(context),
              size: phoneFullscreen ? 44 : 58,
            ),
    );
  }

  Widget _topOverflowButton() {
    if (widget.presentation != VideoPlayerPresentation.fullscreen) {
      return const SizedBox.shrink();
    }
    final phoneFullscreen = _usesPhoneFullscreen(context);
    final size = phoneFullscreen ? 44.0 : 58.0;
    final media = MediaQuery.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final trailingSafeInset = rtl ? media.padding.left : media.padding.right;
    return PositionedDirectional(
      top: media.padding.top + (phoneFullscreen ? 6 : 28),
      end: (phoneFullscreen ? 8 : 30) + trailingSafeInset,
      child: _roundIconButton(
        HeroAppIcons.ellipsisVertical,
        _toggleMoreMenu,
        label: AppStringKeys.momentsMore.l10n(context),
        size: size,
        focusNode: _moreButtonFocusNode,
      ),
    );
  }

  void _toggleMoreMenu() {
    _hideTimer?.cancel();
    setState(() {
      _moreMenuVisible = !_moreMenuVisible;
      _modeMenuVisible = false;
    });
  }

  void _closeMoreMenu() {
    if (!_moreMenuVisible) return;
    setState(() => _moreMenuVisible = false);
    if (_isDesktopPlatform) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _moreButtonFocusNode.requestFocus();
      });
    }
    _scheduleHide();
  }

  void _runMoreMenuAction(VoidCallback action) {
    _closeMoreMenu();
    action();
  }

  void _dismissMenusAndControls({MithkaVideoChromeScope? scope}) {
    _hideTimer?.cancel();
    FocusManager.instance.primaryFocus?.unfocus();
    final hideReusableControls = scope?.snapshot.controlsVisible == true;
    setState(() {
      _moreMenuVisible = false;
      _modeMenuVisible = false;
      if (scope == null) _controlsVisible = false;
    });
    if (hideReusableControls) scope!.actions.toggleControls();
  }

  Widget _moreMenuOverlay({required VoidCallback onTapOutside}) {
    final media = MediaQuery.of(context);
    final phoneFullscreen = _usesPhoneFullscreen(context);
    final menuWidth = math.min(212.0, media.size.width - 24);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final trailingSafeInset = rtl ? media.padding.left : media.padding.right;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: onTapOutside,
            ),
          ),
          PositionedDirectional(
            top: media.padding.top + (phoneFullscreen ? 54 : 88),
            end: (phoneFullscreen ? 10 : 30) + trailingSafeInset,
            width: menuWidth,
            child: TweenAnimationBuilder<double>(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              tween: Tween(begin: 0, end: 1),
              builder: (context, progress, child) => Opacity(
                opacity: progress,
                child: Transform.scale(
                  alignment: AlignmentDirectional.topEnd,
                  scale: 0.96 + progress * 0.04,
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: const ValueKey('video-more-menu-surface'),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.13),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x73000000),
                        blurRadius: 28,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(1),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      child: ColoredBox(
                        color: const Color(0xF21F1F21),
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: FocusTraversalGroup(
                            policy: OrderedTraversalPolicy(),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                KeyedSubtree(
                                  key: const ValueKey('video-more-download'),
                                  child: _FocusableVideoMenuItem(
                                    icon: HeroAppIcons.download,
                                    label: AppStringKeys.musicPlayerDownload
                                        .l10n(context),
                                    autofocus: true,
                                    onPressed: () => _runMoreMenuAction(
                                      () =>
                                          unawaited(_downloadVideoForOffline()),
                                    ),
                                  ),
                                ),
                                const _VideoMenuSeparator(),
                                KeyedSubtree(
                                  key: const ValueKey(
                                    'video-more-save-to-photos',
                                  ),
                                  child: _FocusableVideoMenuItem(
                                    icon: HeroAppIcons.image,
                                    label: AppStringKeys
                                        .messageActionSaveToPhotos
                                        .l10n(context),
                                    onPressed: () => _runMoreMenuAction(
                                      () => unawaited(_saveVideoToPhotos()),
                                    ),
                                  ),
                                ),
                                const _VideoMenuSeparator(),
                                KeyedSubtree(
                                  key: const ValueKey('video-more-share'),
                                  child: _FocusableVideoMenuItem(
                                    icon: HeroAppIcons.forward,
                                    label: AppStringKeys.topicChatShare.l10n(
                                      context,
                                    ),
                                    onPressed: () => _runMoreMenuAction(
                                      () => unawaited(_forwardVideo()),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleModeMenu() {
    _hideTimer?.cancel();
    setState(() {
      _modeMenuVisible = !_modeMenuVisible;
      _moreMenuVisible = false;
    });
  }

  void _closeModeMenu() {
    if (!_modeMenuVisible) return;
    setState(() => _modeMenuVisible = false);
    if (_isDesktopPlatform) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _modeButtonFocusNode.requestFocus();
      });
    }
    _scheduleHide();
  }

  void _selectDisplayMode(VideoDisplayMode mode) {
    _closeModeMenu();
    if (mode == widget.currentMode) return;
    if (mode == VideoDisplayMode.pictureInPicture) {
      unawaited(_enterPictureInPicture());
      return;
    }
    widget.onSwitchMode?.call(mode);
    _scheduleHide();
  }

  Widget _modeMenuOverlay({required VoidCallback onTapOutside}) {
    final media = MediaQuery.of(context);
    final menuWidth = math.min(220.0, media.size.width - 24);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final options = <({VideoDisplayMode mode, AppIconData icon, String label})>[
      if (widget.onSwitchMode != null ||
          widget.currentMode == VideoDisplayMode.fullscreen)
        (
          mode: VideoDisplayMode.fullscreen,
          icon: HeroAppIcons.expand,
          label: AppStringKeys.videoPlayerFullscreen.l10n(context),
        ),
      if (widget.onSwitchMode != null)
        (
          mode: VideoDisplayMode.split,
          icon: HeroAppIcons.tableColumns,
          label: AppStringKeys.videoPlayerSplitScreen.l10n(context),
        ),
      if (_canOfferPictureInPicture ||
          widget.currentMode == VideoDisplayMode.pictureInPicture)
        (
          mode: VideoDisplayMode.pictureInPicture,
          icon: HeroAppIcons.pictureInPicture,
          label: AppStringKeys.videoPlayerPictureInPicture.l10n(context),
        ),
    ];
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: onTapOutside,
            ),
          ),
          CompositedTransformFollower(
            link: _modeButtonLink,
            showWhenUnlinked: false,
            targetAnchor: rtl ? Alignment.topLeft : Alignment.topRight,
            followerAnchor: rtl ? Alignment.bottomLeft : Alignment.bottomRight,
            offset: const Offset(0, -8),
            child: SizedBox(
              width: menuWidth,
              child: TweenAnimationBuilder<double>(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 120),
                curve: Curves.easeOutCubic,
                tween: Tween(begin: 0, end: 1),
                builder: (context, progress, child) => Opacity(
                  opacity: progress,
                  child: Transform.scale(
                    alignment: AlignmentDirectional.bottomEnd,
                    scale: 0.97 + progress * 0.03,
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: const ValueKey('video-mode-menu-surface'),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xF21F1F21),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.13),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x73000000),
                          blurRadius: 28,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: FocusTraversalGroup(
                        policy: OrderedTraversalPolicy(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (
                              var index = 0;
                              index < options.length;
                              index++
                            ) ...[
                              if (index > 0) const _VideoMenuSeparator(),
                              KeyedSubtree(
                                key: ValueKey(
                                  'video-mode-${options[index].mode.name}',
                                ),
                                child: _FocusableVideoMenuItem(
                                  icon: options[index].icon,
                                  label: options[index].label,
                                  selected:
                                      options[index].mode == widget.currentMode,
                                  autofocus:
                                      options[index].mode == widget.currentMode,
                                  onPressed: () =>
                                      _selectDisplayMode(options[index].mode),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pipTopBar() {
    return Positioned(
      top: 3,
      right: 4,
      child: _plainIconButton(
        HeroAppIcons.xmark,
        _close,
        label: AppStringKeys.musicPlayerClose.l10n(context),
        size: 28,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppStringKeys.videoPlayerLoadFailed.l10n(context),
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                const SizedBox(height: 10),
                _FocusableVideoTextButton(
                  text: AppStringKeys.callsRetry.l10n(context),
                  label: AppStringKeys.callsRetry.l10n(context),
                  onPressed: () => unawaited(_retryPlayback()),
                  size: const Size(96, 40),
                  fontSize: 14,
                ),
              ],
            ),
          )
        else ...[
          ..._controlChromeBlocks(visible: true),
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
    final showNavigation = _showsNavigationControls && !layout.timelineCompact;
    return Row(
      children: [
        if (showNavigation) ...[
          _navigationControl(-1, size: layout.playButtonSize.height),
          SizedBox(width: layout.playGap),
        ],
        SizedBox(
          width: layout.playButtonSize.width,
          height: layout.playButtonSize.height,
          child: Semantics(
            label: AppStringKeys.videoPlayerLoading.l10n(context),
            excludeSemantics: true,
            child: Center(
              child: AppIcon(
                HeroAppIcons.play,
                color: Colors.white.withValues(alpha: 0.7),
                size: layout.playIconSize,
              ),
            ),
          ),
        ),
        if (showNavigation) ...[
          SizedBox(width: layout.playGap),
          _navigationControl(1, size: layout.playButtonSize.height),
        ],
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
    return _secondaryActionRow(layout);
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
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_showsDisplayModeButton) ...[
                  const SizedBox(width: 8),
                  _displayModeButton(size: 34),
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
    final secondary = _secondaryActionRow(layout);
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
    final showNavigation = _showsNavigationControls && !layout.timelineCompact;
    return Row(
      children: [
        if (showNavigation) ...[
          _navigationControl(-1, size: layout.playButtonSize.height),
          SizedBox(width: layout.playGap),
        ],
        _FocusableVideoIconButton(
          icon: playing ? HeroAppIcons.pause : HeroAppIcons.play,
          label:
              (playing
                      ? AppStringKeys.musicPlayerPause
                      : AppStringKeys.musicPlayerPlay)
                  .l10n(context),
          onPressed: _togglePlay,
          size: layout.playButtonSize,
          iconSize: layout.playIconSize,
          foregroundColor: Colors.black,
          backgroundColor: Colors.white.withValues(alpha: 0.96),
          borderColor: Colors.white,
          cornerRadius: layout.playButtonSize.height / 2,
        ),
        if (showNavigation) ...[
          SizedBox(width: layout.playGap),
          _navigationControl(1, size: layout.playButtonSize.height),
        ],
        SizedBox(width: layout.playGap),
        Text(_fmt(_displayPosition(c)), style: layout.timeStyle),
        SizedBox(width: layout.timeGap),
        Expanded(child: _scrubber(c, compact: layout.timelineCompact)),
        SizedBox(width: layout.timeGap),
        Text(_fmt(value.duration), style: layout.timeStyle),
      ],
    );
  }

  Widget _transportControls(VideoPlayerController controller) {
    final playing = controller.value.isPlaying;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_showsNavigationControls) ...[
          _navigationControl(-1, size: 54),
          const SizedBox(width: 14),
        ],
        _FocusableVideoIconButton(
          icon: playing ? HeroAppIcons.pause : HeroAppIcons.play,
          label:
              (playing
                      ? AppStringKeys.musicPlayerPause
                      : AppStringKeys.musicPlayerPlay)
                  .l10n(context),
          onPressed: _togglePlay,
          size: const Size.square(66),
          iconSize: 36,
          foregroundColor: Colors.black,
          backgroundColor: Colors.white.withValues(alpha: 0.96),
          borderColor: Colors.white,
          cornerRadius: 33,
        ),
        if (_showsNavigationControls) ...[
          const SizedBox(width: 14),
          _navigationControl(1, size: 54),
        ],
      ],
    );
  }

  Widget _secondaryActionRow(_VideoControlsLayout layout) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = layout.timelineCompact;
        final width = constraints.maxWidth;
        final actions = <Widget>[];

        void addAction(Widget action) {
          if (actions.isNotEmpty) {
            actions.add(SizedBox(width: layout.actionGap));
          }
          actions.add(action);
        }

        if (compact) {
          addAction(_muteButton(size: layout.actionButtonSize));
        } else {
          addAction(_secondaryVolumeSlider(layout));
        }
        if (!compact || width >= 220) {
          addAction(_speedMenu(compact: compact));
        }
        if (_showsOrientationButton && (!compact || width >= 272)) {
          addAction(_orientationButton(size: layout.actionButtonSize));
        }
        final displayModeMinimumWidth = compact && _showsNavigationControls
            ? 252.0
            : 240.0;
        if (_showsDisplayModeButton &&
            (!compact || width >= displayModeMinimumWidth)) {
          addAction(_displayModeButton(size: layout.actionButtonSize));
        }
        final navigation = <Widget>[];
        if (compact && _showsNavigationControls) {
          navigation.add(_navigationControl(-1, size: layout.actionButtonSize));
          navigation.add(SizedBox(width: layout.actionGap));
          navigation.add(_navigationControl(1, size: layout.actionButtonSize));
        }
        return Row(children: [...navigation, const Spacer(), ...actions]);
      },
    );
  }

  Widget _secondaryVolumeSlider(_VideoControlsLayout layout) {
    if (!layout.timelineCompact) return _volumeSlider();
    return SizedBox(width: 82, child: _volumeSlider(compact: true));
  }

  List<Widget> _compactControls(VideoPlayerController c) {
    final pip = widget.presentation == VideoPlayerPresentation.pictureInPicture;
    return [
      Center(child: _transportControls(c)),
      Positioned(
        left: 12,
        right: 12,
        bottom: 10,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 220) {
              return _scrubber(c);
            }
            return Row(
              children: [
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
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (_showsDisplayModeButton) ...[
                  const SizedBox(width: 8),
                  _displayModeButton(size: 34),
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
          MithkaVideoSlider(
            value: duration <= 0 ? 0 : position / duration,
            trackHeight: compact ? 2.5 : 4,
            thumbRadius: compact ? 5 : 8,
            activeColor: Colors.white,
            inactiveColor: Colors.transparent,
            semanticLabel: AppStringKeys.videoPlaybackSwipeAdjustProgress.l10n(
              context,
            ),
            semanticValue:
                '${_fmt(Duration(milliseconds: position))} / ${_fmt(value.duration)}',
            onChangeStart: duration <= 0
                ? null
                : (fraction) =>
                      _beginScrub(c, fraction * duration, compact: compact),
            onChanged: duration <= 0
                ? null
                : (fraction) => _updateScrub(fraction * duration),
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

  void _updateScrub(double value) {
    final position = Duration(milliseconds: value.round());
    setState(() => _scrubPosition = position);
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
    final completedLocalFile =
        _progress?.isCompleted == true &&
        !source.startsWith('http://') &&
        !source.startsWith('https://');
    if (!completedLocalFile) {
      // A thumbnail decoder opens its own AVAsset. While TDLib is still
      // streaming, that second reader would contend with the active player's
      // range requests and cannot be cancelled by a Dart timeout. Keep the
      // stable message thumbnail + timestamp until the local file is complete.
      _scrubPreviewBytes = null;
      _scrubPreviewOverlay?.markNeedsBuild();
      return;
    }
    _scrubPreviewLoading = true;
    _scrubPreviewOverlay?.markNeedsBuild();
    final generation = _scrubPreviewGeneration;
    Uint8List? bytes;
    try {
      bytes = await MithkaVideoThumbnail.generate(
        source: source,
        position: position,
      ).timeout(const Duration(seconds: 2), onTimeout: () => null);
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

  Widget _buildScrubPreviewOverlay(BuildContext _) {
    final scrubberContext = _scrubberKey.currentContext;
    final position = _scrubPosition;
    if (scrubberContext == null || position == null) {
      return const SizedBox.shrink();
    }
    final scrubberBox = scrubberContext.findRenderObject();
    // An OverlayEntry's builder context belongs to the entry's own positioned
    // subtree, not necessarily to the Overlay's coordinate space. Using it as
    // `ancestor` makes localToGlobal return entry-local coordinates (usually
    // near 0,0), which pinned previews to the window's top-left on desktop.
    final overlayBox = Overlay.of(scrubberContext).context.findRenderObject();
    if (scrubberBox is! RenderBox || overlayBox is! RenderBox) {
      return const SizedBox.shrink();
    }
    final durationMs = _controller?.value.duration.inMilliseconds ?? 0;
    final fraction = durationMs <= 0
        ? 0.0
        : (position.inMilliseconds / durationMs).clamp(0.0, 1.0);
    final visualFraction =
        Directionality.of(scrubberContext) == TextDirection.rtl
        ? 1 - fraction
        : fraction;
    final trackInset = _scrubPreviewCompact ? 0.0 : 24.0;
    final trackWidth = math.max(0.0, scrubberBox.size.width - trackInset * 2);
    final globalTarget = scrubberBox.localToGlobal(
      Offset(trackInset + trackWidth * visualFraction, 0),
    );
    final target = overlayBox.globalToLocal(globalTarget);
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
            borderRadius: BorderRadius.circular(AppRadius.control),
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
            borderRadius: BorderRadius.circular(AppRadius.control),
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
                  const Center(child: _VideoLoadingRing(size: 18)),
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
                          fontWeight: FontWeight.w600,
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

  Widget _speedMenu({bool compact = false}) {
    return _FocusableVideoTextButton(
      text: _speedText(_speed),
      label: AppStringKeys.videoPlayerPlaybackSpeed.l10n(context),
      onPressed: _cycleSpeed,
      size: Size(compact ? 44 : 62, compact ? 36 : 50),
      fontSize: compact ? 13 : 16,
    );
  }

  void _cycleSpeed() {
    final index = _speeds.indexOf(_speed);
    final next = _speeds[(index + 1) % _speeds.length];
    unawaited(_setSpeed(next));
  }

  Widget _volumeSlider({bool compact = false}) {
    final iconSize = compact ? 15.0 : 18.0;
    return SizedBox(
      width: compact ? null : 152,
      height: compact ? 36 : 38,
      child: Row(
        mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
        children: [
          _FocusableVideoIconButton(
            icon: _volumeIcon,
            label: _volumeButtonLabel,
            onPressed: _toggleMute,
            size: Size(compact ? 36 : 38, compact ? 36 : 38),
            iconSize: iconSize,
          ),
          SizedBox(width: compact ? 0 : 7),
          Expanded(
            child: MithkaVideoSlider(
              value: _volume,
              trackHeight: compact ? 2.5 : 3,
              thumbRadius: compact ? 5 : 7,
              activeColor: Colors.white,
              inactiveColor: Colors.white.withValues(alpha: 0.22),
              semanticLabel: AppStringKeys.videoPlaybackSwipeAdjustVolume.l10n(
                context,
              ),
              semanticValue: '${(_volume * 100).round()}%',
              onChangeStart: (_) => _hideTimer?.cancel(),
              onChanged: _setVolume,
              onChangeEnd: (_) => _scheduleHide(),
            ),
          ),
        ],
      ),
    );
  }

  AppIconData get _volumeIcon =>
      _volume <= 0.01 ? HeroAppIcons.volumeXmark : HeroAppIcons.volumeHigh;

  String get _volumeButtonLabel =>
      (_volume <= 0.01 ? AppStringKeys.chatUnmute : AppStringKeys.callMute)
          .l10n(context);

  Widget _muteButton({required double size}) {
    return _roundIconButton(
      _volumeIcon,
      _toggleMute,
      label: _volumeButtonLabel,
      size: size,
    );
  }

  bool get _showsOrientationButton =>
      widget.presentation == VideoPlayerPresentation.fullscreen &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Widget _orientationButton({required double size}) {
    final label =
        (_landscapePlayback
                ? AppStringKeys.videoPlayerUseSystemOrientation
                : AppStringKeys.videoPlayerPlayHorizontally)
            .l10n(context);
    return _FocusableVideoIconButton(
      icon: HeroAppIcons.rotate,
      label: label,
      enabled: !_orientationChangeInFlight,
      onPressed: _toggleVideoOrientation,
      size: Size.square(size),
      iconSize: math.max(18, size * 0.44),
      opacity: _orientationChangeInFlight ? 0.48 : 0.92,
      backgroundColor: _landscapePlayback
          ? const Color(0xE238383A)
          : const Color(0xB82C2C2E),
      borderColor: Colors.white.withValues(
        alpha: _landscapePlayback ? 0.28 : 0.12,
      ),
      cornerRadius: math.max(22, size / 2),
    );
  }

  Future<void> _toggleVideoOrientation() async {
    if (_orientationChangeInFlight) return;
    final forceLandscape = !_landscapePlayback;
    setState(() => _orientationChangeInFlight = true);
    try {
      await SystemChrome.setPreferredOrientations(
        forceLandscape
            ? const [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : DeviceOrientation.values,
      );
      if (mounted) setState(() => _landscapePlayback = forceLandscape);
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.videoPlayerOrientationChangeFailed);
      }
    } finally {
      if (mounted) setState(() => _orientationChangeInFlight = false);
    }
    _scheduleHide();
  }

  void _releaseVideoOrientation() {
    if (!_landscapePlayback && !_orientationChangeInFlight) return;
    _landscapePlayback = false;
    _orientationChangeInFlight = false;
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
  }

  bool get _canOfferPictureInPicture =>
      (widget.onSwitchMode != null ||
      _systemPiPSupported ||
      SystemPictureInPicture.isSupportedPlatform);

  bool get _showsDisplayModeButton =>
      widget.onSwitchMode != null || _canOfferPictureInPicture;

  AppIconData get _displayModeIcon => switch (widget.currentMode) {
    VideoDisplayMode.fullscreen => HeroAppIcons.expand,
    VideoDisplayMode.pictureInPicture => HeroAppIcons.pictureInPicture,
    VideoDisplayMode.split => HeroAppIcons.tableColumns,
  };

  Widget _displayModeButton({required double size}) {
    if (!_showsDisplayModeButton) return const SizedBox.shrink();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final directFullscreenRestore =
        widget.presentation == VideoPlayerPresentation.pictureInPicture &&
        widget.onSwitchMode != null;
    final currentModeLabel = switch (widget.currentMode) {
      VideoDisplayMode.fullscreen => AppStringKeys.videoPlayerFullscreen.l10n(
        context,
      ),
      VideoDisplayMode.pictureInPicture =>
        AppStringKeys.videoPlayerPictureInPicture.l10n(context),
      VideoDisplayMode.split => AppStringKeys.videoPlayerSplitScreen.l10n(
        context,
      ),
    };
    return CompositedTransformTarget(
      link: _modeButtonLink,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _FocusableVideoIconButton(
            icon: directFullscreenRestore
                ? HeroAppIcons.expand
                : _displayModeIcon,
            label:
                (directFullscreenRestore
                        ? AppStringKeys.videoPlayerFullscreen
                        : AppStringKeys.videoPlayerToggleDisplayMode)
                    .l10n(context),
            enabled: !_systemPiPBusy,
            onPressed: directFullscreenRestore
                ? () => widget.onSwitchMode!(VideoDisplayMode.fullscreen)
                : _toggleModeMenu,
            size: Size.square(size),
            iconSize: math.max(18, size * 0.44),
            opacity: _systemPiPBusy ? 0 : 0.92,
            backgroundColor: _modeMenuVisible
                ? const Color(0xE238383A)
                : const Color(0xB82C2C2E),
            borderColor: Colors.white.withValues(
              alpha: _modeMenuVisible ? 0.24 : 0.12,
            ),
            cornerRadius: math.max(22, size / 2),
            focusNode: _modeButtonFocusNode,
            semanticValue: directFullscreenRestore ? null : currentModeLabel,
            expanded: directFullscreenRestore ? null : _modeMenuVisible,
          ),
          if (!_systemPiPBusy && !directFullscreenRestore)
            PositionedDirectional(
              end: math.max(6, size * 0.16),
              bottom: math.max(6, size * 0.16),
              child: IgnorePointer(
                child: AnimatedRotation(
                  turns: _modeMenuVisible ? 0.5 : 0,
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  child: AppIcon(
                    HeroAppIcons.chevronDown,
                    color: Colors.white.withValues(alpha: 0.72),
                    size: 8,
                  ),
                ),
              ),
            ),
          if (_systemPiPBusy)
            IgnorePointer(child: _VideoLoadingRing(size: size * 0.42)),
        ],
      ),
    );
  }

  Future<void> _enterPictureInPicture() async {
    if (_systemPiPBusy) return;
    setState(() => _systemPiPBusy = true);
    // Prefer the native backend only after it has confirmed support. When a
    // presentation switch callback is available it remains the deterministic
    // fallback (including while support probing is still in flight).
    if (_systemPiPSupported ||
        (widget.onSwitchMode == null &&
            SystemPictureInPicture.isSupportedPlatform)) {
      try {
        await _startSystemPictureInPicture();
      } catch (_) {}
      if (!mounted) return;
      setState(() => _systemPiPBusy = false);
      return;
    }
    if (!mounted) return;
    setState(() => _systemPiPBusy = false);
    final callback = widget.onSwitchMode;
    if (callback != null) {
      callback(VideoDisplayMode.pictureInPicture);
    }
  }

  bool get _showsNavigationControls =>
      widget.onNavigate != null &&
      (widget.previousVideo != null || widget.nextVideo != null) &&
      widget.presentation != VideoPlayerPresentation.pictureInPicture;

  Widget _navigationControl(int delta, {required double size}) {
    final previous = delta < 0;
    final enabled = _canNavigate(delta) && widget.onNavigate != null;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final icon = previous
        ? (rtl ? HeroAppIcons.arrowRight : HeroAppIcons.arrowLeft)
        : (rtl ? HeroAppIcons.arrowLeft : HeroAppIcons.arrowRight);
    final label =
        (previous
                ? enabled
                      ? AppStringKeys.videoPlayerPreviousVideo
                      : AppStringKeys.videoPlayerNoPreviousVideo
                : enabled
                ? AppStringKeys.videoPlayerNextVideo
                : AppStringKeys.videoPlayerNoNextVideo)
            .l10n(context);
    return _FocusableVideoIconButton(
      icon: icon,
      label: label,
      enabled: enabled,
      onPressed: () => _navigateFromControl(delta),
      size: Size.square(math.max(48, size)),
      iconSize: math.max(22, size * 0.44),
      opacity: enabled ? 1 : 0.38,
      backgroundColor: Colors.black.withValues(alpha: 0.68),
      borderColor: Colors.white.withValues(alpha: 0.24),
      cornerRadius: math.max(48, size) / 2,
    );
  }

  Widget _roundIconButton(
    AppIconData icon,
    VoidCallback onTap, {
    required String label,
    double size = 50,
    FocusNode? focusNode,
  }) {
    return _FocusableVideoIconButton(
      icon: icon,
      label: label,
      onPressed: onTap,
      size: Size.square(size),
      iconSize: size * 0.5,
      opacity: 0.92,
      focusNode: focusNode,
    );
  }

  Widget _plainIconButton(
    AppIconData icon,
    VoidCallback onTap, {
    required String label,
    double size = 34,
  }) {
    return _FocusableVideoIconButton(
      icon: icon,
      label: label,
      onPressed: onTap,
      size: Size.square(size),
      iconSize: size * 0.58,
      opacity: 0.92,
    );
  }

  Future<void> _downloadVideoForOffline() async {
    if (_progress?.isCompleted == true) {
      showToast(context, AppStringKeys.videoPlayerCachedLocally);
      return;
    }
    showToast(
      context,
      AppStringKeys.videoPlayerStreamingWhileDownloading,
      visibleFor: const Duration(milliseconds: 1200),
    );
    final path = await TdFileCenter.shared.path(
      widget.video.id,
      accountSlot: widget.accountSlot,
    );
    if (!mounted) return;
    showToast(
      context,
      path == null
          ? AppStringKeys.videoPlayerLoadFailed
          : AppStringKeys.videoPlayerCachedLocally,
      visibleFor: const Duration(seconds: 2),
    );
  }

  Future<void> _saveVideoToPhotos() async {
    showToast(
      context,
      AppStringKeys.chatSavingToPhotos,
      visibleFor: const Duration(milliseconds: 1200),
    );
    final path = await TdFileCenter.shared.path(
      widget.video.id,
      accountSlot: widget.accountSlot,
    );
    final result = path == null
        ? MediaLibrarySaveResult.failed
        : await MediaLibrarySaver.savePreparedFile(File(path), isVideo: true);
    if (!mounted) return;
    showToast(context, switch (result) {
      MediaLibrarySaveResult.saved => AppStringKeys.chatSavedToPhotos,
      MediaLibrarySaveResult.permissionDenied =>
        AppStringKeys.chatSaveToPhotosPermissionDenied,
      MediaLibrarySaveResult.failed || MediaLibrarySaveResult.unsupported =>
        AppStringKeys.chatSaveToPhotosFailed,
    }, visibleFor: const Duration(seconds: 2));
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
}

class _VideoLoadingRing extends StatefulWidget {
  const _VideoLoadingRing({required this.size});

  final double size;

  @override
  State<_VideoLoadingRing> createState() => _VideoLoadingRingState();
}

class _VideoLoadingRingState extends State<_VideoLoadingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: SizedBox.square(
        dimension: widget.size,
        child: const CustomPaint(painter: _VideoLoadingRingPainter()),
      ),
    );
  }
}

class _VideoLoadingRingPainter extends CustomPainter {
  const _VideoLoadingRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.max(0.0, size.shortestSide / 2 - 1);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 1.35,
      false,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _VideoLoadingRingPainter oldDelegate) => false;
}

class _FocusableVideoTextButton extends StatefulWidget {
  const _FocusableVideoTextButton({
    required this.text,
    required this.label,
    required this.onPressed,
    required this.size,
    required this.fontSize,
  });

  final String text;
  final String label;
  final VoidCallback onPressed;
  final Size size;
  final double fontSize;

  @override
  State<_FocusableVideoTextButton> createState() =>
      _FocusableVideoTextButtonState();
}

class _FocusableVideoTextButtonState extends State<_FocusableVideoTextButton> {
  bool _focused = false;

  void _activate() => widget.onPressed();

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (focused) {
        if (_focused == focused) return;
        setState(() => _focused = focused);
      },
      mouseCursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        label: widget.label,
        value: widget.text,
        onTap: _activate,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: _activate,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _focused
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.transparent,
              border: _focused
                  ? Border.all(color: Colors.white, width: 2)
                  : null,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: SizedBox(
              width: widget.size.width,
              height: widget.size.height,
              child: Center(
                child: Text(
                  widget.text,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: widget.fontSize,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusableVideoIconButton extends StatefulWidget {
  const _FocusableVideoIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.size,
    required this.iconSize,
    this.enabled = true,
    this.opacity = 1,
    this.foregroundColor = Colors.white,
    this.backgroundColor = Colors.transparent,
    this.borderColor,
    this.cornerRadius = 10,
    this.focusNode,
    this.semanticValue,
    this.expanded,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onPressed;
  final Size size;
  final double iconSize;
  final bool enabled;
  final double opacity;
  final Color foregroundColor;
  final Color backgroundColor;
  final Color? borderColor;
  final double cornerRadius;
  final FocusNode? focusNode;
  final String? semanticValue;
  final bool? expanded;

  @override
  State<_FocusableVideoIconButton> createState() =>
      _FocusableVideoIconButtonState();
}

class _FocusableVideoIconButtonState extends State<_FocusableVideoIconButton> {
  bool _focused = false;

  void _activate() {
    if (widget.enabled) widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      enabled: widget.enabled,
      focusNode: widget.focusNode,
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (focused) {
        if (_focused == focused) return;
        setState(() => _focused = focused);
      },
      mouseCursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: Semantics(
        button: true,
        enabled: widget.enabled,
        label: widget.label,
        value: widget.semanticValue,
        expanded: widget.expanded,
        onTap: widget.enabled ? _activate : null,
        child: Opacity(
          opacity: widget.opacity,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: widget.enabled ? _activate : null,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _focused
                    ? Color.alphaBlend(
                        Colors.white.withValues(alpha: 0.14),
                        widget.backgroundColor,
                      )
                    : widget.backgroundColor,
                border: _focused
                    ? Border.all(color: Colors.white, width: 2)
                    : widget.borderColor == null
                    ? null
                    : Border.all(color: widget.borderColor!),
                borderRadius: BorderRadius.circular(widget.cornerRadius),
                boxShadow: widget.backgroundColor.a > 0
                    ? const [
                        BoxShadow(
                          color: Color(0x52000000),
                          blurRadius: 14,
                          offset: Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: SizedBox(
                width: math.max(44, widget.size.width),
                height: math.max(44, widget.size.height),
                child: Center(
                  child: AppIcon(
                    widget.icon,
                    color: widget.foregroundColor,
                    size: widget.iconSize,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusableVideoActionButton extends StatefulWidget {
  const _FocusableVideoActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.primary,
    required this.autofocus,
    this.focusNode,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool primary;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  State<_FocusableVideoActionButton> createState() =>
      _FocusableVideoActionButtonState();
}

class _FocusableVideoActionButtonState
    extends State<_FocusableVideoActionButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final foreground = widget.primary ? Colors.black : Colors.white;
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (focused) {
        if (_focused == focused) return;
        setState(() => _focused = focused);
      },
      mouseCursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        label: widget.label,
        onTap: widget.onPressed,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: widget.onPressed,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: widget.primary ? Colors.white : const Color(0xFF2C2C2E),
              border: _focused
                  ? Border.all(
                      color: widget.primary ? Colors.black : Colors.white,
                      width: 2,
                    )
                  : null,
              borderRadius: BorderRadius.circular(AppRadius.xl),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(widget.icon, size: 18, color: foreground),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoMenuSeparator extends StatelessWidget {
  const _VideoMenuSeparator();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.only(left: 44, right: 8),
      color: Colors.white.withValues(alpha: 0.09),
    );
  }
}

class _FocusableVideoMenuItem extends StatefulWidget {
  const _FocusableVideoMenuItem({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.autofocus = false,
    this.selected = false,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool autofocus;
  final bool selected;

  @override
  State<_FocusableVideoMenuItem> createState() =>
      _FocusableVideoMenuItemState();
}

class _FocusableVideoMenuItemState extends State<_FocusableVideoMenuItem> {
  bool _focused = false;
  bool _hovered = false;
  bool _pressed = false;

  void _activate() => widget.onPressed();

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final fillAlpha = _pressed
        ? 0.14
        : _focused
        ? 0.13
        : _hovered
        ? 0.08
        : widget.selected
        ? 0.07
        : 0.0;
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (focused) {
        if (_focused == focused) return;
        setState(() => _focused = focused);
      },
      onShowHoverHighlight: (hovered) {
        if (_hovered == hovered) return;
        setState(() => _hovered = hovered);
      },
      mouseCursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: widget.label,
        onTap: _activate,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: _activate,
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: fillAlpha),
              border: Border.all(
                color: _focused
                    ? Colors.white.withValues(alpha: 0.72)
                    : Colors.transparent,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Center(
                    child: AppIcon(
                      widget.icon,
                      color: Colors.white.withValues(alpha: 0.82),
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.96),
                      fontSize: 14.5,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.selected) ...[
                  const SizedBox(width: 8),
                  AppIcon(
                    HeroAppIcons.check,
                    color: Colors.white.withValues(alpha: 0.92),
                    size: 16,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
