//
//  full_image_viewer.dart
//
//  Fullscreen image gallery. Pinch / double-tap to zoom, drag to pan when
//  zoomed; at fit-scale swipe down to dismiss and left/right to page across the
//  chat's images. Port of the Swift `FullImageViewer`.
//

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../app/ipad_window_chrome.dart';
import '../app/macos_desktop_title_bar.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../platform/adaptive_platform.dart';
import '../platform/desktop_clipboard_images.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'media_download_service.dart';
import 'media_library_saver.dart';

/// Per-item actions for the viewer's own `…` menu, supplied by entry points
/// that know which message each image belongs to.
class ImageViewerMessageActions {
  const ImageViewerMessageActions({
    required this.messageIds,
    required this.onViewInChat,
    this.onReply,
  });

  /// The message id behind each gallery item, aligned with [FullImageViewer.items].
  final List<int?> messageIds;

  /// Jumps back to the chat and highlights the message. Null entries mean the
  /// entry point cannot resolve an anchor (e.g. profile photos).
  final Future<void> Function(int messageId) onViewInChat;

  /// Same jump, but arms the composer with a reply to the message first.
  final Future<void> Function(int messageId)? onReply;
}

class FullImageViewer extends StatefulWidget {
  const FullImageViewer({
    super.key,
    required this.items,
    this.startIndex = 0,
    this.primaryActionLabel,
    this.onPrimaryAction,
    this.onMore,
    this.messageActions,
  });

  final List<TdFileRef> items;
  final int startIndex;
  final String? primaryActionLabel;
  final Future<void> Function(int index)? onPrimaryAction;
  final Future<void> Function(int index)? onMore;

  /// Enables View in Chat / Reply for galleries opened from a chat.
  final ImageViewerMessageActions? messageActions;

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
  final _pageKeys = <int, GlobalKey<_ViewerPageState>>{};
  int? _gesturePage;
  bool _runningAction = false;
  bool _menuVisible = false;

  int get _max => widget.items.isEmpty ? 0 : widget.items.length - 1;

  /// Keeps the viewer's own controls clear of the macOS window controls, which
  /// sit over this route because it covers the window edge to edge.
  static double get _chromeInset =>
      defaultTargetPlatform == TargetPlatform.macOS
      ? MacosDesktopTitleBar.trafficLightLeadingClearance
      : 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  int? get _currentMessageId {
    final actions = widget.messageActions;
    if (actions == null || _index >= actions.messageIds.length) return null;
    return actions.messageIds[_index];
  }

