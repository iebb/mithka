//
//  topic_list_actions.dart
//
//  The moderation affordances a forum topic list offers: the create/edit
//  draft dialog, the row context menu and the TDLib requests they send.
//  Every surface that renders a topic list (the conversation-pane rail and
//  the split shell's chat-list overlay) shares this file, so their actions
//  cannot drift apart.
//

import 'package:flutter/material.dart';

import '../chat/custom_emoji.dart';
import '../components/app_dialog.dart';
import '../components/app_icons.dart';
import '../l10n/app_localizations.dart';
import '../notifications/notification_settings_payload.dart';
import '../profile/profile_icon_picker_view.dart';
import '../tdlib/td_client.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'topic_list_row.dart';
import 'topic_navigation.dart';

/// The six topic-icon colours Telegram offers when creating a topic.
const List<int> topicIconColors = [
  0x6FB9F0,
  0xFFD67E,
  0xCB86DB,
  0x8EEE98,
  0xFF93B2,
  0xFB6F5F,
];

/// A topic name/icon collected by the create and edit dialogs.
class TopicDraft {
  const TopicDraft({
    required this.name,
    required this.color,
    required this.customEmojiId,
  });

  final String name;
  final int color;
  final int customEmojiId;
}

/// Focused create/edit topic dialog in mithka styling: a name field, the six
/// Telegram topic icon colours (create only — editing keeps the colour), and
/// an optional custom emoji icon.
class TopicDraftDialog extends StatefulWidget {
  const TopicDraftDialog({
    super.key,
    required this.title,
    required this.initialName,
    required this.initialColor,
    required this.initialCustomEmojiId,
    required this.canChangeColor,
  });

  final String title;
  final String initialName;
  final int initialColor;
  final int initialCustomEmojiId;
  final bool canChangeColor;

  @override
  State<TopicDraftDialog> createState() => _TopicDraftDialogState();
}

class _TopicDraftDialogState extends State<TopicDraftDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );
  late int _color = widget.initialColor;
  late int _customEmojiId = widget.initialCustomEmojiId;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(
      context,
    ).pop(TopicDraft(name: name, color: _color, customEmojiId: _customEmojiId));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Built on the project's owned dialog surface: it carries the Material
    // ancestor a TextField needs, so this dialog draws no Material of its own.
    return AppDialogSurface(
      maxWidth: 360,
      title: widget.title.l10n(context),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('topic-draft-name'),
            controller: _controller,
            autofocus: true,
            maxLength: 128,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: AppStrings.t(AppStringKeys.chatInputBarTopicName),
            ),
          ),
          const SizedBox(height: 8),
          if (widget.canChangeColor) ...[
            Text(
              AppStrings.t(AppStringKeys.groupAdministrationIconColor),
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              children: [
                for (final candidate in topicIconColors)
                  GestureDetector(
                    key: ValueKey('topic-draft-color-$candidate'),
                    onTap: () => setState(() => _color = candidate),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF000000 | candidate),
                        border: _color == candidate
                            ? Border.all(color: AppTheme.brand, width: 3)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          GestureDetector(
            key: const ValueKey('topic-draft-emoji'),
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              final id = await Navigator.of(context).push<int>(
                MaterialPageRoute(
                  builder: (_) => ProfileIconPickerView(
                    selectedId: _customEmojiId,
                    title: AppStrings.t(
                      AppStringKeys.groupAdministrationTopicIcon,
                    ),
                    source: ProfileIconSource.status,
                  ),
                ),
              );
              if (id != null && mounted) {
                setState(() => _customEmojiId = id);
              }
            },
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    AppStrings.t(
                      AppStringKeys.groupAdministrationCustomEmojiIcon,
                    ),
                    style: TextStyle(fontSize: 14, color: c.textPrimary),
                  ),
                ),
                if (_customEmojiId == 0)
                  Text(
                    AppStrings.t(AppStringKeys.groupAppearanceNone),
                    style: TextStyle(fontSize: 14, color: c.textSecondary),
                  )
                else
                  CustomEmojiView(id: _customEmojiId, size: 26),
                const SizedBox(width: 8),
                AppIcon(
                  HeroAppIcons.chevronRight,
                  size: 15,
                  color: c.textTertiary,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        AppDialogAction(
          label: AppStrings.t(AppStringKeys.confirmCancel),
          onTap: () => Navigator.of(context).pop(),
        ),
        AppDialogAction(
          key: const ValueKey('topic-draft-save'),
          label: AppStrings.t(AppStringKeys.accentColorPickerSave),
          primary: true,
          onTap: _submit,
        ),
      ],
    );
  }
}

