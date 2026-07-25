//
//  looping_video_view.dart
//
//  Muted, lifecycle-aware playback for Telegram animations. The thumbnail
//  remains visible while TDLib downloads the file and the decoder prepares
//  its first frame.
//

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../components/photo_avatar.dart';
import '../media/looping_media_playback.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';

class LoopingVideoView extends StatefulWidget {
  const LoopingVideoView({
    super.key,
    required this.file,
    this.fallback,
    this.fit = BoxFit.contain,
    this.showDownloadProgress = false,
  });

  final TdFileRef file;
  final TdFileRef? fallback;
  final BoxFit fit;
  final bool showDownloadProgress;

  @override
  State<LoopingVideoView> createState() => _LoopingVideoViewState();
}

class _LoopingVideoViewState extends State<LoopingVideoView>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  int _generation = 0;
  int? _loadedId;
  String? _loadedLocalPath;
  int? _loadedSlot;
  bool _tickerEnabled = false;
  bool _appIsActive = true;
  bool _loadPending = false;
  LoopingMediaPlayerLease? _lease;
  LoopingMediaPlayerWaiter? _leaseWaiter;
  VideoPlayerController? _initializingController;

  bool get _isEligible => loopingMediaPlaybackIsEligible(
    tickerEnabled: _tickerEnabled,
    appIsActive: _appIsActive,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appIsActive =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    addLoopingMediaPlaybackContextListener(_handlePlaybackContextChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _reconcilePlayback(rebuildOnRelease: false);
  }

  @override
  void didUpdateWidget(LoopingVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reconcilePlayback(rebuildOnRelease: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appIsActive = state == AppLifecycleState.resumed;
    _reconcilePlayback();
  }

  void _handlePlaybackContextChanged() {
    if (!mounted) return;
    _reconcilePlayback();
  }

  void _reconcilePlayback({bool rebuildOnRelease = true}) {
    final slot = TdClient.shared.activeSlot;
    final sourceChanged =
        _loadedId != widget.file.id ||
        _loadedLocalPath != widget.file.localPath ||
        _loadedSlot != slot;
    if (!_isEligible || sourceChanged) {
      _releasePlayback(rebuild: rebuildOnRelease);
    }
    if (!_isEligible) return;
    if (sourceChanged) {
      _loadedId = widget.file.id;
      _loadedLocalPath = widget.file.localPath;
      _loadedSlot = slot;
    }
    if (_controller == null && !_loadPending && _leaseWaiter == null) {
      _requestPlaybackLease();
    }
  }

  void _requestPlaybackLease() {
    if (!_isEligible ||
        _loadPending ||
        _controller != null ||
        _leaseWaiter != null) {
      return;
    }
    final ref = widget.file;
    final slot = TdClient.shared.activeSlot;
    final generation = ++_generation;
    final lease = loopingMediaPlayerPool.tryAcquire();
    if (lease != null) {
      _startLoad(lease, generation, ref, slot);
      return;
    }

    late final LoopingMediaPlayerWaiter waiter;
    waiter = loopingMediaPlayerPool.waitForLease((grantedLease) {
      if (identical(_leaseWaiter, waiter)) _leaseWaiter = null;
      if (!_ownsAttempt(generation, ref, slot)) {
        grantedLease.release();
        return;
      }
      _startLoad(grantedLease, generation, ref, slot);
    });
    _leaseWaiter = waiter;
  }

  void _startLoad(
    LoopingMediaPlayerLease lease,
    int generation,
    TdFileRef ref,
    int slot,
  ) {
    if (!_ownsAttempt(generation, ref, slot)) {
      lease.release();
      return;
    }
    _lease = lease;
    _loadPending = true;
    unawaited(_loadWithLease(lease, generation, ref, slot));
  }

  Future<void> _loadWithLease(
    LoopingMediaPlayerLease lease,
    int generation,
    TdFileRef ref,
    int slot,
  ) async {
    if (!_ownsLoad(generation, ref, slot, lease)) {
      _clearLoadLease(lease);
      return;
    }

    final path = await TdFileCenter.shared.pathFor(ref);
    if (!_ownsLoad(generation, ref, slot, lease)) {
      _clearLoadLease(lease);
      return;
    }
    if (path == null) {
      _clearLoadLease(lease);
      return;
    }

    final controller = VideoPlayerController.file(File(path));
    _initializingController = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      disableLoopingMediaAudioTracks(controller);
      if (!_ownsLoad(generation, ref, slot, lease)) {
        await _disposeInitializingLoad(controller, lease);
        return;
      }
      await controller.play();
    } catch (_) {
      await _disposeInitializingLoad(controller, lease);
      return;
    }
    if (!_ownsLoad(generation, ref, slot, lease)) {
      await _disposeInitializingLoad(controller, lease);
      return;
    }
    if (identical(_initializingController, controller)) {
      _initializingController = null;
    }
    _loadPending = false;
    setState(() => _controller = controller);
  }

  bool _ownsAttempt(int generation, TdFileRef ref, int slot) =>
      mounted &&
      _isEligible &&
      generation == _generation &&
      _loadedId == ref.id &&
      _loadedLocalPath == ref.localPath &&
      _loadedSlot == slot &&
      slot == TdClient.shared.activeSlot;

  bool _ownsLoad(
    int generation,
    TdFileRef ref,
    int slot,
    LoopingMediaPlayerLease lease,
  ) =>
      mounted &&
      _isEligible &&
      generation == _generation &&
      _loadedId == ref.id &&
      _loadedLocalPath == ref.localPath &&
      _loadedSlot == slot &&
      slot == TdClient.shared.activeSlot &&
      identical(_lease, lease) &&
      !lease.isReleased;

  void _clearLoadLease(LoopingMediaPlayerLease lease) {
    if (identical(_lease, lease)) {
      _lease = null;
      _loadPending = false;
      lease.release();
    }
  }

  Future<void> _disposeInitializingLoad(
    VideoPlayerController controller,
    LoopingMediaPlayerLease lease,
  ) async {
    if (!identical(_initializingController, controller)) return;
    _initializingController = null;
    final ownsLease = identical(_lease, lease);
    if (ownsLease) {
      _lease = null;
    }
    try {
      await controller.dispose();
    } catch (_) {
      // Native teardown failures must not become uncaught async errors.
    } finally {
      if (ownsLease) {
        if (_lease == null && _initializingController == null) {
          _loadPending = false;
        }
        lease.release();
      }
    }
  }

  void _releasePlayback({bool rebuild = true}) {
    ++_generation;
    _leaseWaiter?.cancel();
    _leaseWaiter = null;
    _loadPending = false;
    final controller = _controller;
    final initializingController = _initializingController;
    final lease = _lease;
    _controller = null;
    _initializingController = null;
    _lease = null;
    final controllers = <VideoPlayerController>{
      ?controller,
      ?initializingController,
    };
    if (controllers.isEmpty) {
      lease?.release();
    } else {
      unawaited(_disposeReleasedControllers(controllers, lease));
    }
    if (controller != null && rebuild && mounted) setState(() {});
  }

  Future<void> _disposeReleasedControllers(
    Set<VideoPlayerController> controllers,
    LoopingMediaPlayerLease? lease,
  ) async {
    try {
      await Future.wait(
        controllers.map((current) async {
          try {
            await current.dispose();
          } catch (_) {
            // Continue tearing down the remaining native players.
          }
        }),
      );
    } finally {
      lease?.release();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    removeLoopingMediaPlaybackContextListener(_handlePlaybackContextChanged);
    _releasePlayback(rebuild: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.fallback case final fallback?)
          TDImage(
            photo: fallback,
            cornerRadius: 0,
            fit: widget.fit,
            showProgress: widget.showDownloadProgress,
          ),
        if (controller != null && controller.value.isInitialized)
          FittedBox(
            fit: widget.fit,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
      ],
    );
  }
}
