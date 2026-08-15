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

import 'package:f_videoplayer/f_videoplayer.dart';
import 'package:f_videoplayer_pip/f_video_picture_in_picture.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fvp/fvp.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../app/app_navigator.dart';
import '../app/video_split_controller.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../media/video_view_compatibility.dart';
import '../platform/player_brightness.dart';
import '../platform/player_system_volume.dart';
import '../platform/screen_wakelock.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'chat_picker_view.dart';
import 'forward_options.dart';
import 'media_library_saver.dart';
import 'td_video_stream_server.dart';
import 'video_playback_preferences.dart';
import 'video_playback_queue.dart';
import 'video_stream_debugger.dart';

export 'td_video_stream_server.dart';

typedef VideoPictureInPictureRestoreCallback =
    FutureOr<bool> Function(FVideoPictureInPictureSnapshot snapshot);

enum VideoPlayerPresentation { fullscreen, embedded, pictureInPicture }

enum VideoDisplayMode { fullscreen, pictureInPicture, split }

/// Restores a native PiP handoff into the app-level navigator.
///
/// Native iOS invokes this only after the user selects PiP's restore action.
/// Returning true tells AVKit that the matching player route was scheduled.
@visibleForTesting
Future<bool> restoreVideoPlaybackFromPictureInPicture({
  required VideoPlaybackQueue queue,
  required FVideoPictureInPictureSnapshot snapshot,
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
      initialVolume: snapshot.volume,
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

/// Whether the host should add its configurable touch-style pan gestures.
///
/// Desktop interaction stays package-owned: keyboard shortcuts, pointer-wheel
/// volume, taps, and fullscreen requests are all handled by [FVideoPlayer].
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

class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({
    super.key,
    required this.video,
    this.accountSlot,
    this.thumb,
    this.title = '',
    this.width,
    this.height,
    this.presentation = VideoPlayerPresentation.fullscreen,
    this.onClose,
    this.compactControls = false,
    this.sourceChatId,
    this.messageId,
    this.currentMode = VideoDisplayMode.fullscreen,
    this.onSwitchMode,
    this.onVolumeChanged,
    this.initialVolume = 1,
    this.initialMuted = false,
    this.initialPlaying = true,
    this.initialSpeed = 1,
    this.initialPosition,
    this.previousVideo,
    this.nextVideo,
    this.onNavigate,
    this.onFVideoPictureInPictureRestore,
    this.onToggleFullscreen,
    this.streamQuery,
  });

  final TdFileRef video;
  final int? accountSlot;
  final TdFileRef? thumb;
  final String title;
  final int? width;
  final int? height;
  final VideoPlayerPresentation presentation;
  final VoidCallback? onClose;
  final bool compactControls;
  final int? sourceChatId;
  final int? messageId;
  final VideoDisplayMode currentMode;
  final ValueChanged<VideoDisplayMode>? onSwitchMode;
  final ValueChanged<double>? onVolumeChanged;
  final double initialVolume;
  final bool initialMuted;
  final bool initialPlaying;
  final double initialSpeed;
  final Duration? initialPosition;
  final VideoPlaybackItem? previousVideo;
  final VideoPlaybackItem? nextVideo;
  final ValueChanged<int>? onNavigate;
  final VideoPictureInPictureRestoreCallback? onFVideoPictureInPictureRestore;

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
    this.onVolumeChanged,
    this.initialVolume = 1,
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
  final ValueChanged<double>? onVolumeChanged;
  final double initialVolume;
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
  late double _lastAudibleVolume;
  late bool _muted;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialVolume.isFinite
        ? widget.initialVolume.clamp(0.0, 1.0).toDouble()
        : 1.0;
    _lastAudibleVolume = initial > 0.01 ? initial : 1.0;
    _muted = widget.initialMuted || initial <= 0.01;
  }

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

  void _handleVolumeChanged(double volume) {
    final normalized = volume.isFinite
        ? volume.clamp(0.0, 1.0).toDouble()
        : 0.0;
    _muted = normalized <= 0.01;
    if (!_muted) _lastAudibleVolume = normalized;
    widget.onVolumeChanged?.call(normalized);
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
      title: item.title,
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
      onVolumeChanged: _handleVolumeChanged,
      initialVolume: _lastAudibleVolume,
      initialMuted: _muted,
      initialPlaying: _initialPlaying,
      initialSpeed: widget.initialSpeed,
      initialPosition: _initialPosition,
      previousVideo: _queue.previous,
      nextVideo: _queue.next,
      onNavigate: _navigate,
      streamQuery: widget.streamQuery,
      onFVideoPictureInPictureRestore: (snapshot) =>
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
  bool _moreMenuVisible = false;
  bool _modeMenuVisible = false;
  StreamSubscription<TdFileProgress>? _progressSub;
  Timer? _progressUiTimer;
  TdFileProgress? _progress;
  double _speed = 1;
  double _volume = 1;
  double _lastAudibleVolume = 1;
  int _volumeControlRequestGeneration = 0;
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
  FVideoActions? _reusablePlayerActions;
  bool _debuggerVisible = false;
  bool _debugRecording = false;
  final List<String> _debugEvents = <String>[];
  int _lastDebugDownloaded = -1;
  int _lastDebugPrefixDownloaded = -1;
  int _lastDebugTotal = -1;
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
  final List<FocusNode> _moreMenuFocusNodes = List<FocusNode>.generate(
    4,
    (index) => FocusNode(debugLabel: 'video-more-menu-action-$index'),
  );
  final Map<VideoDisplayMode, FocusNode> _modeMenuFocusNodes = {
    for (final mode in VideoDisplayMode.values)
      mode: FocusNode(debugLabel: 'video-mode-menu-${mode.name}'),
  };
  final LayerLink _modeButtonLink = LayerLink();
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

  double get _controllerGainForCurrentVolume =>
      _usesAndroidSystemMediaVolume && _volume > 0.01 ? 1.0 : _volume;

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
    final initialVolume = widget.initialVolume.isFinite
        ? widget.initialVolume.clamp(0.0, 1.0).toDouble()
        : 1.0;
    _lastAudibleVolume = initialVolume > 0.01 ? initialVolume : 1;
    _volume = widget.initialMuted ? 0 : initialVolume;
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

  void _recordDebugProgress(TdFileProgress progress) {
    if (progress.downloaded == _lastDebugDownloaded &&
        progress.prefixDownloaded == _lastDebugPrefixDownloaded &&
        progress.total == _lastDebugTotal) {
      return;
    }
    _lastDebugDownloaded = progress.downloaded;
    _lastDebugPrefixDownloaded = progress.prefixDownloaded;
    _lastDebugTotal = progress.total;
    _recordDebugEvent(
      '${_debugTimestamp()}  download ${_debugBytes(progress.downloaded)}'
      ' / ${_debugBytes(progress.total)}',
    );
  }

  void _recordDebugEvent(String event) {
    _debugEvents.add(event);
    if (_debugEvents.length > 80) {
      _debugEvents.removeRange(0, _debugEvents.length - 80);
    }
  }

  void _clearDebuggerEvents() {
    if (mounted) setState(_debugEvents.clear);
  }

  String _debugTimestamp() {
    final now = DateTime.now();
    return '${now.minute.toString().padLeft(2, '0')}'
        ':${now.second.toString().padLeft(2, '0')}';
  }

  String _debugBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _load({Duration? resumeOverride, bool? playOverride}) async {
    final preferredViewType = preferredCompatibleVideoViewType;
    await _progressSub?.cancel();
    _progressSub = TdFileCenter.shared
        .progress(widget.video.id, accountSlot: widget.accountSlot)
        .listen((progress) {
          if (!mounted) return;
          _progress = progress;
          _recordDebugProgress(progress);
          _progressUiTimer ??= Timer(const Duration(milliseconds: 250), () {
            _progressUiTimer = null;
            if (mounted) setState(() {});
          });
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
      await c.setVolume(_controllerGainForCurrentVolume);
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
    _recordDebugEvent(
      '${_debugTimestamp()}  controller ready  ${_fmt(c.value.duration)}',
    );
    setState(() => _controller = c);
    if (_usesAndroidSystemMediaVolume) {
      unawaited(_syncAndroidSystemVolume(c));
    }
    _updateWakelock();
    unawaited(_refreshFVideoPictureInPictureSupport());
    return true;
  }

  void _handleReusablePlayerError(FVideoPlayerError error) {
    _recoverAfterStreamFailure(error, requireControllerError: true);
  }

  void _handleReusablePlayerEnded() {
    if (_completionHandled) return;
    _completionHandled = true;
    unawaited(_handlePlaybackCompleted());
  }

  void _handleReusablePlaybackStateChanged(FVideoPlaybackState state) {
    if (state != FVideoPlaybackState.completed && _completionHandled) {
      _completionHandled = false;
    }
    if (state == FVideoPlaybackState.playing) {
      _lastKnownPlaybackWasPlaying = true;
    } else if (state == FVideoPlaybackState.paused ||
        state == FVideoPlaybackState.completed) {
      _lastKnownPlaybackWasPlaying = false;
    }
  }

  void _handleReusableVolumeChanged(double volume) {
    final normalized = volume.isFinite
        ? volume.clamp(0.0, 1.0).toDouble()
        : 0.0;
    if (normalized > 0.01) _lastAudibleVolume = normalized;
    if (mounted && (_volume - normalized).abs() > 0.001) {
      setState(() => _volume = normalized);
    }
    widget.onVolumeChanged?.call(normalized);
  }

  Future<double> _requestAndroidSystemVolume(double requestedVolume) async {
    final request = ++_volumeControlRequestGeneration;
    final normalized = requestedVolume.clamp(0.0, 1.0).toDouble();
    final current = await PlayerSystemVolume.setFraction(normalized);
    final controller = _controller;
    if (!mounted || request != _volumeControlRequestGeneration) {
      return _volume;
    }
    if (current == null) {
      await controller?.setVolume(normalized);
      if (!mounted ||
          request != _volumeControlRequestGeneration ||
          _controller != controller) {
        return _volume;
      }
      return normalized;
    }
    final actual = current.fraction;
    if (controller != null &&
        actual > 0.01 &&
        (controller.value.volume - 1).abs() > 0.001) {
      await controller.setVolume(1);
      if (!mounted ||
          request != _volumeControlRequestGeneration ||
          _controller != controller) {
        return _volume;
      }
    }
    return actual;
  }

  Future<void> _handleReusablePictureInPictureChanged(bool requested) async {
    if (requested) {
      await _enterPictureInPicture();
      return;
    }
    if (_systemPiPActive) {
      await FVideoPictureInPicture.stop();
    }
    if (mounted && widget.currentMode == VideoDisplayMode.pictureInPicture) {
      widget.onSwitchMode?.call(VideoDisplayMode.fullscreen);
    }
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

  // TDLib recovery, resume persistence, and native PiP remain host-owned. The
  // reusable player independently refreshes its chrome at a throttled cadence.
  void _onTick() {
    final value = _controller?.value;
    if (value != null && !value.hasError) {
      if (!value.isBuffering) {
        _lastKnownPlaybackWasPlaying = value.isPlaying;
      }
      _lastKnownPlaybackPosition = value.position;
    }
    _syncStreamStallRecovery(value);
    if (value != null) {
      _speed = value.playbackSpeed;
    }
    _storePlaybackPositionIfNeeded();
    _syncFVideoPictureInPictureIfNeeded();
    _updateWakelock();
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

  void _syncFVideoPictureInPictureIfNeeded() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return;
    }
    if (_usesAndroidFVideoPictureInPicture &&
        _systemPiPSupported &&
        c.value.isPlaying &&
        _systemPiPId == null &&
        _systemPiPPrepareOperation == null) {
      unawaited(_prepareFVideoPictureInPicture());
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
      FVideoPictureInPicture.updatePrepared(
        id: id,
        position: c.value.position,
        speed: _speed,
        volume: _pictureInPictureVolume,
        muted: muted,
        playing: playing,
        videoSize: c.value.size,
        sourceRect: sourceRect,
        playLabel: AppStringKeys.musicPlayerPlay.l10n(context),
        pauseLabel: AppStringKeys.musicPlayerPause.l10n(context),
      ),
    );
  }

  bool get _usesAndroidFVideoPictureInPicture =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  double get _pictureInPictureVolume =>
      (_volume > 0.01 ? _volume : _lastAudibleVolume)
          .clamp(0.0, 1.0)
          .toDouble();

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

  void _handleFVideoPictureInPictureEntered(FVideoPictureInPictureSnapshot _) {
    if (!mounted || _systemPiPActive) return;
    setState(() {
      _systemPiPActive = true;
      _moreMenuVisible = false;
      _modeMenuVisible = false;
    });
  }

  void _handleFVideoPictureInPictureRestored(FVideoPictureInPictureSnapshot _) {
    if (!mounted || !_systemPiPActive) return;
    _lastSystemPiPSourceRect = null;
    setState(() => _systemPiPActive = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reusablePlayerActions?.showControls();
    });
  }

  Future<void> _handleFVideoPictureInPictureAction(
    FVideoPictureInPictureAction action,
  ) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    switch (action) {
      case FVideoPictureInPictureAction.play:
        await controller.play();
        return;
      case FVideoPictureInPictureAction.pause:
        await controller.pause();
        return;
    }
  }

  Future<void> _handlePlaybackCompleted() async {
    await _storePlaybackPosition(force: true);
    if (!mounted) return;
    switch (_completionAction) {
      case VideoCompletionAction.prompt:
        _reusablePlayerActions?.hideControls();
        setState(() => _showCompletionPrompt = true);
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
    setState(() => _showCompletionPrompt = false);
    _reusablePlayerActions?.showControls();
  }

  void _playNextVideo() {
    if (widget.nextVideo == null || widget.onNavigate == null) return;
    widget.onNavigate!(1);
  }

  Future<void> _syncAndroidSystemVolume(
    VideoPlayerController controller,
  ) async {
    final request = _volumeControlRequestGeneration;
    final current = await PlayerSystemVolume.current();
    if (!mounted ||
        request != _volumeControlRequestGeneration ||
        _controller != controller ||
        current == null) {
      return;
    }
    final actual = current.fraction;
    if (actual > 0.01) _lastAudibleVolume = actual;
    // Preserve an explicitly muted playback snapshot while remembering the
    // system level that the unmute action should restore.
    if (_volume <= 0.01) return;
    await controller.setVolume(1);
    if (!mounted ||
        request != _volumeControlRequestGeneration ||
        _controller != controller) {
      return;
    }
    setState(() => _volume = actual);
    widget.onVolumeChanged?.call(actual);
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

  Future<bool> _restoreFVideoPictureInPicture(
    FVideoPictureInPictureSnapshot snapshot,
  ) {
    final c = _controller;
    final duration = c?.value.duration ?? Duration.zero;
    final normalized = _clampPlaybackPosition(snapshot.position, duration);
    final normalizedSnapshot = FVideoPictureInPictureSnapshot(
      position: normalized,
      playing: snapshot.playing,
      speed: snapshot.speed,
      volume: snapshot.volume,
      muted: snapshot.muted,
    );
    unawaited(_storeResumePosition(normalized, duration));
    final callback = widget.onFVideoPictureInPictureRestore;
    if (callback != null) {
      return Future<bool>.value(callback(normalizedSnapshot));
    }
    return restoreVideoPlaybackFromPictureInPicture(
      queue: _pictureInPictureRestoreQueue(),
      snapshot: normalizedSnapshot,
      streamQuery: widget.streamQuery,
    );
  }

  Future<bool> _startFVideoPictureInPicture() {
    final pending = _systemPiPStartOperation;
    if (pending != null) return pending;
    late final Future<bool> tracked;
    tracked =
        (() async {
          await _prepareFVideoPictureInPicture();
          return _performFVideoPictureInPictureStart();
        })().whenComplete(() {
          if (identical(_systemPiPStartOperation, tracked)) {
            _systemPiPStartOperation = null;
          }
        });
    _systemPiPStartOperation = tracked;
    return tracked;
  }

  Future<bool> _performFVideoPictureInPictureStart() async {
    final c = _controller;
    final uri = _systemPiPSourceUri();
    if (c == null || !c.value.isInitialized || uri == null) {
      return false;
    }
    if (!await _isFVideoPictureInPictureSupported()) {
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
      started = await FVideoPictureInPicture.startPrepared(
        id: id,
        position: c.value.position,
        speed: _speed,
        volume: _pictureInPictureVolume,
        muted: _volume <= 0.01,
        playing: c.value.isPlaying,
        videoSize: c.value.size,
        sourceRect: sourceRect,
        playLabel: playLabel,
        pauseLabel: pauseLabel,
      );
      if (!mounted) {
        await FVideoPictureInPicture.cancelPrepared(id);
        return false;
      }
    }
    if (!started) {
      if (id != null) {
        await FVideoPictureInPicture.cancelPrepared(id);
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
      started = await FVideoPictureInPicture.start(
        id: handoffId,
        uri: uri,
        position: c.value.position,
        speed: _speed,
        volume: _pictureInPictureVolume,
        muted: _volume <= 0.01,
        playing: c.value.isPlaying,
        videoSize: c.value.size,
        sourceRect: sourceRect,
        playLabel: playLabel,
        pauseLabel: pauseLabel,
        playerId: c.fvpPlayerId,
        onEntered: _handleFVideoPictureInPictureEntered,
        onRestored: _handleFVideoPictureInPictureRestored,
        onActionRequested: _handleFVideoPictureInPictureAction,
        onRestoreRequested: (position) async {
          final accepted = await _restoreFVideoPictureInPicture(position);
          restoreAccepted = accepted;
          return accepted;
        },
        onStop: (finalPosition) async {
          if (_usesAndroidFVideoPictureInPicture && mounted) {
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
          if (FVideoPictureInPicture.usesActivePlayer(handoffId)) {
            await c.dispose();
          }
          await server?.close();
          if (shouldCancelOnStop && !restoreAccepted) {
            await _cancelIncompleteDownload();
          }
        },
      );
      if (!mounted) {
        await FVideoPictureInPicture.cancelPrepared(id);
        return false;
      }
    }
    if (!started) {
      if (mounted) {
        showToast(context, AppStringKeys.videoPlayerPictureInPictureFailed);
      }
      return false;
    }
    if (FVideoPictureInPicture.keepsFlutterPlayerInActivity) {
      // Android PiP hosts this Activity. Keep the Flutter route and its video
      // texture mounted so the system captures the active player, not chat.
      _handleFVideoPictureInPictureEntered(
        FVideoPictureInPictureSnapshot(
          position: c.value.position,
          playing: c.value.isPlaying,
          speed: _speed,
          volume: _pictureInPictureVolume,
          muted: _volume <= 0.01,
        ),
      );
      return true;
    }
    _systemPiPUsesActivePlayer =
        id != null && FVideoPictureInPicture.usesActivePlayer(id);
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

  Future<void> _prepareFVideoPictureInPicture() {
    final pending = _systemPiPPrepareOperation;
    if (pending != null) return pending;
    late final Future<void> tracked;
    tracked = _performFVideoPictureInPicturePreparation().whenComplete(() {
      if (identical(_systemPiPPrepareOperation, tracked)) {
        _systemPiPPrepareOperation = null;
      }
    });
    _systemPiPPrepareOperation = tracked;
    return tracked;
  }

  Future<void> _performFVideoPictureInPicturePreparation() async {
    if (_systemPiPPrepared || _systemPiPId != null) {
      return;
    }
    final c = _controller;
    final uri = _systemPiPSourceUri();
    if (c == null || !c.value.isInitialized || uri == null) return;
    if (!await _isFVideoPictureInPictureSupported()) return;
    if (!mounted) return;

    final server = _streamServer;
    final shouldCancelOnStop =
        !_openedCompletedLocalFile && _progress?.isCompleted != true;
    final id = '${widget.video.id}-${DateTime.now().microsecondsSinceEpoch}';
    _systemPiPId = id;
    final sourceRect = _systemPictureInPictureSourceRect(c);
    if (sourceRect != null) _lastSystemPiPSourceRect = sourceRect;
    var restoreAccepted = false;
    final prepared = await FVideoPictureInPicture.prepare(
      id: id,
      uri: uri,
      position: c.value.position,
      speed: _speed,
      volume: _pictureInPictureVolume,
      muted: _volume <= 0.01,
      playing: c.value.isPlaying,
      videoSize: c.value.size,
      sourceRect: sourceRect,
      playLabel: AppStringKeys.musicPlayerPlay.l10n(context),
      pauseLabel: AppStringKeys.musicPlayerPause.l10n(context),
      playerId: c.fvpPlayerId,
      onEntered: _handleFVideoPictureInPictureEntered,
      onRestored: _handleFVideoPictureInPictureRestored,
      onActionRequested: _handleFVideoPictureInPictureAction,
      onRestoreRequested: (position) async {
        final accepted = await _restoreFVideoPictureInPicture(position);
        restoreAccepted = accepted;
        return accepted;
      },
      onStop: (finalPosition) async {
        if (_usesAndroidFVideoPictureInPicture && mounted) {
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
        if (FVideoPictureInPicture.usesActivePlayer(id)) {
          await c.dispose();
        }
        await server?.close();
        if (shouldCancelOnStop && !restoreAccepted) {
          await _cancelIncompleteDownload();
        }
      },
    );
    if (!mounted || _systemPiPId != id) {
      if (prepared) unawaited(FVideoPictureInPicture.cancelPrepared(id));
      return;
    }
    if (prepared) {
      _systemPiPPrepared = true;
      _syncFVideoPictureInPictureIfNeeded();
    } else {
      _systemPiPId = null;
    }
  }

  Future<void> _refreshFVideoPictureInPictureSupport() async {
    final supported = await _isFVideoPictureInPictureSupported();
    if (supported &&
        mounted &&
        _usesAndroidFVideoPictureInPicture &&
        (_controller?.value.isPlaying ?? false)) {
      await _prepareFVideoPictureInPicture();
    }
  }

  Future<bool> _isFVideoPictureInPictureSupported() async {
    if (_systemPiPSupported) return true;
    final supported = await FVideoPictureInPicture.isSupported();
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
    _progressUiTimer?.cancel();
    _streamStallTimer?.cancel();
    _reusablePlayerActions = null;
    _completionPromptFocusNode.dispose();
    _moreButtonFocusNode.dispose();
    _modeButtonFocusNode.dispose();
    for (final focusNode in _moreMenuFocusNodes) {
      focusNode.dispose();
    }
    for (final focusNode in _modeMenuFocusNodes.values) {
      focusNode.dispose();
    }
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
      await FVideoPictureInPicture.cancelPrepared(preparedPiPId);
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
    return ColoredBox(
      color: Colors.black,
      child: _playbackSurface(ready ? c : null),
    );
  }

  Widget _playbackSurface(VideoPlayerController? controller) {
    final player = controller == null
        ? _loadingState()
        : _reusablePlayer(controller);
    if (!_debuggerVisible ||
        widget.presentation != VideoPlayerPresentation.fullscreen ||
        controller == null) {
      return player;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final debugHeight = math
            .min(500.0, math.max(280.0, constraints.maxHeight * 0.54))
            .toDouble();
        final playerHeight = math
            .max(180.0, constraints.maxHeight - debugHeight - 8)
            .toDouble();
        final actualDebugHeight = constraints.maxHeight - playerHeight - 8;
        return Column(
          children: [
            SizedBox(height: playerHeight, child: player),
            const SizedBox(height: 8),
            SizedBox(
              height: math.max(1, actualDebugHeight).toDouble(),
              child: VideoStreamDebugger(
                progress: _progress,
                position: controller.value.position,
                duration: controller.value.duration,
                events: List<String>.unmodifiable(_debugEvents),
                isLive: _streamServer != null || controller.value.isPlaying,
                isRecording: _debugRecording,
                onRecordingChanged: (recording) {
                  if (!mounted) return;
                  setState(() => _debugRecording = recording);
                  _recordDebugEvent(
                    '${_debugTimestamp()}  recording ${recording ? 'started' : 'stopped'}',
                  );
                },
                onClear: _clearDebuggerEvents,
                onExport: _exportDebuggerSnapshot,
                onClose: () {
                  if (mounted) setState(() => _debuggerVisible = false);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportDebuggerSnapshot() async {
    final progress = _progress;
    final total = progress?.total ?? 0;
    final downloaded = progress?.downloaded ?? 0;
    await Clipboard.setData(
      ClipboardData(
        text: [
          'Stream Inspector',
          'video: ${widget.video.id}',
          'downloaded: $downloaded / $total',
          'prefix: ${progress?.prefixDownloaded ?? 0}',
          'events:',
          ..._debugEvents,
        ].join('\n'),
      ),
    );
  }

  Widget _reusablePlayer(VideoPlayerController controller) {
    return FVideoPlayer(
      key: ValueKey('video-${widget.video.id}-${widget.presentation.name}'),
      source: _reusablePlayerSource(),
      controller: controller,
      width: widget.width,
      height: widget.height,
      autoplay: false,
      autofocus: _isDesktopPlatform,
      initialVolume: _controllerGainForCurrentVolume,
      initialPlaybackSpeed: _speed,
      onClose: _close,
      onToggleFullscreen: widget.onToggleFullscreen,
      onPictureInPictureChanged: _canOfferPictureInPicture
          ? _handleReusablePictureInPictureChanged
          : null,
      showPictureInPictureButton: false,
      showFullscreenButton: false,
      onPrevious: widget.previousVideo == null
          ? null
          : () => widget.onNavigate?.call(-1),
      onNext: widget.nextVideo == null
          ? null
          : () => widget.onNavigate?.call(1),
      onEnded: _handleReusablePlayerEnded,
      onPlaybackStateChanged: _handleReusablePlaybackStateChanged,
      onVolumeChanged: _handleReusableVolumeChanged,
      lifecycleBehavior: FVideoLifecycleBehavior.delegateToController,
      controlsAutoHideDuration: const Duration(seconds: 5),
      positionUpdateInterval: const Duration(milliseconds: 200),
      showScrubPreview:
          widget.presentation != VideoPlayerPresentation.fullscreen,
      enableKeyboardShortcuts:
          !_showCompletionPrompt && !_moreMenuVisible && !_modeMenuVisible,
      enableScrollVolume: _isDesktopPlatform,
      thumbnailProvider: _provideScrubThumbnail,
      bufferedFractionOverride: _downloadedFraction,
      externalVolume: _usesAndroidSystemMediaVolume ? _volume : null,
      volumeDelegate: _usesAndroidSystemMediaVolume
          ? _requestAndroidSystemVolume
          : null,
      labels: _playerLabels,
      isFullscreen: widget.presentation == VideoPlayerPresentation.fullscreen,
      isPictureInPicture:
          widget.presentation == VideoPlayerPresentation.pictureInPicture ||
          _systemPiPActive,
      controlsEnabled: !_showCompletionPrompt && !_systemPiPActive,
      onError: _handleReusablePlayerError,
      loadingBuilder: (_) => _loadingState(),
      surfaceInteractionBuilder: _playerSurfaceInteraction,
      chromeBuilder: widget.presentation == VideoPlayerPresentation.fullscreen
          ? _playerChrome
          : null,
      overlayBuilder: _playerOverlay,
      topTrailingBuilder: _playerTopTrailing,
      bottomTrailingBuilder: _playerBottomTrailing,
    );
  }

  double? get _downloadedFraction {
    final value = _progress?.prefixFraction ?? _progress?.fraction;
    return value?.clamp(0.0, 1.0).toDouble();
  }

  Future<Uint8List?> _provideScrubThumbnail(FVideoThumbnailRequest request) {
    final path = _localPath;
    if (!_openedCompletedLocalFile ||
        path == null ||
        path.startsWith('http://') ||
        path.startsWith('https://')) {
      return Future<Uint8List?>.value();
    }
    return FVideoThumbnail.generateRequest(
      FVideoThumbnailRequest(
        source: FVideoSource.file(path),
        position: request.position,
        maxWidth: request.maxWidth,
        quality: request.quality,
      ),
    );
  }

  FVideoPlayerLabels get _playerLabels => FVideoPlayerLabels(
    play: AppStringKeys.musicPlayerPlay.l10n(context),
    pause: AppStringKeys.musicPlayerPause.l10n(context),
    previous: AppStringKeys.videoPlayerPreviousVideo.l10n(context),
    next: AppStringKeys.videoPlayerNextVideo.l10n(context),
    mute: AppStringKeys.callMute.l10n(context),
    unmute: AppStringKeys.chatUnmute.l10n(context),
    fullscreen: AppStringKeys.videoPlayerFullscreen.l10n(context),
    exitFullscreen: AppStringKeys.videoPlayerFullscreen.l10n(context),
    pictureInPicture: AppStringKeys.videoPlayerPictureInPicture.l10n(context),
    exitPictureInPicture: AppStringKeys.videoPlayerFullscreen.l10n(context),
    close: AppStringKeys.musicPlayerClose.l10n(context),
    loading: AppStringKeys.videoPlayerLoading.l10n(context),
    buffering: AppStringKeys.videoPlayerWaitingForFile.l10n(context),
    failed: AppStringKeys.videoPlayerCannotPlay.l10n(context),
    retry: AppStringKeys.callsRetry.l10n(context),
    speed: AppStringKeys.videoPlayerPlaybackSpeed.l10n(context),
    position: AppStringKeys.videoPlaybackSwipeAdjustProgress.l10n(context),
    volume: AppStringKeys.videoPlaybackSwipeAdjustVolume.l10n(context),
  );

  FVideoSource _reusablePlayerSource() {
    final path = _localPath;
    if (path != null &&
        (path.startsWith('http://') || path.startsWith('https://'))) {
      return FVideoSource.network(path);
    }
    if (path != null && path.isNotEmpty) {
      return FVideoSource.file(path);
    }
    throw StateError('An initialized video must have a source');
  }

  Widget _playerChrome(BuildContext context, FVideoChromeScope scope) {
    _reusablePlayerActions = scope.actions;
    final snapshot = scope.snapshot;
    final safePadding = MediaQuery.paddingOf(context);
    return ExcludeFocus(
      excluding: !snapshot.controlsVisible,
      child: ExcludeSemantics(
        excluding: !snapshot.controlsVisible,
        child: IgnorePointer(
          ignoring: !snapshot.controlsVisible,
          child: AnimatedOpacity(
            key: const ValueKey('mithka-video-player-chrome'),
            opacity: snapshot.controlsVisible ? 1 : 0,
            duration: const Duration(milliseconds: 170),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide =
                    MediaQuery.sizeOf(context).width >= 600 &&
                    constraints.maxWidth >= 600;
                final compactQueueNavigation =
                    !wide && MediaQuery.sizeOf(context).width >= 320;
                final title = _videoChromeTitle();
                final subtitle = _videoChromeSubtitle(snapshot.value.duration);
                final metadataAspect = _metadataAspectRatio();
                final controllerAspect = snapshot.value.aspectRatio;
                final aspect =
                    metadataAspect ??
                    (controllerAspect.isFinite && controllerAspect > 0
                        ? controllerAspect
                        : 16 / 9);
                final buffered = math
                    .max(
                      snapshot.value.buffered.isEmpty
                          ? 0.0
                          : snapshot.value.buffered.last.end.inMilliseconds /
                                math.max(
                                  1,
                                  snapshot.value.duration.inMilliseconds,
                                ),
                      _downloadedFraction ?? 0,
                    )
                    .clamp(0.0, 1.0)
                    .toDouble();
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.72),
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.88),
                              ],
                              stops: const [0, 0.46, 1],
                            ),
                          ),
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      top: safePadding.top + 12,
                      start: safePadding.left + 14,
                      end: safePadding.right + 14,
                      child: Row(
                        children: [
                          _playerChromeIconButton(
                            icon: HeroAppIcons.xmark,
                            label: scope.labels.close,
                            onTap: _close,
                            size: 52,
                            iconSize: 27,
                            cornerRadius: 26,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.76),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          _playerChromeIconButton(
                            icon: HeroAppIcons.code,
                            label: 'Stream inspector',
                            onTap: () {
                              setState(
                                () => _debuggerVisible = !_debuggerVisible,
                              );
                              scope.actions.showControls();
                            },
                            size: 44,
                            iconSize: 21,
                            cornerRadius: 22,
                            backgroundColor: _debuggerVisible
                                ? const Color(0xD92C6565)
                                : const Color(0xB82C2C2E),
                          ),
                          const SizedBox(width: 8),
                          _playerChromeIconButton(
                            icon: HeroAppIcons.ellipsisVertical,
                            label: 'More',
                            onTap: _toggleMoreMenu,
                            size: 44,
                            iconSize: 23,
                            cornerRadius: 22,
                            focusNode: _moreButtonFocusNode,
                          ),
                        ],
                      ),
                    ),
                    if (wide && scope.previous != null)
                      PositionedDirectional(
                        start: safePadding.left + 18,
                        top: safePadding.top + 96,
                        bottom: safePadding.bottom + 132,
                        child: Center(
                          child: _MithkaVideoSideButton(
                            icon: HeroAppIcons.chevronLeft,
                            label: scope.labels.previous,
                            onTap: scope.previous!,
                          ),
                        ),
                      ),
                    if (wide && scope.next != null)
                      PositionedDirectional(
                        end: safePadding.right + 18,
                        top: safePadding.top + 96,
                        bottom: safePadding.bottom + 132,
                        child: Center(
                          child: _MithkaVideoSideButton(
                            icon: HeroAppIcons.chevronRight,
                            label: scope.labels.next,
                            onTap: scope.next!,
                          ),
                        ),
                      ),
                    Positioned.fill(
                      top: safePadding.top + 72,
                      bottom: safePadding.bottom + (wide ? 132 : 168),
                      child: Center(
                        child: wide
                            ? _MithkaVideoCenterTransport(
                                value: snapshot.value,
                                scope: scope,
                              )
                            : _MithkaVideoCompactTransport(
                                value: snapshot.value,
                                scope: scope,
                                showQueueNavigation: !compactQueueNavigation,
                              ),
                      ),
                    ),
                    Positioned(
                      left: safePadding.left + (wide ? 28 : 14),
                      right: safePadding.right + (wide ? 28 : 14),
                      bottom: safePadding.bottom + (wide ? 14 : 10),
                      child: _MithkaVideoBottomChrome(
                        scope: scope,
                        wide: wide,
                        buffered: buffered,
                        aspectRatio: aspect,
                        thumbnailProvider: _provideScrubThumbnailAt,
                        compactQueueNavigation: compactQueueNavigation,
                        previousButton:
                            compactQueueNavigation && scope.previous != null
                            ? _MithkaVideoCompactNavButton(
                                icon: HeroAppIcons.chevronLeft,
                                label: scope.labels.previous,
                                onTap: scope.previous!,
                                size: 44,
                              )
                            : null,
                        nextButton: compactQueueNavigation && scope.next != null
                            ? _MithkaVideoCompactNavButton(
                                icon: HeroAppIcons.chevronRight,
                                label: scope.labels.next,
                                onTap: scope.next!,
                                size: 44,
                              )
                            : null,
                        modeButton: _showsDisplayModeButton
                            ? _displayModeButton(size: 44)
                            : null,
                        fullscreenButton:
                            widget.onToggleFullscreen == null ||
                                (widget.onSwitchMode != null && !wide)
                            ? null
                            : _playerChromeIconButton(
                                icon: HeroAppIcons.expand,
                                label: widget.onSwitchMode != null
                                    ? 'Expand player'
                                    : scope.labels.fullscreen,
                                onTap: widget.onToggleFullscreen!,
                                size: 44,
                                iconSize: 20,
                                cornerRadius: 10,
                                backgroundColor: const Color(0x9A1B1D1E),
                                borderColor: Colors.white.withValues(
                                  alpha: 0.26,
                                ),
                              ),
                        qualityLabel: _videoQualityLabel(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _playerChromeIconButton({
    required AppIconData icon,
    required String label,
    required VoidCallback onTap,
    required double size,
    required double iconSize,
    required double cornerRadius,
    Color backgroundColor = const Color(0xB82C2C2E),
    Color? borderColor,
    FocusNode? focusNode,
  }) {
    return _FocusableVideoIconButton(
      icon: icon,
      label: label,
      onPressed: onTap,
      size: Size.square(size),
      iconSize: iconSize,
      backgroundColor: backgroundColor,
      borderColor: borderColor ?? Colors.white.withValues(alpha: 0.15),
      cornerRadius: cornerRadius,
      focusNode: focusNode,
    );
  }

  String _videoChromeTitle() {
    final explicit = widget.title.trim();
    if (explicit.isNotEmpty) return explicit;
    final fileName = widget.video.fileName?.trim() ?? '';
    if (fileName.isNotEmpty) {
      final extension = fileName.lastIndexOf('.');
      return extension > 0 ? fileName.substring(0, extension) : fileName;
    }
    return 'Video';
  }

  String _videoChromeSubtitle(Duration duration) {
    final seconds = math.max(0, duration.inSeconds);
    final unit = seconds == 1 ? 'sec' : 'secs';
    return 'Video  •  $seconds $unit';
  }

  String _videoQualityLabel() {
    final width = widget.width;
    final height = widget.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return '';
    }
    final shortEdge = math.min(width, height);
    if (shortEdge >= 2160) return '4K';
    if (shortEdge >= 1440) return '1440p';
    if (shortEdge >= 1080) return '1080p';
    if (shortEdge >= 720) return '720p';
    return '${shortEdge}p';
  }

  Future<Uint8List?> _provideScrubThumbnailAt(Duration position) {
    final path = _localPath;
    if (!_openedCompletedLocalFile ||
        path == null ||
        path.startsWith('http://') ||
        path.startsWith('https://')) {
      return Future<Uint8List?>.value();
    }
    final controller = _controller;
    final aspect = controller == null
        ? 16 / 9
        : _displayVideoSize(controller).aspectRatio;
    return FVideoThumbnail.generateRequest(
      FVideoThumbnailRequest(
        source: FVideoSource.file(path),
        position: position,
        maxWidth: aspect >= 1 ? 320 : 240,
        quality: 70,
      ),
    );
  }

  Widget _playerSurfaceInteraction(
    BuildContext context,
    FVideoChromeScope scope,
    Widget child,
  ) {
    _reusablePlayerActions = scope.actions;
    final controller = _controller;
    if (!_supportsPlaybackGestures || controller == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanDown: (details) => _gestureOrigin = details.localPosition,
      onPanStart: (details) {
        scope.actions.showControls();
        _startPlaybackGesture(details, controller);
      },
      onPanUpdate: (details) => _updatePlaybackGesture(details, controller),
      onPanEnd: (_) => _finishPlaybackGesture(controller),
      onPanCancel: _cancelPlaybackGesture,
      child: child,
    );
  }

  Widget _playerOverlay(BuildContext context, FVideoChromeScope scope) {
    _reusablePlayerActions = scope.actions;
    if (_systemPiPActive) {
      return const IgnorePointer(child: SizedBox.expand());
    }
    final controller = _controller;
    final overlay = Stack(
      fit: StackFit.expand,
      children: [
        if (_gestureIndicatorReady && controller != null)
          _activeGesture == _PlayerGesture.brightness ||
                  _activeGesture == _PlayerGesture.volume
              ? _sideLevelIndicator()
              : _gestureIndicator(controller),
        if (_showCompletionPrompt) _completionPrompt(),
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
    if (_showCompletionPrompt || _moreMenuVisible || _modeMenuVisible) {
      return Focus(
        canRequestFocus: false,
        onKeyEvent: (node, event) => _handlePlayerMenuKeyEvent(event),
        child: overlay,
      );
    }
    return IgnorePointer(child: overlay);
  }

  KeyEventResult _handlePlayerMenuKeyEvent(KeyEvent event) {
    if (!_moreMenuVisible && !_modeMenuVisible) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_moreMenuVisible) {
        _closeMoreMenu();
      } else {
        _closeModeMenu();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _movePlayerMenuFocus(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _movePlayerMenuFocus(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      _movePlayerMenuFocus(HardwareKeyboard.instance.isShiftPressed ? -1 : 1);
      return KeyEventResult.handled;
    }
    // The focused menu item owns activation. Its inner Shortcuts widget sees
    // these before this ancestor and invokes the corresponding action.
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      return KeyEventResult.ignored;
    }
    // Do not let playback, seeking, volume, or presentation shortcuts run
    // underneath an open application menu.
    return KeyEventResult.handled;
  }

  List<FocusNode> get _visiblePlayerMenuFocusNodes {
    if (_moreMenuVisible) {
      return [
        _moreMenuFocusNodes[0],
        _moreMenuFocusNodes[1],
        _moreMenuFocusNodes[2],
        if (_showsOrientationButton) _moreMenuFocusNodes[3],
      ];
    }
    if (_modeMenuVisible) {
      return [
        for (final mode in _availableDisplayModes) _modeMenuFocusNodes[mode]!,
      ];
    }
    return const [];
  }

  void _movePlayerMenuFocus(int delta) {
    final nodes = _visiblePlayerMenuFocusNodes;
    if (nodes.isEmpty) return;
    final currentIndex = nodes.indexWhere((node) => node.hasFocus);
    final startIndex = currentIndex < 0 ? (delta < 0 ? 0 : -1) : currentIndex;
    final nextIndex = (startIndex + delta) % nodes.length;
    nodes[nextIndex].requestFocus();
  }

  Widget _playerTopTrailing(BuildContext context, FVideoChromeScope scope) {
    _reusablePlayerActions = scope.actions;
    if (widget.presentation != VideoPlayerPresentation.fullscreen) {
      return const SizedBox.shrink();
    }
    return _roundIconButton(
      HeroAppIcons.ellipsisVertical,
      _toggleMoreMenu,
      label: AppStringKeys.momentsMore.l10n(context),
      size: 44,
      focusNode: _moreButtonFocusNode,
    );
  }

  Widget _playerBottomTrailing(BuildContext context, FVideoChromeScope scope) {
    _reusablePlayerActions = scope.actions;
    return _showsDisplayModeButton
        ? _displayModeButton(size: 44)
        : const SizedBox.shrink();
  }

  bool get _supportsPlaybackGestures => videoPlaybackSurfaceUsesPanGestures(
    presentation: widget.presentation,
    platform: defaultTargetPlatform,
    isWeb: kIsWeb,
  );

  bool get _isDesktopPlatform =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.linux ||
        TargetPlatform.macOS ||
        TargetPlatform.windows => true,
        _ => false,
      };

  bool get _gestureIndicatorReady =>
      _activeGesture != null &&
      (_activeGesture != _PlayerGesture.brightness ||
          _gestureBrightnessReady) &&
      (_activeGesture != _PlayerGesture.volume || _gestureVolumeReady);

  void _startPlaybackGesture(
    DragStartDetails details,
    VideoPlayerController controller,
  ) {
    _reusablePlayerActions?.showControls();
    _gestureOrigin ??= details.localPosition;
    _gestureStartValue = _volume;
    _gestureValue = _volume;
    _gestureBrightnessReady = false;
    _gestureVolumeReady = false;
    _gestureUsesSystemVolume = false;
    _gestureVolumeRequestGeneration++;
    _gestureStartPosition = controller.value.position;
    _gestureSeekPosition = _gestureStartPosition;
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
        _volumeControlRequestGeneration++;
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
    } else if (gesture == _PlayerGesture.volume) {
      _volumeControlRequestGeneration++;
      _volume = _gestureValue;
      if (_volume > 0.01) {
        _lastAudibleVolume = _volume;
        if (_gestureUsesSystemVolume && controller.value.volume <= 0.01) {
          unawaited(controller.setVolume(1));
        }
      }
      widget.onVolumeChanged?.call(_volume);
    }
    _cancelPlaybackGesture();
    _reusablePlayerActions?.showControls();
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
        MediaQuery.sizeOf(context).shortestSide < 600 ||
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

  void _toggleMoreMenu() {
    final opening = !_moreMenuVisible;
    setState(() {
      _moreMenuVisible = opening;
      _modeMenuVisible = false;
    });
    if (opening) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _moreMenuVisible) {
          _moreMenuFocusNodes.first.requestFocus();
        }
      });
    }
  }

  void _closeMoreMenu() {
    if (!_moreMenuVisible) return;
    setState(() => _moreMenuVisible = false);
    if (_isDesktopPlatform) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _moreButtonFocusNode.requestFocus();
      });
    }
    _reusablePlayerActions?.showControls();
  }

  void _runMoreMenuAction(VoidCallback action) {
    _closeMoreMenu();
    action();
  }

  void _dismissMenusAndControls({FVideoChromeScope? scope}) {
    FocusManager.instance.primaryFocus?.unfocus();
    final hideReusableControls = scope?.snapshot.controlsVisible == true;
    setState(() {
      _moreMenuVisible = false;
      _modeMenuVisible = false;
    });
    if (hideReusableControls) scope!.actions.toggleControls();
  }

  Widget _moreMenuOverlay({required VoidCallback onTapOutside}) {
    final media = MediaQuery.of(context);
    final phoneFullscreen = media.size.shortestSide < 600;
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
                                    focusNode: _moreMenuFocusNodes[0],
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
                                    focusNode: _moreMenuFocusNodes[1],
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
                                    focusNode: _moreMenuFocusNodes[2],
                                    onPressed: () => _runMoreMenuAction(
                                      () => unawaited(_forwardVideo()),
                                    ),
                                  ),
                                ),
                                if (_showsOrientationButton) ...[
                                  const _VideoMenuSeparator(),
                                  KeyedSubtree(
                                    key: const ValueKey(
                                      'video-more-orientation',
                                    ),
                                    child: _FocusableVideoMenuItem(
                                      icon: HeroAppIcons.rotate,
                                      focusNode: _moreMenuFocusNodes[3],
                                      label:
                                          (_landscapePlayback
                                                  ? AppStringKeys
                                                        .videoPlayerUseSystemOrientation
                                                  : AppStringKeys
                                                        .videoPlayerPlayHorizontally)
                                              .l10n(context),
                                      onPressed: () => _runMoreMenuAction(
                                        () => unawaited(
                                          _toggleVideoOrientation(),
                                        ),
                                      ),
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
            ),
          ),
        ],
      ),
    );
  }

  void _toggleModeMenu() {
    final opening = !_modeMenuVisible;
    setState(() {
      _modeMenuVisible = opening;
      _moreMenuVisible = false;
    });
    if (opening) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_modeMenuVisible) return;
        final modes = _availableDisplayModes;
        if (modes.isEmpty) return;
        final initialMode = modes.contains(widget.currentMode)
            ? widget.currentMode
            : modes.first;
        _modeMenuFocusNodes[initialMode]?.requestFocus();
      });
    }
  }

  void _closeModeMenu() {
    if (!_modeMenuVisible) return;
    setState(() => _modeMenuVisible = false);
    if (_isDesktopPlatform) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _modeButtonFocusNode.requestFocus();
      });
    }
    _reusablePlayerActions?.showControls();
  }

  void _selectDisplayMode(VideoDisplayMode mode) {
    _closeModeMenu();
    if (mode == widget.currentMode) return;
    if (mode == VideoDisplayMode.pictureInPicture) {
      unawaited(_enterPictureInPicture());
      return;
    }
    widget.onSwitchMode?.call(mode);
    _reusablePlayerActions?.showControls();
  }

  List<VideoDisplayMode> get _availableDisplayModes => [
    if (widget.onSwitchMode != null ||
        widget.currentMode == VideoDisplayMode.fullscreen)
      VideoDisplayMode.fullscreen,
    if (widget.onSwitchMode != null) VideoDisplayMode.split,
    if (_canOfferPictureInPicture ||
        widget.currentMode == VideoDisplayMode.pictureInPicture)
      VideoDisplayMode.pictureInPicture,
  ];

  Widget _modeMenuOverlay({required VoidCallback onTapOutside}) {
    final media = MediaQuery.of(context);
    final menuWidth = math.min(220.0, media.size.width - 24);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final options = <({VideoDisplayMode mode, AppIconData icon, String label})>[
      for (final mode in _availableDisplayModes)
        switch (mode) {
          VideoDisplayMode.fullscreen => (
            mode: mode,
            icon: HeroAppIcons.expand,
            label: AppStringKeys.videoPlayerFullscreen.l10n(context),
          ),
          VideoDisplayMode.split => (
            mode: mode,
            icon: HeroAppIcons.tableColumns,
            label: AppStringKeys.videoPlayerSplitScreen.l10n(context),
          ),
          VideoDisplayMode.pictureInPicture => (
            mode: mode,
            icon: HeroAppIcons.pictureInPicture,
            label: AppStringKeys.videoPlayerPictureInPicture.l10n(context),
          ),
        },
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
                                  focusNode:
                                      _modeMenuFocusNodes[options[index].mode],
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

  Widget _loadingState() {
    final aspect =
        widget.width != null &&
            widget.height != null &&
            widget.width! > 0 &&
            widget.height! > 0
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
          const ColoredBox(color: Color(0xFF111113)),
        Center(
          child: Semantics(
            label: _failed
                ? AppStringKeys.videoPlayerLoadFailed.l10n(context)
                : AppStringKeys.videoPlayerLoading.l10n(context),
            child: _failed
                ? _FocusableVideoTextButton(
                    text: AppStringKeys.callsRetry.l10n(context),
                    label: AppStringKeys.callsRetry.l10n(context),
                    onPressed: () => unawaited(_retryPlayback()),
                    size: const Size(96, 40),
                    fontSize: 14,
                  )
                : const _VideoLoadingRing(size: 44),
          ),
        ),
        PositionedDirectional(
          top: MediaQuery.paddingOf(context).top + 6,
          start: 8,
          child: _roundIconButton(
            HeroAppIcons.chevronLeft,
            _close,
            label: AppStringKeys.musicPlayerClose.l10n(context),
            size: 44,
          ),
        ),
      ],
    );
  }

  bool get _showsOrientationButton =>
      widget.presentation == VideoPlayerPresentation.fullscreen &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

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
    _reusablePlayerActions?.showControls();
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
      FVideoPictureInPicture.isSupportedPlatform);

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
            FVideoPictureInPicture.isSupportedPlatform)) {
      try {
        await _startFVideoPictureInPicture();
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
}

class _MithkaVideoCenterTransport extends StatelessWidget {
  const _MithkaVideoCenterTransport({required this.value, required this.scope});

  final VideoPlayerValue value;
  final FVideoChromeScope scope;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MithkaVideoSeekButton(
          backwards: true,
          label: 'Seek backward 10 seconds',
          onTap: () =>
              unawaited(scope.actions.seekBy(const Duration(seconds: -10))),
        ),
        const SizedBox(width: 18),
        ExcludeSemantics(
          child: _MithkaVideoPlayButton(
            playing: value.isPlaying,
            onTap: () => unawaited(scope.actions.togglePlayback()),
            size: 86,
            semanticLabel: 'Center playback',
          ),
        ),
        const SizedBox(width: 18),
        _MithkaVideoSeekButton(
          backwards: false,
          label: 'Seek forward 10 seconds',
          onTap: () =>
              unawaited(scope.actions.seekBy(const Duration(seconds: 10))),
        ),
      ],
    );
  }
}

