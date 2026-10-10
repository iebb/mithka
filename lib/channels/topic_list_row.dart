//
//  topic_list_row.dart
//
//  A forum topic drawn the way Telegram iOS draws it: like a chat-list row.
//  Square topic-icon avatar with the unread count badged on its corner, the
//  topic name with its pinned marker, a last-message preview with the sender
//  prefix and media placeholders, the chat-list timestamp, and the mute bell.
//  Both the conversation-pane rail and the split shell's topic-list overlay
//  render through this one widget so the two surfaces cannot drift apart.
//

import 'package:flutter/material.dart';

import '../chat/custom_emoji.dart';
import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import 'topic_navigation.dart';

/// Chat-list-style row for one forum topic, or for the synthetic "All" entry
/// when [topic] is null.
class TopicListRowView extends StatelessWidget {
  const TopicListRowView({
    super.key,
    required this.topic,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.generalAvatarTitle = '',
    this.generalAvatarPhoto,
    this.usesSquareAvatar = true,
  });

  /// Null renders the "All posts" filter row.
  final TopicNavigationItem? topic;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final GestureTapDownCallback? onSecondaryTapDown;

  /// The group's identity, used for the General topic's avatar: iOS shows the
  /// chat avatar there instead of a topic icon.
  final String generalAvatarTitle;
  final TdFileRef? generalAvatarPhoto;
  final bool usesSquareAvatar;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final item = topic;
    final name = item?.name ?? AppStringKeys.topicChatAllFilter.l10n(context);
    final preview = item?.lastPreview ?? '';
    final rowHeight = AppMetric.rowExtentFor(
      context,
      base: 58,
      lines: [
        AppTextSize.chatListTitle(),
        if (preview.isNotEmpty) AppTextSize.chatListPreview(),
      ],
    );
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: GestureDetector(
        key: ValueKey('topic-navigation-item-${item?.id ?? "all"}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTapDown: onSecondaryTapDown,
        child: Container(
          height: rowHeight,
          color: selected ? c.searchFill : null,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: [
              _avatar(context, item, name),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (item?.isClosed == true) ...[
                          AppIcon(
                            HeroAppIcons.lock,
                            size: 13,
                            color: c.textSecondary,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                        ],
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppTextSize.chatListTitle(),
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: selected ? AppTheme.brand : c.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      ChatPreviewText(
                        sender: item?.lastSender,
                        message: preview,
                        fontSize: AppTextSize.chatListPreview(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              _trailing(context, item, rowHeight),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatar(BuildContext context, TopicNavigationItem? item, String name) {
    final avatarSize = AppMetric.chatListAvatarSize();
    final isGeneral = item?.isGeneral == true;
    final iconId = item?.iconCustomEmojiId ?? 0;
    final rawColor = item?.iconColor ?? 0;
    final tint = rawColor == 0
        ? AppTheme.brand
        : Color(0xFF000000 | (rawColor & 0xFFFFFF));
    return SizedBox(
      width: avatarSize,
      height: avatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (item != null && isGeneral && generalAvatarTitle.isNotEmpty)
            PhotoAvatar(
              title: generalAvatarTitle,
              photo: generalAvatarPhoto,
              size: avatarSize,
              square: usesSquareAvatar,
              allowAnimation: false,
            )
          else
            TopicIconSurface(
              size: avatarSize,
              iconCustomEmojiId: iconId,
              tint: tint,
              selected: selected,
            ),
          if (item != null && item.unreadCount > 0)
            Positioned(
              right: 0,
              top: 0,
              child: UnreadBadge(
                key: ValueKey('topic-navigation-unread-${item.id}'),
                count: item.unreadCount,
                muted: item.isMuted,
              ),
            ),
        ],
      ),
    );
  }

  Widget _trailing(
    BuildContext context,
    TopicNavigationItem? item,
    double rowHeight,
  ) {
    final c = context.colors;
    final date = item?.lastMessageDate ?? 0;
    final showPin = item?.isPinned == true;
    final showMute = item?.isMuted == true;
    if (item == null) return const SizedBox.shrink();
    return SizedBox(
      height: rowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.md + AppSpacing.xxs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (date > 0)
              Text(
                DateText.listLabel(date),
                style: TextStyle(
                  fontSize: AppTextSize.chatListTimestamp(),
                  color: c.textTertiary,
                ),
              ),
            const Spacer(),
            if (showPin || showMute)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showPin)
                    AppPinIcon(
                      key: ValueKey('topic-row-pinned-${item.id}'),
                      size: AppIconSize.sm,
                      color: c.textTertiary,
                    ),
                  if (showPin && showMute) const SizedBox(width: AppSpacing.xs),
                  if (showMute)
                    AppIcon(
                      HeroAppIcons.bellSlash,
                      key: ValueKey('topic-row-muted-${item.id}'),
                      size: AppIconSize.sm,
                      color: c.textTertiary,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// The square topic-icon avatar: a custom emoji when the topic has one, a
/// tinted rounded square with a hashtag otherwise.
class TopicIconSurface extends StatelessWidget {
  const TopicIconSurface({
    super.key,
    required this.size,
    required this.iconCustomEmojiId,
    required this.tint,
    this.selected = false,
    this.fallbackIcon = HeroAppIcons.hashtag,
  });

  final double size;
  final int iconCustomEmojiId;
  final Color tint;
  final bool selected;
  final AppIconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(
          size * AppTheme.groupAvatarCornerRatio,
        ),
      ),
      child: iconCustomEmojiId != 0
          ? CustomEmojiView(id: iconCustomEmojiId, size: size * 0.56)
          : AppIcon(
              fallbackIcon,
              color: selected ? AppTheme.brand : tint,
              size: size * 0.44,
            ),
    );
  }
}