Map<String, dynamic> forumTopicViewMessagesRequest({
  required int chatId,
  required List<int> messageIds,
}) => {
  '@type': 'viewMessages',
  'chat_id': chatId,
  'message_ids': messageIds,
  'source': {'@type': 'messageSourceForumTopicHistory'},
  'force_read': true,
};

/// One topic to clear, reduced to what a read needs: its id, its newest
/// message, and whether it still reports unread traffic.
class ForumTopicReadTarget {
  const ForumTopicReadTarget({
    required this.topicId,
    required this.lastMessageId,
    this.unreadCount = 0,
  });

  final int topicId;
  final int lastMessageId;
  final int unreadCount;
}

/// The per-topic read requests that clear [topics]: one `viewMessages` per
/// topic, scoped through [forumTopicViewMessagesRequest] so TDLib advances
/// that topic's own inbox watermark (a chat-wide read cannot address a
/// thread). Every topic with a real last message is read, whatever counter it
/// reports locally — a stale zero must not leave a topic unread on the
/// server. A topic with no message to advance to has nothing to send.
List<Map<String, dynamic>> forumTopicMarkAllReadRequests({
  required int chatId,
  required Iterable<ForumTopicReadTarget> topics,
}) => [
  for (final topic in topics)
    if (topic.lastMessageId > 0)
      forumTopicViewMessagesRequest(
        chatId: chatId,
        messageIds: [topic.lastMessageId],
      ),
];

Map<String, dynamic> createForumTopicRequest({
  required int chatId,
  required String name,
  required int color,
  required int customEmojiId,
}) => {
  '@type': 'createForumTopic',
  'chat_id': chatId,
  'name': name,
  'is_name_implicit': false,
  'icon': {
    '@type': 'forumTopicIcon',
    'color': color,
    'custom_emoji_id': customEmojiId,
  },
};

Map<String, dynamic> editForumTopicRequest({
  required int chatId,
  required int forumTopicId,
  required String name,
  required int customEmojiId,
}) => {
  '@type': 'editForumTopic',
  'chat_id': chatId,
  'forum_topic_id': forumTopicId,
  'name': name,
  'edit_icon_custom_emoji': true,
  'icon_custom_emoji_id': customEmojiId,
};

Map<String, dynamic> deleteForumTopicRequest({
  required int chatId,
  required int forumTopicId,
}) => {
  '@type': 'deleteForumTopic',
  'chat_id': chatId,
  'forum_topic_id': forumTopicId,
};

Map<String, dynamic> toggleForumTopicPinnedRequest({
  required int chatId,
  required int forumTopicId,
  required bool isPinned,
}) => {
  '@type': 'toggleForumTopicIsPinned',
  'chat_id': chatId,
  'forum_topic_id': forumTopicId,
  'is_pinned': isPinned,
};

Map<String, dynamic> setForumTopicMutedRequest({
  required int chatId,
  required int forumTopicId,
  required bool muted,
}) => {
  '@type': 'setForumTopicNotificationSettings',
  'chat_id': chatId,
  'forum_topic_id': forumTopicId,
  'notification_settings': inheritedChatNotificationSettings(
    muteFor: muted ? 2147483647 : 0,
  ),
};

Map<String, dynamic> toggleForumTopicClosedRequest({
  required int chatId,
  required int forumTopicId,
  required bool isClosed,
}) => {
  '@type': 'toggleForumTopicIsClosed',
  'chat_id': chatId,
  'forum_topic_id': forumTopicId,
  'is_closed': isClosed,
};

