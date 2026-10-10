//
//  topic_list_host.dart
//
//  Wide split shells paint a topic chat's topic list over the chat list
//  column, the way Telegram iOS does, instead of squeezing a rail into the
//  conversation pane. The topic surface owns the topic data and the shell
//  owns the column, so this relay hands the list from one to the other.
//

import 'package:flutter/widgets.dart';

import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'topic_list_row.dart';
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
    this.onCreateTopic,
    this.onTopicMenu,
  });

  final int chatId;
  final String title;
  final bool usesSquareAvatar;
  final TdFileRef? photo;
  final List<TopicNavigationItem> topics;
  final int? selectedTopicId;
  final ValueChanged<int?> onSelect;

  /// Null when the user lacks the right to create topics: the overlay then
  /// hides its '+' exactly like the inline rail does.
  final VoidCallback? onCreateTopic;
  final TopicRowMenuRequest? onTopicMenu;

  /// Publishing an equal list must not re-notify the shell: the topic
  /// surface listens to the host, so a needless notify would loop.
  bool sameContent(TopicListAttachment other) {
    if (chatId != other.chatId ||
        title != other.title ||
        usesSquareAvatar != other.usesSquareAvatar ||
        photo != other.photo ||
        selectedTopicId != other.selectedTopicId ||
        (onCreateTopic == null) != (other.onCreateTopic == null) ||
        topics.length != other.topics.length) {
      return false;
    }
    for (var i = 0; i < topics.length; i++) {
      if (!topics[i].sameDisplay(other.topics[i])) return false;
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
                  if (attachment.onCreateTopic != null)
                    GestureDetector(
                      key: const ValueKey('topic-list-create'),
                      behavior: HitTestBehavior.opaque,
                      onTap: attachment.onCreateTopic,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        child: AppIcon(
                          HeroAppIcons.plus,
                          size: 22,
                          color: AppTheme.brand,
                        ),
                      ),
                    )
                  else
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
                return TopicListRowView(
                  topic: topic,
                  selected: topic?.id == attachment.selectedTopicId,
                  onTap: () => host.select(topic?.id),
                  onLongPress: topic == null || attachment.onTopicMenu == null
                      ? null
                      : () => attachment.onTopicMenu!(topic, null),
                  onSecondaryTapDown:
                      topic == null || attachment.onTopicMenu == null
                      ? null
                      : (details) => attachment.onTopicMenu!(
                          topic,
                          details.globalPosition,
                        ),
                  generalAvatarTitle: attachment.title,
                  generalAvatarPhoto: attachment.photo,
                  usesSquareAvatar: attachment.usesSquareAvatar,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
