import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../tdlib/td_image_loader.dart';

/// The three states that can be known from TDLib's contiguous downloaded
/// prefix. A partially downloaded block is the block containing the current
/// prefix, or a block with non-prefix bytes reported by TDLib.
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
const double _videoDownloadMinimumCellSize = 20;
const double _videoDownloadCellGap = 6;

int _ceilDivide(int value, int divisor) {
  if (value <= 0) return 0;
  return (value + divisor - 1) ~/ divisor;
}

int _roundUpToMiB(int value) {
  if (value <= videoDownloadMinimumBlockBytes) {
    return videoDownloadMinimumBlockBytes;
  }
  return _ceilDivide(value, videoDownloadMinimumBlockBytes) *
      videoDownloadMinimumBlockBytes;
}

/// Computes a grid that fits inside the supplied bounds.
///
/// The byte size represented by each square grows in whole MiB increments as
/// the file gets larger than the number of cells that fit. Therefore the grid
/// never needs to overflow or scroll horizontally just to represent a large
/// file, and every square represents at least one MiB.
VideoDownloadBlockLayout videoDownloadBlockLayout({
  required int totalBytes,
  required int downloadedBytes,
  required int prefixDownloadedBytes,
  required bool completed,
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
  final int columns = math.max(
    1,
    ((safeWidth + safeGap) / (safeMinimumCellSize + safeGap)).floor(),
  );
  final int rows = math.max(
    1,
    ((safeHeight + safeGap) / (safeMinimumCellSize + safeGap)).floor(),
  );
  final safeTotal = math.max(0, totalBytes);
  final capacity = math.max(1, columns * rows);
  final blockSize = _roundUpToMiB(_ceilDivide(safeTotal, capacity));
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
  final blocks = List<VideoDownloadBlock>.generate(blockCount, (index) {
    final start = index * blockSize;
    final end = math.min(safeTotal, start + blockSize);
    final state = videoDownloadBlockState(
      start: start,
      end: end,
      downloadedBytes: safeDownloaded,
      prefixDownloadedBytes: safePrefix,
      completed: completed,
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
}) {
  if (completed || end <= prefixDownloadedBytes) {
    return VideoDownloadBlockState.downloaded;
  }
  if (start < downloadedBytes || start < prefixDownloadedBytes) {
    return VideoDownloadBlockState.partiallyDownloaded;
  }
  return VideoDownloadBlockState.undownloaded;
}

class VideoStreamDebugger extends StatefulWidget {
  const VideoStreamDebugger({
    super.key,
    required this.progress,
    required this.position,
    required this.duration,
    required this.events,
    required this.isLive,
    required this.isRecording,
    required this.onRecordingChanged,
    required this.onClear,
    required this.onExport,
    required this.onClose,
  });

  final TdFileProgress? progress;
  final Duration position;
  final Duration duration;
  final List<String> events;
  final bool isLive;
  final bool isRecording;
  final ValueChanged<bool> onRecordingChanged;
  final VoidCallback onClear;
  final VoidCallback onExport;
  final VoidCallback onClose;

  @override
  State<VideoStreamDebugger> createState() => _VideoStreamDebuggerState();
}

class _VideoStreamDebuggerState extends State<VideoStreamDebugger> {
  _VideoDebuggerTab _tab = _VideoDebuggerTab.cache;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xF20F1112),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Column(
          children: [
            _InspectorHeader(widget: widget),
            _InspectorTabs(
              selected: _tab,
              onSelected: (tab) => setState(() => _tab = tab),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 760;
                  final cache = _DownloadBlockPanel(
                    progress: widget.progress,
                    position: widget.position,
                    duration: widget.duration,
                  );
                  final left = _tab == _VideoDebuggerTab.debug
                      ? _EventLogPanel(events: widget.events)
                      : _RequestPanel(tab: _tab, progress: widget.progress);
                  if (narrow) {
                    return ListView(
                      padding: const EdgeInsets.all(10),
                      children: [
                        SizedBox(height: 174, child: left),
                        const SizedBox(height: 10),
                        SizedBox(height: 220, child: cache),
                      ],
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 3, child: left),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 3,
                          child: _RequestPanel(
                            tab: _VideoDebuggerTab.network,
                            progress: widget.progress,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(flex: 4, child: cache),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _VideoDebuggerTab { debug, network, cache }

class _InspectorHeader extends StatelessWidget {
  const _InspectorHeader({required this.widget});

  final VideoStreamDebugger widget;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final iconOnly = constraints.maxWidth < 560;
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 9),
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
                    fontWeight: FontWeight.w700,
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
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              _InspectorAction(
                icon: HeroAppIcons.circle,
                label: widget.isRecording ? 'STOP' : 'RECORD',
                active: widget.isRecording,
                onTap: () => widget.onRecordingChanged(!widget.isRecording),
                iconOnly: iconOnly,
              ),
              _InspectorAction(
                icon: HeroAppIcons.trash,
                label: 'CLEAR',
                onTap: widget.onClear,
                iconOnly: iconOnly,
              ),
              _InspectorAction(
                icon: HeroAppIcons.upload,
                label: 'EXPORT',
                onTap: widget.onExport,
                iconOnly: iconOnly,
              ),
              _InspectorAction(
                icon: HeroAppIcons.xmark,
                label: 'CLOSE',
                onTap: widget.onClose,
                iconOnly: true,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InspectorAction extends StatelessWidget {
  const _InspectorAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.iconOnly = false,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    return AppInteractiveSurface(
      semanticLabel: label,
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      showFocusRing: false,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: iconOnly ? 8 : 7,
          vertical: 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              icon,
              size: 17,
              color: active ? const Color(0xFF27E5E0) : Colors.white,
            ),
            if (!iconOnly) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: active ? const Color(0xFF27E5E0) : Colors.white,
                  fontSize: 11,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InspectorTabs extends StatelessWidget {
  const _InspectorTabs({required this.selected, required this.onSelected});

  final _VideoDebuggerTab selected;
  final ValueChanged<_VideoDebuggerTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
      ),
      child: Row(
        children: [
          for (final tab in _VideoDebuggerTab.values)
            Expanded(
              child: _InspectorTab(
                tab: tab,
                selected: tab == selected,
                onTap: () => onSelected(tab),
              ),
            ),
        ],
      ),
    );
  }
}

class _InspectorTab extends StatelessWidget {
  const _InspectorTab({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _VideoDebuggerTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = switch (tab) {
      _VideoDebuggerTab.debug => 'DEBUG',
      _VideoDebuggerTab.network => 'NETWORK',
      _VideoDebuggerTab.cache => 'CACHE',
    };
    return AppInteractiveSurface(
      semanticLabel: label,
      selected: selected,
      onTap: onTap,
      showFocusRing: false,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected
                    ? const Color(0xFF28E4E0)
                    : Colors.white.withValues(alpha: 0.66),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          if (selected)
            const Positioned(
              left: 16,
              right: 16,
              bottom: 0,
              height: 2,
              child: ColoredBox(color: Color(0xFF28E4E0)),
            ),
        ],
      ),
    );
  }
}

class _EventLogPanel extends StatelessWidget {
  const _EventLogPanel({required this.events});

  final List<String> events;

  @override
  Widget build(BuildContext context) {
    return _InspectorPanel(
      title: 'Event log',
      child: events.isEmpty
          ? const _InspectorEmptyState(label: 'Waiting for stream events')
          : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              itemCount: math.min(events.length, 12),
              separatorBuilder: (_, _) => const SizedBox(height: 7),
              itemBuilder: (context, index) {
                final event = events[events.length - index - 1];
                return Row(
                  children: [
                    const SizedBox(
                      width: 6,
                      height: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0xFF28E4E0),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        event,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 11,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _RequestPanel extends StatelessWidget {
  const _RequestPanel({required this.tab, required this.progress});

  final _VideoDebuggerTab tab;
  final TdFileProgress? progress;

  @override
  Widget build(BuildContext context) {
    final total = progress?.total ?? 0;
    final downloaded = progress?.downloaded ?? 0;
    final partial =
        progress != null && !progress!.isCompleted && downloaded > 0;
    final status = progress?.isCompleted == true
        ? '200'
        : partial
        ? '206'
        : '—';
    return _InspectorPanel(
      title: tab == _VideoDebuggerTab.network ? 'Requests' : 'Playback',
      trailing: total > 0
          ? '${_formatBytes(downloaded)} / ${_formatBytes(total)}'
          : null,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _InspectorMetricRow(label: 'TYPE', value: 'TDLib stream'),
            const SizedBox(height: 8),
            _InspectorMetricRow(label: 'STATUS', value: status),
            const SizedBox(height: 8),
            _InspectorMetricRow(
              label: 'SIZE',
              value: total > 0 ? _formatBytes(total) : 'unknown',
            ),
            const SizedBox(height: 8),
            _InspectorMetricRow(
              label: 'MODE',
              value: progress?.isActive == true ? 'streaming' : 'local',
            ),
            const SizedBox(height: 16),
            Text(
              tab == _VideoDebuggerTab.network
                  ? 'Range requests are served from the local TDLib stream.'
                  : 'Playback stays separate from the diagnostic view.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InspectorMetricRow extends StatelessWidget {
  const _InspectorMetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.52),
              fontSize: 10,
              letterSpacing: 0.7,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _DownloadBlockPanel extends StatelessWidget {
  const _DownloadBlockPanel({
    required this.progress,
    required this.position,
    required this.duration,
  });

  final TdFileProgress? progress;
  final Duration position;
  final Duration duration;

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layout = videoDownloadBlockLayout(
            totalBytes: total,
            downloadedBytes: downloaded,
            prefixDownloadedBytes: progress?.prefixDownloaded ?? 0,
            completed: progress?.isCompleted == true,
            maxWidth: constraints.maxWidth - 20,
            maxHeight: math.max(1, constraints.maxHeight - 78),
          );
          final playhead = total > 0
              ? (position.inMicroseconds / math.max(1, duration.inMicroseconds))
                    .clamp(0.0, 1.0)
              : 0.0;
          return Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${_formatBlockSize(layout.blockSizeBytes)} per square  •  ${layout.blocks.length} blocks',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 10,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Align(
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
                      if (total > 0)
                        Positioned(
                          left: math.min(
                            layout.width - 1.5,
                            math.max(0, layout.width * playhead),
                          ),
                          top: -12,
                          bottom: -2,
                          child: IgnorePointer(
                            child: Container(
                              width: 1.5,
                              color: const Color(0xFF28E4E0),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
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
                      color: _blockColor(VideoDownloadBlockState.undownloaded),
                      label: 'Undownloaded',
                    ),
                  ],
                ),
              ],
            ),
          );
        },
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectorPanel extends StatelessWidget {
  const _InspectorPanel({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
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
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 7),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (trailing != null)
                  Flexible(
                    child: Text(
                      trailing!,
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.66),
                        fontSize: 10,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
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

class _InspectorEmptyState extends StatelessWidget {
  const _InspectorEmptyState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      label,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.45),
        fontSize: 11,
      ),
    ),
  );
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
  return 'Block ${block.index + 1}, ${_formatBlockSize(layout.blockSizeBytes)}, $state';
}

String _formatBlockSize(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(bytes % (1024 * 1024) == 0 ? 0 : 1)} MB';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
