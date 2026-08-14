//
//  photo_avatar.dart
//
//  Avatar that shows a real TDLib profile photo when available (with an instant
//  minithumbnail placeholder), falling back to a colored monogram. Callers choose
//  circle vs rounded-square. Port of the Swift `PhotoAvatar`/`TDImage`.
//

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../app/performance_metrics.dart';
import '../l10n/app_localizations.dart';
import '../media/looping_media_playback.dart';
import '../tdlib/animated_avatar_repository.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'app_icons.dart';
import 'app_interactive_surface.dart';

/// Sizes its child to the avatar box, clips it to a circle or rounded square,
/// and optionally fills the shape and centres the child inside it.
///
/// This is one render object where the composition it replaces — clip, sized
/// box, coloured container, alignment — was four. Every chat row and every
/// message carries an avatar, so those four were among the priciest widgets in
/// the app by total count.
class AvatarSurface extends SingleChildRenderObjectWidget {
  const AvatarSurface({
    super.key,
    required Widget super.child,
    required this.size,
    this.square = false,
    this.background,
    this.centerChild = false,
  });

  final double size;
  final bool square;

  /// Painted behind the child, inside the clip.
  final Color? background;

  /// Lay the child out loosely and centre it, instead of stretching it to fill.
  final bool centerChild;

  @override
  RenderAvatarSurface createRenderObject(BuildContext context) =>
      _configure(RenderAvatarSurface());

  @override
  void updateRenderObject(
    BuildContext context,
    RenderAvatarSurface renderObject,
  ) => _configure(renderObject);

  RenderAvatarSurface _configure(RenderAvatarSurface renderObject) =>
      renderObject
        ..avatarSize = size
        ..square = square
        ..background = background
        ..centerChild = centerChild;
}

/// Render object behind [AvatarSurface].
class RenderAvatarSurface extends RenderShiftedBox {
  RenderAvatarSurface() : super(null);

  double _avatarSize = 0;
  double get avatarSize => _avatarSize;
  set avatarSize(double value) {
    if (_avatarSize == value) return;
    _avatarSize = value;
    _shapeBounds = null;
    markNeedsLayout();
  }

  bool _square = false;
  bool get square => _square;
  set square(bool value) {
    if (_square == value) return;
    _square = value;
    markNeedsPaint();
  }

  bool _centerChild = false;
  bool get centerChild => _centerChild;
  set centerChild(bool value) {
    if (_centerChild == value) return;
    _centerChild = value;
    markNeedsLayout();
  }

  Color? _background;
  Color? get background => _background;
  set background(Color? value) {
    if (_background == value) return;
    _background = value;
    _fill = value == null ? null : (Paint()..color = value);
    markNeedsPaint();
  }

  final LayerHandle<ClipPathLayer> _ovalLayer = LayerHandle<ClipPathLayer>();
  final LayerHandle<ClipRRectLayer> _roundedLayer =
      LayerHandle<ClipRRectLayer>();

  // A `Path` is a native allocation and a scrolling list repaints every avatar
  // every frame, so the shape is built once per size like `RenderClipOval` does.
  Rect? _shapeBounds;
  Path? _ovalShape;
  RRect? _roundedShape;
  Paint? _fill;

  void _updateShapes(Rect bounds) {
    if (_shapeBounds == bounds) return;
    _shapeBounds = bounds;
    _ovalShape = Path()..addOval(bounds);
    _roundedShape = RRect.fromRectAndRadius(
      bounds,
      Radius.circular(_avatarSize * AppTheme.groupAvatarCornerRatio),
    );
  }

  @override
  double computeMinIntrinsicWidth(double height) => _avatarSize;

  @override
  double computeMaxIntrinsicWidth(double height) => _avatarSize;

  @override
  double computeMinIntrinsicHeight(double width) => _avatarSize;

  @override
  double computeMaxIntrinsicHeight(double width) => _avatarSize;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(Size.square(_avatarSize));

