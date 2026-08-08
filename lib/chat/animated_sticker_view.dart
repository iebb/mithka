//
//  animated_sticker_view.dart
//
//  Renders a Telegram `.tgs` sticker — gzipped Lottie JSON. We resolve the file
//  via TDFileCenter, gunzip it (the `archive` package), and play it with the
//  `lottie` package. Port of the Swift `AnimatedStickerView` + `Gzip` (which
//  used the Compression framework + lottie-ios).
//

import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../tdlib/td_client.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';

Uint8List _inflateTgsSticker(Uint8List bytes) {
  return Uint8List.fromList(const GZipDecoder().decodeBytes(bytes));
}

final Map<String, Future<Uint8List?>> _inflatedTgsCache = {};

/// Releases inflated sticker JSON after an OS memory warning. Visible stickers
/// retain their own bytes and continue rendering; reopened stickers inflate on
/// demand away from the UI isolate.
void clearAnimatedStickerMemoryCache() => _inflatedTgsCache.clear();

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

/// Lottie parses the inflated JSON on whichever isolate asks for it, so a
/// composition that first loads inside `build` costs that frame a 50 KB–1 MB
/// JSON parse. We warm it off the UI isolate instead — capped, because
/// `compute` spawns an isolate per call and an emoji grid mounts dozens of
/// distinct stickers at once.
const int _maxConcurrentTgsParses = 2;
int _activeTgsParses = 0;
final List<Completer<void>> _tgsParseQueue = <Completer<void>>[];

Future<void> _prewarmTgsComposition(
  Uint8List bytes,
  bool Function() stillWanted,
) async {
  if (_activeTgsParses >= _maxConcurrentTgsParses) {
    final turn = Completer<void>();
    _tgsParseQueue.add(turn);
    await turn.future;
    // A flick through a sticker pack queues every cell it passes. Parsing the
    // ones already recycled would push the cells still on screen behind them,
    // so hand the slot straight on instead.
    if (!stillWanted()) {
      if (_tgsParseQueue.isNotEmpty) _tgsParseQueue.removeAt(0).complete();
      return;
    }
  }
  _activeTgsParses++;
  try {
    // Lands in lottie's own `sharedLottieCache`, keyed on the byte buffer, so
    // the `Lottie.memory` in build resolves without parsing again.
    await MemoryLottie(bytes, backgroundLoading: true).load();
  } catch (_) {
    // Let the Lottie widget surface a broken composition on its own.
  } finally {
    _activeTgsParses--;
    if (_tgsParseQueue.isNotEmpty) _tgsParseQueue.removeAt(0).complete();
  }
}

class AnimatedStickerView extends StatefulWidget {
  const AnimatedStickerView({
    super.key,
    required this.file,
    this.onReady,
    this.frameRate,
    this.animate = true,
  });
  final TdFileRef file;
  final VoidCallback? onReady;
  final bool animate;

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
    await _prewarmTgsComposition(
      inflated,
      () => mounted && _loadedId == ref.id,
    );
    if (!mounted || _loadedId != ref.id) return;
    setState(() => _bytes = inflated);
    widget.onReady?.call();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return const SizedBox.expand();
    return Lottie.memory(
      bytes,
      backgroundLoading: true,
      fit: BoxFit.contain,
      animate: widget.animate,
      repeat: widget.animate,
      frameRate: widget.frameRate,
    );
  }
}
