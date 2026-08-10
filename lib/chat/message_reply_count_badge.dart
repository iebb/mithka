import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Compact reply metadata for ordinary group messages.
///
/// Channel posts use the full-width comments attachment instead. Keeping the
/// group form small avoids presenting normal replies as channel comments.
class MessageReplyCountBadge extends StatelessWidget {
  const MessageReplyCountBadge({
    super.key,
    required this.count,
    required this.foreground,
    required this.background,
    this.onTap,
  });

  final int count;
  final Color foreground;
  final Color background;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(HeroAppIcons.reply, size: 12, color: foreground),
          const SizedBox(width: 3),
          Text(
            '$count',
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              color: foreground,
              fontSize: 11,
              height: 1.1,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: onTap != null,
      label: '${AppStrings.t(AppStringKeys.messageActionReplies)}: $count',
      excludeSemantics: true,
      child: onTap == null
          ? badge
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: badge,
            ),
    );
  }
}
