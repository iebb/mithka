//
//  animated_sticker_view.dart
//
//  Renders a Telegram `.tgs` sticker — gzipped Lottie JSON. We resolve the file
//  via TDFileCenter, gunzip it (the `archive` package), and play it with the
//  `lottie` package. Port of the Swift `AnimatedStickerView` + `Gzip` (which
//  used the Compression framework + lottie-ios).
//

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../tdlib/td_client.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';

Uint8List _inflateTgsSticker(Uint8List bytes) {
  return Uint8List.fromList(GZipDecoder().decodeBytes(bytes));
}

final Map<String, Future<Uint8List?>> _inflatedTgsCache = {};

int get _maxInflatedTgsCacheEntries =>
    defaultTargetPlatform == TargetPlatform.android ? 32 : 80;

Future<Uint8List?> _loadInflatedTgsSticker(String cacheKey, String path) {
  final cached = _inflatedTgsCache.remove(cacheKey);
  if (cached != null) {
    _inflatedTgsCache[cacheKey] = cached;
    return cached;
  }

  final future = File(path)
      .readAsBytes()
      .then((bytes) => compute(_inflateTgsSticker, bytes))
      .then<Uint8List?>((bytes) => bytes)
      .catchError((_) {
        _inflatedTgsCache.remove(cacheKey);
        return null;
      });
  _inflatedTgsCache[cacheKey] = future;
  while (_inflatedTgsCache.length > _maxInflatedTgsCacheEntries) {
    _inflatedTgsCache.remove(_inflatedTgsCache.keys.first);
  }
  return future;
}

class AnimatedStickerView extends StatefulWidget {
  const AnimatedStickerView({
    super.key,
    required this.file,
    this.onReady,
    this.frameRate,
  });
  final TdFileRef file;
  final VoidCallback? onReady;

  /// Playback frame rate; null keeps the composition's own rate. Inline
  /// custom emoji pass a reduced rate — at text size the difference is
  /// invisible but the repaint cost is not.
  final FrameRate? frameRate;

  @override
  State<AnimatedStickerView> createState() => _AnimatedStickerViewState();
}

class _AnimatedStickerViewState extends State<AnimatedStickerView> {
  Uint8List? _bytes;
  int? _loadedId;
  int? _loadedSlot;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AnimatedStickerView old) {
    super.didUpdateWidget(old);
    _load();
  }

  Future<void> _load() async {
    final ref = widget.file;
    final slot = TdClient.shared.activeSlot;
    if (_loadedId == ref.id && _loadedSlot == slot) return;
    _loadedId = ref.id;
    _loadedSlot = slot;

    final path = await TdFileCenter.shared.pathFor(ref);
    if (!mounted || path == null || _loadedId != ref.id) return;
    // .tgs = gzipped Lottie JSON. Inflate away from the UI isolate and reuse
    // decoded bytes across recycled chat rows / emoji-grid cells.
    final inflated = await _loadInflatedTgsSticker('$slot:${ref.id}', path);
    if (!mounted || _loadedId != ref.id || inflated == null) return;
    setState(() => _bytes = inflated);
    widget.onReady?.call();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return const SizedBox.expand();
    return Lottie.memory(
      bytes,
      fit: BoxFit.contain,
      repeat: true,
      frameRate: widget.frameRate,
    );
  }
}
