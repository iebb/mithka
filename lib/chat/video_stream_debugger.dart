import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../tdlib/td_image_loader.dart';
import '../theme/app_theme.dart';

/// The three states computed for each byte chunk. Sparse ranges stay at their
/// real offsets, so seeking never paints the untouched gap as downloaded.
enum VideoDownloadBlockState { downloaded, partiallyDownloaded, undownloaded }

@immutable
class VideoDownloadBlock {
  const VideoDownloadBlock({
    required this.index,
    required this.start,
    required this.end,
    required this.state,
  });

  final int index;
  final int start;
  final int end;
  final VideoDownloadBlockState state;

  int get size => math.max(0, end - start);
}

@immutable
class VideoDownloadBlockLayout {
  const VideoDownloadBlockLayout({
    required this.totalBytes,
    required this.blockSizeBytes,
    required this.columns,
    required this.rows,
    required this.cellSize,
    required this.gap,
    required this.blocks,
  });

  final int totalBytes;
  final int blockSizeBytes;
  final int columns;
  final int rows;
  final double cellSize;
  final double gap;
  final List<VideoDownloadBlock> blocks;

  int get capacity => columns * rows;

  double get width => columns * cellSize + math.max(0, columns - 1) * gap;

  double get height => rows * cellSize + math.max(0, rows - 1) * gap;
}

const int videoDownloadMinimumBlockBytes = 1024 * 1024;
const int videoDownloadMaximumBlocks = 4096;
const double _videoDownloadMinimumCellSize = 12;
const double _videoDownloadCellGap = 4;

int _ceilDivide(int value, int divisor) {
  if (value <= 0) return 0;
  return (value + divisor - 1) ~/ divisor;
}

/// Computes a grid that fits inside the supplied bounds.
///
/// The number of chunks follows the measured pixel capacity of the pane. The
/// byte size represented by each square grows as needed for large files, so a
/// dense grid can fill the available space without overflowing and every
/// chunk still represents at least one MiB.
VideoDownloadBlockLayout videoDownloadBlockLayout({
  required int totalBytes,
  required int downloadedBytes,
  required int prefixDownloadedBytes,
  required bool completed,
  List<TdFileByteRange>? downloadedRanges,
  required double maxWidth,
  required double maxHeight,
  double gap = _videoDownloadCellGap,
  double minimumCellSize = _videoDownloadMinimumCellSize,
}) {
  final double safeWidth = maxWidth.isFinite
      ? math.max(1, maxWidth).toDouble()
      : 320.0;
  final double safeHeight = maxHeight.isFinite
      ? math.max(1, maxHeight).toDouble()
      : 220.0;
  final double safeGap = gap.isFinite
      ? math.max(0, gap).toDouble()
      : _videoDownloadCellGap;
  final safeMinimumCellSize = minimumCellSize.isFinite
      ? math.max(1, minimumCellSize).toDouble()
      : _videoDownloadMinimumCellSize;
  final int columns = math.min(
    videoDownloadMaximumBlocks,
    math.max(
      1,
      ((safeWidth + safeGap) / (safeMinimumCellSize + safeGap)).floor(),
    ),
  );
  final int availableRows = math.max(
    1,
    ((safeHeight + safeGap) / (safeMinimumCellSize + safeGap)).floor(),
  );
  final safeTotal = math.max(0, totalBytes);
  final capacity = math.min(
    videoDownloadMaximumBlocks,
    math.max(1, columns * availableRows),
  );
  final blockSize = math.max(
    videoDownloadMinimumBlockBytes,
    _ceilDivide(safeTotal, capacity),
  );
  final blockCount = safeTotal == 0 ? 0 : _ceilDivide(safeTotal, blockSize);
  final int actualRows = math.max(1, _ceilDivide(blockCount, columns));
  final widthCellSize =
      (safeWidth - math.max(0, columns - 1) * safeGap) / columns;
  final heightCellSize =
      (safeHeight - math.max(0, actualRows - 1) * safeGap) / actualRows;
  final cellSize = math
      .max(1, math.min(widthCellSize, heightCellSize))
      .toDouble();
  final safeDownloaded = completed
      ? safeTotal
      : downloadedBytes.clamp(0, safeTotal);
  final safePrefix = completed
      ? safeTotal
      : prefixDownloadedBytes.clamp(0, safeTotal);
  final normalizedRanges = downloadedRanges == null
      ? null
      : _normalizeDownloadedRanges(downloadedRanges, safeTotal);
  final blocks = List<VideoDownloadBlock>.generate(blockCount, (index) {
    final start = index * blockSize;
    final end = math.min(safeTotal, start + blockSize);
    final state = _videoDownloadBlockState(
      start: start,
      end: end,
      downloadedBytes: safeDownloaded,
      prefixDownloadedBytes: safePrefix,
      completed: completed,
      downloadedRanges: normalizedRanges,
    );
    return VideoDownloadBlock(
      index: index,
      start: start,
      end: end,
      state: state,
    );
  });
  return VideoDownloadBlockLayout(
    totalBytes: safeTotal,
    blockSizeBytes: blockSize,
    columns: columns,
    rows: actualRows,
    cellSize: cellSize,
    gap: safeGap,
    blocks: List<VideoDownloadBlock>.unmodifiable(blocks),
  );
}

