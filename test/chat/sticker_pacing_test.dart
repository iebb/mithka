//
//  Mithka video stickers: which player a file gets, and where a looping
//  sticker may hold a native player.
//
//  MDK (fvp) loops a video-only clip at its last frame's timestamp instead of
//  the container duration, dropping that frame's hold every pass — 25% of a
//  five-frame 0.4 s sticker, 1% of a three-second one, which is why only short,
//  low-frame-rate stickers were reported as racing. None of that is fixable
//  from the playback rate (MDK compounds the rate at every loop restart), so a
//  sticker without alpha is routed to the platform player, which loops it at
//  its authored duration. The header's AlphaMode decides.
//

import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/media/looping_media_playback.dart';
import 'package:mithka/media/webm_header.dart';

/// A minimal EBML element: id bytes, a one-byte size, then the payload.
Uint8List _element(int id, List<int> payload) {
  final idBytes = <int>[];
  var remaining = id;
  while (remaining > 0) {
    idBytes.insert(0, remaining & 0xff);
    remaining >>= 8;
  }
  return Uint8List.fromList([...idBytes, 0x80 | payload.length, ...payload]);
}

/// Telegram's stickers put AlphaMode on the track's video element.
Uint8List _webm({int? alphaMode}) {
  final track = _element(0xAE, [
    ..._element(0x86, 'V_VP9'.codeUnits),
    ..._element(0xE0, [
      ..._element(0xB0, [0x02, 0x00]),
      if (alphaMode != null) ..._element(0x53C0, [alphaMode]),
    ]),
  ]);
  final segment = _element(0x18538067, [
    ..._element(0x1549A966, [
      ..._element(0x2AD7B1, [0x0f, 0x42, 0x40]),
    ]),
    ..._element(0x1654AE6B, track),
  ]);
  return Uint8List.fromList([
    ..._element(0x1a45dfa3, [
      0x42,
      0x86,
      0x81,
      0x01,
      0x42,
      0x82,
      0x84,
      0x77,
      0x65,
      0x62,
      0x6d,
    ]),
    ...segment,
  ]);
}

void main() {
  group('webmHasAlpha', () {
    test('AlphaMode 1 on the video track means the sticker has alpha', () {
      expect(webmHasAlpha(_webm(alphaMode: 1)), isTrue);
    });

    test('a track without AlphaMode has none', () {
      expect(webmHasAlpha(_webm()), isFalse);
    });

    test('AlphaMode 0 is not alpha', () {
      expect(webmHasAlpha(_webm(alphaMode: 0)), isFalse);
    });

    test('garbage is not mistaken for an alpha sticker', () {
      expect(webmHasAlpha(Uint8List.fromList([1, 2, 3])), isFalse);
      expect(webmHasAlpha(Uint8List(0)), isFalse);
    });
  });

  group('loopingSurfaceIsOnScreen', () {
    const screen = Size(400, 800);

    test('a sticker inside the viewport plays', () {
      expect(
        loopingSurfaceIsOnScreen(
          rect: const Rect.fromLTWH(20, 300, 160, 160),
          screen: screen,
        ),
        isTrue,
      );
    });

    test('a cached child above the viewport does not hold a player', () {
      expect(
        loopingSurfaceIsOnScreen(
          rect: const Rect.fromLTWH(20, -400, 160, 160),
          screen: screen,
        ),
        isFalse,
      );
    });

    test('the margin keeps a sticker alive across a short overscroll', () {
      // Ends 60 px above the viewport: gone, but still inside the margin.
      const rect = Rect.fromLTWH(20, -220, 160, 160);
      expect(loopingSurfaceIsOnScreen(rect: rect, screen: screen), isFalse);
      expect(
        loopingSurfaceIsOnScreen(rect: rect, screen: screen, margin: 96),
        isTrue,
      );
    });

    test('a sticker hands its player back when it leaves and asks again', () {
      final visibility = LoopingSurfaceVisibility(margin: 64);
      expect(visibility.isOnScreen, isTrue);
      expect(
        visibility.update(
          rect: const Rect.fromLTWH(0, 300, 160, 160),
          screen: screen,
        ),
        isFalse,
      );
      expect(
        visibility.update(
          rect: const Rect.fromLTWH(0, -600, 160, 160),
          screen: screen,
        ),
        isTrue,
      );
      expect(visibility.isOnScreen, isFalse);
      expect(
        visibility.update(
          rect: const Rect.fromLTWH(0, -600, 160, 160),
          screen: screen,
        ),
        isFalse,
      );
      expect(
        visibility.update(
          rect: const Rect.fromLTWH(0, 100, 160, 160),
          screen: screen,
        ),
        isTrue,
      );
      expect(visibility.isOnScreen, isTrue);
    });

    test('a surface without a render box keeps its current state', () {
      final visibility = LoopingSurfaceVisibility();
      expect(visibility.update(rect: null, screen: screen), isFalse);
      expect(visibility.isOnScreen, isTrue);
    });

    test('an unlaid-out surface is not treated as visible', () {
      expect(
        loopingSurfaceIsOnScreen(rect: Rect.zero, screen: screen),
        isFalse,
      );
    });
  });

  test('the sticker budget covers a full viewport of stickers', () {
    // A sticker picker page shows a dozen or more cells at once; anything
    // smaller is what left only the first cell of the grid animating.
    expect(stickerPlayerPool.maximumPlayers, greaterThanOrEqualTo(20));
    final leases = [
      for (var i = 0; i < 12; i++) stickerPlayerPool.tryAcquire(),
    ];
    expect(leases, everyElement(isNotNull));
    for (final lease in leases) {
      lease!.release();
    }
  });
}
