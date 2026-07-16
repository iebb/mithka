import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../chat/video_player_view.dart';
import '../settings/developer_mode_controller.dart';
import 'pip_bounds_debug_overlay.dart';
import 'video_split_controller.dart';

/// Keeps split and picture-in-picture video above the app navigator, allowing
/// conversations to live outside the tab shell without losing video playback.
class GlobalVideoSplitHost extends StatefulWidget {
  const GlobalVideoSplitHost({super.key, required this.child});

  final Widget child;

  @override
  State<GlobalVideoSplitHost> createState() => _GlobalVideoSplitHostState();
}

class _GlobalVideoSplitHostState extends State<GlobalVideoSplitHost> {
  final VideoSplitController _videoSplit = VideoSplitController.instance;
  double _videoSplitFraction = 0.42;
  OverlayEntry? _pictureInPictureVideo;

  @override
  void dispose() {
    _pictureInPictureVideo?.remove();
    if (_pictureInPictureVideo != null) VideoPiPController.instance.close();
    super.dispose();
  }

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
        _videoSplit.close();
        _showSplitVideoPictureInPicture(session);
      case VideoDisplayMode.fullscreen:
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => VideoPlaylistPlayerView(queue: session.queue),
          ),
        );
    }
  }

  void _showSplitVideoPictureInPicture(VideoSplitSession session) {
    final pip = VideoPiPController.instance;
    if (_pictureInPictureVideo != null || pip.isOpen) {
      pip.play(session);
      return;
    }
    pip.play(session);
    final overlay = Overlay.of(context, rootOverlay: true);
    final screen = MediaQuery.sizeOf(context);
    const margin = 16.0;
    var aspect = _videoSessionAspect(session);
    var boxWidth = (screen.width * 0.46).clamp(220.0, 360.0);
    var boxHeight = (boxWidth / aspect).clamp(130.0, 260.0);
    boxWidth = boxHeight * aspect;
    var displayedVideoId = session.video.id;
    var offset = Offset(
      screen.width - boxWidth - margin,
      screen.height - boxHeight - MediaQuery.paddingOf(context).bottom - 110,
    );

    late final OverlayEntry entry;
    void close() {
      entry.remove();
      if (_pictureInPictureVideo == entry) _pictureInPictureVideo = null;
      if (pip.session?.video.id == displayedVideoId) pip.close();
    }

    void switchMode(VideoDisplayMode mode, VideoSplitSession modeSession) {
      if (mode == VideoDisplayMode.pictureInPicture) return;
      close();
      switch (mode) {
        case VideoDisplayMode.pictureInPicture:
          break;
        case VideoDisplayMode.split:
          _videoSplit.play(modeSession);
        case VideoDisplayMode.fullscreen:
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (routeContext) => VideoPlaylistPlayerView(
                queue: modeSession.queue,
                onSwitchMode: (queue, nextMode) {
                  final currentSession = VideoSplitSession.fromQueue(queue);
                  switch (nextMode) {
                    case VideoDisplayMode.fullscreen:
                      break;
                    case VideoDisplayMode.pictureInPicture:
                      Navigator.of(routeContext).maybePop();
                      _showSplitVideoPictureInPicture(currentSession);
                    case VideoDisplayMode.split:
                      Navigator.of(routeContext).maybePop();
                      _videoSplit.play(currentSession);
                  }
                },
              ),
            ),
          );
      }
    }

    entry = OverlayEntry(
      builder: (overlayContext) => StatefulBuilder(
        builder: (context, setOverlayState) {
          final media = MediaQuery.sizeOf(context);
          final padding = MediaQuery.paddingOf(context);
          void clampFrame() {
            final maxWidth = math.max(80.0, media.width - margin * 2);
            final maxHeight = math.max(
              80.0,
              media.height - padding.top - padding.bottom - margin * 2,
            );
            if (boxWidth > maxWidth) {
              boxWidth = maxWidth;
              boxHeight = boxWidth / aspect;
            }
            if (boxHeight > maxHeight) {
              boxHeight = maxHeight;
              boxWidth = boxHeight * aspect;
            }
            final minX = math.min(margin, media.width - boxWidth);
            final maxX = math.max(minX, media.width - boxWidth - margin);
            final minY = math.min(
              padding.top + margin,
              media.height - boxHeight,
            );
            final maxY = math.max(
              minY,
              media.height - boxHeight - padding.bottom - margin,
            );
            offset = Offset(
              offset.dx.clamp(minX, maxX),
              offset.dy.clamp(minY, maxY),
            );
          }

          void syncSession(VideoSplitSession nextSession) {
            if (nextSession.video.id == displayedVideoId) return;
            displayedVideoId = nextSession.video.id;
            aspect = _videoSessionAspect(nextSession);
            boxHeight = (boxWidth / aspect).clamp(110.0, media.height * 0.72);
            boxWidth = boxHeight * aspect;
            clampFrame();
          }

          void move(DragUpdateDetails details) {
            setOverlayState(() {
              offset += details.delta;
              clampFrame();
            });
          }

          void resizeFromCorner(
            DragUpdateDetails details, {
            required int horizontalSign,
            required int verticalSign,
          }) {
            setOverlayState(() {
              final oldWidth = boxWidth;
              final oldHeight = boxHeight;
              final minW = math.min(180.0, media.width - margin * 2);
              final maxW = math.max(minW, media.width - margin * 2);
              final widthFromX = boxWidth + details.delta.dx * horizontalSign;
              final widthFromY =
                  boxWidth + details.delta.dy * verticalSign * aspect;
              final nextWidth =
                  (widthFromX - boxWidth).abs() > (widthFromY - boxWidth).abs()
                  ? widthFromX
                  : widthFromY;
              boxWidth = nextWidth.clamp(minW, maxW);
              boxHeight = boxWidth / aspect;
              if (boxHeight > media.height * 0.72) {
                boxHeight = media.height * 0.72;
                boxWidth = boxHeight * aspect;
              }
              if (boxHeight < 110) {
                boxHeight = 110;
                boxWidth = boxHeight * aspect;
              }
              if (horizontalSign < 0) {
                offset = offset.translate(oldWidth - boxWidth, 0);
              }
              if (verticalSign < 0) {
                offset = offset.translate(0, oldHeight - boxHeight);
              }
              clampFrame();
            });
          }

          return AnimatedBuilder(
            animation: pip,
            builder: (context, _) {
              final currentSession = pip.session;
              if (currentSession == null) return const SizedBox.shrink();
              syncSession(currentSession);
              clampFrame();
              final showDebugBounds = context
                  .watch<DeveloperModeController>()
                  .showPiPBounds;
              return Positioned(
                left: offset.dx,
                top: offset.dy,
                width: boxWidth,
                height: boxHeight,
                child: Material(
                  type: MaterialType.transparency,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          onPanUpdate: move,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: VideoPlayerView(
                              key: ValueKey(
                                '${currentSession.video.id}:${currentSession.messageId ?? 0}',
                              ),
                              video: currentSession.video,
                              thumb: currentSession.thumb,
                              width: currentSession.width,
                              height: currentSession.height,
                              presentation:
                                  VideoPlayerPresentation.pictureInPicture,
                              compactControls: true,
                              onClose: close,
                              sourceChatId: currentSession.chatId,
                              messageId: currentSession.messageId,
                              previousVideo: currentSession.queue.previous,
                              nextVideo: currentSession.queue.next,
                              onNavigate: (delta) {
                                final nextSession = currentSession.moveBy(
                                  delta,
                                );
                                if (nextSession != null) pip.play(nextSession);
                              },
                              currentMode: VideoDisplayMode.pictureInPicture,
                              onSwitchMode: (mode) =>
                                  switchMode(mode, currentSession),
                            ),
                          ),
                        ),
                      ),
                      _SplitPiPCornerHandle(
                        alignment: Alignment.topLeft,
                        onDrag: (details) => resizeFromCorner(
                          details,
                          horizontalSign: -1,
                          verticalSign: -1,
                        ),
                      ),
                      _SplitPiPCornerHandle(
                        alignment: Alignment.topRight,
                        onDrag: (details) => resizeFromCorner(
                          details,
                          horizontalSign: 1,
                          verticalSign: -1,
                        ),
                      ),
                      _SplitPiPCornerHandle(
                        alignment: Alignment.bottomLeft,
                        onDrag: (details) => resizeFromCorner(
                          details,
                          horizontalSign: -1,
                          verticalSign: 1,
                        ),
                      ),
                      _SplitPiPCornerHandle(
                        alignment: Alignment.bottomRight,
                        onDrag: (details) => resizeFromCorner(
                          details,
                          horizontalSign: 1,
                          verticalSign: 1,
                        ),
                      ),
                      if (showDebugBounds)
                        PiPBoundsDebugOverlay(
                          offset: offset,
                          size: Size(boxWidth, boxHeight),
                          viewport: media,
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
    _pictureInPictureVideo = entry;
    overlay.insert(entry);
  }
}

double _videoSessionAspect(VideoSplitSession session) {
  return (session.width != null &&
          session.height != null &&
          session.width! > 0 &&
          session.height! > 0)
      ? session.width! / session.height!
      : 16 / 9;
}

class _SplitPiPCornerHandle extends StatelessWidget {
  const _SplitPiPCornerHandle({required this.alignment, required this.onDrag});

  final Alignment alignment;
  final GestureDragUpdateCallback onDrag;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: alignment.x < 0 ? -8 : null,
      right: alignment.x > 0 ? -8 : null,
      top: alignment.y < 0 ? -8 : null,
      bottom: alignment.y > 0 ? -8 : null,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: onDrag,
        child: const SizedBox(width: 44, height: 44),
      ),
    );
  }
}