  @override
  void performLayout() {
    size = constraints.constrain(Size.square(_avatarSize));
    final child = this.child;
    if (child == null) return;
    final childParentData = child.parentData! as BoxParentData;
    if (_centerChild) {
      child.layout(BoxConstraints.loose(size), parentUsesSize: true);
      childParentData.offset = Alignment.center.alongOffset(
        (size - child.size) as Offset,
      );
    } else {
      child.layout(BoxConstraints.tight(size));
      childParentData.offset = Offset.zero;
    }
  }

  void _paintContents(PaintingContext context, Offset offset) {
    final fill = _fill;
    if (fill != null) context.canvas.drawRect(offset & size, fill);
    super.paint(context, offset);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final bounds = Offset.zero & size;
    _updateShapes(bounds);
    if (_square) {
      _ovalLayer.layer = null;
      _roundedLayer.layer = context.pushClipRRect(
        needsCompositing,
        offset,
        bounds,
        _roundedShape!,
        _paintContents,
        oldLayer: _roundedLayer.layer,
      );
    } else {
      _roundedLayer.layer = null;
      _ovalLayer.layer = context.pushClipPath(
        needsCompositing,
        offset,
        bounds,
        _ovalShape!,
        _paintContents,
        oldLayer: _ovalLayer.layer,
      );
    }
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final bounds = Offset.zero & size;
    _updateShapes(bounds);
    if (_square) {
      if (!_roundedShape!.contains(position)) return false;
    } else {
      final center = bounds.center;
      final normalized = Offset(
        (position.dx - center.dx) / bounds.width,
        (position.dy - center.dy) / bounds.height,
      );
      if (normalized.distanceSquared > 0.25) return false;
    }
    return super.hitTest(result, position: position);
  }

  @override
  Rect describeApproximatePaintClip(RenderObject child) => Offset.zero & size;

  @override
  void dispose() {
    _ovalLayer.layer = null;
    _roundedLayer.layer = null;
    super.dispose();
  }
}

String _initial(String title) {
  final trimmed = title.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed.characters.first.toUpperCase();
}

@visibleForTesting
bool avatarAnimationIsEligible({
  required bool surfaceAllowsAnimation,
  required bool themeAllowsAnimation,
  required bool tickerEnabled,
  required bool appIsActive,
}) =>
    surfaceAllowsAnimation &&
    themeAllowsAnimation &&
    tickerEnabled &&
    appIsActive;

/// FVP/MDK creates a native player and worker set for every video controller.
/// Keep avatar playback globally bounded even outside the chat list so a dense
/// surface cannot exhaust native threads while it is coming on screen.
abstract final class _AvatarPlayerBudget {
  static const maxPlayers = 2;
  static int _reservedPlayers = 0;

  static _AvatarPlayerLease? tryAcquire() {
    if (_reservedPlayers >= maxPlayers) return null;
    _reservedPlayers++;
    return _AvatarPlayerLease();
  }

  static void _release() {
    if (_reservedPlayers > 0) _reservedPlayers--;
  }
}

final class _AvatarPlayerLease {
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _AvatarPlayerBudget._release();
  }
}

/// Profile/group avatar with a real TDLib photo, placeholder, and monogram.
class PhotoAvatar extends StatefulWidget {
  const PhotoAvatar({
    super.key,
    required this.title,
    this.photo,
    this.size = 50,
    this.square = false,
    this.showOnlineDot = false,
    this.allowAnimation = true,
  });

  final String title;
  final TdFileRef? photo;
  final double size;
  final bool square;
  final bool showOnlineDot;

  /// Whether this surface may create a video decoder for an animated avatar.
  /// Dense scrolling lists should leave this off and use the static photo.
  final bool allowAnimation;

  @override
  State<PhotoAvatar> createState() => _PhotoAvatarState();
}

