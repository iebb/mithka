//
//  archived_chats_view.dart
//
//  Telegram archived chats folded behind the group assistant entry.
//

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../app/app_navigator.dart';
import '../chat/chat_view.dart';
import '../components/app_icons.dart';
import '../components/desktop_row_actions.dart';
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

  ChatSummary get summary {
    final latest = _latest;
    final title = AppStrings.t(AppStringKeys.archivedChatsGroupAssistant);
    return ChatSummary(
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
  }

  @override
  Widget build(BuildContext context) {
    final summary = this.summary;
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
        child: const AppIcon(
          HeroAppIcons.solidMessage,
          size: 48 * 0.46,
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
    this.onUnarchive,
    this.onBack,
    this.onChatSelected,
    this.selectedChatId,
  });

  final Listenable updates;
  final List<ChatSummary> Function() chatsProvider;
  final ValueChanged<ChatSummary>? onClearUnread;
  final ValueChanged<ChatSummary>? onUnarchive;
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
        onUnarchive: onUnarchive,
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
    this.onUnarchive,
    this.onBack,
    this.onChatSelected,
    this.selectedChatId,
  });
  final List<ChatSummary> chats;
  final ValueChanged<ChatSummary>? onClearUnread;
  final ValueChanged<ChatSummary>? onUnarchive;
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
                return _ArchivedChatSwipeRow(
                  key: ValueKey(chat.id),
                  chat: chat,
                  selected: chat.id == selectedChatId,
                  onTap: () => _openChat(context, chat),
                  onClearUnread: () => onClearUnread?.call(chat),
                  onUnarchive: onUnarchive == null
                      ? null
                      : () => onUnarchive!(chat),
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

class _ArchivedChatSwipeRow extends StatefulWidget {
  const _ArchivedChatSwipeRow({
    super.key,
    required this.chat,
    required this.selected,
    required this.onTap,
    required this.onClearUnread,
    this.onUnarchive,
  });

  final ChatSummary chat;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClearUnread;
  final VoidCallback? onUnarchive;

  @override
  State<_ArchivedChatSwipeRow> createState() => _ArchivedChatSwipeRowState();
}

class _ArchivedChatSwipeRowState extends State<_ArchivedChatSwipeRow> {
  static const _actionWidth = 92.0;
  double _offset = 0;

  @override
  Widget build(BuildContext context) {
    final action = widget.onUnarchive;
    final row = ChatRowView(
      chat: widget.chat,
      archived: true,
      selected: widget.selected,
      onClearUnread: widget.onClearUnread,
    );
    // Match the main list: macOS uses secondary-click commands, never a
    // horizontal swipe tray (including trackpad drags).
    if (!kIsWeb && Theme.of(context).platform == TargetPlatform.macOS) {
      return DesktopRowActionRegion(
        actions: [
          if (action != null)
            DesktopRowAction(
              id: 'unarchive',
              label: AppStringKeys.chatListUnarchive,
              icon: HeroAppIcons.inbox,
              onInvoke: action,
            ),
          if (widget.chat.unreadCount > 0 || widget.chat.isMarkedUnread)
            DesktopRowAction(
              id: 'mark-read',
              label: AppStringKeys.channelDirectMessagesMarkRead,
              icon: HeroAppIcons.circleCheck,
              onInvoke: widget.onClearUnread,
            ),
        ],
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: row,
        ),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _offset == 0 ? widget.onTap : () => setState(() => _offset = 0),
      onHorizontalDragUpdate: action == null
          ? null
          : (details) => setState(() {
              _offset = (_offset + details.delta.dx).clamp(-_actionWidth, 0);
            }),
      onHorizontalDragEnd: action == null
          ? null
          : (_) => setState(
              () => _offset = _offset <= -_actionWidth / 2 ? -_actionWidth : 0,
            ),
      child: ClipRect(
        child: Stack(
          alignment: Alignment.centerRight,
          children: [
            if (action != null && _offset != 0)
              Positioned(
                key: const ValueKey('archived-chat-unarchive'),
                top: 0,
                bottom: 0,
                right: 0,
                width: _actionWidth,
                child: ColoredBox(
                  color: AppTheme.brand,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      action();
                      setState(() => _offset = 0);
                    },
                    child: const Center(
                      child: AppIcon(
                        HeroAppIcons.inbox,
                        size: 22,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            Transform.translate(
              offset: Offset(_offset, 0),
              child: ColoredBox(color: context.colors.background, child: row),
            ),
          ],
        ),
      ),
    );
  }
}
