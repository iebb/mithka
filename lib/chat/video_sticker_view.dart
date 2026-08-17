//
//  video_sticker_view.dart
//
//  Plays a Telegram `.webm` (VP9 + alpha) video sticker, looping + muted.
//  Android routes files from TDLib's sticker cache through the scoped FVP
//  software decoder so VP9 alpha is preserved without affecting normal video.
//

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../components/photo_avatar.dart';
import '../media/looping_media_playback.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';

class VideoStickerView extends StatefulWidget {
  const VideoStickerView({
    super.key,
    required this.file,
    this.fallback,
    this.onReady,
  });
  final TdFileRef file;
  final TdFileRef? fallback;
  final VoidCallback? onReady;

  @override
  State<VideoStickerView> createState() => _VideoStickerViewState();
}

class _VideoStickerViewState extends State<VideoStickerView>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  int? _loadedId;
  String? _loadedLocalPath;
  int? _loadedSlot;
  bool _fallbackOnly = false;
  bool _tickerEnabled = false;
  bool _appIsActive = true;
  bool _loadPending = false;
  int _generation = 0;
  LoopingMediaPlayerLease? _lease;
  LoopingMediaPlayerWaiter? _leaseWaiter;
  VideoPlayerController? _initializingController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appIsActive =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    addLoopingMediaPlaybackContextListener(_handlePlaybackContextChanged);
  }

  bool get _isEligible => loopingMediaPlaybackIsEligible(
    tickerEnabled: _tickerEnabled,
    appIsActive: _appIsActive,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _reconcilePlayback(rebuildOnRelease: false);
  }

  @override
  void didUpdateWidget(VideoStickerView old) {
    super.didUpdateWidget(old);
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
      _fallbackOnly = false;
    }
    if (!_fallbackOnly &&
        _controller == null &&
        !_loadPending &&
        _leaseWaiter == null) {
      _requestPlaybackLease();
    }
  }

  void _requestPlaybackLease() {
    if (!_isEligible ||
        _fallbackOnly ||
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

    final fallbackOnly = await _useStaticFallbackOnly();
    if (!_ownsLoad(generation, ref, slot, lease)) {
      _clearLoadLease(lease);
      return;
    }
    if (fallbackOnly) {
      _fallbackOnly = true;
      _clearLoadLease(lease);
      setState(() {});
      widget.onReady?.call();
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

    final c = VideoPlayerController.file(
      File(path),
      videoPlayerOptions: mutedLoopingVideoPlayerOptions(),
    );
    _initializingController = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      disableLoopingMediaAudioTracks(c);
      if (!_ownsLoad(generation, ref, slot, lease)) {
        await _disposeInitializingLoad(c, lease);
        return;
      }
      await c.play();
    } catch (_) {
      final ownsCurrentSource = _ownsLoad(generation, ref, slot, lease);
      if (ownsCurrentSource) {
        _fallbackOnly = true;
      }
      await _disposeInitializingLoad(c, lease);
      if (ownsCurrentSource && _ownsAttempt(generation, ref, slot)) {
        setState(() {});
        widget.onReady?.call();
      }
      return;
    }
    if (!_ownsLoad(generation, ref, slot, lease)) {
      await _disposeInitializingLoad(c, lease);
      return;
    }
    if (identical(_initializingController, c)) {
      _initializingController = null;
    }
    _loadPending = false;
    setState(() => _controller = c);
    widget.onReady?.call();
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

  static Future<bool> _useStaticFallbackOnly() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(false);
    }
    return Future.value(false);
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
    final c = _controller;
    if (c == null || !c.value.isInitialized || _fallbackOnly) {
      final fallback = widget.fallback;
      if (fallback == null) return const SizedBox.expand();
      return TDImage(photo: fallback, cornerRadius: 0, fit: BoxFit.contain);
    }
    return VideoPlayer(c);
  }
}
