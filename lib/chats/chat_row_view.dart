//
//  chat_row_view.dart
//
//  Reusable chat-list row: avatar with the unread count badged on its top-right
//  corner and an optional marker on its bottom-right one; the title with the
//  timestamp on its trailing edge, sharing the name's baseline; the preview;
//  and the mute bell at the row's bottom-right. Port of the Swift `ChatRowView`.
//

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../chat/custom_emoji.dart';
import '../chat/group_remark_controller.dart';
import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../platform/adaptive_platform.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/content_size.dart';
import '../theme/date_text.dart';
import '../theme/theme_controller.dart';
import 'chat_folder_tag_controller.dart';
import 'chat_row_metrics.dart';

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
  const ChatRowView({
    super.key,
    required this.chat,
    this.archived = false,
    this.selected = false,
    this.onClearUnread,
    this.avatarBuilder,
    this.avatarBadge,
    this.titleTrailing,
    this.trailingIndicator,
    this.pinned,
  });
  final ChatSummary chat;
  final bool archived;
  final bool selected;
  final VoidCallback? onClearUnread;
  final Widget Function(double size)? avatarBuilder;

  /// Marker pinned to the avatar's bottom-right corner. It lives inside the
  /// avatar box, so its own gesture wins over the row's.
  final Widget? avatarBadge;
  final Widget? titleTrailing;
  final Widget? trailingIndicator;

  /// Pin state for the list this row is rendered in. Null keeps the Main
  /// list's [ChatSummary.isPinned]; a folder projection passes its own value
  /// so the two lists never share one flag.
  final bool? pinned;
  bool get _pinned => pinned ?? chat.isPinned;

  @override
  Widget build(BuildContext context) => ContentSizeScope(
    child: LayoutBuilder(
      builder: (context, constraints) => ChatRowWidth(
        width: constraints.maxWidth,
        child: Builder(builder: _buildContent),
      ),
    ),
  );

  Widget _buildContent(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    final showSavedMessagesIdentity =
        chat.isSavedMessages && theme.showSavedMessagesIdentity;
    final title = showSavedMessagesIdentity
        ? AppStrings.t(AppStringKeys.savedMessages)
        : chat.kind == ChatKind.group
        ? context.watch<GroupRemarkController?>()?.displayTitleFor(
                chat.id,
                chat.title,
              ) ??
              chat.title
        : chat.title;
    final folderTags =
        context.watch<ChatFolderTagController?>()?.tagsFor(chat.folderIds) ??
        const <ChatFolderTag>[];
    final metrics = chatRowMetricsFor(
      context,
      chat,
      pinned: _pinned,
      trailingWidth: trailingIndicator != null && !isDesktopTargetPlatform()
          ? 13
          : 0,
      titleAccessoryWidth:
          (titleTrailing != null ? 22 : 0) +
          (chat.peerEmojiStatusId != 0 && theme.chatListStatusEmojiMode.visible
              ? 21
              : 0) +
          (chat.kind == ChatKind.secret ? 18 : 0),
    );
    final rowHeight = metrics.extent;
    final avatarSize = metrics.avatar;
    final titleFontSize = AppTextSize.chatListTitle();
    final previewFontSize = AppTextSize.chatListPreview();
    final timestampFontSize = AppTextSize.chatListTimestamp();
    final nameColor =
        !showSavedMessagesIdentity &&
            theme.chatListNameColorAudience.shows(
              isPremium: chat.peerIsPremium,
            ) &&
            chat.peerAccentColorId >= 0
        ? _accentColor(chat.peerAccentColorId)
        : c.textPrimary;
    final showStatus =
        !showSavedMessagesIdentity &&
        theme.chatListStatusEmojiMode.visible &&
        chat.peerEmojiStatusId != 0;
    return Container(
      height: rowHeight,
      color: selected
          ? c.listHeaderTint
          : (_pinned ? c.pinnedRow : c.background),
      padding: EdgeInsets.symmetric(
        horizontal: AppMetric.chatRowHorizontalInset(),
      ),
      child: Row(
        children: [
          _avatar(
            context,
            title,
            avatarSize,
            showSavedMessagesIdentity: showSavedMessagesIdentity,
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            // Name and time share one baseline-aligned line; the indicators
            // keep the bottom trailing corner beside the preview.
            child: ChatRowTextColumn(
              title: Row(
                children: [
                  if (chat.kind == ChatKind.secret) ...[
                    IgnoreBaseline(
                      child: AppIcon(
                        HeroAppIcons.lock,
                        size: 14,
                        color: c.textSecondary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: titleFontSize,
                        fontWeight:
                            chat.peerIsPremium && !showSavedMessagesIdentity
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: nameColor,
                      ),
                    ),
                  ),
                  if (titleTrailing case final trailing?) ...[
                    const SizedBox(width: AppSpacing.sm),
                    IgnoreBaseline(child: trailing),
                  ],
                  if (showStatus) ...[
                    const SizedBox(width: AppSpacing.xs),
                    IgnoreBaseline(
                      child: StatusEmojiView(
                        id: chat.peerEmojiStatusId,
                        size: 17,
                        color: nameColor,
                        animate: theme.chatListStatusEmojiMode.animate,
                      ),
                    ),
                  ],
                ],
              ),
              time: !metrics.timeBelow && chat.date > 0
                  ? _time(context, timestampFontSize)
                  : null,
              timeWidth: metrics.timestampWidth,
              indicators: metrics.timeBelow || !_hasIndicators
                  ? null
                  : _indicators(context),
              body: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: AppMetric.chatRowPreviewGap()),
                  chat.draftText.trim().isNotEmpty
                      ? ChatPreviewText(
                          message: chat.draftText,
                          draft: true,
                          fontSize: previewFontSize,
                          chatRowSizing: isTouchTargetPlatform(),
                        )
                      : ChatPreviewText(
                          sender: chat.lastSender,
                          message: chat.lastMessage,
                          fontSize: previewFontSize,
                          chatRowSizing: isTouchTargetPlatform(),
                        ),
                  if (metrics.timeBelow && chat.date > 0)
                    _time(context, timestampFontSize),
                  if (folderTags.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    _folderTags(context, folderTags),
                  ],
                  if (metrics.timeBelow) ...[
                    const SizedBox(height: 4),
                    _indicators(context),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _time(BuildContext context, double fontSize) => Text(
    DateText.listLabel(chat.date),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(fontSize: fontSize, color: context.colors.textTertiary),
  );

  /// 文件夹标签, on their own line along the bottom of the row, under the
  /// message preview. Names only, in each folder's own colour — a chat in five
  /// folders would turn the row into a wall of chips otherwise.
  Widget _folderTags(BuildContext context, List<ChatFolderTag> tags) {
    final fontSize = AppTextSize.chatListFolderTag();
    return SizedBox(
      key: const ValueKey('chat-row-folder-tags'),
      height: MediaQuery.textScalerOf(context).scale(fontSize) * 1.35,
      child: Row(
        children: [
          for (final tag in tags) ...[
            if (tag != tags.first) const SizedBox(width: AppSpacing.sm),
            // Loose flex rather than a fixed width: a row of short folder
            // names draws at its natural size, and only a set too wide for
            // the row starts ellipsizing.
            Flexible(
              child: Text(
                tag.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: fontSize,
                  height: 1.0,
                  fontWeight: AppTextWeight.medium,
                  color: tag.color ?? AppTheme.brand,
                ),
              ),
            ),
          ],
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

  Widget _avatar(
    BuildContext context,
    String title,
    double avatarSize, {
    required bool showSavedMessagesIdentity,
  }) {
    final theme = context.watch<ThemeController>();
    final circleGroups = theme.circularGroupAvatars;
    return SizedBox(
      width: avatarSize,
      height: avatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (showSavedMessagesIdentity)
            AvatarSurface(
              key: const ValueKey('saved-messages-avatar'),
              size: avatarSize,
              background: AppTheme.brand,
              centerChild: true,
              child: const AppIcon(
                HeroAppIcons.bookmark,
                size: 48 * 0.46,
                color: Colors.white,
              ),
            )
          else
            avatarBuilder?.call(avatarSize) ??
                PhotoAvatar(
                  title: title,
                  photo: chat.photo,
                  size: avatarSize,
                  square: chat.usesSquareAvatar && !circleGroups,
                  allowAnimation: false,
                ),
          if (chat.unreadCount > 0)
            Positioned(
              right: 0,
              top: 0,
              child: UnreadBadge(
                count: chat.unreadCount,
                muted: archived || chat.isMuted,
                onClear: onClearUnread,
                chatAvatar: isTouchTargetPlatform(),
              ),
            )
          else if (chat.isMarkedUnread)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.all(AppMetric.badgeOutlinePadding),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: RedDot(
                  size: AppMetric.unreadDot,
                  muted: archived || chat.isMuted,
                ),
              ),
            ),
          if (avatarBadge case final badge?)
            Positioned(right: 0, bottom: 0, child: badge),
        ],
      ),
    );
  }

  bool get _hasIndicators =>
      chat.unreadMentionCount > 0 ||
      chat.unreadReactionCount > 0 ||
      _pinned ||
      chat.isMuted ||
      (trailingIndicator != null && !isDesktopTargetPlatform());

  Widget _indicators(BuildContext context) {
    final c = context.colors;
    final showTrailingIndicator = !isDesktopTargetPlatform();
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (chat.unreadMentionCount > 0)
          _UnreadActivityBadge(
            key: const ValueKey('chat-row-unread-mention'),
            icon: HeroAppIcons.at,
            count: chat.unreadMentionCount,
            label: AppStrings.t(AppStringKeys.notificationMentions),
          ),
        if (chat.unreadReactionCount > 0)
          _UnreadActivityBadge(
            key: const ValueKey('chat-row-unread-reaction'),
            icon: HeroAppIcons.heart,
            count: chat.unreadReactionCount,
            label: AppStrings.t(AppStringKeys.notificationReactions),
          ),
        if (_pinned)
          AppPinIcon(
            key: const ValueKey('chat-row-pinned'),
            size: AppIconSize.sm,
            color: c.textTertiary,
          ),
        if (chat.isMuted)
          AppIcon(
            HeroAppIcons.bellSlash,
            key: const ValueKey('chat-row-muted'),
            size: AppIconSize.sm,
            color: c.textTertiary,
          ),
        if (showTrailingIndicator) ?trailingIndicator,
      ],
    );
  }
}

class _UnreadActivityBadge extends StatelessWidget {
  const _UnreadActivityBadge({
    super.key,
    required this.icon,
    required this.count,
    required this.label,
  });

  final AppIconData icon;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final countLabel = count > 99 ? '99+' : '$count';
    final colors = context.colors;
    return Semantics(
      label: '$label: $countLabel',
      child: Container(
        constraints: const BoxConstraints(minHeight: AppMetric.unreadBadgeMin),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        decoration: BoxDecoration(
          color: colors.badgeBackground,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(icon, size: 11, color: colors.badgeText),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              countLabel,
              style: TextStyle(
                color: colors.badgeText,
                fontSize: 10,
                fontWeight: AppTextWeight.semibold,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
