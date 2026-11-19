import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../components/app_interactive_surface.dart';
import '../../l10n/app_localizations.dart';
import '../../tdlib/td_client.dart';
import '../../tdlib/td_models.dart';

/// Opening one item must not reveal other spoilers by gallery swipe or autoplay.
bool canPreviewMediaAlongside(ChatMessage candidate, ChatMessage selected) =>
    !candidate.hasSpoiler ||
    (candidate.id == selected.id && candidate.chatId == selected.chatId);

/// A preview-only reveal gate. Hidden media is never mounted, so native video
/// surfaces, autoplay and accessibility cannot expose it beneath the cover.
/// The parent must supply bounded dimensions (or [width] and [height]).
class MediaSpoiler extends StatefulWidget {
  const MediaSpoiler({
    super.key,
    required this.identity,
    required this.enabled,
    required this.child,
    this.miniThumbnail,
    this.width,
    this.height,
    this.borderRadius = BorderRadius.zero,
  });

  final Object identity;
  final bool enabled;
  final Widget child;
  final Uint8List? miniThumbnail;
  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  @override
  State<MediaSpoiler> createState() => _MediaSpoilerState();
}

class _MediaSpoilerState extends State<MediaSpoiler>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );
  bool _revealed = false;

  void _syncAnimation() {
    final animate =
        widget.enabled &&
        !_revealed &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (animate && !_animation.isAnimating) {
      _animation.repeat();
    } else if (!animate) {
      _animation.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(MediaSpoiler oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity ||
        oldWidget.enabled != widget.enabled) {
      _revealed = false;
    }
    _syncAnimation();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || _revealed) return widget.child;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: AppInteractiveSurface(
          semanticLabel: AppStringKeys.mediaSpoilerReveal.l10n(context),
          onTap: () {
            setState(() => _revealed = true);
            _syncAnimation();
          },
          child: RepaintBoundary(
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Color(0xFF9B9692)),
                if (widget.miniThumbnail case final bytes?
                    when bytes.isNotEmpty)
                  ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) => const SizedBox.expand(),
                    ),
                  ),
                const ColoredBox(color: Color(0x667B7672)),
                CustomPaint(painter: _SpoilerDust(_animation)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps reveal state local to this message, account and media revision.
class MessageMediaSpoiler extends StatelessWidget {
  const MessageMediaSpoiler({
    super.key,
    required this.message,
    required this.child,
    this.accountSlot,
    this.width,
    this.height,
    this.borderRadius = BorderRadius.zero,
  });

  final ChatMessage message;
  final Widget child;
  final int? accountSlot;
  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) => !message.hasSpoiler
      ? child
      : MediaSpoiler(
          identity: (
            accountSlot ?? TdClient.shared.activeSlot,
            message.chatId,
            message.id,
            message.image?.id,
            message.video?.id,
          ),
          enabled: message.hasSpoiler,
          miniThumbnail: message.image?.miniThumb ?? message.video?.miniThumb,
          width: width,
          height: height,
          borderRadius: borderRadius,
          child: child,
        );
}

class _SpoilerDust extends CustomPainter {
  _SpoilerDust(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(43);
    final count = (size.width * size.height / 90).round().clamp(24, 1800);
    final phase = animation.value * math.pi * 2;
    final paint = Paint();
    for (var i = 0; i < count; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final offset = random.nextDouble() * math.pi * 2;
      final radius = 0.6 + random.nextDouble() * 0.7;
      paint.color = const Color(
        0xFFFFFFFF,
      ).withValues(alpha: 0.25 + (math.sin(phase + offset) + 1) * 0.27);
      canvas.drawCircle(
        Offset(
          x + math.sin(phase + offset) * 2,
          y + math.cos(phase + offset) * 2,
        ),
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SpoilerDust oldDelegate) =>
      animation != oldDelegate.animation;
}
