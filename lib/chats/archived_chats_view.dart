//
//  archived_chats_view.dart
//
//  Telegram archived chats folded behind the group assistant entry.
//

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../app/app_navigator.dart';
import '../chat/chat_view.dart';
import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'chat_row_view.dart';

class ArchivedChatsRow extends StatelessWidget {
  const ArchivedChatsRow({
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
    final latest = _latest;
    final title = AppStrings.t(AppStringKeys.archivedChatsGroupAssistant);
    final summary = ChatSummary(
      id: 0,
      title: title,
      lastMessage: latest?.lastMessage ?? '',
      lastMessageId: latest?.lastMessageId ?? 0,
      date: latest?.date ?? 0,
      unreadCount: _totalUnread,
      order: latest?.order ?? 0,
      isMuted: true,
      lastSender: latest?.title,
    );
    return ChatRowView(
      chat: summary,
      archived: true,
      onClearUnread: onClearUnread,
      avatarBuilder: (size) => Container(
        key: const ValueKey('archived-chats-avatar'),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Color(0xFFFF9D2E),
          shape: BoxShape.circle,
        ),
        child: AppIcon(
          HeroAppIcons.solidMessage,
          size: size * 0.46,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// [ArchivedChatsView] kept in step with the chat list model.
///
/// The view itself renders the list it is handed, which suits the split layout
/// because that pane rebuilds whenever its owner does. A pushed route has no
/// such owner: clearing a row's badge updates the model, but the route kept
/// rendering the snapshot it was built with, so the counter only disappeared
/// when the screen was reopened.
class LiveArchivedChatsView extends StatelessWidget {
  const LiveArchivedChatsView({
    super.key,
    required this.updates,
    required this.chatsProvider,
    this.onClearUnread,
    this.onBack,
    this.onChatSelected,
    this.selectedChatId,
  });

  final Listenable updates;
  final List<ChatSummary> Function() chatsProvider;
  final ValueChanged<ChatSummary>? onClearUnread;
  final VoidCallback? onBack;
  final ValueChanged<ChatSummary>? onChatSelected;
  final int? selectedChatId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: updates,
      builder: (context, _) => ArchivedChatsView(
        chats: chatsProvider(),
        onClearUnread: onClearUnread,
        onBack: onBack,
        onChatSelected: onChatSelected,
        selectedChatId: selectedChatId,
      ),
    );
  }
}

class ArchivedChatsView extends StatelessWidget {
  const ArchivedChatsView({
    super.key,
    required this.chats,
    this.onClearUnread,
    this.onBack,
    this.onChatSelected,
    this.selectedChatId,
  });
  final List<ChatSummary> chats;
  final ValueChanged<ChatSummary>? onClearUnread;
  final VoidCallback? onBack;
  final ValueChanged<ChatSummary>? onChatSelected;
  final int? selectedChatId;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.archivedChatsGroupAssistant),
            onBack: onBack ?? () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: chats.length,
              itemBuilder: (context, i) {
                final chat = chats[i];
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openChat(context, chat),
                  child: ChatRowView(
                    chat: chat,
                    archived: true,
                    selected: chat.id == selectedChatId,
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

  void _openChat(BuildContext context, ChatSummary chat) {
    final selectionHandler = onChatSelected;
    if (selectionHandler != null) {
      selectionHandler(chat);
      return;
    }
    pushAppChatRoute(
      context,
      AppChatPageRoute(
        builder: (_) => ChatView(chatId: chat.id, title: chat.title),
      ),
    );
  }
}
