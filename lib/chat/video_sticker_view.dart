//
//  video_sticker_view.dart
//
//  Renders a Telegram `.webm` (VP9 + alpha) video sticker. video_player can't
//  show the alpha (it composites transparency as black), so instead we transcode
//  the webm to an animated WebP with FFmpeg (alpha preserved) and let Flutter's
//  Image animate it — transparent AND animated, and works on iOS too. The WebP
//  is cached on disk and one transcode is shared across every bubble showing the
//  same sticker.
//

import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';

import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';

class VideoStickerView extends StatefulWidget {
  const VideoStickerView({super.key, required this.file, this.onReady});
  final TdFileRef file;
  final VoidCallback? onReady;

  @override
  State<VideoStickerView> createState() => _VideoStickerViewState();
}

class _VideoStickerViewState extends State<VideoStickerView> {
  // One transcode per sticker file id, shared across all bubbles + cached.
  static final Map<int, Future<String?>> _transcodes = {};
  String? _webp;
  int? _loadedId;

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
    final webp = await _transcodes.putIfAbsent(ref.id, () => _transcode(ref.id));
    if (!mounted || _loadedId != ref.id || webp == null) return;
    setState(() => _webp = webp);
    widget.onReady?.call();
  }

  /// webm (VP9 + alpha) → animated WebP (alpha preserved). Cached next to the
  /// source file. Two flags are load-bearing:
  ///   * `-c:v libvpx-vp9` (BEFORE -i) forces the libvpx decoder — FFmpeg's
  ///     default *native* vp9 decoder silently drops the alpha layer (decodes
  ///     yuv420p), which is exactly what produced the opaque/black sticker.
  ///     libvpx-vp9 decodes the alpha plane → yuva420p.
  ///   * `-c:v libwebp -loop 0` emits a looping *animated* WebP with alpha.
  static Future<String?> _transcode(int fileId) async {
    final src = await TdFileCenter.shared.path(fileId);
    if (src == null) return null;
    final out = '$src.anim.webp';
    final cached = File(out);
    if (cached.existsSync() && cached.lengthSync() > 0) return out;
    final session = await FFmpegKit.execute(
      '-y -c:v libvpx-vp9 -i "$src" -an -c:v libwebp -loop 0 -lossless 0 '
      '-compression_level 4 -q:v 70 "$out"',
    );
    final rc = await session.getReturnCode();
    if (ReturnCode.isSuccess(rc) &&
        cached.existsSync() &&
        cached.lengthSync() > 0) {
      return out;
    }
    debugPrint(
      'VideoSticker: transcode failed rc=${rc?.getValue()} '
      'out=${cached.existsSync() ? cached.lengthSync() : "missing"}\n'
      '${await session.getOutput()}',
    );
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final webp = _webp;
    if (webp == null) return const SizedBox.expand();
    return Image.file(File(webp), fit: BoxFit.contain, gaplessPlayback: true);
  }
}
