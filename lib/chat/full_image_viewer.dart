//
//  full_image_viewer.dart
//
//  Fullscreen image gallery. Pinch / double-tap to zoom, drag to pan when
//  zoomed; at fit-scale swipe down to dismiss and left/right to page across the
//  chat's images. Port of the Swift `FullImageViewer`.
//

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';

class FullImageViewer extends StatefulWidget {
  const FullImageViewer({
    super.key,
    required this.items,
    this.startIndex = 0,
    this.primaryActionLabel,
    this.onPrimaryAction,
    this.onMore,
  });

  final List<TdFileRef> items;
  final int startIndex;
  final String? primaryActionLabel;
  final Future<void> Function(int index)? onPrimaryAction;
  final Future<void> Function(int index)? onMore;

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
  bool _runningAction = false;

  int get _max => widget.items.isEmpty ? 0 : widget.items.length - 1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _runAction(Future<void> Function(int index) action) async {
    if (_runningAction) return;
    setState(() => _runningAction = true);
    try {
      await action(_index);
    } finally {
      if (mounted) setState(() => _runningAction = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dragY.abs() / 260).clamp(0.0, 1.0);
    return ColoredBox(
      color: const Color(0xFF000000).withValues(alpha: 1 - progress * 0.85),
      child: Stack(
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
                    key: const ValueKey('image-viewer-close'),
                  ),
                  Expanded(
                    child: Center(
                      child: widget.items.length > 1
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFFFFFFF,
                                ).withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                '${_index + 1} / ${widget.items.length}',
                                style: const TextStyle(
                                  color: Color(0xFFFFFFFF),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                  if (widget.onMore != null)
                    _circleAppIcon(
                      HeroAppIcons.ellipsis,
                      _runningAction
                          ? null
                          : () => unawaited(_runAction(widget.onMore!)),
                      key: const ValueKey('image-viewer-more'),
                    )
                  else
                    const SizedBox(width: 40, height: 40),
                ],
              ),
            ),
          ),
          if (widget.primaryActionLabel != null &&
              widget.onPrimaryAction != null)
            Positioned(
              left: 22,
              right: 22,
              bottom: MediaQuery.of(context).padding.bottom + 18,
              child: Opacity(
                opacity: 1 - progress,
                child: Semantics(
                  button: true,
                  label: widget.primaryActionLabel,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _runningAction
                        ? null
                        : () => unawaited(_runAction(widget.onPrimaryAction!)),
                    child: Container(
                      key: const ValueKey('image-viewer-primary-action'),
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTheme.brand,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x55000000),
                            blurRadius: 18,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: _runningAction
                          ? const AppActivityIndicator(
                              size: 20,
                              color: Color(0xFFFFFFFF),
                            )
                          : Text(
                              widget.primaryActionLabel!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppTheme.onBrand,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _circleAppIcon(AppIconData name, VoidCallback? onTap, {Key? key}) =>
      GestureDetector(
        key: key,
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF).withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: AppIcon(name, size: 18, color: const Color(0xFFFFFFFF)),
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
        child: AppActivityIndicator(size: 24, color: Color(0xFFFFFFFF)),
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