  Future<void> _viewInChat({bool reply = false}) async {
    final messageId = _currentMessageId;
    if (messageId == null) return;
    final actions = widget.messageActions!;
    if (mounted) setState(() => _menuVisible = false);
    // Close only this gallery route. Its chat may be nested in a tab or
    // pushed above the root's home; unwinding to the root's first route
    // would dispose the latter before the message jump can be applied.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    if (route != null && !route.isFirst) {
      Navigator.of(context).pop();
    }
    final replyHandler = reply ? actions.onReply : null;
    if (replyHandler != null) {
      await replyHandler(messageId);
    } else {
      await actions.onViewInChat(messageId);
    }
  }

  Future<void> _copyCurrentImage() async {
    if (mounted) setState(() => _menuVisible = false);
    final ref = widget.items[_index];
    try {
      final path = await TdFileCenter.shared.pathFor(ref);
      final copied =
          path != null &&
          await DesktopClipboardImageService.copyImageFile(File(path));
      if (!mounted) return;
      showToast(
        context,
        copied
            ? AppStringKeys.qrScannerCopied
            : AppStringKeys.messageActionCopyImageFailed,
        visibleFor: const Duration(seconds: 2),
      );
    } catch (_) {
      if (!mounted) return;
      showToast(
        context,
        AppStringKeys.messageActionCopyImageFailed,
        visibleFor: const Duration(seconds: 2),
      );
    }
  }

  Future<void> _saveCurrentImage() async {
    if (mounted) setState(() => _menuVisible = false);
    final ref = widget.items[_index];
    final isDesktop = isDesktopTargetPlatform(defaultTargetPlatform);
    try {
      if (isDesktop) {
        final outcome = await MediaDownloadService.saveMedia(
          file: ref,
          isVideo: false,
        );
        if (!mounted) return;
        final feedback = MediaDownloadService.feedbackFor(outcome);
        if (feedback != null) {
          showToast(context, feedback, visibleFor: const Duration(seconds: 2));
        }
        return;
      }
      DateTime? progressShownAt;
      final progressTimer = Timer(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        progressShownAt = DateTime.now();
        showToast(
          context,
          AppStringKeys.chatSavingToPhotos,
          visibleFor: const Duration(milliseconds: 900),
        );
      });
      MediaLibrarySaveResult result;
      try {
        final path = await TdFileCenter.shared.pathFor(ref);
        if (path == null || !await File(path).exists()) {
          result = MediaLibrarySaveResult.failed;
        } else {
          result = await MediaLibrarySaver.savePreparedFile(
            File(path),
            isVideo: false,
          );
        }
      } finally {
        progressTimer.cancel();
      }
      if (!mounted) return;
      if (progressShownAt case final shownAt?) {
        final remaining =
            const Duration(milliseconds: 1400) -
            DateTime.now().difference(shownAt);
        if (remaining > Duration.zero) {
          await Future<void>.delayed(remaining);
        }
        if (!mounted) return;
      }
      showToast(context, switch (result) {
        MediaLibrarySaveResult.saved => AppStringKeys.chatSavedToPhotos,
        MediaLibrarySaveResult.permissionDenied =>
          AppStringKeys.chatSaveToPhotosPermissionDenied,
        MediaLibrarySaveResult.failed || MediaLibrarySaveResult.unsupported =>
          AppStringKeys.chatSaveToPhotosFailed,
      }, visibleFor: const Duration(seconds: 2));
    } catch (_) {
      if (!mounted) return;
      showToast(
        context,
        AppStringKeys.chatSaveToPhotosFailed,
        visibleFor: const Duration(seconds: 2),
      );
    }
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

  _ViewerPageState? get _gesturePageState =>
      _pageKeys[_gesturePage]?.currentState;

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _gesturePage ??= _index;
    _gesturePageState?._onPointerDown(event);
  }

  void _onPointerMove(PointerMoveEvent event) {
    final page = _gesturePageState;
    final viewport = context.size;
    if (page != null && viewport != null) {
      page._onPointerMove(event, viewport);
    }
  }

  void _onPointerEnd(PointerEvent event) {
    final page = _gesturePageState;
    page?._onPointerEnd(event);
    if (page == null || page._touches.isEmpty) _gesturePage = null;
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dragY.abs() / 260).clamp(0.0, 1.0);
    return ColoredBox(
      color: const Color(0xFF000000).withValues(alpha: 1 - progress * 0.85),
      child: Stack(
        children: [
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerEnd,
            onPointerCancel: _onPointerEnd,
            child: GestureDetector(
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
                    key: _pageKeys.putIfAbsent(
                      i,
                      GlobalKey<_ViewerPageState>.new,
                    ),
                    ref: widget.items[i],
                    onPinchStart: () {
                      setState(() {
                        _dragY = 0;
                        _zoomed = true;
                      });
                      _pageController.jumpToPage(_index);
                    },
                    onZoomChanged: (z) {
                      if (z != _zoomed) setState(() => _zoomed = z);
                    },
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top:
                MediaQuery.of(context).padding.top +
                iPadWindowChromeInsetOf(context) +
                8,
            // The viewer covers the whole window, so on macOS the row would
            // otherwise sit under the traffic lights. Both sides move in by the
            // same clearance to keep the counter centred on the window.
            left: 16 + _chromeInset,
            right: 16 + _chromeInset,
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
                              key: const ValueKey('image-viewer-counter'),
                              height: 32,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFFFFFFF,
                                ).withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.lg,
                                ),
                              ),
                              // A Container given an alignment grows to its
                              // constraints, which here is the whole width
                              // between the buttons: the counter rendered as a
                              // bar across the window. Centring with a width
                              // factor keeps the pill around its text.
                              child: Center(
                                widthFactor: 1,
                                child: Text(
                                  '${_index + 1} / ${widget.items.length}',
                                  style: const TextStyle(
                                    color: Color(0xFFFFFFFF),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                  _circleAppIcon(
                    HeroAppIcons.ellipsis,
                    _runningAction
                        ? null
                        : () {
                            if (widget.onMore != null) {
                              unawaited(_runAction(widget.onMore!));
                            } else {
                              setState(() => _menuVisible = !_menuVisible);
                            }
                          },
                    key: const ValueKey('image-viewer-more'),
                  ),
                ],
              ),
            ),
          ),
          if (_menuVisible)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (_) => setState(() => _menuVisible = false),
                child: const SizedBox.expand(),
              ),
            ),
          if (_menuVisible)
            Positioned(
              top:
                  MediaQuery.of(context).padding.top +
                  iPadWindowChromeInsetOf(context) +
                  56,
              right: 16 + _chromeInset,
              child: _ViewerActionsMenu(
                canCopy: DesktopClipboardImageService.canWriteImage,
                messageActions: _currentMessageId == null
                    ? null
                    : widget.messageActions,
                onCopy: () => unawaited(_copyCurrentImage()),
                onSave: () => unawaited(_saveCurrentImage()),
                onViewInChat: () => unawaited(_viewInChat()),
                onReply: widget.messageActions?.onReply == null
                    ? null
                    : () => unawaited(_viewInChat(reply: true)),
                onDismiss: () => setState(() => _menuVisible = false),
              ),
            ),
          if (widget.primaryActionLabel != null &&
              widget.onPrimaryAction != null)
            Positioned(
              left: 22 + _chromeInset,
              right: 22 + _chromeInset,
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
                        borderRadius: BorderRadius.circular(AppRadius.card),
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
  const _ViewerPage({
    super.key,
    required this.ref,
    required this.onZoomChanged,
    required this.onPinchStart,
  });
  final TdFileRef ref;
  final ValueChanged<bool> onZoomChanged;
  final VoidCallback onPinchStart;

  @override
  State<_ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<_ViewerPage> {
  final _controller = TransformationController();
  final _touches = <int, Offset>{};
  bool _touchZoomActive = false;
  double _pinchStartSpan = 1;
  double _pinchStartScale = 1;
  Offset _pinchScenePoint = Offset.zero;
  File? _file;
  File? _thumbnailFile;
  int _resolutionGeneration = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransform);
    _resolveFiles();
  }

  @override
  void didUpdateWidget(covariant _ViewerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isSameFile(oldWidget.ref, widget.ref)) {
      _file = null;
      _thumbnailFile = null;
      _controller.value = Matrix4.identity();
      widget.onZoomChanged(false);
      _resolveFiles();
    }
  }

  bool _isSameFile(TdFileRef a, TdFileRef b) =>
      a.id == b.id &&
      a.localPath == b.localPath &&
      a.thumbnail?.id == b.thumbnail?.id &&
      a.thumbnail?.localPath == b.thumbnail?.localPath;

  void _resolveFiles() {
    final generation = ++_resolutionGeneration;
    final ref = widget.ref;
    TdFileCenter.shared.pathFor(ref).then((path) {
      if (!mounted || generation != _resolutionGeneration || path == null) {
        return;
      }
      setState(() => _file = File(path));
    });

    final thumbnail = ref.thumbnail;
    if (thumbnail == null || thumbnail.id == ref.id) return;
    TdFileCenter.shared.pathFor(thumbnail).then((path) {
      if (!mounted || generation != _resolutionGeneration || path == null) {
        return;
      }
      setState(() => _thumbnailFile = File(path));
    });
  }

  void _onTransform() {
    widget.onZoomChanged(
      _touchZoomActive || _controller.value.getMaxScaleOnAxis() > 1.01,
    );
  }

  // A second finger can take over even when a gallery swipe or dismiss drag
  // has already won the gesture arena before the scale recognizer starts.
  void _onPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _touches[event.pointer] = event.localPosition;
    if (_touches.length != 2) return;
    setState(() => _touchZoomActive = true);
    widget.onPinchStart();
    final points = _touches.values.toList();
    _pinchStartSpan = math.max(1, (points[1] - points[0]).distance);
    _pinchStartScale = _controller.value.getMaxScaleOnAxis();
    _pinchScenePoint = _controller.toScene((points[0] + points[1]) / 2);
  }

  void _onPointerMove(PointerMoveEvent event, Size viewport) {
    final previous = _touches[event.pointer];
    if (previous == null) return;
    _touches[event.pointer] = event.localPosition;
    if (!_touchZoomActive) return;
    if (_touches.length >= 2) {
      final points = _touches.values.take(2).toList();
      final scale =
          (_pinchStartScale *
                  (points[1] - points[0]).distance /
                  _pinchStartSpan)
              .clamp(1.0, 5.0);
      _setTouchTransform(
        scale,
        (points[0] + points[1]) / 2 - _pinchScenePoint * scale,
        viewport,
      );
    } else {
      final translation = _controller.value.getTranslation();
      _setTouchTransform(
        _controller.value.getMaxScaleOnAxis(),
        Offset(translation.x, translation.y) + event.localPosition - previous,
        viewport,
      );
    }
  }

  void _setTouchTransform(double scale, Offset offset, Size viewport) {
    _controller.value = Matrix4.identity()
      ..setTranslationRaw(
        offset.dx.clamp(viewport.width * (1 - scale), 0),
        offset.dy.clamp(viewport.height * (1 - scale), 0),
        0,
      )
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _onPointerEnd(PointerEvent event) {
    _touches.remove(event.pointer);
    if (_touches.isEmpty && _touchZoomActive) {
      setState(() => _touchZoomActive = false);
      _onTransform();
    }
  }

  void _toggleZoom() {
    final current = _controller.value.getMaxScaleOnAxis();
    final next = current > 1.01 ? 1.0 : 2.0;
    _controller.value = Matrix4.diagonal3Values(next, next, 1);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransform);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Sized from the box this page is given, not MediaQuery: the viewer also
    // runs inside a desktop window and a split-layout pane, where the screen is
    // larger than the viewport and the image spilled past it.
    return LayoutBuilder(builder: _buildPage);
  }

  Widget _buildPage(BuildContext context, BoxConstraints constraints) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final size = constraints.biggest;
    final cacheWidth = (size.width * ratio).ceil();
    final cacheHeight = (size.height * ratio).ceil();
    Widget fittedImage(ImageProvider<Object> image) => SizedBox(
      width: size.width,
      height: size.height,
      child: Image(image: image, fit: BoxFit.contain),
    );
    Widget interactive(Widget child) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: 1,
        maxScale: 5,
        panEnabled: !_touchZoomActive,
        scaleEnabled: !_touchZoomActive,
        trackpadScrollCausesScale: true,
        // Keep a finite viewport-sized child for both the real image and its
        // full image and every thumbnail. Previously only a fully downloaded
        // file or an in-memory mini-thumbnail was put in InteractiveViewer,
        // so images still resolving from TDLib could not be zoomed at all.
        child: child,
      ),
    );
    if (_file == null) {
      if (_thumbnailFile != null) {
        return interactive(
          fittedImage(
            ResizeImage(
              FileImage(_thumbnailFile!),
              width: cacheWidth,
              height: cacheHeight,
              policy: ResizeImagePolicy.fit,
            ),
          ),
        );
      }
      if (widget.ref.miniThumb != null) {
        return Center(
          child: interactive(
            fittedImage(
              ResizeImage(
                MemoryImage(widget.ref.miniThumb!),
                width: cacheWidth,
                height: cacheHeight,
                policy: ResizeImagePolicy.fit,
              ),
            ),
          ),
        );
      }
      return const Center(
        child: AppActivityIndicator(size: 24, color: Color(0xFFFFFFFF)),
      );
    }
    return interactive(
      fittedImage(
        ResizeImage(
          FileImage(_file!),
          width: cacheWidth,
          height: cacheHeight,
          policy: ResizeImagePolicy.fit,
        ),
      ),
    );
  }
}

