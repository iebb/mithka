import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

/// Immediately swaps heavy detail content while keeping every transition
/// frame fully painted.
///
/// The arriving child always occupies the complete pane. A short, low-opacity
/// tint using the active chat background provides the entrance cue without
/// translating or fading the child itself, so list/detail boundaries cannot
/// expose an ancestor canvas during chat switches.
class DetailContentReveal extends StatefulWidget {
  const DetailContentReveal({
    super.key,
    required this.motionKey,
    required this.child,
  });

  @visibleForTesting
  static const surfaceKey = ValueKey('detail-content-reveal-surface');

  @visibleForTesting
  static const transitionTintKey = ValueKey(
    'detail-content-reveal-transition-tint',
  );

  final Key motionKey;
  final Widget child;

  @override
  State<DetailContentReveal> createState() => _DetailContentRevealState();
}

class _DetailContentRevealState extends State<DetailContentReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.deliberate,
    value: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = AppMotion.duration(context, AppMotion.deliberate);
    if (AppMotion.isReduced(context)) _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant DetailContentReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.motionKey == widget.motionKey) return;
    _controller.duration = AppMotion.duration(context, AppMotion.deliberate);
    if (_controller.duration == Duration.zero) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final background = context.colors.chatBackground;
    return ColoredBox(
      key: DetailContentReveal.surfaceKey,
      color: background,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          child: KeyedSubtree(key: widget.motionKey, child: widget.child),
          builder: (context, child) {
            final progress = AppMotion.standard.transform(_controller.value);
            final tintOpacity = 0.08 * (1 - progress);
            return Stack(
              fit: StackFit.expand,
              children: [
                child!,
                if (tintOpacity > 0)
                  IgnorePointer(
                    child: ColoredBox(
                      key: DetailContentReveal.transitionTintKey,
                      color: background.withValues(alpha: tintOpacity),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