class _MithkaVideoCompactTransport extends StatelessWidget {
  const _MithkaVideoCompactTransport({
    required this.value,
    required this.scope,
    required this.showQueueNavigation,
  });

  final VideoPlayerValue value;
  final FVideoChromeScope scope;
  final bool showQueueNavigation;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showQueueNavigation && scope.previous != null)
          _MithkaVideoCompactNavButton(
            icon: HeroAppIcons.chevronLeft,
            label: scope.labels.previous,
            onTap: scope.previous!,
          )
        else
          _MithkaVideoSeekButton(
            backwards: true,
            label: 'Seek backward 10 seconds',
            compact: true,
            onTap: () =>
                unawaited(scope.actions.seekBy(const Duration(seconds: -10))),
          ),
        const SizedBox(width: 12),
        ExcludeSemantics(
          child: _MithkaVideoPlayButton(
            playing: value.isPlaying,
            onTap: () => unawaited(scope.actions.togglePlayback()),
            size: 72,
            semanticLabel: 'Center playback',
          ),
        ),
        const SizedBox(width: 12),
        if (showQueueNavigation && scope.next != null)
          _MithkaVideoCompactNavButton(
            icon: HeroAppIcons.chevronRight,
            label: scope.labels.next,
            onTap: scope.next!,
          )
        else
          _MithkaVideoSeekButton(
            backwards: false,
            label: 'Seek forward 10 seconds',
            compact: true,
            onTap: () =>
                unawaited(scope.actions.seekBy(const Duration(seconds: 10))),
          ),
      ],
    );
  }
}