VideoDownloadBlockState videoDownloadBlockState({
  required int start,
  required int end,
  required int downloadedBytes,
  required int prefixDownloadedBytes,
  required bool completed,
  List<TdFileByteRange>? downloadedRanges,
}) => _videoDownloadBlockState(
  start: start,
  end: end,
  downloadedBytes: downloadedBytes,
  prefixDownloadedBytes: prefixDownloadedBytes,
  completed: completed,
  downloadedRanges: downloadedRanges == null
      ? null
      : _normalizeDownloadedRanges(downloadedRanges, end),
);

VideoDownloadBlockState _videoDownloadBlockState({
  required int start,
  required int end,
  required int downloadedBytes,
  required int prefixDownloadedBytes,
  required bool completed,
  required List<TdFileByteRange>? downloadedRanges,
}) {
  if (completed) {
    return VideoDownloadBlockState.downloaded;
  }
  if (downloadedRanges != null) {
    var cursor = start;
    var overlaps = false;
    for (final range in downloadedRanges) {
      if (range.end <= start) continue;
      if (range.start >= end) break;
      overlaps = true;
      if (range.start > cursor) {
        return VideoDownloadBlockState.partiallyDownloaded;
      }
      cursor = math.max(cursor, range.end);
      if (cursor >= end) return VideoDownloadBlockState.downloaded;
    }
    return overlaps
        ? VideoDownloadBlockState.partiallyDownloaded
        : VideoDownloadBlockState.undownloaded;
  }
  if (end <= prefixDownloadedBytes) {
    return VideoDownloadBlockState.downloaded;
  }
  if (start < downloadedBytes || start < prefixDownloadedBytes) {
    return VideoDownloadBlockState.partiallyDownloaded;
  }
  return VideoDownloadBlockState.undownloaded;
}

List<TdFileByteRange> _normalizeDownloadedRanges(
  List<TdFileByteRange> ranges,
  int total,
) {
  final sorted = <TdFileByteRange>[];
  for (final range in ranges) {
    final start = range.start.clamp(0, total);
    final end = range.end.clamp(start, total);
    if (end > start) sorted.add(TdFileByteRange(start: start, end: end));
  }
  sorted.sort((a, b) => a.start.compareTo(b.start));
  final merged = <TdFileByteRange>[];
  for (final range in sorted) {
    if (merged.isEmpty || range.start > merged.last.end) {
      merged.add(range);
      continue;
    }
    final previous = merged.removeLast();
    merged.add(
      TdFileByteRange(
        start: previous.start,
        end: math.max(previous.end, range.end),
      ),
    );
  }
  return merged;
}

