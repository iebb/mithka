import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import 'video_slider.dart';
import 'video_source.dart';
import 'video_thumbnail.dart';

typedef MithkaVideoControllerBuilder =
    FutureOr<VideoPlayerController> Function(MithkaVideoSource source);

typedef MithkaVideoPlayerLoadingBuilder = Widget Function(BuildContext context);

typedef MithkaVideoPlayerErrorBuilder =
    Widget Function(
      BuildContext context,
      MithkaVideoPlayerError error,
      VoidCallback? retry,
    );

typedef MithkaVideoSurfaceBuilder =
    Widget Function(BuildContext context, VideoPlayerController controller);

typedef MithkaVideoScrubPreviewBuilder =
    Widget Function(
      BuildContext context,
      Uint8List? imageBytes,
      Duration position,
    );

typedef MithkaVideoPlayerErrorCallback =
    void Function(MithkaVideoPlayerError error);

typedef MithkaVideoRetryCallback = FutureOr<void> Function();

typedef MithkaVideoChromeBuilder =
    Widget Function(BuildContext context, MithkaVideoChromeScope scope);

/// Builds an action or inline menu at the safe-area-aware top-trailing edge of
/// the package's default chrome.
///
/// The returned widget should have finite intrinsic dimensions and must not be
/// a [Positioned] widget; the player owns its placement. It remains inside the
/// default chrome's focus, semantics, visibility, and pointer lifecycle.
typedef MithkaVideoTopTrailingBuilder =
    Widget Function(BuildContext context, MithkaVideoChromeScope scope);

/// Requests a host-owned picture-in-picture presentation change.
///
/// The package deliberately does not select a platform PiP implementation.
/// Hosts can bridge this callback to AVPictureInPictureController, Android
/// picture-in-picture, a desktop mini-player, or another presentation service.
typedef MithkaVideoPictureInPictureChanged =
    FutureOr<void> Function(bool pictureInPicture);

/// Visual configuration for the dependency-free default player chrome.
///
/// Defaults use high-contrast transport surfaces that remain legible over
/// bright or rapidly changing video without Material, Cupertino, or icon-font
/// dependencies.
@immutable
class MithkaVideoChromeStyle {
  const MithkaVideoChromeStyle({
    this.foregroundColor = const Color(0xFFFFFFFF),
    this.transportBackgroundColor = const Color(0xCC000000),
    this.primaryTransportBackgroundColor = const Color(0xE6000000),
    this.transportBorderColor = const Color(0x66FFFFFF),
    this.transportBorderWidth = 1,
    this.transportShadowColor = const Color(0xB3000000),
    this.transportShadowBlurRadius = 12,
    this.transportShadowOffset = const Offset(0, 3),
    this.focusColor = const Color(0xFFFFFFFF),
    this.hoverColor = const Color(0x26FFFFFF),
    this.topScrimColor = const Color(0x80000000),
    this.bottomScrimColor = const Color(0xE0000000),
    this.bufferedTrackColor = const Color(0xB3FFFFFF),
    this.inactiveTrackColor = const Color(0x66FFFFFF),
    this.compactTransportButtonSize = 44,
    this.compactPrimaryTransportButtonSize = 56,
    this.wideTransportButtonSize = 56,
    this.widePrimaryTransportButtonSize = 68,
    this.compactTransportSpacing = 8,
    this.wideTransportSpacing = 12,
  }) : assert(
         transportBorderWidth >= 0 && transportBorderWidth < double.infinity,
       ),
       assert(
         transportShadowBlurRadius >= 0 &&
             transportShadowBlurRadius < double.infinity,
       ),
       assert(
         compactTransportButtonSize >= 44 &&
             compactTransportButtonSize < double.infinity,
       ),
       assert(
         compactPrimaryTransportButtonSize >= 44 &&
             compactPrimaryTransportButtonSize < double.infinity,
       ),
       assert(
         wideTransportButtonSize >= 44 &&
             wideTransportButtonSize < double.infinity,
       ),
       assert(
         widePrimaryTransportButtonSize >= 44 &&
             widePrimaryTransportButtonSize < double.infinity,
       ),
       assert(
         compactTransportSpacing >= 0 &&
             compactTransportSpacing < double.infinity,
       ),
       assert(
         wideTransportSpacing >= 0 && wideTransportSpacing < double.infinity,
       );

  /// Glyph, time-label, and volume-track foreground.
  final Color foregroundColor;

  /// Filled background for secondary previous/next transports.
  final Color transportBackgroundColor;

  /// Filled background for the primary play/pause transport.
  final Color primaryTransportBackgroundColor;

  /// Border shared by filled transport buttons.
  final Color transportBorderColor;
  final double transportBorderWidth;

  /// Shadow shared by filled transport buttons.
  final Color transportShadowColor;
  final double transportShadowBlurRadius;
  final Offset transportShadowOffset;

  /// Focus ring and pointer-hover wash for default controls.
  final Color focusColor;
  final Color hoverColor;

  /// Chrome gradient endpoints over the video surface.
  final Color topScrimColor;
  final Color bottomScrimColor;

  /// Secondary timeline track colors.
  final Color bufferedTrackColor;
  final Color inactiveTrackColor;

  /// Center-transport dimensions for compact player layouts.
  final double compactTransportButtonSize;
  final double compactPrimaryTransportButtonSize;

  /// Center-transport dimensions for wide player layouts.
  final double wideTransportButtonSize;
  final double widePrimaryTransportButtonSize;

  /// Gaps between center transports in compact and wide layouts.
  final double compactTransportSpacing;
  final double wideTransportSpacing;
}

enum MithkaVideoLifecycleBehavior {
  pauseAndResume,
  pause,
  delegateToController,
}

/// Selects whether the player or a custom chrome owns surface gestures.
enum MithkaVideoInteractionMode {
  /// Enables the built-in tap, touch double-tap, and desktop double-click
  /// behavior.
  builtIn,

  /// Leaves surface pointer gestures to [MithkaVideoPlayer.chromeBuilder].
  ///
  /// Focus, keyboard shortcuts, pointer-wheel volume, playback state, the
  /// video surface, buffering feedback, and captions remain player-owned.
  delegateToChrome,
}

enum MithkaVideoPlaybackState {
  initializing,
  ready,
  playing,
  paused,
  buffering,
  completed,
  failed,
}

/// Playback commands available to custom player chrome.
///
/// The facade never transfers ownership of the underlying video controller.
/// Calls made after the player is disposed are safe no-ops.
abstract interface class MithkaVideoActions {
  Future<void> togglePlayback();

  Future<void> seekTo(Duration position);

  Future<void> seekBy(Duration delta);

  Future<void> setVolume(double volume);

  Future<void> toggleMute();

  Future<void> setPlaybackSpeed(double speed);

  void showControls();

  void hideControls();

  void toggleControls();

  void requestFullscreen(bool fullscreen);

  /// Requests that the host enter or leave picture-in-picture.
  ///
  /// Concurrent requests are coalesced until the host callback completes.
  Future<void> requestPictureInPicture(bool pictureInPicture);

  void beginScrub(double fraction);

  void updateScrub(double fraction);

  Future<void> endScrub(double fraction);
}

/// Immutable playback state supplied to [MithkaVideoChromeBuilder].
@immutable
class MithkaVideoChromeSnapshot {
  const MithkaVideoChromeSnapshot({
    required this.value,
    required this.playbackState,
    required this.displayPosition,
    required this.controlsVisible,
    required this.isScrubbing,
    required this.bufferingIndicatorVisible,
    required this.isFullscreen,
    this.isPictureInPicture = false,
    this.pictureInPictureRequestPending = false,
  });

  final VideoPlayerValue value;
  final MithkaVideoPlaybackState playbackState;
  final Duration displayPosition;
  final bool controlsVisible;
  final bool isScrubbing;
  final bool bufferingIndicatorVisible;
  final bool isFullscreen;
  final bool isPictureInPicture;
  final bool pictureInPictureRequestPending;
}

/// Immutable dependencies supplied to custom player chrome.
@immutable
class MithkaVideoChromeScope {
  const MithkaVideoChromeScope({
    required this.snapshot,
    required this.actions,
    required this.labels,
    required this.previous,
    required this.next,
  });

  final MithkaVideoChromeSnapshot snapshot;
  final MithkaVideoActions actions;
  final MithkaVideoPlayerLabels labels;

  /// Requests the previous item, or is null when the host has no such action.
  final VoidCallback? previous;

  /// Requests the next item, or is null when the host has no such action.
  final VoidCallback? next;
}

class MithkaVideoPlayerError implements Exception {
  const MithkaVideoPlayerError(this.message, {this.cause, this.stackTrace});

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => message;
}

class MithkaVideoPlayerLabels {
  const MithkaVideoPlayerLabels({
    this.play = 'Play',
    this.pause = 'Pause',
    this.previous = 'Previous video',
    this.next = 'Next video',
    this.mute = 'Mute',
    this.unmute = 'Unmute',
    this.fullscreen = 'Fullscreen',
    this.exitFullscreen = 'Exit fullscreen',
    this.pictureInPicture = 'Picture in picture',
    this.exitPictureInPicture = 'Exit picture in picture',
    this.close = 'Close',
    this.loading = 'Loading video',
    this.buffering = 'Buffering',
    this.failed = 'This video could not be played',
    this.retry = 'Retry',
    this.speed = 'Playback speed',
    this.video = 'Video player',
    this.position = 'Playback position',
    this.volume = 'Volume',
    this.live = 'Live',
  });