class _MithkaVideoPlayButton extends StatelessWidget {
  const _MithkaVideoPlayButton({
    required this.playing,
    required this.onTap,
    required this.size,
    this.semanticLabel,
  });

  final bool playing;
  final VoidCallback onTap;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return _FocusableVideoIconButton(
      icon: playing ? HeroAppIcons.pause : HeroAppIcons.play,
      label: semanticLabel ?? (playing ? 'Pause' : 'Play'),
      onPressed: onTap,
      size: Size.square(size),
      iconSize: size * 0.44,
      backgroundColor: const Color(0xCC2C2C2E),
      borderColor: Colors.white.withValues(alpha: 0.18),
      cornerRadius: size / 2,
    );
  }
}

class _MithkaVideoSeekButton extends StatelessWidget {
  const _MithkaVideoSeekButton({
    required this.backwards,
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  final bool backwards;
  final String label;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 62.0 : 78.0;
    return AppInteractiveSurface(
      semanticLabel: label,
      onTap: onTap,
      borderRadius: BorderRadius.circular(size / 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xA92C2C2E),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x42000000),
              blurRadius: 14,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AppIcon(
                backwards ? HeroAppIcons.rotateLeft : HeroAppIcons.rotateRight,
                color: Colors.white,
                size: size * 0.61,
              ),
              Padding(
                padding: EdgeInsets.only(top: size * 0.02),
                child: Text(
                  '10',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 11 : 13,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MithkaVideoCompactNavButton extends StatelessWidget {
  const _MithkaVideoCompactNavButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 56,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => _FocusableVideoIconButton(
    icon: icon,
    label: label,
    onPressed: onTap,
    size: Size.square(size),
    iconSize: size * 0.45,
    backgroundColor: const Color(0xB82C2C2E),
    borderColor: Colors.white.withValues(alpha: 0.18),
    cornerRadius: size / 2,
  );
}

class _MithkaVideoSideButton extends StatelessWidget {
  const _MithkaVideoSideButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _FocusableVideoIconButton(
    icon: icon,
    label: label,
    onPressed: onTap,
    size: const Size(52, 116),
    iconSize: 25,
    backgroundColor: const Color(0xA92C2C2E),
    borderColor: Colors.white.withValues(alpha: 0.24),
    cornerRadius: 26,
  );
}

class _MithkaVideoBottomChrome extends StatelessWidget {
  const _MithkaVideoBottomChrome({
    required this.scope,
    required this.wide,
    required this.buffered,
    required this.aspectRatio,
    required this.thumbnailProvider,
    required this.compactQueueNavigation,
    required this.previousButton,
    required this.nextButton,
    required this.modeButton,
    required this.fullscreenButton,
    required this.qualityLabel,
  });

  final FVideoChromeScope scope;
  final bool wide;
  final double buffered;
  final double aspectRatio;
  final Future<Uint8List?> Function(Duration position) thumbnailProvider;
  final bool compactQueueNavigation;
  final Widget? previousButton;
  final Widget? nextButton;
  final Widget? modeButton;
  final Widget? fullscreenButton;
  final String qualityLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MithkaVideoTimeline(
          scope: scope,
          wide: wide,
          buffered: buffered,
          aspectRatio: aspectRatio,
          thumbnailProvider: thumbnailProvider,
        ),
        const SizedBox(height: 5),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final showVolumeSlider = width >= 220;
            final showTime = !compactQueueNavigation && (width >= 330 || wide);
            final showWaveform = wide && width >= 700;
            final showSpeed = !compactQueueNavigation && (width >= 320 || wide);
            final showQuality = qualityLabel.isNotEmpty && width >= 700;
            return Row(
              children: [
                if (compactQueueNavigation) ...[
                  previousButton ?? const SizedBox.square(dimension: 44),
                  const SizedBox(width: 4),
                ],
                _FocusableVideoIconButton(
                  icon: scope.snapshot.value.isPlaying
                      ? HeroAppIcons.pause
                      : HeroAppIcons.play,
                  label: scope.snapshot.value.isPlaying
                      ? scope.labels.pause
                      : scope.labels.play,
                  onPressed: () => unawaited(scope.actions.togglePlayback()),
                  size: const Size.square(44),
                  iconSize: 23,
                ),
                if (compactQueueNavigation) ...[
                  const SizedBox(width: 4),
                  nextButton ?? const SizedBox.square(dimension: 44),
                ],
                const SizedBox(width: 4),
                _FocusableVideoIconButton(
                  icon: scope.snapshot.volume <= 0.01
                      ? HeroAppIcons.volumeXmark
                      : HeroAppIcons.volumeHigh,
                  label: scope.snapshot.volume <= 0.01
                      ? scope.labels.unmute
                      : scope.labels.mute,
                  onPressed: () => unawaited(scope.actions.toggleMute()),
                  size: const Size.square(44),
                  iconSize: 23,
                ),
                if (showVolumeSlider) ...[
                  const SizedBox(width: 2),
                  SizedBox(
                    width: wide ? 74 : 64,
                    height: 44,
                    child: FVideoSlider(
                      value: scope.snapshot.volume.clamp(0.0, 1.0).toDouble(),
                      trackHeight: 3,
                      thumbRadius: 5,
                      activeColor: Colors.white,
                      inactiveColor: Colors.white.withValues(alpha: 0.26),
                      semanticLabel: scope.labels.volume,
                      semanticValue:
                          '${(scope.snapshot.volume * 100).round()}%',
                      onChanged: (value) =>
                          unawaited(scope.actions.setVolume(value)),
                    ),
                  ),
                ],
                if (showTime) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: wide ? 78 : 70,
                    child: Text(
                      '${_formatTimelineDuration(scope.snapshot.displayPosition)} / ${_formatTimelineDuration(scope.snapshot.value.duration)}',
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
                if (showWaveform) ...[
                  const SizedBox(width: 10),
                  const Expanded(child: _MithkaVideoWaveform()),
                  const SizedBox(width: 10),
                ] else
                  const Spacer(),
                if (showSpeed)
                  _MithkaVideoTextButton(
                    text: _formatPlaybackSpeed(
                      scope.snapshot.value.playbackSpeed,
                    ),
                    label: scope.labels.speed,
                    onTap: () => unawaited(
                      scope.actions.setPlaybackSpeed(
                        _nextPlaybackSpeed(scope.snapshot.value.playbackSpeed),
                      ),
                    ),
                  ),
                if (showQuality)
                  _MithkaVideoReadOnlyBadge(
                    label: 'Video quality',
                    value: qualityLabel,
                  ),
                if (modeButton != null) ...[
                  const SizedBox(width: 6),
                  modeButton!,
                ],
                if (fullscreenButton != null) ...[
                  const SizedBox(width: 6),
                  fullscreenButton!,
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MithkaVideoTextButton extends StatelessWidget {
  const _MithkaVideoTextButton({
    required this.text,
    required this.label,
    required this.onTap,
  });

  final String text;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppInteractiveSurface(
    semanticLabel: label,
    semanticValue: text,
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      constraints: const BoxConstraints(minWidth: 54, minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0x8A1B1D1E),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ),
  );
}

class _MithkaVideoReadOnlyBadge extends StatelessWidget {
  const _MithkaVideoReadOnlyBadge({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: label,
    value: value,
    child: Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0x8A1B1D1E),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _MithkaVideoTimeline extends StatefulWidget {
  const _MithkaVideoTimeline({
    required this.scope,
    required this.wide,
    required this.buffered,
    required this.aspectRatio,
    required this.thumbnailProvider,
  });

  final FVideoChromeScope scope;
  final bool wide;
  final double buffered;
  final double aspectRatio;
  final Future<Uint8List?> Function(Duration position) thumbnailProvider;

  @override
  State<_MithkaVideoTimeline> createState() => _MithkaVideoTimelineState();
}

class _MithkaVideoTimelineState extends State<_MithkaVideoTimeline> {
  Timer? _thumbnailTimer;
  Timer? _thumbnailTimeout;
  int _thumbnailGeneration = 0;
  double? _scrubFraction;
  Uint8List? _thumbnail;

  @override
  void dispose() {
    _thumbnailTimer?.cancel();
    _thumbnailTimeout?.cancel();
    super.dispose();
  }

  Duration _positionFor(double fraction) {
    final duration = widget.scope.snapshot.value.duration;
    return Duration(
      microseconds: (duration.inMicroseconds * fraction.clamp(0.0, 1.0))
          .round(),
    );
  }

  void _beginScrub(double fraction) {
    _thumbnailTimer?.cancel();
    _thumbnailTimeout?.cancel();
    widget.scope.actions.beginScrub(fraction);
    setState(() {
      _scrubFraction = fraction;
      _thumbnail = null;
    });
    _scheduleThumbnail(fraction);
  }

  void _updateScrub(double fraction) {
    widget.scope.actions.updateScrub(fraction);
    setState(() => _scrubFraction = fraction);
    _scheduleThumbnail(fraction);
  }

  void _endScrub(double fraction) {
    _thumbnailTimer?.cancel();
    _thumbnailTimeout?.cancel();
    final finalFraction = _scrubFraction ?? fraction;
    unawaited(_commitScrub(finalFraction));
  }

  Future<void> _commitScrub(double fraction) async {
    await widget.scope.actions.endScrub(fraction);
    if (!mounted) return;
    setState(() {
      _scrubFraction = null;
      _thumbnail = null;
    });
  }

  void _scheduleThumbnail(double fraction) {
    _thumbnailTimer?.cancel();
    _thumbnailTimeout?.cancel();
    final generation = ++_thumbnailGeneration;
    _thumbnailTimer = Timer(const Duration(milliseconds: 200), () async {
      _thumbnailTimer = null;
      try {
        final result = await widget.thumbnailProvider(_positionFor(fraction));
        if (!mounted || generation != _thumbnailGeneration) return;
        setState(() => _thumbnail = result);
      } catch (_) {
        if (mounted && generation == _thumbnailGeneration) {
          setState(() => _thumbnail = null);
        }
      }
    });
    _thumbnailTimeout = Timer(const Duration(seconds: 2), () {
      if (!mounted || generation != _thumbnailGeneration) return;
      _thumbnailTimer?.cancel();
      setState(() => _thumbnail = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.scope.snapshot.value.duration;
    final durationMs = math.max(1, duration.inMilliseconds);
    final position = widget.scope.snapshot.displayPosition;
    final actualFraction = (position.inMilliseconds / durationMs)
        .clamp(0.0, 1.0)
        .toDouble();
    final fraction = _scrubFraction ?? actualFraction;
    return LayoutBuilder(
      builder: (context, constraints) {
        final previewWidth = widget.wide ? 160.0 : 128.0;
        final previewHeight = (previewWidth / widget.aspectRatio)
            .clamp(widget.wide ? 78.0 : 72.0, widget.wide ? 110.0 : 72.0)
            .toDouble();
        final trackWidth = constraints.maxWidth;
        final previewLeft = (fraction * trackWidth - previewWidth / 2)
            .clamp(0.0, math.max(0.0, trackWidth - previewWidth))
            .toDouble();
        return SizedBox(
          height: widget.wide ? 30 : 28,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: FVideoSlider(
                  value: actualFraction,
                  bufferedValue: widget.buffered,
                  trackHeight: widget.wide ? 4 : 3,
                  thumbRadius: widget.wide ? 7 : 6,
                  activeColor: const Color(0xFF24DDD9),
                  bufferedColor: Colors.white.withValues(alpha: 0.32),
                  inactiveColor: Colors.white.withValues(alpha: 0.86),
                  semanticLabel: widget.scope.labels.position,
                  semanticValue:
                      '${_formatTimelineDuration(position)} / ${_formatTimelineDuration(duration)}',
                  semanticIncreasedValue: _formatTimelineDuration(
                    position + const Duration(seconds: 10) > duration
                        ? duration
                        : position + const Duration(seconds: 10),
                  ),
                  semanticDecreasedValue: _formatTimelineDuration(
                    position - const Duration(seconds: 10) < Duration.zero
                        ? Duration.zero
                        : position - const Duration(seconds: 10),
                  ),
                  keyboardStep: math.min(
                    1,
                    const Duration(seconds: 10).inMilliseconds / durationMs,
                  ),
                  onChangeStart: _beginScrub,
                  onChanged: _updateScrub,
                  onChangeEnd: _endScrub,
                ),
              ),
              if (_scrubFraction != null)
                Positioned(
                  left: previewLeft,
                  bottom: (widget.wide ? 30 : 28) + 8,
                  width: previewWidth,
                  height: previewHeight,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF111315),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x99000000),
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
                            if (_thumbnail != null)
                              Image.memory(
                                _thumbnail!,
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
                                    colors: [
                                      Color(0x00000000),
                                      Color(0xDD000000),
                                    ],
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    6,
                                    12,
                                    6,
                                    5,
                                  ),
                                  child: Text(
                                    _formatTimelineDuration(
                                      _positionFor(fraction),
                                    ),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
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
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MithkaVideoWaveform extends StatelessWidget {
  const _MithkaVideoWaveform();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 30,
    child: CustomPaint(painter: _MithkaVideoWaveformPainter()),
  );
}

class _MithkaVideoWaveformPainter extends CustomPainter {
  const _MithkaVideoWaveformPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final count = math.max(1, (size.width / 4).floor());
    for (var index = 0; index < count; index++) {
      final x = index * size.width / count;
      final wave = (math.sin(index * 1.73) + math.sin(index * 0.43) * 0.5)
          .abs();
      final height = 4 + wave * (size.height - 8);
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MithkaVideoWaveformPainter oldDelegate) =>
      false;
}

String _formatPlaybackSpeed(double speed) {
  if (!speed.isFinite || speed <= 0) return '1x';
  return '${speed.toStringAsFixed(speed % 1 == 0 ? 0 : 2)}x';
}

double _nextPlaybackSpeed(double speed) {
  const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  final index = speeds.indexWhere((value) => (value - speed).abs() < 0.001);
  return speeds[(index + 1) % speeds.length];
}

String _formatTimelineDuration(Duration value) {
  final seconds = math.max(0, value.inSeconds);
  final hours = seconds ~/ 3600;
  final minutes = (seconds ~/ 60) % 60;
  final remainder = seconds % 60;
  return hours > 0
      ? '$hours:${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}'
      : '$minutes:${remainder.toString().padLeft(2, '0')}';
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
                    color: Colors.white,
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
    this.focusNode,
    this.autofocus = false,
    this.selected = false,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
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
      focusNode: widget.focusNode,
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