typedef VideoStreamDebuggerBuilder =
    Widget Function(BuildContext context, BoxConstraints constraints);

/// Keeps the player in a stable element slot while the inspector is shown or
/// hidden. This prevents closing the overlay from disposing and recreating the
/// underlying video player.
class VideoStreamDebuggerOverlay extends StatelessWidget {
  const VideoStreamDebuggerOverlay({
    super.key,
    required this.player,
    required this.visible,
    required this.inspectorBuilder,
  });

  final Widget player;
  final bool visible;
  final VideoStreamDebuggerBuilder inspectorBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalInset = constraints.maxWidth < 520 ? 8.0 : 16.0;
        final verticalInset = constraints.maxHeight < 420 ? 8.0 : 16.0;
        final availableHeight = math.max(
          1.0,
          constraints.maxHeight - verticalInset * 2,
        );
        final inspectorHeight = math
            .min(500.0, math.max(260.0, constraints.maxHeight * 0.54))
            .clamp(1.0, availableHeight)
            .toDouble();
        return Stack(
          children: [
            Positioned.fill(child: player),
            if (visible)
              Positioned(
                left: horizontalInset,
                right: horizontalInset,
                bottom: verticalInset,
                height: inspectorHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0xB3000000),
                        blurRadius: 28,
                        spreadRadius: 2,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: inspectorBuilder(context, constraints),
                ),
              ),
          ],
        );
      },
    );
  }
}

class VideoStreamDebugger extends StatefulWidget {
  const VideoStreamDebugger({
    super.key,
    required this.progress,
    required this.position,
    required this.duration,
    required this.events,
    required this.isLive,
    required this.onClose,
    this.viewportSize = Size.zero,
    this.videoSize = Size.zero,
    this.volume = 1,
    this.playbackSpeed = 1,
    this.bufferedAhead = Duration.zero,
    this.downloadBytesPerSecond = 0,
  });

  final TdFileProgress? progress;
  final Duration position;
  final Duration duration;
  final List<String> events;
  final bool isLive;
  final VoidCallback onClose;
  final Size viewportSize;
  final Size videoSize;
  final double volume;
  final double playbackSpeed;
  final Duration bufferedAhead;
  final double downloadBytesPerSecond;

  @override
  State<VideoStreamDebugger> createState() => _VideoStreamDebuggerState();
}

class _VideoStreamDebuggerState extends State<VideoStreamDebugger> {
  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: const TextStyle(fontWeight: FontWeight.w400),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xF20F1112),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Column(
            children: [
              _InspectorHeader(widget: widget),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 760;
                    final stats = _StatsForNerdsPanel(
                      progress: widget.progress,
                      viewportSize: widget.viewportSize,
                      videoSize: widget.videoSize,
                      volume: widget.volume,
                      playbackSpeed: widget.playbackSpeed,
                      bufferedAhead: widget.bufferedAhead,
                      downloadBytesPerSecond: widget.downloadBytesPerSecond,
                      events: widget.events,
                    );
                    final cache = _DownloadBlockPanel(
                      progress: widget.progress,
                    );
                    if (narrow) {
                      return ListView(
                        padding: const EdgeInsets.all(10),
                        children: [
                          SizedBox(height: 250, child: stats),
                          const SizedBox(height: 10),
                          SizedBox(height: 260, child: cache),
                        ],
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: stats),
                          const SizedBox(width: 10),
                          Expanded(child: cache),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InspectorHeader extends StatelessWidget {
  const _InspectorHeader({required this.widget});

  final VideoStreamDebugger widget;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 9),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                const Flexible(
                  child: Text(
                    'Stream Inspector',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: widget.isLive
                        ? const Color(0xFF7DDF3A)
                        : const Color(0xFF6B7280),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  widget.isLive ? 'LIVE' : 'IDLE',
                  style: TextStyle(
                    color: widget.isLive
                        ? const Color(0xFFB8F28B)
                        : Colors.white.withValues(alpha: 0.6),
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          _InspectorAction(
            icon: HeroAppIcons.xmark,
            label: 'CLOSE',
            onTap: widget.onClose,
          ),
        ],
      ),
    );
  }
}

class _InspectorAction extends StatelessWidget {
  const _InspectorAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppInteractiveSurface(
      semanticLabel: label,
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      showFocusRing: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: AppIcon(icon, size: 17, color: Colors.white),
      ),
    );
  }
}

