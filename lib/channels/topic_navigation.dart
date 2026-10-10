import 'package:flutter/widgets.dart';

import '../app/adaptive_split_layout.dart';
import '../chat/custom_emoji.dart';
import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'topic_list_row.dart';

class TopicNavigationItem {
  const TopicNavigationItem({
    required this.id,
    required this.name,
    this.iconCustomEmojiId = 0,
    this.iconColor = 0,
    this.unreadCount = 0,
    this.isMuted = false,
    this.isPinned = false,
    this.isGeneral = false,
    this.isClosed = false,
    this.lastPreview = '',
    this.lastSender,
    this.lastMessageDate = 0,
  });

  final int id;
  final String name;
  final int iconCustomEmojiId;
  final int iconColor;

  /// Live unread messages in this topic, maintained through the shared forum
  /// topic index; 0 when unknown.
  final int unreadCount;
  final bool isMuted;
  final bool isPinned;

  /// The General topic (id 1): shows the chat avatar and cannot be deleted.
  final bool isGeneral;
  final bool isClosed;

  /// Last-message preview text with media/service placeholders already
  /// composed the way the chat list composes them; empty hides the line.
  final String lastPreview;

  /// Sender prefix for [lastPreview] ("Alice", "You:"), null for none.
  final String? lastSender;

  /// Unix seconds of the last message; 0 hides the timestamp.
  final int lastMessageDate;

  /// Whether any chat-list-style row data is present, so a compact rail that
  /// lacks it can keep its 44px chip rows instead of half-empty list rows.
  bool get hasRowDetail =>
      lastPreview.isNotEmpty || lastMessageDate > 0 || isPinned;

  /// Display-field equality, so a republished list that changed nothing
  /// never re-notifies a listening shell.
  bool sameDisplay(TopicNavigationItem other) =>
      id == other.id &&
      name == other.name &&
      iconCustomEmojiId == other.iconCustomEmojiId &&
      iconColor == other.iconColor &&
      unreadCount == other.unreadCount &&
      isMuted == other.isMuted &&
      isPinned == other.isPinned &&
      isGeneral == other.isGeneral &&
      isClosed == other.isClosed &&
      lastPreview == other.lastPreview &&
      lastSender == other.lastSender &&
      lastMessageDate == other.lastMessageDate;
}

/// One action offered by a topic row's context menu.
class TopicRowAction {
  const TopicRowAction({
    required this.key,
    required this.label,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
  });

  /// Stable identifier, also used as the menu row's ValueKey suffix.
  final String key;
  final String label;
  final AppIconData icon;
  final VoidCallback onSelected;
  final bool destructive;
}

/// A topic row's context menu request: the topic and where the gesture
/// landed (desktop right-click anchors a positioned menu there).
typedef TopicRowMenuRequest =
    void Function(TopicNavigationItem topic, Offset? globalPosition);

/// The group's has_forum_tabs setting selects top tabs; other wide topic
/// chats show a rail at the left edge of their conversation pane.
class TopicNavigationLayout extends StatelessWidget {
  const TopicNavigationLayout({
    super.key,
    required this.topics,
    required this.selectedTopicId,
    required this.hasForumTabs,
    required this.onSelected,
    required this.child,
    this.onCreateTopic,
    this.onTopicMenu,
    this.generalAvatarTitle = '',
    this.generalAvatarPhoto,
  });

  final List<TopicNavigationItem> topics;
  final int? selectedTopicId;
  final bool hasForumTabs;
  final ValueChanged<int?> onSelected;
  final Widget child;

  /// Telegram iOS offers topic creation from the topic list itself; null
  /// hides the affordance (no can_create_topics / can_manage_topics right).
  final VoidCallback? onCreateTopic;
  final TopicRowMenuRequest? onTopicMenu;
  final String generalAvatarTitle;
  final TdFileRef? generalAvatarPhoto;

