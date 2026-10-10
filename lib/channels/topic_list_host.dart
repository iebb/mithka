//
//  topic_list_host.dart
//
//  Wide split shells paint a topic chat's topic list over the chat list
//  column, the way Telegram iOS does, instead of squeezing a rail into the
//  conversation pane. The topic surface owns the topic data and the shell
//  owns the column, so this relay hands the list from one to the other.
//

import 'package:flutter/widgets.dart';

import '../chat/custom_emoji.dart';
import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'topic_navigation.dart';

/// Where a topic surface should paint its topic list.
enum TopicListPlacement {
  /// Inside the conversation pane (phones, separate chat windows).
  inline,

  /// Handed to the split shell, which overlays it on the chat list column.
  sidebar,
}

class TopicListPlacementScope extends InheritedWidget {
  const TopicListPlacementScope({
    super.key,
    required this.placement,
    required super.child,
  });

  final TopicListPlacement placement;

  static TopicListPlacement of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<TopicListPlacementScope>()
          ?.placement ??
      TopicListPlacement.inline;

  @override
  bool updateShouldNotify(TopicListPlacementScope oldWidget) =>
      placement != oldWidget.placement;
}

/// One topic chat's list, published by the topic surface for the shell.
class TopicListAttachment {
  const TopicListAttachment({
    required this.chatId,
    required this.title,
    required this.usesSquareAvatar,
    this.photo,
    required this.topics,
    required this.selectedTopicId,
    required this.onSelect,
  });

  final int chatId;
  final String title;
  final bool usesSquareAvatar;
  final TdFileRef? photo;
  final List<TopicNavigationItem> topics;
  final int? selectedTopicId;
  final ValueChanged<int?> onSelect;

  /// Publishing an equal list must not re-notify the shell: the topic
  /// surface listens to the host, so a needless notify would loop.
  bool sameContent(TopicListAttachment other) {
    if (chatId != other.chatId ||
        title != other.title ||
        usesSquareAvatar != other.usesSquareAvatar ||
        photo != other.photo ||
        selectedTopicId != other.selectedTopicId ||
        topics.length != other.topics.length) {
      return false;
    }
    for (var i = 0; i < topics.length; i++) {
      final a = topics[i];
      final b = other.topics[i];
      if (a.id != b.id ||
          a.name != b.name ||
          a.iconCustomEmojiId != b.iconCustomEmojiId ||
          a.iconColor != b.iconColor ||
          a.unreadCount != b.unreadCount ||
          a.isMuted != b.isMuted) {
        return false;
      }
    }
    return true;
  }
}

class TopicListHost extends ChangeNotifier {
  TopicListAttachment? _attachment;
  bool _listHidden = false;
  bool _disposed = false;

  TopicListAttachment? get attachment => _attachment;

  /// The user dismissed the overlay to reach the chat list underneath.
  bool get listHidden => _listHidden;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void publish(TopicListAttachment attachment) {
    if (_disposed) return;
    final fresh = _attachment?.chatId != attachment.chatId;
    _attachment = attachment;
    if (fresh) _listHidden = false;
    notifyListeners();
  }

  void unpublish(TopicListAttachment attachment) {
    if (_disposed || !identical(_attachment, attachment)) return;
    _attachment = null;
    _listHidden = false;
    notifyListeners();
  }

  void hideList() {
    if (_disposed || _attachment == null || _listHidden) return;
    _listHidden = true;
    notifyListeners();
  }

  void showList() {
    if (_disposed || _attachment == null || !_listHidden) return;
    _listHidden = false;
    notifyListeners();
  }

  void select(int? topicId) => _attachment?.onSelect(topicId);
}

/// The chat-list overlay: the group's topic list with live unread counters.
class ForumTopicListPane extends StatelessWidget {
  const ForumTopicListPane({super.key, required this.host});

  final TopicListHost host;

  @override
  Widget build(BuildContext context) {
    final attachment = host.attachment;
    if (attachment == null) return const SizedBox.shrink();
    final c = context.colors;
    return Container(
      key: const ValueKey('topic-navigation-left'),
      color: c.background,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
            decoration: BoxDecoration(
              color: c.navBar,
              border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
            ),
            child: SizedBox(
              height: 48,
              child: Row(
                children: [
                  GestureDetector(
                    key: const ValueKey('topic-list-back'),
                    behavior: HitTestBehavior.opaque,
                    onTap: host.hideList,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                      child: AppIcon(
                        HeroAppIcons.chevronLeft,
                        size: 24,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  PhotoAvatar(
                    title: attachment.title,
                    photo: attachment.photo,
                    size: 32,
                    square: attachment.usesSquareAvatar,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          attachment.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          AppStrings.t(AppStringKeys.topicChatTopicCount, {
                            'value1': attachment.topics.length,
                          }),
                          style: TextStyle(
                            fontSize: 12,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: attachment.topics.length + 1,
              itemBuilder: (context, index) {
                final topic = index == 0 ? null : attachment.topics[index - 1];
                return _TopicListRow(
                  topic: topic,
                  selected: topic?.id == attachment.selectedTopicId,
                  onTap: () => host.select(topic?.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TopicListRow extends StatelessWidget {
  const _TopicListRow({
    required this.topic,
    required this.selected,
    required this.onTap,
  });

  final TopicNavigationItem? topic;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final item = topic;
    final name = item?.name ?? AppStringKeys.topicChatAllFilter.l10n(context);
    final iconId = item?.iconCustomEmojiId ?? 0;
    final rawColor = item?.iconColor ?? 0;
    final tint = rawColor == 0
        ? AppTheme.brand
        : Color(0xFF000000 | (rawColor & 0xFFFFFF));
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: GestureDetector(
        key: ValueKey('topic-navigation-item-${topic?.id ?? "all"}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          color: selected ? c.searchFill : null,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: iconId != 0
                    ? CustomEmojiView(id: iconId, size: 24)
                    : AppIcon(
                        HeroAppIcons.hashtag,
                        color: selected ? AppTheme.brand : tint,
                        size: 20,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? AppTheme.brand : c.textPrimary,
                  ),
                ),
              ),
              if (item != null && item.unreadCount > 0) ...[
                const SizedBox(width: 8),
                UnreadBadge(
                  key: ValueKey('topic-navigation-unread-${item.id}'),
                  count: item.unreadCount,
                  muted: item.isMuted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
