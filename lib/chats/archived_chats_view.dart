//
//  archived_chats_view.dart
//
//  The reference "群助手": Telegram Archive chats folded behind a single entry.
//  GroupAssistantRow is the collapsed row shown in the 消息 list; tapping it
//  pushes ArchivedChatsView. Port of the Swift `ArchivedChatsView`.
//

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../chat/chat_view.dart';
import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import '../theme/theme_controller.dart';
import 'chat_row_view.dart';

/// Collapsed "群助手" entry summarizing archived chats.
class GroupAssistantRow extends StatelessWidget {
  const GroupAssistantRow({
    super.key,
    required this.archived,
    this.onClearUnread,
  });
  final List<ChatSummary> archived;
  final VoidCallback? onClearUnread;

  ChatSummary? get _latest => archived.isEmpty ? null : archived.first;
  int get _totalUnread => archived.fold(0, (a, c) => a + c.unreadCount);
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
                    color: Color(0xFFFF9D2E),
                    shape: BoxShape.circle,
                  ),
                  child: AppIcon(
                    HeroAppIcons.solidMessage,
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
                  AppStrings.t(AppStringKeys.archivedChatsGroupAssistant),
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
          Padding(
            padding: const EdgeInsets.only(top: 13),
            child: Text(
              DateText.listLabel(_latest?.date ?? 0),
              style: TextStyle(
                fontSize: AppTextSize.caption,
                color: c.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ArchivedChatsView extends StatelessWidget {
  const ArchivedChatsView({super.key, required this.chats, this.onClearUnread});
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
            title: AppStrings.t(AppStringKeys.archivedChatsGroupAssistant),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: chats.length,
              itemBuilder: (context, i) {
                final chat = chats[i];
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).push(
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