/// The dropdown opened by the viewer's `…` button: copy / save the current
/// image, and jump back to its chat when the entry point supplied message
/// anchors. Styled after the desktop preview window's more menu.
class _ViewerActionsMenu extends StatelessWidget {
  const _ViewerActionsMenu({
    required this.canCopy,
    required this.onCopy,
    required this.onSave,
    required this.onViewInChat,
    required this.onDismiss,
    this.messageActions,
    this.onReply,
  });

  final bool canCopy;
  final ImageViewerMessageActions? messageActions;
  final VoidCallback onCopy;
  final VoidCallback onSave;
  final VoidCallback onViewInChat;
  final VoidCallback? onReply;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('image-viewer-actions-menu'),
      width: 204,
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xF5222327),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: const Color(0xFF3B3D42)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (messageActions != null) ...[
            _ViewerActionsMenuItem(
              key: const ValueKey('image-viewer-action-view-in-chat'),
              icon: HeroAppIcons.arrowRight,
              label: AppStringKeys.messageViewInChat.l10n(context),
              onTap: onViewInChat,
            ),
            if (onReply != null)
              _ViewerActionsMenuItem(
                key: const ValueKey('image-viewer-action-reply'),
                icon: HeroAppIcons.quoteLeft,
                label: AppStringKeys.chatInputBarReply.l10n(context),
                onTap: onReply!,
              ),
          ],
          if (canCopy)
            _ViewerActionsMenuItem(
              key: const ValueKey('image-viewer-action-copy'),
              icon: HeroAppIcons.image,
              label: AppStringKeys.messageActionCopyImage.l10n(context),
              onTap: onCopy,
            ),
          _ViewerActionsMenuItem(
            key: const ValueKey('image-viewer-action-save'),
            icon: HeroAppIcons.download,
            label: AppStringKeys.messageActionSaveToPhotos.l10n(context),
            onTap: onSave,
          ),
        ],
      ),
    );
  }
}

class _ViewerActionsMenuItem extends StatelessWidget {
  const _ViewerActionsMenuItem({
    super.key,
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
      child: SizedBox(
        height: 36,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          child: Row(
            children: [
              AppIcon(icon, size: 16, color: const Color(0xFFCACCD0)),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFE8E9EB),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
