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

import '../../tdlib/td_client.dart';
import '../../tdlib/td_image_loader.dart';
import '../../tdlib/td_models.dart';

Uint8List _inflateTgsSticker(Uint8List bytes) {
  return Uint8List.fromList(const GZipDecoder().decodeBytes(bytes));
}

final Map<String, Future<Uint8List?>> _inflatedTgsCache = {};

/// Releases inflated sticker JSON after an OS memory warning. Visible stickers
/// retain their own bytes and continue rendering; reopened stickers inflate on
/// demand away from the UI isolate.
void clearAnimatedStickerMemoryCache() {
  _inflatedTgsCache.clear();
  // Without this the parsed compositions — and, through their keys, the byte
  // buffers we just dropped — stay pinned by lottie, so a memory warning frees
  // nothing. Mounted widgets hold their own composition future and keep playing.
  Lottie.cache.clear();
}

bool _lottieCacheBounded = false;

/// lottie's shared composition cache holds 1000 entries by default and nothing
/// ever trims it, so every sticker parsed this session is retained. Its key is
/// the byte buffer's identity, so a sticker evicted from `_inflatedTgsCache`
/// and re-inflated parks a *second* composition under a new key.
void _boundLottieCache() {
  if (_lottieCacheBounded) return;
  _lottieCacheBounded = true;
  Lottie.cache.maximumSize = defaultTargetPlatform == TargetPlatform.android
      ? 128
      : 256;
}

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

Future<LottieComposition?> _prewarmTgsComposition(
  Uint8List bytes,
  bool Function() stillWanted,
) async {
  _boundLottieCache();
  if (_activeTgsParses >= _maxConcurrentTgsParses) {
    final turn = Completer<void>();
    _tgsParseQueue.add(turn);
    await turn.future;
    // A flick through a sticker pack queues every cell it passes. Parsing the
    // ones already recycled would push the cells still on screen behind them,
    // so hand the slot straight on instead.
    if (!stillWanted()) {
      if (_tgsParseQueue.isNotEmpty) _tgsParseQueue.removeAt(0).complete();
      return null;
    }
  }
  _activeTgsParses++;
  try {
    // Lands in lottie's own `sharedLottieCache`, keyed on the byte buffer, so
    // a remount of the same sticker resolves without parsing again.
    return await MemoryLottie(bytes, backgroundLoading: true).load();
  } catch (_) {
    // A broken composition simply renders as its placeholder frame.
    return null;
  } finally {
    _activeTgsParses--;
    if (_tgsParseQueue.isNotEmpty) _tgsParseQueue.removeAt(0).complete();
  }
}

/// The controller that drives a sticker loop.
///
/// Lottie's built-in controller is stopped and restarted by every parent
/// rebuild (a busy chat row rebuilds on reactions, read state, selection) and
/// inherits the platform's reduced-motion scale. A sticker is content with an
/// authored three-second loop, so it gets one long-lived controller per
/// composition that is started once and preserves its duration
/// ([AnimationBehavior.preserve]) — Telegram's rlottie loop is likewise
/// independent of the UI animation scale.
@visibleForTesting
AnimationController createStickerPlaybackController({
  required TickerProvider vsync,
  required Duration duration,
}) => AnimationController(
  vsync: vsync,
  duration: duration,
  animationBehavior: AnimationBehavior.preserve,
);

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

class _AnimatedStickerViewState extends State<AnimatedStickerView>
    with SingleTickerProviderStateMixin {
  LottieComposition? _composition;
  AnimationController? _playback;
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
    if (old.animate != widget.animate) {
      final playback = _playback;
      if (playback != null) _applyPlayback(playback);
    }
    _load();
  }

  @override
  void dispose() {
    _playback?.dispose();
    super.dispose();
  }

  void _applyPlayback(AnimationController playback) {
    if (widget.animate) {
      playback.repeat();
    } else {
      playback
        ..stop()
        ..value = 0;
    }
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
    final composition = await _prewarmTgsComposition(
      inflated,
      () => mounted && _loadedId == ref.id,
    );
    if (!mounted || _loadedId != ref.id || composition == null) return;
    final playback =
        _playback ??
        createStickerPlaybackController(
          vsync: this,
          duration: composition.duration,
        );
    // A recycled cell gets a new sticker: rewind before the new composition
    // paints, so the first visible frame is its first frame.
    playback
      ..duration = composition.duration
      ..value = 0;
    _applyPlayback(playback);
    setState(() {
      _composition = composition;
      _playback = playback;
    });
    widget.onReady?.call();
  }

  @override
  Widget build(BuildContext context) {
    final composition = _composition;
    final playback = _playback;
    if (composition == null || playback == null) {
      return const SizedBox.expand();
    }
    // Our own controller survives parent rebuilds: lottie's built-in one is
    // stopped and restarted by every didUpdateWidget, which a busy chat row
    // (reactions, read state, selection) triggers often.
    return Lottie(
      composition: composition,
      controller: playback,
      fit: BoxFit.contain,
      frameRate: widget.frameRate,
    );
  }
}
