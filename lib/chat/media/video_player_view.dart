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
import 'dart:ui' as ui;

import 'package:cineplay/cineplay.dart';
import 'package:cineplay_fvp/cineplay_fvp.dart';
import 'package:cineplay_pip/cineplay_pip.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fvp/fvp.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../../app/app_navigator.dart';
import '../../app/chat_deep_link_controller.dart';
import '../../app/ipad_window_chrome.dart';
import '../../app/video_split_controller.dart';
import '../../components/app_icons.dart';
import '../../components/app_interactive_surface.dart';
import '../../components/photo_avatar.dart';
import '../../components/toast.dart';
import '../../media/media_metadata.dart';
import '../../media/media_metadata_dialog.dart';
import '../../media/video_playback_reporting.dart';
import '../../media/video_view_compatibility.dart';
import '../../platform/fullscreen_system_ui.dart';
import '../../platform/keyboard_modifiers.dart';
import '../../platform/ohos_support.dart';
import '../../platform/player_brightness.dart';
import '../../platform/player_system_volume.dart';
import '../../platform/screen_wakelock.dart';
import '../../tdlib/json_helpers.dart';
import '../../tdlib/td_client.dart';
import '../../tdlib/td_image_loader.dart';
import '../../tdlib/td_models.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_controller.dart';
import '../chat_picker_view.dart';
import '../forward_handoff.dart';
import '../messages/forward_markdown.dart';
import 'media_download_service.dart';
import 'media_library_saver.dart';
import 'td_video_stream_server.dart';
import 'video_playback_preferences.dart';
import 'video_playback_queue.dart';
import 'video_stream_debugger.dart';

export 'td_video_stream_server.dart';

part 'video_player_chrome.dart';
part 'video_player_controller_recovery.dart';
part 'video_player_overlays_menus.dart';

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
    pageBuilder: (routeContext, _, _) => VideoOnDemandPlayerView(
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

/// The base playback rate the most recently built player keeps in its state.
///
/// A regression can then assert what the player DISPLAYS after a rate request
/// completes, not only what the platform received.
@visibleForTesting
double debugVideoPlayerBaseSpeed = double.nan;

/// The base playback rate this player currently keeps, with no test hook.
@visibleForTesting
double get videoPlayerBaseSpeedForTesting => VideoPlayerView.debugLastBaseSpeed;

// A pan only becomes a real gesture once it clears a deliberate-drag threshold.
// The pan recognizer joins the arena at the platform's `kTouchSlop`, which on a
// high-density phone is a few millimetres — the same distance a thumb rolls
// during a tap meant to toggle the chrome. Engaging a seek at that point stole
// the tap: the package's tap recognizer never won, so the chrome never toggled,
// and the roll committed a seek instead. Below this threshold the pan is
// treated as a tap.
const _playbackGestureEngageDistance = kTouchSlop * 1.75;

// Holding a finger down changes the playback rate; a tap must never turn into
// a hold just because the press outlasted the long-press threshold.

/// Whether a pan has travelled far enough to be a playback gesture rather than
/// a tap.
///
/// The pan recognizer wins the arena at [kTouchSlop], which is also the
/// distance a thumb rolls during an ordinary tap, so winning the arena is not
/// evidence of intent. Nothing engages below this distance: no seek, no
/// brightness or volume change, and the release is finished as a tap.
bool videoPlaybackPanEngages(Offset delta) =>
    math.max(delta.dx.abs(), delta.dy.abs()) >= _playbackGestureEngageDistance;

// A drag has to lean this much toward one axis before it counts as that axis,
// so a diagonal roll stays a tap instead of becoming a volume or queue swipe.
const _playbackGestureAxisLockRatio = 1.20;

/// Whether a surface pan was the deliberate horizontal drag that moves through
/// the playback queue, rather than the tap it shares a pointer with.
///
/// The playback surface is a [GestureDetector] that owns both a pan and a tap.
/// Once the pan wins the arena the tap can no longer fire, so the pan has to
/// decide on release: travel under [_playbackGestureEngageDistance] was a tap
/// that rolled, and a drag across any other axis is not the queue swipe either.
/// Both are finished as the tap they displaced.
bool videoSurfacePanReplacesTap(Offset delta) {
  if (videoPlaybackPanEngages(delta)) {
    return delta.dx.abs() >= delta.dy.abs() * _playbackGestureAxisLockRatio;
  }
  return false;
}

class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({
    super.key,
    required this.video,
    this.accountSlot,
    this.thumb,
    this.title = '',
    this.width,
    this.height,
    this.durationSeconds,
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
    this.onDemandQueue,
    this.onDemandSelect,
    this.onFVideoPictureInPictureRestore,
    this.onToggleFullscreen,
    this.streamQuery,
    this.thumbnailProvider,
  });

  final TdFileRef video;
  final int? accountSlot;
  final TdFileRef? thumb;
  final String title;
  final int? width;
  final int? height;
  final int? durationSeconds;
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
  final VideoPlaybackQueue? onDemandQueue;
  final ValueChanged<int>? onDemandSelect;
  final VideoPictureInPictureRestoreCallback? onFVideoPictureInPictureRestore;

  final VoidCallback? onToggleFullscreen;

  /// Overrides TDLib file queries for deterministic host tests.
  @visibleForTesting
  final TdVideoStreamQuery? streamQuery;

  /// Overrides native thumbnail generation for deterministic host tests.
  @visibleForTesting
  final FVideoThumbnailProvider? thumbnailProvider;

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();

  /// The base rate the last built player kept; the test hook writes it.
  static double debugLastBaseSpeed = double.nan;
}

typedef VideoOnDemandModeCallback =
    void Function(VideoPlaybackQueue queue, VideoDisplayMode mode);

