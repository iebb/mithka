//
//  chat_row_view.dart
//
//  Reusable chat-list row: avatar with the unread count badged on its top-right
//  corner; title + preview; and a right column holding the timestamp (top) and
//  the mute bell at the row's bottom-right. Port of the Swift `ChatRowView`.
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
import '../theme/date_text.dart';
import '../theme/theme_controller.dart';
import 'chat_folder_tag_controller.dart';

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
    this.titleTrailing,
    this.trailingIndicator,
  });
  final ChatSummary chat;
  final bool archived;
  final bool selected;
  final VoidCallback? onClearUnread;
  final Widget Function(double size)? avatarBuilder;
  final Widget? titleTrailing;
  final Widget? trailingIndicator;

  @override
  Widget build(BuildContext context) {
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
    final rowHeight = chatListRowExtentFor(context);
    final folderTags =
        context.watch<ChatFolderTagController?>()?.tagsFor(chat.folderIds) ??
        const <ChatFolderTag>[];
    final avatarSize = AppMetric.chatListAvatarSize();
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
          : (chat.isPinned ? c.pinnedRow : c.background),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (chat.kind == ChatKind.secret) ...[
                      AppIcon(
                        HeroAppIcons.lock,
                        size: 14,
                        color: c.textSecondary,
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
                      trailing,
                    ],
                    if (showStatus) ...[
                      const SizedBox(width: AppSpacing.xs),
                      StatusEmojiView(
                        id: chat.peerEmojiStatusId,
                        size: 17,
                        color: nameColor,
                        animate: theme.chatListStatusEmojiMode.animate,
                      ),
                    ],
                  ],
                ),
                if (folderTags.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  _folderTags(context, folderTags),
                ],
                const SizedBox(height: AppSpacing.xs),
                chat.draftText.trim().isNotEmpty
                    ? ChatPreviewText(
                        message: chat.draftText,
                        draft: true,
                        fontSize: previewFontSize,
                      )
                    : ChatPreviewText(
                        sender: chat.lastSender,
                        message: chat.lastMessage,
                        fontSize: previewFontSize,
                      ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          _rightColumn(context, rowHeight, timestampFontSize),
        ],
      ),
    );
  }

  /// 文件夹标签, on their own line between the chat's name and its preview.
  /// Names only, in each folder's own colour — a chat in five folders would
  /// turn the row into a wall of chips otherwise.
  Widget _folderTags(BuildContext context, List<ChatFolderTag> tags) {
    final fontSize = AppTextSize.chatListFolderTag();
    return SizedBox(
      key: const ValueKey('chat-row-folder-tags'),
      height: fontSize * 1.35,
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
              child: AppIcon(
                HeroAppIcons.bookmark,
                size: avatarSize * 0.46,
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
        ],
      ),
    );
  }

  Widget _rightColumn(
    BuildContext context,
    double rowHeight,
    double timestampFontSize,
  ) {
    final c = context.colors;
    final showTrailingIndicator = !isDesktopTargetPlatform();
    return SizedBox(
      height: rowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.md + AppSpacing.xxs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              DateText.listLabel(chat.date),
              style: TextStyle(
                fontSize: timestampFontSize,
                color: c.textTertiary,
              ),
            ),
            const Spacer(),
            SizedBox(
              height: AppIconSize.sm,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (chat.isPinned)
                    AppPinIcon(
                      key: const ValueKey('chat-row-pinned'),
                      size: AppIconSize.sm,
                      color: c.textTertiary,
                    ),
                  if (chat.isPinned && chat.isMuted)
                    const SizedBox(width: AppSpacing.xs),
                  if (chat.isMuted)
                    AppIcon(
                      HeroAppIcons.bellSlash,
                      key: const ValueKey('chat-row-muted'),
                      size: AppIconSize.sm,
                      color: c.textTertiary,
                    ),
                  if ((chat.isPinned || chat.isMuted) &&
                      showTrailingIndicator &&
                      trailingIndicator != null)
                    const SizedBox(width: AppSpacing.xs),
                  if (showTrailingIndicator) ?trailingIndicator,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
