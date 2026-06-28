//
//  photo_avatar.dart
//
//  Avatar that shows a real TDLib profile photo when available (with an instant
//  minithumbnail placeholder), falling back to a colored monogram. Callers choose
//  circle vs rounded-square. Port of the Swift `PhotoAvatar`/`TDImage`.
//

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';

/// Clips its child to a circle or rounded square.
class AvatarClip extends StatelessWidget {
  const AvatarClip({
    super.key,
    required this.child,
    required this.size,
    this.square = false,
  });
  final Widget child;
  final double size;
  final bool square;

  @override
  Widget build(BuildContext context) {
    if (square) {
      return ClipRRect(
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(
          size * AppTheme.groupAvatarCornerRatio,
        ),
        child: child,
      );
    }
    return ClipOval(clipBehavior: Clip.antiAlias, child: child);
  }
}

String _initial(String title) {
  final trimmed = title.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed.characters.first.toUpperCase();
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
  });

  final String title;
  final TdFileRef? photo;
  final double size;
  final bool square;
  final bool showOnlineDot;

  @override
  State<PhotoAvatar> createState() => _PhotoAvatarState();
}

class _PhotoAvatarState extends State<PhotoAvatar> {
  File? _file;
  int? _loadedId;
  int? _loadedSlot;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PhotoAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
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
    setState(() => _file = null); // reset to placeholder
    TdFileCenter.shared.path(ref.id).then((path) {
      if (!mounted || _loadedId != ref.id || _loadedSlot != slot) return;
      if (path != null) setState(() => _file = File(path));
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    Widget avatar = AvatarClip(
      size: size,
      square: widget.square,
      child: SizedBox(width: size, height: size, child: _content()),
    );

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
    if (_file != null) {
      return Image.file(
        _file!,
        fit: BoxFit.cover,
        cacheWidth: cacheSize,
        cacheHeight: cacheSize,
        gaplessPlayback: true,
        // medium = trilinear/mipmapped sampling, so a large source photo shrunk
        // to a small avatar isn't aliased/shimmery (low is the default).
        filterQuality: FilterQuality.medium,
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
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    final size = widget.size;
    return Container(
      color: AppTheme.avatarColor(widget.title),
      alignment: Alignment.center,
      child: Text(
        _initial(widget.title),
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
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
  int? _loadedId;
  int? _loadedSlot;
  TdFileProgress? _progress;
  StreamSubscription<TdFileProgress>? _progressSub;

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
    _progressSub?.cancel();
    super.dispose();
  }

  void _load() {
    final ref = widget.photo;
    final slot = TdClient.shared.activeSlot;
    if (ref == null) {
      _loadedId = null;
      _loadedSlot = null;
      _progressSub?.cancel();
      _progressSub = null;
      if (_file != null || _progress != null) {
        setState(() {
          _file = null;
          _progress = null;
        });
      } else {
        _progress = null;
      }
      return;
    }
    if (_loadedId == ref.id &&
        _loadedSlot == slot &&
        oldProgressModeUnchanged()) {
      return;
    }
    _loadedId = ref.id;
    _loadedSlot = slot;
    _progress = null;
    _progressSub?.cancel();
    _progressSub = null;
    if (widget.showProgress) {
      _progressSub = TdFileCenter.shared.progress(ref.id).listen((progress) {
        if (!mounted || _loadedId != ref.id || _loadedSlot != slot) return;
        setState(() => _progress = progress);
      });
    }
    setState(() => _file = null);
    TdFileCenter.shared.path(ref.id).then((path) {
      if (!mounted || _loadedId != ref.id || _loadedSlot != slot) return;
      if (path != null) setState(() => _file = File(path));
    });
  }

  bool oldProgressModeUnchanged() {
    if (widget.showProgress) return _progressSub != null;
    return _progressSub == null;
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_file != null) {
      child = Image.file(
        _file!,
        fit: widget.fit,
        cacheWidth: widget.cacheWidth,
        cacheHeight: widget.cacheHeight,
        gaplessPlayback: true,
      );
    } else if (widget.photo?.miniThumb != null) {
      child = Image.memory(
        widget.photo!.miniThumb!,
        fit: widget.fit,
        cacheWidth: widget.cacheWidth,
        cacheHeight: widget.cacheHeight,
        gaplessPlayback: true,
      );
    } else {
      child = Container(color: context.colors.groupedBackground);
    }
    if (widget.showProgress && _file == null) {
      child = Stack(
        fit: StackFit.expand,
        children: [
          child,
          _MediaLoadingProgress(progress: _progress),
        ],
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.cornerRadius),
      child: child,
    );
  }
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
    return Center(
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
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
