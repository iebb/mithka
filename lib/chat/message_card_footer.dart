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

  /// The footer's height at text scale 1; it grows with [scale].
  static const double height = 24;

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
    return ColoredBox(
      color: c.card,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height * scale),
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
                  size: MediaQuery.textScalerOf(context).scale(AppIconSize.sm),
                  color: c.textSecondary,
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
