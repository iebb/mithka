import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

const _indicatorWhite = Color(0xFFFFFFFF);

/// The animated selection pill shared by every app glass bar: a rounded,
/// tinted highlight that slides to the selected slot.
class GlassSelectionIndicator extends StatelessWidget {
  const GlassSelectionIndicator({
    super.key,
    required this.selection,
    required this.itemCount,
  }) : assert(itemCount > 0),
       assert(selection >= 0 && selection < itemCount);

  final int selection;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dark = colors.navBar.computeLuminance() < 0.5;
    final highContrast = MediaQuery.highContrastOf(context);
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          AnimatedPositionedDirectional(
            duration: AppMotion.duration(context, AppMotion.deliberate),
            curve: AppMotion.emphasized,
            start: constraints.maxWidth * selection / itemCount,
            width: constraints.maxWidth / itemCount,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: DecoratedBox(
                key: const ValueKey('liquid-glass-selection'),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  color: colors.linkBlue.withValues(
                    alpha: highContrast ? 0.22 : (dark ? 0.19 : 0.10),
                  ),
                  border: Border.all(
                    color: highContrast
                        ? colors.linkBlue
                        : _indicatorWhite.withValues(alpha: dark ? 0.16 : 0.70),
                    width: 0.8,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The app's glass bottom bar. The shell overlays this transparent surface
/// above the scrollable content, with no opaque backing strip, on every
/// target: [BackdropFilter] blurs the app's own layer tree, so the capsule
/// refracts whatever actually scrolls behind it.
class LiquidGlassBottomBar extends StatelessWidget {
  const LiquidGlassBottomBar({
    super.key,
    required this.selection,
    required this.itemCount,
    required this.child,
  }) : assert(itemCount > 0),
       assert(selection >= 0 && selection < itemCount);

  final int selection;
  final int itemCount;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dark = colors.navBar.computeLuminance() < 0.5;
    final highContrast = MediaQuery.highContrastOf(context);
    const white = _indicatorWhite;
    const black = Color(0xFF000000);
    const radius = BorderRadius.all(Radius.circular(AppRadius.pill));
    final rim = white.withValues(alpha: dark ? 0.22 : 0.85);
    // A white capsule on a white page has no edge: the specular rim above
    // disappears into the background. A dark hairline drawn outside it gives
    // the stadium a silhouette on any surface while the rim keeps the lit top
    // edge. High contrast already relies on its solid fill and text border.
    final contour = black.withValues(alpha: dark ? 0.34 : 0.055);
    final tint = colors.navBar.withValues(alpha: dark ? 0.78 : 0.64);

    return SafeArea(
      key: const ValueKey('liquid-glass-bottom-bar'),
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: black.withValues(alpha: dark ? 0.24 : 0.09),
                blurRadius: 20,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: DecoratedBox(
            // Foreground so the contour sits on the capsule's outer edge
            // instead of being covered by the glass clipped inside it.
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: contour, width: 0.6),
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                enabled: !highContrast,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    color: highContrast ? colors.navBar : null,
                    gradient: highContrast
                        ? null
                        : LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color.alphaBlend(
                                white.withValues(alpha: dark ? 0.09 : 0.48),
                                tint,
                              ),
                              tint,
                              Color.alphaBlend(
                                colors.linkBlue.withValues(alpha: 0.045),
                                tint,
                              ),
                            ],
                            stops: const [0, 0.52, 1],
                          ),
                    border: Border.all(
                      color: highContrast ? colors.textSecondary : rim,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: GlassSelectionIndicator(
                            selection: selection,
                            itemCount: itemCount,
                          ),
                        ),
                        child,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
