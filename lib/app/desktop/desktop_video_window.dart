import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cineplay/cineplay.dart';
import 'package:cineplay_fvp/cineplay_fvp.dart';
import 'package:cineplay_pip/cineplay_pip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show
        debugPaintBaselinesEnabled,
        debugPaintLayerBordersEnabled,
        debugPaintPointersEnabled,
        debugPaintSizeEnabled,
        debugRepaintRainbowEnabled;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:video_player/video_player.dart';

import '../../chat/media/media_download_service.dart';
import '../../chat/media/video_player_view.dart';
import '../../chat/media/video_stream_debugger.dart';
import '../../components/app_icons.dart';
import '../../components/toast.dart';
import '../../l10n/app_localizations.dart';
import '../../media/video_playback_reporting.dart';
import '../../tdlib/td_client.dart';
import '../../tdlib/td_image_loader.dart';
import '../../tdlib/td_models.dart';
import '../../theme/app_theme.dart';
import '../video_split_controller.dart';
import 'desktop_media_window_registry.dart';
import 'desktop_video_window_actions.dart';

bool get supportsDesktopVideoWindows => fVideoSupportsDesktopVideoWindows;

typedef DesktopVideoWindowArguments = FVideoDesktopWindowArguments;

@visibleForTesting
Future<bool> prepareDesktopVideoPlayback(
  Future<bool> Function() prepare, {
  int maximumAttempts = 2,
}) async {
  assert(maximumAttempts > 0);
  for (var attempt = 0; attempt < maximumAttempts; attempt++) {
    if (await prepare()) return true;
  }
  return false;
}

@visibleForTesting
TdFileProgress? decodeDesktopVideoProgress(String source) {
  try {
    final value = jsonDecode(source);
    if (value is! Map<String, dynamic>) return null;
    int? integer(String key) {
      final field = value[key];
      return field is num ? field.toInt() : null;
    }

    final fileId = integer('file_id');
    final total = integer('total');
    final downloaded = integer('downloaded');
    final prefix = integer('prefix_downloaded');
    if (fileId == null ||
        total == null ||
        downloaded == null ||
        prefix == null ||
        total < 0) {
      return null;
    }
    final downloadedRanges = <TdFileByteRange>[];
    final rawRanges = value['downloaded_ranges'];
    if (rawRanges is List) {
      for (final rawRange in rawRanges) {
        if (rawRange is! Map) continue;
        final startValue = rawRange['start'];
        final endValue = rawRange['end'];
        if (startValue is! num || endValue is! num) continue;
        final start = startValue.toInt().clamp(0, total);
        final end = endValue.toInt().clamp(start, total);
        if (end > start) {
          downloadedRanges.add(TdFileByteRange(start: start, end: end));
        }
      }
    }
    return TdFileProgress(
      fileId: fileId,
      downloaded: downloaded.clamp(0, total),
      prefixDownloaded: prefix.clamp(0, total),
      total: total,
      isActive: value['is_active'] == true,
      isCompleted: value['is_completed'] == true,
      downloadedRanges: List<TdFileByteRange>.unmodifiable(downloadedRanges),
    );
  } catch (_) {
    return null;
  }
}

class DesktopVideoWindowService {
  DesktopVideoWindowService._();

  static final DesktopVideoWindowService instance =
      DesktopVideoWindowService._();

  /// Keeps one window per video: a repeat play raises the window that already
  /// has it instead of stacking a second copy of the same video.
  final DesktopMediaWindowRegistry _windows = DesktopMediaWindowRegistry();

  /// Save and share targets of each open window, by window id.
  final Map<int, _VideoWindowActions> _actions = {};

  /// Opens still in flight. A new window can ask for its actions before
  /// [open] has learned the window's id, so requests wait for these first.
  final Set<Future<void>> _opening = {};

  /// Opens [session] in its own window. [onShare] forwards the message from
  /// the chat that opened it and returns whether the share sheet opened; when
  /// null, the window offers Save only.
  Future<bool> open(
    VideoSplitSession session, {
    bool muted = false,
    Future<bool> Function()? onShare,
  }) async {
    final done = Completer<void>();
    _opening.add(done.future);
    try {
      return await _open(session, muted: muted, onShare: onShare);
    } finally {
      _opening.remove(done.future);
      done.complete();
    }
  }

