//
//  video_sticker_view.dart
//
//  Plays a Telegram `.webm` (VP9 + alpha) video sticker, looping + muted when the
//  MDK/FFmpeg backend is available. Android 14+ skips fvp because libmdk crashes
//  during native load there, so those devices render TDLib's static thumbnail.
//

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../components/photo_avatar.dart';
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

class _VideoStickerViewState extends State<VideoStickerView> {
  VideoPlayerController? _controller;
  int? _loadedId;
  bool _fallbackOnly = false;

  static Future<bool>? _androidNeedsStaticFallback;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(VideoStickerView old) {
    super.didUpdateWidget(old);
    _load();
  }

  Future<void> _load() async {
    final ref = widget.file;
    if (_loadedId == ref.id) return;
    _loadedId = ref.id;
    _fallbackOnly = false;

    final old = _controller;
    if (old != null) {
      _controller = null;
      if (mounted) setState(() {});
      await old.dispose();
    }

    final fallbackOnly = await _useStaticFallbackOnly();
    if (!mounted || _loadedId != ref.id) return;
    if (fallbackOnly) {
      setState(() => _fallbackOnly = true);
      widget.onReady?.call();
      return;
    }

    final path = await TdFileCenter.shared.pathFor(ref);
    if (!mounted || path == null || _loadedId != ref.id) return;

    final c = VideoPlayerController.file(File(path));
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      await c.play();
    } catch (_) {
      await c.dispose();
      if (mounted && _loadedId == ref.id) {
        setState(() => _fallbackOnly = true);
        widget.onReady?.call();
      }
      return;
    }
    if (!mounted || _loadedId != ref.id) {
      await c.dispose();
      return;
    }
    setState(() => _controller = c);
    widget.onReady?.call();
  }

  static Future<bool> _useStaticFallbackOnly() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(false);
    }
    return _androidNeedsStaticFallback ??= _androidSdkInt().then(
      (sdkInt) => sdkInt == null || sdkInt >= 34,
    );
  }

  static Future<int?> _androidSdkInt() async {
    try {
      final info = await const MethodChannel(
        'mithka/app_info',
      ).invokeMapMethod<String, Object?>('info');
      final sdkInt = info?['sdkInt'];
      return sdkInt is int ? sdkInt : null;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
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
