import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../components/sf_symbols.dart';
import '../theme/app_theme.dart';

enum _EditTool { crop, mask, draw, text }

enum _CropDrag { none, move, topLeft, topRight, bottomLeft, bottomRight }

class ImageEditResult {
  const ImageEditResult({required this.path, this.caption = ''});

  final String path;
  final String caption;
}

class ImageEditView extends StatefulWidget {
  const ImageEditView({
    super.key,
    required this.sourcePath,
    this.avatar = false,
  });

  final String sourcePath;
  final bool avatar;

  @override
  State<ImageEditView> createState() => _ImageEditViewState();
}

class _ImageEditViewState extends State<ImageEditView> {
  Uint8List? _bytes;
  ui.Image? _image;
  Rect? _crop;
  Rect? _imageRect;
  _EditTool _tool = _EditTool.crop;
  _CropDrag _drag = _CropDrag.none;
  Offset? _lastImagePoint;
  final List<_Stroke> _strokes = [];
  final List<_TextLabel> _labels = [];
  final _captionController = TextEditingController();
  _Stroke? _activeStroke;
  double _drawSize = 8;
  double _maskSize = 34;
  bool _saving = false;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = await File(widget.sourcePath).readAsBytes();
    final image = await decodeImageFromList(bytes);
    final crop = _defaultCrop(image);
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _image = image;
      _crop = crop;
    });
  }

  Rect _defaultCrop(ui.Image image) {
    final full = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    if (!widget.avatar) return full;
    final side = math.min(full.width, full.height);
    return Rect.fromLTWH(
      (full.width - side) / 2,
      (full.height - side) / 2,
      side,
      side,
    );
  }

  Rect _fitRect(Size box) {
    final image = _image;
    if (image == null) return Rect.zero;
    final iw = image.width.toDouble();
    final ih = image.height.toDouble();
    final scale = math.min(box.width / iw, box.height / ih);
    final w = iw * scale;
    final h = ih * scale;
    return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  Offset? _toImagePoint(Offset local) {
    final rect = _imageRect;
    final image = _image;
    if (rect == null || image == null || !rect.contains(local)) return null;
    return Offset(
      ((local.dx - rect.left) / rect.width) * image.width,
      ((local.dy - rect.top) / rect.height) * image.height,
    );
  }

  Offset _toScreenPoint(Offset point) {
    final rect = _imageRect!;
    final image = _image!;
    return Offset(
      rect.left + point.dx / image.width * rect.width,
      rect.top + point.dy / image.height * rect.height,
    );
  }

  Rect _toScreenRect(Rect rect) {
    final a = _toScreenPoint(rect.topLeft);
    final b = _toScreenPoint(rect.bottomRight);
    return Rect.fromPoints(a, b);
  }

  void _onPanStart(DragStartDetails details) {
    final point = _toImagePoint(details.localPosition);
    if (point == null) return;
    _lastImagePoint = point;
    if (_tool == _EditTool.crop) {
      _drag = _hitCrop(details.localPosition);
      return;
    }
    if (_tool == _EditTool.text) {
      _addText(point);
      return;
    }
    final rect = _imageRect;
    final image = _image;
    final imageScale = rect == null || image == null
        ? 1.0
        : image.width / rect.width;
    _activeStroke = _Stroke(
      tool: _tool,
      color: _tool == _EditTool.mask ? Colors.black : AppTheme.tagRed,
      width: (_tool == _EditTool.mask ? _maskSize : _drawSize) * imageScale,
      points: [point],
    );
    setState(() => _strokes.add(_activeStroke!));
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final point = _toImagePoint(details.localPosition);
    if (point == null) return;
    final last = _lastImagePoint;
    _lastImagePoint = point;

    if (_tool == _EditTool.crop) {
      if (last == null || _drag == _CropDrag.none) return;
      _updateCrop(point - last);
      return;
    }

    final active = _activeStroke;
    if (active == null) return;
    setState(() => active.points.add(point));
  }

  void _onPanEnd(DragEndDetails details) {
    _drag = _CropDrag.none;
    _lastImagePoint = null;
    _activeStroke = null;
  }

  _CropDrag _hitCrop(Offset local) {
    final crop = _crop;
    if (crop == null || _imageRect == null) return _CropDrag.none;
    final screen = _toScreenRect(crop);
    const hit = 28.0;
    if ((local - screen.topLeft).distance <= hit) return _CropDrag.topLeft;
    if ((local - screen.topRight).distance <= hit) return _CropDrag.topRight;
    if ((local - screen.bottomLeft).distance <= hit) {
      return _CropDrag.bottomLeft;
    }
    if ((local - screen.bottomRight).distance <= hit) {
      return _CropDrag.bottomRight;
    }
    return screen.contains(local) ? _CropDrag.move : _CropDrag.none;
  }

  void _updateCrop(Offset delta) {
    final image = _image;
    final crop = _crop;
    if (image == null || crop == null) return;
    final bounds = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    const minSide = 90.0;
    var next = crop;
    switch (_drag) {
      case _CropDrag.move:
        next = crop.shift(delta);
        next = next.shift(
          Offset(
            next.left < bounds.left
                ? bounds.left - next.left
                : next.right > bounds.right
                ? bounds.right - next.right
                : 0,
            next.top < bounds.top
                ? bounds.top - next.top
                : next.bottom > bounds.bottom
                ? bounds.bottom - next.bottom
                : 0,
          ),
        );
      case _CropDrag.topLeft:
        next = Rect.fromLTRB(
          crop.left + delta.dx,
          crop.top + delta.dy,
          crop.right,
          crop.bottom,
        );
      case _CropDrag.topRight:
        next = Rect.fromLTRB(
          crop.left,
          crop.top + delta.dy,
          crop.right + delta.dx,
          crop.bottom,
        );
      case _CropDrag.bottomLeft:
        next = Rect.fromLTRB(
          crop.left + delta.dx,
          crop.top,
          crop.right,
          crop.bottom + delta.dy,
        );
      case _CropDrag.bottomRight:
        next = Rect.fromLTRB(
          crop.left,
          crop.top,
          crop.right + delta.dx,
          crop.bottom + delta.dy,
        );
      case _CropDrag.none:
        return;
    }

    if (_drag != _CropDrag.move && widget.avatar) {
      final side = math.max(
        minSide,
        math.min(next.width.abs(), next.height.abs()),
      );
      next = switch (_drag) {
        _CropDrag.topLeft => Rect.fromLTRB(
          crop.right - side,
          crop.bottom - side,
          crop.right,
          crop.bottom,
        ),
        _CropDrag.topRight => Rect.fromLTRB(
          crop.left,
          crop.bottom - side,
          crop.left + side,
          crop.bottom,
        ),
        _CropDrag.bottomLeft => Rect.fromLTRB(
          crop.right - side,
          crop.top,
          crop.right,
          crop.top + side,
        ),
        _CropDrag.bottomRight => Rect.fromLTWH(crop.left, crop.top, side, side),
        _ => next,
      };
    }

    if (next.width < minSide || next.height < minSide) return;
    next = Rect.fromLTRB(
      next.left.clamp(bounds.left, bounds.right - minSide),
      next.top.clamp(bounds.top, bounds.bottom - minSide),
      next.right.clamp(bounds.left + minSide, bounds.right),
      next.bottom.clamp(bounds.top + minSide, bounds.bottom),
    );
    if (widget.avatar) {
      final side = math.min(next.width, next.height);
      next = Rect.fromLTWH(next.left, next.top, side, side);
      if (next.right > bounds.right) {
        next = next.shift(Offset(bounds.right - next.right, 0));
      }
      if (next.bottom > bounds.bottom) {
        next = next.shift(Offset(0, bounds.bottom - next.bottom));
      }
    }
    setState(() => _crop = next);
  }

  Future<void> _done() async {
    final image = _image;
    final crop = _crop;
    if (image == null || crop == null || _saving) return;
    setState(() => _saving = true);
    try {
      final outW = math.max(1, crop.width.round());
      final outH = math.max(1, crop.height.round());
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()..filterQuality = FilterQuality.high;
      final dest = Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble());
      canvas.drawImageRect(image, crop, dest, paint);
      canvas.save();
      canvas.translate(-crop.left, -crop.top);
      canvas.clipRect(crop);
      for (final stroke in _strokes) {
        _drawStroke(canvas, stroke);
      }
      for (final label in _labels) {
        _drawTextLabel(canvas, label);
      }
      canvas.restore();
      final picture = recorder.endRecording();
      final out = await picture.toImage(outW, outH);
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/mithka_edit_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(data.buffer.asUint8List());
      if (mounted) {
        if (widget.avatar) {
          Navigator.of(context).pop(file.path);
        } else {
          Navigator.of(context).pop(
            ImageEditResult(
              path: file.path,
              caption: _captionController.text.trim(),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _drawStroke(Canvas canvas, _Stroke stroke) {
    if (stroke.points.isEmpty) return;
    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    if (stroke.points.length == 1) {
      canvas.drawCircle(stroke.points.first, stroke.width / 2, paint);
      return;
    }
    final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
    for (final point in stroke.points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }

  void _drawTextLabel(Canvas canvas, _TextLabel label) {
    final painter = TextPainter(
      text: TextSpan(
        text: label.text,
        style: TextStyle(
          color: Colors.white,
          fontSize: label.size,
          fontWeight: FontWeight.w600,
          shadows: const [
            Shadow(color: Colors.black, blurRadius: 3, offset: Offset(0, 1)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 4,
    )..layout(maxWidth: 360);
    final bg = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        label.position.dx - 6,
        label.position.dy - 4,
        painter.width + 12,
        painter.height + 8,
      ),
      const Radius.circular(6),
    );
    canvas.drawRRect(bg, Paint()..color = Colors.black.withValues(alpha: 0.38));
    painter.paint(canvas, label.position);
  }

  void _undo() {
    if (_labels.isNotEmpty) {
      setState(() => _labels.removeLast());
      return;
    }
    if (_strokes.isNotEmpty) setState(() => _strokes.removeLast());
  }

  void _resetCrop() {
    final image = _image;
    if (image == null) return;
    setState(() => _crop = _defaultCrop(image));
  }

  Future<void> _rotateRight() async {
    final image = _image;
    if (image == null || _saving) return;
    setState(() => _saving = true);
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.translate(image.height.toDouble(), 0);
      canvas.rotate(math.pi / 2);
      canvas.drawImage(
        image,
        Offset.zero,
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final rotated = await picture.toImage(image.height, image.width);
      final data = await rotated.toByteData(format: ui.ImageByteFormat.png);
      if (data == null || !mounted) return;
      setState(() {
        _bytes = data.buffer.asUint8List();
        _image = rotated;
        _crop = _defaultCrop(rotated);
        _strokes.clear();
        _labels.clear();
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addText(Offset point) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('添加文字', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: '输入标注',
            hintStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || text == null || text.trim().isEmpty) return;
    final rect = _imageRect;
    final image = _image;
    final imageScale = rect == null || image == null
        ? 1.0
        : image.width / rect.width;
    setState(() {
      _labels.add(
        _TextLabel(text: text.trim(), position: point, size: 22 * imageScale),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(context),
            Expanded(
              child: bytes == null || _image == null
                  ? const Center(child: CircularProgressIndicator.adaptive())
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        _imageRect = _fitRect(
                          Size(constraints.maxWidth, constraints.maxHeight),
                        );
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: _onPanStart,
                          onPanUpdate: _onPanUpdate,
                          onPanEnd: _onPanEnd,
                          child: Stack(
                            children: [
                              Positioned.fromRect(
                                rect: _imageRect!,
                                child: Image.memory(bytes, fit: BoxFit.fill),
                              ),
                              CustomPaint(
                                size: Size.infinite,
                                painter: _ImageEditPainter(
                                  crop: _crop == null
                                      ? null
                                      : _toScreenRect(_crop!),
                                  strokes: _strokes,
                                  labels: _labels,
                                  toScreen: _toScreenPoint,
                                  avatar: widget.avatar,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            if (!widget.avatar) _captionField(context),
            _toolBar(context),
          ],
        ),
      ),
    );
  }

  Widget _captionField(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: TextField(
        controller: _captionController,
        minLines: 1,
        maxLines: 3,
        textInputAction: TextInputAction.newline,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: '添加说明…',
          hintStyle: const TextStyle(color: Colors.white54),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.08),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return SizedBox(
      height: 50,
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(sfIcon('xmark'), color: Colors.white),
          ),
          Text(
            widget.avatar ? '裁剪头像' : '编辑图片',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: '重置裁剪',
            onPressed: _resetCrop,
            icon: Icon(
              sfIcon('arrow.triangle.2.circlepath'),
              color: Colors.white,
            ),
          ),
          if (!widget.avatar)
            IconButton(
              tooltip: '旋转',
              onPressed: _saving ? null : _rotateRight,
              icon: Icon(
                sfIcon('rotate.right'),
                color: _saving ? Colors.white38 : Colors.white,
              ),
            ),
          TextButton(
            onPressed: _saving ? null : _done,
            child: Text(
              _saving ? '处理中…' : '完成',
              style: TextStyle(
                color: _saving ? Colors.white54 : AppTheme.brand,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _toolButton(_EditTool.crop, sfIcon('crop'), '裁剪'),
                if (!widget.avatar) ...[
                  _toolButton(_EditTool.mask, sfIcon('drop'), '遮挡'),
                  _toolButton(_EditTool.draw, sfIcon('pencil'), '画笔'),
                  _toolButton(_EditTool.text, sfIcon('textformat'), '文字'),
                ],
                const Spacer(),
                IconButton(
                  onPressed: _strokes.isEmpty && _labels.isEmpty ? null : _undo,
                  icon: Icon(
                    sfIcon('arrow.counterclockwise'),
                    color: _strokes.isEmpty && _labels.isEmpty
                        ? Colors.white30
                        : Colors.white,
                  ),
                ),
              ],
            ),
            if (_tool == _EditTool.mask || _tool == _EditTool.draw)
              _sizeSlider(),
          ],
        ),
      ),
    );
  }

  Widget _sizeSlider() {
    final isMask = _tool == _EditTool.mask;
    final value = isMask ? _maskSize : _drawSize;
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Icon(
            isMask ? sfIcon('drop') : sfIcon('pencil'),
            size: 16,
            color: Colors.white70,
          ),
          Expanded(
            child: Slider(
              value: value,
              min: isMask ? 18 : 3,
              max: isMask ? 72 : 24,
              activeColor: AppTheme.brand,
              onChanged: (next) => setState(() {
                if (isMask) {
                  _maskSize = next;
                } else {
                  _drawSize = next;
                }
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolButton(_EditTool tool, IconData icon, String label) {
    final active = _tool == tool;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _tool = tool),
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: active ? AppTheme.brand : Colors.white),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                color: active ? AppTheme.brand : Colors.white70,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageEditPainter extends CustomPainter {
  _ImageEditPainter({
    required this.crop,
    required this.strokes,
    required this.labels,
    required this.toScreen,
    required this.avatar,
  });

  final Rect? crop;
  final List<_Stroke> strokes;
  final List<_TextLabel> labels;
  final Offset Function(Offset) toScreen;
  final bool avatar;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }
    for (final label in labels) {
      _drawTextLabel(canvas, label);
    }
    final cropRect = crop;
    if (cropRect == null) return;
    final shade = Paint()..color = Colors.black.withValues(alpha: 0.45);
    final overlay = Path()..addRect(Offset.zero & size);
    if (avatar) {
      overlay.addOval(cropRect);
    } else {
      overlay.addRect(cropRect);
    }
    canvas.drawPath(overlay..fillType = PathFillType.evenOdd, shade);
    final border = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    if (avatar) {
      canvas.drawOval(cropRect, border);
    } else {
      canvas.drawRect(cropRect, border);
    }
    final handle = Paint()..color = Colors.white;
    for (final p in [
      cropRect.topLeft,
      cropRect.topRight,
      cropRect.bottomLeft,
      cropRect.bottomRight,
    ]) {
      canvas.drawCircle(p, 5, handle);
    }
  }

  void _drawTextLabel(Canvas canvas, _TextLabel label) {
    final p0 = label.position;
    final screenSize = (toScreen(p0 + Offset(label.size, 0)) - toScreen(p0))
        .distance
        .clamp(8.0, 44.0);
    final painter = TextPainter(
      text: TextSpan(
        text: label.text,
        style: TextStyle(
          color: Colors.white,
          fontSize: screenSize,
          fontWeight: FontWeight.w600,
          shadows: const [
            Shadow(color: Colors.black, blurRadius: 3, offset: Offset(0, 1)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 4,
    )..layout(maxWidth: 260);
    final point = toScreen(label.position);
    final bg = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        point.dx - 6,
        point.dy - 4,
        painter.width + 12,
        painter.height + 8,
      ),
      const Radius.circular(6),
    );
    canvas.drawRRect(bg, Paint()..color = Colors.black.withValues(alpha: 0.38));
    painter.paint(canvas, point);
  }

  void _drawStroke(Canvas canvas, _Stroke stroke) {
    if (stroke.points.isEmpty) return;
    final p0 = stroke.points.first;
    final screenWidth = (toScreen(p0 + Offset(stroke.width, 0)) - toScreen(p0))
        .distance
        .clamp(1.0, 80.0);
    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = screenWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final first = toScreen(stroke.points.first);
    if (stroke.points.length == 1) {
      canvas.drawCircle(first, paint.strokeWidth / 2, paint);
      return;
    }
    final path = Path()..moveTo(first.dx, first.dy);
    for (final point in stroke.points.skip(1)) {
      final screen = toScreen(point);
      path.lineTo(screen.dx, screen.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ImageEditPainter oldDelegate) {
    return true;
  }
}

class _Stroke {
  _Stroke({
    required this.tool,
    required this.color,
    required this.width,
    required this.points,
  });

  final _EditTool tool;
  final Color color;
  final double width;
  final List<Offset> points;
}

class _TextLabel {
  _TextLabel({required this.text, required this.position, required this.size});

  final String text;
  final Offset position;
  final double size;
}
