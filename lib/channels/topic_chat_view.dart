//
//  topic_chat_view.dart
//
//  Forum/topic chat surface. This is not the normal Telegram chat screen:
//  it presents a topic tab strip and post feed for forum supergroups and
//  private bot chats whose userTypeBot advertises has_topics.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_navigator.dart';
import '../app/chat_pane.dart';
import '../app/ipad_window_chrome.dart';
import '../chat/chat_members_view.dart';
import '../chat/chat_picker_view.dart';
import '../chat/chat_view.dart';
import '../chat/custom_emoji.dart';
import '../chat/forward_options.dart';
import '../chat/group_remark_controller.dart';
import '../chat/message_replies_sheet.dart';
import '../chat/outgoing_attachment.dart';
import '../chat/rich_text_composer_view.dart';
import '../chat/rich_text_format.dart';
import '../components/app_icons.dart';
import '../components/confirm_dialog.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../notifications/notification_settings_payload.dart';
import '../profile/profile_icon_picker_view.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import '../theme/theme_controller.dart';
import 'topic_list_host.dart';
import 'topic_list_row.dart';
import 'topic_navigation.dart';
import 'topic_post_content.dart';

/// Keeps a forum browser suspended while its topic route is replaced by other
/// views in the same conversation. Only the newest route can reveal it.
class TopicChatRouteSession {
  final _browserRevealed = Completer<void>();
  var _routeGeneration = 0;

  Future<void> get whenBrowserRevealed => _browserRevealed.future;

  void trackRoute<T>(Future<T> Function() openRoute) {
    final generation = ++_routeGeneration;
    final route = openRoute();
    unawaited(_completeWhenCurrentRouteCloses(generation, route));
  }

  Future<void> _completeWhenCurrentRouteCloses<T>(
    int generation,
    Future<T> route,
  ) async {
    try {
      await route;
    } catch (_) {
      // A failed route still uncovers the browser; refresh its cached topics.
    }
    if (generation == _routeGeneration && !_browserRevealed.isCompleted) {
      _browserRevealed.complete();
    }
  }
}

void _replaceTrackedChatWithTopic(
  BuildContext context,
  ChatSummary chat,
  TopicChatRouteSession routeSession,
  int? threadId,
) {
  routeSession.trackRoute(
    () => replaceWithAppChatRoute<void, void>(
      context,
      AppChatPageRoute<void>(
        builder: (_) => ChatView(
          chatId: chat.id,
          title: chat.title,
          forumTopicId: threadId,
        ),
      ),
    ),
  );
}

class TopicChatView extends StatefulWidget {
  const TopicChatView({
    super.key,
    required this.chat,
    this.initialThreadId,
    this.initialMessageId,
    this.hasForumTabs = false,
    this.showBackButton = true,
    this.headerHeight = 48,
    this.headerColor,
    this.chatRouteBelow = false,
    this.onOpenChatView,
    this.onBack,
    this.routeSession,
    this.query,
  });

  final ChatSummary chat;
  final int? initialThreadId;
  final int? initialMessageId;
  final bool hasForumTabs;
  final bool showBackButton;
  final double headerHeight;
  final Color? headerColor;
  final bool chatRouteBelow;
  final VoidCallback? onOpenChatView;
  final VoidCallback? onBack;
  final TopicChatRouteSession? routeSession;
  @visibleForTesting
  final ForumTopicMessageQuery? query;

  @override
  State<TopicChatView> createState() => _TopicChatViewState();
}

class _ForumTopic {
  const _ForumTopic({
    required this.id,
    required this.name,
    required this.lastMessage,
    required this.isPinned,
    required this.isMuted,
    required this.unreadCount,
    required this.iconCustomEmojiId,
    required this.iconColor,
    required this.lastMessageIsSynthetic,
    this.hasRealLastMessage = false,
    this.isGeneral = false,
    this.isClosed = false,
    this.creatorId = 0,
  });

  final int id;
  final String name;
  final ChatMessage lastMessage;
  final bool isPinned;
  final bool isMuted;
  final int unreadCount;
  final int iconCustomEmojiId;
  final Color? iconColor;
  final bool lastMessageIsSynthetic;

  /// True when getForumTopics carried an actual last message (including a
  /// service one). The chat-list-style preview only renders for real
  /// messages; the synthetic fallback's text is the topic name itself.
  final bool hasRealLastMessage;

  /// The General topic: keeps the chat avatar, and its name cannot change.
  final bool isGeneral;
  final bool isClosed;

  /// Topic creator's user id, 0 when unknown. The creator may delete their
  /// own topic even without can_manage_topics (TDLib enforces the rest).
  final int creatorId;

  _ForumTopic copyWith({
    String? name,
    ChatMessage? lastMessage,
    bool? lastMessageIsSynthetic,
    bool? hasRealLastMessage,
    bool? isPinned,
    bool? isMuted,
    bool? isClosed,
    int? unreadCount,
    int? iconCustomEmojiId,
    Color? iconColor,
  }) => _ForumTopic(
    id: id,
    name: name ?? this.name,
    lastMessage: lastMessage ?? this.lastMessage,
    isPinned: isPinned ?? this.isPinned,
    isMuted: isMuted ?? this.isMuted,
    unreadCount: unreadCount ?? this.unreadCount,
    iconCustomEmojiId: iconCustomEmojiId ?? this.iconCustomEmojiId,
    iconColor: iconColor ?? this.iconColor,
    lastMessageIsSynthetic:
        lastMessageIsSynthetic ?? this.lastMessageIsSynthetic,
    hasRealLastMessage: hasRealLastMessage ?? this.hasRealLastMessage,
    isGeneral: isGeneral,
    isClosed: isClosed ?? this.isClosed,
    creatorId: creatorId,
  );
}

class _TopicPost {
  const _TopicPost({
    required this.topic,
    required this.message,
    required this.isSynthetic,
  });

  final _ForumTopic topic;
  final ChatMessage message;
  final bool isSynthetic;
}

const _topicHeartReactions = {'❤️', '❤'};
const _topicLikeReactionCandidates = ['❤️', '❤', '👍'];

bool _isTopicLikeReaction(MessageReaction reaction) {
  final emoji = reaction.emoji;
  return emoji != null && _topicLikeReactionCandidates.contains(emoji);
}

bool isReportableForumTopicMessage(
  ChatMessage message, {
  required bool isSynthetic,
}) {
  return !isSynthetic &&
      message.id > 0 &&
      !message.isOutgoing &&
      !message.isService;
}

bool showsGroupTopicControls(ChatSummary chat) => chat.isForum;

bool canComposeInTopicSurface({
  required ChatSummary chat,
  required int? forumTopicId,
}) {
  if (chat.isForum) return true;
  return chat.supportsBotTopics && forumTopicId != null;
}

