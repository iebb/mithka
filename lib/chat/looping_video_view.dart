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
  int? _loadedSlot;
  bool _tickerEnabled = false;
  bool _appIsActive = true;

  bool get _shouldPlay => _tickerEnabled && _appIsActive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appIsActive =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    if (_tickerEnabled == enabled) return;
    _tickerEnabled = enabled;
    if (enabled && _controller == null) {
      unawaited(_load());
    } else {
      unawaited(_syncPlayback());
    }
  }

  @override
  void didUpdateWidget(LoopingVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.id != widget.file.id ||
        oldWidget.file.localPath != widget.file.localPath ||
        _loadedSlot != TdClient.shared.activeSlot) {
      unawaited(_load());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appIsActive = state == AppLifecycleState.resumed;
    unawaited(_syncPlayback());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final ref = widget.file;
    final slot = TdClient.shared.activeSlot;
    _loadedSlot = slot;

    final old = _controller;
    _controller = null;
    if (old != null) {
      await old.dispose();
      if (mounted && generation == _generation) setState(() {});
    }

    final path = await TdFileCenter.shared.pathFor(ref);
    if (!mounted ||
        generation != _generation ||
        slot != TdClient.shared.activeSlot ||
        path == null) {
      return;
    }

    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      if (_shouldPlay) await controller.play();
    } catch (_) {
      await controller.dispose();
      return;
    }
    if (!mounted ||
        generation != _generation ||
        slot != TdClient.shared.activeSlot) {
      await controller.dispose();
      return;
    }
    setState(() => _controller = controller);
  }

  Future<void> _syncPlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      if (_shouldPlay) {
        await controller.play();
      } else {
        await controller.pause();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    unawaited(_controller?.dispose());
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