/// The gated action list for one topic row, exactly the way Telegram iOS
/// offers them: mark-read while unread remains, mute for everyone, pin/edit/
/// close behind can_manage_topics, delete behind the creator /
/// can_delete_messages rule (the caller decides that one).
List<TopicRowAction> topicRowActions({
  required TopicNavigationItem topic,
  required bool canManage,
  required bool canDelete,
  required Future<void> Function() onMarkRead,
  required Future<void> Function() onTogglePinned,
  required Future<void> Function() onToggleMuted,
  required Future<void> Function() onEdit,
  required Future<void> Function() onToggleClosed,
  required Future<void> Function() onDelete,
}) {
  return [
    if (topic.unreadCount > 0)
      TopicRowAction(
        key: 'read',
        label: AppStrings.t(AppStringKeys.channelDirectMessagesMarkRead),
        icon: HeroAppIcons.circleCheck,
        onSelected: onMarkRead,
      ),
    if (canManage)
      TopicRowAction(
        key: 'pin',
        label: topic.isPinned
            ? AppStrings.t(AppStringKeys.chatListUnpin)
            : AppStrings.t(AppStringKeys.chatInfoPin),
        icon: HeroAppIcons.thumbtack,
        onSelected: onTogglePinned,
      ),
    TopicRowAction(
      key: 'mute',
      label: topic.isMuted
          ? AppStrings.t(AppStringKeys.chatUnmute)
          : AppStrings.t(AppStringKeys.callMute),
      icon: topic.isMuted ? HeroAppIcons.bell : HeroAppIcons.bellSlash,
      onSelected: onToggleMuted,
    ),
    if (canManage && !topic.isGeneral)
      TopicRowAction(
        key: 'edit',
        label: AppStrings.t(AppStringKeys.groupAdministrationEditTopic),
        icon: HeroAppIcons.pen,
        onSelected: onEdit,
      ),
    if (canManage && !topic.isGeneral)
      TopicRowAction(
        key: 'close',
        label: topic.isClosed
            ? AppStrings.t(AppStringKeys.topicChatReopenTopic)
            : AppStrings.t(AppStringKeys.topicChatCloseTopic),
        icon: topic.isClosed ? HeroAppIcons.eye : HeroAppIcons.lock,
        onSelected: onToggleClosed,
      ),
    if (canDelete)
      TopicRowAction(
        key: 'delete',
        label: AppStrings.t(AppStringKeys.chatDelete),
        icon: HeroAppIcons.trash,
        destructive: true,
        onSelected: onDelete,
      ),
  ];
}

/// The topic row's context menu sheet (iOS swipe action / long press).
Future<void> showTopicRowMenuSheet({
  required BuildContext context,
  required TopicNavigationItem topic,
  required List<TopicRowAction> actions,
}) async {
  if (actions.isEmpty) return;
  await showAppModalSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final c = sheetContext.colors;
      return SafeArea(
        child: Container(
          key: ValueKey('topic-row-menu-${topic.id}'),
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    TopicIconSurface(
                      size: 32,
                      iconCustomEmojiId: topic.iconCustomEmojiId,
                      tint: topic.iconColor == 0
                          ? AppTheme.brand
                          : Color(0xFF000000 | (topic.iconColor & 0xFFFFFF)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        topic.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              for (final action in actions) TopicMenuRow(action: action),
            ],
          ),
        ),
      );
    },
  );
}

/// One row of a topic's context menu sheet.
class TopicMenuRow extends StatelessWidget {
  const TopicMenuRow({super.key, required this.action});

  final TopicRowAction action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final foreground = action.destructive ? AppTheme.tagRed : c.textPrimary;
    return Semantics(
      button: true,
      label: action.label,
      child: GestureDetector(
        key: ValueKey('topic-menu-${action.key}'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Navigator.of(context).pop();
          action.onSelected();
        },
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.divider, width: 0.5)),
          ),
          child: Row(
            children: [
              AppIcon(action.icon, size: 19, color: foreground),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Error text for a failed topic action, keeping TDLib's message when the
/// error carries one.
String topicActionErrorText(String fallback, Object error) {
  if (error is TdError && error.message.trim().isNotEmpty) {
    return '$fallback: ${error.message.trim()}';
  }
  return AppStrings.t(AppStringKeys.topicPostContentActionFailed);
}
