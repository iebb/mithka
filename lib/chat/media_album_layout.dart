import 'dart:math' as math;
import 'dart:ui';

class MediaAlbumItem {
  const MediaAlbumItem({this.width, this.height});

  final int? width;
  final int? height;

  double get aspectRatio {
    final w = width;
    final h = height;
    if (w == null || h == null || w <= 0 || h <= 0) {
      return 1.0;
    }
    return w / h;
  }
}

class MediaAlbumLayout {
  const MediaAlbumLayout({
    required this.width,
    required this.height,
    required this.tiles,
  });

  final double width;
  final double height;
  final List<Rect> tiles;
}

MediaAlbumLayout buildTelegramMediaAlbumLayout({
  required List<MediaAlbumItem> items,
  required double maxWidth,
  double gap = 3,
  int maxItems = 9,
  double minSingleHeight = 120,
  double maxSingleHeight = 360,
  double minRowHeight = 84,
  double maxRowHeight = 260,
}) {
  final visible = items.take(maxItems).toList(growable: false);
  if (visible.isEmpty || maxWidth <= 0) {
    return const MediaAlbumLayout(width: 0, height: 0, tiles: []);
  }

  if (visible.length == 1) {
    final aspect = visible.first.aspectRatio.clamp(0.35, 3.0).toDouble();
    var width = maxWidth;
    var height = width / aspect;
    if (height > maxSingleHeight) {
      height = maxSingleHeight;
      width = math.min(maxWidth, height * aspect);
    } else if (height < minSingleHeight) {
      height = minSingleHeight;
      width = math.min(maxWidth, height * aspect);
    }
    return MediaAlbumLayout(
      width: width,
      height: height,
      tiles: [Rect.fromLTWH(0, 0, width, height)],
    );
  }

  final rawRatios = visible
      .map((item) {
        return item.aspectRatio.clamp(0.45, 2.35).toDouble();
      })
      .toList(growable: false);
  final average = rawRatios.reduce((a, b) => a + b) / rawRatios.length;
  final ratios = rawRatios
      .map((ratio) {
        if (average > 1.1) {
          return ratio.clamp(1.0, 1.7).toDouble();
        }
        return ratio.clamp(0.66667, 1.0).toDouble();
      })
      .toList(growable: false);

  _AlbumAttempt? best;
  for (final plan in _albumRowPlans(ratios.length)) {
    final attempt = _buildAttempt(
      plan,
      ratios,
      maxWidth,
      gap,
      minRowHeight,
      maxRowHeight,
    );
    if (best == null || attempt.score < best.score) {
      best = attempt;
    }
  }

  if (best == null) {
    return MediaAlbumLayout(
      width: maxWidth,
      height: maxWidth,
      tiles: [for (final _ in visible) Rect.fromLTWH(0, 0, maxWidth, maxWidth)],
    );
  }
  return MediaAlbumLayout(
    width: maxWidth,
    height: best.height,
    tiles: best.tiles,
  );
}

List<List<int>> _albumRowPlans(int count) {
  final plans = <List<int>>[];

  void walk(int remaining, List<int> rows) {
    if (remaining == 0) {
      plans.add(List<int>.from(rows));
      return;
    }
    if (rows.length >= 4) return;
    final maxInRow = math.min(3, remaining);
    for (var row = 1; row <= maxInRow; row++) {
      rows.add(row);
      walk(remaining - row, rows);
      rows.removeLast();
    }
  }

  walk(count, <int>[]);
  return plans
      .where((plan) {
        if (count == 2) return plan.length == 1 || plan.length == 2;
        if (count > 2 && plan.length == 1) return count <= 3;
        return true;
      })
      .toList(growable: false);
}

_AlbumAttempt _buildAttempt(
  List<int> plan,
  List<double> ratios,
  double maxWidth,
  double gap,
  double minRowHeight,
  double maxRowHeight,
) {
  var index = 0;
  var top = 0.0;
  var score = 0.0;
  final tiles = <Rect>[];
  final count = ratios.length;

  for (var rowIndex = 0; rowIndex < plan.length; rowIndex++) {
    final rowCount = plan[rowIndex];
    final rowRatios = ratios.sublist(index, index + rowCount);
    final rowWidth = maxWidth - gap * (rowCount - 1);
    final rowHeight = rowWidth / rowRatios.reduce((a, b) => a + b);
    if (rowHeight < minRowHeight) {
      score += (minRowHeight - rowHeight) * 2.2;
    } else if (rowHeight > maxRowHeight) {
      score += (rowHeight - maxRowHeight) * 1.5;
    }
    if (rowCount == 1 && count > 1) {
      score += rowHeight * 0.18;
    }

    var left = 0.0;
    for (var i = 0; i < rowRatios.length; i++) {
      final isLast = i == rowRatios.length - 1;
      final width = isLast ? maxWidth - left : rowRatios[i] * rowHeight;
      if (width < maxWidth * 0.18) {
        score += (maxWidth * 0.18 - width) * 2;
      }
      tiles.add(Rect.fromLTWH(left, top, width, rowHeight));
      left += width + gap;
    }

    top += rowHeight + (rowIndex == plan.length - 1 ? 0 : gap);
    index += rowCount;
  }

  final target = switch (count) {
    2 => maxWidth * 0.58,
    3 => maxWidth * 1.05,
    4 => maxWidth * 0.95,
    <= 6 => maxWidth * 1.05,
    _ => maxWidth * 1.18,
  };
  score += (top - target).abs();

  if (count == 2 && plan.length > 1) {
    score += maxWidth * 0.45;
  }
  if (count > 2 && plan.length == 1) {
    score += maxWidth * 0.35;
  }
  for (var i = 0; i < plan.length - 1; i++) {
    if (plan[i] > plan[i + 1]) {
      score *= 1.18;
      break;
    }
  }

  return _AlbumAttempt(height: top, tiles: tiles, score: score);
}

class _AlbumAttempt {
  const _AlbumAttempt({
    required this.height,
    required this.tiles,
    required this.score,
  });

  final double height;
  final List<Rect> tiles;
  final double score;
}