  final String play;
  final String pause;
  final String previous;
  final String next;
  final String mute;
  final String unmute;
  final String fullscreen;
  final String exitFullscreen;
  final String pictureInPicture;
  final String exitPictureInPicture;
  final String close;
  final String loading;
  final String buffering;
  final String failed;
  final String retry;
  final String speed;
  final String video;
  final String position;
  final String volume;
  final String live;
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
    this.initialVolume,
    this.initialPlaybackSpeed,
    this.initialPosition,
    this.onClose,
    this.onToggleFullscreen,
    this.onReady,
    this.onEnded,
    this.onPrevious,
    this.onNext,
    this.onPositionChanged,
    this.onPlaybackStateChanged,
    this.onError,
    this.onRetry,
    this.onFullscreenChanged,
    this.onPictureInPictureChanged,
    this.labels = const MithkaVideoPlayerLabels(),
    this.chromeStyle = const MithkaVideoChromeStyle(),
    this.accentColor = const Color(0xFFFFFFFF),
    this.backgroundColor = const Color(0xFF000000),
    this.controller,
    this.controllerBuilder,
    this.lifecycleBehavior = MithkaVideoLifecycleBehavior.pauseAndResume,
    this.controlsAutoHideDuration = const Duration(seconds: 3),
    this.positionUpdateInterval = const Duration(milliseconds: 100),
    this.bufferingIndicatorDelay = const Duration(milliseconds: 250),
    this.seekInterval = const Duration(seconds: 10),
    this.volumeStep = 0.05,
    this.playbackSpeeds = const [0.5, 0.75, 1, 1.25, 1.5, 2],
    this.autofocus = false,
    this.focusNode,
    this.enableKeyboardShortcuts = true,
    this.enableScrollVolume = false,
    this.interactionMode = MithkaVideoInteractionMode.builtIn,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.captionsEnabled = true,
    this.captionStyle = const TextStyle(
      color: Color(0xFFFFFFFF),
      fontSize: 16,
      fontWeight: FontWeight.w600,
      shadows: [Shadow(color: Color(0xFF000000), blurRadius: 4)],
    ),
    this.showScrubPreview = true,
    this.thumbnailProvider,
    this.loadingBuilder,
    this.errorBuilder,
    this.videoSurfaceBuilder,
    this.scrubPreviewBuilder,
    this.chromeBuilder,
    this.topTrailingBuilder,
    this.isFullscreen = false,
    this.isPictureInPicture = false,
  }) : assert(controller == null || controllerBuilder == null),
       assert(
         initialVolume == null || initialVolume >= 0 && initialVolume <= 1,
       ),
       assert(initialPlaybackSpeed == null || initialPlaybackSpeed > 0),
       assert(volumeStep > 0 && volumeStep <= 1);

  final MithkaVideoSource source;
  final int? width;
  final int? height;
  final bool autoplay;
  final bool looping;
  final bool initialMuted;
  final double? initialVolume;
  final double? initialPlaybackSpeed;
  final Duration? initialPosition;
  final VoidCallback? onClose;
  final VoidCallback? onToggleFullscreen;
  final ValueChanged<VideoPlayerController>? onReady;
  final VoidCallback? onEnded;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<Duration>? onPositionChanged;
  final ValueChanged<MithkaVideoPlaybackState>? onPlaybackStateChanged;
  final MithkaVideoPlayerErrorCallback? onError;
  final MithkaVideoRetryCallback? onRetry;
  final ValueChanged<bool>? onFullscreenChanged;

  /// Requests a host-owned picture-in-picture presentation change.
  ///
  /// The callback may be asynchronous. Rebuild with [isPictureInPicture]
  /// after the platform transition succeeds; failed requests can throw and
  /// are reported through [onError] as non-fatal command errors.
  final MithkaVideoPictureInPictureChanged? onPictureInPictureChanged;
  final MithkaVideoPlayerLabels labels;

  /// Visual configuration for the package's default ready chrome.
  ///
  /// This has no effect when [chromeBuilder] replaces that chrome.
  final MithkaVideoChromeStyle chromeStyle;
  final Color accentColor;
  final Color backgroundColor;

  /// Optional preconfigured controller, primarily for custom platform backends.
  /// The caller retains ownership when supplied. A caller-owned controller's
  /// [VideoPlayerOptions.allowBackgroundPlayback] cannot be changed here, so it
  /// must be configured consistently with [lifecycleBehavior] before it is
  /// initialized.
  final VideoPlayerController? controller;

  /// Asynchronously creates a controller and transfers its ownership here.
  /// For either player-owned lifecycle policy, builders should create their
  /// controller with `allowBackgroundPlayback: true` so this widget is the only
  /// lifecycle observer. Changing [lifecycleBehavior] recreates a builder-owned
  /// controller.
  final MithkaVideoControllerBuilder? controllerBuilder;

  /// Selects which layer owns foreground/background playback transitions.
  ///
  /// Changing this value recreates source- and builder-owned controllers. It
  /// cannot replace a caller-owned [controller], whose construction options
  /// remain the caller's responsibility.
  final MithkaVideoLifecycleBehavior lifecycleBehavior;
  final Duration controlsAutoHideDuration;
  final Duration positionUpdateInterval;
  final Duration bufferingIndicatorDelay;
  final Duration seekInterval;
  final double volumeStep;
  final List<double> playbackSpeeds;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool enableKeyboardShortcuts;
  final bool enableScrollVolume;
  final MithkaVideoInteractionMode interactionMode;
  final BoxFit fit;
  final AlignmentGeometry alignment;
  final bool captionsEnabled;
  final TextStyle captionStyle;
  final bool showScrubPreview;
  final MithkaVideoThumbnailProvider? thumbnailProvider;
  final MithkaVideoPlayerLoadingBuilder? loadingBuilder;
  final MithkaVideoPlayerErrorBuilder? errorBuilder;
  final MithkaVideoSurfaceBuilder? videoSurfaceBuilder;
  final MithkaVideoScrubPreviewBuilder? scrubPreviewBuilder;
  final MithkaVideoChromeBuilder? chromeBuilder;

  /// Adds an action or inline menu to the default chrome's top-trailing edge.
  ///
  /// This is ignored when [chromeBuilder] replaces the entire ready chrome.
  final MithkaVideoTopTrailingBuilder? topTrailingBuilder;
  final bool isFullscreen;

  /// The host-confirmed picture-in-picture state.
  ///
  /// This value drives default/custom chrome state and does not itself start a
  /// platform transition.
  final bool isPictureInPicture;

  @override
  State<MithkaVideoPlayer> createState() => _MithkaVideoPlayerState();
}

