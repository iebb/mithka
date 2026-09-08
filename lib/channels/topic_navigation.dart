import 'package:flutter/widgets.dart';

import '../app/adaptive_split_layout.dart';
import '../chat/custom_emoji.dart';
import '../components/app_icons.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

class TopicNavigationItem {
  const TopicNavigationItem({
    required this.id,
    required this.name,
    this.iconCustomEmojiId = 0,
    this.iconColor = 0,
  });

  final int id;
  final String name;
  final int iconCustomEmojiId;
  final int iconColor;
}

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
  });

  final List<TopicNavigationItem> topics;
  final int? selectedTopicId;
  final bool hasForumTabs;
  final ValueChanged<int?> onSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final vertical =
        usesSplitSelectionLayout(MediaQuery.sizeOf(context)) && !hasForumTabs;
    final navigation = _TopicNavigation(
      topics: topics,
      selectedTopicId: selectedTopicId,
      vertical: vertical,
      onSelected: onSelected,
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
            width: (constraints.maxWidth * 0.24).clamp(120.0, 196.0),
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
    required this.onSelected,
  });

  final List<TopicNavigationItem> topics;
  final int? selectedTopicId;
  final bool vertical;
  final ValueChanged<int?> onSelected;

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
      child: ListView.builder(
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
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