class _StatsForNerdsPanel extends StatelessWidget {
  const _StatsForNerdsPanel({
    required this.progress,
    required this.viewportSize,
    required this.videoSize,
    required this.volume,
    required this.playbackSpeed,
    required this.bufferedAhead,
    required this.downloadBytesPerSecond,
    required this.events,
  });

  final TdFileProgress? progress;
  final Size viewportSize;
  final Size videoSize;
  final double volume;
  final double playbackSpeed;
  final Duration bufferedAhead;
  final double downloadBytesPerSecond;
  final List<String> events;

  @override
  Widget build(BuildContext context) {
    final total = progress?.total ?? 0;
    final downloaded = progress?.downloaded ?? 0;
    final viewport = _formatPixelSize(viewportSize);
    final resolution = _formatPixelSize(videoSize);
    final speed = math.max(0, downloadBytesPerSecond).toDouble();
    final lastEvent = events.isEmpty
        ? 'Waiting for stream events'
        : events.last;
    return _InspectorPanel(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            _NerdStatRow(
              label: 'Video ID / File',
              value: progress == null ? '—' : '${progress!.fileId}',
            ),
            _NerdStatRow(label: 'Viewport / Frames', value: '$viewport / —'),
            _NerdStatRow(
              label: 'Current / Optimal Res',
              value: '$resolution / $resolution',
            ),
            _NerdStatRow(
              label: 'Volume / Normalized',
              value: '${(volume.clamp(0.0, 1.0) * 100).round()}% / 100%',
            ),
            _NerdStatRow(
              label: 'Playback Rate',
              value:
                  '${playbackSpeed.toStringAsFixed(playbackSpeed % 1 == 0 ? 0 : 2)}x',
            ),
            _NerdStatRow(
              label: 'Connection Speed',
              value: _formatBitsPerSecond(speed),
            ),
            _NerdStatRow(
              label: 'Network Activity',
              value: '${_formatBytes(speed.round())}/s',
            ),
            _NerdStatRow(
              label: 'Buffer Health',
              value:
                  '${(math.max(0, bufferedAhead.inMilliseconds) / 1000).toStringAsFixed(2)} s',
            ),
            _NerdStatRow(
              label: 'Cache',
              value: total > 0
                  ? '${_formatBytes(downloaded)} / ${_formatBytes(total)}'
                  : 'waiting for size',
            ),
            _NerdStatRow(label: 'Last Event', value: lastEvent),
          ],
        ),
      ),
    );
  }
}

class _NerdStatRow extends StatelessWidget {
  const _NerdStatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 126,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontFamily: 'monospace',
              fontSize: 10,
              fontWeight: FontWeight.w400,
              height: 1.3,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 10,
              fontWeight: FontWeight.w400,
              height: 1.3,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    ),
  );
}

class _DownloadBlockPanel extends StatelessWidget {
  const _DownloadBlockPanel({required this.progress});

  final TdFileProgress? progress;

