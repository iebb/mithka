//
//  forum_topic_browser_view.dart
//
//  Intermediate browser for forum/topic chats opened from the main chat list:
//  the left rail is the topic-chat list, and the right side lists topics for
//  the selected chat. Opening a row enters the real topic view.
//

import 'package:flutter/material.dart';

import '../chat/chat_view.dart';
import '../chat/custom_emoji.dart';
import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import 'topic_chat_view.dart';

class ForumTopicBrowserView extends StatefulWidget {
  const ForumTopicBrowserView({
    super.key,
    required this.chats,
    required this.initialChat,
  });

  final List<ChatSummary> chats;
  final ChatSummary initialChat;

  @override
  State<ForumTopicBrowserView> createState() => _ForumTopicBrowserViewState();
}

class _ForumTopicBrowserViewState extends State<ForumTopicBrowserView> {
  final _topicsByChat = <int, List<_ForumTopicEntry>>{};
  final _loadingChats = <int>{};
  late ChatSummary _selectedChat = widget.initialChat;

  List<ChatSummary> get _chats {
    final byId = <int, ChatSummary>{};
    for (final chat in [widget.initialChat, ...widget.chats]) {
      byId[chat.id] = chat;
    }
    return byId.values.toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  @override
  void initState() {
    super.initState();
    _loadTopics(_selectedChat);
  }

  void _selectChat(ChatSummary chat) {
    if (_selectedChat.id == chat.id) return;
    if (!chat.isForum) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatView(
            chatId: chat.id,
            title: chat.title,
            seedMessage: chat.lastChatMessage,
          ),
        ),
      );
      return;
    }
    setState(() => _selectedChat = chat);
    _loadTopics(chat);
  }

  Future<void> _loadTopics(ChatSummary chat) async {
    if (_topicsByChat.containsKey(chat.id) || _loadingChats.contains(chat.id)) {
      return;
    }
    setState(() => _loadingChats.add(chat.id));
    try {
      final response = await TdClient.shared.query({
        '@type': 'getForumTopics',
        'chat_id': chat.id,
        'query': '',
        'offset_date': 0,
        'offset_message_id': 0,
        'offset_message_thread_id': 0,
        'limit': 120,
      });
      final rawTopics =
          response.objects('topics') ?? const <Map<String, dynamic>>[];
      final topics = <_ForumTopicEntry>[];
      for (final topic in rawTopics) {
        final info = topic.obj('info') ?? topic;
        final last = topic.obj('last_message');
        final message = last == null ? null : TDParse.message(last);
        final id =
            info.int64('message_thread_id') ?? topic.int64('message_thread_id');
        if (id == null || id == 0) continue;
        topics.add(
          _ForumTopicEntry(
            id: id,
            name:
                info.str('name') ??
                topic.str('name') ??
                AppStrings.t(AppStringKeys.topicChatTopicTitle),
            lastMessage: message,
            unreadCount: _topicUnreadCount(topic, info),
            isMuted:
                (topic.obj('notification_settings')?.integer('mute_for') ?? 0) >
                0,
            iconCustomEmojiId: _topicCustomEmojiId(topic, info),
            iconColor: _topicIconColor(topic, info),
          ),
        );
      }
      topics.sort((a, b) {
        final bd = b.lastMessage?.date ?? 0;
        final ad = a.lastMessage?.date ?? 0;
        return bd.compareTo(ad);
      });
      if (!mounted) return;
      setState(() => _topicsByChat[chat.id] = topics);
    } catch (_) {
      if (mounted) setState(() => _topicsByChat[chat.id] = const []);
    } finally {
      if (mounted) setState(() => _loadingChats.remove(chat.id));
    }
  }

  int _topicUnreadCount(Map<String, dynamic> topic, Map<String, dynamic> info) {
    final count =
        topic.integer('unread_count') ??
        info.integer('unread_count') ??
        topic.integer('unread_mention_count') ??
        info.integer('unread_mention_count') ??
        0;
    return count < 0 ? 0 : count;
  }

  int _topicCustomEmojiId(
    Map<String, dynamic> topic,
    Map<String, dynamic> info,
  ) {
    return info.obj('icon')?.int64('custom_emoji_id') ??
        topic.obj('icon')?.int64('custom_emoji_id') ??
        info.int64('icon_custom_emoji_id') ??
        topic.int64('icon_custom_emoji_id') ??
        0;
  }

  Color? _topicIconColor(
    Map<String, dynamic> topic,
    Map<String, dynamic> info,
  ) {
    final raw =
        info.obj('icon')?.integer('color') ??
        topic.obj('icon')?.integer('color') ??
        info.integer('icon_color') ??
        topic.integer('icon_color');
    if (raw == null || raw == 0) return null;
    return Color(0xFF000000 | (raw & 0xFFFFFF));
  }

  void _openTopic(_ForumTopicEntry topic) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            TopicChatView(chat: _selectedChat, initialThreadId: topic.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final topics = _topicsByChat[_selectedChat.id] ?? const [];
    final loading = _loadingChats.contains(_selectedChat.id);
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          NavHeader(
            title: _selectedChat.title,
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Row(
              children: [
                _chatRail(c),
                Expanded(
                  child: loading && topics.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : topics.isEmpty
                      ? _empty(c)
                      : ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: topics.length,
                          separatorBuilder: (_, _) =>
                              const InsetDivider(leadingInset: 72),
                          itemBuilder: (_, index) => _TopicBrowserRow(
                            chat: _selectedChat,
                            topic: topics[index],
                            onTap: () => _openTopic(topics[index]),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chatRail(AppColors c) {
    return Container(
      width: 72,
      decoration: BoxDecoration(
        color: c.groupedBackground,
        border: Border(right: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 10),
        itemCount: _chats.length,
        itemBuilder: (_, index) {
          final chat = _chats[index];
          final selected = chat.id == _selectedChat.id;
          return _ForumChatRailItem(
            chat: chat,
            selected: selected,
            onTap: () => _selectChat(chat),
          );
        },
      ),
    );
  }

  Widget _empty(AppColors c) {
    return Center(
      child: Text(
        AppStringKeys.chatNoTopics.l10n(context),
        style: TextStyle(fontSize: 15, color: c.textSecondary),
      ),
    );
  }
}

class _ForumTopicEntry {
  const _ForumTopicEntry({
    required this.id,
    required this.name,
    this.lastMessage,
    this.unreadCount = 0,
    this.isMuted = false,
    this.iconCustomEmojiId = 0,
    this.iconColor,
  });

  final int id;
  final String name;
  final ChatMessage? lastMessage;
  final int unreadCount;
  final bool isMuted;
  final int iconCustomEmojiId;
  final Color? iconColor;
}

class _ForumChatRailItem extends StatelessWidget {
  const _ForumChatRailItem({
    required this.chat,
    required this.selected,
    required this.onTap,
  });

  final ChatSummary chat;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: chat.title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 72,
          height: 66,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: 18,
                bottom: 18,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 4,
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.brand : Colors.transparent,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(4),
                    ),
                  ),
                ),
              ),
              AnimatedScale(
                duration: const Duration(milliseconds: 180),
                scale: selected ? 1.06 : 1,
                child: PhotoAvatar(
                  title: chat.title,
                  photo: chat.photo,
                  size: 46,
                  square: chat.usesSquareAvatar,
                ),
              ),
              if (chat.unreadCount > 0)
                Positioned(
                  right: 7,
                  bottom: 6,
                  child: UnreadBadge(
                    count: chat.unreadCount,
                    muted: chat.isMuted,
                  ),
                ),
              if (chat.isMarkedUnread && chat.unreadCount <= 0)
                const Positioned(
                  right: 12,
                  bottom: 10,
                  child: RedDot(size: AppMetric.unreadDot),
                ),
              Positioned(
                bottom: 0,
                child: Container(
                  width: selected ? 18 : 0,
                  height: 3,
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.brand : Colors.transparent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: selected
                        ? Border.all(color: c.divider.withValues(alpha: 0.18))
                        : null,
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

class _TopicBrowserRow extends StatelessWidget {
  const _TopicBrowserRow({
    required this.chat,
    required this.topic,
    required this.onTap,
  });

  final ChatSummary chat;
  final _ForumTopicEntry topic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final message = topic.lastMessage;
    final preview = message?.text.trim() ?? '';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        color: c.background,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TopicEmojiIcon(topic: topic),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          topic.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      if (message != null)
                        Text(
                          DateText.listLabel(message.date),
                          style: TextStyle(fontSize: 13, color: c.textTertiary),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    preview.isEmpty
                        ? AppStrings.t(AppStringKeys.topicChatTopicTitle)
                        : preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: c.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    chat.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.textTertiary),
                  ),
                ],
              ),
            ),
            if (topic.unreadCount > 0) ...[
              const SizedBox(width: 10),
              UnreadBadge(count: topic.unreadCount, muted: topic.isMuted),
            ],
          ],
        ),
      ),
    );
  }
}

class _TopicEmojiIcon extends StatelessWidget {
  const _TopicEmojiIcon({required this.topic});

  final _ForumTopicEntry topic;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = (topic.iconColor ?? AppTheme.avatarColor(topic.name)).withValues(
      alpha: Theme.of(context).brightness == Brightness.dark ? 0.32 : 0.16,
    );
    final fg = topic.iconColor ?? AppTheme.brand;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: topic.iconCustomEmojiId != 0
          ? CustomEmojiView(id: topic.iconCustomEmojiId, size: 28)
          : AppIcon(
              HeroAppIcons.hashtag,
              size: 24,
              color: topic.isMuted ? c.textTertiary : fg,
            ),
    );
  }
}
