import 'package:flutter/widgets.dart';

import '../app/adaptive_split_layout.dart';
import '../chat/stickers/custom_emoji.dart';
import '../components/app_icons.dart';
import '../components/chat_folder_icons.dart';
import '../components/full_page_back_swipe.dart';
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
    this.onMarkAllRead,
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

  /// Clears every unread topic at once; null while no topic is unread.
  final VoidCallback? onMarkAllRead;
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
      onMarkAllRead: onMarkAllRead,
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
    this.onMarkAllRead,
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
  final VoidCallback? onMarkAllRead;
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
          if (detailed && (onCreateTopic != null || onMarkAllRead != null))
            _RailHeader(
              onCreateTopic: onCreateTopic,
              onMarkAllRead: onMarkAllRead,
            ),
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

/// The vertical rail's header: Telegram iOS puts topic creation in the topic
/// list's own header, so the '+' lives above the rows here. The same header
/// carries the bulk "mark all topics read" action while anything is unread.
class _RailHeader extends StatelessWidget {
  const _RailHeader({this.onCreateTopic, this.onMarkAllRead});

  final VoidCallback? onCreateTopic;
  final VoidCallback? onMarkAllRead;

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
          if (onMarkAllRead != null)
            Semantics(
              button: true,
              label: AppStringKeys.topicChatMarkAllRead.l10n(context),
              child: GestureDetector(
                key: const ValueKey('topic-list-mark-all-read'),
                behavior: HitTestBehavior.opaque,
                onTap: onMarkAllRead,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: AppIcon(
                    HeroAppIcons.circleCheck,
                    size: 20,
                    color: c.textSecondary,
                  ),
                ),
              ),
            ),
          if (onCreateTopic != null)
            GestureDetector(
              key: const ValueKey('topic-list-create'),
              behavior: HitTestBehavior.opaque,
              onTap: onCreateTopic,
              child: Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.md,
                  right: AppSpacing.lg,
                  top: AppSpacing.sm,
                  bottom: AppSpacing.sm,
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

/// Remembers each chat's tab-strip scroll offset across transcript swaps.
/// Opening a topic replaces the whole ChatView (its state reads the topic
/// once), so the fresh strip rebuilds at offset 0 without this — shifting
/// the tabs the user was looking at. Keyed by chat, never cleared: it is a
/// few floats per forum chat.
class TopicTabStripScrollMemory {
  TopicTabStripScrollMemory._();

  static final Map<int, double> _offsets = {};

  static double? read(int chatId) => _offsets[chatId];

  static void write(int chatId, double offset) {
    // Guard degenerate extents before the list has laid out.
    if (!offset.isFinite || offset < 0) return;
    _offsets[chatId] = offset;
  }

  /// Drops every remembered offset. Tests only.
  @visibleForTesting
  static void resetForTesting() => _offsets.clear();
}

/// The topic tab strip: a horizontal, folder-tab-styled selector pinned
/// under the chat header for forum groups and bot topic chats on narrow
/// layouts. Mirrors the chat list's folder tabs — label with the topic
/// icon, unread badge pill, and the 4pt selection indicator under the
/// chosen tab. Switching topics must not move the strip: the scroll offset
/// lives in [TopicTabStripScrollMemory] and survives the transcript swap.
class TopicTabStrip extends StatefulWidget {
  const TopicTabStrip({
    super.key,
    required this.chatId,
    required this.topics,
    required this.selectedTopicId,
    required this.onSelected,
    this.showUnreadBadges = true,
    this.badgeOverflowLabel,
    this.isLoading = false,
    this.onLongPress,
  });

  /// The chat whose topics these are; keys the scroll-offset memory.
  final int chatId;

  final List<TopicNavigationItem> topics;

  /// The open transcript's topic id; null = the "All" pseudo-topic.
  final int? selectedTopicId;
  final ValueChanged<int?> onSelected;

  /// Folder-tab badge parity: honours the chat-list unread-badge setting.
  final bool showUnreadBadges;

  /// Pre-formatted count text for [topics]' total unread; when null the strip
  /// derives per-topic labels itself (capped at 99+).
  final String? Function(int count)? badgeOverflowLabel;

  /// Shows the trailing shimmer tab while a topic page is still in flight.
  final bool isLoading;

  /// Long press on a real topic tab, with the tab's global rect as the
  /// anchor for the host's topic menu. The "All" pseudo-tab never fires it.
  final void Function(TopicNavigationItem topic, Rect anchor)? onLongPress;

  @override
  State<TopicTabStrip> createState() => _TopicTabStripState();
}

class _TopicTabStripState extends State<TopicTabStrip> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController(
      initialScrollOffset: TopicTabStripScrollMemory.read(widget.chatId) ?? 0,
    );
    _controller.addListener(_rememberOffset);
  }

  @override
  void dispose() {
    _rememberOffset();
    _controller.dispose();
    super.dispose();
  }

  void _rememberOffset() {
    if (!_controller.hasClients) return;
    TopicTabStripScrollMemory.write(widget.chatId, _controller.offset);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tabHeight = AppMetric.rowExtentFor(
      context,
      base: 44,
      lines: const [AppTextSize.callout],
    );
    final topics = widget.topics;
    final isLoading = widget.isLoading;
    // The strip scrolls horizontally, so a rightward drag on it means "show
    // earlier tabs" — never the page's back swipe. Keep the whole bar out of
    // that gesture, including the gaps between tabs.
    return ExcludeFromBackSwipe(
      child: Container(
        width: double.infinity,
        height: tabHeight,
        decoration: BoxDecoration(
          // Same bar as the chat header so the strip reads as part of the
          // header, not a separate washed panel.
          color: c.navBar,
          border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
        ),
        child: ListView.separated(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          itemCount: topics.length + 1 + (isLoading ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(width: 28),
          itemBuilder: (context, index) {
            // Index 0 is the "All" tab; topics occupy 1..topics.length, and the
            // loading placeholder is the LAST slot. Getting this off by one
            // reads topics[-1] on an empty page and Flutter swaps in an error
            // box, which release builds paint as an opaque grey block over the
            // strip's right side.
            if (isLoading && index == topics.length + 1) {
              // Topic info is still loading: the placeholder tab keeps the same
              // bar color as the header so the strip reads as one unified
              // surface instead of a grey block sticking out.
              return SizedBox(height: tabHeight);
            }
            final all = index == 0;
            final topic = all ? null : topics[index - 1];
            final selected = all
                ? widget.selectedTopicId == null
                : topic!.id == widget.selectedTopicId;
            return _TopicTab(
              key: ValueKey('topic-tab-${topic?.id ?? "all"}'),
              topic: topic,
              selected: selected,
              showUnreadBadge: widget.showUnreadBadges,
              badgeOverflowLabel: widget.badgeOverflowLabel,
              onTap: () => widget.onSelected(topic?.id),
              onLongPress: topic == null
                  ? null
                  : (anchor) => widget.onLongPress?.call(topic, anchor),
            );
          },
        ),
      ),
    );
  }
}