class VideoOnDemandPlayerView extends StatefulWidget {
  const VideoOnDemandPlayerView({
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
  final VideoOnDemandModeCallback? onSwitchMode;
  final ValueChanged<VideoPlaybackQueue>? onQueueChanged;
  final ValueChanged<double>? onVolumeChanged;
  final double initialVolume;
  final bool initialMuted;
  final bool initialPlaying;
  final double initialSpeed;
  final Duration? initialPosition;
  final TdVideoStreamQuery? streamQuery;

  @override
  State<VideoOnDemandPlayerView> createState() =>
      _VideoOnDemandPlayerViewState();
}

class _VideoOnDemandPlayerViewState extends State<VideoOnDemandPlayerView>
    with SingleTickerProviderStateMixin {
  late VideoPlaybackQueue _queue = widget.queue;
  late Duration? _initialPosition = widget.initialPosition;
  late bool _initialPlaying = widget.initialPlaying;
  late double _lastAudibleVolume;
  late bool _muted;
  late final AnimationController _queueTransition = AnimationController(
    vsync: this,
    duration: AppMotion.deliberate,
    value: 1,
  );
  int _queueTransitionDirection = 1;

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
  void didUpdateWidget(covariant VideoOnDemandPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.queue != oldWidget.queue) {
      if (widget.queue.current.video.id != _queue.current.video.id) {
        _startQueueTransition(widget.queue.index >= _queue.index ? 1 : -1);
      }
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
    _startQueueTransition(delta);
    widget.onQueueChanged?.call(next);
  }

  void _selectOnDemandItem(int index) {
    final next = _queue.moveTo(index);
    if (next == null || identical(next, _queue)) return;
    final direction = index >= _queue.index ? 1 : -1;
    setState(() {
      _queue = next;
      _initialPosition = null;
      _initialPlaying = true;
    });
    _startQueueTransition(direction);
    widget.onQueueChanged?.call(next);
  }

  void _startQueueTransition(int direction) {
    _queueTransitionDirection = direction >= 0 ? 1 : -1;
    if (AppMotion.isReduced(context)) {
      _queueTransition.value = 1;
    } else {
      _queueTransition.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _queueTransition.dispose();
    super.dispose();
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
    final player = VideoPlayerView(
      key: ValueKey(
        '${item.accountSlot ?? 'active'}:${item.video.id}:${item.messageId ?? 0}',
      ),
      video: item.video,
      accountSlot: item.accountSlot,
      thumb: item.thumb,
      title: item.title,
      width: item.width,
      height: item.height,
      durationSeconds: item.durationSeconds,
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
      onDemandQueue: _queue,
      onDemandSelect: _selectOnDemandItem,
      streamQuery: widget.streamQuery,
      onFVideoPictureInPictureRestore: (snapshot) =>
          restoreVideoPlaybackFromPictureInPicture(
            queue: _queue,
            snapshot: snapshot,
            streamQuery: widget.streamQuery,
          ),
    );
    return ColoredBox(
      color: Colors.black,
      child: AnimatedBuilder(
        animation: _queueTransition,
        child: player,
        builder: (context, child) {
          final arrival = AppMotion.standard.transform(_queueTransition.value);
          return Opacity(
            key: const ValueKey('video-queue-arrival'),
            opacity: 0.35 + arrival * 0.65,
            child: Transform.translate(
              offset: Offset(0, _queueTransitionDirection * (1 - arrival) * 44),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

class _VideoPlayerViewState extends State<VideoPlayerView>
    with WidgetsBindingObserver {
  void _updateState(VoidCallback fn) => setState(fn);

  late final TdVideoStreamQuery _streamQuery =
      widget.streamQuery ?? tdVideoStreamQueryForAccount(widget.accountSlot);

  VideoPlayerController? _controller;
  final FVideoThumbnailCache _scrubThumbnailCache = FVideoThumbnailCache();
  bool _nextVideoPrewarmed = false;

  late final _playbackDiagnostics = VideoPlaybackDiagnostics(
    location: VideoPlaybackLocation.player,
    mimeType: widget.video.mimeType,
    width: widget.width,
    height: widget.height,
  );

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

  bool _appInForeground = true;

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

  /// Control visibility for the loading chrome, which mithka owns until the
  /// package player takes over. Reset whenever playback re-enters loading.
  bool _loadingControlsVisible = true;

  _LoadingVideoActions? _loadingActions;

  bool _debuggerVisible = false;

  bool _onDemandPanelVisible = false;

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

  bool _heldSpeedActive = false;

  double _heldSpeedRate = 1;

  /// The rate playback runs at when no hold is applied. It survives a hold and
  /// a restore still travelling to the platform, so a second hold restores to
  /// it instead of to a rate the wire has not delivered yet.
  double _heldSpeedBaseRate = 1;

  /// The rate the native player should settle at. Every speed write goes
  /// through [_pumpHeldSpeedWrites], which is the only caller of
  /// `setPlaybackSpeed`, so the last rate the native side sees is always this
  /// one whatever order the earlier futures complete in.
  double? _heldSpeedDesiredRate;

  bool _heldSpeedWriteInFlight = false;

  bool _heldSpeedDisposed = false;

  /// How many consecutive native rate writes may fail before the pump stops
  /// trying to reconcile the player and leaves the remembered base alone.
  /// The first failure still queues the restore once (the rate the wire
  /// carried may never have landed), but a restore that fails in turn gives
  /// up instead of looping: the next ordinary speed change re-arms the pump.
  static const _heldSpeedMaxConsecutiveFailures = 2;

  int _heldSpeedConsecutiveFailures = 0;

  /// The pointer that owns the active hold. A second finger landing, lifting
  /// or being cancelled must not end the first one's hold, so the pinch
  /// listener's pointer up/cancel only ends the hold when this pointer does.
  /// `null` means the hold is inactive or was started by a non-touch pointer
  /// (e.g. a mouse) that never went through `_videoZoomPointers` — in that
  /// fallback that listener keeps the old unconditional behaviour.
  int? _heldSpeedPointer;

  // Below this the copy reads as a pause, so the hold leaves playback alone.
  static const _minimumHeldSpeedRate = 0.25;

  /// Width of the left edge band whose rightward swipe leaves the player.
  static const videoDismissEdgeWidth = 24.0;

  /// Horizontal travel, in logical pixels, that commits that swipe.
  static const videoDismissDragDistance = 96.0;

  // The swipe only takes over once it is clearly horizontal, so a vertical
  // drag inside the same band still reaches the brightness/volume gesture.
  static const _dismissIntentDistance = 18.0;

  int? _dismissPointer;

  double _dismissTrackedDx = 0;

  double _dismissTrackedDy = 0;

  double _dismissDx = 0;

  bool _edgeDismissCandidate = false;

  bool _edgeDismissActive = false;

  bool _dismissGestureSettling = false;

  /// Stamp of the settling window; a newer press or a cancel retires it.
  int _dismissSettlerGeneration = 0;

  Timer? _touchControlsHideTimer;

  double _videoZoomScale = 1;

  Offset _videoZoomOffset = Offset.zero;

  Rect _videoZoomViewport = Rect.zero;

  bool _videoZoomGestureActive = false;

  double _videoZoomGestureStartScale = 1;

  double _videoZoomGestureScaleBaseline = 1;

  Offset _videoZoomGestureContentAnchor = Offset.zero;

  final Map<int, Offset> _videoZoomPointers = <int, Offset>{};

  List<int> _videoZoomPinchPointers = const <int>[];

  bool _videoZoomSuppressPlaybackGestures = false;

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
    6,
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

  static const _minimumVideoZoomScale = 1.0;

  static const _maximumVideoZoomScale = 4.0;

  static const _videoZoomResetThreshold = 1.02;

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
      _heldSpeedBaseRate = _speed;
      VideoPlayerView.debugLastBaseSpeed = _speed;
      debugVideoPlayerBaseSpeed = _speed;
    }
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadPlaybackPreferences());
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;
    _syncStreamStallRecovery(_controller?.value);
    // Leaving the app is where the resume position has to become durable: the
    // process may never be resumed, and the periodic save is coarse.
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_storePlaybackPosition(force: true));
    }
  }

  bool get _usesAndroidFVideoPictureInPicture =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  double get _pictureInPictureVolume =>
      (_volume > 0.01 ? _volume : _lastAudibleVolume)
          .clamp(0.0, 1.0)
          .toDouble();

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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelHeldSpeed();
    // A write already on the wire is not recalled; the pump re-checks this
    // flag after every completion and must not touch the player again.
    _heldSpeedDisposed = true;
    _touchControlsHideTimer?.cancel();
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
    _scrubThumbnailCache.clear();
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

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    final player = FullscreenSystemUi(
      enabled:
          widget.presentation == VideoPlayerPresentation.fullscreen &&
          !_systemPiPActive,
      child: ColoredBox(
        color: Colors.black,
        child: _playbackSurface(ready ? c : null),
      ),
    );
    // A rightward swipe from the left edge slides the page away with the
    // finger so the player can be left from the surface itself.
    final drag = _dismissDx;
    if (drag == 0) return player;
    final progress = (drag / videoDismissDragDistance).clamp(0.0, 1.0);
    return ColoredBox(
      color: Colors.black,
      child: Transform.translate(
        key: const ValueKey('video-dismiss-drag'),
        offset: Offset(drag, 0),
        child: Transform.scale(
          scale: 1 - progress * 0.06,
          child: Opacity(opacity: 1 - progress * 0.3, child: player),
        ),
      ),
    );
  }

  Widget _playbackSurface(VideoPlayerController? controller) {
    final player = controller == null
        ? _loadingSurface()
        : _reusablePlayer(controller);
    if (widget.presentation != VideoPlayerPresentation.fullscreen ||
        controller == null) {
      return player;
    }
    return VideoStreamDebuggerOverlay(
      player: player,
      visible: _debuggerVisible,
      inspectorBuilder: (_, constraints) => VideoStreamDebugger(
        progress: _progress,
        position: controller.value.position,
        duration: controller.value.duration,
        events: List<String>.unmodifiable(_debugEvents),
        isLive: _streamServer != null || controller.value.isPlaying,
        viewportSize: Size(constraints.maxWidth, constraints.maxHeight),
        videoSize: controller.value.size,
        volume: controller.value.volume,
        playbackSpeed: controller.value.playbackSpeed,
        bufferedAhead: _bufferedAhead(controller.value),
        onClose: () {
          if (mounted) _updateState(() => _debuggerVisible = false);
        },
      ),
    );
  }

  Widget _reusablePlayer(VideoPlayerController controller) {
    final player = FVideoPlayer(
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
      onPositionChanged: _handleReusablePositionChanged,
      onPlaybackStateChanged: _handleReusablePlaybackStateChanged,
      onVolumeChanged: _handleReusableVolumeChanged,
      chapters: _resolvedChapters(controller),
      frameStepDelegate: (frames) async {
        final active = _controller;
        if (active == null) return;
        final stepped = await FvpControllerBridge.stepFrames(active, frames);
        if (!stepped) {
          final target =
              active.value.position + Duration(milliseconds: 33 * frames);
          await active.seekTo(target < Duration.zero ? Duration.zero : target);
        }
      },
      snapshotDelegate: ({width, height}) {
        final active = _controller;
        if (active == null) return Future<Uint8List?>.value();
        return FvpControllerBridge.captureFramePng(
          active,
          width: width,
          height: height,
        );
      },
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
    if (!_supportsPlaybackGestures) return player;
    return Listener(
      key: const ValueKey('video-pinch-zoom-listener'),
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleVideoZoomPointerDown,
      onPointerMove: _handleVideoZoomPointerMove,
      // Only the pointer that owns the hold ends it: a second finger
      // lifting or being cancelled must not end the first one's hold. The
      // long-press recognizer tracks its own primary pointer, but this
      // viewport-wide listener sees every touch, so the guard lives here.
      onPointerUp: (event) {
        _stopHeldSpeedForPointer(event.pointer);
        _handleVideoZoomPointerEnd(event);
      },
      onPointerCancel: (event) {
        _stopHeldSpeedForPointer(event.pointer);
        _handleVideoZoomPointerEnd(event);
      },
      child: player,
    );
  }

  /// The player's own viewport inside this widget.
  ///
  /// A wide window letterboxes the video surface, and the uncovered bands are
  /// not the player: the edge-swipe and hold gestures only belong to the
  /// darkened box the video actually fills.
  Rect get _darkenedPlayerViewport {
    final render = context.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return Rect.zero;
    final size = render.size;
    final aspect = _lastKnownVideoAspectRatio;
    var width = size.width;
    var height = width / aspect;
    if (height > size.height) {
      height = size.height;
      width = height * aspect;
    }
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: width,
      height: height,
    );
  }

  /// The last known video aspect ratio, falling back to the initial value.
  double get _lastKnownVideoAspectRatio {
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      return _resolvedVideoAspectRatio(controller.value);
    }
    return _metadataAspectRatio() ?? 16 / 9;
  }

  bool get _hasOnDemandQueue => (widget.onDemandQueue?.items.length ?? 0) >= 2;

  double? get _downloadedFraction {
    final value = _progress?.prefixFraction ?? _progress?.fraction;
    return value?.clamp(0.0, 1.0).toDouble();
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

  Widget _playerChrome(BuildContext context, FVideoChromeScope scope) {
    _reusablePlayerActions = scope.actions;
    // The chrome's speed controls ask the package to apply the next step.
    // Routing that through the hold's serializer keeps one newest desired
    // rate, so a speed step and a hold cannot land out of order.
    final chromeScope = FVideoChromeScope(
      snapshot: _chromeSnapshotForKeptRate(scope.snapshot),
      actions: _SerializedVideoActions(scope.actions, _applyPlaybackSpeedRate),
      labels: scope.labels,
      previous: scope.previous,
      next: scope.next,
    );
    return GestureDetector(
      // Text and decorative chrome can hit-test without handling taps. Let
      // their taps dismiss controls while buttons/sliders keep their gestures.
      onTap: () => _dismissMenusAndControls(scope: chromeScope),
      child: _playerFullscreenChrome(context, chromeScope),
    );
  }

  Widget _playerFullscreenChrome(
    BuildContext context,
    FVideoChromeScope scope,
  ) {
    final snapshot = scope.snapshot;
    final safePadding = MediaQuery.paddingOf(context);
    if (snapshot.controlsVisible && _showsOnDemandLayout(context)) {
      return _playerOnDemandChrome(context, scope, safePadding);
    }
    final standalone = _usesStandaloneFullscreenLayout(context);
    return DefaultTextStyle.merge(
      style: const TextStyle(
        decoration: TextDecoration.none,
        fontWeight: FontWeight.w400,
      ),
      child: ExcludeFocus(
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
                  final subtitle = _videoChromeSubtitle(
                    snapshot.value.duration,
                  );
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
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.76,
                                      ),
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
                              label: AppStrings.t(
                                AppStringKeys.videoPlayerStreamInspector,
                              ),
                              onTap: () {
                                _updateState(
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
                              label: AppStrings.t(AppStringKeys.momentsMore),
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
                        bottom:
                            safePadding.bottom +
                            (wide ? (standalone ? 158 : 132) : 168),
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
                        child: standalone
                            ? _MithkaVideoStandaloneBottomChrome(
                                scope: scope,
                                buffered: buffered,
                                aspectRatio: aspect,
                                thumbnailProvider: _provideScrubThumbnailAt,
                                modeButton: _showsDisplayModeButton
                                    ? _displayModeButton(size: 44)
                                    : null,
                                onDemandButton: _hasOnDemandQueue
                                    ? _onDemandToggleButton()
                                    : null,
                                fullscreenButton:
                                    widget.onToggleFullscreen == null
                                    ? null
                                    : _playerChromeIconButton(
                                        icon: HeroAppIcons.expand,
                                        label: scope.labels.fullscreen,
                                        onTap: widget.onToggleFullscreen!,
                                        size: 44,
                                        iconSize: 20,
                                        cornerRadius: 10,
                                        backgroundColor: const Color(
                                          0x9A1B1D1E,
                                        ),
                                        borderColor: Colors.white.withValues(
                                          alpha: 0.26,
                                        ),
                                      ),
                              )
                            : _MithkaVideoBottomChrome(
                                scope: scope,
                                wide: wide,
                                buffered: buffered,
                                aspectRatio: aspect,
                                thumbnailProvider: _provideScrubThumbnailAt,
                                compactQueueNavigation: compactQueueNavigation,
                                previousButton:
                                    compactQueueNavigation &&
                                        scope.previous != null
                                    ? _MithkaVideoCompactNavButton(
                                        icon: HeroAppIcons.chevronLeft,
                                        label: scope.labels.previous,
                                        onTap: scope.previous!,
                                        size: 44,
                                      )
                                    : null,
                                nextButton:
                                    compactQueueNavigation && scope.next != null
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
                                onDemandButton: _hasOnDemandQueue
                                    ? _onDemandToggleButton()
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
                                        backgroundColor: const Color(
                                          0x9A1B1D1E,
                                        ),
                                        borderColor: Colors.white.withValues(
                                          alpha: 0.26,
                                        ),
                                      ),
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _playerOnDemandChrome(
    BuildContext context,
    FVideoChromeScope scope,
    EdgeInsets safePadding,
  ) {
    final snapshot = scope.snapshot;
    final queue = widget.onDemandQueue!;
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
                    math.max(1, snapshot.value.duration.inMilliseconds),
          _downloadedFraction ?? 0,
        )
        .clamp(0.0, 1.0)
        .toDouble();
    final title = _videoChromeTitle();
    final subtitle =
        'On-demand  •  '
        '${formatVideoPlayerDuration(snapshot.value.duration)}';

    return DefaultTextStyle.merge(
      style: const TextStyle(
        decoration: TextDecoration.none,
        fontWeight: FontWeight.w400,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final geometry = _VideoOnDemandGeometry.resolve(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            safePadding: safePadding,
            aspectRatio: aspect,
          );
          final modeButton = _showsDisplayModeButton
              ? _displayModeButton(size: 44)
              : null;
          final onDemandButton = _onDemandToggleButton();
          final fullscreenButton = widget.onToggleFullscreen == null
              ? null
              : _playerChromeIconButton(
                  icon: HeroAppIcons.expand,
                  label: scope.labels.fullscreen,
                  onTap: widget.onToggleFullscreen!,
                  size: 44,
                  iconSize: 20,
                  cornerRadius: 10,
                  backgroundColor: const Color(0x9A1B1D1E),
                  borderColor: Colors.white.withValues(alpha: 0.26),
                );
          final controls = Stack(
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
                          Colors.black.withValues(alpha: 0.54),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.48),
                        ],
                        stops: const [0, 0.42, 1],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fromRect(
                rect: geometry.headerRect,
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
                    if (geometry.wide) ...[
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.74),
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else
                      const Spacer(),
                    const SizedBox(width: 10),
                    _playerChromeIconButton(
                      icon: HeroAppIcons.code,
                      label: AppStrings.t(
                        AppStringKeys.videoPlayerStreamInspector,
                      ),
                      onTap: () {
                        _updateState(
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
                      label: AppStrings.t(AppStringKeys.momentsMore),
                      onTap: _toggleMoreMenu,
                      size: 44,
                      iconSize: 23,
                      cornerRadius: 22,
                      focusNode: _moreButtonFocusNode,
                    ),
                  ],
                ),
              ),
              Positioned.fromRect(
                rect: geometry.videoRect,
                child: Center(
                  child: geometry.wide
                      ? _MithkaVideoCenterTransport(
                          value: snapshot.value,
                          scope: scope,
                        )
                      : _MithkaVideoCompactTransport(
                          value: snapshot.value,
                          scope: scope,
                          showQueueNavigation: false,
                        ),
                ),
              ),
              Positioned.fromRect(
                rect: geometry.bottomChromeRect,
                child: geometry.wide
                    ? Align(
                        alignment: Alignment.bottomCenter,
                        child: _MithkaVideoBottomChrome(
                          scope: scope,
                          wide: true,
                          buffered: buffered,
                          aspectRatio: aspect,
                          thumbnailProvider: _provideScrubThumbnailAt,
                          compactQueueNavigation: false,
                          previousButton: null,
                          nextButton: null,
                          modeButton: modeButton,
                          onDemandButton: onDemandButton,
                          fullscreenButton: fullscreenButton,
                        ),
                      )
                    : _MithkaVideoOnDemandBottomChrome(
                        scope: scope,
                        buffered: buffered,
                        aspectRatio: aspect,
                        thumbnailProvider: _provideScrubThumbnailAt,
                        title: title,
                        subtitle: subtitle,
                        modeButton: modeButton,
                        onDemandButton: onDemandButton,
                        fullscreenButton: fullscreenButton,
                      ),
              ),
            ],
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fromRect(
                rect: geometry.panelRect,
                child: _MithkaVideoOnDemandPanel(
                  key: const ValueKey('video-on-demand-panel'),
                  queue: queue,
                  wide: geometry.wide,
                  onSelect: widget.onDemandSelect,
                  autoplay:
                      _completionAction == VideoCompletionAction.autoplayNext,
                  onAutoplayChanged: _setOnDemandAutoplay,
                ),
              ),
              ExcludeFocus(
                excluding: !snapshot.controlsVisible,
                child: ExcludeSemantics(
                  excluding: !snapshot.controlsVisible,
                  child: IgnorePointer(
                    ignoring: !snapshot.controlsVisible,
                    child: AnimatedOpacity(
                      key: const ValueKey('mithka-video-player-chrome'),
                      opacity: snapshot.controlsVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 170),
                      child: controls,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _onDemandToggleButton() {
    return KeyedSubtree(
      key: const ValueKey('video-on-demand-toggle'),
      child: _FocusableVideoIconButton(
        icon: HeroAppIcons.listCheck,
        label: AppStrings.t(AppStringKeys.videoPlayerOnDemand),
        onPressed: _toggleOnDemandPanel,
        size: const Size.square(44),
        iconSize: 21,
        backgroundColor: _onDemandPanelVisible
            ? const Color(0xD92C6565)
            : const Color(0x8A1B1D1E),
        borderColor: Colors.white.withValues(
          alpha: _onDemandPanelVisible ? 0.32 : 0.24,
        ),
        expanded: _onDemandPanelVisible,
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

  Widget _playerSurfaceInteraction(
    BuildContext context,
    FVideoChromeScope scope,
    Widget child,
  ) {
    _reusablePlayerActions = scope.actions;
    final controller = _controller;
    Widget surface = child;
    if (scope.snapshot.controlsVisible && _showsOnDemandLayout(context)) {
      final videoChild = surface;
      surface = LayoutBuilder(
        builder: (context, constraints) {
          final geometry = _VideoOnDemandGeometry.resolve(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            safePadding: MediaQuery.paddingOf(context),
            aspectRatio: _resolvedVideoAspectRatio(scope.snapshot.value),
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              if (widget.thumb != null)
                Positioned.fill(
                  child: ClipRect(
                    // Own layer, so the gaussian is not re-recorded each
                    // time the controls or the video surface repaint.
                    child: RepaintBoundary(
                      child: ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(
                          sigmaX: 24,
                          sigmaY: 24,
                        ),
                        child: Transform.scale(
                          scale: 1.12,
                          child: Opacity(
                            opacity: 0.42,
                            child: TDImage(
                              photo: widget.thumb,
                              cornerRadius: 0,
                            ),
                          ),
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
                        Colors.black.withValues(alpha: 0.34),
                        Colors.black.withValues(alpha: 0.12),
                        Colors.black.withValues(alpha: 0.72),
                      ],
                      stops: const [0, 0.48, 1],
                    ),
                  ),
                ),
              ),
              Positioned.fromRect(
                rect: geometry.videoRect,
                child: ClipRRect(
                  key: const ValueKey('video-on-demand-surface'),
                  borderRadius: BorderRadius.circular(geometry.wide ? 12 : 10),
                  child: ColoredBox(
                    color: Colors.black,
                    child: _zoomedPlaybackSurface(
                      child: videoChild,
                      viewport: geometry.videoRect,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    } else if (_usesStandaloneFullscreenLayout(context)) {
      final videoChild = surface;
      surface = Stack(
        key: const ValueKey('video-standalone-surface'),
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          if (widget.thumb != null)
            Positioned.fill(
              child: ClipRect(
                child: RepaintBoundary(
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                    child: Transform.scale(
                      scale: 1.14,
                      child: Opacity(
                        opacity: 0.46,
                        child: TDImage(photo: widget.thumb, cornerRadius: 0),
                      ),
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
                    Colors.black.withValues(alpha: 0.28),
                    Colors.black.withValues(alpha: 0.04),
                    Colors.black.withValues(alpha: 0.48),
                  ],
                  stops: const [0, 0.48, 1],
                ),
              ),
            ),
          ),
          Positioned.fill(child: _fullViewportZoomedSurface(videoChild)),
        ],
      );
    } else {
      surface = _fullViewportZoomedSurface(surface);
    }
    if (_supportsPlaybackGestures && controller != null) {
      surface = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanDown: (details) {
          // DragDownDetails carries where the press landed; the pan only
          // reports its own origin once the press has already rolled past the
          // slop, so the press point has to be kept here.
          _surfacePressOrigin = details.localPosition;
          _surfacePanTravel = Offset.zero;
          if (!_videoZoomSuppressPlaybackGestures) {
            _gestureOrigin = details.localPosition;
          }
        },
        onPanStart: (details) =>
            _startSurfacePanGesture(details, controller, scope.actions),
        onPanUpdate: (details) =>
            _updateSurfacePanGesture(details, controller, scope.actions),
        onPanEnd: (_) => _finishSurfacePanGesture(controller),
        onPanCancel: _cancelSurfacePanGesture,
        // The viewport-wide listener fires long press first; only the
        // darkened player viewport holds to speed up, so a swipe that began
        // on a letterbox band keeps its previous behaviour.
        onLongPressStart: (details) {
          if (_darkenedPlayerViewport.contains(details.localPosition)) {
            _startHeldSpeed(controller);
          }
        },
        onLongPressEnd: (_) => _stopHeldSpeed(),
        child: surface,
      );
      surface = Listener(
        key: const ValueKey('video-dismiss-listener'),
        behavior: HitTestBehavior.translucent,
        onPointerDown: _trackDismissPointerStart,
        onPointerMove: _trackDismissPointerMove,
        // Only the tracked pointer owns the swipe: a second finger lifting
        // must not finish or cancel the first one's drag.
        onPointerUp: (event) {
          if (event.pointer == _dismissPointer) _finishDismissDrag();
        },
        onPointerCancel: (event) {
          if (event.pointer == _dismissPointer) _cancelDismissDrag();
        },
        child: surface,
      );
    }
    return surface;
  }

  Widget _fullViewportZoomedSurface(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport =
            Offset.zero & Size(constraints.maxWidth, constraints.maxHeight);
        return _zoomedPlaybackSurface(child: child, viewport: viewport);
      },
    );
  }

  Widget _zoomedPlaybackSurface({
    required Widget child,
    required Rect viewport,
  }) {
    _videoZoomViewport = viewport;
    _videoZoomOffset = _clampVideoZoomOffset(
      _videoZoomOffset,
      _videoZoomScale,
      viewport.size,
    );
    return ClipRect(
      child: Transform.translate(
        key: const ValueKey('video-zoom-translation'),
        offset: _videoZoomOffset,
        child: Transform.scale(
          key: const ValueKey('video-zoom-transform'),
          scale: _videoZoomScale,
          child: child,
        ),
      ),
    );
  }

  Widget _playerOverlay(BuildContext context, FVideoChromeScope scope) {
    _reusablePlayerActions = scope.actions;
    _syncTouchControlsAutoHide(scope);
    if (_systemPiPActive) {
      return const IgnorePointer(child: SizedBox.expand());
    }
    final controller = _controller;
    final overlay = Stack(
      fit: StackFit.expand,
      children: [
        if (_videoZoomGestureActive) _videoZoomIndicator(),
        if (_gestureIndicatorReady && controller != null)
          _activeGesture == _PlayerGesture.brightness ||
                  _activeGesture == _PlayerGesture.volume
              ? _sideLevelIndicator()
              : _gestureIndicator(controller),
        if (_heldSpeedActive) _heldSpeedIndicator(),
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

  List<FocusNode> get _visiblePlayerMenuFocusNodes {
    if (_moreMenuVisible) {
      return [
        _moreMenuFocusNodes[0],
        _moreMenuFocusNodes[1],
        _moreMenuFocusNodes[2],
        _moreMenuFocusNodes[3],
        if (_showsOrientationButton) _moreMenuFocusNodes[4],
        if (_showsMetadataRow) _moreMenuFocusNodes[5],
      ];
    }
    if (_modeMenuVisible) {
      return [
        for (final mode in _availableDisplayModes) _modeMenuFocusNodes[mode]!,
      ];
    }
    return const [];
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

  void _handleVideoZoomPointerDown(PointerDownEvent event) {
    if (event.kind != ui.PointerDeviceKind.touch) return;
    _videoZoomPointers[event.pointer] = event.localPosition;
    if (_videoZoomPinchPointers.isNotEmpty || _videoZoomPointers.length < 2) {
      return;
    }
    _videoZoomSuppressPlaybackGestures = true;
    _cancelPlaybackGesture();
    _beginVideoPinchFromActivePointers();
  }

  void _handleVideoZoomPointerMove(PointerMoveEvent event) {
    if (event.kind != ui.PointerDeviceKind.touch ||
        !_videoZoomPointers.containsKey(event.pointer)) {
      return;
    }
    _videoZoomPointers[event.pointer] = event.localPosition;
    if (_videoZoomPinchPointers.isEmpty) {
      if (_videoZoomPointers.length >= 2) {
        _beginVideoPinchFromActivePointers();
      }
      return;
    }
    final points = _activeVideoPinchPoints;
    if (points == null) return;
    _updateVideoZoomGesture(
      focalPoint: (points.$1 + points.$2) / 2,
      scaleValue: (points.$1 - points.$2).distance,
    );
    _reusablePlayerActions?.hideControls();
  }

  void _handleVideoZoomPointerEnd(PointerEvent event) {
    if (event.kind != ui.PointerDeviceKind.touch ||
        !_videoZoomPointers.containsKey(event.pointer)) {
      return;
    }
    final endedActivePinch = _videoZoomPinchPointers.contains(event.pointer);
    _videoZoomPointers.remove(event.pointer);
    if (endedActivePinch) {
      _videoZoomPinchPointers = const <int>[];
      _finishVideoZoomGesture();
      if (_videoZoomPointers.length >= 2) {
        _beginVideoPinchFromActivePointers();
      }
    }
    if (_videoZoomPointers.isEmpty) {
      _videoZoomSuppressPlaybackGestures = false;
    }
  }

  void _beginVideoPinchFromActivePointers() {
    if (_videoZoomPointers.length < 2) return;
    final pointers = _videoZoomPointers.keys.take(2).toList(growable: false);
    final first = _videoZoomPointers[pointers[0]]!;
    final second = _videoZoomPointers[pointers[1]]!;
    _videoZoomPinchPointers = pointers;
    _videoZoomSuppressPlaybackGestures = true;
    _beginVideoZoomGesture(
      (first + second) / 2,
      scaleBaseline: math.max((first - second).distance, 1),
    );
    _reusablePlayerActions?.hideControls();
  }

  (Offset, Offset)? get _activeVideoPinchPoints {
    if (_videoZoomPinchPointers.length != 2) return null;
    final first = _videoZoomPointers[_videoZoomPinchPointers[0]];
    final second = _videoZoomPointers[_videoZoomPinchPointers[1]];
    if (first == null || second == null) return null;
    return (first, second);
  }

  // Travel the surface pan has accumulated for the current press, and where
  // that press went down. The pan shares its pointer with the package's tap,
  // so the travel decides whether the release is that tap or a drag; it is
  // measured from the press point because the pan only reports its own origin
  // after the press has already rolled past the slop.
  Offset _surfacePanTravel = Offset.zero;

  Offset? _surfacePressOrigin;

  void _startSurfacePanGesture(
    DragStartDetails details,
    VideoPlayerController controller,
    FVideoActions actions,
  ) {
    if (_videoZoomSuppressPlaybackGestures) return;
    // An edge swipe that is leaving the player never also starts a pan; the
    // package's tap fallback likewise stays out of the release.
    if (_edgeDismissActive || _dismissGestureSettling) {
      _cancelPlaybackGesture();
      return;
    }
    if (_videoZoomScale > _minimumVideoZoomScale) {
      _cancelPlaybackGesture();
      _beginVideoZoomGesture(details.localPosition, scaleBaseline: 1);
      actions.hideControls();
      return;
    }
    _startPlaybackGesture(details.localPosition, controller);
  }

  void _updateSurfacePanGesture(
    DragUpdateDetails details,
    VideoPlayerController controller,
    FVideoActions actions,
  ) {
    if (_videoZoomSuppressPlaybackGestures) return;
    if (_edgeDismissActive) {
      _cancelPlaybackGesture();
      return;
    }
    if (_videoZoomGestureActive && _videoZoomScale > _minimumVideoZoomScale) {
      _updateVideoZoomGesture(focalPoint: details.localPosition, scaleValue: 1);
      actions.hideControls();
      return;
    }
    final press = _surfacePressOrigin;
    if (press != null) _surfacePanTravel = details.localPosition - press;
    _updatePlaybackGesture(details.localPosition, controller);
  }

  void _finishSurfacePanGesture(VideoPlayerController controller) {
    if (_videoZoomSuppressPlaybackGestures) {
      _cancelPlaybackGesture();
      return;
    }
    if (_edgeDismissActive || _dismissGestureSettling) {
      _cancelPlaybackGesture();
      return;
    }
    if (_videoZoomGestureActive) {
      _finishVideoZoomGesture();
      return;
    }
    if (!videoSurfacePanReplacesTap(_surfacePanTravel)) {
      // The pan took the tap on this pointer but never became the deliberate
      // drag a gesture has to be, so the release is that tap. Finish it here:
      // no other recognizer can, and a position step must not be committed.
      _cancelPlaybackGesture();
      _reusablePlayerActions?.toggleControls();
      return;
    }
    _finishPlaybackGesture(controller);
  }

  void _cancelSurfacePanGesture() {
    _surfacePanTravel = Offset.zero;
    _surfacePressOrigin = null;
    if (!_videoZoomSuppressPlaybackGestures && _videoZoomGestureActive) {
      _finishVideoZoomGesture();
      return;
    }
    _cancelPlaybackGesture();
  }

  /// Holding the surface plays up to [videoHeldSpeedRate] until release, then
  /// resumes at the rate playback had before the press.
  ///
  /// Native rate writes are serialized: a hold, its release, a newer hold, an
  /// ordinary speed change and disposal all only move [_heldSpeedDesiredRate],
  /// and [_pumpHeldSpeedWrites] carries that rate to the controller one request
  /// at a time. A held request that is already on the wire cannot be recalled,
  /// but the pump issues the newest rate after it settles, so the final native
  /// rate is the intended one whichever order the futures complete in.
  void _startHeldSpeed(VideoPlayerController controller, {int? pointer}) {
    if (_videoZoomSuppressPlaybackGestures ||
        _videoZoomGestureActive ||
        _videoZoomScale > _minimumVideoZoomScale) {
      return;
    }
    // The controller still reports the held rate while a restore is on the
    // wire, so a press that lands in that window measures the base the player
    // already knows instead of doubling the held rate.
    final pendingWrite =
        _heldSpeedActive ||
        _heldSpeedWriteInFlight ||
        _heldSpeedDesiredRate != null;
    final reported = controller.value.playbackSpeed;
    final current = pendingWrite
        ? _heldSpeedBaseRate
        : reported.isFinite && reported > 0
        ? reported
        : _speed;
    _heldSpeedBaseRate = current;
    final rate = videoHeldSpeedRate(current);
    if (rate < _minimumHeldSpeedRate) return;
    if (!mounted) return;
    _updateState(() {
      _heldSpeedRate = rate;
      _heldSpeedActive = true;
    });
    _reusablePlayerActions?.showControls();
    // The long-press callback carries no pointer id. Its recognizer's primary
    // pointer is the oldest touch still down, which is exactly the first key
    // of the insertion-ordered pinch map; a non-touch hold (mouse) has no
    // entry there and releases through the unconditional path instead.
    _heldSpeedPointer =
        pointer ??
        (_videoZoomPointers.isEmpty ? null : _videoZoomPointers.keys.first);
    _heldSpeedDesiredRate = rate;
    unawaited(_pumpHeldSpeedWrites());
  }

  /// Returns playback to the pre-press rate and clears the badge.
  void _stopHeldSpeed() {
    if (!_heldSpeedActive) return;
    _heldSpeedActive = false;
    _heldSpeedPointer = null;
    if (mounted) _updateState(() {});
    // The pump owns the wire: it lands the base rate behind any held request
    // still in flight instead of racing it.
    _heldSpeedDesiredRate = _heldSpeedBaseRate;
    unawaited(_pumpHeldSpeedWrites());
  }

  /// Ends the hold only when [pointer] is the pointer that owns it.
  ///
  /// The viewport-wide pinch listener sees every touch on the player, so a
  /// second finger lifting (or being cancelled by the system) must not end
  /// the first finger's hold. A hold whose owning pointer was never recorded
  /// (the listener only tracks touch pointers) stays under that listener's
  /// old unconditional end, so a mouse hold is still released by its own up.
  void _stopHeldSpeedForPointer(int pointer) {
    final owner = _heldSpeedPointer;
    if (owner == null) {
      _stopHeldSpeed();
      return;
    }
    if (pointer == owner) _stopHeldSpeed();
  }

  /// [snapshot] with the speed the player keeps instead of the lagging one the
  /// controller reports while a hold's write is still travelling.
  ///
  /// The chrome's speed control steps from this value, so a step taken during
  /// that window moves from the base rate rather than from a held rate the
  /// player is about to replace.
  FVideoChromeSnapshot _chromeSnapshotForKeptRate(
    FVideoChromeSnapshot snapshot,
  ) {
    final reported = snapshot.value.playbackSpeed;
    final kept = _keptPlaybackRate(reported);
    if (kept == reported) return snapshot;
    return FVideoChromeSnapshot(
      value: snapshot.value.copyWith(playbackSpeed: kept),
      playbackState: snapshot.playbackState,
      displayPosition: snapshot.displayPosition,
      controlsVisible: snapshot.controlsVisible,
      isScrubbing: snapshot.isScrubbing,
      bufferingIndicatorVisible: snapshot.bufferingIndicatorVisible,
      isFullscreen: snapshot.isFullscreen,
      volume: snapshot.volume,
      isPictureInPicture: snapshot.isPictureInPicture,
      pictureInPictureRequestPending: snapshot.pictureInPictureRequestPending,
    );
  }

  /// The rate the player keeps, not the one still travelling to the platform.
  double _keptPlaybackRate(double reported) {
    if (_heldSpeedActive ||
        _heldSpeedWriteInFlight ||
        _heldSpeedDesiredRate != null) {
      return _heldSpeedBaseRate;
    }
    return reported.isFinite && reported > 0 ? reported : _heldSpeedBaseRate;
  }

  /// Applies an ordinary speed change (the chrome's speed menu).
  ///
  /// The request supersedes a pending held rate, exactly as the newest desired
  /// rate rule requires, and is dropped while a hold runs because the press
  /// owns playback for its duration.
  Future<void> _applyPlaybackSpeedRate(double rate) async {
    if (!rate.isFinite || rate <= 0) return;
    _heldSpeedBaseRate = rate;
    if (!_heldSpeedActive) _heldSpeedDesiredRate = rate;
    await _pumpHeldSpeedWrites();
  }

  /// Carries [_heldSpeedDesiredRate] to the controller.
  ///
  /// Only one request is in flight at a time. The loop re-reads the desired
  /// rate after every completion, so a release (or a newer hold) that lands
  /// while an earlier rate is still travelling issues its own write after
  /// that future settles. The write that settles with nothing newer waiting
  /// is the rate the player keeps, and refreshing the base from the
  /// controller's reported value makes that the last write _speed shows.
  Future<void> _pumpHeldSpeedWrites() async {
    if (_heldSpeedWriteInFlight) return;
    final controller = _controller;
    if (controller == null) return;
    _heldSpeedWriteInFlight = true;
    try {
      while (!_heldSpeedDisposed && mounted) {
        final rate = _heldSpeedDesiredRate;
        if (rate == null) break;
        try {
          await controller.setPlaybackSpeed(rate);
          _heldSpeedConsecutiveFailures = 0;
        } catch (_) {
          // A route that closes mid-hold owns a released controller; the
          // hold is over either way. While the widget still lives, the
          // failed write cannot leave a queued restore stranded behind a
          // pump that already returned: drop the failed rate, queue the
          // restore exactly once when this failure was a held rate, and let
          // the loop's tail (or a later ordinary speed change) carry it.
          // A failing restore gives up after the bound: no retry loop, and
          // the remembered/displayed base keeps the last rate the UI meant.
          if (!mounted) return;
          _heldSpeedActive = false;
          _heldSpeedPointer = null;
          if (mounted) _updateState(() {});
          _heldSpeedConsecutiveFailures++;
          final restore = _heldSpeedBaseRate;
          if (_heldSpeedConsecutiveFailures >=
              _heldSpeedMaxConsecutiveFailures) {
            _heldSpeedDesiredRate = null;
            return;
          }
          _heldSpeedDesiredRate = restore;
          continue;
        }
        if (_heldSpeedDisposed || !mounted) return;
        // Nothing newer is waiting: the write that just settled is the rate
        // the player keeps. A hold keeps the base its press measured, so only
        // a write issued outside a hold moves the base and the test hooks.
        if (_heldSpeedDesiredRate == rate) {
          _heldSpeedDesiredRate = null;
          if (!_heldSpeedActive) {
            final applied = controller.value.playbackSpeed;
            final base = applied.isFinite && applied > 0 ? applied : rate;
            _heldSpeedBaseRate = base;
            VideoPlayerView.debugLastBaseSpeed = base;
            debugVideoPlayerBaseSpeed = base;
          }
        }
      }
    } finally {
      _heldSpeedWriteInFlight = false;
    }
    // A rate that arrived while this pump was unwinding still has to land.
    // The flag now reads false, so this call is the one that picks the rate
    // up; a caller that finds the flag set in turn relies on this tail.
    if (!_heldSpeedDisposed && mounted && _heldSpeedDesiredRate != null) {
      unawaited(_pumpHeldSpeedWrites());
    }
  }

  void _cancelHeldSpeed() {
    _heldSpeedActive = false;
    _heldSpeedPointer = null;
    _heldSpeedDesiredRate = null;
    _heldSpeedBaseRate = _speed;
  }

  Widget _heldSpeedIndicator() {
    return Center(
      child: IgnorePointer(
        child: Semantics(
          liveRegion: true,
          label: AppStrings.t(AppStringKeys.videoPlayerHoldPlaybackSpeed),
          value: formatVideoPlayerSpeed(_heldSpeedRate),
          child: Container(
            key: const ValueKey('video-held-speed-indicator'),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.76),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppIcon(
                  HeroAppIcons.flash,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  formatVideoPlayerSpeed(_heldSpeedRate),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    AppStringKeys.videoPlayerHoldPlaybackSpeed.l10n(context),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 13,
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

  void _trackDismissPointerStart(PointerDownEvent event) {
    if (_videoZoomSuppressPlaybackGestures ||
        _videoZoomGestureActive ||
        _dismissPointer != null) {
      return;
    }
    _dismissSettlerGeneration++;
    _dismissGestureSettling = false;
    _dismissPointer = event.pointer;
    _dismissTrackedDx = 0;
    _dismissTrackedDy = 0;
    _dismissDx = 0;
    _edgeDismissActive = false;
    final width = MediaQuery.sizeOf(context).width;
    _edgeDismissCandidate =
        width > 0 && event.localPosition.dx <= videoDismissEdgeWidth;
  }

  void _trackDismissPointerMove(PointerMoveEvent event) {
    if (event.pointer != _dismissPointer) return;
    _dismissTrackedDx += event.delta.dx;
    _dismissTrackedDy += event.delta.dy;
    if (!_edgeDismissCandidate) return;
    if (!_edgeDismissActive) {
      final dx = _dismissTrackedDx;
      // A downward drag from the same band belongs to the vertical gesture,
      // so this only claims movement that reads as a sideways swipe.
      if (dx < _dismissIntentDistance ||
          dx.abs() <= _dismissTrackedDy.abs() * 1.2) {
        return;
      }
      _edgeDismissActive = true;
      _cancelPlaybackGesture();
      _stopHeldSpeed();
    }
    if (!mounted) return;
    _updateState(() => _dismissDx = math.max(0.0, _dismissTrackedDx));
  }

  void _finishDismissDrag() {
    if (_dismissPointer == null) return;
    final dx = _dismissDx;
    final active = _edgeDismissActive;
    _dismissPointer = null;
    _edgeDismissCandidate = false;
    _edgeDismissActive = false;
    _dismissTrackedDx = 0;
    _dismissTrackedDy = 0;
    if (dx != 0 && mounted) _updateState(() => _dismissDx = 0);
    if (!active) return;
    if (dx >= videoDismissDragDistance) {
      _close();
      return;
    }
    // An abandoned swipe must not finish as a tap on the surface beneath it.
    // The settling window belongs to this gesture: a newer press or a
    // cancellation ends it early instead of leaving the surface inert.
    _dismissGestureSettling = true;
    final generation = ++_dismissSettlerGeneration;
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (!mounted || generation != _dismissSettlerGeneration) return;
      _updateState(() => _dismissGestureSettling = false);
    });
  }

  void _cancelDismissDrag() {
    _dismissSettlerGeneration++;
    _dismissGestureSettling = false;
    _dismissPointer = null;
    _edgeDismissCandidate = false;
    _edgeDismissActive = false;
    _dismissTrackedDx = 0;
    _dismissTrackedDy = 0;
    if (_dismissDx != 0 && mounted) _updateState(() => _dismissDx = 0);
  }

  void _beginVideoZoomGesture(
    Offset focalPoint, {
    required double scaleBaseline,
  }) {
    final viewport = _resolvedVideoZoomViewport;
    final localFocalPoint = focalPoint - viewport.topLeft;
    final center = viewport.size.center(Offset.zero);
    _videoZoomGestureStartScale = _videoZoomScale;
    _videoZoomGestureScaleBaseline = math.max(scaleBaseline, 0.0001);
    _videoZoomGestureContentAnchor =
        (localFocalPoint - center - _videoZoomOffset) / _videoZoomScale;
    if (mounted) {
      _updateState(() => _videoZoomGestureActive = true);
    }
  }

  void _updateVideoZoomGesture({
    required Offset focalPoint,
    required double scaleValue,
  }) {
    if (!_videoZoomGestureActive) return;
    final viewport = _resolvedVideoZoomViewport;
    final scale =
        (_videoZoomGestureStartScale *
                scaleValue /
                _videoZoomGestureScaleBaseline)
            .clamp(_minimumVideoZoomScale, _maximumVideoZoomScale)
            .toDouble();
    final localFocalPoint = focalPoint - viewport.topLeft;
    final center = viewport.size.center(Offset.zero);
    final offset =
        localFocalPoint - center - _videoZoomGestureContentAnchor * scale;
    final clampedOffset = _clampVideoZoomOffset(offset, scale, viewport.size);
    if (!mounted) return;
    _updateState(() {
      _videoZoomScale = scale;
      _videoZoomOffset = clampedOffset;
    });
  }

  void _finishVideoZoomGesture() {
    if (!mounted) return;
    _updateState(() {
      _videoZoomGestureActive = false;
      if (_videoZoomScale <= _videoZoomResetThreshold) {
        _videoZoomScale = _minimumVideoZoomScale;
        _videoZoomOffset = Offset.zero;
      } else {
        _videoZoomOffset = _clampVideoZoomOffset(
          _videoZoomOffset,
          _videoZoomScale,
          _resolvedVideoZoomViewport.size,
        );
      }
    });
  }

  Rect get _resolvedVideoZoomViewport {
    if (!_videoZoomViewport.isEmpty) return _videoZoomViewport;
    return Offset.zero & MediaQuery.sizeOf(context);
  }

  Offset _clampVideoZoomOffset(Offset offset, double scale, Size viewport) {
    if (scale <= _minimumVideoZoomScale || viewport.isEmpty) {
      return Offset.zero;
    }
    final maximumX = viewport.width * (scale - 1) / 2;
    final maximumY = viewport.height * (scale - 1) / 2;
    return Offset(
      offset.dx.clamp(-maximumX, maximumX).toDouble(),
      offset.dy.clamp(-maximumY, maximumY).toDouble(),
    );
  }

  void _startPlaybackGesture(
    Offset localPosition,
    VideoPlayerController controller,
  ) {
    _gestureOrigin ??= localPosition;
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
    Offset localPosition,
    VideoPlayerController controller,
  ) {
    final origin = _gestureOrigin;
    if (origin == null) return;
    final delta = localPosition - origin;
    final size = MediaQuery.sizeOf(context);
    var gesture = _activeGesture;
    if (gesture == null) {
      if (!videoPlaybackPanEngages(delta)) return;
      // A gesture has engaged, so the chrome should be up while it runs. A pan
      // that never reaches this point stays a tap and leaves the chrome alone.
      _reusablePlayerActions?.showControls();
      final horizontal =
          delta.dx.abs() >= delta.dy.abs() * _playbackGestureAxisLockRatio;
      final vertical =
          delta.dy.abs() >= delta.dx.abs() * _playbackGestureAxisLockRatio;
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
    _updateState(() => _activeGesture = gesture);
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
    _updateState(() {
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
    _updateState(() {
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
    _updateState(() => _gestureValue = current.fraction);
  }

  void _finishPlaybackGesture(VideoPlayerController controller) {
    final gesture = _activeGesture;
    if (gesture == null) {
      // Nothing engaged: the pan was a press that never became a gesture.
      _cancelPlaybackGesture();
      _reusablePlayerActions?.showControls();
      return;
    }
    if (gesture == _PlayerGesture.seek) {
      unawaited(_seekTo(controller, _gestureSeekPosition));
    } else if (gesture == _PlayerGesture.skipTenSeconds &&
        _gestureNavigationDelta != 0) {
      unawaited(_seekTo(controller, _gestureSeekPosition));
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

  Future<void> _seekTo(
    VideoPlayerController controller,
    Duration position,
  ) async {
    try {
      await controller.seekTo(position);
    } catch (_) {
      // The route can close between the release and this commit.
    }
  }

  void _cancelPlaybackGesture() {
    _gestureVolumeRequestGeneration++;
    if (!mounted) return;
    _updateState(() {
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

  Widget _videoZoomIndicator() {
    final percentage = (_videoZoomScale * 100).round();
    return Center(
      child: IgnorePointer(
        child: Semantics(
          liveRegion: true,
          label: AppStrings.t(AppStringKeys.videoPlayerVideoZoom),
          value: '$percentage%',
          child: Container(
            key: const ValueKey('video-zoom-indicator'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: Text(
              '${_videoZoomScale.toStringAsFixed(1)}×',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w400,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }

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
                  fontWeight: FontWeight.w400,
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
                    fontWeight: FontWeight.w400,
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
                        fontWeight: FontWeight.w400,
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
                                      fontWeight: FontWeight.w400,
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

  /// Shares the photo gallery's preference for its metadata row. A player
  /// hosted outside the app's providers has no preference to read, so the row
  /// stays hidden rather than guessing one. The focus traversal reads this too:
  /// a node whose item is not rendered would swallow an arrow key.
  bool get _showsMetadataRow =>
      Provider.of<ThemeController?>(
        context,
        listen: false,
      )?.mediaMetadataEnabled ??
      false;

  Widget _moreMenuOverlay({required VoidCallback onTapOutside}) => Builder(
    builder: (context) =>
        _buildMoreMenuOverlay(context, onTapOutside: onTapOutside),
  );

  Widget _buildMoreMenuOverlay(
    BuildContext context, {
    required VoidCallback onTapOutside,
  }) {
    final media = MediaQuery.of(context);
    final phoneFullscreen = media.size.shortestSide < 600;
    final showMetadata = context.select<ThemeController?, bool>(
      (theme) => theme?.mediaMetadataEnabled ?? false,
    );
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
                                    icon: _isDesktopPlatform
                                        ? HeroAppIcons.folder
                                        : HeroAppIcons.image,
                                    label:
                                        (_isDesktopPlatform
                                                ? AppStringKeys
                                                      .messageActionSaveAs
                                                : AppStringKeys
                                                      .messageActionSaveToPhotos)
                                            .l10n(context),
                                    focusNode: _moreMenuFocusNodes[1],
                                    onPressed: () => _runMoreMenuAction(
                                      () => unawaited(_saveVideo()),
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
                                const _VideoMenuSeparator(),
                                KeyedSubtree(
                                  key: const ValueKey('video-more-speed'),
                                  child: _FocusableVideoMenuItem(
                                    icon: HeroAppIcons.clock,
                                    label:
                                        '${AppStringKeys.videoPlayerPlaybackSpeed.l10n(context)} '
                                        '${_formatPlaybackSpeed(_keptPlaybackRate(_controller?.value.playbackSpeed ?? _speed))}',
                                    focusNode: _moreMenuFocusNodes[3],
                                    onPressed: () {
                                      final current = _keptPlaybackRate(
                                        _controller?.value.playbackSpeed ??
                                            _speed,
                                      );
                                      final actions = _reusablePlayerActions;
                                      actions?.showControls();
                                      unawaited(
                                        _applyPlaybackSpeedRate(
                                          _nextPlaybackSpeed(current),
                                        ),
                                      );
                                    },
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
                                      focusNode: _moreMenuFocusNodes[4],
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
                                if (showMetadata) ...[
                                  const _VideoMenuSeparator(),
                                  KeyedSubtree(
                                    key: const ValueKey('video-more-metadata'),
                                    child: _FocusableVideoMenuItem(
                                      icon: HeroAppIcons.circleInfo,
                                      label: AppStringKeys.mediaMetadataViewInfo
                                          .l10n(context),
                                      focusNode: _moreMenuFocusNodes[5],
                                      onPressed: () => _runMoreMenuAction(
                                        _showMediaMetadata,
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

  /// The player must look the same from the moment it opens, so the chrome is
  /// drawn over the loading placeholder instead of appearing only once the
  /// first frame decodes. Playback commands stay inert until the controller is
  /// initialized; close, the menus and the display mode already work.
  Widget _loadingSurface() {
    if (widget.presentation != VideoPlayerPresentation.fullscreen || _failed) {
      return _loadingState();
    }
    final scope = _loadingChromeScope();
    return Stack(
      fit: StackFit.expand,
      children: [
        _loadingPlaceholder(),
        // The package player owns surface taps once it is mounted. Until then
        // this layer keeps controls that were tapped away recoverable.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: () => _handleLoadingSurfaceTap(scope),
          ),
        ),
        _playerChrome(context, scope),
        _playerOverlay(context, scope),
      ],
    );
  }

  /// Loading artwork without chrome: the thumbnail or a dark box, plus the
  /// spinner, or the retry action once playback failed.
  Widget _loadingPlaceholder() {
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
      ],
    );
  }

  Widget _loadingState() {
    return Stack(
      fit: StackFit.expand,
      children: [
        _loadingPlaceholder(),
        PositionedDirectional(
          top: topChromeInsetOf(context) + 6,
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
      isMobilePlatform;

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

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}
