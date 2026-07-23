import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../chat/video_player_view.dart';
import 'video_split_controller.dart';

/// Keeps a split video above the app navigator without losing video playback.
class GlobalVideoSplitHost extends StatefulWidget {
  const GlobalVideoSplitHost({super.key, required this.child});

  final Widget child;

  @override
  State<GlobalVideoSplitHost> createState() => _GlobalVideoSplitHostState();
}

class _GlobalVideoSplitHostState extends State<GlobalVideoSplitHost> {
  final VideoSplitController _videoSplit = VideoSplitController.instance;
  double _videoSplitFraction = 0.42;
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _videoSplit,
      builder: (context, _) {
        final session = _videoSplit.session;
        if (session == null) return widget.child;
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide =
                constraints.maxWidth >= 760 &&
                constraints.maxWidth > constraints.maxHeight;
            if (wide) {
              final videoWidth = _clampSplitExtent(
                totalExtent: constraints.maxWidth,
                fraction: _videoSplitFraction,
                preferredMin: 280,
                reservedExtent: 320,
                fallbackMin: 180,
              );
              return Row(
                children: [
                  Expanded(child: widget.child),
                  _videoSplitDivider(
                    vertical: true,
                    onDrag: (delta) => setState(() {
                      _videoSplitFraction =
                          (_videoSplitFraction - delta / constraints.maxWidth)
                              .clamp(0.25, 0.72);
                    }),
                  ),
                  SizedBox(width: videoWidth, child: _videoSibling(session)),
                ],
              );
            }

            final videoHeight = _clampSplitExtent(
              totalExtent: constraints.maxHeight,
              fraction: _videoSplitFraction,
              preferredMin: 220,
              reservedExtent: 260,
              fallbackMin: 96,
            );
            final topInset = MediaQuery.paddingOf(context).top;
            return Column(
              children: [
                SizedBox(
                  height: videoHeight + topInset,
                  child: ColoredBox(
                    color: Colors.black,
                    child: Column(
                      children: [
                        SizedBox(height: topInset),
                        Expanded(child: _videoSibling(session)),
                      ],
                    ),
                  ),
                ),
                _videoSplitDivider(
                  vertical: false,
                  onDrag: (delta) => setState(() {
                    _videoSplitFraction =
                        (_videoSplitFraction + delta / constraints.maxHeight)
                            .clamp(0.25, 0.72);
                  }),
                ),
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: widget.child,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  double _clampSplitExtent({
    required double totalExtent,
    required double fraction,
    required double preferredMin,
    required double reservedExtent,
    required double fallbackMin,
  }) {
    if (!totalExtent.isFinite || totalExtent <= 0) return fallbackMin;
    final upper = math.max(fallbackMin, totalExtent - reservedExtent);
    final lower = math.min(preferredMin, upper);
    return (totalExtent * fraction).clamp(lower, upper).toDouble();
  }

  Widget _videoSibling(VideoSplitSession session) {
    return ColoredBox(
      color: Colors.black,
      child: VideoPlayerView(
        key: ValueKey('${session.video.id}:${session.messageId ?? 0}'),
        video: session.video,
        thumb: session.thumb,
        width: session.width,
        height: session.height,
        presentation: VideoPlayerPresentation.embedded,
        onClose: _videoSplit.close,
        sourceChatId: session.chatId,
        messageId: session.messageId,
        previousVideo: session.queue.previous,
        nextVideo: session.queue.next,
        onNavigate: (delta) {
          final nextSession = session.moveBy(delta);
          if (nextSession != null) _videoSplit.play(nextSession);
        },
        currentMode: VideoDisplayMode.split,
        onSwitchMode: (mode) => _switchSiblingVideoMode(session, mode),
      ),
    );
  }

  Widget _videoSplitDivider({
    required bool vertical,
    required ValueChanged<double> onDrag,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) =>
          onDrag(vertical ? details.delta.dx : details.delta.dy),
      child: Container(
        width: vertical ? 14 : double.infinity,
        height: vertical ? double.infinity : 14,
        color: const Color(0xFF111113),
        alignment: Alignment.center,
        child: Container(
          width: vertical ? 3 : 52,
          height: vertical ? 52 : 3,
          decoration: BoxDecoration(
            color: const Color(0xFF3A3A3C),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  void _switchSiblingVideoMode(
    VideoSplitSession session,
    VideoDisplayMode mode,
  ) {
    switch (mode) {
      case VideoDisplayMode.split:
        break;
      case VideoDisplayMode.pictureInPicture:
        // The player starts AVPictureInPictureController before this fallback
        // is reached on iOS. Do not replace it with an in-app overlay.
        _videoSplit.close();
      case VideoDisplayMode.fullscreen:
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => VideoPlaylistPlayerView(queue: session.queue),
          ),
        );
    }
  }
}
