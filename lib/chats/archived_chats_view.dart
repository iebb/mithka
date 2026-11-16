//
//  archived_chats_view.dart
//
//  Telegram archived chats folded behind the group assistant entry.
//

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:mithka/l10n/app_localizations.dart';

import '../app/app_navigator.dart';
import '../app/ipad_window_chrome.dart';
import '../chat/chat_view.dart';
import '../components/app_confirm_dialog.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/desktop_row_actions.dart';
import '../components/ui_components.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'chat_list_view.dart' show ChatListSelectionHighlight;
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
    this.onToggleMute,
    this.onBack,
    this.onChatSelected,
    this.selectedChatId,
  });

  final Listenable updates;
  final List<ChatSummary> Function() chatsProvider;
  final ValueChanged<ChatSummary>? onClearUnread;
  final ValueChanged<ChatSummary>? onUnarchive;
  final ValueChanged<ChatSummary>? onToggleMute;
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

/// The archived list, with the same long-press edit mode exteraless gives its
/// archive folder (a DialogsActivity with folderId=1 runs the identical action
/// mode): a body long press selects, the header becomes a command bar, and
/// every command maps onto the archive's own row actions.
class ArchivedChatsView extends StatefulWidget {
  const ArchivedChatsView({
    super.key,
    required this.chats,
    this.onClearUnread,
    this.onUnarchive,
    this.onToggleMute,
    this.onBack,
    this.onChatSelected,
    this.selectedChatId,
  });
  final List<ChatSummary> chats;
  final ValueChanged<ChatSummary>? onClearUnread;
  final ValueChanged<ChatSummary>? onUnarchive;
  final ValueChanged<ChatSummary>? onToggleMute;
  final VoidCallback? onBack;
  final ValueChanged<ChatSummary>? onChatSelected;
  final int? selectedChatId;

  @override
  State<ArchivedChatsView> createState() => _ArchivedChatsViewState();
}

class _ArchivedChatsViewState extends State<ArchivedChatsView> {
  final Set<int> _selectedChatIds = {};

  bool get _selectionMode => _selectedChatIds.isNotEmpty;

  List<ChatSummary> get _selectedChats =>
      widget.chats.where((chat) => _selectedChatIds.contains(chat.id)).toList();

  void _beginSelection(ChatSummary chat) {
    unawaited(HapticFeedback.mediumImpact());
    setState(() => _selectedChatIds.add(chat.id));
  }

  void _exitSelection() {
    setState(_selectedChatIds.clear);
  }

  void _toggleSelected(ChatSummary chat) => setState(() {
    if (!_selectedChatIds.add(chat.id)) _selectedChatIds.remove(chat.id);
  });

  void _runOverSelection(void Function(ChatSummary chat) action) {
    final chats = _selectedChats;
    _exitSelection();
    for (final chat in chats) {
      action(chat);
    }
  }