class _MithkaVideoPlayerState extends State<MithkaVideoPlayer>
    with WidgetsBindingObserver {
  static const _previewDebounceDuration = Duration(milliseconds: 200);
  static const _previewRequestTimeout = Duration(seconds: 2);
  static const _previewBucketDuration = Duration(seconds: 1);

  VideoPlayerController? _controller;
  Timer? _hideTimer;
  Timer? _previewTimer;
  Timer? _previewTimeoutTimer;
  Timer? _positionRefreshTimer;
  Timer? _bufferingTimer;
  bool _controlsVisible = true;
  bool _initializing = true;
  bool _retrying = false;
  bool _showBuffering = false;
  bool _ended = false;
  bool _ownsController = false;
  bool _scrubActive = false;
  bool _resumeAfterScrub = false;
  bool _resumeAfterLifecycle = false;
  bool _controlsHaveFocus = false;
  bool _accessibleNavigation = false;
  bool _pictureInPictureRequestPending = false;
  double _volume = 1;
  double _lastAudibleVolume = 1;
  double _speed = 1;
  MithkaVideoPlayerError? _error;
  MithkaVideoPlaybackState? _playbackState;
  Duration? _scrubPosition;
  VideoPlayerController? _scrubController;
  Uint8List? _previewBytes;
  int _previewGeneration = 0;
  bool _previewLoading = false;
  bool _previewTimedOut = false;
  Completer<Uint8List?>? _previewWaiter;
  int? _pendingPreviewBucket;
  VideoPlayerValue? _lastRenderedValue;
  Duration _lastReportedPosition = Duration.zero;
  int _controllerGeneration = 0;
  int _scrubGeneration = 0;
  int _scrubCommitGeneration = 0;
  Future<void> _scrubPause = Future.value();
  Future<void> _lifecyclePause = Future.value();
  AppLifecycleState _lifecycleState =
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
  PointerDeviceKind? _lastPointerKind;
  final Map<int, Uint8List> _previewCache = {};
  FocusNode? _internalFocusNode;
  late final MithkaVideoActions _actions;

  FocusNode get _focusNode =>
      widget.focusNode ??
      (_internalFocusNode ??= FocusNode(debugLabel: 'mithka-video-player'));

  EdgeInsets get _fullscreenSafePadding => widget.isFullscreen
      ? MediaQuery.maybeOf(context)?.padding ?? EdgeInsets.zero
      : EdgeInsets.zero;

  @override
  void initState() {
    super.initState();
    _actions = _MithkaVideoActions(this);
    _validateConfiguration();
    WidgetsBinding.instance.addObserver(this);
    _volume = widget.initialMuted ? 0 : widget.initialVolume ?? 1;
    _lastAudibleVolume = widget.initialMuted ? 1 : _volume;
    _speed = widget.initialPlaybackSpeed ?? 1;
    unawaited(_replaceController(rebuild: false));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final accessibleNavigation =
        MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;
    if (_accessibleNavigation == accessibleNavigation) return;
    _accessibleNavigation = accessibleNavigation;
    if (accessibleNavigation) {
      _hideTimer?.cancel();
      _controlsVisible = true;
    } else {
      _scheduleHide();
    }
  }

  @override
  void didUpdateWidget(covariant MithkaVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _validateConfiguration();
    if (oldWidget.source != widget.source ||
        oldWidget.thumbnailProvider != widget.thumbnailProvider) {
      _resetPreviewState();
    }
    final controllerInputChanged =
        oldWidget.controller != widget.controller ||
        (widget.controller == null &&
            (oldWidget.source != widget.source ||
                oldWidget.controllerBuilder != widget.controllerBuilder ||
                oldWidget.lifecycleBehavior != widget.lifecycleBehavior));
    if (controllerInputChanged) {
      unawaited(_replaceController());
      return;
    }
    if (oldWidget.lifecycleBehavior != widget.lifecycleBehavior &&
        widget.controller != null) {
      _resumeAfterLifecycle = false;
    }
    final controller = _controller;
    if (controller != null && oldWidget.looping != widget.looping) {
      unawaited(_runCommand(() => controller.setLooping(widget.looping)));
    }
  }

  Future<void> _replaceController({bool rebuild = true}) async {
    final generation = ++_controllerGeneration;
    _resetScrubSession(clearPreviewCache: true);
    _hideTimer?.cancel();
    _positionRefreshTimer?.cancel();
    _bufferingTimer?.cancel();
    final old = _controller;
    final owned = _ownsController;
    old?.removeListener(_onControllerChanged);
    _controller = null;
    _ownsController = false;
    _lastRenderedValue = null;
    _lastReportedPosition = Duration.zero;
    _showBuffering = false;
    _resumeAfterLifecycle = false;
    if (mounted && rebuild) {
      setState(() {
        _initializing = true;
        _retrying = false;
        _error = null;
        _ended = false;
      });
    }
    if (rebuild) {
      _notifyPlaybackState(MithkaVideoPlaybackState.initializing);
    }
    if (owned && old != null) {
      try {
        await old.dispose();
      } catch (_) {
        // Replacement must proceed even if a backend fails to release cleanly.
      }
    }
    if (!mounted || generation != _controllerGeneration) return;
    await _initialize(generation);
  }

  Future<void> _initialize(int generation) async {
    final source = widget.source;
    final suppliedController = widget.controller;
    final builder = widget.controllerBuilder;
    final ownsController = suppliedController == null;
    VideoPlayerController controller;
    try {
      controller =
          suppliedController ??
          await Future<VideoPlayerController>.value(
            builder?.call(source) ??
                source.createController(
                  videoPlayerOptionsOverride: _ownedVideoPlayerOptions(source),
                ),
          );
    } catch (error, stackTrace) {
      if (mounted && generation == _controllerGeneration) {
        _setFatalError(error, stackTrace);
      }
      return;
    }
    if (!mounted || generation != _controllerGeneration) {
      if (ownsController) unawaited(controller.dispose());
      return;
    }
    _controller = controller;
    _ownsController = ownsController;
    controller.addListener(_onControllerChanged);
    try {
      if (!controller.value.isInitialized) await controller.initialize();
    } catch (error, stackTrace) {
      if (mounted && generation == _controllerGeneration) {
        _setFatalError(error, stackTrace);
      }
      return;
    }
    if (!mounted || generation != _controllerGeneration) return;
    if (controller.value.hasError) {
      _setFatalError(
        MithkaVideoPlayerError(
          controller.value.errorDescription ?? widget.labels.failed,
        ),
        StackTrace.empty,
      );
      return;
    }
    final targetVolume = widget.initialMuted
        ? 0.0
        : widget.initialVolume ?? controller.value.volume;
    final targetSpeed =
        widget.initialPlaybackSpeed ?? controller.value.playbackSpeed;
    _volume = targetVolume;
    _lastAudibleVolume = _volume > 0 ? _volume : 1;
    _speed = targetSpeed;
    _initializing = false;
    _error = null;
    _lastRenderedValue = controller.value;
    setState(() {});
    _invokeCallback(
      () => widget.onReady?.call(controller),
      'while notifying that the video player is ready',
    );
    _notifyPlaybackState(_stateFor(controller.value));
    await _applyInitialConfiguration(
      controller,
      generation,
      targetVolume: targetVolume,
      targetSpeed: targetSpeed,
    );
    if (!_isCurrentController(controller, generation)) return;
    if (widget.autoplay) {
      if (_lifecycleState == AppLifecycleState.resumed ||
          widget.lifecycleBehavior ==
              MithkaVideoLifecycleBehavior.delegateToController) {
        // Browser autoplay can be rejected without invalidating initialized
        // media. Keep the controls usable and report it as non-fatal.
        await _runCommand(controller.play);
      } else {
        _resumeAfterLifecycle = true;
      }
    }
    if (!_isCurrentController(controller, generation)) return;
    if (widget.autofocus) _focusNode.requestFocus();
    _scheduleHide();
  }

  Future<void> _applyInitialConfiguration(
    VideoPlayerController controller,
    int generation, {
    required double targetVolume,
    required double targetSpeed,
  }) async {
    if (controller.value.isLooping != widget.looping) {
      await _runCommand(() => controller.setLooping(widget.looping));
      if (!_isCurrentController(controller, generation)) return;
    }
    if (controller.value.volume != targetVolume) {
      await _runCommand(() => controller.setVolume(targetVolume));
      if (!_isCurrentController(controller, generation)) return;
      _volume = controller.value.volume.clamp(0.0, 1.0);
      if (_volume > 0) _lastAudibleVolume = _volume;
    }
    if (controller.value.playbackSpeed != targetSpeed) {
      await _runCommand(() => controller.setPlaybackSpeed(targetSpeed));
      if (!_isCurrentController(controller, generation)) return;
      _speed = controller.value.playbackSpeed;
    }
    final initialPosition = widget.initialPosition;
    if (initialPosition != null && initialPosition > Duration.zero) {
      final duration = controller.value.duration;
      final target = duration > Duration.zero && initialPosition > duration
          ? duration
          : initialPosition;
      if (controller.value.position != target) {
        await _runCommand(() => controller.seekTo(target));
        if (!_isCurrentController(controller, generation)) return;
      }
    }
    if (mounted) setState(() {});
  }

  bool _isCurrentController(VideoPlayerController controller, int generation) =>
      mounted &&
      generation == _controllerGeneration &&
      identical(controller, _controller);

  VideoPlayerOptions? _ownedVideoPlayerOptions(MithkaVideoSource source) {
    if (widget.lifecycleBehavior ==
        MithkaVideoLifecycleBehavior.delegateToController) {
      return source.videoPlayerOptions;
    }
    final options = source.videoPlayerOptions;
    return VideoPlayerOptions(
      mixWithOthers: options?.mixWithOthers ?? true,
      allowBackgroundPlayback: true,
      preventsDisplaySleepDuringVideoPlayback:
          options?.preventsDisplaySleepDuringVideoPlayback ?? true,
      webOptions: options?.webOptions,
      backBufferDurationMs: options?.backBufferDurationMs,
    );
  }

  void _validateConfiguration() {
    if (widget.controller != null && widget.controllerBuilder != null) {
      throw ArgumentError(
        'controller and controllerBuilder cannot both be provided',
      );
    }
    final initialVolume = widget.initialVolume;
    if (initialVolume != null &&
        (!initialVolume.isFinite || initialVolume < 0 || initialVolume > 1)) {
      throw ArgumentError.value(
        initialVolume,
        'initialVolume',
        'must be finite and between zero and one',
      );
    }
    final initialPlaybackSpeed = widget.initialPlaybackSpeed;
    if (initialPlaybackSpeed != null &&
        (!initialPlaybackSpeed.isFinite || initialPlaybackSpeed <= 0)) {
      throw ArgumentError.value(
        initialPlaybackSpeed,
        'initialPlaybackSpeed',
        'must be finite and greater than zero',
      );
    }
    if (widget.initialPosition?.isNegative ?? false) {
      throw ArgumentError.value(
        widget.initialPosition,
        'initialPosition',
        'must not be negative',
      );
    }
    if (widget.controlsAutoHideDuration.isNegative) {
      throw ArgumentError.value(
        widget.controlsAutoHideDuration,
        'controlsAutoHideDuration',
        'must not be negative',
      );
    }
    if (widget.positionUpdateInterval <= Duration.zero) {
      throw ArgumentError.value(
        widget.positionUpdateInterval,
        'positionUpdateInterval',
        'must be greater than zero',
      );
    }
    if (widget.bufferingIndicatorDelay.isNegative) {
      throw ArgumentError.value(
        widget.bufferingIndicatorDelay,
        'bufferingIndicatorDelay',
        'must not be negative',
      );
    }
    if (widget.seekInterval <= Duration.zero) {
      throw ArgumentError.value(
        widget.seekInterval,
        'seekInterval',
        'must be greater than zero',
      );
    }
    if (!widget.volumeStep.isFinite ||
        widget.volumeStep <= 0 ||
        widget.volumeStep > 1) {
      throw ArgumentError.value(
        widget.volumeStep,
        'volumeStep',
        'must be finite and between zero (exclusive) and one',
      );
    }
    if (widget.playbackSpeeds.any((speed) => speed <= 0 || !speed.isFinite)) {
      throw ArgumentError.value(
        widget.playbackSpeeds,
        'playbackSpeeds',
        'must contain only finite values greater than zero',
      );
    }
    if (widget.playbackSpeeds.isEmpty) {
      throw ArgumentError.value(
        widget.playbackSpeeds,
        'playbackSpeeds',
        'must not be empty',
      );
    }
  }

  void _resetPreviewState() {
    _previewTimer?.cancel();
    _cancelPreviewWait();
    _previewGeneration++;
    _previewCache.clear();
    _previewBytes = null;
    _pendingPreviewBucket = null;
    _previewTimedOut = false;
  }

  void _resetScrubSession({bool clearPreviewCache = false}) {
    _scrubGeneration++;
    _scrubCommitGeneration++;
    _scrubActive = false;
    _scrubController = null;
    _scrubPosition = null;
    _resumeAfterScrub = false;
    _scrubPause = Future.value();
    _previewTimer?.cancel();
    _cancelPreviewWait();
    _previewGeneration++;
    _previewBytes = null;
    _pendingPreviewBucket = null;
    _previewTimedOut = false;
    if (clearPreviewCache) _previewCache.clear();
  }

  void _onControllerChanged() {
    final controller = _controller;
    if (!mounted || controller == null) return;
    final value = controller.value;
    if (value.hasError) {
      _setFatalError(
        MithkaVideoPlayerError(value.errorDescription ?? widget.labels.failed),
        StackTrace.empty,
      );
      return;
    }
    if ((value.position - _lastReportedPosition).abs() >=
        const Duration(milliseconds: 250)) {
      _lastReportedPosition = value.position;
      _invokeCallback(
        () => widget.onPositionChanged?.call(value.position),
        'while reporting the video position',
      );
    }
    final completed =
        !widget.looping &&
        !value.isPlaying &&
        (value.isCompleted ||
            (value.isInitialized &&
                value.duration > Duration.zero &&
                value.position >= value.duration));
    var needsImmediateRefresh = false;
    if (completed && !_ended) {
      _ended = true;
      _invokeCallback(
        () => widget.onEnded?.call(),
        'while reporting completed video playback',
      );
      _controlsVisible = true;
      needsImmediateRefresh = true;
    } else if (!completed && _ended) {
      _ended = false;
      needsImmediateRefresh = true;
    }
    final previous = _lastRenderedValue;
    if (value.volume != _volume) {
      _volume = value.volume.clamp(0.0, 1.0);
      if (_volume > 0) _lastAudibleVolume = _volume;
    }
    if (value.playbackSpeed != _speed) {
      _speed = value.playbackSpeed;
    }
    _syncBuffering(value.isBuffering);
    _notifyPlaybackState(_stateFor(value));
    if (previous == null ||
        previous.isPlaying != value.isPlaying ||
        previous.isBuffering != value.isBuffering ||
        previous.hasError != value.hasError ||
        previous.duration != value.duration ||
        previous.caption != value.caption ||
        previous.volume != value.volume ||
        previous.playbackSpeed != value.playbackSpeed) {
      needsImmediateRefresh = true;
    }
    if (previous?.isPlaying != value.isPlaying) {
      if (value.isPlaying) {
        _scheduleHide();
      } else {
        _hideTimer?.cancel();
        _controlsVisible = true;
      }
    }
    _lastRenderedValue = value;
    if (needsImmediateRefresh) {
      _positionRefreshTimer?.cancel();
      _positionRefreshTimer = null;
      setState(() {});
    } else if (_controlsVisible && _positionRefreshTimer == null) {
      // The texture renders independently; controls only need a human-readable
      // position refresh rather than rebuilding for every decoded frame.
      _positionRefreshTimer = Timer(widget.positionUpdateInterval, () {
        _positionRefreshTimer = null;
        if (mounted && _controlsVisible) setState(() {});
      });
    }
  }

  MithkaVideoPlaybackState _stateFor(VideoPlayerValue value) {
    if (_error != null || value.hasError) {
      return MithkaVideoPlaybackState.failed;
    }
    if (_initializing || !value.isInitialized) {
      return MithkaVideoPlaybackState.initializing;
    }
    if (!widget.looping && (_ended || value.isCompleted && !value.isPlaying)) {
      return MithkaVideoPlaybackState.completed;
    }
    if (value.isBuffering) return MithkaVideoPlaybackState.buffering;
    if (value.isPlaying) return MithkaVideoPlaybackState.playing;
    return value.position == Duration.zero
        ? MithkaVideoPlaybackState.ready
        : MithkaVideoPlaybackState.paused;
  }

  void _notifyPlaybackState(MithkaVideoPlaybackState state) {
    if (_playbackState == state) return;
    _playbackState = state;
    _invokeCallback(
      () => widget.onPlaybackStateChanged?.call(state),
      'while reporting video playback state',
    );
  }

  void _syncBuffering(bool buffering) {
    if (!buffering) {
      _bufferingTimer?.cancel();
      _bufferingTimer = null;
      if (_showBuffering) {
        _showBuffering = false;
        if (mounted) setState(() {});
      }
      return;
    }
    if (_showBuffering || _bufferingTimer != null) return;
    _bufferingTimer = Timer(widget.bufferingIndicatorDelay, () {
      _bufferingTimer = null;
      if (mounted && _controller?.value.isBuffering == true) {
        setState(() => _showBuffering = true);
      }
    });
  }

  void _setFatalError(Object error, StackTrace stackTrace) {
    if (!mounted || _error != null) return;
    final playerError = error is MithkaVideoPlayerError
        ? error
        : MithkaVideoPlayerError(
            widget.labels.failed,
            cause: error,
            stackTrace: stackTrace,
          );
    setState(() {
      _initializing = false;
      _error = playerError;
      _showBuffering = false;
      _controlsVisible = true;
    });
    _notifyPlaybackState(MithkaVideoPlaybackState.failed);
    _invokeCallback(
      () => widget.onError?.call(playerError),
      'while reporting a video playback error',
    );
  }

  Future<void> _runCommand(Future<void> Function() command) async {
    try {
      await command();
    } catch (error, stackTrace) {
      final playerError = MithkaVideoPlayerError(
        error.toString(),
        cause: error,
        stackTrace: stackTrace,
      );
      _invokeCallback(
        () => widget.onError?.call(playerError),
        'while reporting a non-fatal video command error',
      );
    }
  }

  void _invokeCallback(VoidCallback callback, String context) {
    try {
      callback();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'mithka_video_player',
          context: ErrorDescription(context),
        ),
      );
    }
  }

  void _showControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _hideControls() {
    _hideTimer?.cancel();
    if (!_controlsVisible || _accessibleNavigation || _controlsHaveFocus) {
      return;
    }
    setState(() => _controlsVisible = false);
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideTimer?.cancel();
      if (_accessibleNavigation) {
        _showControls();
        return;
      }
      setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  void _handleControlsFocusChange(bool focused) {
    if (_controlsHaveFocus == focused) return;
    _controlsHaveFocus = focused;
    if (focused) {
      _hideTimer?.cancel();
      if (mounted && !_controlsVisible) {
        setState(() => _controlsVisible = true);
      }
    } else {
      _scheduleHide();
    }
  }

  bool get _controlsMustRemainVisible =>
      _controller?.value.isPlaying != true ||
      _scrubActive ||
      _controlsHaveFocus ||
      _accessibleNavigation ||
      widget.controlsAutoHideDuration == Duration.zero;

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (_controlsMustRemainVisible) return;
    _hideTimer = Timer(widget.controlsAutoHideDuration, () {
      if (mounted && !_controlsMustRemainVisible) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_ended) {
      await _runCommand(() => controller.seekTo(Duration.zero));
      _ended = false;
    }
    await _runCommand(
      controller.value.isPlaying ? controller.pause : controller.play,
    );
    _showControls();
  }

  Future<void> _seekBy(Duration delta) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final duration = controller.value.duration;
    if (duration <= Duration.zero) return;
    await _seekTo(controller.value.position + delta);
  }

  Future<void> _seekTo(Duration position) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final duration = controller.value.duration;
    if (duration <= Duration.zero) return;
    final target = position < Duration.zero
        ? Duration.zero
        : position > duration
        ? duration
        : position;
    await _runCommand(() => controller.seekTo(target));
    _showControls();
  }

  Future<void> _setVolume(double value) async {
    final next = value.clamp(0.0, 1.0).toDouble();
    if (next > 0) _lastAudibleVolume = next;
    _volume = next;
    final controller = _controller;
    if (controller != null) {
      await _runCommand(() => controller.setVolume(next));
    }
    if (mounted) setState(() {});
    _showControls();
  }

  Future<void> _toggleMute() =>
      _setVolume(_volume > 0 ? 0 : math.max(0.2, _lastAudibleVolume));

  Future<void> _setPlaybackSpeed(double speed) async {
    if (!speed.isFinite || speed <= 0) {
      throw ArgumentError.value(speed, 'speed', 'must be finite and positive');
    }
    final previous = _speed;
    _speed = speed;
    final controller = _controller;
    if (controller != null) {
      try {
        await controller.setPlaybackSpeed(speed);
      } catch (error, stackTrace) {
        _speed = previous;
        await _runCommand(() => Future<void>.error(error, stackTrace));
      }
    }
    if (mounted) setState(() {});
    _showControls();
  }

  Future<void> _cycleSpeed() async {
    final speeds = widget.playbackSpeeds.where((speed) => speed > 0).toList();
    if (speeds.isEmpty) return;
    final index = speeds.indexOf(_speed);
    await _setPlaybackSpeed(speeds[(index + 1) % speeds.length]);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!widget.enableKeyboardShortcuts ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final repeating = event is KeyRepeatEvent;
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
      if (repeating) return KeyEventResult.handled;
      unawaited(_togglePlayback());
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.keyJ) {
      unawaited(_seekBy(-widget.seekInterval));
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyL) {
      unawaited(_seekBy(widget.seekInterval));
    } else if (key == LogicalKeyboardKey.arrowUp) {
      unawaited(_setVolume(_volume + widget.volumeStep));
    } else if (key == LogicalKeyboardKey.arrowDown) {
      unawaited(_setVolume(_volume - widget.volumeStep));
    } else if (key == LogicalKeyboardKey.keyM) {
      if (repeating) return KeyEventResult.handled;
      unawaited(_toggleMute());
    } else if (key == LogicalKeyboardKey.keyF) {
      if (repeating) return KeyEventResult.handled;
      _requestFullscreen(!widget.isFullscreen);
    } else if (key == LogicalKeyboardKey.keyP &&
        widget.onPictureInPictureChanged != null) {
      if (repeating) return KeyEventResult.handled;
      unawaited(_requestPictureInPicture(!widget.isPictureInPicture));
    } else if (key == LogicalKeyboardKey.escape) {
      if (repeating) return KeyEventResult.handled;
      if (widget.isFullscreen &&
          (widget.onFullscreenChanged != null ||
              widget.onToggleFullscreen != null)) {
        _requestFullscreen(false);
      } else if (widget.isPictureInPicture &&
          widget.onPictureInPictureChanged != null) {
        unawaited(_requestPictureInPicture(false));
      } else if (widget.onClose != null) {
        _invokeCallback(widget.onClose!, 'while closing the video player');
      } else {
        return KeyEventResult.ignored;
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _beginScrub(double fraction) {
    final controller = _controller;
    if (controller == null || controller.value.duration <= Duration.zero) {
      return;
    }
    if (_scrubActive && identical(_scrubController, controller)) {
      _updateScrub(fraction);
      return;
    }
    _resetScrubSession();
    _scrubGeneration++;
    _scrubActive = true;
    _scrubController = controller;
    _previewTimedOut = false;
    _hideTimer?.cancel();
    _resumeAfterScrub = controller.value.isPlaying;
    _scrubPause = _resumeAfterScrub
        ? _runCommand(controller.pause)
        : Future.value();
    _updateScrub(fraction.clamp(0.0, 1.0));
  }

  void _updateScrub(double fraction) {
    if (!_scrubActive) return;
    final duration = _scrubController?.value.duration ?? Duration.zero;
    final position = duration * fraction.clamp(0.0, 1.0);
    _queuePreview(position);
    setState(() => _scrubPosition = position);
  }

  Future<void> _endScrub(double fraction) async {
    final controller = _scrubController;
    if (!_scrubActive || controller == null) return;
    final session = _scrubGeneration;
    final commit = ++_scrubCommitGeneration;
    final shouldResume = _resumeAfterScrub;
    final position = controller.value.duration * fraction.clamp(0.0, 1.0);
    await _scrubPause;
    if (!_isCurrentScrub(controller, session, commit)) return;
    await _runCommand(() => controller.seekTo(position));
    if (!_isCurrentScrub(controller, session, commit)) return;
    if (shouldResume) {
      if (_lifecycleState == AppLifecycleState.resumed) {
        await _runCommand(controller.play);
      } else if (widget.lifecycleBehavior !=
          MithkaVideoLifecycleBehavior.pause) {
        _resumeAfterLifecycle = true;
      }
    }
    if (!_isCurrentScrub(controller, session, commit)) return;
    _finishScrubSession(session);
  }

  bool _isCurrentScrub(
    VideoPlayerController controller,
    int session,
    int commit,
  ) =>
      mounted &&
      _scrubActive &&
      session == _scrubGeneration &&
      commit == _scrubCommitGeneration &&
      identical(controller, _scrubController) &&
      identical(controller, _controller);

  void _finishScrubSession(int session) {
    if (!_scrubActive || session != _scrubGeneration) return;
    _scrubActive = false;
    _scrubController = null;
    _resumeAfterScrub = false;
    _scrubPause = Future.value();
    _previewTimer?.cancel();
    _cancelPreviewWait();
    _previewGeneration++;
    _pendingPreviewBucket = null;
    _previewTimedOut = false;
    if (mounted) {
      setState(() {
        _scrubPosition = null;
        _previewBytes = null;
      });
    }
    _scheduleHide();
  }

  void _queuePreview(Duration position) {
    if (!widget.showScrubPreview || _previewTimedOut) return;
    final bucketSize = _previewBucketDuration.inMilliseconds;
    final bucket = (position.inMilliseconds ~/ bucketSize) * bucketSize;
    final cached = _previewCache[bucket];
    if (cached != null) {
      _previewTimer?.cancel();
      _previewGeneration++;
      _pendingPreviewBucket = null;
      _previewBytes = cached;
      return;
    }
    _previewBytes = null;
    _pendingPreviewBucket = bucket;
    _previewTimer?.cancel();
    _previewGeneration++;
    _previewTimer = Timer(
      _previewDebounceDuration,
      () => unawaited(_drainPreviewQueue()),
    );
  }

  Future<void> _drainPreviewQueue() async {
    if (_previewLoading) return;
    final bucket = _pendingPreviewBucket;
    if (bucket == null) return;
    _pendingPreviewBucket = null;
    final generation = _previewGeneration;
    final scrubGeneration = _scrubGeneration;
    _previewLoading = true;
    Uint8List? bytes;
    var timedOut = false;
    try {
      final request = MithkaVideoThumbnailRequest(
        source: widget.source,
        position: Duration(milliseconds: bucket),
      );
      bytes = await _waitForPreview(
        (widget.thumbnailProvider ?? MithkaVideoThumbnail.generateRequest)(
          request,
        ),
        onTimeout: () => timedOut = true,
      );
    } catch (_) {
      bytes = null;
    } finally {
      _previewLoading = false;
    }
    if (timedOut &&
        mounted &&
        scrubGeneration == _scrubGeneration &&
        _scrubActive) {
      _previewTimedOut = true;
      _pendingPreviewBucket = null;
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
    if (_pendingPreviewBucket != null && scrubGeneration == _scrubGeneration) {
      unawaited(_drainPreviewQueue());
    }
  }

  Future<Uint8List?> _waitForPreview(
    Future<Uint8List?> request, {
    required VoidCallback onTimeout,
  }) {
    final waiter = Completer<Uint8List?>();
    final timeout = Timer(_previewRequestTimeout, () {
      if (waiter.isCompleted) return;
      onTimeout();
      waiter.complete(null);
    });
    _previewWaiter = waiter;
    _previewTimeoutTimer = timeout;
    request.then(
      (bytes) {
        if (!waiter.isCompleted) waiter.complete(bytes);
      },
      onError: (Object _, StackTrace _) {
        if (!waiter.isCompleted) waiter.complete(null);
      },
    );
    return waiter.future.whenComplete(() {
      timeout.cancel();
      if (identical(_previewWaiter, waiter)) _previewWaiter = null;
      if (identical(_previewTimeoutTimer, timeout)) {
        _previewTimeoutTimer = null;
      }
    });
  }

  void _cancelPreviewWait() {
    _previewTimeoutTimer?.cancel();
    _previewTimeoutTimer = null;
    final waiter = _previewWaiter;
    _previewWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete(null);
  }

  void _requestFullscreen(bool fullscreen) {
    if (widget.onFullscreenChanged != null) {
      _invokeCallback(
        () => widget.onFullscreenChanged!(fullscreen),
        'while changing fullscreen video playback',
      );
    } else if (widget.onToggleFullscreen != null) {
      _invokeCallback(
        widget.onToggleFullscreen!,
        'while toggling fullscreen video playback',
      );
    }
    _showControls();
  }

  Future<void> _requestPictureInPicture(bool pictureInPicture) async {
    final callback = widget.onPictureInPictureChanged;
    if (callback == null || _pictureInPictureRequestPending) return;
    _pictureInPictureRequestPending = true;
    if (mounted) setState(() {});
    try {
      await _runCommand(
        () => Future<void>.sync(() => callback(pictureInPicture)),
      );
    } finally {
      _pictureInPictureRequestPending = false;
      if (mounted) setState(() {});
    }
    if (!mounted) return;
    _showControls();
  }

  void _requestPrevious() {
    if (!mounted) return;
    final callback = widget.onPrevious;
    if (callback == null) return;
    _invokeCallback(callback, 'while requesting the previous video');
    _showControls();
  }

  void _requestNext() {
    if (!mounted) return;
    final callback = widget.onNext;
    if (callback == null) return;
    _invokeCallback(callback, 'while requesting the next video');
    _showControls();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state != AppLifecycleState.resumed) {
      if (_scrubActive &&
          _resumeAfterScrub &&
          widget.lifecycleBehavior ==
              MithkaVideoLifecycleBehavior.pauseAndResume) {
        _resumeAfterLifecycle = true;
      }
      if (widget.lifecycleBehavior ==
          MithkaVideoLifecycleBehavior.delegateToController) {
        return;
      }
      if (controller.value.isPlaying) {
        if (widget.lifecycleBehavior ==
            MithkaVideoLifecycleBehavior.pauseAndResume) {
          _resumeAfterLifecycle = true;
        }
        _lifecyclePause = _runCommand(controller.pause);
      }
      return;
    }
    final shouldResume = _resumeAfterLifecycle;
    _resumeAfterLifecycle = false;
    if (shouldResume) {
      if (_scrubActive) {
        _resumeAfterScrub = true;
        return;
      }
      unawaited(() async {
        await _lifecyclePause;
        if (mounted &&
            _controller == controller &&
            !_scrubActive &&
            _lifecycleState == AppLifecycleState.resumed) {
          if (!controller.value.isPlaying) {
            await _runCommand(controller.play);
          }
        }
      }());
    }
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await Future<void>.value(widget.onRetry?.call());
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() => _retrying = false);
        final playerError = MithkaVideoPlayerError(
          widget.labels.failed,
          cause: error,
          stackTrace: stackTrace,
        );
        _invokeCallback(
          () => widget.onError?.call(playerError),
          'while reporting a video retry error',
        );
      }
      return;
    }
    if (mounted) await _replaceController();
  }

  @override
  void dispose() {
    _controllerGeneration++;
    _resetScrubSession(clearPreviewCache: true);
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _positionRefreshTimer?.cancel();
    _bufferingTimer?.cancel();
    _internalFocusNode?.dispose();
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
      autofocus: widget.autofocus,
      onKeyEvent: _handleKey,
      child: Semantics(
        container: true,
        label: widget.labels.video,
        child: MouseRegion(
          cursor: _controlsVisible
              ? SystemMouseCursors.basic
              : SystemMouseCursors.none,
          onEnter: (_) => _showControls(),
          onHover: (_) => _showControls(),
          child: Listener(
            onPointerDown: (event) {
              _lastPointerKind = event.kind;
              _focusNode.requestFocus();
            },
            onPointerSignal: (event) {
              if (widget.enableScrollVolume &&
                  event is PointerScrollEvent &&
                  event.scrollDelta.dy != 0) {
                GestureBinding.instance.pointerSignalResolver.register(event, (
                  resolvedEvent,
                ) {
                  if (resolvedEvent is PointerScrollEvent) {
                    unawaited(
                      _setVolume(
                        _volume -
                            resolvedEvent.scrollDelta.dy.sign *
                                widget.volumeStep,
                      ),
                    );
                  }
                });
              }
            },
            child: ColoredBox(
              color: widget.backgroundColor,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final mediaSize = MediaQuery.maybeSizeOf(context);
                  final desktopLayout =
                      kIsWeb ||
                      defaultTargetPlatform == TargetPlatform.linux ||
                      defaultTargetPlatform == TargetPlatform.macOS ||
                      defaultTargetPlatform == TargetPlatform.windows;
                  final wide =
                      constraints.maxWidth >= 700 &&
                      constraints.maxHeight >= 360 &&
                      (desktopLayout ||
                          mediaSize == null ||
                          mediaSize.shortestSide >= 600);
                  if (_error != null) return _errorView();
                  if (_initializing ||
                      controller == null ||
                      !controller.value.isInitialized) {
                    return _loadingView();
                  }
                  final readyPlayer = Stack(
                    fit: StackFit.expand,
                    children: [
                      _videoSurface(controller),
                      if (_showBuffering)
                        Center(
                          child: Semantics(
                            label: widget.labels.buffering,
                            liveRegion: true,
                            child: const SizedBox.square(
                              dimension: 32,
                              child: _ActivityIndicator(),
                            ),
                          ),
                        ),
                      if (widget.captionsEnabled &&
                          controller.value.caption.text.trim().isNotEmpty)
                        _caption(controller.value.caption.text),
                      _chrome(controller, wide, constraints.maxHeight),
                    ],
                  );
                  if (widget.interactionMode ==
                      MithkaVideoInteractionMode.delegateToChrome) {
                    return readyPlayer;
                  }
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _handleSurfaceTap,
                    onDoubleTapDown: (details) =>
                        _handleSurfaceDoubleTap(details, constraints.maxWidth),
                    child: readyPlayer,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleSurfaceTap() {
    _toggleControls();
  }

  void _handleSurfaceDoubleTap(TapDownDetails details, double width) {
    if (_lastPointerKind == PointerDeviceKind.mouse ||
        _lastPointerKind == PointerDeviceKind.trackpad) {
      _requestFullscreen(!widget.isFullscreen);
      return;
    }
    final fraction = width <= 0 ? 0.5 : details.localPosition.dx / width;
    if (fraction < 0.42) {
      unawaited(_seekBy(-widget.seekInterval));
    } else if (fraction > 0.58) {
      unawaited(_seekBy(widget.seekInterval));
    } else {
      unawaited(_togglePlayback());
    }
  }

  Widget _chrome(
    VideoPlayerController controller,
    bool wide,
    double availableHeight,
  ) {
    final scope = _chromeScope(controller);
    final builder = widget.chromeBuilder;
    if (builder != null) {
      return Focus(
        canRequestFocus: false,
        onFocusChange: _handleControlsFocusChange,
        child: builder(context, scope),
      );
    }
    final safePadding = _fullscreenSafePadding;
    return Focus(
      canRequestFocus: false,
      onFocusChange: _handleControlsFocusChange,
      child: ExcludeFocus(
        excluding: !_controlsVisible,
        child: ExcludeSemantics(
          excluding: !_controlsVisible,
          child: IgnorePointer(
            ignoring: !_controlsVisible,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 170),
              child: _controls(
                controller,
                scope,
                wide,
                safePadding,
                availableHeight,
              ),
            ),
          ),
        ),
      ),
    );
  }

  MithkaVideoChromeScope _chromeScope(VideoPlayerController controller) =>
      MithkaVideoChromeScope(
        snapshot: MithkaVideoChromeSnapshot(
          value: controller.value,
          playbackState: _stateFor(controller.value),
          displayPosition: _scrubPosition ?? controller.value.position,
          controlsVisible: _controlsVisible,
          isScrubbing: _scrubActive,
          bufferingIndicatorVisible: _showBuffering,
          isFullscreen: widget.isFullscreen,
          isPictureInPicture: widget.isPictureInPicture,
          pictureInPictureRequestPending: _pictureInPictureRequestPending,
        ),
        actions: _actions,
        labels: widget.labels,
        previous: widget.onPrevious == null ? null : _requestPrevious,
        next: widget.onNext == null ? null : _requestNext,
      );

  Widget _videoSurface(VideoPlayerController controller) {
    final surface =
        widget.videoSurfaceBuilder?.call(context, controller) ??
        VideoPlayer(controller);
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sourceSize = _sourceSize(controller);
          final bounds = Size(
            constraints.hasBoundedWidth
                ? constraints.maxWidth
                : sourceSize.width,
            constraints.hasBoundedHeight
                ? constraints.maxHeight
                : sourceSize.height,
          );
          final fittedSize = _fittedSurfaceSize(sourceSize, bounds, widget.fit);
          return OverflowBox(
            alignment: widget.alignment,
            minWidth: 0,
            maxWidth: double.infinity,
            minHeight: 0,
            maxHeight: double.infinity,
            child: SizedBox(
              width: fittedSize.width,
              height: fittedSize.height,
              child: RepaintBoundary(child: surface),
            ),
          );
        },
      ),
    );
  }

  Widget _caption(String text) {
    final safePadding = _fullscreenSafePadding;
    return Positioned(
      left: 24 + safePadding.left,
      right: 24 + safePadding.right,
      bottom: (_controlsVisible ? 92 : 22) + safePadding.bottom,
      child: Semantics(
        liveRegion: true,
        label: text,
        excludeSemantics: true,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xB0000000),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: widget.captionStyle,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Size _sourceSize(VideoPlayerController controller) {
    if (widget.width != null &&
        widget.height != null &&
        widget.width! > 0 &&
        widget.height! > 0) {
      return Size(widget.width!.toDouble(), widget.height!.toDouble());
    }
    final size = controller.value.size;
    if (size.width.isFinite &&
        size.height.isFinite &&
        size.width > 0 &&
        size.height > 0) {
      return size;
    }
    final ratio = controller.value.aspectRatio;
    final effectiveRatio = ratio.isFinite && ratio > 0 ? ratio : 16 / 9;
    return Size(effectiveRatio * 1000, 1000);
  }

  double _aspectRatio(VideoPlayerController controller) =>
      _sourceSize(controller).aspectRatio;

  Size _fittedSurfaceSize(Size source, Size bounds, BoxFit fit) {
    if (source.width <= 0 ||
        source.height <= 0 ||
        bounds.width <= 0 ||
        bounds.height <= 0) {
      return Size.zero;
    }
    return switch (fit) {
      BoxFit.fill => bounds,
      BoxFit.contain => _scaledSize(
        source,
        math.min(bounds.width / source.width, bounds.height / source.height),
      ),
      BoxFit.cover => _scaledSize(
        source,
        math.max(bounds.width / source.width, bounds.height / source.height),
      ),
      BoxFit.fitWidth => _scaledSize(source, bounds.width / source.width),
      BoxFit.fitHeight => _scaledSize(source, bounds.height / source.height),
      BoxFit.none => source,
      BoxFit.scaleDown => _scaledSize(
        source,
        math.min(
          1,
          math.min(bounds.width / source.width, bounds.height / source.height),
        ),
      ),
    };
  }

  Size _scaledSize(Size source, double scale) =>
      Size(source.width * scale, source.height * scale);

  Widget _loadingView() =>
      widget.loadingBuilder?.call(context) ??
      Center(
        child: Semantics(
          label: widget.labels.loading,
          child: const SizedBox.square(
            dimension: 34,
            child: _ActivityIndicator(),
          ),
        ),
      );

  Widget _errorView() {
    final error = _error!;
    final retry = widget.controller == null || widget.onRetry != null
        ? () => unawaited(_retry())
        : null;
    return widget.errorBuilder?.call(context, error, retry) ??
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.labels.failed,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 15,
                  ),
                ),
                if (retry != null) ...[
                  const SizedBox(height: 14),
                  _TextControlButton(
                    label: widget.labels.retry,
                    onTap: _retrying ? null : retry,
                  ),
                ],
              ],
            ),
          ),
        );
  }

  Widget _controls(
    VideoPlayerController controller,
    MithkaVideoChromeScope scope,
    bool wide,
    EdgeInsets safePadding,
    double availableHeight,
  ) {
    final value = controller.value;
    final hasTimeline = value.duration > Duration.zero;
    final durationMs = hasTimeline ? value.duration.inMilliseconds : 1;
    final position = _scrubPosition ?? value.position;
    final fraction = (position.inMilliseconds / durationMs).clamp(0.0, 1.0);
    final buffered = value.buffered.isEmpty
        ? 0.0
        : (value.buffered.last.end.inMilliseconds / durationMs).clamp(0.0, 1.0);
    final mergeTransport =
        !wide && availableHeight - safePadding.vertical < 220;
    final horizontalPadding = mergeTransport ? 8.0 : (wide ? 24.0 : 14.0);
    final bottomPadding = mergeTransport ? 4.0 : (wide ? 20.0 : 12.0);
    final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final safeStart = textDirection == TextDirection.ltr
        ? safePadding.left
        : safePadding.right;
    final safeEnd = textDirection == TextDirection.ltr
        ? safePadding.right
        : safePadding.left;
    final chromeStyle = widget.chromeStyle;
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    chromeStyle.topScrimColor,
                    const Color(0x00000000),
                    chromeStyle.bottomScrimColor,
                  ],
                  stops: [0, 0.48, 1],
                ),
              ),
            ),
          ),
          if (widget.onClose != null)
            PositionedDirectional(
              top: 14 + safePadding.top,
              start: 14 + safeStart,
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(1),
                child: _controlButton(
                  glyph: _Glyph.close,
                  label: widget.labels.close,
                  onTap: widget.onClose!,
                  size: 42,
                ),
              ),
            ),
          if (!mergeTransport)
            Center(
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(3),
                child: _transportControls(value, wide),
              ),
            ),
          Positioned(
            left: horizontalPadding + safePadding.left,
            right: horizontalPadding + safePadding.right,
            bottom: bottomPadding + safePadding.bottom,
            child: FocusTraversalOrder(
              order: const NumericFocusOrder(4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasTimeline)
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
                                bufferedColor: chromeStyle.bufferedTrackColor,
                                inactiveColor: chromeStyle.inactiveTrackColor,
                                semanticLabel: widget.labels.position,
                                semanticValue:
                                    '${_format(position)} / ${_format(value.duration)}',
                                semanticIncreasedValue: _format(
                                  position + widget.seekInterval >
                                          value.duration
                                      ? value.duration
                                      : position + widget.seekInterval,
                                ),
                                semanticDecreasedValue: _format(
                                  position - widget.seekInterval < Duration.zero
                                      ? Duration.zero
                                      : position - widget.seekInterval,
                                ),
                                keyboardStep: math.min(
                                  1,
                                  widget.seekInterval.inMilliseconds /
                                      durationMs,
                                ),
                                onChangeStart: _beginScrub,
                                onChanged: _updateScrub,
                                onChangeEnd: _endScrub,
                              ),
                            ),
                            if (widget.showScrubPreview &&
                                _scrubPosition != null)
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
                  LayoutBuilder(
                    builder: (context, constraints) => _bottomControlsRow(
                      value: value,
                      position: position,
                      hasTimeline: hasTimeline,
                      wide: wide,
                      mergeTransport: mergeTransport,
                      availableWidth: constraints.maxWidth,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.topTrailingBuilder != null)
            PositionedDirectional(
              top: 14 + safePadding.top,
              start: (widget.onClose == null ? 14 : 70) + safeStart,
              end: 14 + safeEnd,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.max(
                    0,
                    availableHeight - 28 - safePadding.top - safePadding.bottom,
                  ),
                ),
                child: FocusTraversalOrder(
                  order: const NumericFocusOrder(2),
                  child: Align(
                    alignment: AlignmentDirectional.topEnd,
                    child: Semantics(
                      container: true,
                      explicitChildNodes: true,
                      child: FocusTraversalGroup(
                        child: widget.topTrailingBuilder!(context, scope),
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

  Widget _bottomControlsRow({
    required VideoPlayerValue value,
    required Duration position,
    required bool hasTimeline,
    required bool wide,
    required bool mergeTransport,
    required double availableWidth,
  }) {
    final hasFullscreen =
        widget.onToggleFullscreen != null || widget.onFullscreenChanged != null;
    final hasPictureInPicture = widget.onPictureInPictureChanged != null;
    var fixedWidth = 44.0;
    if (mergeTransport && widget.onPrevious != null) fixedWidth += 48;
    if (mergeTransport && widget.onNext != null) fixedWidth += 48;
    final showFullscreen = hasFullscreen && availableWidth >= fixedWidth + 44;
    if (showFullscreen) fixedWidth += 44;
    final showPictureInPicture =
        hasPictureInPicture && availableWidth >= fixedWidth + 44;
    if (showPictureInPicture) fixedWidth += 44;
    final showMute = availableWidth >= fixedWidth + 48;
    if (showMute) fixedWidth += 48;
    final showVolume = wide && showMute && availableWidth >= fixedWidth + 98;
    if (showVolume) fixedWidth += 98;
    const speedWidth = 64.0;
    final showSpeed = availableWidth >= fixedWidth + speedWidth + 88;
    if (showSpeed) fixedWidth += speedWidth;
    final showTime = availableWidth >= fixedWidth + 44;

    return Row(
      children: [
        if (mergeTransport && widget.onPrevious != null) ...[
          _controlButton(
            glyph: _Glyph.previous,
            label: widget.labels.previous,
            onTap: _requestPrevious,
            filled: true,
          ),
          const SizedBox(width: 4),
        ],
        _controlButton(
          glyph: value.isPlaying ? _Glyph.pause : _Glyph.play,
          label: value.isPlaying ? widget.labels.pause : widget.labels.play,
          onTap: _togglePlayback,
          filled: mergeTransport,
          prominent: mergeTransport,
        ),
        if (mergeTransport && widget.onNext != null) ...[
          const SizedBox(width: 4),
          _controlButton(
            glyph: _Glyph.next,
            label: widget.labels.next,
            onTap: _requestNext,
            filled: true,
          ),
        ],
        if (showMute) ...[
          const SizedBox(width: 4),
          _controlButton(
            glyph: _volume == 0 ? _Glyph.muted : _Glyph.volume,
            label: _volume == 0 ? widget.labels.unmute : widget.labels.mute,
            onTap: () => unawaited(_toggleMute()),
          ),
        ],
        if (showVolume) ...[
          const SizedBox(width: 6),
          SizedBox(
            width: 92,
            height: 28,
            child: MithkaVideoSlider(
              value: _volume,
              trackHeight: 3,
              thumbRadius: 5,
              activeColor: widget.chromeStyle.foregroundColor,
              inactiveColor: widget.chromeStyle.inactiveTrackColor,
              semanticLabel: widget.labels.volume,
              semanticValue: '${(_volume * 100).round()}%',
              keyboardStep: widget.volumeStep,
              onChanged: (next) => unawaited(_setVolume(next)),
            ),
          ),
        ],
        if (showTime) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasTimeline
                  ? '${_format(position)} / ${_format(value.duration)}'
                  : widget.labels.live,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(
                inherit: false,
                color: widget.chromeStyle.foregroundColor,
                fontSize: wide ? 13 : 12,
                fontWeight: FontWeight.normal,
                decoration: TextDecoration.none,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ] else
          const Spacer(),
        if (showSpeed)
          SizedBox(
            width: speedWidth,
            child: _BareTextControlButton(
              label: widget.labels.speed,
              text: '${_speed.toStringAsFixed(_speed % 1 == 0 ? 0 : 2)}x',
              onTap: _cycleSpeed,
              style: widget.chromeStyle,
            ),
          ),
        if (showPictureInPicture)
          _controlButton(
            glyph: widget.isPictureInPicture
                ? _Glyph.exitPictureInPicture
                : _Glyph.pictureInPicture,
            label: widget.isPictureInPicture
                ? widget.labels.exitPictureInPicture
                : widget.labels.pictureInPicture,
            toggled: widget.isPictureInPicture,
            busy: _pictureInPictureRequestPending,
            onTap: () =>
                unawaited(_requestPictureInPicture(!widget.isPictureInPicture)),
          ),
        if (showFullscreen)
          _controlButton(
            glyph: widget.isFullscreen
                ? _Glyph.exitFullscreen
                : _Glyph.fullscreen,
            label: widget.isFullscreen
                ? widget.labels.exitFullscreen
                : widget.labels.fullscreen,
            toggled: widget.isFullscreen,
            onTap: () => _requestFullscreen(!widget.isFullscreen),
          ),
      ],
    );
  }

  Widget _transportControls(VideoPlayerValue value, bool wide) {
    final previous = widget.onPrevious;
    final next = widget.onNext;
    final style = widget.chromeStyle;
    final sideSize = wide
        ? style.wideTransportButtonSize
        : style.compactTransportButtonSize;
    final primarySize = wide
        ? style.widePrimaryTransportButtonSize
        : style.compactPrimaryTransportButtonSize;
    final spacing = wide
        ? style.wideTransportSpacing
        : style.compactTransportSpacing;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (previous != null) ...[
            _controlButton(
              glyph: _Glyph.previous,
              label: widget.labels.previous,
              onTap: _requestPrevious,
              size: sideSize,
              filled: true,
            ),
            SizedBox(width: spacing),
          ],
          _controlButton(
            glyph: value.isPlaying ? _Glyph.pause : _Glyph.play,
            label: value.isPlaying ? widget.labels.pause : widget.labels.play,
            onTap: _togglePlayback,
            size: primarySize,
            filled: true,
            prominent: true,
          ),
          if (next != null) ...[
            SizedBox(width: spacing),
            _controlButton(
              glyph: _Glyph.next,
              label: widget.labels.next,
              onTap: _requestNext,
              size: sideSize,
              filled: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _scrubPreview(
    double trackWidth,
    double fraction,
    Duration position,
    bool wide,
  ) {
    final previewWidth = wide ? 160.0 : 128.0;
    final controller = _controller;
    final sourceAspect = controller == null ? 16 / 9 : _aspectRatio(controller);
    final previewHeight = (previewWidth / sourceAspect)
        .clamp(72.0, 110.0)
        .toDouble();
    final thumbRadius = wide ? 7.0 : 6.0;
    final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final visualFraction = textDirection == TextDirection.rtl
        ? 1 - fraction
        : fraction;
    final thumbCenter =
        thumbRadius +
        math.max(0, trackWidth - thumbRadius * 2) * visualFraction;
    final left = (thumbCenter - previewWidth / 2)
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
          child:
              widget.scrubPreviewBuilder?.call(
                context,
                _previewBytes,
                position,
              ) ??
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_previewBytes != null)
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
    bool prominent = false,
    bool busy = false,
    bool? toggled,
  }) => _PlayerControlButton(
    glyph: glyph,
    label: label,
    onTap: onTap,
    size: math.max(44, size),
    filled: filled,
    prominent: prominent,
    busy: busy,
    toggled: toggled,
    style: widget.chromeStyle,
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

final class _MithkaVideoActions implements MithkaVideoActions {
  const _MithkaVideoActions(this._state);

  final _MithkaVideoPlayerState _state;

  bool get _active => _state.mounted;

  @override
  Future<void> togglePlayback() =>
      _active ? _state._togglePlayback() : Future.value();

  @override
  Future<void> seekTo(Duration position) =>
      _active ? _state._seekTo(position) : Future.value();

  @override
  Future<void> seekBy(Duration delta) =>
      _active ? _state._seekBy(delta) : Future.value();

  @override
  Future<void> setVolume(double volume) =>
      _active ? _state._setVolume(volume) : Future.value();

  @override
  Future<void> toggleMute() => _active ? _state._toggleMute() : Future.value();

  @override
  Future<void> setPlaybackSpeed(double speed) =>
      _active ? _state._setPlaybackSpeed(speed) : Future.value();

  @override
  void showControls() {
    if (_active) _state._showControls();
  }

  @override
  void hideControls() {
    if (_active) _state._hideControls();
  }

  @override
  void toggleControls() {
    if (_active) _state._toggleControls();
  }

  @override
  void requestFullscreen(bool fullscreen) {
    if (_active) _state._requestFullscreen(fullscreen);
  }

  @override
  Future<void> requestPictureInPicture(bool pictureInPicture) => _active
      ? _state._requestPictureInPicture(pictureInPicture)
      : Future.value();

  @override
  void beginScrub(double fraction) {
    if (_active) _state._beginScrub(fraction);
  }

  @override
  void updateScrub(double fraction) {
    if (_active) _state._updateScrub(fraction);
  }

  @override
  Future<void> endScrub(double fraction) =>
      _active ? _state._endScrub(fraction) : Future.value();
}

enum _Glyph {
  play,
  pause,
  previous,
  next,
  volume,
  muted,
  pictureInPicture,
  exitPictureInPicture,
  fullscreen,
  exitFullscreen,
  close,
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph, this.color);

  final _Glyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
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
      case _Glyph.previous:
        paint.style = PaintingStyle.fill;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.2, h * 0.2, w * 0.1, h * 0.6),
            Radius.circular(w * 0.025),
          ),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.76, h * 0.18)
            ..lineTo(w * 0.32, h * 0.5)
            ..lineTo(w * 0.76, h * 0.82)
            ..close(),
          paint,
        );
      case _Glyph.next:
        paint.style = PaintingStyle.fill;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.7, h * 0.2, w * 0.1, h * 0.6),
            Radius.circular(w * 0.025),
          ),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.24, h * 0.18)
            ..lineTo(w * 0.68, h * 0.5)
            ..lineTo(w * 0.24, h * 0.82)
            ..close(),
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
      case _Glyph.pictureInPicture:
      case _Glyph.exitPictureInPicture:
        final outer = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.12, h * 0.2, w * 0.76, h * 0.6),
          Radius.circular(w * 0.08),
        );
        canvas.drawRRect(outer, paint);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.5, h * 0.5, w * 0.27, h * 0.2),
            Radius.circular(w * 0.035),
          ),
          paint,
        );
        if (glyph == _Glyph.exitPictureInPicture) {
          canvas.drawPath(
            Path()
              ..moveTo(w * 0.53, h * 0.5)
              ..lineTo(w * 0.35, h * 0.34)
              ..moveTo(w * 0.35, h * 0.34)
              ..lineTo(w * 0.36, h * 0.5)
              ..moveTo(w * 0.35, h * 0.34)
              ..lineTo(w * 0.51, h * 0.35),
            paint,
          );
        }
      case _Glyph.fullscreen:
      case _Glyph.exitFullscreen:
        final inset = w * 0.16;
        final length = w * 0.25;
        if (glyph == _Glyph.fullscreen) {
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
        } else {
          canvas.drawPath(
            Path()
              ..moveTo(inset, inset + length)
              ..lineTo(inset + length, inset + length)
              ..lineTo(inset + length, inset)
              ..moveTo(w - inset, inset + length)
              ..lineTo(w - inset - length, inset + length)
              ..lineTo(w - inset - length, inset)
              ..moveTo(inset + length, h - inset)
              ..lineTo(inset + length, h - inset - length)
              ..lineTo(inset, h - inset - length)
              ..moveTo(w - inset - length, h - inset)
              ..lineTo(w - inset - length, h - inset - length)
              ..lineTo(w - inset, h - inset - length),
            paint,
          );
        }
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
  bool shouldRepaint(_GlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}

