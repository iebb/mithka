//
//  full_image_viewer.dart
//
//  Fullscreen image gallery. Pinch / double-tap to zoom, drag to pan when
//  zoomed; at fit-scale swipe down to dismiss and left/right to page across the
//  chat's images. Port of the Swift `FullImageViewer`.
//

import 'dart:io';

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';

class FullImageViewer extends StatefulWidget {
  const FullImageViewer({super.key, required this.items, this.startIndex = 0});
  final List<TdFileRef> items;
  final int startIndex;

  @override
  State<FullImageViewer> createState() => _FullImageViewerState();
}

class _FullImageViewerState extends State<FullImageViewer> {
  late final PageController _pageController = PageController(
    initialPage: widget.startIndex.clamp(0, _max),
  );
  late int _index = widget.startIndex.clamp(0, _max);
  double _dragY = 0;
  bool _zoomed = false;

  int get _max => widget.items.isEmpty ? 0 : widget.items.length - 1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dragY.abs() / 260).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 1 - progress * 0.85),
      body: Stack(
        children: [
          GestureDetector(
            onVerticalDragUpdate: _zoomed
                ? null
                : (d) => setState(() => _dragY += d.delta.dy),
            onVerticalDragEnd: _zoomed
                ? null
                : (_) {
                    if (_dragY.abs() > 110) {
                      Navigator.of(context).pop();
                    } else {
                      setState(() => _dragY = 0);
                    }
                  },
            child: Transform.translate(
              offset: Offset(0, _dragY),
              child: PageView.builder(
                controller: _pageController,
                physics: _zoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                onPageChanged: (i) => setState(() => _index = i),
                itemCount: widget.items.length,
                itemBuilder: (context, i) => _ViewerPage(
                  ref: widget.items[i],
                  onZoomChanged: (z) {
                    if (z != _zoomed) setState(() => _zoomed = z);
                  },
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Opacity(
              opacity: 1 - progress,
              child: Row(
                children: [
                  _circleAppIcon(
                    HeroAppIcons.xmark,
                    () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  if (widget.items.length > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${_index + 1} / ${widget.items.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  if (widget.items.length > 1) const Spacer(),
                  if (widget.items.length > 1) const SizedBox(width: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleAppIcon(AppIconData name, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: AppIcon(name, size: 18, color: Colors.white),
        ),
      );
}

class _ViewerPage extends StatefulWidget {
  const _ViewerPage({required this.ref, required this.onZoomChanged});
  final TdFileRef ref;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<_ViewerPage> {
  final _controller = TransformationController();
  File? _file;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransform);
    TdFileCenter.shared.pathFor(widget.ref).then((path) {
      if (mounted && path != null) setState(() => _file = File(path));
    });
  }

  void _onTransform() {
    widget.onZoomChanged(_controller.value.getMaxScaleOnAxis() > 1.01);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransform);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final cacheWidth = (media.size.width * media.devicePixelRatio).ceil();
    final cacheHeight = (media.size.height * media.devicePixelRatio).ceil();
    if (_file == null) {
      if (widget.ref.miniThumb != null) {
        return Center(
          child: Image.memory(
            widget.ref.miniThumb!,
            cacheWidth: cacheWidth,
            cacheHeight: cacheHeight,
          ),
        );
      }
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(Colors.white),
        ),
      );
    }
    return InteractiveViewer(
      transformationController: _controller,
      minScale: 1,
      maxScale: 5,
      child: Center(
        child: Image.file(
          _file!,
          fit: BoxFit.contain,
          cacheWidth: cacheWidth,
          cacheHeight: cacheHeight,
        ),
      ),
    );
  }
}