  Future<bool> _open(
    VideoSplitSession session, {
    required bool muted,
    Future<bool> Function()? onShare,
  }) async {
    if (!supportsDesktopVideoWindows) return false;
    final videoId = session.video.id;
    final accountSlot = session.accountSlot ?? TdClient.shared.activeSlot;
    final mediaKey = (accountSlot: accountSlot, videoId: videoId);
    if (_windows.isOpening(mediaKey)) return true;
    final existing = _windows.windowFor(mediaKey);
    if (existing != null) {
      if (await FVideoDesktopWindows.instance.focus(existing)) return true;
      _windows.forget(mediaKey);
    }
    _windows.beginOpening(mediaKey);
    final accountLease = TdClient.shared.retainAccountSlot(accountSlot);
    if (accountLease == null) {
      _windows.finishOpening(mediaKey);
      return false;
    }
    final stream = TdVideoStreamServer(
      videoId,
      query: accountLease.query,
      fileName: session.video.fileName,
      mimeType: session.video.mimeType,
    );
    Future<void> releaseResources() async {
      await stream.close();
      await accountLease.release();
    }

    var handedOffToWindow = false;
    int? openedWindowId;
    try {
      final uri = await stream.start();
      if (uri == null) return false;
      // Binding the loopback server is quick; filling its bootstrap ranges is
      // not. Start that in the background and open the window immediately so
      // the player's own loading state stands in for the wait — waiting here
      // would leave the chat looking like the tap did nothing.
      stream.holdRequestsUntilPrepared(
        prepareDesktopVideoPlayback(stream.prepareForPlayback),
      );
      final windowId = await FVideoDesktopWindows.instance.open(
        DesktopVideoWindowArguments(
          uri: uri,
          title: session.title,
          width: session.width,
          height: session.height,
          muted: muted,
        ),
        onClosed: () {
          _windows.forget(mediaKey);
          _actions.remove(openedWindowId);
          return releaseResources();
        },
      );
      if (windowId == null) throw StateError('Window creation failed');
      openedWindowId = windowId;
      setDesktopVideoWindowActionHandler(_handleAction);
      _actions[windowId] = _VideoWindowActions(
        video: session.video,
        accountSlot: accountSlot,
        onShare: onShare,
      );
      handedOffToWindow = true;
      return true;
    } catch (_) {
      return false;
    } finally {
      _windows.finishOpening(mediaKey, windowId: openedWindowId);
      if (!handedOffToWindow) await releaseResources();
    }
  }

  Future<Map<String, Object?>?> _handleAction(
    int fromWindowId,
    DesktopVideoWindowAction action,
  ) async {
    var actions = _actions[fromWindowId];
    if (actions == null && _opening.isNotEmpty) {
      await Future.wait(
        _opening.toList(),
      ).timeout(const Duration(seconds: 5), onTimeout: () => const []);
      actions = _actions[fromWindowId];
    }
    if (actions == null) return null;
    switch (action) {
      case DesktopVideoWindowAction.capabilities:
        return DesktopVideoWindowCapabilities(
          canSave: MediaDownloadService.isSupported,
          canShare: actions.onShare != null,
        ).toJson();
      case DesktopVideoWindowAction.save:
        final outcome = await MediaDownloadService.saveMedia(
          file: actions.video,
          isVideo: true,
          accountSlot: actions.accountSlot,
        );
        return DesktopVideoWindowActionResult(
          ok: outcome.result == MediaDownloadResult.saved,
          message: MediaDownloadService.feedbackFor(outcome),
        ).toJson();
      case DesktopVideoWindowAction.share:
        final onShare = actions.onShare;
        if (onShare == null) {
          return DesktopVideoWindowActionResult.failed.toJson();
        }
        // The chat picker opens in this window, so bring it forward first.
        await focusCurrentDesktopWindow();
        bool ok;
        try {
          ok = await onShare();
        } on Object {
          ok = false;
        }
        return DesktopVideoWindowActionResult(ok: ok).toJson();
    }
  }
}

class _VideoWindowActions {
  const _VideoWindowActions({
    required this.video,
    required this.accountSlot,
    required this.onShare,
  });

  final TdFileRef video;
  final int accountSlot;
  final Future<bool> Function()? onShare;
}

class DesktopVideoWindowApp extends StatelessWidget {
  const DesktopVideoWindowApp({super.key, required this.arguments});

