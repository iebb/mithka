//
//  message_card_footer.dart
//
//  The strip under a card that replaces a message bubble (gift, Gram
//  transfer): it names the card, with an optional glyph, and holds the
//  message's delivery mark at its trailing end.
//

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../theme/app_theme.dart';

class MessageCardFooter extends StatelessWidget {
  const MessageCardFooter({
    super.key,
    required this.label,
    required this.scale,
    this.glyph,
    this.meta,
  });

  /// The footer's height at text scale 1; it grows with [scale] up to [maxScale].
  static const double height = 24;

  /// Keeps the footer label and glyph fitting inside a width-capped card at the
  /// largest accessibility text sizes.
  static const double maxScale = 1.6;

  final String label;

  /// The card's text scale, never below 1.
  final double scale;
  final AppIconData? glyph;

  /// The message's delivery tick or edited mark; null when it shows none.
  final Widget? meta;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final glyph = this.glyph;
    final footerScale = scale < maxScale ? scale : maxScale;
    final textScaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: maxScale);
    return ColoredBox(
      color: c.card,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height * footerScale),
        child: Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.md,
          ),
          child: Row(
            children: [
              if (glyph != null) ...[
                AppIcon(
                  glyph,
                  size: textScaler.scale(AppIconSize.sm),
                  color: c.textSecondary,
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textScaler: textScaler,
                  style: AppTextStyle.caption(c.textSecondary),
                ),
              ),
              ?meta,
            ],
          ),
        ),
      ),
    );
  }
}
