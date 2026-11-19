part of 'message_bubble.dart';

class _RichDetailsBlock extends StatefulWidget {
  const _RichDetailsBlock({
    required this.initiallyOpen,
    required this.color,
    required this.header,
    required this.child,
  });

  final bool initiallyOpen;
  final Color color;
  final Widget header;
  final Widget child;

  @override
  State<_RichDetailsBlock> createState() => _RichDetailsBlockState();
}

class _RichDetailsBlockState extends State<_RichDetailsBlock> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: widget.color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Expanded(child: widget.header),
                  const SizedBox(width: 8),
                  AppIcon(
                    _open
                        ? HeroAppIcons.chevronDown
                        : HeroAppIcons.chevronRight,
                    size: 16,
                    color: widget.color,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 9),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}

/// Static map preview for a location message. Telegram renders the map tile via
/// getMapThumbnailFile (no marker); we overlay a centre pin.
class _MapThumbnail extends StatefulWidget {
  const _MapThumbnail({
    required this.latitude,
    required this.longitude,
    this.zoom = 16,
    this.height = 120,
  });
  final double latitude;
  final double longitude;
  final int zoom;
  final double height;

  @override
  State<_MapThumbnail> createState() => _MapThumbnailState();
}

class _MapThumbnailState extends State<_MapThumbnail> {
  TdFileRef? _ref;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await TdClient.shared.query({
        '@type': 'getMapThumbnailFile',
        'location': {
          '@type': 'location',
          'latitude': widget.latitude,
          'longitude': widget.longitude,
        },
        'zoom': widget.zoom.clamp(1, 20),
        'width': 220,
        'height': widget.height.round().clamp(40, 1024),
        'scale': 2,
        'chat_id': 0,
      });
      final id = res.integer('id');
      if (mounted && id != null) setState(() => _ref = TdFileRef(id: id));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_ref != null)
            TDImage(photo: _ref, cornerRadius: 0)
          else
            Container(color: c.groupedBackground),
          Center(
            child: AppIcon(
              HeroAppIcons.locationPin,
              size: 32,
              color: AppTheme.brand,
            ),
          ),
        ],
      ),
    );
  }
}

class _LatexView extends StatelessWidget {
  const _LatexView({
    required this.expression,
    required this.style,
    this.display = false,
  });

  final String expression;
  final TextStyle style;
  final bool display;

  @override
  Widget build(BuildContext context) {
    try {
      return Math.tex(
        expression,
        textStyle: style,
        mathStyle: display ? MathStyle.display : MathStyle.text,
        onErrorFallback: (error) => Text(expression, style: style),
      );
    } catch (_) {
      return Text(expression, style: style);
    }
  }
}

/// The settled tick: no controller, no ticker. Only the in-flight spinner needs
/// an animation, and every outgoing bubble used to mount one to draw a circle.
class _MessageDeliverySettled extends StatelessWidget {
  const _MessageDeliverySettled({
    required this.isRead,
    required this.color,
    required this.size,
  });

  final bool isRead;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    key: ValueKey(isRead ? 'messageDeliveryRead' : 'messageDeliverySent'),
    dimension: size,
    child: CustomPaint(
      painter: _MessageDeliveryPainter(isSending: false, color: color),
    ),
  );
}

class _MessageDeliveryIndicator extends StatefulWidget {
  const _MessageDeliveryIndicator({
    required this.pendingColor,
    required this.size,
  });

  final Color pendingColor;
  final double size;

  @override
  State<_MessageDeliveryIndicator> createState() =>
      _MessageDeliveryIndicatorState();
}

class _MessageDeliveryIndicatorState extends State<_MessageDeliveryIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    key: const ValueKey('messageDeliverySending'),
    dimension: widget.size,
    // Its own layer: the painter repaints on every tick, and without a
    // boundary that re-records the whole outgoing bubble at 60fps for the
    // entire send.
    child: RepaintBoundary(
      child: CustomPaint(
        painter: _MessageDeliveryPainter(
          rotation: _controller,
          isSending: true,
          color: widget.pendingColor.withValues(alpha: 0.72),
        ),
      ),
    ),
  );
}

class _MessageDeliveryPainter extends CustomPainter {
  _MessageDeliveryPainter({
    Animation<double>? rotation,
    required this.isSending,
    required this.color,
  }) : _rotation = rotation,
       super(repaint: rotation);