  final DesktopVideoWindowArguments arguments;

  @override
  Widget build(BuildContext context) {
    // Flutter's service extensions are isolate-scoped. A debug-paint toggle on
    // a detached engine must never leak into the product chrome as yellow text
    // baselines or layout outlines. Reassert this on every child rebuild so a
    // restored inspector setting cannot turn the overlays back on.
    debugPaintSizeEnabled = false;
    debugPaintBaselinesEnabled = false;
    debugPaintLayerBordersEnabled = false;
    debugPaintPointersEnabled = false;
    debugRepaintRainbowEnabled = false;
    return MaterialApp(
      title: arguments.title,
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
      // The player's screens bring no text style of their own; without this
      // default a Text that omits its weight draws at weight 900.
      builder: (context, child) => DefaultTextStyle(
        style: AppTextStyle.body(Colors.white),
        child: child ?? const SizedBox.shrink(),
      ),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: FVideoDesktopWindowHost(
        initialArguments: arguments,
        builder: (context, arguments) =>
            _DesktopVideoWindowPlayer(arguments: arguments),
      ),
    );
  }
}

class _DesktopVideoWindowPlayer extends StatefulWidget {
  const _DesktopVideoWindowPlayer({required this.arguments});

  final DesktopVideoWindowArguments arguments;

  @override
  State<_DesktopVideoWindowPlayer> createState() =>
      _DesktopVideoWindowPlayerState();
}

class _DesktopVideoWindowPlayerState extends State<_DesktopVideoWindowPlayer> {
  VideoPlayerController? _controller;
  late final _playbackDiagnostics =
      VideoPlaybackDiagnostics(
        location: VideoPlaybackLocation.desktopWindow,
        width: arguments.width,
        height: arguments.height,
      )..beginAttempt(
        source: VideoPlaybackSource.loopback,
        viewType: VideoViewType.textureView,
      );
  FVideoPlaybackState? _playbackState;
  final HttpClient _progressClient = HttpClient();
  final FVideoThumbnailCache _thumbnailCache = FVideoThumbnailCache();
  final List<String> _debugEvents = <String>[];
  List<FVideoChapter> _chapters = const [];
  Timer? _progressTimer;
  TdFileProgress? _progress;
  DateTime? _progressSampleAt;
  int? _progressSampleBytes;
  double _downloadBytesPerSecond = 0;
  bool _progressRequestInFlight = false;
  bool _debuggerVisible = false;
  DesktopVideoWindowCapabilities _messageActions =
      DesktopVideoWindowCapabilities.none;
  bool _pictureInPictureSupported = false;
  bool _pictureInPicture = false;
  bool _pictureInPictureBusy = false;
  bool _pictureInPictureRestoreRequested = false;
  bool _wasPlayingBeforePictureInPicture = false;

  DesktopVideoWindowArguments get arguments => widget.arguments;

  @override
  void initState() {
    super.initState();
    FVideoDesktopWindows.currentWindowCloseRevision.addListener(
      _handleWindowClosing,
    );
    _recordDebugEvent('stream inspector connected');
    unawaited(_pollProgress());
    _progressTimer = Timer.periodic(
      const Duration(milliseconds: 400),
      (_) => unawaited(_pollProgress()),
    );
    unawaited(_loadPictureInPictureSupport());
    unawaited(_loadMessageActions());
  }

  Future<void> _loadMessageActions() async {
    final capabilities = await requestDesktopVideoWindowCapabilities();
    if (mounted && capabilities.any) {
      setState(() => _messageActions = capabilities);
    }
  }

  Future<void> _saveVideo() async {
    final result = await requestDesktopVideoWindowAction(
      DesktopVideoWindowAction.save,
    );
    // The save panel belongs to the main window; come back to the video.
    await focusCurrentDesktopWindow();
    if (!mounted) return;
    final message =
        result.message ??
        (result.ok ? null : AppStringKeys.chatSaveToFolderFailed);
    if (message != null) showToast(context, message);
  }

  Future<void> _shareVideo() async {
    final result = await requestDesktopVideoWindowAction(
      DesktopVideoWindowAction.share,
    );
    if (!mounted || result.ok) return;
    showToast(context, AppStringKeys.videoPlayerForwardUnsupported);
  }

