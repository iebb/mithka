//
//  topic_channels_view.dart
//
//  Root tab for forum/topic chats. This is intentionally separate from
//  MomentsView: 动态 remains stories/channel activity, while 频道 shows topic
//  feeds from chats that TDLib exposes as view_as_topics.
//

import 'package:flutter/material.dart';

import '../chats/chat_list_view_model.dart';
import '../components/photo_avatar.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/chat_membership.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import 'topic_chat_view.dart';
import 'topic_post_content.dart';

class TopicChannelsView extends StatefulWidget {
  const TopicChannelsView({super.key, this.onOpenDetail});

  final ValueChanged<Widget>? onOpenDetail;

  @override
  State<TopicChannelsView> createState() => _TopicChannelsViewState();
}

class _TopicPost {
  const _TopicPost({
    required this.chat,
    required this.topicName,
    required this.threadId,
    required this.message,
  });

  final ChatSummary chat;
  final String topicName;
  final int threadId;
  final ChatMessage message;
}

class _TopicChannelsViewState extends State<TopicChannelsView> {
  final _model = ChatListViewModel();
  final _postsByChat = <int, List<_TopicPost>>{};
  final _loadingChats = <int>{};
  final Map<int, bool> _joinedChatCache = {};
  bool _loading = true;
  bool _nonMutedOnly = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _model.addListener(_onModel);
    _model.onAppear();
  }

  @override
  void dispose() {
    _model.removeListener(_onModel);
    _model.dispose();
    super.dispose();
  }

  void _onModel() {
    if (!mounted) return;
    setState(() {});
    _loadTopics();
  }

  List<ChatSummary> get _topicChats {
    final byId = <int, ChatSummary>{};
    for (final chat in [..._model.chats, ..._model.archived]) {
      if (chat.isForum &&
          (_joinedChatCache[chat.id] ?? true) &&
          (!_nonMutedOnly || !chat.isMuted)) {
        byId[chat.id] = chat;
      }
    }
    return byId.values.toList();
  }

  List<_TopicPost> get _posts {
    final posts = _postsByChat.values.expand((items) => items).toList()
      ..sort((a, b) => b.message.date.compareTo(a.message.date));
    return posts;
  }

  Future<void> _loadTopics() async {
    final chats = _topicChats;
    if (chats.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    for (final chat in chats) {
      if (_postsByChat.containsKey(chat.id) ||
          _loadingChats.contains(chat.id)) {
        continue;
      }
      _loadingChats.add(chat.id);
      _loadTopicsForChat(chat, _loadGeneration);
    }
    if (mounted) setState(() => _loading = _loadingChats.isNotEmpty);
  }

  Future<void> _loadTopicsForChat(ChatSummary chat, int generation) async {
    try {
      if (!await _isJoinedChat(chat)) return;
      final response = await TdClient.shared.query({
        '@type': 'getForumTopics',
        'chat_id': chat.id,
        'query': '',
        'offset_date': 0,
        'offset_message_id': 0,
        'offset_forum_topic_id': 0,
        'limit': 40,
      });
      final topics =
          response.objects('topics') ?? const <Map<String, dynamic>>[];
      final posts = <_TopicPost>[];
      final seenMessages = <String>{};
      for (final topic in topics) {
        final info = topic.obj('info') ?? topic;
        final last = topic.obj('last_message');
        final parsedLast = last == null ? null : TDParse.message(last);
        final threadId =
            info.int64('message_thread_id') ??
            topic.int64('message_thread_id') ??
            parsedLast?.id;
        final messages = await _recentRootPostsForTopic(
          chat.id,
          threadId,
          parsedLast,
        );
        final topicName = info.str('name') ?? topic.str('name') ?? chat.title;
        for (final message in messages) {
          if (message.isService) continue;
          final key = '${chat.id}:${message.id}';
          if (!seenMessages.add(key)) continue;
          posts.add(
            _TopicPost(
              chat: chat,
              topicName: topicName,
              threadId: threadId ?? message.id,
              message: message,
            ),
          );
        }
      }
      if (generation != _loadGeneration) return;
      _postsByChat[chat.id] = posts;
    } catch (_) {
      if (generation != _loadGeneration) return;
      _postsByChat[chat.id] = const [];
    } finally {
      if (generation == _loadGeneration) {
        _loadingChats.remove(chat.id);
        if (mounted) setState(() => _loading = _loadingChats.isNotEmpty);
      }
    }
  }

  Future<bool> _isJoinedChat(ChatSummary chat) async {
    final cached = _joinedChatCache[chat.id];
    if (cached != null) return cached;
    final joined = await isJoinedGroupOrChannelChat(chat.id);
    _joinedChatCache[chat.id] = joined;
    if (!joined) {
      _postsByChat.remove(chat.id);
      if (mounted) setState(() {});
    }
    return joined;
  }

  Future<List<ChatMessage>> _recentRootPostsForTopic(
    int chatId,
    int? threadId,
    ChatMessage? fallback,
  ) async {
    if (threadId == null) {
      return fallback == null || fallback.isService ? const [] : [fallback];
    }
    try {
      final response = await TdClient.shared.query({
        '@type': 'getMessageThreadHistory',
        'chat_id': chatId,
        'message_id': threadId,
        'from_message_id': 0,
        'offset': 0,
        'limit': 30,
      });
      final messages =
          (response.objects('messages') ?? const <Map<String, dynamic>>[])
              .map(TDParse.message)
              .whereType<ChatMessage>()
              .where((message) => !message.isService)
              .where((message) => message.replyToMessageId == null)
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));
      if (messages.isNotEmpty) return messages;
    } catch (_) {
      // Fall through to the topic's last message as a best-effort preview.
    }
    return fallback == null || fallback.isService ? const [] : [fallback];
  }

  void _toggleNonMutedOnly() {
    setState(() {
      _nonMutedOnly = !_nonMutedOnly;
      _loadGeneration += 1;
      _postsByChat.clear();
      _loadingChats.clear();
      _loading = true;
    });
    _loadTopics();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final posts = _posts;
    return Container(
      color: c.background,
      child: Column(
        children: [
          NavHeader(
            title: '频道',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleNonMutedOnly,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
                    child: Icon(
                      _nonMutedOnly
                          ? FontAwesomeIcons.solidBell.data
                          : FontAwesomeIcons.bellSlash.data,
                      size: 24,
                      color: _nonMutedOnly ? AppTheme.brand : c.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: posts.isEmpty
                ? _empty()
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: posts.length,
                    separatorBuilder: (_, _) =>
                        const InsetDivider(leadingInset: 0),
                    itemBuilder: (context, index) => _TopicPostRow(
                      post: posts[index],
                      onOpenDetail: widget.onOpenDetail,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    final c = context.colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _loading
              ? const CircularProgressIndicator()
              : FaIcon(
                  FontAwesomeIcons.hashtag,
                  size: 46,
                  color: AppTheme.brand,
                ),
          const SizedBox(height: 12),
          Text(
            (_loading ? '加载频道…' : '暂无话题频道').l10n(context),
            style: TextStyle(fontSize: 15, color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _TopicPostRow extends StatelessWidget {
  const _TopicPostRow({required this.post, this.onOpenDetail});

  final _TopicPost post;
  final ValueChanged<Widget>? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = _displayText;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final detail = TopicChatView(
          chat: post.chat,
          initialThreadId: post.threadId,
          initialMessageId: post.message.id,
          showBackButton: onOpenDetail == null,
        );
        if (onOpenDetail != null) {
          onOpenDetail!(detail);
          return;
        }
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => detail));
      },
      child: Container(
        color: c.background,
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PhotoAvatar(
                  title: post.chat.title,
                  photo: post.chat.photo,
                  size: 42,
                  square: true,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.topicName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '# ${post.chat.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: c.textTertiary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_hasRenderableContent) ...[
              const SizedBox(height: 12),
              TopicPostContent(
                chatId: post.chat.id,
                message: post.message,
                text: text,
                maxTextLines: 6,
                textOverflow: TextOverflow.ellipsis,
                textStyle: TextStyle(
                  fontSize: 17,
                  height: 1.35,
                  color: c.textPrimary,
                ),
              ),
            ],
            const SizedBox(height: 12),
            _TopicStats(message: post.message),
          ],
        ),
      ),
    );
  }

  String get _displayText {
    final text = post.message.text.trim();
    if (text.startsWith('[') && text.endsWith(']')) return '';
    if (post.message.document != null && text.startsWith('[文件]')) return '';
    return text;
  }

  bool get _hasRenderableContent =>
      _displayText.isNotEmpty ||
      post.message.image != null ||
      post.message.document != null ||
      post.message.buttonRows.isNotEmpty;
}

class _TopicStats extends StatelessWidget {
  const _TopicStats({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reactionCount = message.reactions.fold<int>(
      0,
      (sum, reaction) => sum + reaction.count,
    );
    return Row(
      children: [
        Text(
          DateText.listLabel(message.date),
          style: TextStyle(fontSize: 14, color: c.textTertiary),
        ),
        const Spacer(),
        FaIcon(FontAwesomeIcons.thumbsUp, size: 24, color: c.textPrimary),
        const SizedBox(width: 5),
        Text(
          reactionCount == 0 ? '' : '$reactionCount',
          style: TextStyle(fontSize: 15, color: c.textPrimary),
        ),
        const SizedBox(width: 24),
        FaIcon(FontAwesomeIcons.comment, size: 24, color: c.textPrimary),
        const SizedBox(width: 5),
        Text(
          message.commentCount == 0 ? '' : '${message.commentCount}',
          style: TextStyle(fontSize: 15, color: c.textPrimary),
        ),
        const SizedBox(width: 24),
        FaIcon(FontAwesomeIcons.share, size: 27, color: c.textPrimary),
      ],
    );
  }
}