class _PhotoAvatarState extends State<PhotoAvatar> with WidgetsBindingObserver {
  File? _file;
  VideoPlayerController? _animationController;
  _AvatarPlayerLease? _animationLease;
  int? _loadedId;
  int? _loadedSlot;
  bool _animateAvatars = false;
  bool _themeAllowsAnimation = true;
  bool _tickerEnabled = true;
  bool _appIsActive = true;
  bool _animationLoadPending = false;
  int _animationGeneration = 0;
  int? _animationSlot;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appIsActive =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _load();
  }

  @override
  void didUpdateWidget(PhotoAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
    if (oldWidget.photo?.id != widget.photo?.id ||
        oldWidget.photo?.hasAnimation != widget.photo?.hasAnimation ||
        oldWidget.photo?.photoId != widget.photo?.photoId ||
        oldWidget.allowAnimation != widget.allowAnimation ||
        _animationSlot != TdClient.shared.activeSlot) {
      _updateAnimationEligibility(forceReload: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    var themeAllowsAnimation = true;
    try {
      themeAllowsAnimation = context.watch<ThemeController>().animateAvatars;
    } on ProviderNotFoundException catch (_) {
      // Standalone widget tests and previews may not install app providers.
    }
    _themeAllowsAnimation = themeAllowsAnimation;
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _updateAnimationEligibility();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appIsActive = state == AppLifecycleState.resumed;
    _updateAnimationEligibility();
  }

  void _updateAnimationEligibility({bool forceReload = false}) {
    final enabled = avatarAnimationIsEligible(
      surfaceAllowsAnimation: widget.allowAnimation,
      themeAllowsAnimation: _themeAllowsAnimation,
      tickerEnabled: _tickerEnabled,
      appIsActive: _appIsActive,
    );
    final photo = widget.photo;
    // With nothing to play and nothing to tear down the async pass only
    // re-reads the account slot, and every avatar in a list pays for it.
    if (_animationController == null &&
        !_animationLoadPending &&
        (photo == null || !photo.hasAnimation)) {
      _animateAvatars = enabled;
      _animationSlot = TdClient.shared.activeSlot;
      return;
    }
    if (!forceReload && _animateAvatars == enabled) {
      if (enabled && _animationController == null && !_animationLoadPending) {
        unawaited(_syncAnimation());
      }
      return;
    }
    _animateAvatars = enabled;
    unawaited(_syncAnimation());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animationGeneration++;
    final controller = _animationController;
    final lease = _animationLease;
    _animationController = null;
    _animationLease = null;
    if (controller != null) {
      AppPerformanceMetrics.animatedAvatarPlayerStopped();
      unawaited(controller.dispose().whenComplete(() => lease?.release()));
    } else {
      lease?.release();
    }
    super.dispose();
  }

  Future<void> _syncAnimation() async {
    final generation = ++_animationGeneration;
    _animationLoadPending = true;
    try {
      await _syncAnimationForGeneration(generation);
    } finally {
      if (generation == _animationGeneration) {
        _animationLoadPending = false;
      }
    }
  }

  Future<void> _syncAnimationForGeneration(int generation) async {
    final oldController = _animationController;
    final oldLease = _animationLease;
    _animationController = null;
    _animationLease = null;
    if (oldController != null) {
      AppPerformanceMetrics.animatedAvatarPlayerStopped();
      try {
        await oldController.dispose();
      } finally {
        oldLease?.release();
      }
      if (mounted) setState(() {});
    } else {
      oldLease?.release();
    }
    final photo = widget.photo;
    final slot = TdClient.shared.activeSlot;
    _animationSlot = slot;
    if (!_animateAvatars || photo == null || !photo.hasAnimation) return;

    final lease = _AvatarPlayerBudget.tryAcquire();
    if (lease == null) return;
    var stateOwnsLease = false;

    try {
      final animation = await AnimatedAvatarRepository.shared.resolve(photo);
      if (!mounted || generation != _animationGeneration || animation == null) {
        return;
      }
      final path = await TdFileCenter.shared.pathFor(animation);
      if (!mounted || generation != _animationGeneration || path == null) {
        return;
      }
      final controller = VideoPlayerController.file(
        File(path),
        videoPlayerOptions: mutedLoopingVideoPlayerOptions(),
      );
      try {
        await controller.initialize();
        await controller.setLooping(true);
        await controller.setVolume(0);
        disableLoopingMediaAudioTracks(controller);
        await controller.play();
      } catch (_) {
        await controller.dispose();
        return;
      }
      if (!mounted ||
          generation != _animationGeneration ||
          slot != TdClient.shared.activeSlot) {
        await controller.dispose();
        return;
      }
      _animationLease = lease;
      stateOwnsLease = true;
      AppPerformanceMetrics.animatedAvatarPlayerStarted();
      setState(() => _animationController = controller);
    } finally {
      if (!stateOwnsLease) lease.release();
    }
  }

  void _load() {
    final ref = widget.photo;
    final slot = TdClient.shared.activeSlot;
    if (ref == null) {
      if (_file != null) setState(() => _file = null);
      _loadedId = null;
      _loadedSlot = null;
      return;
    }
    // File ids are per-account; reload when either id or active account changes.
    if (_loadedId == ref.id && _loadedSlot == slot) return;
    _loadedId = ref.id;
    _loadedSlot = slot;
    if (_file != null) {
      setState(() => _file = null); // reset to placeholder
    }
    TdFileCenter.shared.pathFor(ref).then((path) {
      if (!mounted || _loadedId != ref.id || _loadedSlot != slot) return;
      if (path != null) setState(() => _file = File(path));
    });
  }

  /// True while nothing but the monogram can paint, which the surface can then
  /// draw itself instead of stacking a fill and an alignment on top of it.
  bool get _showsMonogramOnly {
    final animation = _animationController;
    if (animation != null && animation.value.isInitialized) return false;
    return _file == null && widget.photo?.miniThumb == null;
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    Widget avatar = _showsMonogramOnly
        ? AvatarSurface(
            size: size,
            square: widget.square,
            background: AppTheme.avatarColor(widget.title),
            centerChild: true,
            child: _monogram(),
          )
        : AvatarSurface(size: size, square: widget.square, child: _content());

    if (widget.showOnlineDot) {
      final dot = size * 0.26;
      avatar = Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                color: AppTheme.onlineDot,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: size * 0.05),
              ),
            ),
          ),
        ],
      );
    }
    return avatar;
  }

  Widget _content() {
    final ref = widget.photo;
    final cacheSize = _cacheSizePx(context, widget.size);
    final animation = _animationController;
    if (animation != null && animation.value.isInitialized) {
      final videoSize = animation.value.size;
      return FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: videoSize.width,
          height: videoSize.height,
          child: VideoPlayer(animation),
        ),
      );
    }
    if (_file != null) {
      return Image.file(
        _file!,
        fit: BoxFit.cover,
        cacheWidth: cacheSize,
        cacheHeight: cacheSize,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    if (ref?.miniThumb != null) {
      return Image.memory(
        ref!.miniThumb!,
        fit: BoxFit.cover,
        cacheWidth: cacheSize,
        cacheHeight: cacheSize,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    return _placeholder();
  }

  /// Used when an image fails to decode, so it has to fill the box itself.
  Widget _placeholder() => Container(
    color: AppTheme.avatarColor(widget.title),
    alignment: Alignment.center,
    child: _monogram(),
  );

  Widget _monogram() => Text(
    _initial(widget.title),
    style: TextStyle(
      color: Colors.white,
      fontSize: widget.size * 0.42,
      fontWeight: FontWeight.w500,
    ),
  );
}

int _cacheSizePx(BuildContext context, double logicalSize) =>
    (logicalSize * MediaQuery.devicePixelRatioOf(context)).ceil();

/// Circular monogram avatar (fallback / simple cases like "我").
class MonogramAvatar extends StatelessWidget {
  const MonogramAvatar({
    super.key,
    required this.title,
    this.size = 50,
    this.showOnlineDot = false,
    this.square = false,
  });

  final String title;
  final double size;
  final bool showOnlineDot;
  final bool square;

  @override
  Widget build(BuildContext context) {
    return PhotoAvatar(
      title: title,
      size: size,
      square: square,
      showOnlineDot: showOnlineDot,
    );
  }
}

/// Generic TDLib-file image (e.g. photo-message thumbnails).
class TDImage extends StatefulWidget {
  const TDImage({
    super.key,
    this.photo,
    this.cornerRadius = 8,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.cacheHeight,
    this.showProgress = false,
  });
  final TdFileRef? photo;
  final double cornerRadius;
  final BoxFit fit;
  final int? cacheWidth;
  final int? cacheHeight;
  final bool showProgress;

  @override
  State<TDImage> createState() => _TDImageState();
}

class _TDImageState extends State<TDImage> {
  File? _file;
  File? _thumbnailFile;
  int? _loadedId;
  int? _loadedThumbnailId;
  int? _loadedSlot;
  TdFileProgress? _progress;
  StreamSubscription<TdFileProgress>? _progressSub;
  Timer? _progressPaintTimer;
  Timer? _downloadStallTimer;
  Timer? _downloadRecoveryTimer;
  DateTime? _lastProgressPaint;
  int? _stallWatchedDownloaded;
  int? _resumedDownloaded;
  bool _downloadStalled = false;
  int _missingFileRecoveries = 0;

  static const _maxMissingFileRecoveries = 2;
  static const _progressPaintInterval = Duration(milliseconds: 120);
  static const _downloadStallInterval = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TDImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  @override
  void dispose() {
    _progressPaintTimer?.cancel();
    _downloadStallTimer?.cancel();
    _downloadRecoveryTimer?.cancel();
    _progressSub?.cancel();
    super.dispose();
  }

  void _load() {
    final ref = widget.photo;
    final slot = TdClient.shared.activeSlot;
    final thumbnailId = ref?.thumbnail?.id;
    if (ref == null) {
      _loadedId = null;
      _loadedThumbnailId = null;
      _loadedSlot = null;
      _progressPaintTimer?.cancel();
      _progressPaintTimer = null;
      _downloadStallTimer?.cancel();
      _downloadStallTimer = null;
      _downloadRecoveryTimer?.cancel();
      _downloadRecoveryTimer = null;
      _stallWatchedDownloaded = null;
      _resumedDownloaded = null;
      _downloadStalled = false;
      _progressSub?.cancel();
      _progressSub = null;
      if (_file != null || _thumbnailFile != null || _progress != null) {
        setState(() {
          _file = null;
          _thumbnailFile = null;
          _progress = null;
        });
      } else {
        _progress = null;
      }
      return;
    }
    if (_loadedId == ref.id &&
        _loadedThumbnailId == thumbnailId &&
        _loadedSlot == slot &&
        oldProgressModeUnchanged()) {
      return;
    }
    if (_loadedId != ref.id || _loadedSlot != slot) _missingFileRecoveries = 0;
    _loadedId = ref.id;
    _loadedThumbnailId = thumbnailId;
    _loadedSlot = slot;
    _progress = null;
    _lastProgressPaint = null;
    _progressPaintTimer?.cancel();
    _progressPaintTimer = null;
    _downloadStallTimer?.cancel();
    _downloadStallTimer = null;
    _downloadRecoveryTimer?.cancel();
    _downloadRecoveryTimer = null;
    _stallWatchedDownloaded = null;
    _resumedDownloaded = null;
    _downloadStalled = false;
    _progressSub?.cancel();
    _progressSub = null;
    if (widget.showProgress) {
      _progressSub = TdFileCenter.shared
          .progress(ref.id, accountSlot: slot)
          .listen((progress) {
            if (!mounted || _loadedId != ref.id || _loadedSlot != slot) return;
            final now = DateTime.now();
            if (progress.isCompleted || !progress.isActive) {
              _progressPaintTimer?.cancel();
              _progressPaintTimer = null;
              _downloadStallTimer?.cancel();
              _downloadStallTimer = null;
              if (progress.isCompleted) {
                _downloadRecoveryTimer?.cancel();
                _downloadRecoveryTimer = null;
                _downloadStalled = false;
              }
              _stallWatchedDownloaded = null;
              _lastProgressPaint = now;
              setState(() => _progress = progress);
              if (progress.isCompleted && _file == null) {
                unawaited(_resolveCompletedFile(ref, slot));
              } else if (!progress.isCompleted) {
                _resumeDownloadOnce(ref, slot, progress.downloaded);
              }
              return;
            }
            _watchForStalledDownload(ref, slot, progress);
            final previous = _lastProgressPaint;
            if (previous != null &&
                now.difference(previous) < _progressPaintInterval) {
              _progress = progress;
              _progressPaintTimer ??= Timer(
                _progressPaintInterval - now.difference(previous),
                () {
                  _progressPaintTimer = null;
                  if (!mounted || _loadedId != ref.id || _loadedSlot != slot) {
                    return;
                  }
                  _lastProgressPaint = DateTime.now();
                  setState(() {});
                },
              );
              return;
            }
            _progressPaintTimer?.cancel();
            _progressPaintTimer = null;
            _lastProgressPaint = now;
            setState(() => _progress = progress);
          });
    }
    if (_file != null || _thumbnailFile != null) {
      setState(() {
        _file = null;
        _thumbnailFile = null;
      });
    }
    final thumbnail = ref.thumbnail;
    if (thumbnail != null && thumbnail.id != ref.id) {
      TdFileCenter.shared.pathFor(thumbnail, accountSlot: slot).then((path) {
        if (!mounted ||
            _loadedId != ref.id ||
            _loadedThumbnailId != thumbnail.id ||
            _loadedSlot != slot) {
          return;
        }
        if (path != null) setState(() => _thumbnailFile = File(path));
      });
    }
    TdFileCenter.shared.pathFor(ref, accountSlot: slot).then((path) {
      if (!mounted || _loadedId != ref.id || _loadedSlot != slot) return;
      if (path != null) {
        setState(() => _file = File(path));
        return;
      }
      // The bounded resolver expired. Stop painting its last active percent
      // and make one mounted-only, fire-and-forget resume request. A later
      // completion event will resolve the cached file through
      // _resolveCompletedFile without keeping another long waiter alive.
      _progressPaintTimer?.cancel();
      _progressPaintTimer = null;
      final stalledDownloaded = _progress?.downloaded ?? -1;
      if (_progress != null) setState(() => _progress = null);
      _resumeDownloadOnce(ref, slot, stalledDownloaded);
    });
  }

  void _watchForStalledDownload(
    TdFileRef ref,
    int slot,
    TdFileProgress progress,
  ) {
    final downloaded = progress.downloaded;
    final resumed = _resumedDownloaded;
    if (resumed != null && downloaded > resumed) {
      _resumedDownloaded = null;
      _downloadRecoveryTimer?.cancel();
      _downloadRecoveryTimer = null;
      _downloadStalled = false;
    }
    if (_stallWatchedDownloaded == downloaded && _downloadStallTimer != null) {
      return;
    }
    _downloadStallTimer?.cancel();
    _downloadStallTimer = null;
    _stallWatchedDownloaded = downloaded;
    if (_resumedDownloaded == downloaded) return;
    _downloadStallTimer = Timer(_downloadStallInterval, () {
      _downloadStallTimer = null;
      _stallWatchedDownloaded = null;
      if (!mounted ||
          _loadedId != ref.id ||
          _loadedSlot != slot ||
          _progress?.isActive != true ||
          _progress?.downloaded != downloaded) {
        return;
      }
      _resumeDownloadOnce(ref, slot, downloaded);
    });
  }

  void _resumeDownloadOnce(TdFileRef ref, int slot, int downloaded) {
    if (_resumedDownloaded == downloaded) return;
    _resumedDownloaded = downloaded;
    _downloadRecoveryTimer?.cancel();
    _downloadRecoveryTimer = Timer(_downloadStallInterval, () {
      _downloadRecoveryTimer = null;
      if (!mounted ||
          _loadedId != ref.id ||
          _loadedSlot != slot ||
          _resumedDownloaded != downloaded ||
          (_progress != null && _progress?.downloaded != downloaded)) {
        return;
      }
      setState(() => _downloadStalled = true);
    });
    TdFileCenter.shared.resumeDownload(ref.id, accountSlot: slot);
  }

  void _retryStalledDownload() {
    final ref = widget.photo;
    final slot = _loadedSlot;
    if (ref == null ||
        slot == null ||
        _loadedId != ref.id ||
        !_downloadStalled) {
      return;
    }
    final downloaded = _progress?.downloaded ?? _resumedDownloaded ?? -1;
    _resumedDownloaded = null;
    setState(() => _downloadStalled = false);
    _resumeDownloadOnce(ref, slot, downloaded);
  }

  /// A completion can arrive after path()'s bounded waiter has returned null.
  /// TdFileCenter has already cached the completed path before dispatching the
  /// terminal progress event, so resolve it again instead of leaving the
  /// minithumbnail and its last active percentage on screen forever.
  Future<void> _resolveCompletedFile(TdFileRef ref, int slot) async {
    final path = await TdFileCenter.shared.pathFor(ref, accountSlot: slot);
    if (!mounted ||
        path == null ||
        _loadedId != ref.id ||
        _loadedSlot != slot ||
        _file?.path == path) {
      return;
    }
    setState(() => _file = File(path));
  }

  bool oldProgressModeUnchanged() {
    if (widget.showProgress) return _progressSub != null;
    return _progressSub == null;
  }

  /// Replaces an unreadable local file with the placeholder and fetches it
  /// again. TDLib deletes cached media behind the app's back, and a path that
  /// resolved earlier then makes `Image.file` throw — which used to paint
  /// Flutter's broken-image box across the whole media frame.
  Widget _recoverFromUnreadableFile(File file, {required bool isThumbnail}) {
    final ref = widget.photo;
    final target = isThumbnail ? ref?.thumbnail : ref;
    final slot = _loadedSlot;
    if (target != null &&
        slot != null &&
        _missingFileRecoveries < _maxMissingFileRecoveries) {
      _missingFileRecoveries++;
      TdFileCenter.shared.forget(target.id, accountSlot: slot);
      // errorBuilder runs inside build, so the state change waits for the frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          _reresolveMissingFile(
            file,
            target,
            accountSlot: slot,
            isThumbnail: isThumbnail,
          ),
        );
      });
    }
    final miniThumb = ref?.miniThumb;
    if (miniThumb != null) {
      return Image.memory(miniThumb, fit: widget.fit, gaplessPlayback: true);
    }
    return ColoredBox(color: context.colors.groupedBackground);
  }

  Future<void> _reresolveMissingFile(
    File missing,
    TdFileRef target, {
    required int accountSlot,
    required bool isThumbnail,
  }) async {
    final owned = isThumbnail
        ? _thumbnailFile?.path == missing.path
        : _file?.path == missing.path;
    if (!owned || _loadedSlot != accountSlot) return;
    setState(() {
      if (isThumbnail) {
        _thumbnailFile = null;
      } else {
        _file = null;
      }
    });
    final path = await TdFileCenter.shared.pathFor(
      target,
      accountSlot: accountSlot,
    );
    if (!mounted || path == null || _loadedSlot != accountSlot) return;
    if (isThumbnail ? _thumbnailFile != null : _file != null) return;
    setState(() {
      if (isThumbnail) {
        _thumbnailFile = File(path);
      } else {
        _file = File(path);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Callers that already know their decode size skip the LayoutBuilder, whose
    // performLayout re-enters the build phase on every relayout.
    final Widget child = widget.cacheWidth != null && widget.cacheHeight != null
        ? _image(context, widget.cacheWidth, widget.cacheHeight)
        : LayoutBuilder(
            builder: (context, constraints) => _image(
              context,
              widget.cacheWidth ??
                  _cacheSizePxFromConstraint(context, constraints.maxWidth),
              widget.cacheHeight ??
                  _cacheSizePxFromConstraint(context, constraints.maxHeight),
            ),
          );
    // A zero-radius ClipRRect still costs a clip op per paint, and 25 of the
    // TDImage call sites ask for one.
    if (widget.cornerRadius <= 0) return child;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.cornerRadius),
      child: child,
    );
  }

  Widget _image(
    BuildContext context,
    int? requestedWidth,
    int? requestedHeight,
  ) {
    final cacheSize = _boundedImageCacheSize(requestedWidth, requestedHeight);
    final cacheWidth = cacheSize?.width;
    final cacheHeight = cacheSize?.height;
    Widget child;
    if (_file != null) {
      child = Image.file(
        _file!,
        fit: widget.fit,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        gaplessPlayback: true,
        errorBuilder: (context, _, _) =>
            _recoverFromUnreadableFile(_file!, isThumbnail: false),
      );
    } else if (_thumbnailFile != null) {
      child = Image.file(
        _thumbnailFile!,
        fit: widget.fit,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        gaplessPlayback: true,
        errorBuilder: (context, _, _) =>
            _recoverFromUnreadableFile(_thumbnailFile!, isThumbnail: true),
      );
    } else if (widget.photo?.miniThumb != null) {
      child = Image.memory(
        widget.photo!.miniThumb!,
        fit: widget.fit,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        gaplessPlayback: true,
      );
    } else {
      child = Container(color: context.colors.groupedBackground);
    }
    final showRetry = widget.showProgress && _file == null && _downloadStalled;
    final showLoadingProgress =
        widget.showProgress &&
        _file == null &&
        !showRetry &&
        _progress?.isActive == true &&
        _progress?.isCompleted != true;
    if (showRetry || showLoadingProgress) {
      child = Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (showRetry)
            _MediaDownloadRetry(onRetry: _retryStalledDownload)
          else
            _MediaLoadingProgress(progress: _progress),
        ],
      );
    }
    return child;
  }
}