  @override
  Widget build(BuildContext context) {
    final vertical =
        usesSplitSelectionLayout(MediaQuery.sizeOf(context)) && !hasForumTabs;
    final detailed = topics.any((topic) => topic.hasRowDetail);
    final navigation = _TopicNavigation(
      topics: topics,
      selectedTopicId: selectedTopicId,
      vertical: vertical,
      detailed: vertical && detailed,
      onSelected: onSelected,
      onCreateTopic: vertical ? onCreateTopic : null,
      onTopicMenu: onTopicMenu,
      generalAvatarTitle: generalAvatarTitle,
      generalAvatarPhoto: generalAvatarPhoto,
    );
    if (!vertical) {
      return Column(
        children: [
          SizedBox(height: 44, child: navigation),
          Expanded(child: child),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          SizedBox(
            width: detailed
                ? (constraints.maxWidth * 0.30).clamp(212.0, 280.0)
                : (constraints.maxWidth * 0.24).clamp(120.0, 196.0),
            child: navigation,
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _TopicNavigation extends StatelessWidget {
  const _TopicNavigation({
    required this.topics,
    required this.selectedTopicId,
    required this.vertical,
    required this.detailed,
    required this.onSelected,
    this.onCreateTopic,
    this.onTopicMenu,
    this.generalAvatarTitle = '',
    this.generalAvatarPhoto,
  });

  final List<TopicNavigationItem> topics;
  final int? selectedTopicId;
  final bool vertical;

  /// Vertical rails with preview data draw chat-list-style rows.
  final bool detailed;
  final ValueChanged<int?> onSelected;
  final VoidCallback? onCreateTopic;
  final TopicRowMenuRequest? onTopicMenu;
  final String generalAvatarTitle;
  final TdFileRef? generalAvatarPhoto;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      key: ValueKey(
        vertical ? 'topic-navigation-left' : 'topic-navigation-top',
      ),
      decoration: BoxDecoration(
        color: c.background,
        border: vertical
            ? Border(right: BorderSide(color: c.divider, width: 0.5))
            : Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: Column(
        children: [
          if (detailed && onCreateTopic != null)
            _RailCreateHeader(onCreateTopic: onCreateTopic!),
          Expanded(
            child: detailed ? _detailedList(context) : _compactList(context),
          ),
        ],
      ),
    );
  }

  Widget _detailedList(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.symmetric(vertical: 6),
    itemCount: topics.length + 1,
    itemBuilder: (context, index) {
      final topic = index == 0 ? null : topics[index - 1];
      return TopicListRowView(
        topic: topic,
        selected: topic?.id == selectedTopicId,
        onTap: () => onSelected(topic?.id),
        onLongPress: topic == null || onTopicMenu == null
            ? null
            : () => onTopicMenu!(topic, null),
        onSecondaryTapDown: topic == null || onTopicMenu == null
            ? null
            : (details) => onTopicMenu!(topic, details.globalPosition),
        generalAvatarTitle: generalAvatarTitle,
        generalAvatarPhoto: generalAvatarPhoto,
      );
    },
  );

  Widget _compactList(BuildContext context) {
    final c = context.colors;
    return ListView.builder(
      padding: EdgeInsets.symmetric(
        horizontal: vertical ? 6 : 10,
        vertical: vertical ? 6 : 0,
      ),
      scrollDirection: vertical ? Axis.vertical : Axis.horizontal,
      itemCount: topics.length + 1,
      itemBuilder: (context, index) {
        final topic = index == 0 ? null : topics[index - 1];
        final selected = topic?.id == selectedTopicId;
        final name =
            topic?.name ?? AppStringKeys.topicChatAllFilter.l10n(context);
        final iconId = topic?.iconCustomEmojiId ?? 0;
        final rawColor = topic?.iconColor ?? 0;
        final color = selected
            ? AppTheme.brand
            : rawColor == 0
            ? c.textSecondary
            : Color(0xFF000000 | (rawColor & 0xFFFFFF));
        return Semantics(
          button: true,
          selected: selected,
          label: name,
          child: GestureDetector(
            key: ValueKey('topic-navigation-item-${topic?.id ?? "all"}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelected(topic?.id),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: vertical && selected ? c.searchFill : null,
                borderRadius: vertical
                    ? BorderRadius.circular(AppRadius.control)
                    : null,
                border: !vertical && selected
                    ? Border(
                        bottom: BorderSide(color: AppTheme.brand, width: 3),
                      )
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (iconId != 0)
                    CustomEmojiView(id: iconId)
                  else
                    AppIcon(HeroAppIcons.hashtag, color: color, size: 20),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: selected ? AppTheme.brand : c.textPrimary,
                      ),
                    ),
                  ),
                  if (topic != null && topic.unreadCount > 0) ...[
                    const SizedBox(width: 6),
                    UnreadBadge(
                      key: ValueKey('topic-navigation-unread-${topic.id}'),
                      count: topic.unreadCount,
                      muted: topic.isMuted,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The vertical rail's create affordance: Telegram iOS puts topic creation
/// in the topic list's own header, so the '+' lives above the rows here.
class _RailCreateHeader extends StatelessWidget {
  const _RailCreateHeader({required this.onCreateTopic});

  final VoidCallback onCreateTopic;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 40,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                AppStringKeys.groupAdministrationForumTopics.l10n(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.textSecondary,
                ),
              ),
            ),
          ),
          GestureDetector(
            key: const ValueKey('topic-list-create'),
            behavior: HitTestBehavior.opaque,
            onTap: onCreateTopic,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: AppIcon(
                HeroAppIcons.plus,
                size: 20,
                color: AppTheme.brand,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
