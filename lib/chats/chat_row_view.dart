//
//  chat_row_view.dart
//
//  Reusable chat-list row: avatar with the unread count badged on its top-right
//  corner; title + preview; and a right column holding the timestamp (top) and
//  the mute bell at the row's bottom-right. Port of the Swift `ChatRowView`.
//

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/photo_avatar.dart';
import '../components/sf_symbols.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import '../theme/theme_controller.dart';
import '../tdlib/td_models.dart';

class ChatRowView extends StatelessWidget {
  const ChatRowView({super.key, required this.chat});
  final ChatSummary chat;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: AppTheme.rowHeight,
      color: chat.isPinned ? c.pinnedRow : c.background,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          _avatar(context),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chat.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                chat.draftText.trim().isNotEmpty
                    ? ChatPreviewText(message: chat.draftText, draft: true)
                    : ChatPreviewText(
                        sender: chat.lastSender,
                        message: chat.lastMessage,
                      ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _rightColumn(context),
        ],
      ),
    );
  }

  Widget _avatar(BuildContext context) {
    final circleGroups = context.watch<ThemeController>().circularGroupAvatars;
    return SizedBox(
      width: AppTheme.avatarSize,
      height: AppTheme.avatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          PhotoAvatar(
            title: chat.title,
            photo: chat.photo,
            size: AppTheme.avatarSize,
            square: chat.usesSquareAvatar && !circleGroups,
          ),
          if (chat.unreadCount > 0)
            Positioned(
              right: -6,
              top: -5,
              child: UnreadBadge(count: chat.unreadCount, muted: chat.isMuted),
            )
          else if (chat.isMarkedUnread)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.all(1.5),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const RedDot(size: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _rightColumn(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: AppTheme.rowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              DateText.listLabel(chat.date),
              style: TextStyle(fontSize: 12, color: c.textTertiary),
            ),
            const Spacer(),
            if (chat.isMuted)
              Icon(sfIcon('bell.slash.fill'), size: 13, color: c.textTertiary)
            else if (chat.isPinned)
              Transform.rotate(
                angle: 0.785, // 45°
                child: Icon(
                  sfIcon('pin.fill'),
                  size: 12,
                  color: c.textTertiary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