int? _cacheSizePxFromConstraint(BuildContext context, double logicalSize) {
  if (!logicalSize.isFinite || logicalSize <= 0) return null;
  return _cacheSizePx(context, logicalSize);
}

_DecodedImageSize? _boundedImageCacheSize(int? width, int? height) {
  if (width == null && height == null) return null;
  final maxSide = defaultTargetPlatform == TargetPlatform.android ? 1280 : 1920;
  final maxPixels = defaultTargetPlatform == TargetPlatform.android
      ? 1280 * 1280
      : 1920 * 1920;
  var boundedWidth = _boundedImageDimension(width, maxSide);
  var boundedHeight = _boundedImageDimension(height, maxSide);
  if (boundedWidth != null && boundedHeight != null) {
    final pixels = boundedWidth * boundedHeight;
    if (pixels > maxPixels) {
      final scale = math.sqrt(maxPixels / pixels);
      boundedWidth = math.max(1, (boundedWidth * scale).round());
      boundedHeight = math.max(1, (boundedHeight * scale).round());
    }
  }
  return _DecodedImageSize(width: boundedWidth, height: boundedHeight);
}

int? _boundedImageDimension(int? value, int maxSide) {
  if (value == null || value <= 0) return null;
  return value > maxSide ? maxSide : value;
}