class _TopicTab extends StatelessWidget {
  const _TopicTab({
    super.key,
    required this.topic,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.showUnreadBadge = true,
    this.badgeOverflowLabel,
  });

  final TopicNavigationItem? topic;
  final bool selected;
  final VoidCallback onTap;

  /// Reports the tab's global rect so the host can hang its menu there.
  final ValueChanged<Rect>? onLongPress;
  final bool showUnreadBadge;
  final String? Function(int count)? badgeOverflowLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isAll = topic == null;
    final name = isAll
        ? AppStringKeys.topicChatAllFilter.l10n(context)
        : topic!.name;
    final unread = topic?.unreadCount ?? 0;
    final iconId = topic?.iconCustomEmojiId ?? 0;
    final rawColor = topic?.iconColor ?? 0;
    final iconColor = selected
        ? AppTheme.brand
        : rawColor == 0
        ? c.textSecondary
        : Color(0xFF000000 | (rawColor & 0xFFFFFF));
    final longPress = onLongPress;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: longPress == null
          ? null
          : () {
              final box = context.findRenderObject() as RenderBox?;
              if (box == null || !box.hasSize) return;
              longPress(box.localToGlobal(Offset.zero) & box.size);
            },
      child: SizedBox(
        height: 44,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (iconId != 0)
                  CustomEmojiView(id: iconId, size: 17)
                else
                  AppIcon(
                    isAll ? HeroAppIcons.inbox : HeroAppIcons.hashtag,
                    size: 17,
                    color: iconColor,
                  ),
                const SizedBox(width: AppSpacing.xs + 1),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 168),
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppTextSize.callout,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: c.textPrimary,
                    ),
                  ),
                ),
                if (showUnreadBadge && !isAll && unread > 0) ...[
                  const SizedBox(width: 5),
                  FolderUnreadBadge(
                    key: ValueKey('topic-tab-unread-${topic!.id}'),
                    label: _badgeLabel(unread),
                    accent: !topic!.isMuted,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 7),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.brand.withValues(alpha: selected ? 1 : 0),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _badgeLabel(int count) {
    final custom = badgeOverflowLabel?.call(count);
    if (custom != null) return custom;
    return count > 99 ? '99+' : '$count';
  }
}