  Future<void> _pollProgress() async {
    if (_progressRequestInFlight) return;
    _progressRequestInFlight = true;
    try {
      final request = await _progressClient.getUrl(
        tdVideoStreamProgressUri(arguments.uri),
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return;
      }
      final source = await response.transform(utf8.decoder).join();
      final next = decodeDesktopVideoProgress(source);
      if (next == null || !mounted) return;
      final previous = _progress;
      final sampleAt = DateTime.now();
      final previousSampleAt = _progressSampleAt;
      final previousSampleBytes = _progressSampleBytes;
      final elapsedSeconds = previousSampleAt == null
          ? 0.0
          : sampleAt.difference(previousSampleAt).inMicroseconds / 1000000;
      final byteDelta = previousSampleBytes == null
          ? 0
          : math.max(0, next.downloaded - previousSampleBytes);
      final transferRate = elapsedSeconds > 0
          ? byteDelta / elapsedSeconds
          : 0.0;
      setState(() {
        _progress = next;
        _progressSampleAt = sampleAt;
        _progressSampleBytes = next.downloaded;
        _downloadBytesPerSecond = transferRate;
        if (previous?.downloaded != next.downloaded ||
            previous?.prefixDownloaded != next.prefixDownloaded ||
            previous?.total != next.total) {
          _recordDebugEvent(
            'download ${_formatDebugBytes(next.downloaded)} / '
            '${_formatDebugBytes(next.total)}',
          );
        }
      });
    } catch (_) {
      // The parent engine owns this loopback endpoint and may close it first.
    } finally {
      _progressRequestInFlight = false;
    }
  }

  void _recordDebugEvent(String event) {
    final now = DateTime.now();
    final timestamp =
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    _debugEvents.add('$timestamp  $event');
    if (_debugEvents.length > 80) {
      _debugEvents.removeRange(0, _debugEvents.length - 80);
    }
  }

  String _formatDebugBytes(int value) {
    if (value >= 1024 * 1024) {
      return '${(value / (1024 * 1024)).toStringAsFixed(1)} MiB';
    }
    if (value >= 1024) return '${(value / 1024).toStringAsFixed(0)} KiB';
    return '$value B';
  }

  void _handleControllerReady(VideoPlayerController controller) {
    if (identical(_controller, controller)) return;
    _controller?.removeListener(_handleControllerChanged);
    _controller = controller;
    _playbackDiagnostics.initialized(value: controller.value);
    controller.addListener(_handleControllerChanged);
  }

  void _handlePlaybackError(FVideoPlayerError error) {
    // FVideoPlayer also calls onError for harmless command failures (volume,
    // PiP, etc.). A fatal error changes its state BEFORE invoking onError.
    if (!mounted || _playbackState != FVideoPlaybackState.failed) return;
    _playbackDiagnostics.recordFailure(
      error,
      stage: _controller == null
          ? VideoFailureStage.initialization
          : VideoFailureStage.playback,
    );
    _playbackDiagnostics.reportTerminal();
  }

  void _handleControllerChanged() {
    if (mounted && _debuggerVisible) setState(() {});
  }

  Future<void> _loadPictureInPictureSupport() async {
    if (!Platform.isMacOS) return;
    final supported = await FVideoPictureInPicture.isSupported();
    if (mounted && supported != _pictureInPictureSupported) {
      setState(() => _pictureInPictureSupported = supported);
    }
  }

  void _handleWindowClosing() {
    unawaited(_controller?.pause());
    if (_pictureInPicture) unawaited(FVideoPictureInPicture.stop());
  }

  Future<void> _setPictureInPicture(bool enabled) async {
    if (_pictureInPictureBusy || enabled == _pictureInPicture) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() => _pictureInPictureBusy = true);
    if (!enabled) {
      await FVideoPictureInPicture.stop();
      if (mounted) setState(() => _pictureInPictureBusy = false);
      return;
    }

