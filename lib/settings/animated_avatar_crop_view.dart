import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:video_player/video_player.dart';

import '../components/app_icons.dart';
import '../platform/animated_avatar_preparer.dart';
import '../theme/app_theme.dart';

class AnimatedAvatarCropView extends StatefulWidget {
  const AnimatedAvatarCropView({super.key, required this.source});

  final XFile source;

  @override
  State<AnimatedAvatarCropView> createState() => _AnimatedAvatarCropViewState();
}

class _AnimatedAvatarCropViewState extends State<AnimatedAvatarCropView> {
  VideoPlayerController? _video;
  Size? _sourceSize;
  Object? _loadError;
  double _scale = 1;
  double _startScale = 1;
  Offset _offset = Offset.zero;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;
  double _viewportSide = 1;

  bool get _isVideo {
    final mimeType = widget.source.mimeType?.toLowerCase();
    if (mimeType?.startsWith('video/') ?? false) return true;
    final path = widget.source.path.toLowerCase();
    return path.endsWith('.mp4') ||
        path.endsWith('.mov') ||
        path.endsWith('.m4v');
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      if (_isVideo) {
        final controller = VideoPlayerController.file(File(widget.source.path));
        await controller.initialize();
        await controller.setLooping(true);
        await controller.setVolume(0);
        await controller.play();
        if (!mounted) {
          await controller.dispose();
          return;
        }
        setState(() {
          _video = controller;
          _sourceSize = controller.value.size;
        });
        return;
      }
      final bytes = await File(widget.source.path).readAsBytes();
      final image = await decodeImageFromList(bytes);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _sourceSize = Size(image.width.toDouble(), image.height.toDouble());
      });
      image.dispose();
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  Size _baseDisplaySize(double side) {
    final source = _sourceSize!;
    final factor = math.max(side / source.width, side / source.height);
    return Size(source.width * factor, source.height * factor);
  }

  Offset _clampOffset(Offset value, double scale, double side) {
    final base = _baseDisplaySize(side);
    final maxX = math.max(0.0, (base.width * scale - side) / 2);
    final maxY = math.max(0.0, (base.height * scale - side) / 2);
    return Offset(value.dx.clamp(-maxX, maxX), value.dy.clamp(-maxY, maxY));
  }

  void _onScaleStart(ScaleStartDetails details) {
    _startScale = _scale;
    _startOffset = _offset;
    _startFocal = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final nextScale = (_startScale * details.scale).clamp(1.0, 5.0);
    final focalDelta = details.localFocalPoint - _startFocal;
    setState(() {
      _scale = nextScale;
      _offset = _clampOffset(
        _startOffset + focalDelta,
        nextScale,
        _viewportSide,
      );
    });
  }

  void _done() {
    final source = _sourceSize;
    if (source == null) return;
    final base = _baseDisplaySize(_viewportSide);
    final displayedWidth = base.width * _scale;
    final displayedHeight = base.height * _scale;
    final left =
        ((displayedWidth - _viewportSide) / 2 - _offset.dx) / displayedWidth;
    final top =
        ((displayedHeight - _viewportSide) / 2 - _offset.dy) / displayedHeight;
    Navigator.of(context).pop(
      AnimatedAvatarCrop(
        left: left.clamp(0.0, 1.0),
        top: top.clamp(0.0, 1.0),
        width: (_viewportSide / displayedWidth).clamp(0.0, 1.0),
        height: (_viewportSide / displayedHeight).clamp(0.0, 1.0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final side = math.min(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  _viewportSide = math.max(1, side);
                  return Center(
                    child: SizedBox.square(
                      dimension: side,
                      child: _cropViewport(side),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              child: Text(
                AppStrings.t(AppStringKeys.imageEditCropAvatar),
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: AppIcon(HeroAppIcons.xmark, color: Colors.white),
            ),
          ),
          Text(
            AppStrings.t(AppStringKeys.imageEditCropAvatar),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _sourceSize == null ? null : _done,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Text(
                AppStrings.t(AppStringKeys.addMembersDone),
                style: TextStyle(
                  color: _sourceSize == null ? Colors.white38 : AppTheme.brand,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cropViewport(double side) {
    if (_loadError != null) {
      return Center(
        child: Text(
          _loadError.toString(),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }
    if (_sourceSize == null) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator.adaptive(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(Colors.white),
          ),
        ),
      );
    }
    final base = _baseDisplaySize(side);
    return ClipRect(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Transform.translate(
                offset: _offset,
                child: Transform.scale(
                  scale: _scale,
                  child: SizedBox(
                    width: base.width,
                    height: base.height,
                    child: _preview(),
                  ),
                ),
              ),
            ),
            IgnorePointer(
              child: CustomPaint(painter: _AvatarCropOverlayPainter()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview() {
    final controller = _video;
    if (controller != null) return VideoPlayer(controller);
    return Image.file(
      File(widget.source.path),
      fit: BoxFit.fill,
      gaplessPlayback: true,
      filterQuality: FilterQuality.high,
    );
  }
}

class _AvatarCropOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final circle = Rect.fromCircle(
      center: bounds.center,
      radius: math.min(size.width, size.height) / 2 - 2,
    );
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(bounds)
      ..addOval(circle);
    canvas.drawPath(outside, Paint()..color = Colors.black54);
    canvas.drawOval(
      circle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white70,
    );
    final grid = Paint()
      ..strokeWidth = 0.6
      ..color = Colors.white24;
    canvas.drawLine(
      Offset(size.width / 3, 0),
      Offset(size.width / 3, size.height),
      grid,
    );
    canvas.drawLine(
      Offset(size.width * 2 / 3, 0),
      Offset(size.width * 2 / 3, size.height),
      grid,
    );
    canvas.drawLine(
      Offset(0, size.height / 3),
      Offset(size.width, size.height / 3),
      grid,
    );
    canvas.drawLine(
      Offset(0, size.height * 2 / 3),
      Offset(size.width, size.height * 2 / 3),
      grid,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
