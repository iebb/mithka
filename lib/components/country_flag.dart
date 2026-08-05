import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Draws one country flag from the shared sprite sheet.
///
/// The sheet is a 26x26 grid built by `tool/build_flag_sprite.py` from
/// Tossface's SVG release, laid out so a flag's cell is its own ISO letters —
/// column from the first, row from the second. Nothing maps a code to a
/// position, so there is no list to keep in step with the artwork.
class CountryFlag extends StatelessWidget {
  const CountryFlag({
    super.key,
    required this.iso,
    this.size = FlagSprite.cell,
  });

  final String iso;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cell = FlagSprite.cellFor(iso);
    // An unrecognised code still occupies its slot so rows do not reflow.
    if (cell == null) return SizedBox.square(dimension: size);
    return SizedBox.square(
      dimension: size,
      child: FutureBuilder<ui.Image>(
        future: FlagSprite.sheet(),
        builder: (context, snapshot) {
          final sheet = snapshot.data;
          if (sheet == null) return const SizedBox.shrink();
          return CustomPaint(
            painter: _FlagPainter(sheet: sheet, cell: cell),
            size: Size.square(size),
          );
        },
      ),
    );
  }
}

/// Geometry of, and access to, the flag sprite sheet.
abstract final class FlagSprite {
  static const asset = 'assets/flags/flags.png';

  /// Cell edge in logical points; the sheet ships at 1x, 2x and 3x.
  static const cell = 26.0;

  /// One column and one row per letter, covering AA through ZZ.
  static const letters = 26;

  /// Grid cell for [iso], or null when it is not two ASCII letters.
  ///
  /// A well-formed code that Tossface has no artwork for lands on a
  /// transparent cell, which is the fallback we want anyway.
  static ({int column, int row})? cellFor(String iso) {
    if (iso.length != 2) return null;
    final upper = iso.toUpperCase();
    final column = upper.codeUnitAt(0) - 0x41; // 'A'
    final row = upper.codeUnitAt(1) - 0x41;
    if (column < 0 || column >= letters) return null;
    if (row < 0 || row >= letters) return null;
    return (column: column, row: row);
  }

  static Future<ui.Image>? _sheet;

  /// The decoded sheet, loaded once per process.
  static Future<ui.Image> sheet() => _sheet ??= _load();

  static Future<ui.Image> _load() {
    final stream = const AssetImage(asset).resolve(ImageConfiguration.empty);
    final completer = Completer<ui.Image>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        completer.complete(info.image);
      },
      onError: (error, stack) {
        stream.removeListener(listener);
        completer.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  @visibleForTesting
  static void reset() => _sheet = null;
}

class _FlagPainter extends CustomPainter {
  const _FlagPainter({required this.sheet, required this.cell});

  final ui.Image sheet;
  final ({int column, int row}) cell;

  @override
  void paint(Canvas canvas, Size size) {
    // The decoded sheet is whatever resolution Flutter picked, so derive the
    // pixel cell from the image itself instead of assuming a scale.
    final pixels = sheet.width / FlagSprite.letters;
    canvas.drawImageRect(
      sheet,
      Rect.fromLTWH(cell.column * pixels, cell.row * pixels, pixels, pixels),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_FlagPainter oldDelegate) =>
      oldDelegate.sheet != sheet || oldDelegate.cell != cell;
}