  @override
  Widget build(BuildContext context) {
    final total = progress?.total ?? 0;
    final downloaded = progress?.downloaded ?? 0;
    final fraction = total > 0 ? (downloaded / total).clamp(0.0, 1.0) : 0.0;
    return _InspectorPanel(
      title: 'Stream cache',
      trailing: total > 0
          ? '${_formatBytes(downloaded)} / ${_formatBytes(total)}  •  ${(fraction * 100).round()}%'
          : 'waiting for size',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const legendHeight = 16.0;
            const legendGap = 6.0;
            final gridHeight = math.max(
              1.0,
              constraints.maxHeight - legendGap - legendHeight,
            );
            final layout = videoDownloadBlockLayout(
              totalBytes: total,
              downloadedBytes: downloaded,
              prefixDownloadedBytes: progress?.prefixDownloaded ?? 0,
              completed: progress?.isCompleted == true,
              downloadedRanges: progress?.downloadedRanges,
              maxWidth: constraints.maxWidth,
              maxHeight: gridHeight,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: layout.width,
                      height: layout.height,
                      child: Wrap(
                        spacing: layout.gap,
                        runSpacing: layout.gap,
                        children: [
                          for (final block in layout.blocks)
                            Semantics(
                              label: _blockLabel(block, layout),
                              child: Container(
                                key: ValueKey(
                                  'video-debug-block-${block.index}',
                                ),
                                width: layout.cellSize,
                                height: layout.cellSize,
                                decoration: BoxDecoration(
                                  color: _blockColor(block.state),
                                  borderRadius: BorderRadius.circular(3),
                                  border:
                                      block.state ==
                                          VideoDownloadBlockState
                                              .partiallyDownloaded
                                      ? Border.all(
                                          color: const Color(0xFF28E4E0),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: legendGap),
                SizedBox(
                  height: legendHeight,
                  child: Row(
                    children: [
                      _LegendDot(
                        color: _blockColor(VideoDownloadBlockState.downloaded),
                        label: 'Downloaded',
                      ),
                      const SizedBox(width: 10),
                      _LegendDot(
                        color: _blockColor(
                          VideoDownloadBlockState.partiallyDownloaded,
                        ),
                        label: 'Partial',
                      ),
                      const SizedBox(width: 10),
                      _LegendDot(
                        color: _blockColor(
                          VideoDownloadBlockState.undownloaded,
                        ),
                        label: 'Undownloaded',
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.68),
                fontSize: 10,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectorPanel extends StatelessWidget {
  const _InspectorPanel({required this.child, this.title, this.trailing});

  final String? title;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xB5151718),
        border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          if (title != null || trailing != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 7),
              child: Row(
                key: ValueKey<String>(
                  'video-debug-panel-header-${title ?? ''}',
                ),
                children: [
                  if (title != null)
                    Expanded(
                      child: Text(
                        title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  if (trailing != null)
                    Text(
                      trailing!,
                      key: ValueKey<String>(
                        'video-debug-panel-trailing-${title ?? ''}',
                      ),
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.66),
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
            ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

Color _blockColor(VideoDownloadBlockState state) => switch (state) {
  VideoDownloadBlockState.downloaded => const Color(0xFF79D33E),
  VideoDownloadBlockState.partiallyDownloaded => const Color(0xFF22D5D0),
  VideoDownloadBlockState.undownloaded => const Color(0xFF34383B),
};

String _blockLabel(VideoDownloadBlock block, VideoDownloadBlockLayout layout) {
  final state = switch (block.state) {
    VideoDownloadBlockState.downloaded => 'downloaded',
    VideoDownloadBlockState.partiallyDownloaded => 'partially downloaded',
    VideoDownloadBlockState.undownloaded => 'undownloaded',
  };
  return 'Chunk ${block.index + 1}, ${_formatBlockSize(layout.blockSizeBytes)}, $state';
}

String _formatBlockSize(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(bytes % (1024 * 1024) == 0 ? 0 : 1)} MB';
}

String _formatPixelSize(Size size) {
  if (!size.width.isFinite ||
      !size.height.isFinite ||
      size.width <= 0 ||
      size.height <= 0) {
    return '—';
  }
  return '${size.width.round()}x${size.height.round()}';
}

String _formatBitsPerSecond(double bytesPerSecond) {
  if (!bytesPerSecond.isFinite || bytesPerSecond <= 0) return '0 Kbps';
  final bits = bytesPerSecond * 8;
  if (bits >= 1000000) return '${(bits / 1000000).toStringAsFixed(1)} Mbps';
  return '${(bits / 1000).toStringAsFixed(0)} Kbps';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
