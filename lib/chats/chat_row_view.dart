//
//  chat_row_view.dart
//
//  Reusable chat-list row: avatar with the unread count badged on its top-right
//  corner; title + preview; and a right column holding the timestamp (top) and
//  the mute bell at the row's bottom-right. Port of the Swift `ChatRowView`.
//

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../chat/custom_emoji.dart';
import '../components/photo_avatar.dart';
import '../components/sf_symbols.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import '../theme/theme_controller.dart';
import '../tdlib/td_models.dart';

const List<Color> _telegramAccentColors = [
  Color(0xFFCC5049),
  Color(0xFFD67722),
  Color(0xFF955CDB),
  Color(0xFF40A920),
  Color(0xFF309EBA),
  Color(0xFF368AD1),
  Color(0xFFC7508B),
];

class ChatRowView extends StatelessWidget {
  const ChatRowView({super.key, required this.chat});
  final ChatSummary chat;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    final rowHeight = theme.rowHeight;
    final premiumNameColor = theme.showPremiumNameColors && chat.peerIsPremium
        ? _accentColor(chat.peerAccentColorId)
        : c.textPrimary;
    final showPremiumStatus =
        theme.showPremiumEmojiStatus &&
        chat.peerIsPremium &&
        chat.peerEmojiStatusId != 0;
    return Container(
      height: rowHeight,
      color: chat.isPinned ? c.pinnedRow : c.background,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Row(
        children: [
          _avatar(context),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        chat.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppTextSize.body,
                          fontWeight: chat.peerIsPremium
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: premiumNameColor,
                        ),
                      ),
                    ),
                    if (showPremiumStatus) ...[
                      const SizedBox(width: AppSpacing.xs),
                      CustomEmojiView(
                        id: chat.peerEmojiStatusId,
                        size: 17,
                        color: premiumNameColor,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                chat.draftText.trim().isNotEmpty
                    ? ChatPreviewText(message: chat.draftText, draft: true)
                    : ChatPreviewText(
                        sender: chat.lastSender,
                        message: chat.lastMessage,
                      ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          _rightColumn(context),
        ],
      ),
    );
  }

  Color _accentColor(int id) {
    if (id >= 0 && id < _telegramAccentColors.length) {
      return _telegramAccentColors[id];
    }
    return AppTheme.brand;
  }

  Widget _avatar(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final circleGroups = theme.circularGroupAvatars;
    final avatarSize = theme.avatarSize;
    return SizedBox(
      width: avatarSize,
      height: avatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          PhotoAvatar(
            title: chat.title,
            photo: chat.photo,
            size: avatarSize,
            square: chat.usesSquareAvatar && !circleGroups,
          ),
          if (chat.unreadCount > 0)
            Positioned(
              right: -AppSpacing.sm,
              top: -(AppSpacing.xs + 1),
              child: UnreadBadge(count: chat.unreadCount, muted: chat.isMuted),
            )
          else if (chat.isMarkedUnread)
            Positioned(
              right: -AppSpacing.xxs,
              top: -AppSpacing.xxs,
              child: Container(
                padding: const EdgeInsets.all(AppMetric.badgeOutlinePadding),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const RedDot(size: AppMetric.unreadDot),
              ),
            ),
        ],
      ),
    );
  }

  Widget _rightColumn(BuildContext context) {
    final c = context.colors;
    final rowHeight = context.watch<ThemeController>().rowHeight;
    return SizedBox(
      height: rowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.lg + AppSpacing.xxs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              DateText.listLabel(chat.date),
              style: TextStyle(
                fontSize: AppTextSize.caption,
                color: c.textTertiary,
              ),
            ),
            const Spacer(),
            if (chat.isMuted)
              Icon(
                sfIcon('bell.slash.fill'),
                size: AppIconSize.sm,
                color: c.textTertiary,
              )
            else if (chat.isPinned)
              Transform.rotate(
                angle: 0.785, // 45°
                child: Icon(
                  sfIcon('pin.fill'),
                  size: AppIconSize.xs,
                  color: c.textTertiary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