  Future<void> _deleteSelection() async {
    final count = _selectedChats.length;
    if (count == 0) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: AppStringKeys.chatListDeleteChatQuestion,
      message: AppStrings.t(AppStringKeys.chatListSelectedCountValue1, {
        'value1': '$count',
      }),
      confirmText: AppStringKeys.chatDelete.l10n(context),
      destructive: true,
    );
    if (!confirmed) return;
    // exteraless's archive delete only clears the archive's own rows; the
    // host owns the actual removal, and clearing read state is not it.
    final onUnarchive = widget.onUnarchive;
    _runOverSelection((chat) => onUnarchive?.call(chat));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final selectionMode = _selectionMode;
    return PopScope(
      canPop: !selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitSelection();
      },
      child: Scaffold(
        backgroundColor: c.background,
        body: Column(
          children: [
            if (selectionMode) _selectionHeader(context) else _normalHeader(),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: widget.chats.length,
                itemBuilder: (context, i) {
                  final chat = widget.chats[i];
                  return _ArchivedChatSwipeRow(
                    key: ValueKey(chat.id),
                    chat: chat,
                    selected: chat.id == widget.selectedChatId,
                    selectionTint: _selectedChatIds.contains(chat.id),
                    onTap: () => selectionMode
                        ? _toggleSelected(chat)
                        : _openChat(context, chat),
                    onLongPress: () => selectionMode
                        ? _toggleSelected(chat)
                        : _beginSelection(chat),
                    onClearUnread: () => widget.onClearUnread?.call(chat),
                    onUnarchive: widget.onUnarchive == null
                        ? null
                        : () => widget.onUnarchive!(chat),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _normalHeader() => NavHeader(
    title: AppStrings.t(AppStringKeys.archivedChatsGroupAssistant),
    onBack: widget.onBack ?? () => Navigator.of(context).pop(),
  );

  /// Same command bar as the main list's edit mode, trimmed to the archive's
  /// own actions: unarchive replaces pin (an archive row cannot pin), mute
  /// and delete stay, read moves to the overflow column.
  Widget _selectionHeader(BuildContext context) {
    final c = context.colors;
    final chats = _selectedChats;
    final allMuted = chats.isNotEmpty && chats.every((chat) => chat.isMuted);
    Widget command({
      required Key key,
      required String label,
      required AppIconData icon,
      required VoidCallback onTap,
      bool destructive = false,
    }) => AppInteractiveSurface(
      key: key,
      semanticLabel: label,
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: AppIcon(
          icon,
          size: AppIconSize.lg,
          color: destructive ? AppTheme.tagRed : c.textPrimary,
        ),
      ),
    );
    return Container(
      key: const ValueKey('chat-list-selection-header'),
      color: c.listHeaderTint,
      padding: headerChromePaddingOf(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            AppInteractiveSurface(
              key: const ValueKey('chat-list-close-selection'),
              semanticLabel: AppStringKeys.countryPickerCancel.l10n(context),
              onTap: _exitSelection,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: AppIcon(
                  HeroAppIcons.xmark,
                  size: AppIconSize.lg,
                  color: c.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                '${_selectedChatIds.length}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppTextSize.bodyLarge,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            command(
              key: const ValueKey('chat-list-selection-unarchive'),
              label: AppStrings.t(AppStringKeys.chatListUnarchive),
              icon: HeroAppIcons.inbox,
              onTap: () =>
                  _runOverSelection((chat) => widget.onUnarchive?.call(chat)),
            ),
            command(
              key: const ValueKey('chat-list-selection-mute'),
              label: AppStrings.t(
                allMuted ? AppStringKeys.chatUnmute : AppStringKeys.callMute,
              ),
              icon: allMuted ? HeroAppIcons.bell : HeroAppIcons.bellSlash,
              onTap: () =>
                  _runOverSelection((chat) => widget.onToggleMute?.call(chat)),
            ),
            command(
              key: const ValueKey('chat-list-selection-delete'),
              label: AppStrings.t(AppStringKeys.chatDelete),
              icon: HeroAppIcons.trash,
              destructive: true,
              onTap: () => unawaited(_deleteSelection()),
            ),
          ],
        ),
      ),
    );
  }

  void _openChat(BuildContext context, ChatSummary chat) {
    final selectionHandler = widget.onChatSelected;
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
    this.onLongPress,
    this.selectionTint = false,
  });

  final ChatSummary chat;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClearUnread;
  final VoidCallback? onUnarchive;
  final VoidCallback? onLongPress;

  /// Edit-mode membership tint, drawn over the row like the main list.
  final bool selectionTint;

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
    final tintedRow = widget.selectionTint
        ? ChatListSelectionHighlight(selected: true, child: row)
        : row;
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
          onLongPress: widget.onLongPress,
          child: tintedRow,
        ),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _offset == 0 ? widget.onTap : () => setState(() => _offset = 0),
      onLongPress: widget.selectionTint || _offset == 0
          ? widget.onLongPress
          : null,
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
              child: ColoredBox(
                color: context.colors.background,
                child: tintedRow,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