List<int> takeNewlyVisibleForumTopicMessageIds({
  required Rect viewport,
  required Map<int, Rect> messageBounds,
  required Set<int> alreadyReported,
}) {
  final visible = <int>[];
  for (final entry in messageBounds.entries) {
    if (alreadyReported.contains(entry.key) ||
        !entry.value.overlaps(viewport)) {
      continue;
    }
    alreadyReported.add(entry.key);
    visible.add(entry.key);
  }
  return visible;
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

typedef ForumTopicMessageQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

const forumTopicInitialMessageAlignment = 0.15;

Future<Map<String, dynamic>> queryForumTopicHistoryWithFallback({
  required ForumTopicMessageQuery query,
  required int chatId,
  required int forumTopicId,
  required int fromMessageId,
  required int offset,
  required int limit,
}) async {
  try {
    return await query({
      '@type': 'getForumTopicHistory',
      'chat_id': chatId,
      'forum_topic_id': forumTopicId,
      'from_message_id': fromMessageId,
      'offset': offset,
      'limit': limit,
    });
  } catch (_) {
    return query({
      '@type': 'getMessageThreadHistory',
      'chat_id': chatId,
      'message_id': forumTopicId,
      'from_message_id': fromMessageId,
      'offset': offset,
      'limit': limit,
    });
  }
}

Map<String, dynamic> forumTopicScopedSendRequest({
  required Map<String, dynamic> request,
  required int forumTopicId,
}) {
  if (forumTopicId == 0) {
    throw ArgumentError.value(forumTopicId, 'forumTopicId');
  }
  return Map<String, dynamic>.from(request)
    ..remove('message_thread_id')
    ..['topic_id'] = {
      '@type': 'messageTopicForum',
      'forum_topic_id': forumTopicId,
    };
}

Future<Map<String, dynamic>> sendScopedForumTopicMessage({
  required ForumTopicMessageQuery query,
  required Map<String, dynamic> request,
}) {
  final topic = request.obj('topic_id');
  final topicId = topic?.integer('forum_topic_id');
  if (topic?.type != 'messageTopicForum' || topicId == null || topicId == 0) {
    throw StateError('FORUM_TOPIC_REQUIRED');
  }
  return query(request);
}

class _SenderInfo {
  const _SenderInfo({required this.name, this.photo});

  final String name;
  final TdFileRef? photo;
}

class _TopicChatViewState extends State<TopicChatView> {
  final _scroll = ScrollController();
  final _topicViewportKey = GlobalKey();
  final _postVisibilityKeys = <int, GlobalKey>{};
  final _reportedVisibleMessageIds = <int>{};
  final _input = TextEditingController();
  final _topics = <_ForumTopic>[];
  final _topicMessages = <int, List<ChatMessage>>{};
  final _loadingThreads = <int>{};
  final _senderCache = <int, _SenderInfo>{};
  bool _loading = true;
  bool _visibleMessageUpdateScheduled = false;
  bool _initialMessagePositionScheduled = false;
  int? _selectedThreadId;
  int? _pendingInitialMessageId;
  late bool _hasForumTabs = widget.hasForumTabs;
  final int _accountClientId = TdClient.shared.activeClientId;
  int? _supergroupId;
  int _topicLayoutRevision = 0;
  StreamSubscription<Map<String, dynamic>>? _supergroupUpdates;
  StreamSubscription<Map<String, dynamic>>? _topicUpdates;
  TopicListHost? _topicListHost;
  TopicListAttachment? _publishedAttachment;
  bool _topicListOverlaid = false;

  // Topic moderation rights, probed once per surface. iOS shows create/edit/
  // delete affordances only while the account actually holds them.
  int? _meUserId;
  bool _canCreateTopics = false;
  bool _canManageTopics = false;
  bool _canDeleteMessages = false;

  @override
  void initState() {
    super.initState();
    _selectedThreadId = widget.initialThreadId;
    _pendingInitialMessageId = widget.initialMessageId;
    _scroll.addListener(_scheduleVisibleMessageUpdate);
    if (widget.chat.isForum) {
      _supergroupUpdates = TdClient.shared.updatesOf('updateSupergroup').listen(
        (update) {
          if (!mounted || TdClient.shared.activeClientId != _accountClientId) {
            return;
          }
          final group = update.obj('supergroup');
          if (_supergroupId == null || group?.int64('id') != _supergroupId) {
            return;
          }
          ++_topicLayoutRevision;
          setState(
            () => _hasForumTabs = group?.boolean('has_forum_tabs') ?? false,
          );
          _syncTopicListHost();
        },
      );
      unawaited(_loadTopicLayout());
      unawaited(_loadTopicModerationRights());
      _topicUpdates = TdClient.shared
          .updatesOfAny(const [
            'updateNewMessage',
            'updateForumTopic',
            'updateForumTopicInfo',
            'updateDeleteMessages',
          ])
          .listen(_applyTopicUpdate);
    }
    _loadTopics();
  }

  /// Reads whether this account may create and manage topics in the forum.
  ///
  /// TDLib: creating needs the can_manage_topics administrator right or the
  /// can_create_topics member right; pinning/editing/closing need
  /// can_manage_topics; deleting needs can_delete_messages unless the user
  /// created the topic. A failed probe leaves everything hidden, which is
  /// the safe direction — the server still enforces the real rule.
  Future<void> _loadTopicModerationRights() async {
    try {
      final chat = await _query({
        '@type': 'getChat',
        'chat_id': widget.chat.id,
      });
      if (!mounted) return;
      final canCreate =
          chat.obj('permissions')?.boolean('can_create_topics') ?? false;
      int? meId;
      bool canManage = false;
      bool canDelete = false;
      try {
        final me = await _query({'@type': 'getMe'});
        meId = me.int64('id');
        if (meId != null) {
          final member = await _query({
            '@type': 'getChatMember',
            'chat_id': widget.chat.id,
            'member_id': {'@type': 'messageSenderUser', 'user_id': meId},
          });
          final status = member.obj('status');
          switch (status?.type) {
            case 'chatMemberStatusCreator':
              canManage = true;
              canDelete = true;
            case 'chatMemberStatusAdministrator':
              final rights = status?.obj('rights');
              canManage = rights?.boolean('can_manage_topics') ?? false;
              canDelete = rights?.boolean('can_delete_messages') ?? false;
          }
        }
      } catch (_) {
        // Keep the member-right answer; moderation stays hidden.
      }
      if (!mounted) return;
      setState(() {
        _meUserId = meId;
        _canCreateTopics = canCreate || canManage;
        _canManageTopics = canManage;
        _canDeleteMessages = canDelete;
      });
      _syncTopicListHost();
    } catch (_) {
      // Offline or unsupported: no destructive affordances.
    }
  }

  /// Whether this account may delete [topic]: topic creators may delete
  /// their own topic, and admins need can_delete_messages or can_manage_topics.
  bool _canDeleteTopic(_ForumTopic topic) =>
      !topic.isGeneral &&
      (_canManageTopics ||
          _canDeleteMessages ||
          (_meUserId != null && topic.creatorId == _meUserId));

  /// Folds live updates into the topic list so previews, badges, pins and
  /// renames move without a full getForumTopics round-trip.
  void _applyTopicUpdate(Map<String, dynamic> update) {
    if (!mounted || TdClient.shared.activeClientId != _accountClientId) {
      return;
    }
    if (_topics.isEmpty) return;
    final chatId = widget.chat.id;
    switch (update.type) {
      case 'updateNewMessage':
        final raw = update.obj('message');
        if (raw?.int64('chat_id') != chatId) return;
        final message = TDParse.message(raw!);
        if (message == null) return;
        final topicRef = raw.obj('topic_id');
        final topicId = topicRef?.type == 'messageTopicForum'
            ? topicRef?.integer('forum_topic_id')
            : 1;
        if (topicId == null) return;
        final index = _topics.indexWhere((topic) => topic.id == topicId);
        if (index < 0) return;
        final topic = _topics[index];
        if (topic.hasRealLastMessage &&
            (message.date < topic.lastMessage.date ||
                message.id < topic.lastMessage.id)) {
          return;
        }
        _topics[index] = topic.copyWith(
          lastMessage: message,
          lastMessageIsSynthetic: message.isService,
          hasRealLastMessage: true,
        );
        // The post feed renders the topic's fallback message while history
        // is not loaded; keep that fallback in step with the row preview.
        final loaded = _topicMessages[topicId];
        if (loaded != null &&
            loaded.length == 1 &&
            identical(loaded.first, topic.lastMessage)) {
          _topicMessages[topicId] = [message];
        }
        unawaited(_resolvePreviewSenders([message]));
        _rebuildPosts();
        setState(() {});
        _syncTopicListHost();

      case 'updateForumTopic':
        if (update.int64('chat_id') != chatId) return;
        final topicId = update.integer('forum_topic_id');
        if (topicId == null) return;
        final index = _topics.indexWhere((topic) => topic.id == topicId);
        if (index < 0) return;
        final settings = update.obj('notification_settings');
        _topics[index] = _topics[index].copyWith(
          isPinned: update.boolean('is_pinned'),
          isMuted: settings == null
              ? null
              : (settings.integer('mute_for') ?? 0) > 0,
        );
        setState(() {});
        _syncTopicListHost();

      case 'updateForumTopicInfo':
        final info = update.obj('info');
        if (info?.int64('chat_id') != chatId) return;
        final topicId = info?.integer('forum_topic_id');
        final name = info?.str('name');
        if (topicId == null || name == null || name.isEmpty) return;
        final index = _topics.indexWhere((topic) => topic.id == topicId);
        if (index < 0) return;
        final icon = info?.obj('icon');
        _topics[index] = _topics[index].copyWith(
          name: name,
          isClosed: info?.boolean('is_closed'),
          iconCustomEmojiId: icon?.int64('custom_emoji_id'),
          iconColor: icon == null
              ? null
              : _iconColorFromRaw(icon.integer('color')),
        );
        setState(() {});
        _syncTopicListHost();

      case 'updateDeleteMessages':
        if (update.int64('chat_id') != chatId) return;
        // A deleted last message leaves a stale preview; a refresh is cheap
        // enough here because deletions in forum lists are rare.
        unawaited(_loadTopics());
    }
  }

  Color? _iconColorFromRaw(int? raw) {
    if (raw == null || raw == 0) return null;
    return Color(0xFF000000 | (raw & 0xFFFFFF));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTopicListHost();
  }

  /// Wide split shells overlay this view's topic list on the chat list
  /// column, so the in-pane rail stays out of the conversation there.
  void _syncTopicListHost() {
    final host = context.read<TopicListHost?>();
    final overlaid =
        host != null &&
        !_hasForumTabs &&
        TopicListPlacementScope.of(context) == TopicListPlacement.sidebar;
    _topicListOverlaid = overlaid;
    _topicListHost = overlaid ? host : null;
    final attachment = overlaid ? _topicListAttachment() : null;
    final previous = _publishedAttachment;
    if (attachment != null &&
        previous != null &&
        previous.sameContent(attachment)) {
      return;
    }
    _publishedAttachment = attachment;
    // The shell's sidebar listens to the host; publishing mid-build would
    // mark an already-built ancestor dirty.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attachment != null) {
        if (mounted) host?.publish(attachment);
        return;
      }
      if (previous != null) host?.unpublish(previous);
    });
  }

  TopicListAttachment _topicListAttachment() => TopicListAttachment(
    chatId: widget.chat.id,
    title: widget.chat.title,
    usesSquareAvatar: widget.chat.usesSquareAvatar,
    photo: widget.chat.photo,
    topics: [for (final topic in _topics) _navigationItem(topic)],
    selectedTopicId: _selectedThreadId,
    onSelect: _selectTopic,
    onCreateTopic: _canCreateTopics ? _openCreateTopicDialog : null,
    onTopicMenu: _showTopicRowMenu,
  );

  Future<Map<String, dynamic>> _query(Map<String, dynamic> request) =>
      widget.query?.call(request) ??
      TdClient.shared.queryTo(request, _accountClientId);

  Future<void> _loadTopicLayout() async {
    try {
      final chat = await _query({
        '@type': 'getChat',
        'chat_id': widget.chat.id,
      });
      if (!mounted) return;
      _supergroupId = chat.obj('type')?.int64('supergroup_id');
      if (_supergroupId == null) return;
      final revision = _topicLayoutRevision;
      final group = await _query({
        '@type': 'getSupergroup',
        'supergroup_id': _supergroupId,
      });
      if (!mounted || revision != _topicLayoutRevision) return;
      setState(() => _hasForumTabs = group.boolean('has_forum_tabs') ?? false);
      _syncTopicListHost();
    } catch (_) {
      // Keep the entry snapshot while offline or while metadata is unavailable.
    }
  }

  @override
  void dispose() {
    final host = _topicListHost;
    final published = _publishedAttachment;
    if (host != null && published != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => host.unpublish(published),
      );
    }
    _supergroupUpdates?.cancel();
    _topicUpdates?.cancel();
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<void> _loadTopics() async {
    // Callers clear _topicMessages immediately before this; refresh the posts
    // here so the reload frame never renders against the stale list.
    setState(() {
      _loading = true;
      _rebuildPosts();
    });
    try {
      final response = await _query({
        '@type': 'getForumTopics',
        'chat_id': widget.chat.id,
        'query': '',
        'offset_date': 0,
        'offset_message_id': 0,
        'offset_forum_topic_id': 0,
        'limit': 80,
      });
      if (!mounted) return;
      final rawTopics =
          response.objects('topics') ?? const <Map<String, dynamic>>[];
      final next = <_ForumTopic>[];
      for (final topic in rawTopics) {
        final info = topic.obj('info') ?? topic;
        final last = topic.obj('last_message');
        final message = last == null ? null : TDParse.message(last);
        final id = _topicId(topic, info) ?? message?.id;
        if (id == null || id == 0) continue;
        final isServiceLast = message?.isService == true;
        final fallbackDate = last?.integer('date');
        next.add(
          _ForumTopic(
            id: id,
            name:
                info.str('name') ??
                topic.str('name') ??
                AppStringKeys.topicChatTopicTitle,
            lastMessage:
                message ??
                _fallbackTopicMessage(
                  id,
                  info,
                  topic,
                  fallbackDate: fallbackDate,
                ),
            isPinned: topic.boolean('is_pinned') ?? false,
            isMuted:
                (topic.obj('notification_settings')?.integer('mute_for') ?? 0) >
                0,
            unreadCount: _topicUnreadCount(topic, info),
            iconCustomEmojiId: _topicCustomEmojiId(topic, info),
            iconColor: _topicIconColor(topic, info),
            lastMessageIsSynthetic: message == null || isServiceLast,
            hasRealLastMessage: message != null,
            isGeneral:
                info.boolean('is_general') == true ||
                topic.boolean('is_general') == true,
            isClosed:
                info.boolean('is_closed') == true ||
                topic.boolean('is_closed') == true,
            creatorId: _topicCreatorId(info),
          ),
        );
      }
      next.sort((a, b) => b.lastMessage.date.compareTo(a.lastMessage.date));
      _topics
        ..clear()
        ..addAll(next);
      if (_selectedThreadId != null &&
          !_topics.any((topic) => topic.id == _selectedThreadId)) {
        _selectedThreadId = null;
      }
      _rebuildPosts();
      await _loadVisibleThreads();
      unawaited(
        _resolvePreviewSenders([
          for (final topic in next)
            if (topic.hasRealLastMessage) topic.lastMessage,
        ]),
      );
    } catch (_) {
      // A failed topic refresh must not surface as an uncaught navigation error.
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _syncTopicListHost();
      }
    }
  }

  Future<void> _loadVisibleThreads() async {
    final selected = _selectedThreadId;
    final threads = selected == null
        ? _topics.take(12)
        : _topics.where((topic) => topic.id == selected);
    await Future.wait(threads.map(_loadThreadMessages));
  }

  Future<void> _loadThreadMessages(_ForumTopic topic) async {
    if (_topicMessages.containsKey(topic.id) ||
        _loadingThreads.contains(topic.id)) {
      return;
    }
    _loadingThreads.add(topic.id);
    try {
      final targetMessageId = topic.id == _selectedThreadId
          ? _pendingInitialMessageId
          : null;
      final response = await _queryForumTopicHistory(
        topic.id,
        _selectedThreadId == null ? 6 : 40,
        fromMessageId: targetMessageId ?? 0,
        offset: targetMessageId == null ? 0 : -20,
      );
      final messages =
          (response.objects('messages') ?? const <Map<String, dynamic>>[])
              .map(TDParse.message)
              .whereType<ChatMessage>()
              .where((message) => !message.isService)
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));
      _topicMessages[topic.id] = messages.isEmpty
          ? [topic.lastMessage]
          : messages;
      unawaited(_resolveSenders(_topicMessages[topic.id]!));
    } catch (_) {
      _topicMessages[topic.id] = [topic.lastMessage];
      unawaited(_resolveSenders(_topicMessages[topic.id]!));
    } finally {
      _loadingThreads.remove(topic.id);
      _rebuildPosts();
      if (mounted) setState(() {});
    }
  }

  Future<Map<String, dynamic>> _queryForumTopicHistory(
    int forumTopicId,
    int limit, {
    int fromMessageId = 0,
    int offset = 0,
  }) => queryForumTopicHistoryWithFallback(
    query: _query,
    chatId: widget.chat.id,
    forumTopicId: forumTopicId,
    fromMessageId: fromMessageId,
    offset: offset,
    limit: limit,
  );

  void _selectTopic(int? threadId) {
    setState(() {
      _pendingInitialMessageId = null;
      _selectedThreadId = threadId;
      _rebuildPosts();
    });
    _syncTopicListHost();
    _loadVisibleThreads();
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
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

  int? _topicId(Map<String, dynamic> topic, Map<String, dynamic> info) {
    return info.integer('forum_topic_id') ??
        topic.integer('forum_topic_id') ??
        info.int64('message_thread_id') ??
        topic.int64('message_thread_id');
  }

  ChatMessage _fallbackTopicMessage(
    int id,
    Map<String, dynamic> info,
    Map<String, dynamic> topic, {
    int? fallbackDate,
  }) {
    final created =
        info.integer('creation_date') ?? topic.integer('creation_date') ?? 0;
    return ChatMessage(
      id: id,
      text:
          info.str('name') ??
          topic.str('name') ??
          AppStrings.t(AppStringKeys.topicChatTopicTitle),
      date: fallbackDate ?? created,
      isOutgoing: false,
      chatId: widget.chat.id,
    );
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

  int _topicCreatorId(Map<String, dynamic> info) {
    final creator = info.obj('creator_id');
    if (creator?.type == 'messageSenderUser') {
      return creator?.int64('user_id') ?? 0;
    }
    return 0;
  }

  /// Resolves preview sender names through the same cache the post rows use,
  /// so the chat-list-style topic rows can draw the "Alice: …" prefix.
  Future<void> _resolvePreviewSenders(List<ChatMessage> messages) async {
    final missing = messages
        .where((message) => !message.isOutgoing)
        .map((message) => message.senderId)
        .whereType<int>()
        .where((id) => id != 0 && !_senderCache.containsKey(id))
        .toSet();
    if (missing.isEmpty) {
      if (mounted) setState(() {});
      return;
    }
    for (final id in missing) {
      try {
        if (id > 0) {
          final user = await _query({'@type': 'getUser', 'user_id': id});
          _senderCache[id] = _SenderInfo(
            name: TDParse.userName(user),
            photo: TDParse.smallPhoto(user.obj('profile_photo')),
          );
        } else {
          final chat = await _query({'@type': 'getChat', 'chat_id': id});
          _senderCache[id] = _SenderInfo(
            name: chat.str('title') ?? AppStringKeys.topicChatUsers,
            photo: TDParse.smallPhoto(chat.obj('photo')),
          );
        }
      } catch (_) {
        // An unresolved sender simply omits the preview prefix.
      }
    }
    if (mounted) {
      setState(() {});
      _syncTopicListHost();
    }
  }

  /// The chat-list-style preview for a topic: the sender prefix source and
  /// the message text with media/service placeholders (composed by
  /// TDParse.messageText through TDParse.message). Synthetic fallback
  /// messages render no preview at all — their text is the topic's own name.
  String? _topicPreviewSender(_ForumTopic topic) {
    final message = topic.lastMessage;
    if (message.isOutgoing) {
      return AppStrings.t(AppStringKeys.chatMeLabel);
    }
    final senderId = message.senderId;
    if (senderId == null || senderId == 0) {
      return message.senderName?.trim().isNotEmpty == true
          ? message.senderName!.trim()
          : null;
    }
    final cached = _senderCache[senderId];
    if (cached != null && cached.name.trim().isNotEmpty) {
      return cached.name.trim();
    }
    final name = message.senderName?.trim();
    return name != null && name.isNotEmpty ? name : null;
  }

  TopicNavigationItem _navigationItem(_ForumTopic topic) => TopicNavigationItem(
    id: topic.id,
    name: topic.name,
    iconCustomEmojiId: topic.iconCustomEmojiId,
    iconColor: topic.iconColor?.toARGB32() ?? 0,
    unreadCount: topic.unreadCount,
    isMuted: topic.isMuted,
    isPinned: topic.isPinned,
    isGeneral: topic.isGeneral,
    isClosed: topic.isClosed,
    lastPreview: topic.hasRealLastMessage ? topic.lastMessage.text.trim() : '',
    lastSender: topic.hasRealLastMessage ? _topicPreviewSender(topic) : null,
    lastMessageDate: topic.hasRealLastMessage ? topic.lastMessage.date : 0,
  );

  // MARK: - Topic moderation (Telegram iOS parity)

  static const _topicIconColors = [
    0x6FB9F0,
    0xFFD67E,
    0xCB86DB,
    0x8EEE98,
    0xFF93B2,
    0xFB6F5F,
  ];

  _ForumTopic? _topicById(int? id) {
    if (id == null) return null;
    for (final topic in _topics) {
      if (topic.id == id) return topic;
    }
    return null;
  }

  /// Telegram iOS offers topic creation right from the topic list.
  Future<void> _openCreateTopicDialog() async {
    final draft = await showDialog<_TopicDraft>(
      context: context,
      builder: (dialogContext) => _TopicDraftDialog(
        title: AppStrings.t(AppStringKeys.groupAdministrationNewTopic),
        initialName: '',
        initialColor:
            _topicIconColors[_topics.length % _topicIconColors.length],
        initialCustomEmojiId: 0,
        canChangeColor: true,
      ),
    );
    if (!mounted || draft == null || draft.name.isEmpty) return;
    try {
      final created = await _query({
        '@type': 'createForumTopic',
        'chat_id': widget.chat.id,
        'name': draft.name,
        'is_name_implicit': false,
        'icon': {
          '@type': 'forumTopicIcon',
          'color': draft.color,
          'custom_emoji_id': draft.customEmojiId,
        },
      });
      _topicMessages.clear();
      await _loadTopics();
      // Open the fresh topic the way iOS does after creation.
      final newId = created.integer('forum_topic_id');
      if (mounted && newId != null && newId != 0) _selectTopic(newId);
    } catch (error) {
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(
          AppStringKeys.groupAdministrationCouldnTCreateTopicValue1,
          {'value1': error},
        ),
      );
    }
  }

  Future<void> _editTopic(_ForumTopic topic) async {
    if (topic.isGeneral) return;
    final draft = await showDialog<_TopicDraft>(
      context: context,
      builder: (dialogContext) => _TopicDraftDialog(
        title: AppStrings.t(AppStringKeys.groupAdministrationEditTopic),
        initialName: topic.name,
        initialColor: topic.iconColor?.toARGB32() ?? _topicIconColors.first,
        initialCustomEmojiId: topic.iconCustomEmojiId,
        canChangeColor: false,
      ),
    );
    if (!mounted || draft == null || draft.name.isEmpty) return;
    try {
      await _query({
        '@type': 'editForumTopic',
        'chat_id': widget.chat.id,
        'forum_topic_id': topic.id,
        'name': draft.name,
        'edit_icon_custom_emoji': true,
        'icon_custom_emoji_id': draft.customEmojiId,
      });
      await _loadTopics();
    } catch (error) {
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.groupAdministrationCouldnTEditTopicValue1, {
          'value1': error,
        }),
      );
    }
  }

  Future<void> _deleteTopic(_ForumTopic topic) async {
    if (topic.isGeneral || !_canDeleteTopic(topic)) return;
    final ok = await confirmDialog(
      context,
      title: AppStrings.t(
        AppStringKeys.groupAdministrationDeleteTopicAndMessages,
        {'value1': topic.name},
      ),
      confirmText: AppStringKeys.chatDelete,
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await _query({
        '@type': 'deleteForumTopic',
        'chat_id': widget.chat.id,
        'forum_topic_id': topic.id,
      });
      if (_selectedThreadId == topic.id) {
        _selectTopic(null);
      }
      _topicMessages.remove(topic.id);
      await _loadTopics();
    } catch (error) {
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(
          AppStringKeys.groupAdministrationCouldnTDeleteTopicValue1,
          {'value1': error},
        ),
      );
    }
  }

  Future<void> _toggleTopicPinned(_ForumTopic topic) async {
    try {
      await _query({
        '@type': 'toggleForumTopicIsPinned',
        'chat_id': widget.chat.id,
        'forum_topic_id': topic.id,
        'is_pinned': !topic.isPinned,
      });
      await _loadTopics();
    } catch (error) {
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.groupAdministrationCouldnTPinTopicValue1, {
          'value1': error,
        }),
      );
    }
  }

  Future<void> _toggleTopicMuted(_ForumTopic topic) async {
    try {
      await _query({
        '@type': 'setForumTopicNotificationSettings',
        'chat_id': widget.chat.id,
        'forum_topic_id': topic.id,
        'notification_settings': inheritedChatNotificationSettings(
          muteFor: topic.isMuted ? 0 : 2147483647,
        ),
      });
      await _loadTopics();
    } catch (error) {
      if (!mounted) return;
      showToast(
        context,
        _topicActionError(AppStringKeys.topicChatMuteFailed, error),
      );
    }
  }

  Future<void> _toggleTopicClosed(_ForumTopic topic) async {
    try {
      await _query({
        '@type': 'toggleForumTopicIsClosed',
        'chat_id': widget.chat.id,
        'forum_topic_id': topic.id,
        'is_closed': !topic.isClosed,
      });
      await _loadTopics();
    } catch (error) {
      if (!mounted) return;
      showToast(
        context,
        _topicActionError(AppStringKeys.topicPostContentActionFailed, error),
      );
    }
  }

  /// Marks the topic read the way viewing its newest message does: TDLib
  /// advances the topic's inbox watermark to the highest viewed message id.
  Future<void> _markTopicRead(_ForumTopic topic) async {
    if (!topic.hasRealLastMessage || topic.unreadCount == 0) return;
    try {
      await _query(
        forumTopicViewMessagesRequest(
          chatId: widget.chat.id,
          messageIds: [topic.lastMessage.id],
        ),
      );
      await _loadTopics();
    } catch (_) {
      // A failed mark-read is silent: nothing destructive happened.
    }
  }

  String _topicActionError(String fallback, Object error) {
    if (error is TdError && error.message.trim().isNotEmpty) {
      return '$fallback: ${error.message.trim()}';
    }
    return AppStrings.t(AppStringKeys.topicPostContentActionFailed);
  }

  /// The topic row's context menu (iOS swipe action / long press). Destructive
  /// and management items only appear while the account holds the right;
  /// mute and mark-read stay available to everyone.
  void _showTopicRowMenu(TopicNavigationItem item, Offset? globalPosition) {
    final topic = _topicById(item.id);
    if (topic == null) return;
    final canManage = _canManageTopics;
    final actions = <TopicRowAction>[
      if (topic.unreadCount > 0)
        TopicRowAction(
          key: 'read',
          label: AppStrings.t(AppStringKeys.channelDirectMessagesMarkRead),
          icon: HeroAppIcons.circleCheck,
          onSelected: () => unawaited(_markTopicRead(topic)),
        ),
      if (canManage)
        TopicRowAction(
          key: 'pin',
          label: topic.isPinned
              ? AppStrings.t(AppStringKeys.chatListUnpin)
              : AppStrings.t(AppStringKeys.chatInfoPin),
          icon: HeroAppIcons.thumbtack,
          onSelected: () => unawaited(_toggleTopicPinned(topic)),
        ),
      TopicRowAction(
        key: 'mute',
        label: topic.isMuted
            ? AppStrings.t(AppStringKeys.chatUnmute)
            : AppStrings.t(AppStringKeys.callMute),
        icon: topic.isMuted ? HeroAppIcons.bell : HeroAppIcons.bellSlash,
        onSelected: () => unawaited(_toggleTopicMuted(topic)),
      ),
      if (canManage && !topic.isGeneral)
        TopicRowAction(
          key: 'edit',
          label: AppStrings.t(AppStringKeys.groupAdministrationEditTopic),
          icon: HeroAppIcons.pen,
          onSelected: () => unawaited(_editTopic(topic)),
        ),
      if (canManage && !topic.isGeneral)
        TopicRowAction(
          key: 'close',
          label: topic.isClosed
              ? AppStrings.t(AppStringKeys.topicChatReopenTopic)
              : AppStrings.t(AppStringKeys.topicChatCloseTopic),
          icon: topic.isClosed ? HeroAppIcons.eye : HeroAppIcons.lock,
          onSelected: () => unawaited(_toggleTopicClosed(topic)),
        ),
      if (_canDeleteTopic(topic))
        TopicRowAction(
          key: 'delete',
          label: AppStrings.t(AppStringKeys.chatDelete),
          icon: HeroAppIcons.trash,
          destructive: true,
          onSelected: () => unawaited(_deleteTopic(topic)),
        ),
    ];
    if (actions.isEmpty) return;
    showAppModalSheet<void>(
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
                        tint: topic.iconColor ?? AppTheme.brand,
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
                for (final action in actions) _TopicMenuRow(action: action),
              ],
            ),
          ),
        );
      },
    );
  }

  // Materialized rather than recomputed: as a getter this allocated a
  // _TopicPost per loaded message and re-sorted the whole list on every scroll
  // frame (_updateVisibleMessages) as well as on every build.
  List<_TopicPost> _posts = const <_TopicPost>[];

  void _rebuildPosts() {
    final selected = _selectedThreadId;
    final posts = <_TopicPost>[];
    for (final topic in _topics) {
      if (selected != null && topic.id != selected) continue;
      final loadedMessages = _topicMessages[topic.id];
      final messages = loadedMessages ?? [topic.lastMessage];
      for (final message in messages) {
        posts.add(
          _TopicPost(
            topic: topic,
            message: message,
            isSynthetic:
                topic.lastMessageIsSynthetic &&
                (loadedMessages == null ||
                    identical(message, topic.lastMessage)),
          ),
        );
      }
    }
    posts.sort((a, b) => b.message.date.compareTo(a.message.date));
    _posts = posts;
  }

  void _scheduleInitialMessagePosition(List<_TopicPost> posts) {
    final targetMessageId = _pendingInitialMessageId;
    if (targetMessageId == null || _initialMessagePositionScheduled) return;
    final targetIndex = posts.indexWhere(
      (post) => post.message.id == targetMessageId,
    );
    if (targetIndex < 0) {
      if (!_loading && _loadingThreads.isEmpty) {
        _pendingInitialMessageId = null;
      }
      return;
    }
    _initialMessagePositionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialMessagePositionScheduled = false;
      if (!mounted || _pendingInitialMessageId != targetMessageId) return;
      unawaited(
        _positionInitialMessage(
          messageId: targetMessageId,
          targetIndex: targetIndex,
          postCount: posts.length,
        ),
      );
    });
  }

  Future<void> _positionInitialMessage({
    required int messageId,
    required int targetIndex,
    required int postCount,
  }) async {
    final key = _postVisibilityKeys.putIfAbsent(messageId, GlobalKey.new);
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!mounted || _pendingInitialMessageId != messageId) return;
      final itemContext = key.currentContext;
      if (itemContext != null && itemContext.mounted) {
        await Scrollable.ensureVisible(
          itemContext,
          alignment: forumTopicInitialMessageAlignment,
        );
        if (mounted && _pendingInitialMessageId == messageId) {
          _pendingInitialMessageId = null;
          _scheduleVisibleMessageUpdate();
        }
        return;
      }
      if (!_scroll.hasClients || postCount <= 1) break;
      final position = _scroll.position;
      final fraction = targetIndex / (postCount - 1);
      final estimatedOffset =
          position.minScrollExtent +
          (position.maxScrollExtent - position.minScrollExtent) * fraction;
      _scroll.jumpTo(
        estimatedOffset.clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
      await WidgetsBinding.instance.endOfFrame;
    }
    if (mounted && _pendingInitialMessageId == messageId) {
      _pendingInitialMessageId = null;
    }
  }

  void _scheduleVisibleMessageUpdate() {
    if (_visibleMessageUpdateScheduled || !mounted) return;
    _visibleMessageUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibleMessageUpdateScheduled = false;
      if (mounted) _updateVisibleMessages();
    });
  }

  void _updateVisibleMessages() {
    if (!TickerMode.valuesOf(context).enabled ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final viewportContext = _topicViewportKey.currentContext;
    final viewportRenderObject = viewportContext?.findRenderObject();
    if (viewportRenderObject is! RenderBox || !viewportRenderObject.attached) {
      return;
    }
    // Viewport-local coordinates: stopping the transform walk at the list keeps
    // it off the whole ancestor chain, once per row per scroll frame.
    final viewport = Offset.zero & viewportRenderObject.size;
    final bounds = <int, Rect>{};
    for (final post in _posts) {
      if (!isReportableForumTopicMessage(
        post.message,
        isSynthetic: post.isSynthetic,
      )) {
        continue;
      }
      final itemContext = _postVisibilityKeys[post.message.id]?.currentContext;
      final itemRenderObject = itemContext?.findRenderObject();
      if (itemRenderObject is! RenderBox || !itemRenderObject.attached) {
        continue;
      }
      final origin = itemRenderObject.localToGlobal(
        Offset.zero,
        ancestor: viewportRenderObject,
      );
      bounds[post.message.id] = origin & itemRenderObject.size;
    }
    final visible = takeNewlyVisibleForumTopicMessageIds(
      viewport: viewport,
      messageBounds: bounds,
      alreadyReported: _reportedVisibleMessageIds,
    );
    if (visible.isEmpty) return;
    TdClient.shared.send(
      forumTopicViewMessagesRequest(
        chatId: widget.chat.id,
        messageIds: visible,
      ),
    );
  }

  Future<void> _resolveSenders(List<ChatMessage> messages) async {
    for (final message in messages) {
      final id = message.senderId;
      if (id == null || _senderCache.containsKey(id)) continue;
      try {
        if (id > 0) {
          final user = await TdClient.shared.query({
            '@type': 'getUser',
            'user_id': id,
          });
          _senderCache[id] = _SenderInfo(
            name: TDParse.userName(user),
            photo: TDParse.smallPhoto(user.obj('profile_photo')),
          );
        } else {
          final chat = await TdClient.shared.query({
            '@type': 'getChat',
            'chat_id': id,
          });
          _senderCache[id] = _SenderInfo(
            name: chat.str('title') ?? AppStringKeys.topicChatUsers,
            photo: TDParse.smallPhoto(chat.obj('photo')),
          );
        }
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Future<void> _sendPostText(FormattedTextPayload formatted) async {
    if (formatted.text.trim().isEmpty) return;
    final threadId = _selectedThreadId;
    if (!canComposeInTopicSurface(chat: widget.chat, forumTopicId: threadId)) {
      return;
    }
    try {
      final request = <String, dynamic>{
        '@type': 'sendMessage',
        'chat_id': widget.chat.id,
        'input_message_content': {
          '@type': 'inputMessageText',
          'text': formatted.toTdJson(),
        },
      };
      if (threadId != null) _attachForumTopic(request, threadId);
      await _sendForumMessage(request);
      _input.clear();
      _topicMessages.clear();
      await _loadTopics();
    } catch (_) {}
  }

  Future<void> _openComposer() async {
    final result = await showRichTextComposerSheet(
      context,
      initialText: _input.text,
      hintText: AppStringKeys.topicChatComposerPlaceholder,
    );
    if (result == null) return;
    _input.text = result.text;
    if (result.attachments.isEmpty) {
      await _sendPostText(result.formattedText);
    } else {
      await _sendPostMedia(result);
    }
  }

  Future<void> _sendPostMedia(RichTextComposerResult result) async {
    final threadId = _selectedThreadId;
    if (!canComposeInTopicSurface(chat: widget.chat, forumTopicId: threadId)) {
      return;
    }
    final requests = buildAttachmentSendRequests(
      chatId: widget.chat.id,
      attachments: result.attachments,
      caption: result.text,
      captionEntities: result.entities,
    );
    for (final request in requests) {
      if (threadId != null) _attachForumTopic(request, threadId);
      await _sendForumMessage(request);
    }
    _input.clear();
    _topicMessages.clear();
    await _loadTopics();
  }

  void _attachForumTopic(Map<String, dynamic> request, int forumTopicId) {
    final scoped = forumTopicScopedSendRequest(
      request: request,
      forumTopicId: forumTopicId,
    );
    request
      ..clear()
      ..addAll(scoped);
  }

  Future<void> _sendForumMessage(Map<String, dynamic> request) async {
    if (!request.containsKey('topic_id')) {
      await TdClient.shared.query(request);
      return;
    }
    await sendScopedForumTopicMessage(
      query: TdClient.shared.query,
      request: request,
    );
  }

  Future<void> _openSearch() async {
    final topicId = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => _TopicSearchView(chat: widget.chat, topics: _topics),
      ),
    );
    if (!mounted || topicId == null) return;
    _selectTopic(topicId);
  }

  void _openSettings() {
    _ForumTopic? currentTopic;
    final selected = _selectedThreadId;
    if (selected != null) {
      for (final topic in _topics) {
        if (topic.id == selected) {
          currentTopic = topic;
          break;
        }
      }
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TopicChannelSettingsView(
          chat: widget.chat,
          currentTopic: currentTopic,
          topics: _topics,
          onOpenMessages: () {
            Navigator.of(context).pop();
            final topic = currentTopic;
            if (topic != null) _selectTopic(topic.id);
          },
          onTopicChanged: () async {
            _topicMessages.clear();
            await _loadTopics();
          },
        ),
      ),
    );
  }

  Future<void> _openChatView() async {
    final onOpenChatView = widget.onOpenChatView;
    if (onOpenChatView != null) {
      onOpenChatView();
      return;
    }
    final chat = widget.chat;
    if (ChatPane.replace(
      context,
      (onBack) => ChatView(
        chatId: chat.id,
        title: chat.title,
        seedMessage: chat.lastChatMessage,
        headerHeight: widget.headerHeight,
        headerColor: widget.headerColor,
        onBack: onBack,
      ),
    )) {
      return;
    }
    if (widget.chatRouteBelow) {
      Navigator.of(context).pop();
      return;
    }
    final routeSession = widget.routeSession;
    final route = AppChatPageRoute<void>(
      builder: (chatContext) => ChatView(
        chatId: chat.id,
        title: chat.title,
        seedMessage: chat.lastChatMessage,
        onOpenTopicTranscript: routeSession == null
            ? null
            : (threadId) => _replaceTrackedChatWithTopic(
                chatContext,
                chat,
                routeSession,
                threadId,
              ),
      ),
    );
    if (routeSession == null) {
      unawaited(replaceWithAppChatRoute<void, void>(context, route));
    } else {
      routeSession.trackRoute(
        () => replaceWithAppChatRoute<void, void>(context, route),
      );
    }
  }

  void _openComments(_TopicPost post) {
    showMessageRepliesSheet(
      context: context,
      chatId: widget.chat.id,
      message: post.message,
      peerTitle: widget.chat.title,
      forumTopicId: post.topic.id,
      onSent: () {
        post.message.commentCount += 1;
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _sharePost(_TopicPost post) async {
    final result = await Navigator.of(context).push<ChatPickerResult>(
      MaterialPageRoute(
        builder: (_) => const ChatPickerView(
          title: AppStringKeys.chatForwardToTitle,
          showForwardOptions: true,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final target = result.chat;
    try {
      await forwardMessagesWithOptions(
        client: TdClient.shared,
        targetChatId: target.id,
        fromChatId: widget.chat.id,
        messageIds: [post.message.id],
        options: result.forwardOptions,
      );
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.chatForwardedToName, {
          'value1': target.title,
        }),
      );
    } catch (e) {
      if (!mounted) return;
      showToast(
        context,
        isForwardProtectedError(e)
            ? AppStringKeys.chatForwardProtected
            : AppStrings.t(AppStringKeys.chatForwardFailed, {'value1': e}),
      );
    }
  }

  Future<void> _addReaction(_TopicPost post, String emoji) async {
    try {
      final reactionEmoji = await _resolveReactionEmoji(post, emoji);
      try {
        await _sendReaction(post, reactionEmoji);
      } catch (_) {
        final retry = _alternateHeartReaction(reactionEmoji);
        if (retry == null) rethrow;
        await _sendReaction(post, retry);
      }
      _topicMessages.clear();
      await _loadTopics();
      if (mounted) showToast(context, AppStringKeys.momentsLiked);
    } catch (e) {
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.momentsLikeFailed, {'value1': e}),
      );
    }
  }

  Future<String> _resolveReactionEmoji(
    _TopicPost post,
    String preferred,
  ) async {
    final candidates = _topicHeartReactions.contains(preferred)
        ? _topicLikeReactionCandidates
        : <String>[preferred];
    Set<String> emojis;
    try {
      final available = await TdClient.shared.query({
        '@type': 'getMessageAvailableReactions',
        'chat_id': widget.chat.id,
        'message_id': post.message.id,
        'row_size': 25,
      });
      emojis = _availableReactionEmojis(available);
    } catch (_) {
      // Older or constrained TDLib builds can fail this query; the send path
      // still has a heart-variant retry below.
      emojis = const {};
    }
    for (final candidate in candidates) {
      if (emojis.contains(candidate)) return candidate;
    }
    if (emojis.isNotEmpty) {
      throw StateError('Reaction is not available for this message');
    }
    return _topicHeartReactions.contains(preferred) ? '❤' : preferred;
  }

  Set<String> _availableReactionEmojis(Map<String, dynamic> available) {
    final emojis = <String>{};
    void collect(String key) {
      for (final reaction
          in available.objects(key) ?? const <Map<String, dynamic>>[]) {
        if (reaction.boolean('needs_premium') == true) continue;
        final type = reaction.obj('type');
        if (type?.type != 'reactionTypeEmoji') continue;
        final emoji = type?.str('emoji');
        if (emoji != null && emoji.isNotEmpty) emojis.add(emoji);
      }
    }

    collect('top_reactions');
    collect('recent_reactions');
    collect('popular_reactions');
    return emojis;
  }

  Future<void> _sendReaction(_TopicPost post, String emoji) {
    return TdClient.shared.query({
      '@type': 'addMessageReaction',
      'chat_id': widget.chat.id,
      'message_id': post.message.id,
      'reaction_type': {'@type': 'reactionTypeEmoji', 'emoji': emoji},
      'is_big': false,
      'update_recent_reactions': true,
    });
  }

  String? _alternateHeartReaction(String emoji) {
    if (emoji == '❤️') return '❤';
    if (emoji == '❤') return '❤️';
    return null;
  }

  void _showReactionPicker(_TopicPost post) {
    showAppModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final c = context.colors;
        const reactions = ['❤️', '👍', '😂', '😮', '😢', '🔥'];
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (final reaction in reactions)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Navigator.of(context).pop();
                      _addReaction(post, reaction);
                    },
                    child: Text(reaction, style: const TextStyle(fontSize: 28)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final body = Column(
      children: [
        if (_selectedThreadId == null && widget.chat.lastMessage.isNotEmpty)
          _pinnedLine(),
        Expanded(child: _content()),
        if (canComposeInTopicSurface(
          chat: widget.chat,
          forumTopicId: _selectedThreadId,
        ))
          _bottomComposer(),
      ],
    );
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          _header(),
          Expanded(
            child: _topicListOverlaid
                ? body
                : TopicNavigationLayout(
                    topics: [
                      for (final topic in _topics) _navigationItem(topic),
                    ],
                    selectedTopicId: _selectedThreadId,
                    hasForumTabs: _hasForumTabs,
                    onSelected: _selectTopic,
                    onCreateTopic: _canCreateTopics
                        ? _openCreateTopicDialog
                        : null,
                    onTopicMenu: _showTopicRowMenu,
                    generalAvatarTitle: widget.chat.title,
                    generalAvatarPhoto: widget.chat.photo,
                    child: body,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final c = context.colors;
    final listHiddenByUser =
        _topicListOverlaid &&
        (context.watch<TopicListHost?>()?.listHidden ?? false);
    final top =
        MediaQuery.of(context).padding.top + iPadWindowChromeInsetOf(context);
    final title = widget.chat.isBotTopicChat
        ? widget.chat.title
        : context.watch<GroupRemarkController?>()?.displayTitleFor(
                widget.chat.id,
                widget.chat.title,
              ) ??
              widget.chat.title;
    return Container(
      height: top + widget.headerHeight,
      padding: EdgeInsets.only(top: top),
      decoration: BoxDecoration(
        color: widget.headerColor ?? c.navBar,
        image: const DecorationImage(
          image: AssetImage('assets/app_icon.png'),
          fit: BoxFit.cover,
          opacity: 0.04,
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: widget.headerHeight,
            child: Row(
              children: [
                if (widget.showBackButton)
                  GestureDetector(
                    key: const ValueKey('topic-header-back'),
                    behavior: HitTestBehavior.opaque,
                    onTap:
                        widget.onBack ?? () => Navigator.of(context).maybePop(),
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
                  )
                else
                  const SizedBox(width: AppSpacing.sm),
                PhotoAvatar(
                  title: title,
                  photo: widget.chat.photo,
                  size: 32,
                  square: widget.chat.usesSquareAvatar,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: c.textPrimary,
                        ),
                      ),
                      Text(
                        _topics.isEmpty
                            ? AppStrings.t(
                                widget.chat.isBotTopicChat
                                    ? AppStringKeys.topicChatAllTopics
                                    : AppStringKeys.topicChatGroupChatTitle,
                              )
                            : AppStrings.t(AppStringKeys.topicChatTopicCount, {
                                'value1': _topics.length,
                              }),
                        style: TextStyle(fontSize: 12, color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  key: const ValueKey('topic-header-search'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _openSearch,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: AppIcon(
                      HeroAppIcons.magnifyingGlass,
                      size: 25,
                      color: c.textPrimary,
                    ),
                  ),
                ),
                if (listHiddenByUser) ...[
                  const SizedBox(width: AppSpacing.md),
                  GestureDetector(
                    key: const ValueKey('topic-header-list'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => context.read<TopicListHost?>()?.showList(),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: AppIcon(
                        HeroAppIcons.hashtag,
                        size: 25,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: AppSpacing.md),
                GestureDetector(
                  key: const ValueKey('topic-header-chat-mode'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _openChatView,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: AppIcon(
                      HeroAppIcons.message,
                      size: 25,
                      color: c.textPrimary,
                    ),
                  ),
                ),
                if (showsGroupTopicControls(widget.chat) &&
                    _canCreateTopics &&
                    (!_topicListOverlaid || _hasForumTabs)) ...[
                  const SizedBox(width: AppSpacing.md),
                  GestureDetector(
                    key: const ValueKey('topic-header-create-topic'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _openCreateTopicDialog,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: AppIcon(
                        HeroAppIcons.plus,
                        size: 25,
                        color: AppTheme.brand,
                      ),
                    ),
                  ),
                ],
                if (showsGroupTopicControls(widget.chat)) ...[
                  const SizedBox(width: AppSpacing.xl),
                  GestureDetector(
                    key: const ValueKey('topic-header-settings'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _openSettings,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: AppIcon(
                        HeroAppIcons.bars,
                        size: 25,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: AppSpacing.xl),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pinnedLine() {
    final c = context.colors;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.background,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          Text(
            AppStrings.t(AppStringKeys.topicChatPinnedPrefix),
            style: TextStyle(fontSize: 15, color: c.textSecondary),
          ),
          Expanded(
            child: Text(
              widget.chat.lastMessage,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, color: c.textPrimary),
            ),
          ),
          Text(
            AppStringKeys.topicChatExpand.l10n(context),
            style: TextStyle(fontSize: 14, color: c.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    final posts = _posts;
    if (_loading && posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (posts.isEmpty) {
      return Center(
        child: Text(
          AppStringKeys.topicChatNoMoreContent.l10n(context),
          style: TextStyle(fontSize: 15, color: context.colors.textTertiary),
        ),
      );
    }
    _scheduleVisibleMessageUpdate();
    _scheduleInitialMessagePosition(posts);
    return ListView.separated(
      key: _topicViewportKey,
      controller: _scroll,
      padding: EdgeInsets.zero,
      itemCount: posts.length,
      separatorBuilder: (_, _) => const InsetDivider(leadingInset: 0),
      itemBuilder: (context, index) {
        final post = posts[index];
        final visibilityKey = _postVisibilityKeys.putIfAbsent(
          post.message.id,
          GlobalKey.new,
        );
        return KeyedSubtree(
          key: visibilityKey,
          child: KeyedSubtree(
            key: ValueKey('topic-post-${post.message.id}'),
            child: _TopicPostRow(
              chatId: widget.chat.id,
              post: post,
              sender: _senderCache[post.message.senderId],
              onLike: () => _addReaction(post, '❤️'),
              onPickReaction: () => _showReactionPicker(post),
              onComments: () => _openComments(post),
              onShare: () => _sharePost(post),
            ),
          ),
        );
      },
    );
  }

  Widget _bottomComposer() {
    final c = context.colors;
    return Material(
      color: c.navBar,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _openComposer,
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: c.searchFill,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: Text(
                      _input.text.trim().isEmpty
                          ? AppStrings.t(
                              AppStringKeys.topicChatAwaitingYourPost,
                            )
                          : _input.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        color: _input.text.trim().isEmpty
                            ? c.textTertiary
                            : c.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openComposer,
                child: AppIcon(
                  HeroAppIcons.penToSquare,
                  size: 26,
                  color: AppTheme.brand,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicPostRow extends StatelessWidget {
  const _TopicPostRow({
    required this.chatId,
    required this.post,
    required this.onLike,
    required this.onPickReaction,
    required this.onComments,
    required this.onShare,
    this.sender,
  });

  final int chatId;
  final _TopicPost post;
  final _SenderInfo? sender;
  final VoidCallback onLike;
  final VoidCallback onPickReaction;
  final VoidCallback onComments;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = _displayText;
    final chatTextSize = context.watch<ThemeController>().chatTextSize(15);
    final name = sender?.name.trim().isNotEmpty == true
        ? sender!.name.trim()
        : post.message.senderName ?? post.topic.name;
    return Container(
      color: c.background,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PhotoAvatar(title: name, photo: sender?.photo, size: 48),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      DateText.listLabel(post.message.date),
                      style: TextStyle(fontSize: 14, color: c.textTertiary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_hasRenderableContent) ...[
            const SizedBox(height: 14),
            TopicPostContent(
              chatId: chatId,
              message: post.message,
              text: text,
              textStyle: TextStyle(
                fontSize: chatTextSize,
                height: 1.35,
                color: c.textPrimary,
              ),
              imageReactions: _ExtraReactions(message: post.message),
            ),
          ],
          const SizedBox(height: 13),
          _PostActions(
            message: post.message,
            onLike: onLike,
            onPickReaction: onPickReaction,
            onComments: onComments,
            onShare: onShare,
          ),
        ],
      ),
    );
  }

  String get _displayText {
    return post.message.text.trim();
  }

  bool get _hasRenderableContent =>
      _displayText.isNotEmpty ||
      post.message.image != null ||
      post.message.document != null ||
      post.message.buttonRows.isNotEmpty;
}

class _PostActions extends StatelessWidget {
  const _PostActions({
    required this.message,
    required this.onLike,
    required this.onPickReaction,
    required this.onComments,
    required this.onShare,
  });

  final ChatMessage message;
  final VoidCallback onLike;
  final VoidCallback onPickReaction;
  final VoidCallback onComments;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final likeCount = message.reactions.fold<int>(
      0,
      (sum, reaction) =>
          _isTopicLikeReaction(reaction) ? sum + reaction.count : sum,
    );
    return Row(
      children: [
        const Spacer(),
        _PostActionButton(
          icon: HeroAppIcons.heart,
          label: '$likeCount',
          onTap: onLike,
          onLongPress: onPickReaction,
        ),
        const SizedBox(width: 18),
        _PostActionButton(
          icon: HeroAppIcons.comment,
          label: message.commentCount == 0 ? '' : '${message.commentCount}',
          onTap: onComments,
        ),
        const SizedBox(width: 18),
        _PostActionButton(icon: HeroAppIcons.forward, onTap: onShare),
      ],
    );
  }
}

class _PostActionButton extends StatelessWidget {
  const _PostActionButton({
    required this.icon,
    required this.onTap,
    this.label = '',
    this.onLongPress,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(icon, size: 24, color: c.textPrimary),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 5),
              Text(label, style: TextStyle(fontSize: 14, color: c.textPrimary)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExtraReactions extends StatelessWidget {
  const _ExtraReactions({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final extra = message.reactions
        .where(
          (reaction) => reaction.count > 0 && !_isTopicLikeReaction(reaction),
        )
        .toList();
    if (extra.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final reaction in extra)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: c.searchFill,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Text(
                '${reaction.emoji ?? '⭐'} ${reaction.count}',
                style: TextStyle(fontSize: 13, color: c.textPrimary),
              ),
            ),
        ],
      ),
    );
  }
}

class _TopicSearchView extends StatefulWidget {
  const _TopicSearchView({required this.chat, required this.topics});

  final ChatSummary chat;
  final List<_ForumTopic> topics;

  @override
  State<_TopicSearchView> createState() => _TopicSearchViewState();
}

class _TopicSearchViewState extends State<_TopicSearchView> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<ChatMessage> _results = const [];
  List<_TopicNameSearchHit> _topicResults = const [];
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    setState(() {});
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = const [];
        _topicResults = const [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(value));
  }

  Future<void> _run(String query) async {
    setState(() => _loading = true);
    try {
      final responses = await Future.wait([
        TdClient.shared.query({
          '@type': 'getForumTopics',
          'chat_id': widget.chat.id,
          'query': query,
          'offset_date': 0,
          'offset_message_id': 0,
          'offset_forum_topic_id': 0,
          'limit': 50,
        }),
        TdClient.shared.query({
          '@type': 'searchChatMessages',
          'chat_id': widget.chat.id,
          'topic_id': null,
          'query': query,
          'sender_id': null,
          'from_message_id': 0,
          'offset': 0,
          'limit': 50,
          'filter': {'@type': 'searchMessagesFilterEmpty'},
        }),
      ]);
      final results =
          (responses[1].objects('messages') ?? const <Map<String, dynamic>>[])
              .map(TDParse.message)
              .whereType<ChatMessage>()
              .where((message) => !message.isService)
              .toList();
      final topicResults = <_TopicNameSearchHit>[];
      for (final topic
          in responses[0].objects('topics') ?? const <Map<String, dynamic>>[]) {
        final info = topic.obj('info') ?? topic;
        final id = info.integer('forum_topic_id');
        final name = info.str('name');
        if (id == null || id == 0 || name == null || name.isEmpty) continue;
        topicResults.add(_TopicNameSearchHit(id: id, name: name));
      }
      if (!mounted || query != _controller.text) return;
      setState(() {
        _results = results;
        _topicResults = topicResults;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 14, 12),
              child: Row(
                children: [
                  IconButton(
                    icon: AppIcon(
                      HeroAppIcons.chevronLeft,
                      color: c.textPrimary,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: c.searchFill,
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        onChanged: _changed,
                        style: TextStyle(fontSize: 16, color: c.textPrimary),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          icon: AppIcon(
                            HeroAppIcons.magnifyingGlass,
                            color: c.textTertiary,
                          ),
                          hintText: AppStrings.t(AppStringKeys.topicChatSearch),
                          suffixIcon: _controller.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: AppIcon(
                                    HeroAppIcons.solidCircleXmark,
                                    color: c.textTertiary,
                                  ),
                                  onPressed: () {
                                    _controller.clear();
                                    _changed('');
                                  },
                                ),
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      AppStringKeys.countryPickerCancel.l10n(context),
                      style: TextStyle(color: AppTheme.brand),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
              child: Row(
                children: [
                  _filterPill(c, AppStringKeys.topicChatSelectSection),
                  const SizedBox(width: 10),
                  _filterPill(c, AppStringKeys.topicChatSelectTime),
                  const Spacer(),
                  Text(
                    AppStringKeys.topicChatMostRelevant.l10n(context),
                    style: TextStyle(color: c.textPrimary),
                  ),
                  const SizedBox(width: 3),
                  const AppIcon(HeroAppIcons.arrowsUpDown, size: 17),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _searchResults(c),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchResults(AppColors c) {
    if (_topicResults.isEmpty && _results.isEmpty) {
      return Center(
        child: Text(
          AppStringKeys.chatSearchNoMessagesFound.l10n(context),
          style: TextStyle(fontSize: 14, color: c.textTertiary),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      children: [
        if (_topicResults.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Text(
              AppStringKeys.topicChatSelectSection.l10n(context),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
              ),
            ),
          ),
          for (final topic in _topicResults)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(topic.id),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.divider)),
                ),
                child: Row(
                  children: [
                    AppIcon(
                      HeroAppIcons.comments,
                      size: 20,
                      color: AppTheme.brand,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        topic.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, color: c.textPrimary),
                      ),
                    ),
                    AppIcon(
                      HeroAppIcons.chevronRight,
                      size: 15,
                      color: c.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
        ],
        if (_results.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 2),
            child: Text(
              AppStringKeys.chatSearchMessageResultLabel.l10n(context),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
              ),
            ),
          ),
          for (final message in _results)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => pushAppChatRoute(
                context,
                AppChatPageRoute(
                  builder: (_) => ChatView(
                    chatId: widget.chat.id,
                    title: widget.chat.title,
                    initialMessageId: message.id,
                  ),
                ),
              ),
              child: Column(
                children: [
                  _SearchResultRow(message: message),
                  Divider(height: 1, color: c.divider),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _filterPill(AppColors c, String text) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border.all(color: c.divider),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          Text(
            text.l10n(context),
            style: TextStyle(fontSize: 14, color: c.textPrimary),
          ),
          const SizedBox(width: 6),
          AppIcon(HeroAppIcons.chevronDown, size: 14, color: c.textPrimary),
        ],
      ),
    );
  }
}

class _TopicNameSearchHit {
  const _TopicNameSearchHit({required this.id, required this.name});

  final int id;
  final String name;
}

class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = message.senderName ?? AppStringKeys.topicChatUsers;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PhotoAvatar(title: name, photo: message.senderPhoto, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                if (message.text.trim().isNotEmpty)
                  Text(
                    message.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      color: c.textPrimary,
                    ),
                  ),
                if (message.image != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: SizedBox(
                      width: 160,
                      height: 92,
                      child: TDImage(photo: message.image, cornerRadius: 6),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      DateText.listLabel(message.date),
                      style: TextStyle(fontSize: 13, color: c.textTertiary),
                    ),
                    const Spacer(),
                    Text(
                      AppStrings.t(AppStringKeys.topicChatLikeCommentSummary, {
                        'value1': message.reactions.fold<int>(
                          0,
                          (sum, item) => sum + item.count,
                        ),
                        'value2': message.commentCount,
                      }),
                      style: TextStyle(fontSize: 13, color: c.textTertiary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopicMemberInfo {
  const _TopicMemberInfo({required this.name, this.photo});

  final String name;
  final TdFileRef? photo;
}

class _TopicChannelSettingsView extends StatefulWidget {
  const _TopicChannelSettingsView({
    required this.chat,
    required this.currentTopic,
    required this.topics,
    required this.onOpenMessages,
    required this.onTopicChanged,
  });

  final ChatSummary chat;
  final _ForumTopic? currentTopic;
  final List<_ForumTopic> topics;
  final VoidCallback onOpenMessages;
  final Future<void> Function() onTopicChanged;

  @override
  State<_TopicChannelSettingsView> createState() =>
      _TopicChannelSettingsViewState();
}

class _TopicChannelSettingsViewState extends State<_TopicChannelSettingsView> {
  final _members = <_TopicMemberInfo>[];
  int _memberCount = 0;
  bool _loadingMembers = true;
  late bool _topicPinned = widget.currentTopic?.isPinned ?? false;
  late bool _topicMuted = widget.currentTopic?.isMuted ?? false;

  _ForumTopic? get _topic => widget.currentTopic;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    try {
      final chat = await TdClient.shared.query({
        '@type': 'getChat',
        'chat_id': widget.chat.id,
      });
      final type = chat.obj('type');
      List<Map<String, dynamic>> raw = [];
      if (type?.type == 'chatTypeBasicGroup') {
        final gid = type?.int64('basic_group_id');
        if (gid != null) {
          final full = await TdClient.shared.query({
            '@type': 'getBasicGroupFullInfo',
            'basic_group_id': gid,
          });
          raw = full.objects('members') ?? const <Map<String, dynamic>>[];
          _memberCount = raw.length;
        }
      } else if (type?.type == 'chatTypeSupergroup') {
        final sgid = type?.int64('supergroup_id');
        if (sgid != null) {
          final result = await TdClient.shared.query({
            '@type': 'getSupergroupMembers',
            'supergroup_id': sgid,
            'filter': {'@type': 'supergroupMembersFilterRecent'},
            'offset': 0,
            'limit': 30,
          });
          raw = result.objects('members') ?? const <Map<String, dynamic>>[];
          _memberCount =
              result.integer('member_count') ??
              result.integer('total_count') ??
              raw.length;
        }
      }
      await _resolveMembers(raw);
    } catch (_) {
      _memberCount = _members.length;
    } finally {
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  Future<void> _resolveMembers(List<Map<String, dynamic>> raw) async {
    final result = <_TopicMemberInfo>[];
    for (final entry in raw.take(12)) {
      final memberId = entry.obj('member_id');
      if (memberId?.type != 'messageSenderUser') continue;
      final uid = memberId?.int64('user_id');
      if (uid == null) continue;
      try {
        final user = await TdClient.shared.query({
          '@type': 'getUser',
          'user_id': uid,
        });
        result.add(
          _TopicMemberInfo(
            name: TDParse.userName(user),
            photo: TDParse.smallPhoto(user.obj('profile_photo')),
          ),
        );
        if (mounted) {
          setState(() {
            _members
              ..clear()
              ..addAll(result);
          });
        }
      } catch (_) {}
    }
  }

  void _openMembers() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ChatMembersView(chatId: widget.chat.id, title: widget.chat.title),
      ),
    );
  }

  Future<void> _setTopicPinned(bool value) async {
    final topic = _topic;
    if (topic == null) return;
    setState(() => _topicPinned = value);
    try {
      await TdClient.shared.query({
        '@type': 'toggleForumTopicIsPinned',
        'chat_id': widget.chat.id,
        'forum_topic_id': topic.id,
        'message_thread_id': topic.id,
        'is_pinned': value,
      });
      await widget.onTopicChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() => _topicPinned = !value);
      showToast(
        context,
        _tdActionError(AppStringKeys.topicChatSetPinnedFailed, e),
      );
    }
  }

  Future<void> _setTopicMuted(bool value) async {
    final topic = _topic;
    if (topic == null) return;
    setState(() => _topicMuted = value);
    try {
      await TdClient.shared.query({
        '@type': 'setForumTopicNotificationSettings',
        'chat_id': widget.chat.id,
        'forum_topic_id': topic.id,
        'message_thread_id': topic.id,
        'notification_settings': inheritedChatNotificationSettings(
          muteFor: value ? 2147483647 : 0,
        ),
      });
      await widget.onTopicChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() => _topicMuted = !value);
      showToast(context, _tdActionError(AppStringKeys.topicChatMuteFailed, e));
    }
  }

  String _tdActionError(String fallback, Object error) {
    if (error is TdError && error.message.trim().isNotEmpty) {
      return '$fallback：${error.message.trim()}';
    }
    final text = error.toString().trim();
    return text.isEmpty ? fallback : '$fallback：$text';
  }

  Future<void> _exitTopic() async {
    final topic = _topic;
    if (topic == null) return;
    final ok = await confirmDialog(
      context,
      title: AppStringKeys.topicChatLeaveChannel,
      message: AppStrings.t(AppStringKeys.topicChatLeaveChannelConfirm, {
        'value1': topic.name,
      }),
      confirmText: AppStringKeys.topicChatLeave,
      destructive: true,
    );
    if (!ok) return;
    try {
      await TdClient.shared.query({
        '@type': 'deleteForumTopic',
        'chat_id': widget.chat.id,
        'forum_topic_id': topic.id,
        'message_thread_id': topic.id,
      });
      await widget.onTopicChanged();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.topicChatLeaveChannelFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final topic = _topic;
    return Scaffold(
      key: const ValueKey('topic-settings'),
      backgroundColor: c.groupedBackground,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 58,
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('topic-settings-back'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: AppIcon(
                      HeroAppIcons.chevronLeft,
                      color: c.textPrimary,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      AppStrings.t(
                        AppStringKeys.topicChatChannelSettings,
                      ).l10n(context),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: AppIcon(HeroAppIcons.share, color: c.textPrimary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                children: [
                  Row(
                    children: [
                      PhotoAvatar(
                        title: widget.chat.title,
                        photo: widget.chat.photo,
                        size: 72,
                        square: true,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.chat.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: c.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              AppStrings.t(
                                AppStringKeys.topicChatChannelNumber,
                                {'value1': widget.chat.id.abs()},
                              ).l10n(context),
                              style: TextStyle(
                                fontSize: 14,
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      AppIcon(
                        HeroAppIcons.qrcode,
                        size: 26,
                        color: c.textPrimary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  SettingsCard(
                    children: [
                      SettingsRow(
                        key: const ValueKey('topic-settings-members'),
                        title: AppStrings.t(
                          AppStringKeys.topicChatChannelMembers,
                        ),
                        value: _loadingMembers
                            ? AppStrings.t(AppStringKeys.topicChatLoading)
                            : AppStrings.t(AppStringKeys.topicChatMemberCount, {
                                'value1': _memberCount,
                              }),
                        onTap: _openMembers,
                      ),
                      _memberStrip(c),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const SettingsCard(
                    children: [
                      SettingsRow(
                        title: AppStringKeys.topicChatMyProfile,
                        value: 'ieb',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SettingsCard(
                    children: [
                      SettingsRow(
                        title: AppStrings.t(
                          AppStringKeys.topicChatChannelMessages,
                        ),
                        value:
                            topic?.name ??
                            AppStrings.t(AppStringKeys.topicChatAllTopics),
                        onTap: widget.onOpenMessages,
                      ),
                      SettingsSwitchRow(
                        title: AppStrings.t(AppStringKeys.topicChatPinToggle),
                        value: _topicPinned,
                        onChanged: topic == null
                            ? (_) {}
                            : (value) => unawaited(_setTopicPinned(value)),
                      ),
                      SettingsSwitchRow(
                        title: AppStrings.t(
                          AppStringKeys.topicChatMuteMessagesToggle,
                        ),
                        value: _topicMuted,
                        onChanged: topic == null
                            ? (_) {}
                            : (value) => unawaited(_setTopicMuted(value)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (topic != null)
                    SettingsCard(
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _exitTopic,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                AppStrings.t(
                                  AppStringKeys.topicChatLeaveChannel,
                                ).l10n(context),
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Color(0xFFFF3B30),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberStrip(AppColors c) {
    final people = _members.take(4).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          for (final person in people) ...[
            Expanded(
              child: Column(
                children: [
                  PhotoAvatar(
                    title: person.name,
                    photo: person.photo,
                    size: 42,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    person.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ],
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.searchFill,
                    shape: BoxShape.circle,
                  ),
                  child: AppIcon(HeroAppIcons.plus, color: c.textSecondary),
                ),
                const SizedBox(height: 6),
                Text(
                  AppStringKeys.topicChatInvite.l10n(context),
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A topic name/icon collected by the create and edit dialogs.
class _TopicDraft {
  const _TopicDraft({
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
class _TopicDraftDialog extends StatefulWidget {
  const _TopicDraftDialog({
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
  State<_TopicDraftDialog> createState() => _TopicDraftDialogState();
}

class _TopicDraftDialogState extends State<_TopicDraftDialog> {
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
    Navigator.of(context).pop(
      _TopicDraft(name: name, color: _color, customEmojiId: _customEmojiId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Material(
            type: MaterialType.transparency,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: c.divider, width: 0.5),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title.l10n(context),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const ValueKey('topic-draft-name'),
                      controller: _controller,
                      autofocus: true,
                      maxLength: 128,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        hintText: AppStrings.t(
                          AppStringKeys.chatInputBarTopicName,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (widget.canChangeColor) ...[
                      Text(
                        AppStrings.t(
                          AppStringKeys.groupAdministrationIconColor,
                        ),
                        style: TextStyle(fontSize: 13, color: c.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        children: [
                          for (final candidate in _topicIconColorCandidates)
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
                                      ? Border.all(
                                          color: AppTheme.brand,
                                          width: 3,
                                        )
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
                                AppStringKeys
                                    .groupAdministrationCustomEmojiIcon,
                              ),
                              style: TextStyle(
                                fontSize: 14,
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                          if (_customEmojiId == 0)
                            Text(
                              AppStrings.t(AppStringKeys.groupAppearanceNone),
                              style: TextStyle(
                                fontSize: 14,
                                color: c.textSecondary,
                              ),
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
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            AppStrings.t(AppStringKeys.confirmCancel),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          key: const ValueKey('topic-draft-save'),
                          onPressed: _submit,
                          child: Text(
                            AppStrings.t(AppStringKeys.accentColorPickerSave),
                            style: TextStyle(color: AppTheme.brand),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const List<int> _topicIconColorCandidates = [
  0x6FB9F0,
  0xFFD67E,
  0xCB86DB,
  0x8EEE98,
  0xFF93B2,
  0xFB6F5F,
];

/// One row of a topic's context menu sheet.
class _TopicMenuRow extends StatelessWidget {
  const _TopicMenuRow({required this.action});

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