class _PlayerControlButton extends StatelessWidget {
  const _PlayerControlButton({
    required this.glyph,
    required this.label,
    required this.onTap,
    required this.size,
    required this.filled,
    required this.prominent,
    required this.busy,
    required this.toggled,
    required this.style,
  });

  final _Glyph glyph;
  final String label;
  final VoidCallback onTap;
  final double size;
  final bool filled;
  final bool prominent;
  final bool busy;
  final bool? toggled;
  final MithkaVideoChromeStyle style;

  @override
  Widget build(BuildContext context) => _FocusableTapRegion(
    label: label,
    toggled: toggled,
    onTap: busy ? null : onTap,
    borderRadius: BorderRadius.circular(size / 2),
    focusColor: style.focusColor,
    hoverColor: style.hoverColor,
    child: Container(
      width: size,
      height: size,
      decoration: filled
          ? BoxDecoration(
              color: prominent
                  ? style.primaryTransportBackgroundColor
                  : style.transportBackgroundColor,
              shape: BoxShape.circle,
              border: style.transportBorderWidth == 0
                  ? null
                  : Border.all(
                      color: style.transportBorderColor,
                      width: style.transportBorderWidth,
                    ),
              boxShadow: [
                BoxShadow(
                  color: style.transportShadowColor,
                  blurRadius: style.transportShadowBlurRadius,
                  offset: style.transportShadowOffset,
                ),
              ],
            )
          : null,
      alignment: Alignment.center,
      child: busy
          ? SizedBox.square(
              dimension: size * 0.4,
              child: _ActivityIndicator(color: style.foregroundColor),
            )
          : CustomPaint(
              size: Size.square(size * (filled ? 0.42 : 0.48)),
              painter: _GlyphPainter(glyph, style.foregroundColor),
            ),
    ),
  );
}

