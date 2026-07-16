import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_navigator.dart';
import '../chat/chat_view.dart';
import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import '../theme/theme_controller.dart';
import 'chat_row_view.dart';

const filteredChatsTitle = 'Filtered Chats';

class FilteredChatsRow extends StatelessWidget {
  const FilteredChatsRow({super.key, required this.chats, this.onClearUnread});

  final List<ChatSummary> chats;
  final VoidCallback? onClearUnread;

  ChatSummary? get _latest => chats.isEmpty ? null : chats.first;
  int get _totalUnread =>
      chats.fold(0, (total, chat) => total + chat.unreadCount);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    final rowHeight = theme.rowHeight;
    final avatarSize = theme.avatarSize;
    return Container(
      height: rowHeight,
      color: c.background,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Row(
        children: [
          SizedBox(
            width: avatarSize,
            height: avatarSize,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: avatarSize,
                  height: avatarSize,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFF6E8DB7),
                    shape: BoxShape.circle,
                  ),
                  child: AppIcon(
                    HeroAppIcons.filter,
                    size: theme.scaled(22),
                    color: Colors.white,
                  ),
                ),
                if (_totalUnread > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: UnreadBadge(
                      count: _totalUnread,
                      muted: true,
                      onClear: onClearUnread,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  filteredChatsTitle,
                  style: TextStyle(
                    fontSize: AppTextSize.bodyLarge,
                    fontWeight: FontWeight.w500,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                ChatPreviewText(
                  sender: _latest?.title,
                  message: _latest?.lastMessage ?? '',
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          SizedBox(
            height: rowHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.lg + AppSpacing.xxs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    DateText.listLabel(_latest?.date ?? 0),
                    style: TextStyle(
                      fontSize: AppTextSize.caption,
                      color: c.textTertiary,
                    ),
                  ),
                  const Spacer(),
                  AppIcon(
                    HeroAppIcons.bellSlash,
                    size: AppIconSize.sm,
                    color: c.textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FilteredChatsView extends StatelessWidget {
  const FilteredChatsView({super.key, required this.chats, this.onClearUnread});

  final List<ChatSummary> chats;
  final ValueChanged<ChatSummary>? onClearUnread;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          NavHeader(
            title: filteredChatsTitle,
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: chats.length,
              itemBuilder: (context, index) {
                final chat = chats[index];
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => pushAppChatRoute(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ChatView(chatId: chat.id, title: chat.title),
                    ),
                  ),
                  child: ChatRowView(
                    chat: chat,
                    archived: true,
                    onClearUnread: () => onClearUnread?.call(chat),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
