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

  /// webm (VP9 + alpha) → a looping, alpha-correct animation, cached next to the
  /// source. `-c:v libvpx-vp9` (BEFORE -i) is mandatory: FFmpeg's default native
  /// vp9 decoder drops the alpha layer (yuv420p), which gave the opaque/black
  /// sticker; libvpx-vp9 decodes the alpha plane (yuva420p).
  ///
  /// The container is chosen by transparency, because each one is wrong for the
  /// other case:
  ///   * Transparent stickers → APNG (`-f apng`). FFmpeg's libwebp_anim encoder
  ///     hard-codes every WebP frame to blend=yes / dispose=none (no AVOption
  ///     exposes the WebPAnimEncoder knobs), so a moving transparent sticker's
  ///     earlier frames bleed through later frames' transparent pixels → ghost
  ///     trails. APNG instead carries proper per-frame dispose ops → no trails.
  ///   * Opaque stickers (full-frame "video" stickers) → lossy animated WebP.
  ///     Opaque frames fully overwrite the canvas, so blend=yes never trails,
  ///     and lossy WebP is a fraction of the size of a lossless APNG of the same
  ///     photographic clip (which can run to tens of MB).
  /// Flutter's Image animates both APNG and WebP natively, with alpha, on iOS
  /// and Android.
  static Future<String?> _transcode(int fileId) async {
    final src = await TdFileCenter.shared.path(fileId);
    if (src == null) return null;
    // Version suffix: bump whenever the ffmpeg recipe changes so stale caches
    // from an older encoding aren't reused.
    final apng = File('$src.anim.v3.png');
    final webp = File('$src.anim.v3.webp');
    if (apng.existsSync() && apng.lengthSync() > 0) return apng.path;
    if (webp.existsSync() && webp.lengthSync() > 0) return webp.path;

    final transparent = await _hasTransparency(src);
    final out = transparent ? apng.path : webp.path;
    final cmd = transparent
        ? '-y -c:v libvpx-vp9 -i "$src" -an -f apng -plays 0 "$out"'
        : '-y -c:v libvpx-vp9 -i "$src" -an -c:v libwebp -q:v 75 -loop 0 "$out"';
    final session = await FFmpegKit.execute(cmd);
    final rc = await session.getReturnCode();
    final f = File(out);
    if (ReturnCode.isSuccess(rc) && f.existsSync() && f.lengthSync() > 0) {
      return out;
    }
    debugPrint(
      'VideoSticker: transcode failed rc=${rc?.getValue()} '
      'transparent=$transparent\n${await session.getOutput()}',
    );
    return null;
  }

  /// Whether any decoded frame has a transparent pixel. Telegram tags both
  /// transparent character stickers and opaque "video" stickers with alpha_mode,
  /// so we actually inspect the alpha plane: alphaextract → per-frame YMIN, and
  /// treat the clip as transparent if the minimum alpha dips below ~opaque.
  static Future<bool> _hasTransparency(String src) async {
    final session = await FFmpegKit.execute(
      '-hide_banner -c:v libvpx-vp9 -i "$src" -vf '
      '"alphaextract,signalstats,metadata=print:key=lavfi.signalstats.YMIN" '
      '-f null -',
    );
    final out = await session.getOutput() ?? '';
    var minY = 255;
    for (final m in RegExp(r'YMIN=(\d+)').allMatches(out)) {
      final v = int.tryParse(m.group(1)!) ?? 255;
      if (v < minY) minY = v;
    }
    // No YMIN lines → alphaextract found no alpha plane → treat as opaque.
    return minY < 250;
  }

  @override
  Widget build(BuildContext context) {
    final webp = _webp;
    if (webp == null) return const SizedBox.expand();
    return Image.file(File(webp), fit: BoxFit.contain, gaplessPlayback: true);
  }
}