class _BareTextControlButton extends StatelessWidget {
  const _BareTextControlButton({
    required this.label,
    required this.text,
    required this.onTap,
    required this.style,
  });

  final String label;
  final String text;
  final VoidCallback onTap;
  final MithkaVideoChromeStyle style;

  @override
  Widget build(BuildContext context) => _FocusableTapRegion(
    label: label,
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    focusColor: style.focusColor,
    hoverColor: style.hoverColor,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        style: TextStyle(
          inherit: false,
          color: style.foregroundColor,
          fontSize: 13,
          fontWeight: FontWeight.normal,
          decoration: TextDecoration.none,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ),
  );
}

class _FocusableTapRegion extends StatefulWidget {
  const _FocusableTapRegion({
    required this.label,
    required this.onTap,
    required this.borderRadius,
    required this.focusColor,
    required this.hoverColor,
    required this.child,
    this.toggled,
  });

  final String label;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final Color focusColor;
  final Color hoverColor;
  final Widget child;
  final bool? toggled;

  @override
  State<_FocusableTapRegion> createState() => _FocusableTapRegionState();
}

class _FocusableTapRegionState extends State<_FocusableTapRegion> {
  bool _focused = false;
  bool _hovered = false;

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final onTap = widget.onTap;
    if (onTap == null) return KeyEventResult.ignored;
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space)) {
      onTap();
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space)) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: widget.onTap != null,
    label: widget.label,
    toggled: widget.toggled,
    onTap: widget.onTap,
    child: Focus(
      canRequestFocus: widget.onTap != null,
      onFocusChange: (focused) => setState(() => _focused = focused),
      onKeyEvent: _onKeyEvent,
      child: MouseRegion(
        cursor: widget.onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: widget.onTap == null
            ? null
            : (_) => setState(() => _hovered = true),
        onExit: widget.onTap == null
            ? null
            : (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            decoration: BoxDecoration(
              color: _hovered && widget.onTap != null
                  ? widget.hoverColor
                  : null,
              border: _focused
                  ? Border.all(color: widget.focusColor, width: 2)
                  : null,
              borderRadius: widget.borderRadius,
            ),
            child: widget.child,
          ),
        ),
      ),
    ),
  );
}

class _ActivityIndicator extends StatefulWidget {
  const _ActivityIndicator({this.color = const Color(0xFFFFFFFF)});

  final Color color;

  @override
  State<_ActivityIndicator> createState() => _ActivityIndicatorState();
}

class _ActivityIndicatorState extends State<_ActivityIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: RotationTransition(
      turns: _controller,
      child: CustomPaint(painter: _ActivityIndicatorPainter(widget.color)),
    ),
  );
}

class _ActivityIndicatorPainter extends CustomPainter {
  const _ActivityIndicatorPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = math.max(2.0, size.shortestSide * 0.075);
    final rect = Offset.zero & size;
    canvas.drawArc(
      rect.deflate(strokeWidth / 2),
      -math.pi / 2,
      math.pi * 1.35,
      false,
      Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_ActivityIndicatorPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _TextControlButton extends StatelessWidget {
  const _TextControlButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    label: label,
    onTap: onTap,
    child: FocusableActionDetector(
      enabled: onTap != null,
      mouseCursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            onTap?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0x22FFFFFF),
            border: Border.all(color: const Color(0x55FFFFFF)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
