import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_press_ripple.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'custom_emoji.dart';

/// The reaction buckets under a message bubble or media album.
class MessageReactionChips extends StatelessWidget {
  const MessageReactionChips({
    super.key,
    required this.message,
    required this.outgoing,
    this.onToggle,
    this.onShowUsers,
  });

  final ChatMessage message;
  final bool outgoing;
  final ValueChanged<MessageReaction>? onToggle;
  final void Function(ChatMessage message, MessageReaction reaction)?
  onShowUsers;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      alignment: outgoing ? WrapAlignment.end : WrapAlignment.start,
      children: [for (final r in message.reactions) _chip(c, r)],
    );
  }

  /// The emoji toggles the reaction; the count is a separate target that opens
  /// the reactors sheet, so a multi-reaction chip no longer hides that list
  /// behind an undiscoverable long press.
  Widget _chip(AppColors c, MessageReaction r) {
    final foreground = r.chosen ? AppTheme.brand : c.textSecondary;
    return GestureDetector(
      key: ValueKey('reactionChip-${message.id}-${_reactionKey(r)}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => onToggle?.call(r),
      onLongPress: () => onShowUsers?.call(message, r),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: r.chosen
              ? AppTheme.brand.withValues(alpha: 0.18)
              : c.searchFill,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: r.chosen ? Border.all(color: AppTheme.brand) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            r.customEmojiId != 0
                ? CustomEmojiView(
                    id: r.customEmojiId,
                    size: 16,
                    color: foreground,
                  )
                : Text(r.emoji ?? '', style: const TextStyle(fontSize: 14)),
            if (r.count > 1) _countTarget(r, foreground),
          ],
        ),
      ),
    );
  }

  Widget _countTarget(MessageReaction r, Color color) {
    final count = Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text('${r.count}', style: TextStyle(fontSize: 12, color: color)),
    );
    final onShow = onShowUsers;
    // Without a list callback the count stays plain text, so the whole chip
    // keeps toggling the reaction exactly as before.
    if (onShow == null) return count;
    return Semantics(
      key: ValueKey('reactionCount-${message.id}-${_reactionKey(r)}'),
      button: true,
      label: AppStrings.t(AppStringKeys.chatReactionUsersCount, {
        'value1': r.count,
      }),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onShow(message, r),
        child: AppPressRipple(
          borderRadius: BorderRadius.circular(AppRadius.control),
          color: color,
          child: count,
        ),
      ),
    );
  }

  static String _reactionKey(MessageReaction reaction) =>
      reaction.customEmojiId != 0
      ? 'custom:${reaction.customEmojiId}'
      : 'emoji:${reaction.emoji ?? ''}';
}