class _DecodedImageSize {
  const _DecodedImageSize({required this.width, required this.height});

  final int? width;
  final int? height;
}

class _MediaLoadingProgress extends StatelessWidget {
  const _MediaLoadingProgress({this.progress});

  final TdFileProgress? progress;

  @override
  Widget build(BuildContext context) {
    final value = progress?.fraction;
    final text = value == null || value <= 0 || value >= 1
        ? null
        : '${(value * 100).clamp(1, 99).round()}%';
    // Without a boundary the indeterminate sweep repaints the whole media
    // bubble — decoded image, clip and blurred frame — on every frame.
    return RepaintBoundary(
      child: Center(
        child: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.38),
            shape: BoxShape.circle,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 46,
                height: 46,
                child: CircularProgressIndicator(
                  value: value != null && value > 0 && value < 1 ? value : null,
                  strokeWidth: 3,
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                  backgroundColor: Colors.white.withValues(alpha: 0.24),
                ),
              ),
              if (text != null)
                Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaDownloadRetry extends StatelessWidget {
  const _MediaDownloadRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppInteractiveSurface(
        key: const ValueKey('td-image-download-retry'),
        onTap: onRetry,
        semanticLabel: AppStringKeys.callsRetry.l10n(context),
        borderRadius: BorderRadius.circular(29),
        child: Container(
          width: 58,
          height: 58,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.46),
            shape: BoxShape.circle,
          ),
          child: const AppIcon(
            HeroAppIcons.arrowsRotate,
            size: 27,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