  final Animation<double>? _rotation;
  final bool isSending;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = math.max(1.25, size.shortestSide * 0.16);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: radius,
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    if (isSending) {
      canvas.drawArc(
        rect,
        (_rotation?.value ?? 0.0) * math.pi * 2 - math.pi / 2,
        math.pi * 1.35,
        false,
        paint,
      );
    } else {
      canvas.drawCircle(size.center(Offset.zero), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_MessageDeliveryPainter oldDelegate) =>
      oldDelegate.isSending != isSending || oldDelegate.color != color;
}

/// Folds a rich quote body to [maxHeight]. The child is laid out with an
/// unbounded height at the incoming width, so the fold follows the real layout
/// instead of a character count or an intrinsic pass, and while [collapsed] it
/// paints clipped to the cap with a short bottom fade. The measurement is
/// reported after the frame — through [onOverflowChanged] — so the caller only
/// builds an affordance when there is something to fold.
class _QuoteFold extends SingleChildRenderObjectWidget {
  const _QuoteFold({
    required this.maxHeight,
    required this.collapsed,
    required this.fadeExtent,
    required this.onOverflowChanged,
    super.child,
  });

  final double maxHeight;
  final bool collapsed;
  final double fadeExtent;
  final ValueChanged<bool> onOverflowChanged;

  @override
  _RenderQuoteFold createRenderObject(BuildContext context) => _RenderQuoteFold(
    maxHeight: maxHeight,
    collapsed: collapsed,
    fadeExtent: fadeExtent,
    onOverflowChanged: onOverflowChanged,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderQuoteFold renderObject) {
    renderObject
      ..maxHeight = maxHeight
      ..collapsed = collapsed
      ..fadeExtent = fadeExtent
      ..onOverflowChanged = onOverflowChanged;
  }
}

class _RenderQuoteFold extends RenderProxyBox {
  _RenderQuoteFold({
    required this._maxHeight,
    required this._collapsed,
    required this._fadeExtent,
    required this._onOverflowChanged,
  });

  double get maxHeight => _maxHeight;
  double _maxHeight;
  set maxHeight(double value) {
    if (value == _maxHeight) return;
    _maxHeight = value;
    markNeedsLayout();
  }

  bool get collapsed => _collapsed;
  bool _collapsed;
  set collapsed(bool value) {
    if (value == _collapsed) return;
    _collapsed = value;
    markNeedsLayout();
  }

  double get fadeExtent => _fadeExtent;
  double _fadeExtent;
  set fadeExtent(double value) {
    if (value == _fadeExtent) return;
    _fadeExtent = value;
    markNeedsPaint();
  }

  set onOverflowChanged(ValueChanged<bool> value) {
    if (value == _onOverflowChanged) return;
    _onOverflowChanged = value;
  }

  ValueChanged<bool> _onOverflowChanged;
  bool _overflows = false;
  bool _reportedOverflow = false;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(
      BoxConstraints(
        minWidth: constraints.minWidth,
        maxWidth: constraints.maxWidth,
      ),
      parentUsesSize: true,
    );
    final bodyHeight = child.size.height;
    _overflows = bodyHeight > _maxHeight + precisionErrorTolerance;
    size = constraints.constrain(
      Size(
        child.size.width,
        _overflows && _collapsed ? _maxHeight : bodyHeight,
      ),
    );
    if (_overflows != _reportedOverflow) {
      _reportedOverflow = _overflows;
      final report = _onOverflowChanged;
      // The caller rebuilds to add or drop the affordance, and a layout-time
      // setState is illegal: the report lands right after this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (attached) report(_overflows);
      });
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (!_overflows || !_collapsed) {
      context.paintChild(child, offset);
      return;
    }
    context.pushClipRect(needsCompositing, offset, Offset.zero & size, (
      PaintingContext context,
      Offset clippedOffset,
    ) {
      final fadeTop = math.max(0.0, size.height - _fadeExtent);
      if (fadeTop <= 0) {
        context.paintChild(child, clippedOffset);
        return;
      }
      final bounds = clippedOffset & size;
      final canvas = context.canvas;
      canvas.saveLayer(bounds, Paint());
      context.paintChild(child, clippedOffset);
      // Alpha-only fade: the body thins out towards the cut without assuming
      // which fill sits behind the quote.
      canvas.drawRect(
        bounds,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = ui.Gradient.linear(
            Offset(bounds.left, bounds.top + fadeTop),
            Offset(bounds.left, bounds.bottom),
            const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
          ),
      );
      canvas.restore();
    });
  }
}
