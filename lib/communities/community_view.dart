//
//  community_view.dart
//
//  Telegram Communities browser based on the July 2026 iOS flow: a community
//  can occupy one chat-list row, opening a compact hub for its related chats.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_navigator.dart';
import '../channels/forum_topic_browser_view.dart';
import '../chat/chat_view.dart';
import '../chats/chat_row_view.dart';
import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../settings/topic_group_display_mode.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import '../theme/theme_controller.dart';
import 'community_models.dart';

class CommunityChatListRow extends StatelessWidget {
  const CommunityChatListRow({
    super.key,
    required this.entry,
    this.selected = false,
    this.onClearUnread,
  });

  final CommunityGroupEntry entry;
  final bool selected;
  final VoidCallback? onClearUnread;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    final latest = entry.latestChat;
    final preview = _preview(context, latest);
    return Container(
      height: theme.rowHeight,
      color: selected
          ? c.listHeaderTint
          : (entry.isPinned ? c.pinnedRow : c.background),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Row(
        children: [
          SizedBox(
            width: theme.avatarSize,
            height: theme.avatarSize,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                PhotoAvatar(
                  title: entry.community.name,
                  photo: entry.community.photo,
                  size: theme.avatarSize,
                  square: !theme.circularGroupAvatars,
                ),
                if (entry.unreadCount > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: UnreadBadge(
                      count: entry.unreadCount,
                      muted: entry.isMuted,
                      onClear: onClearUnread,
                    ),
                  )
                else if (entry.isMarkedUnread)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(
                        AppMetric.badgeOutlinePadding,
                      ),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: RedDot(
                        size: AppMetric.unreadDot,
                        muted: entry.isMuted,
                      ),
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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.community.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppTextSize.body,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    AppIcon(
                      HeroAppIcons.objectGroup,
                      size: 14,
                      color: c.textTertiary,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTextSize.callout,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          SizedBox(
            height: theme.rowHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.lg + AppSpacing.xxs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    DateText.listLabel(latest.date),
                    style: TextStyle(
                      fontSize: AppTextSize.caption,
                      color: c.textTertiary,
                    ),
                  ),
                  const Spacer(),
                  if (entry.isMuted)
                    AppIcon(
                      HeroAppIcons.bellSlash,
                      size: AppIconSize.sm,
                      color: c.textTertiary,
                    )
                  else
                    AppIcon(
                      HeroAppIcons.chevronRight,
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

  String _preview(BuildContext context, ChatSummary latest) {
    final message = latest.lastMessage.trim();
    final sender = latest.lastSender?.trim();
    final body = [
      if (sender != null && sender.isNotEmpty) sender,
      if (message.isNotEmpty) message,
    ].join(': ');
    if (body.isEmpty) {
      return AppStrings.t(AppStringKeys.communityChatCount, {
        'value1': entry.chats.length,
      });
    }
    return '${latest.title}: $body';
  }
}

class CommunityView extends StatefulWidget {
  const CommunityView({
    super.key,
    required this.community,
    required this.chats,
    this.viewableChats = const [],
    this.updates,
    this.chatsProvider,
    this.viewableChatsProvider,
    required this.onCollapsedChanged,
    this.onChatSelected,
    this.showBackButton = true,
    this.onBack,
  });

  final CommunitySummary community;
  final List<ChatSummary> chats;
  final List<ChatSummary> viewableChats;
  final Listenable? updates;
  final List<ChatSummary> Function()? chatsProvider;
  final List<ChatSummary> Function()? viewableChatsProvider;
  final ValueChanged<bool> onCollapsedChanged;
  final ValueChanged<ChatSummary>? onChatSelected;
  final bool showBackButton;
  final VoidCallback? onBack;

  @override
  State<CommunityView> createState() => _CommunityViewState();
}

class _CommunityViewState extends State<CommunityView> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  late bool _collapsed = widget.community.collapsed;
  bool _searching = false;
  String _query = '';

  List<ChatSummary> get _currentChats =>
      widget.chatsProvider?.call() ?? widget.chats;
  List<ChatSummary> get _currentViewableChats =>
      widget.viewableChatsProvider?.call() ?? widget.viewableChats;

  @override
  void initState() {
    super.initState();
    widget.updates?.addListener(_handleUpdates);
  }

  @override
  void didUpdateWidget(covariant CommunityView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.community.collapsed != widget.community.collapsed) {
      _collapsed = widget.community.collapsed;
    }
    if (oldWidget.updates != widget.updates) {
      oldWidget.updates?.removeListener(_handleUpdates);
      widget.updates?.addListener(_handleUpdates);
    }
  }

  @override
  void dispose() {
    widget.updates?.removeListener(_handleUpdates);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _handleUpdates() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final query = _query.trim().toLowerCase();
    final chats = _filtered(_currentChats, query);
    final viewableChats = _filtered(_currentViewableChats, query);
    final hasResults = chats.isNotEmpty || viewableChats.isNotEmpty;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.communityTitle,
            onBack: widget.showBackButton
                ? widget.onBack ?? () => Navigator.of(context).pop()
                : null,
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleSearch,
              child: SizedBox(
                width: AppMetric.hitTarget,
                height: AppMetric.hitTarget,
                child: AppIcon(
                  _searching
                      ? HeroAppIcons.xmark
                      : HeroAppIcons.magnifyingGlass,
                  size: AppIconSize.nav - 2,
                  color: c.textPrimary,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 28),
              children: [
                _communityHeader(),
                if (_searching) ...[const SizedBox(height: 12), _searchField()],
                const SizedBox(height: 14),
                _collapseCard(),
                const SizedBox(height: 20),
                if (!hasResults)
                  _chatCard(const [])
                else ...[
                  if (chats.isNotEmpty) ...[
                    _sectionHeader(AppStringKeys.communityChatsYouAreIn),
                    const SizedBox(height: 8),
                    _chatCard(chats),
                  ],
                  if (chats.isNotEmpty && viewableChats.isNotEmpty)
                    const SizedBox(height: 20),
                  if (viewableChats.isNotEmpty) ...[
                    _sectionHeader(AppStringKeys.communityChatsYouCanView),
                    const SizedBox(height: 8),
                    _chatCard(viewableChats),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<ChatSummary> _filtered(List<ChatSummary> chats, String query) {
    if (query.isEmpty) return chats;
    return chats
        .where(
          (chat) =>
              chat.title.toLowerCase().contains(query) ||
              chat.lastMessage.toLowerCase().contains(query),
        )
        .toList();
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Text(
      title.l10n(context),
      style: TextStyle(
        fontSize: AppTextSize.caption,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: context.colors.textTertiary,
      ),
    ),
  );

  Widget _communityHeader() {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          PhotoAvatar(
            title: widget.community.name,
            photo: widget.community.photo,
            size: 76,
            square: true,
          ),
          const SizedBox(height: 12),
          Text(
            widget.community.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppTextSize.title,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            AppStrings.t(AppStringKeys.communityChatCount, {
              'value1': {
                ..._currentChats.map((chat) => chat.id),
                ..._currentViewableChats.map((chat) => chat.id),
              }.length,
            }),
            style: TextStyle(
              fontSize: AppTextSize.callout,
              color: c.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    final c = context.colors;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.searchFill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          AppIcon(
            HeroAppIcons.magnifyingGlass,
            size: 16,
            color: c.textTertiary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: EditableText(
              controller: _searchController,
              focusNode: _searchFocus,
              style: TextStyle(fontSize: 15, color: c.textPrimary),
              cursorColor: c.linkBlue,
              backgroundCursorColor: c.textTertiary,
              textInputAction: TextInputAction.search,
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
        ],
      ),
    );
  }

  Widget _collapseCard() {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStringKeys.communityShowAsOneChat.l10n(context),
                  style: TextStyle(
                    fontSize: AppTextSize.body,
                    fontWeight: FontWeight.w500,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  AppStringKeys.communityShowAsOneChatDescription.l10n(context),
                  style: TextStyle(
                    fontSize: AppTextSize.caption,
                    height: 1.3,
                    color: c.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          AppSwitch(
            value: _collapsed,
            onChanged: (value) {
              setState(() => _collapsed = value);
              widget.onCollapsedChanged(value);
            },
          ),
        ],
      ),
    );
  }

  Widget _chatCard(List<ChatSummary> chats) {
    final c = context.colors;
    if (chats.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 38),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            AppIcon(HeroAppIcons.objectGroup, size: 30, color: c.textTertiary),
            const SizedBox(height: 10),
            Text(
              AppStringKeys.communityNoChats.l10n(context),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppTextSize.callout,
                color: c.textTertiary,
              ),
            ),
          ],
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ColoredBox(
        color: c.card,
        child: Column(
          children: [
            for (var i = 0; i < chats.length; i++) ...[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openChat(chats[i]),
                child: ChatRowView(chat: chats[i]),
              ),
              if (i != chats.length - 1) const InsetDivider(leadingInset: 72),
            ],
          ],
        ),
      ),
    );
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _query = '';
        _searchController.clear();
        _searchFocus.unfocus();
      }
    });
    if (_searching) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
  }

  Future<void> _openChat(ChatSummary chat) async {
    final onChatSelected = widget.onChatSelected;
    if (onChatSelected != null) {
      onChatSelected(chat);
      return;
    }
    if (chat.isForum) {
      final mode = await TopicGroupDisplayPreference.load();
      if (!mounted) return;
      if (!mode.isChat) {
        unawaited(
          pushAppChatRoute(
            context,
            MaterialPageRoute(
              builder: (_) => ForumTopicBrowserView(
                chats: [..._currentChats, ..._currentViewableChats],
                initialChat: chat,
              ),
            ),
          ),
        );
        return;
      }
    }
    if (!mounted) return;
    unawaited(
      pushAppChatRoute(
        context,
        MaterialPageRoute(
          builder: (_) => ChatView(
            chatId: chat.id,
            title: chat.title,
            seedMessage: chat.lastChatMessage,
          ),
        ),
      ),
    );
  }
}
