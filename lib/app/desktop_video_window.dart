import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:f_videoplayer/f_videoplayer.dart';
import 'package:f_videoplayer_pip/f_video_picture_in_picture.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:video_player/video_player.dart';

import '../chat/video_player_view.dart';
import '../chat/video_stream_debugger.dart';
import '../components/app_icons.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_image_loader.dart';
import 'desktop_media_window_registry.dart';
import 'video_split_controller.dart';

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
    return TdFileProgress(
      fileId: fileId,
      downloaded: downloaded.clamp(0, total),
      prefixDownloaded: prefix.clamp(0, total),
      total: total,
      isActive: value['is_active'] == true,
      isCompleted: value['is_completed'] == true,
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

  Future<bool> open(VideoSplitSession session, {bool muted = false}) async {
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
          return releaseResources();
        },
      );
      if (windowId == null) throw StateError('Window creation failed');
      openedWindowId = windowId;
      handedOffToWindow = true;
      return true;
    } catch (_) {
      return false;
    } finally {
      _windows.finishOpening(mediaKey, windowId: openedWindowId);
      if (!handedOffToWindow) await releaseResources();
    }
  }
}

class DesktopVideoWindowApp extends StatelessWidget {
  const DesktopVideoWindowApp({super.key, required this.arguments});

  final DesktopVideoWindowArguments arguments;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: arguments.title,
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
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

class _DesktopVideoWindowPlayer extends StatefulWidget {
  const _DesktopVideoWindowPlayer({required this.arguments});

  final DesktopVideoWindowArguments arguments;

  @override
  State<_DesktopVideoWindowPlayer> createState() =>
      _DesktopVideoWindowPlayerState();
}

class _DesktopVideoWindowPlayerState extends State<_DesktopVideoWindowPlayer> {
  VideoPlayerController? _controller;
  final HttpClient _progressClient = HttpClient();
  final List<String> _debugEvents = <String>[];
  Timer? _progressTimer;
  TdFileProgress? _progress;
  bool _progressRequestInFlight = false;
  bool _debuggerVisible = false;
  bool _debugRecording = false;
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
      setState(() {
        _progress = next;
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
    controller.addListener(_handleControllerChanged);
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
    if (!_debuggerVisible || controller == null) return player;
    return LayoutBuilder(
      builder: (context, constraints) {
        final debugHeight = math
            .min(500.0, math.max(280.0, constraints.maxHeight * 0.54))
            .toDouble();
        final playerHeight = math
            .min(
              constraints.maxHeight,
              math.max(180.0, constraints.maxHeight - debugHeight - 8),
            )
            .toDouble();
        final actualDebugHeight = constraints.maxHeight - playerHeight - 8;
        if (actualDebugHeight < 180) {
          return Stack(
            children: [
              Positioned.fill(child: player),
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                height: math
                    .min(500.0, math.max(1.0, constraints.maxHeight - 16))
                    .toDouble(),
                child: _inspector(controller),
              ),
            ],
          );
        }
        return Column(
          children: [
            SizedBox(height: playerHeight, child: player),
            const SizedBox(height: 8),
            SizedBox(height: actualDebugHeight, child: _inspector(controller)),
          ],
        );
      },
    );
  }

  Widget _inspector(VideoPlayerController controller) => VideoStreamDebugger(
    key: const ValueKey('desktop-video-stream-inspector'),
    progress: _progress,
    position: controller.value.position,
    duration: controller.value.duration,
    events: List<String>.unmodifiable(_debugEvents),
    isLive: _progress?.isActive == true || controller.value.isPlaying,
    isRecording: _debugRecording,
    onRecordingChanged: (recording) {
      if (!mounted) return;
      setState(() {
        _debugRecording = recording;
        _recordDebugEvent(
          recording ? 'recording started' : 'recording stopped',
        );
      });
    },
    onClear: () => setState(_debugEvents.clear),
    onExport: _exportDebuggerSnapshot,
    onClose: () => setState(() => _debuggerVisible = false),
  );

  Future<void> _exportDebuggerSnapshot() async {
    final progress = _progress;
    final controller = _controller;
    await Clipboard.setData(
      ClipboardData(
        text: [
          'Stream Inspector',
          'downloaded: ${progress?.downloaded ?? 0} / ${progress?.total ?? 0}',
          'prefix: ${progress?.prefixDownloaded ?? 0}',
          'position_ms: ${controller?.value.position.inMilliseconds ?? 0}',
          'duration_ms: ${controller?.value.duration.inMilliseconds ?? 0}',
          'events:',
          ..._debugEvents,
        ].join('\n'),
      ),
    );
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
      onReady: _handleControllerReady,
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
        modeButton: _pictureInPictureSupported
            ? MithkaVideoChromeAction(
                icon: HeroAppIcons.pictureInPicture,
                label: 'Picture in picture',
                onTap: () => unawaited(_setPictureInPicture(true)),
                enabled: !_pictureInPictureBusy,
              )
            : null,
        fullscreenButton: MithkaVideoChromeAction(
          icon: HeroAppIcons.expand,
          label: fullscreen ? 'Exit fullscreen' : 'Fullscreen',
          onTap: () => unawaited(
            FVideoDesktopWindows.setCurrentWindowFullscreen(!fullscreen),
          ),
        ),
        qualityLabel: _videoQualityLabel(),
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
    return FVideoThumbnail.generateRequest(
      FVideoThumbnailRequest(
        source: FVideoSource.uri(arguments.uri),
        position: position,
        maxWidth: maxWidth,
        quality: 70,
      ),
    );
  }

  String _videoQualityLabel() {
    final width = arguments.width;
    final height = arguments.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return '';
    }
    final shortEdge = width < height ? width : height;
    if (shortEdge >= 2160) return '4K';
    if (shortEdge >= 1440) return '1440p';
    if (shortEdge >= 1080) return '1080p';
    if (shortEdge >= 720) return '720p';
    return '${shortEdge}p';
  }
}
