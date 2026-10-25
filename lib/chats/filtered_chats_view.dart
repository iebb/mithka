import 'package:flutter/material.dart';

import '../app/app_navigator.dart';
import '../chat/chat_view.dart';
import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'chat_row_view.dart';

const filteredChatsTitle = 'Filtered Chats';

class FilteredChatsRow extends StatelessWidget {
  const FilteredChatsRow({super.key, required this.chats, this.onClearUnread});

  final List<ChatSummary> chats;
  final VoidCallback? onClearUnread;

  ChatSummary? get _latest => chats.isEmpty ? null : chats.first;
  int get _totalUnread =>
      chats.fold(0, (total, chat) => total + chat.unreadCount);

  ChatSummary get summary => ChatSummary(
    id: 0,
    title: filteredChatsTitle,
    lastSender: _latest?.title,
    lastMessage: _latest?.lastMessage ?? '',
    lastMessageId: _latest?.lastMessageId ?? 0,
    date: _latest?.date ?? 0,
    unreadCount: _totalUnread,
    order: 0,
    isMuted: true,
  );

  @override
  Widget build(BuildContext context) => ChatRowView(
    archived: true,
    onClearUnread: onClearUnread,
    chat: summary,
    avatarBuilder: (size) => Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFF6E8DB7),
        shape: BoxShape.circle,
      ),
      child: const AppIcon(HeroAppIcons.filter, size: 22, color: Colors.white),
    ),
  );
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
                    AppChatPageRoute(
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