    final value = controller.value;
    _pictureInPictureRestoreRequested = false;
    _wasPlayingBeforePictureInPicture = value.isPlaying;
    final sourceSize = value.size;
    final videoSize = sourceSize.width > 0 && sourceSize.height > 0
        ? sourceSize
        : Size(
            (arguments.width ?? 16).toDouble(),
            (arguments.height ?? 9).toDouble(),
          );
    final id = 'desktop-video:${arguments.uri}';
    final started = await FVideoPictureInPicture.start(
      id: id,
      uri: arguments.uri,
      position: value.position,
      speed: value.playbackSpeed,
      volume: value.volume,
      muted: value.volume <= 0.001,
      playing: value.isPlaying,
      videoSize: videoSize,
      onRestoreRequested: (_) async {
        _pictureInPictureRestoreRequested = true;
        await FVideoDesktopWindows.focusCurrentWindow();
        return true;
      },
      onStop: (finalPosition) async {
        final activeController = _controller;
        if (activeController != null && finalPosition != null) {
          await activeController.seekTo(finalPosition);
        }
        final restoreRequested = _pictureInPictureRestoreRequested;
        _pictureInPictureRestoreRequested = false;
        if (mounted) {
          setState(() {
            _pictureInPicture = false;
            _pictureInPictureBusy = false;
          });
        }
        if (restoreRequested) {
          if (_wasPlayingBeforePictureInPicture) {
            await activeController?.play();
          }
        } else {
          await FVideoDesktopWindows.closeCurrentWindow();
        }
      },
    );
    if (!mounted) {
      if (started) await FVideoPictureInPicture.stop();
      return;
    }
    if (started) {
      await controller.pause();
    }
    setState(() {
      _pictureInPicture = started;
      _pictureInPictureBusy = false;
    });
    if (started) await FVideoDesktopWindows.hideCurrentWindow();
  }

  @override
  void dispose() {
    FVideoDesktopWindows.currentWindowCloseRevision.removeListener(
      _handleWindowClosing,
    );
    _progressTimer?.cancel();
    _progressClient.close(force: true);
    _controller?.removeListener(_handleControllerChanged);
    unawaited(_controller?.pause());
    if (_pictureInPicture) unawaited(FVideoPictureInPicture.stop());
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: FVideoDesktopWindows.currentWindowFullscreen,
    builder: (context, fullscreen, _) =>
        ColoredBox(color: Colors.black, child: _playerAndInspector(fullscreen)),
  );

  Widget _playerAndInspector(bool fullscreen) {
    final player = _player(fullscreen);
    final controller = _controller;
    return VideoStreamDebuggerOverlay(
      player: player,
      visible: _debuggerVisible && controller != null,
      inspectorBuilder: (_, _) =>
          controller == null ? const SizedBox.shrink() : _inspector(controller),
    );
  }

  Widget _inspector(VideoPlayerController controller) => VideoStreamDebugger(
    key: const ValueKey('desktop-video-stream-inspector'),
    progress: _progress,
    position: controller.value.position,
    duration: controller.value.duration,
    events: List<String>.unmodifiable(_debugEvents),
    viewportSize: MediaQuery.sizeOf(context),
    videoSize: controller.value.size,
    volume: controller.value.volume,
    playbackSpeed: controller.value.playbackSpeed,
    bufferedAhead: _bufferedAhead(controller.value),
    downloadBytesPerSecond: _downloadBytesPerSecond,
    isLive: _progress?.isActive == true || controller.value.isPlaying,
    onClose: () => setState(() => _debuggerVisible = false),
  );

  Duration _bufferedAhead(VideoPlayerValue value) {
    var bufferedEnd = value.position;
    for (final range in value.buffered) {
      if (range.end.compareTo(bufferedEnd) > 0) bufferedEnd = range.end;
    }
    final ahead = bufferedEnd - value.position;
    return ahead.isNegative ? Duration.zero : ahead;
  }

  Widget _player(bool fullscreen) {
    final aspectRatio = _videoAspectRatio();
    return FVideoPlayer(
      source: FVideoSource.uri(arguments.uri),
      width: arguments.width,
      height: arguments.height,
      initialMuted: arguments.muted,
      autofocus: true,
      controlsAutoHideDuration: const Duration(seconds: 5),
      positionUpdateInterval: const Duration(milliseconds: 200),
      bufferedFractionOverride:
          _progress?.prefixFraction ?? _progress?.fraction,
      showScrubPreview: false,
      showPictureInPictureButton: false,
      showFullscreenButton: false,
      chapters: _chapters,
      frameStepDelegate: (frames) async {
        final controller = _controller;
        if (controller == null) return;
        final stepped = await FvpControllerBridge.stepFrames(
          controller,
          frames,
        );
        if (!stepped) {
          final target =
              controller.value.position + Duration(milliseconds: 33 * frames);
          await controller.seekTo(
            target < Duration.zero ? Duration.zero : target,
          );
        }
      },
      snapshotDelegate: ({width, height}) {
        final controller = _controller;
        if (controller == null) return Future<Uint8List?>.value();
        return FvpControllerBridge.captureFramePng(
          controller,
          width: width,
          height: height,
        );
      },
      onReady: (controller) {
        _handleControllerReady(controller);
        final chapters = FvpControllerBridge.chapters(controller);
        if (mounted && chapters.isNotEmpty) {
          setState(() => _chapters = chapters);
        }
      },
      onPlaybackStateChanged: (state) => _playbackState = state,
      onError: _handlePlaybackError,
      isFullscreen: fullscreen,
      isPictureInPicture: _pictureInPicture,
      onPictureInPictureChanged: _pictureInPictureSupported
          ? _setPictureInPicture
          : null,
      onFullscreenChanged: (value) =>
          unawaited(FVideoDesktopWindows.setCurrentWindowFullscreen(value)),
      chromeBuilder: (context, scope) => MithkaDesktopVideoChrome(
        scope: scope,
        title: arguments.title,
        onClose: () => unawaited(FVideoDesktopWindows.closeCurrentWindow()),
        inspectorVisible: _debuggerVisible,
        onToggleInspector: () =>
            setState(() => _debuggerVisible = !_debuggerVisible),
        aspectRatio: aspectRatio,
        downloadedFraction: _progress?.prefixFraction ?? _progress?.fraction,
        thumbnailProvider: _provideScrubThumbnail,
        shareButton: _messageActions.any
            ? MithkaVideoShareMenuButton(
                controlsVisible: scope.snapshot.controlsVisible,
                onSave: _messageActions.canSave
                    ? () => unawaited(_saveVideo())
                    : null,
                onShare: _messageActions.canShare
                    ? () => unawaited(_shareVideo())
                    : null,
                onOpened: scope.actions.showControls,
              )
            : null,
        pinButton: ValueListenableBuilder<bool>(
          valueListenable: FVideoDesktopWindows.currentWindowAlwaysOnTop,
          builder: (context, pinned, _) => MithkaVideoChromeAction(
            icon: HeroAppIcons.pin,
            label: pinned ? 'Unpin window' : 'Pin window on top',
            onTap: () {
              unawaited(FVideoDesktopWindows.toggleCurrentWindowAlwaysOnTop());
              scope.actions.showControls();
            },
            iconColor: pinned ? const Color(0xFF24DDD9) : Colors.white,
          ),
        ),
        modeButton: _pictureInPictureSupported
            ? MithkaVideoChromeAction(
                icon: HeroAppIcons.pictureInPicture,
                label: AppStrings.t(AppStringKeys.videoPlayerPictureInPicture),
                onTap: () => unawaited(_setPictureInPicture(true)),
                enabled: !_pictureInPictureBusy,
              )
            : null,
        fullscreenButton: MithkaVideoChromeAction(
          icon: HeroAppIcons.expand,
          label: AppStrings.t(
            fullscreen
                ? AppStringKeys.videoPlayerExitFullscreen
                : AppStringKeys.videoPlayerFullscreen,
          ),
          onTap: () => unawaited(
            FVideoDesktopWindows.setCurrentWindowFullscreen(!fullscreen),
          ),
        ),
        topInset: Platform.isMacOS ? 28 : 0,
      ),
    );
  }

  double _videoAspectRatio() {
    final width = arguments.width;
    final height = arguments.height;
    if (width != null && height != null && width > 0 && height > 0) {
      return width / height;
    }
    final value = _controller?.value;
    if (value != null && value.aspectRatio.isFinite && value.aspectRatio > 0) {
      return value.aspectRatio;
    }
    return 16 / 9;
  }

  Future<Uint8List?> _provideScrubThumbnail(Duration position) {
    final maxWidth = _videoAspectRatio() >= 1 ? 320 : 240;
    return _thumbnailCache.resolve(
      FVideoThumbnailRequest(
        source: FVideoSource.uri(arguments.uri),
        position: position,
        maxWidth: maxWidth,
        quality: 70,
      ),
    );
  }
}
