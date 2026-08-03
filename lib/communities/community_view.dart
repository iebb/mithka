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
import '../theme/theme_controller.dart';
import 'community_models.dart';

enum _CommunityHeaderAction { toggleCollapsed }

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
    final summary = ChatSummary(
      id: -entry.community.id.abs(),
      title: entry.community.name,
      lastMessage: latest.lastMessage.trim().isEmpty
          ? AppStrings.t(AppStringKeys.communityChatCount, {
              'value1': entry.chats.length,
            })
          : latest.lastMessage,
      lastMessageId: latest.lastMessageId,
      date: latest.date,
      unreadCount: entry.unreadCount,
      order: latest.order,
      isMuted: entry.isMuted,
      lastSender: latest.lastSender,
      isPinned: entry.isPinned,
      isMarkedUnread: entry.isMarkedUnread,
    );
    return ChatRowView(
      chat: summary,
      selected: selected,
      onClearUnread: onClearUnread,
      avatarBuilder: (size) => _CommunityStackedAvatar(
        title: entry.community.name,
        photo: entry.community.photo,
        size: size,
        square: !theme.circularGroupAvatars,
      ),
      titleTrailing: AppIcon(
        HeroAppIcons.objectGroup,
        size: 14,
        color: c.textTertiary,
      ),
      trailingIndicator: AppIcon(
        HeroAppIcons.chevronRight,
        size: AppIconSize.sm,
        color: c.textTertiary,
      ),
    );
  }
}

class _CommunityStackedAvatar extends StatelessWidget {
  const _CommunityStackedAvatar({
    required this.title,
    required this.photo,
    required this.size,
    required this.square,
  });

  final String title;
  final TdFileRef? photo;
  final double size;
  final bool square;

  @override
  Widget build(BuildContext context) {
    final backColor = context.colors.textTertiary;
    final cornerRadius = square
        ? size * AppTheme.groupAvatarCornerRatio
        : size / 2;
    Widget plate(Key key, double opacity) => Container(
      key: key,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backColor.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(cornerRadius),
      ),
    );

    return SizedBox(
      key: const ValueKey('community-stacked-avatar'),
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -size * 0.18,
            top: size * 0.12,
            child: plate(const ValueKey('community-avatar-back-2'), 0.28),
          ),
          Positioned(
            left: -size * 0.09,
            top: size * 0.06,
            child: plate(const ValueKey('community-avatar-back-1'), 0.42),
          ),
          PhotoAvatar(
            key: const ValueKey('community-avatar-front'),
            title: title,
            photo: photo,
            size: size,
            square: square,
            allowAnimation: false,
          ),
        ],
      ),
    );
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
  late bool _collapsed = widget.community.collapsed;

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
    super.dispose();
  }

  void _handleUpdates() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final chats = _currentChats;
    final viewableChats = _currentViewableChats;
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
            trailing: _headerMenu(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 28),
              children: [
                _communityHeader(),
                const SizedBox(height: 14),
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

  Widget _headerMenu() => PopupMenuButton<_CommunityHeaderAction>(
    key: const ValueKey('community-header-menu'),
    tooltip: '',
    color: context.colors.background,
    padding: EdgeInsets.zero,
    onSelected: (_) => _setCollapsed(!_collapsed),
    itemBuilder: (context) => [
      PopupMenuItem<_CommunityHeaderAction>(
        value: _CommunityHeaderAction.toggleCollapsed,
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: _collapsed
                  ? AppIcon(
                      HeroAppIcons.check,
                      size: 16,
                      color: context.colors.linkBlue,
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Text(AppStringKeys.communityShowAsOneChat.l10n(context)),
          ],
        ),
      ),
    ],
    child: SizedBox(
      width: AppMetric.hitTarget,
      height: AppMetric.hitTarget,
      child: AppIcon(
        HeroAppIcons.ellipsis,
        size: AppIconSize.nav,
        color: context.colors.textPrimary,
      ),
    ),
  );

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
      key: const ValueKey('community-header'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          PhotoAvatar(
            title: widget.community.name,
            photo: widget.community.photo,
            size: 64,
            square: true,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.community.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.left,
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
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: AppTextSize.callout,
                    color: c.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _setCollapsed(bool value) {
    setState(() => _collapsed = value);
    widget.onCollapsedChanged(value);
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

  Future<void> _openChat(ChatSummary chat) async {
    final onChatSelected = widget.onChatSelected;
    if (onChatSelected != null) {
      onChatSelected(chat);
      return;
    }
    if (chat.supportsTopics) {
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
        AppChatPageRoute<void>(
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
