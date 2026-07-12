//
//  moments_view.dart
//
//  The 动态 tab: friends' Telegram Stories (TDLib active stories). Each row is a
//  friend whose active stories are grouped; tapping opens a full-screen viewer.
//  Port of the Swift `MomentsView` / `MomentsViewModel`.
//

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../chat/chat_picker_view.dart';
import '../chat/chat_view.dart';
import '../chat/forward_options.dart';
import '../chat/full_image_viewer.dart';
import '../chat/media_album_layout.dart';
import '../chat/outgoing_attachment.dart';
import '../chat/rich_text_composer_view.dart';
import '../chat/rich_text_format.dart';
import '../chat/shared_media_view.dart';
import '../chat/telegram_rich_text.dart';
import '../chat/video_player_view.dart';
import '../chats/chat_list_view_model.dart';
import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../l10n/telegram_language_controller.dart';
import '../media/app_asset_picker.dart';
import '../profile/profile_detail_view.dart';
import '../settings/accent_color_picker_view.dart';
import '../tdlib/chat_membership.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import 'story_viewer_view.dart';

class StoryGroup {
  StoryGroup({
    required this.chatId,
    required this.name,
    this.photo,
    required this.storyIds,
    required this.hasUnread,
    required this.order,
  });
  final int chatId;
  final String name;
  final TdFileRef? photo;
  final List<int> storyIds;
  final bool hasUnread;
  final int order;
}

class ChannelPost {
  ChannelPost({
    required this.channel,
    required this.message,
    this.threadTarget,
    this.authorName,
    this.authorPhoto,
    this.likeNames,
    this.comments,
    List<ChatMessage>? messages,
  }) : messages = messages ?? <ChatMessage>[message];

  final ChatSummary channel;
  final ChatMessage message;
  final List<ChatMessage> messages;
  ChannelPostThreadTarget? threadTarget;
  String? authorName;
  TdFileRef? authorPhoto;
  List<String>? likeNames;
  List<ChannelPostComment>? comments;
}

class ChannelPostThreadTarget {
  const ChannelPostThreadTarget({
    required this.chatId,
    required this.messageThreadId,
  });

  final int chatId;
  final int messageThreadId;
}

class ChannelPostComment {
  const ChannelPostComment({
    required this.chatId,
    required this.messageId,
    required this.senderName,
    required this.text,
    this.entities = const [],
    this.senderPhoto,
    this.date = 0,
    this.replyToMessageId,
    this.reactionCount = 0,
  });

  final int chatId;
  final int messageId;
  final String senderName;
  final String text;
  final List<MessageTextEntity> entities;
  final TdFileRef? senderPhoto;
  final int date;
  final int? replyToMessageId;
  final int reactionCount;
}

class _LoadedPostComment {
  const _LoadedPostComment({required this.chatId, required this.message});

  final int chatId;
  final ChatMessage message;
}

bool _isChannelSelfPost(ChannelPost post) {
  final senderId = post.message.senderId;
  if (senderId != null) return senderId == post.channel.id;

  final senderTitle = post.message.senderTitle?.trim();
  if (senderTitle == null || senderTitle.isEmpty) return false;
  return senderTitle == post.channel.title.trim();
}

Future<bool> _canPostToChannel(ChatSummary channel, int meId) async {
  try {
    final member = await TdClient.shared.query({
      '@type': 'getChatMember',
      'chat_id': channel.id,
      'member_id': {'@type': 'messageSenderUser', 'user_id': meId},
    });
    final status = member.obj('status');
    switch (status?.type) {
      case 'chatMemberStatusCreator':
        return true;
      case 'chatMemberStatusAdministrator':
        return status?.obj('rights')?.boolean('can_post_messages') ?? true;
    }
  } catch (_) {}
  return false;
}

Color _momentQuoteFill(AppColors c) =>
    c.groupedBackground.withValues(alpha: 0.88);

class MomentsView extends StatefulWidget {
  const MomentsView({super.key, this.onOpenDetail});

  final ValueChanged<Widget>? onOpenDetail;

  @override
  State<MomentsView> createState() => _MomentsViewState();
}

class _MomentsViewState extends State<MomentsView> {
  final _channels = ChatListViewModel();

  @override
  void initState() {
    super.initState();
    _channels.addListener(_onChannels);
    _channels.onAppear();
  }

  @override
  void dispose() {
    _channels.removeListener(_onChannels);
    _channels.dispose();
    super.dispose();
  }

  void _onChannels() {
    if (mounted) setState(() {});
  }

  List<ChatSummary> get _unreadChannels => _allChannels
      .where((chat) => chat.unreadCount > 0 || chat.isMarkedUnread)
      .toList();

  List<ChatSummary> get _allChannels {
    final byId = <int, ChatSummary>{};
    for (final chat in [..._channels.chats, ..._channels.archived]) {
      if (chat.kind == ChatKind.channel) byId[chat.id] = chat;
    }
    return byId.values.toList();
  }

  int get _newPostCount => _unreadChannels.fold<int>(
    0,
    (sum, chat) => sum + (chat.unreadCount > 0 ? chat.unreadCount : 1),
  );

  void _openDetail(Widget detail) {
    if (widget.onOpenDetail != null) {
      widget.onOpenDetail!(detail);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => detail));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.groupedBackground,
      child: Column(
        children: [
          const NavHeader(title: AppStringKeys.tabMoments),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              children: [
                Container(
                  color: c.background,
                  child: Column(
                    children: [
                      _menuRow(
                        icon: HeroAppIcons.star.data,
                        iconColor: const Color(0xFFFFBE00),
                        title: AppStrings.t(AppStringKeys.tabMoments),
                        trailing: _channelActivity(),
                        onTap: () => _openDetail(
                          ChannelMomentsView(
                            isRootTab: widget.onOpenDetail != null,
                            title: widget.onOpenDetail == null
                                ? AppStrings.t(AppStringKeys.tabMoments)
                                : AppStrings.t(AppStringKeys.tabFriendMoments),
                            initialChannels: _allChannels,
                          ),
                        ),
                      ),
                      _menuRow(
                        icon: HeroAppIcons.wandMagicSparkles.data,
                        iconColor: const Color(0xFFFFBE00),
                        title: AppStrings.t(AppStringKeys.momentsStories),
                        onTap: () => _openDetail(
                          StoriesView(
                            showBackButton: widget.onOpenDetail == null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  color: c.background,
                  child: Column(
                    children: [
                      _menuRow(
                        icon: HeroAppIcons.music.data,
                        iconColor: const Color(0xFFFF8A2A),
                        title: AppStrings.t(AppStringKeys.profileDetailMusic),
                        onTap: () => _openDetail(
                          SharedMediaView(
                            chatId: 0,
                            title: AppStrings.t(
                              AppStringKeys.profileDetailMusic,
                            ),
                            initialTab: 5,
                            displayTitle: AppStringKeys.profileDetailMusic,
                            lockedTab: true,
                          ),
                        ),
                      ),
                      _menuRow(
                        icon: HeroAppIcons.video.data,
                        iconColor: const Color(0xFF7B61FF),
                        title: telegramText(AppStringKeys.sharedMediaVideos),
                        onTap: () => _openDetail(
                          SharedMediaView(
                            chatId: 0,
                            title: telegramText(
                              AppStringKeys.sharedMediaVideos,
                            ),
                            initialTab: 4,
                            displayTitle: AppStringKeys.sharedMediaVideos,
                            lockedTab: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 50,
        child: Row(
          children: [
            const SizedBox(width: AppSpacing.xl),
            SizedBox(width: 36, child: Icon(icon, size: 25, color: iconColor)),
            const SizedBox(width: AppSpacing.md),
            Text(
              title.l10n(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16, color: c.textPrimary),
            ),
            const Spacer(),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.md),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 190),
                child: trailing,
              ),
            ],
            const SizedBox(width: AppSpacing.md),
            AppIcon(HeroAppIcons.chevronRight, size: 18, color: c.textTertiary),
            const SizedBox(width: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _channelActivity() {
    final unread = _unreadChannels;
    if (unread.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final avatars = unread.take(2).toList();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppLocalizations.of(
            context,
          ).format(AppStringKeys.momentsNewPostsCount, '$_newPostCount'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 14, color: c.textSecondary),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: avatars.length == 1 ? 30 : 48,
          height: 30,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < avatars.length; i++)
                Positioned(
                  left: i * 18,
                  child: Container(
                    padding: const EdgeInsets.all(1.5),
                    decoration: BoxDecoration(
                      color: c.background,
                      shape: BoxShape.circle,
                    ),
                    child: PhotoAvatar(
                      title: avatars[i].title,
                      photo: avatars[i].photo,
                      size: 27,
                      square: true,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class ChannelMomentsView extends StatefulWidget {
  const ChannelMomentsView({
    super.key,
    this.isRootTab = false,
    this.title = AppStringKeys.tabMoments,
    this.initialChannels = const [],
    this.onOpenDetail,
  });

  final bool isRootTab;
  final String title;
  final List<ChatSummary> initialChannels;
  final ValueChanged<Widget>? onOpenDetail;

  @override
  State<ChannelMomentsView> createState() => _ChannelMomentsViewState();
}

class _ChannelMomentsViewState extends State<ChannelMomentsView> {
  final _model = ChatListViewModel();
  final _replyController = TextEditingController();
  final _replyFocus = FocusNode();
  final _scroll = ScrollController();
  StreamSubscription? _tdSub;
  Timer? _refreshTimer;
  Timer? _metadataHydrationTimer;
  final Map<int, List<ChannelPost>> _postsByChannel = {};
  final Map<int, int> _oldestMessageByChannel = {};
  final Set<int> _loadingChannels = {};
  final Set<int> _exhaustedChannels = {};
  final Set<String> _loadingLikeNames = {};
  final Set<String> _loadingComments = {};
  final Set<String> _loadingReplyQuotes = {};
  final Set<String> _loadingThreadTargets = {};
  final Map<int, bool> _joinedChannelCache = {};
  List<ChatSummary> _postableChannels = const [];
  String _postableSignature = '';
  ChannelPost? _replyPost;
  int? _meUserId;
  int? _selectedPostChannelId;
  String _meName = AppStringKeys.chatMeLabel;
  TdFileRef? _mePhoto;
  int _meAccentColorId = -1;
  int _meProfileAccentColorId = -1;
  bool _loadingPosts = false;
  bool _loadingPostableChannels = false;
  bool _refreshingLiveUpdates = false;
  bool _nonMutedOnly = false;
  int _feedLoadGeneration = 0;
  static const _perChannelPageSize = 30;
  static const _metadataHydrationLimit = 60;
  static const _feedLimit = 500;

  @override
  void initState() {
    super.initState();
    _model.addListener(_onModel);
    _scroll.addListener(_onScroll);
    _tdSub = TdClient.shared.subscribe().listen(_handleTdUpdate);
    _model.onAppear();
    _loadMe();
    if (widget.initialChannels.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadChannelPosts();
      });
    }
  }

  @override
  void dispose() {
    _model.removeListener(_onModel);
    _model.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _tdSub?.cancel();
    _refreshTimer?.cancel();
    _metadataHydrationTimer?.cancel();
    _replyController.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.extentAfter < 600) _loadChannelPosts(loadOlder: true);
  }

  void _onModel() {
    _feedChatIds = null; // channel set may have changed
    if (mounted) setState(() {});
    _loadChannelPosts();
    _loadPostableChannels();
  }

  Future<void> _loadMe() async {
    try {
      final me = await TdClient.shared.query({'@type': 'getMe'});
      final name = TDParse.userName(me).trim();
      final userId = me.int64('id');
      if (!mounted) return;
      setState(() {
        _meUserId = userId;
        if (name.isNotEmpty) _meName = name;
        _mePhoto = TDParse.smallPhoto(me.obj('profile_photo'));
        _meAccentColorId = me.integer('accent_color_id') ?? -1;
        _meProfileAccentColorId = me.integer('profile_accent_color_id') ?? -1;
      });
      unawaited(_loadPostableChannels());
    } catch (_) {}
  }

  void _handleTdUpdate(Map<String, dynamic> update) {
    switch (update.type) {
      case 'updateNewMessage':
      case 'updateMessageContent':
      case 'updateMessageEdited':
      case 'updateMessageInteractionInfo':
      case 'updateMessageUnreadReactions':
      case 'updateDeleteMessages':
        if (!_touchesMomentsFeed(update)) return;
        _invalidateCachedInteractions(update);
        _scheduleLiveRefresh();
    }
  }

  // Message updates for EVERY chat flow through _handleTdUpdate. _channels is
  // a computed getter and the thread-target scan walks all loaded posts, so
  // doing both per update is an allocation storm during sync bursts — the
  // relevant chat ids are cached until the feed or channel set changes.
  Set<int>? _feedChatIds;

  Set<int> get _feedChatIdSet => _feedChatIds ??= {
    for (final chat in _channels) chat.id,
    for (final post in _postsByChannel.values.expand((items) => items))
      if (post.threadTarget != null) post.threadTarget!.chatId,
  };

  bool _touchesMomentsFeed(Map<String, dynamic> update) {
    final rawMessage = update.obj('message');
    final chatId = update.int64('chat_id') ?? rawMessage?.int64('chat_id');
    if (chatId == null) return true;
    return _feedChatIdSet.contains(chatId);
  }

  void _invalidateCachedInteractions(Map<String, dynamic> update) {
    final rawMessage = update.obj('message');
    final chatId = update.int64('chat_id') ?? rawMessage?.int64('chat_id');
    final messageId = update.int64('message_id') ?? rawMessage?.int64('id');
    if (chatId == null) return;
    for (final post in _postsByChannel.values.expand((items) => items)) {
      if (post.channel.id == chatId &&
          (messageId == null || post.message.id == messageId)) {
        post.likeNames = null;
        post.comments = null;
      }
      if (post.threadTarget?.chatId == chatId) {
        post.comments = null;
      }
    }
  }

  void _scheduleLiveRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 450), _refreshFeedNow);
  }

  Future<void> _refreshFeedNow() async {
    if (_refreshingLiveUpdates || !mounted) return;
    final channels = _channels;
    if (channels.isEmpty) return;
    _refreshingLiveUpdates = true;
    _loadingPosts = true;
    if (mounted) setState(() {});
    final futures = <Future<void>>[];
    for (final channel in channels) {
      if (!await _isJoinedChannel(channel)) continue;
      if (!_loadingChannels.add(channel.id)) continue;
      futures.add(_loadPostsForChannel(channel, fromMessageId: 0));
    }
    try {
      await Future.wait(futures);
    } finally {
      _refreshingLiveUpdates = false;
      _loadingPosts = _loadingChannels.isNotEmpty;
      if (mounted) setState(() {});
    }
  }

  List<ChatSummary> get _channels {
    final byId = <int, ChatSummary>{};
    for (final chat in widget.initialChannels) {
      if (chat.kind == ChatKind.channel &&
          (_joinedChannelCache[chat.id] ?? true) &&
          (!_nonMutedOnly || !chat.isMuted)) {
        byId[chat.id] = chat;
      }
    }
    for (final chat in [..._model.chats, ..._model.archived]) {
      if (chat.kind == ChatKind.channel &&
          (_joinedChannelCache[chat.id] ?? true) &&
          (!_nonMutedOnly || !chat.isMuted)) {
        byId[chat.id] = chat;
      }
    }
    return byId.values.toList();
  }

  // Flattening + sorting + album-grouping the whole feed is O(n log n) with
  // allocations; this getter is hit from build(), so cache until a
  // _postsByChannel mutation invalidates it.
  List<ChannelPost>? _postsCache;
  Map<Key, int>? _postIndexByKey;

  void _invalidateFeed() {
    _postsCache = null;
    _postIndexByKey = null;
    _feedChatIds = null;
  }

  List<ChannelPost> get _posts {
    final cached = _postsCache;
    if (cached != null) return cached;
    final posts = _postsByChannel.values.expand((items) => items).toList()
      ..sort((a, b) => b.message.date.compareTo(a.message.date));
    return _postsCache = _groupPostAlbums(posts).take(_feedLimit).toList();
  }

  static Key _postKey(ChannelPost post) =>
      ValueKey('post-${post.channel.id}-${post.message.id}');

  static const _composerHeaderKey = ValueKey('moments-composer-header');

  /// Feed-list index per child key (composer header at 0, posts at i+1), so
  /// keyed rows are reused when a refresh prepends new posts.
  Map<Key, int> get _feedIndexByKey => _postIndexByKey ??= <Key, int>{
    _composerHeaderKey: 0,
    for (var i = 0; i < _posts.length; i++) _postKey(_posts[i]): i + 1,
  };

  List<ChannelPost> _groupPostAlbums(List<ChannelPost> posts) {
    final grouped = <ChannelPost>[];
    final albums = <String, List<ChannelPost>>{};
    final consumed = <String>{};
    for (final post in posts) {
      final key = _postAlbumKey(post);
      if (key == null) {
        grouped.add(post);
      } else {
        (albums[key] ??= <ChannelPost>[]).add(post);
      }
    }
    for (final post in posts) {
      final key = _postAlbumKey(post);
      if (key == null || !consumed.add(key)) continue;
      final album = albums[key] ?? const <ChannelPost>[];
      album.sort((a, b) {
        final date = a.message.date.compareTo(b.message.date);
        return date != 0 ? date : a.message.id.compareTo(b.message.id);
      });
      if (album.length <= 1) {
        grouped.add(post);
        continue;
      }
      final primary = album.reduce(
        (a, b) => a.message.date >= b.message.date ? a : b,
      );
      grouped.add(
        ChannelPost(
          channel: primary.channel,
          message: primary.message,
          threadTarget: primary.threadTarget,
          authorName: primary.authorName,
          authorPhoto: primary.authorPhoto,
          likeNames: primary.likeNames,
          comments: primary.comments,
          messages: album.map((item) => item.message).toList(),
        ),
      );
    }
    return grouped;
  }

  String? _postAlbumKey(ChannelPost post) {
    final message = post.message;
    if (message.mediaAlbumId == 0 || !message.isAlbumVisualMedia) {
      return null;
    }
    return '${post.channel.id}:${message.mediaAlbumId}';
  }

  ChatSummary? get _selectedPostChannel {
    if (_postableChannels.isEmpty) return null;
    final selectedId = _selectedPostChannelId;
    if (selectedId != null) {
      for (final channel in _postableChannels) {
        if (channel.id == selectedId) return channel;
      }
    }
    return _postableChannels.first;
  }

  Future<void> _loadPostableChannels() async {
    final meId = _meUserId;
    if (meId == null || _loadingPostableChannels) return;
    final channels = _channels;
    final signature = '$meId:${channels.map((c) => c.id).join(',')}';
    if (signature == _postableSignature) return;
    _postableSignature = signature;
    _loadingPostableChannels = true;
    final postable = <ChatSummary>[];
    for (final channel in channels) {
      if (await _canPostToChannel(channel, meId)) postable.add(channel);
    }
    _loadingPostableChannels = false;
    if (!mounted) return;
    setState(() {
      _postableChannels = postable;
      if (postable.isEmpty) {
        _selectedPostChannelId = null;
      } else if (_selectedPostChannelId == null ||
          !postable.any((c) => c.id == _selectedPostChannelId)) {
        _selectedPostChannelId = postable.first.id;
      }
    });
  }

  Future<void> _loadChannelPosts({bool loadOlder = false}) async {
    final allChannels = _channels;
    if (allChannels.isEmpty) {
      _loadingPosts = false;
      return;
    }
    final channels = allChannels;
    final generation = _feedLoadGeneration;
    for (final channel in channels) {
      if (!await _isJoinedChannel(channel)) continue;
      final hasLoaded = _postsByChannel.containsKey(channel.id);
      if (_loadingChannels.contains(channel.id) ||
          _exhaustedChannels.contains(channel.id) ||
          (hasLoaded && !loadOlder)) {
        continue;
      }
      _loadingChannels.add(channel.id);
      unawaited(
        _loadPostsForChannel(
          channel,
          fromMessageId: loadOlder
              ? (_oldestMessageByChannel[channel.id] ?? 0)
              : 0,
          generation: generation,
        ),
      );
    }
    _loadingPosts = _loadingChannels.isNotEmpty;
    if (mounted) setState(() {});
  }

  Future<bool> _isJoinedChannel(ChatSummary channel) async {
    final cached = _joinedChannelCache[channel.id];
    if (cached != null) return cached;
    final joined = await isJoinedGroupOrChannelChat(channel.id);
    _joinedChannelCache[channel.id] = joined;
    _feedChatIds = null; // joined-state feeds the _channels filter
    if (!joined) {
      _postsByChannel.remove(channel.id);
      _invalidateFeed();
      _oldestMessageByChannel.remove(channel.id);
      _exhaustedChannels.add(channel.id);
      if (mounted) setState(() {});
    }
    return joined;
  }

  Future<void> _loadPostsForChannel(
    ChatSummary channel, {
    required int fromMessageId,
    int? generation,
  }) async {
    try {
      final response = await TdClient.shared.query({
        '@type': 'getChatHistory',
        'chat_id': channel.id,
        'from_message_id': fromMessageId,
        'offset': 0,
        'limit': _perChannelPageSize,
        'only_local': false,
      });
      final messages =
          (response.objects('messages') ?? const <Map<String, dynamic>>[])
              .map(TDParse.message)
              .whereType<ChatMessage>()
              .where((message) => !message.isService)
              .map((message) => ChannelPost(channel: channel, message: message))
              .toList();
      if (generation != null && generation != _feedLoadGeneration) return;
      if (messages.isEmpty) {
        _exhaustedChannels.add(channel.id);
      }
      _appendPosts(channel.id, messages);
      _schedulePostMetadataHydration();
    } catch (_) {
      if (generation != null && generation != _feedLoadGeneration) return;
      _postsByChannel.putIfAbsent(channel.id, () => const []);
      _invalidateFeed();
    } finally {
      if (generation == null || generation == _feedLoadGeneration) {
        _loadingChannels.remove(channel.id);
        _loadingPosts = _loadingChannels.isNotEmpty;
        if (mounted) setState(() {});
      }
    }
  }

  void _toggleNonMutedOnly() {
    setState(() {
      _nonMutedOnly = !_nonMutedOnly;
      _feedLoadGeneration += 1;
      _postsByChannel.clear();
      _invalidateFeed();
      _oldestMessageByChannel.clear();
      _exhaustedChannels.clear();
      _loadingChannels.clear();
      _postableSignature = '';
      _loadingPosts = true;
    });
    _loadChannelPosts();
    _loadPostableChannels();
  }

  void _schedulePostMetadataHydration() {
    _metadataHydrationTimer?.cancel();
    _metadataHydrationTimer = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      final posts = _posts.take(_metadataHydrationLimit).toList();
      _loadAuthors(posts);
      _loadReplyQuotes(posts);
      _loadLikeNames(posts);
      _loadThreadTargets(posts);
      _loadComments(posts);
    });
  }

  void _loadReplyQuotes(List<ChannelPost> posts) {
    for (final post in posts) {
      final message = post.message;
      final replyToMessageId = message.replyToMessageId;
      if (replyToMessageId == null || message.replyToPreview != null) {
        continue;
      }
      final key = '${post.channel.id}:${message.id}:$replyToMessageId';
      if (_loadingReplyQuotes.contains(key)) continue;
      _loadingReplyQuotes.add(key);
      _resolveReplyQuote(post, key);
    }
  }

  Future<void> _resolveReplyQuote(ChannelPost post, String key) async {
    final message = post.message;
    final replyToMessageId = message.replyToMessageId;
    if (replyToMessageId == null) {
      _loadingReplyQuotes.remove(key);
      return;
    }
    try {
      final raw = await TdClient.shared.query({
        '@type': 'getMessage',
        'chat_id': post.channel.id,
        'message_id': replyToMessageId,
      });
      final quoted = TDParse.message(raw);
      if (quoted == null) return;
      message.replyToPreview = _replyPreview(quoted);
      message.replyToImage = quoted.image;
      message.replyToImageWidth = quoted.imageWidth;
      message.replyToImageHeight = quoted.imageHeight;
      message.replyToSender = await _senderName(quoted) ?? post.channel.title;
    } catch (_) {
      message.replyToPreview ??= '';
      message.replyToSender ??= post.channel.title;
    } finally {
      _loadingReplyQuotes.remove(key);
      if (mounted) setState(() {});
    }
  }

  void _loadComments(List<ChannelPost> posts) {
    for (final post in posts) {
      if (post.message.commentCount <= 0) continue;
      final key = '${post.channel.id}:${post.message.id}';
      if (_loadingComments.contains(key) || post.comments != null) continue;
      _loadingComments.add(key);
      _loadCommentsForPost(post, key);
    }
  }

  void _loadThreadTargets(List<ChannelPost> posts) {
    for (final post in posts) {
      if (post.threadTarget != null) continue;
      final key = '${post.channel.id}:${post.message.id}';
      if (_loadingThreadTargets.contains(key)) continue;
      _loadingThreadTargets.add(key);
      _resolveThreadTarget(post, key);
    }
  }

  Future<ChannelPostThreadTarget?> _resolveThreadTarget(
    ChannelPost post, [
    String? loadingKey,
  ]) async {
    if (post.threadTarget != null) return post.threadTarget;
    final key = loadingKey ?? '${post.channel.id}:${post.message.id}';
    var shouldNotify = false;
    try {
      try {
        final properties = await TdClient.shared.query({
          '@type': 'getMessageProperties',
          'chat_id': post.channel.id,
          'message_id': post.message.id,
        });
        if (properties.boolean('can_get_message_thread') == false) return null;
      } catch (_) {}
      final thread = await TdClient.shared.query({
        '@type': 'getMessageThread',
        'chat_id': post.channel.id,
        'message_id': post.message.id,
      });
      final chatId = thread.int64('chat_id');
      final threadId = thread.int64('message_thread_id');
      if (chatId == null || threadId == null || threadId == 0) return null;
      final target = ChannelPostThreadTarget(
        chatId: chatId,
        messageThreadId: threadId,
      );
      post.threadTarget = target;
      shouldNotify = true;
      return target;
    } catch (_) {
      return null;
    } finally {
      _loadingThreadTargets.remove(key);
      if (shouldNotify && mounted) setState(() {});
    }
  }

  Future<void> _loadCommentsForPost(ChannelPost post, String key) async {
    try {
      final target = await _resolveThreadTarget(post);
      final response = await TdClient.shared.query({
        '@type': 'getMessageThreadHistory',
        'chat_id': post.channel.id,
        'message_id': post.message.id,
        'from_message_id': 0,
        'offset': 0,
        'limit': 5,
      });
      final rawMessages =
          response.objects('messages') ?? const <Map<String, dynamic>>[];
      final entries = <_LoadedPostComment>[];
      for (final raw in rawMessages) {
        final message = TDParse.message(raw);
        if (message == null ||
            message.isService ||
            message.id == post.message.id ||
            message.id == target?.messageThreadId ||
            _commentText(message).isEmpty) {
          continue;
        }
        entries.add(
          _LoadedPostComment(
            chatId: raw.int64('chat_id') ?? post.channel.id,
            message: message,
          ),
        );
      }
      entries.sort((a, b) => a.message.date.compareTo(b.message.date));
      final comments = <ChannelPostComment>[];
      for (final entry in entries.take(4)) {
        final message = entry.message;
        final senderName = await _senderName(message);
        comments.add(
          ChannelPostComment(
            chatId: entry.chatId,
            messageId: message.id,
            senderName: senderName ?? AppStringKeys.topicChatUsers,
            text: _commentText(message),
            entities: _commentEntities(message),
          ),
        );
      }
      post.comments = comments;
    } catch (_) {
      post.comments = const [];
    } finally {
      _loadingComments.remove(key);
      if (mounted) setState(() {});
    }
  }

  String _commentText(ChatMessage message) {
    final text = message.text.trim();
    if (text.startsWith('[') && text.endsWith(']')) return '';
    return text;
  }

  String _replyPreview(ChatMessage message) {
    if (message.document != null) {
      return AppStrings.t(AppStringKeys.composerFilePreview, {
        'value1': message.document!.fileName,
      });
    }
    if (message.voice != null) {
      return telegramText(AppStringKeys.composerVoicePreview);
    }
    if (message.location != null) {
      return telegramText(AppStringKeys.composerLocationPreview);
    }
    if (message.animatedSticker != null) {
      return telegramText(AppStringKeys.composerAnimatedEmojiPreview);
    }
    if (message.video != null) {
      final placeholder = telegramText(AppStringKeys.chatVideoPlaceholder);
      return message.text == placeholder ? '' : message.text;
    }
    if (message.image != null) {
      final placeholder = switch (message.contentType) {
        'messagePhoto' => telegramText(AppStringKeys.composerImagePreview),
        'messageAnimation' => telegramText(
          AppStringKeys.composerAnimatedEmojiPreview,
        ),
        _ => null,
      };
      return message.text == placeholder ? '' : message.text;
    }
    final text = message.text.trim();
    return text.isEmpty
        ? telegramText(AppStringKeys.chatSearchMessageResultLabel)
        : text;
  }

  List<MessageTextEntity> _commentEntities(ChatMessage message) {
    return message.text == message.text.trim()
        ? message.textEntities
        : const [];
  }

  void _appendPosts(int channelId, List<ChannelPost> posts) {
    final existing = _postsByChannel[channelId] ?? const <ChannelPost>[];
    final byId = <int, ChannelPost>{
      for (final post in existing) post.message.id: post,
    };
    for (final post in posts) {
      final previous = byId[post.message.id];
      if (previous != null) {
        post.threadTarget = previous.threadTarget;
        if (_isChannelSelfPost(post)) {
          post.authorName = null;
          post.authorPhoto = null;
        } else {
          post.authorName = previous.authorName;
          post.authorPhoto = previous.authorPhoto;
        }
        post.message.replyToSender = previous.message.replyToSender;
        post.message.replyToPreview = previous.message.replyToPreview;
        post.message.replyToImage = previous.message.replyToImage;
        post.message.replyToImageWidth = previous.message.replyToImageWidth;
        post.message.replyToImageHeight = previous.message.replyToImageHeight;
        final likesChanged =
            _reactionCount(previous.message) != _reactionCount(post.message);
        final commentsChanged =
            previous.message.commentCount != post.message.commentCount ||
            previous.message.lastCommentMessageId !=
                post.message.lastCommentMessageId;
        post.likeNames = likesChanged ? null : previous.likeNames;
        post.comments = commentsChanged ? null : previous.comments;
      }
      byId[post.message.id] = post;
    }
    final merged = byId.values.toList()
      ..sort((a, b) => b.message.date.compareTo(a.message.date));
    _postsByChannel[channelId] = merged;
    _invalidateFeed();
    if (merged.isNotEmpty) {
      _oldestMessageByChannel[channelId] = merged
          .map((post) => post.message.id)
          .reduce((a, b) => a < b ? a : b);
    }
  }

  void _loadLikeNames(List<ChannelPost> posts) {
    for (final post in posts) {
      if (_reactionCount(post.message) <= 0) continue;
      final key = '${post.channel.id}:${post.message.id}';
      if (_loadingLikeNames.contains(key) || post.likeNames != null) continue;
      _loadingLikeNames.add(key);
      _loadLikeNamesForPost(post, key);
    }
  }

  void _loadAuthors(List<ChannelPost> posts) {
    for (final post in posts) {
      if (_isChannelSelfPost(post)) {
        post.authorName = null;
        post.authorPhoto = null;
        continue;
      }
      if (post.authorName != null) continue;
      _resolvePostAuthor(post);
    }
  }

  Future<void> _resolvePostAuthor(ChannelPost post) async {
    if (_isChannelSelfPost(post)) {
      post.authorName = null;
      post.authorPhoto = null;
      return;
    }
    final senderId = post.message.senderId;
    try {
      if (senderId != null && senderId > 0) {
        final user = await TdClient.shared.query({
          '@type': 'getUser',
          'user_id': senderId,
        });
        final name = TDParse.userName(user).trim();
        if (name.isNotEmpty) post.authorName = name;
        post.authorPhoto = TDParse.smallPhoto(user.obj('profile_photo'));
      } else if (senderId != null && senderId < 0) {
        final chat = await TdClient.shared.query({
          '@type': 'getChat',
          'chat_id': senderId,
        });
        final name = chat.str('title')?.trim();
        if (name != null && name.isNotEmpty) post.authorName = name;
        post.authorPhoto = TDParse.smallPhoto(chat.obj('photo'));
      } else {
        final title = post.message.senderTitle?.trim();
        if (title != null && title.isNotEmpty) {
          post.authorName = title;
        }
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _loadLikeNamesForPost(ChannelPost post, String key) async {
    try {
      final response = await TdClient.shared.query({
        '@type': 'getMessageAddedReactions',
        'chat_id': post.channel.id,
        'message_id': post.message.id,
        'reaction_type': {'@type': 'reactionTypeEmoji', 'emoji': '👍'},
        'offset': '',
        'limit': 4,
      });
      final raw =
          response.objects('added_reactions') ??
          response.objects('reactions') ??
          const <Map<String, dynamic>>[];
      final names = <String>[];
      for (final item in raw) {
        final name = await _reactionSenderName(item.obj('sender_id'));
        if (name != null && !names.contains(name)) names.add(name);
      }
      post.likeNames = names;
    } catch (_) {
      post.likeNames = const [];
    } finally {
      _loadingLikeNames.remove(key);
      if (mounted) setState(() {});
    }
  }

  Future<String?> _reactionSenderName(Map<String, dynamic>? sender) async {
    try {
      switch (sender?.type) {
        case 'messageSenderUser':
          final userId = sender?.int64('user_id');
          if (userId == null) return null;
          final user = await TdClient.shared.query({
            '@type': 'getUser',
            'user_id': userId,
          });
          final name = TDParse.userName(user).trim();
          return name.isEmpty ? null : name;
        case 'messageSenderChat':
          final chatId = sender?.int64('chat_id');
          if (chatId == null) return null;
          final chat = await TdClient.shared.query({
            '@type': 'getChat',
            'chat_id': chatId,
          });
          final name = chat.str('title')?.trim();
          return name == null || name.isEmpty ? null : name;
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _senderName(ChatMessage message) async {
    final senderId = message.senderId;
    if (senderId == null) {
      final title = message.senderTitle?.trim();
      return title != null && title.isNotEmpty ? title : null;
    }
    try {
      if (senderId > 0) {
        final user = await TdClient.shared.query({
          '@type': 'getUser',
          'user_id': senderId,
        });
        final name = TDParse.userName(user).trim();
        return name.isEmpty ? null : name;
      }
      final chat = await TdClient.shared.query({
        '@type': 'getChat',
        'chat_id': senderId,
      });
      final name = chat.str('title')?.trim();
      return name == null || name.isEmpty ? null : name;
    } catch (_) {
      final title = message.senderTitle?.trim();
      return title != null && title.isNotEmpty ? title : null;
    }
  }

  int _reactionCount(ChatMessage message) =>
      message.reactions.fold<int>(0, (sum, reaction) => sum + reaction.count);

  void _beginReply(ChannelPost post) {
    setState(() {
      _replyPost = post;
      _replyController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _replyFocus.requestFocus();
    });
  }

  void _beginReplyFromInline(ChannelPost post, BuildContext anchorContext) {
    _beginReply(post);
    _hideInlineReplyBehindComposer(anchorContext);
  }

  Future<void> _hideInlineReplyBehindComposer(
    BuildContext anchorContext,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted || !_scroll.hasClients) return;
    if (!anchorContext.mounted) return;
    final box = anchorContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final media = MediaQuery.of(context);
    final bottomHiddenTop = media.size.height - media.viewInsets.bottom - 92;
    final bottom = box.localToGlobal(Offset.zero).dy + box.size.height;
    if (bottom >= bottomHiddenTop) return;
    final delta = bottomHiddenTop - bottom + 6;
    final next = (_scroll.offset - delta).clamp(
      _scroll.position.minScrollExtent,
      _scroll.position.maxScrollExtent,
    );
    if ((next - _scroll.offset).abs() < 1) return;
    unawaited(
      _scroll.animateTo(
        next,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Future<void> _sendQuickReply() async {
    final post = _replyPost;
    final text = _replyController.text.trim();
    if (post == null || text.isEmpty) return;
    try {
      final target = await _resolveThreadTarget(post);
      if (target == null) {
        if (mounted) {
          showToast(context, AppStringKeys.momentsReplyUnavailable);
        }
        return;
      }
      await _sendThreadReply(target, text);
      _replyController.clear();
      if (mounted) showToast(context, AppStringKeys.momentsReplied);
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.momentsReplyFailed, {'value1': e}),
        );
      }
    }
  }

  Future<void> _sendThreadReply(
    ChannelPostThreadTarget target,
    String text,
  ) async {
    final content = {
      '@type': 'inputMessageText',
      'text': {'@type': 'formattedText', 'text': text},
    };
    try {
      await TdClient.shared.query({
        '@type': 'sendMessage',
        'chat_id': target.chatId,
        'topic_id': {
          '@type': 'messageTopicThread',
          'message_thread_id': target.messageThreadId,
        },
        'input_message_content': content,
      });
    } catch (_) {
      await TdClient.shared.query({
        '@type': 'sendMessage',
        'chat_id': target.chatId,
        'reply_to': {
          '@type': 'inputMessageReplyToMessage',
          'message_id': target.messageThreadId,
        },
        'input_message_content': content,
      });
    }
  }

  Future<void> _openNewPostComposer() async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ChannelPostComposerView(
          channels: _postableChannels,
          initialChannel: _selectedPostChannel,
        ),
      ),
    );
    if (sent == true) {
      _refreshAfterPost();
    }
  }

  void _openPostDetail(ChannelPost post) {
    final detail = ChannelPostDetailView(
      post: post,
      showBackButton: widget.onOpenDetail == null,
    );
    if (widget.onOpenDetail != null) {
      widget.onOpenDetail!(detail);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => detail));
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChannelMomentsSearchView(
          channels: _channels,
          meName: _meName,
          mePhoto: _mePhoto,
        ),
      ),
    );
  }

  void _refreshAfterPost() {
    for (final channel in _postableChannels) {
      _exhaustedChannels.remove(channel.id);
      _oldestMessageByChannel.remove(channel.id);
      _postsByChannel.remove(channel.id);
    }
    _invalidateFeed();
    _loadChannelPosts();
  }

  Color _profileHeaderColor(BuildContext context) {
    final colorId = _meProfileAccentColorId >= 0
        ? _meProfileAccentColorId
        : _meAccentColorId;
    if (colorId >= 0 && colorId < kAccentColors.length) {
      return kAccentColors[colorId].withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.30 : 0.17,
      );
    }
    return AppTheme.brand.withValues(
      alpha: Theme.of(context).brightness == Brightness.dark ? 0.25 : 0.13,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final posts = _posts;
    return Material(
      color: c.groupedBackground,
      child: Column(
        children: [
          NavHeader(
            title: widget.title.l10n(context),
            onBack: widget.isRootTab ? null : () => Navigator.of(context).pop(),
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
                          ? HeroAppIcons.solidBell.data
                          : HeroAppIcons.bellSlash.data,
                      size: 24,
                      color: _nonMutedOnly ? AppTheme.brand : c.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _openSearch,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
                    child: AppIcon(
                      HeroAppIcons.magnifyingGlass,
                      size: 25,
                      color: c.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: c.background,
              child: ListView.builder(
                controller: _scroll,
                padding: EdgeInsets.zero,
                itemCount: posts.isEmpty ? 2 : posts.length + 1,
                findChildIndexCallback: (key) => _feedIndexByKey[key],
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return KeyedSubtree(
                      key: _composerHeaderKey,
                      child: _MomentsComposerHeader(
                        meName: _meName,
                        mePhoto: _mePhoto,
                        backgroundColor: _profileHeaderColor(context),
                        canCompose: _postableChannels.isNotEmpty,
                        onCompose: _openNewPostComposer,
                      ),
                    );
                  }
                  if (posts.isEmpty) {
                    return SizedBox(height: 260, child: _empty());
                  }
                  final post = posts[i - 1];
                  return KeyedSubtree(
                    key: _postKey(post),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ChannelPostRow(
                          post: post,
                          meName: _meName,
                          mePhoto: _mePhoto,
                          onOpenPost: _openPostDetail,
                          onComment: _beginReplyFromInline,
                        ),
                        if (i != posts.length)
                          const InsetDivider(leadingInset: 0),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          if (_replyPost != null) _quickReplyBar(),
        ],
      ),
    );
  }

  Widget _quickReplyBar() {
    final c = context.colors;
    final post = _replyPost!;
    return Material(
      color: c.navBar,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: c.navBar,
            border: Border(top: BorderSide(color: c.divider, width: 0.5)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  AppIcon(
                    HeroAppIcons.solidFaceSmile,
                    size: 24,
                    color: c.textPrimary,
                  ),
                  const SizedBox(width: 18),
                  AppIcon(HeroAppIcons.font, size: 24, color: c.textPrimary),
                  const SizedBox(width: 18),
                  AppIcon(HeroAppIcons.image, size: 24, color: c.textPrimary),
                  const SizedBox(width: 18),
                  AppIcon(HeroAppIcons.at, size: 24, color: c.textPrimary),
                  const Spacer(),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() => _replyPost = null);
                      _replyFocus.unfocus();
                    },
                    child: AppIcon(
                      HeroAppIcons.xmark,
                      size: 20,
                      color: c.textTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(minHeight: 38),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: c.searchFill,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _replyController,
                        focusNode: _replyFocus,
                        minLines: 1,
                        maxLines: 3,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendQuickReply(),
                        style: TextStyle(fontSize: 16, color: c.textPrimary),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isCollapsed: true,
                          hintText: AppStrings.t(
                            AppStringKeys.momentsReplyToPlaceholder,
                            {'value1': post.channel.title},
                          ),
                          hintStyle: TextStyle(color: c.textTertiary),
                        ),
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _sendQuickReply,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: AppIcon(
                          HeroAppIcons.solidPaperPlane,
                          size: 22,
                          color: AppTheme.brand,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    final c = context.colors;
    final loading = _loadingPosts || _loadingChannels.isNotEmpty;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          loading
              ? const CircularProgressIndicator()
              : AppIcon(
                  HeroAppIcons.towerBroadcast,
                  size: 46,
                  color: AppTheme.brand,
                ),
          const SizedBox(height: 12),
          Text(
            (loading
                    ? AppStrings.t(AppStringKeys.channelsLoading)
                    : AppStringKeys.momentsNoChannelContent)
                .l10n(context),
            style: TextStyle(fontSize: 15, color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _MomentsComposerHeader extends StatelessWidget {
  const _MomentsComposerHeader({
    required this.meName,
    this.mePhoto,
    required this.backgroundColor,
    required this.canCompose,
    required this.onCompose,
  });

  final String meName;
  final TdFileRef? mePhoto;
  final Color backgroundColor;
  final bool canCompose;
  final VoidCallback onCompose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      color: c.background,
      child: Column(
        children: [
          Container(
            height: 166,
            color: backgroundColor,
            child: Stack(
              children: [
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 20,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      PhotoAvatar(title: meName, photo: mePhoto, size: 74),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                meName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w600,
                                  color: c.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (canCompose)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: c.background,
                  border: Border.all(color: c.divider),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onCompose,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        AppStringKeys.momentsShareSomethingPlaceholder.l10n(
                          context,
                        ),
                        style: TextStyle(fontSize: 14, color: c.textTertiary),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ChannelMomentsSearchView extends StatefulWidget {
  const ChannelMomentsSearchView({
    super.key,
    required this.channels,
    required this.meName,
    this.mePhoto,
  });

  final List<ChatSummary> channels;
  final String meName;
  final TdFileRef? mePhoto;

  @override
  State<ChannelMomentsSearchView> createState() =>
      _ChannelMomentsSearchViewState();
}

class _ChannelMomentsSearchViewState extends State<ChannelMomentsSearchView> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  String _query = '';
  bool _loading = false;
  List<ChannelPost> _results = const [];

  List<ChatSummary> get _channels =>
      widget.channels.where((chat) => chat.kind == ChatKind.channel).toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _loading = false;
        _results = const [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(query));
  }

  Future<void> _run(String query) async {
    final channels = _channels;
    if (channels.isEmpty) {
      setState(() {
        _loading = false;
        _results = const [];
      });
      return;
    }
    setState(() => _loading = true);
    final currentQuery = query;
    try {
      final batches = await Future.wait(
        channels.map((channel) => _searchChannel(channel, currentQuery)),
      );
      final results = batches.expand((items) => items).toList()
        ..sort((a, b) => b.message.date.compareTo(a.message.date));
      if (!mounted || _query.trim() != currentQuery) return;
      setState(() {
        _results = results.take(120).toList();
        _loading = false;
      });
      _hydrateAuthors(_results);
    } catch (_) {
      if (mounted && _query.trim() == currentQuery) {
        setState(() => _loading = false);
      }
    }
  }

  Future<List<ChannelPost>> _searchChannel(
    ChatSummary channel,
    String query,
  ) async {
    try {
      final response = await TdClient.shared.query({
        '@type': 'searchChatMessages',
        'chat_id': channel.id,
        'query': query,
        'sender_id': null,
        'from_message_id': 0,
        'offset': 0,
        'limit': 30,
        'filter': {'@type': 'searchMessagesFilterEmpty'},
      });
      final rawMessages =
          response.objects('messages') ?? const <Map<String, dynamic>>[];
      return [
        for (final raw in rawMessages)
          if ((raw.int64('chat_id') ?? channel.id) == channel.id)
            if (TDParse.message(raw) case final message?)
              if (!message.isService)
                ChannelPost(channel: channel, message: message),
      ];
    } catch (_) {
      return const [];
    }
  }

  void _hydrateAuthors(List<ChannelPost> posts) {
    for (final post in posts) {
      if (_isChannelSelfPost(post)) {
        post.authorName = null;
        post.authorPhoto = null;
        continue;
      }
      if (post.authorName != null) continue;
      unawaited(_resolvePostAuthor(post));
    }
  }

  Future<void> _resolvePostAuthor(ChannelPost post) async {
    if (_isChannelSelfPost(post)) {
      post.authorName = null;
      post.authorPhoto = null;
      return;
    }
    final senderId = post.message.senderId;
    try {
      if (senderId != null && senderId > 0) {
        final user = await TdClient.shared.query({
          '@type': 'getUser',
          'user_id': senderId,
        });
        final name = TDParse.userName(user).trim();
        if (name.isNotEmpty) post.authorName = name;
        post.authorPhoto = TDParse.smallPhoto(user.obj('profile_photo'));
      } else if (senderId != null && senderId < 0) {
        final chat = await TdClient.shared.query({
          '@type': 'getChat',
          'chat_id': senderId,
        });
        final name = chat.str('title')?.trim();
        if (name != null && name.isNotEmpty) post.authorName = name;
        post.authorPhoto = TDParse.smallPhoto(chat.obj('photo'));
      } else {
        final title = post.message.senderTitle?.trim();
        if (title != null && title.isNotEmpty) {
          post.authorName = title;
        }
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _openPost(ChannelPost post) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChannelPostDetailView(post: post)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          _header(),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _header() {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SizedBox(
        height: 50,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: AppIcon(
                    HeroAppIcons.chevronLeft,
                    size: 22,
                    color: c.textPrimary,
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: c.searchFill,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      AppIcon(
                        HeroAppIcons.magnifyingGlass,
                        size: 15,
                        color: c.textTertiary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focus,
                          autocorrect: false,
                          textInputAction: TextInputAction.search,
                          style: TextStyle(fontSize: 15, color: c.textPrimary),
                          decoration: InputDecoration(
                            hintText: AppStrings.t(
                              AppStringKeys.momentsSearchChannelPosts,
                            ).l10n(context),
                            hintStyle: TextStyle(color: c.textTertiary),
                            border: InputBorder.none,
                            isCollapsed: true,
                          ),
                          onChanged: _onChanged,
                          onSubmitted: (value) => _run(value.trim()),
                        ),
                      ),
                      if (_query.isNotEmpty)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            _controller.clear();
                            _onChanged('');
                          },
                          child: AppIcon(
                            HeroAppIcons.xmark,
                            size: 16,
                            color: c.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    final c = context.colors;
    if (_channels.isEmpty) {
      return Center(
        child: Text(
          AppStringKeys.momentsNoSearchableChannels.l10n(context),
          style: TextStyle(fontSize: 14, color: c.textSecondary),
        ),
      );
    }
    if (_loading && _results.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator.adaptive(strokeWidth: 2),
        ),
      );
    }
    if (_query.trim().isEmpty) {
      return Center(
        child: Text(
          AppStringKeys.momentsSearchJoinedChannelPosts.l10n(context),
          style: TextStyle(fontSize: 14, color: c.textSecondary),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          (_loading
                  ? AppStringKeys.momentsSearching
                  : AppStringKeys.momentsNoPostsFound)
              .l10n(context),
          style: TextStyle(fontSize: 14, color: c.textSecondary),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final post = _results[index];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChannelPostRow(
              post: post,
              meName: widget.meName,
              mePhoto: widget.mePhoto,
              onOpenPost: _openPost,
              showInlineReply: false,
              showInlineComments: false,
            ),
            if (index != _results.length - 1)
              const InsetDivider(leadingInset: 0),
          ],
        );
      },
    );
  }
}

void openChannelPostOriginal(BuildContext context, ChannelPost post) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChatView(
        chatId: post.channel.id,
        title: post.channel.title,
        initialMessageId: post.message.id,
      ),
    ),
  );
}

Future<void> showChannelPostMenu(BuildContext context, ChannelPost post) {
  final anchor = context.findRenderObject() as RenderBox?;
  final overlay =
      Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
  if (anchor == null || overlay == null) {
    openChannelPostOriginal(context, post);
    return Future.value();
  }
  final anchorTopLeft = anchor.localToGlobal(Offset.zero, ancestor: overlay);
  final anchorBottomRight = anchor.localToGlobal(
    anchor.size.bottomRight(Offset.zero),
    ancestor: overlay,
  );
  final anchorRect = Rect.fromLTRB(
    anchorTopLeft.dx,
    anchorTopLeft.dy,
    anchorBottomRight.dx,
    anchorBottomRight.dy + 4,
  );
  return showMenu<_ChannelPostMenuAction>(
    context: context,
    position: RelativeRect.fromRect(anchorRect, Offset.zero & overlay.size),
    color: context.colors.card,
    elevation: 8,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    items: [
      PopupMenuItem<_ChannelPostMenuAction>(
        value: _ChannelPostMenuAction.openOriginal,
        height: AppMetric.menuRowHeight,
        child: Row(
          children: [
            SizedBox(
              width: AppMetric.menuIconSlot,
              child: AppIcon(
                HeroAppIcons.rightFromBracket,
                size: AppIconSize.lg + 1,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(width: AppSpacing.xl),
            Text(
              AppStringKeys.momentsOpenOriginalMessage.l10n(context),
              style: TextStyle(
                fontSize: AppTextSize.bodyLarge,
                color: context.colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    ],
  ).then((action) {
    if (!context.mounted) return;
    switch (action) {
      case _ChannelPostMenuAction.openOriginal:
        openChannelPostOriginal(context, post);
      case null:
        break;
    }
  });
}

enum _ChannelPostMenuAction { openOriginal }

class _ChannelPostOverflowButton extends StatelessWidget {
  const _ChannelPostOverflowButton({required this.post});

  final ChannelPost post;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showChannelPostMenu(context, post),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
        child: AppIcon(HeroAppIcons.ellipsis, size: 22, color: c.textTertiary),
      ),
    );
  }
}

class ChannelPostDetailView extends StatefulWidget {
  const ChannelPostDetailView({
    super.key,
    required this.post,
    this.showBackButton = true,
  });

  final ChannelPost post;
  final bool showBackButton;

  @override
  State<ChannelPostDetailView> createState() => _ChannelPostDetailViewState();
}

class _ChannelPostDetailViewState extends State<ChannelPostDetailView> {
  final _replyController = TextEditingController();
  final _replyFocus = FocusNode();
  StreamSubscription? _tdSub;
  Timer? _refreshTimer;
  ChannelPostThreadTarget? _target;
  List<ChannelPostComment> _comments = const [];
  ChannelPostComment? _replyTo;
  String _meName = AppStringKeys.chatMeLabel;
  TdFileRef? _mePhoto;
  bool _loading = true;
  bool _sending = false;

  ChannelPost get post => widget.post;

  @override
  void initState() {
    super.initState();
    _target = post.threadTarget;
    _tdSub = TdClient.shared.subscribe().listen(_handleTdUpdate);
    _loadMe();
    _loadComments();
  }

  @override
  void dispose() {
    _tdSub?.cancel();
    _refreshTimer?.cancel();
    _replyController.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  Future<void> _loadMe() async {
    try {
      final me = await TdClient.shared.query({'@type': 'getMe'});
      if (!mounted) return;
      final name = TDParse.userName(me).trim();
      setState(() {
        if (name.isNotEmpty) _meName = name;
        _mePhoto = TDParse.smallPhoto(me.obj('profile_photo'));
      });
    } catch (_) {}
  }

  void _handleTdUpdate(Map<String, dynamic> update) {
    final rawMessage = update.obj('message');
    final chatId = update.int64('chat_id') ?? rawMessage?.int64('chat_id');
    final target = _target;
    final touchesPost = chatId == post.channel.id;
    final touchesThread = target != null && chatId == target.chatId;
    if (!touchesPost && !touchesThread) return;
    switch (update.type) {
      case 'updateNewMessage':
      case 'updateMessageContent':
      case 'updateMessageEdited':
      case 'updateMessageInteractionInfo':
      case 'updateDeleteMessages':
        _refreshTimer?.cancel();
        _refreshTimer = Timer(const Duration(milliseconds: 350), _loadComments);
    }
  }

  Future<ChannelPostThreadTarget?> _resolveThreadTarget() async {
    if (_target != null) return _target;
    try {
      final thread = await TdClient.shared.query({
        '@type': 'getMessageThread',
        'chat_id': post.channel.id,
        'message_id': post.message.id,
      });
      final chatId = thread.int64('chat_id');
      final threadId = thread.int64('message_thread_id');
      if (chatId == null || threadId == null || threadId == 0) return null;
      final target = ChannelPostThreadTarget(
        chatId: chatId,
        messageThreadId: threadId,
      );
      post.threadTarget = target;
      _target = target;
      return target;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadComments() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final target = await _resolveThreadTarget();
      if (target == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final response = await TdClient.shared.query({
        '@type': 'getMessageThreadHistory',
        'chat_id': post.channel.id,
        'message_id': post.message.id,
        'from_message_id': 0,
        'offset': 0,
        'limit': 120,
      });
      final rawMessages =
          response.objects('messages') ?? const <Map<String, dynamic>>[];
      final comments = <ChannelPostComment>[];
      for (final raw in rawMessages) {
        final message = TDParse.message(raw);
        if (message == null ||
            message.isService ||
            message.id == post.message.id ||
            message.id == target.messageThreadId ||
            _commentText(message).isEmpty) {
          continue;
        }
        final sender = await _commentSender(message);
        comments.add(
          ChannelPostComment(
            chatId: raw.int64('chat_id') ?? target.chatId,
            messageId: message.id,
            senderName: sender.name,
            senderPhoto: sender.photo,
            text: _commentText(message),
            entities: _commentEntities(message),
            date: message.date,
            replyToMessageId: message.replyToMessageId,
            reactionCount: _reactionCount(message),
          ),
        );
      }
      comments.sort((a, b) => a.date.compareTo(b.date));
      if (!mounted) return;
      setState(() {
        _comments = comments;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _commentText(ChatMessage message) {
    final text = message.text.trim();
    if (text.startsWith('[') && text.endsWith(']')) return '';
    return text;
  }

  List<MessageTextEntity> _commentEntities(ChatMessage message) {
    return message.text == message.text.trim()
        ? message.textEntities
        : const [];
  }

  int _reactionCount(ChatMessage message) =>
      message.reactions.fold<int>(0, (sum, reaction) => sum + reaction.count);

  Future<_CommentSender> _commentSender(ChatMessage message) async {
    final title = message.senderTitle?.trim();
    final senderId = message.senderId;
    try {
      if (senderId != null && senderId > 0) {
        final user = await TdClient.shared.query({
          '@type': 'getUser',
          'user_id': senderId,
        });
        final name = TDParse.userName(user).trim();
        return _CommentSender(
          name: name.isNotEmpty ? name : title ?? AppStringKeys.topicChatUsers,
          photo: TDParse.smallPhoto(user.obj('profile_photo')),
        );
      }
      if (senderId != null && senderId < 0) {
        final chat = await TdClient.shared.query({
          '@type': 'getChat',
          'chat_id': senderId,
        });
        final name = chat.str('title')?.trim();
        return _CommentSender(
          name: name == null || name.isEmpty
              ? title ?? AppStringKeys.topicChatUsers
              : name,
          photo: TDParse.smallPhoto(chat.obj('photo')),
        );
      }
    } catch (_) {}
    return _CommentSender(
      name: title == null || title.isEmpty
          ? AppStringKeys.topicChatUsers
          : title,
    );
  }

  void _beginReply([ChannelPostComment? comment]) {
    setState(() => _replyTo = comment);
    _replyFocus.requestFocus();
  }

  Future<void> _sendReply() async {
    final target = await _resolveThreadTarget();
    final text = _replyController.text.trim();
    if (target == null || text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final replyTo = _replyTo;
    final content = {
      '@type': 'inputMessageText',
      'text': {'@type': 'formattedText', 'text': text},
    };
    try {
      final replyMessageId = replyTo?.messageId;
      if (replyMessageId == null) {
        await TdClient.shared.query({
          '@type': 'sendMessage',
          'chat_id': target.chatId,
          'topic_id': {
            '@type': 'messageTopicThread',
            'message_thread_id': target.messageThreadId,
          },
          'input_message_content': content,
        });
      } else {
        try {
          await TdClient.shared.query({
            '@type': 'sendMessage',
            'chat_id': target.chatId,
            'topic_id': {
              '@type': 'messageTopicThread',
              'message_thread_id': target.messageThreadId,
            },
            'reply_to': {
              '@type': 'inputMessageReplyToMessage',
              'message_id': replyMessageId,
            },
            'input_message_content': content,
          });
        } catch (_) {
          await TdClient.shared.query({
            '@type': 'sendMessage',
            'chat_id': target.chatId,
            'reply_to': {
              '@type': 'inputMessageReplyToMessage',
              'message_id': replyMessageId,
            },
            'input_message_content': content,
          });
        }
      }
      _replyController.clear();
      if (!mounted) return;
      setState(() => _replyTo = null);
      await _loadComments();
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.momentsReplyFailed, {'value1': e}),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _likeComment(ChannelPostComment comment) async {
    try {
      await TdClient.shared.query({
        '@type': 'addMessageReaction',
        'chat_id': comment.chatId,
        'message_id': comment.messageId,
        'reaction_type': {'@type': 'reactionTypeEmoji', 'emoji': '👍'},
        'is_big': false,
        'update_recent_reactions': true,
      });
      unawaited(_loadComments());
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.momentsLikeFailed, {'value1': e}),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.momentsDetails,
            onBack: widget.showBackButton
                ? () => Navigator.of(context).pop()
                : null,
            trailing: Builder(
              builder: (menuContext) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => showChannelPostMenu(menuContext, post),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: AppIcon(
                      HeroAppIcons.ellipsis,
                      size: 24,
                      color: c.textPrimary,
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ChannelPostRow(
                  post: post,
                  meName: '',
                  showInlineReply: false,
                  showInlineComments: false,
                ),
                const InsetDivider(leadingInset: 14),
                if (_loading && _comments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  _CommentThreadList(
                    post: post,
                    comments: _comments,
                    onReply: _beginReply,
                    onLike: _likeComment,
                  ),
              ],
            ),
          ),
          if (_target != null || post.message.hasCommentThread)
            _bottomReplyBar(),
        ],
      ),
    );
  }

  Widget _bottomReplyBar() {
    final c = context.colors;
    final replyTo = _replyTo;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        decoration: BoxDecoration(
          color: c.background,
          border: Border(top: BorderSide(color: c.divider)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (replyTo != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppStrings.t(AppStringKeys.momentsReplyToUser, {
                          'value1': replyTo.senderName,
                        }),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: c.linkBlue),
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _replyTo = null),
                      child: AppIcon(
                        HeroAppIcons.solidCircleXmark,
                        size: 18,
                        color: c.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              constraints: const BoxConstraints(minHeight: 42),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: _momentQuoteFill(c),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  PhotoAvatar(title: _meName, photo: _mePhoto, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _replyController,
                      focusNode: _replyFocus,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.send,
                      onTap: () => _beginReply(_replyTo),
                      onSubmitted: (_) => _sendReply(),
                      style: TextStyle(fontSize: 15, color: c.textPrimary),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isCollapsed: true,
                        hintText: replyTo == null
                            ? AppStrings.t(
                                AppStringKeys.momentsCommentPlaceholder,
                              )
                            : AppStrings.t(
                                AppStringKeys.momentsReplyToUserPlaceholder,
                                {'value1': replyTo.senderName},
                              ),
                        hintStyle: TextStyle(color: c.textTertiary),
                      ),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _sendReply,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: AppIcon(
                        HeroAppIcons.solidPaperPlane,
                        size: 21,
                        color: AppTheme.brand.withValues(
                          alpha: _sending ? 0.45 : 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentSender {
  const _CommentSender({required this.name, this.photo});

  final String name;
  final TdFileRef? photo;
}

class _CommentThreadList extends StatelessWidget {
  const _CommentThreadList({
    required this.post,
    required this.comments,
    required this.onReply,
    required this.onLike,
  });

  final ChannelPost post;
  final List<ChannelPostComment> comments;
  final ValueChanged<ChannelPostComment> onReply;
  final ValueChanged<ChannelPostComment> onLike;

  @override
  Widget build(BuildContext context) {
    if (comments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Text(
            AppStringKeys.momentsNoComments.l10n(context),
            style: TextStyle(fontSize: 14, color: context.colors.textTertiary),
          ),
        ),
      );
    }
    final byId = {for (final comment in comments) comment.messageId: comment};
    final roots = comments.where((comment) => _isRoot(comment, byId)).toList();
    final childrenByRoot = <int, List<ChannelPostComment>>{};
    for (final comment in comments) {
      if (_isRoot(comment, byId)) continue;
      final rootId = _rootId(comment, byId);
      childrenByRoot.putIfAbsent(rootId, () => []).add(comment);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
      child: Column(
        children: [
          for (final root in roots) ...[
            _DetailCommentTile(comment: root, onReply: onReply, onLike: onLike),
            for (final child
                in childrenByRoot[root.messageId] ??
                    const <ChannelPostComment>[])
              _DetailCommentTile(
                comment: child,
                prefix: _replyPrefix(child, root, byId),
                nested: true,
                onReply: onReply,
                onLike: onLike,
              ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  bool _isRoot(ChannelPostComment comment, Map<int, ChannelPostComment> byId) {
    final replyTo = comment.replyToMessageId;
    return replyTo == null ||
        replyTo == post.message.id ||
        replyTo == post.threadTarget?.messageThreadId ||
        !byId.containsKey(replyTo);
  }

  int _rootId(ChannelPostComment comment, Map<int, ChannelPostComment> byId) {
    var current = comment;
    final seen = <int>{};
    while (current.replyToMessageId != null &&
        byId.containsKey(current.replyToMessageId) &&
        seen.add(current.messageId)) {
      final parent = byId[current.replyToMessageId]!;
      if (_isRoot(parent, byId)) return parent.messageId;
      current = parent;
    }
    return current.messageId;
  }

  String? _replyPrefix(
    ChannelPostComment comment,
    ChannelPostComment root,
    Map<int, ChannelPostComment> byId,
  ) {
    final replyTo = comment.replyToMessageId;
    if (replyTo == null || replyTo == root.messageId) return null;
    final parent = byId[replyTo];
    if (parent == null) return null;
    return AppStrings.t(AppStringKeys.momentsReplyPrefix, {
      'value1': parent.senderName,
    });
  }
}

class _DetailCommentTile extends StatelessWidget {
  const _DetailCommentTile({
    required this.comment,
    required this.onReply,
    required this.onLike,
    this.prefix,
    this.nested = false,
  });

  final ChannelPostComment comment;
  final String? prefix;
  final bool nested;
  final ValueChanged<ChannelPostComment> onReply;
  final ValueChanged<ChannelPostComment> onLike;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final avatarSize = nested ? 30.0 : 38.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onReply(comment),
      child: Padding(
        padding: EdgeInsets.only(left: nested ? 52 : 0, top: nested ? 10 : 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PhotoAvatar(
              title: comment.senderName,
              photo: comment.senderPhoto,
              size: avatarSize,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          comment.senderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: c.linkBlue,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateText.listLabel(comment.date),
                        style: TextStyle(fontSize: 13, color: c.textTertiary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    children: [
                      if (prefix != null)
                        Text(
                          prefix!,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.28,
                            color: c.textSecondary,
                          ),
                        ),
                      TelegramRichText(
                        text: comment.text,
                        entities: comment.entities,
                        quoteBackgroundColor: _momentQuoteFill(c),
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.28,
                          color: c.textPrimary,
                        ),
                        onMentionTap: (userId, name) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ProfileDetailView(userId: userId, name: name),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onLike(comment),
              child: SizedBox(
                width: 34,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      HeroAppIcons.thumbsUp,
                      size: 21,
                      color: c.textTertiary,
                    ),
                    if (comment.reactionCount > 0) ...[
                      const SizedBox(height: 3),
                      Text(
                        _compactCount(comment.reactionCount),
                        style: TextStyle(fontSize: 12, color: c.textTertiary),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _compactCount(int count) {
    if (count > 99) return '99+';
    return '$count';
  }
}

class ChannelPostComposerView extends StatefulWidget {
  const ChannelPostComposerView({
    super.key,
    required this.channels,
    this.initialChannel,
  });

  final List<ChatSummary> channels;
  final ChatSummary? initialChannel;

  @override
  State<ChannelPostComposerView> createState() =>
      _ChannelPostComposerViewState();
}

class _ChannelPostComposerViewState extends State<ChannelPostComposerView> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final List<OutgoingAttachment> _attachments = [];
  FormattedTextPayload? _richTextPayload;
  ChatSummary? _channel;
  bool _notifySubscribers = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _channel =
        widget.initialChannel ??
        (widget.channels.isNotEmpty ? widget.channels.first : null);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          _header(),
          Expanded(
            child: ListView(
              padding: AppInsets.composerScreen,
              children: [
                _editorCard(),
                const SizedBox(height: AppSpacing.xl),
                _publishSettingsCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top,
        left: AppSpacing.xxl,
        right: AppSpacing.xxl,
      ),
      height:
          MediaQuery.of(context).padding.top + AppMetric.composerHeaderHeight,
      color: c.groupedBackground,
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(false),
            child: Text(
              AppStringKeys.countryPickerCancel.l10n(context),
              style: AppTextStyle.bodyLarge(c.textPrimary),
            ),
          ),
          const Spacer(),
          Text(
            AppStringKeys.momentsCreatePostTitle.l10n(context),
            style: AppTextStyle.title(
              c.textPrimary,
              weight: AppTextWeight.semibold,
            ),
          ),
          const Spacer(),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _sending ? null : _send,
            child: Container(
              height: AppMetric.composerPublishButtonHeight,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xxl + AppSpacing.xxs,
              ),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.brand.withValues(alpha: _canSend ? 1 : 0.45),
                borderRadius: BorderRadius.circular(AppRadius.md + 1),
              ),
              child: Text(
                (_sending
                        ? AppStringKeys.momentsSending
                        : AppStringKeys.momentsPostAction)
                    .l10n(context),
                style: AppTextStyle.bodyLarge(
                  Colors.white,
                  weight: AppTextWeight.medium,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editorCard() {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.xl,
        AppSpacing.xxl,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            focusNode: _focus,
            autofocus: true,
            minLines: 9,
            maxLines: 16,
            textInputAction: TextInputAction.newline,
            contextMenuBuilder: (context, editableTextState) {
              return AdaptiveTextSelectionToolbar.editableText(
                editableTextState: editableTextState,
              );
            },
            style: AppTextStyle.bodyLarge(c.textPrimary).copyWith(height: 1.4),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: AppStringKeys.momentsShareSomethingPlaceholder.l10n(
                context,
              ),
              hintStyle: AppTextStyle.bodyLarge(c.textTertiary),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          _mediaStrip(),
          const SizedBox(height: AppSpacing.lg),
          _markdownToolbar(),
        ],
      ),
    );
  }

  Widget _mediaStrip() {
    final children = <Widget>[
      for (var i = 0; i < _attachments.length; i++) _imageTile(i),
      if (_attachments.length < 10) _addImageTile(),
    ];
    return SizedBox(
      height: AppMetric.mediaTile,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (_, index) => children[index],
      ),
    );
  }

  Widget _imageTile(int index) {
    final attachment = _attachments[index];
    final isVisual =
        attachment.kind == OutgoingAttachmentKind.photo ||
        attachment.kind == OutgoingAttachmentKind.video;
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: isVisual
              ? Image.file(
                  File(attachment.path),
                  width: AppMetric.mediaTile,
                  height: AppMetric.mediaTile,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _postAttachmentIcon(attachment),
                )
              : _postAttachmentIcon(attachment),
        ),
        Positioned(
          top: AppSpacing.xs,
          right: AppSpacing.xs,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _attachments.removeAt(index)),
            child: Container(
              width: AppMetric.overlayCloseButton,
              height: AppMetric.overlayCloseButton,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: const AppIcon(
                HeroAppIcons.xmark,
                size: AppIconSize.xs,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _postAttachmentIcon(OutgoingAttachment attachment) {
    final c = context.colors;
    return Container(
      width: AppMetric.mediaTile,
      height: AppMetric.mediaTile,
      color: c.searchFill,
      alignment: Alignment.center,
      child: AppIcon(switch (attachment.kind) {
        OutgoingAttachmentKind.photo => HeroAppIcons.image,
        OutgoingAttachmentKind.video ||
        OutgoingAttachmentKind.animation => HeroAppIcons.video,
        OutgoingAttachmentKind.document => HeroAppIcons.file,
        OutgoingAttachmentKind.audio => HeroAppIcons.music,
      }, color: c.textTertiary),
    );
  }

  Widget _addImageTile() {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _pickImages,
      child: Container(
        width: AppMetric.mediaTile,
        height: AppMetric.mediaTile,
        decoration: BoxDecoration(
          color: c.searchFill,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(
              HeroAppIcons.image,
              size: AppIconSize.add,
              color: c.textTertiary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              AppStringKeys.richTextComposerPhotoVideo.l10n(context),
              style: AppTextStyle.footnote(c.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _markdownToolbar() {
    final c = context.colors;
    return Row(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(_openRichTextComposer()),
          child: Container(
            height: AppMetric.composerFormatButtonHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.searchFill,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  HeroAppIcons.penToSquare,
                  size: AppIconSize.sm,
                  color: c.textSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  AppStringKeys.composerRichText.l10n(context),
                  style: AppTextStyle.body(
                    c.textPrimary,
                    weight: AppTextWeight.semibold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        Text(
          AppStringKeys.markdownLabel.l10n(context),
          style: AppTextStyle.caption(c.textTertiary),
        ),
      ],
    );
  }

  Future<void> _openRichTextComposer() async {
    final result = await showRichTextComposerSheet(
      context,
      initialText: _controller.text,
      title: AppStringKeys.momentsCreatePostTitle,
      submitText: AppStringKeys.addMembersDone,
      hintText: AppStringKeys.momentsShareSomethingPlaceholder,
      initialAttachments: _attachments,
    );
    if (result == null || !mounted) return;
    setState(() {
      _controller.text = result.text;
      _richTextPayload = result.formattedText;
      _attachments
        ..clear()
        ..addAll(result.attachments);
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
  }

  Widget _publishSettingsCard() {
    final c = context.colors;
    return SettingsCard(
      children: [
        SettingsRow(
          leading: AppIcon(
            HeroAppIcons.paperPlane,
            size: AppIconSize.nav,
            color: c.textPrimary,
          ),
          title: AppStringKeys.momentsPublishTo,
          value: _channel?.title ?? AppStringKeys.momentsSelectChannel,
          onTap: _selectChannel,
          leadingInset: AppSpacing.xxl + AppSpacing.xxs,
          height: AppMetric.settingsRowHeight - AppSpacing.xxs,
        ),
        const InsetDivider(leadingInset: AppMetric.settingsIconDividerInset),
        SettingsSwitchRow(
          leading: AppIcon(
            HeroAppIcons.bell,
            size: AppIconSize.nav,
            color: c.textPrimary,
          ),
          title: AppStringKeys.momentsNotifySubscribers,
          value: _notifySubscribers,
          onChanged: (value) => setState(() => _notifySubscribers = value),
          leadingInset: AppSpacing.xxl + AppSpacing.xxs,
          height: AppMetric.settingsRowHeight - AppSpacing.xxs,
        ),
      ],
    );
  }

  bool get _canSend =>
      _channel != null &&
      (_controller.text.trim().isNotEmpty || _attachments.isNotEmpty);

  Future<void> _pickImages() async {
    try {
      final remaining = 10 - _attachments.length;
      final images = await AppAssetPicker.pick(
        context,
        type: AppAssetPickerType.image,
        maxAssets: remaining,
      );
      if (images.isEmpty || !mounted) return;
      setState(() {
        _attachments.addAll(
          images.map(
            (image) => OutgoingAttachment(
              path: image.path,
              kind: OutgoingAttachmentKind.photo,
            ),
          ),
        );
      });
    } catch (_) {
      if (mounted) showToast(context, AppStringKeys.momentsPickPhotoFailed);
    }
  }

  Future<void> _selectChannel() async {
    if (widget.channels.isEmpty) {
      showToast(context, AppStringKeys.momentsNoPostableChannels);
      return;
    }
    final selected = await showModalBottomSheet<ChatSummary>(
      context: context,
      backgroundColor: context.colors.background,
      builder: (context) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: widget.channels.length,
          separatorBuilder: (_, _) => const InsetDivider(leadingInset: 66),
          itemBuilder: (context, index) {
            final channel = widget.channels[index];
            final selected = channel.id == _channel?.id;
            final c = context.colors;
            return ListTile(
              leading: PhotoAvatar(
                title: channel.title,
                photo: channel.photo,
                size: 38,
                square: true,
              ),
              title: Text(
                channel.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, color: c.textPrimary),
              ),
              trailing: selected
                  ? AppIcon(HeroAppIcons.circleCheck, color: AppTheme.brand)
                  : null,
              onTap: () => Navigator.of(context).pop(channel),
            );
          },
        ),
      ),
    );
    if (selected != null && mounted) setState(() => _channel = selected);
  }

  Future<void> _send() async {
    final channel = _channel;
    final text = _controller.text.trim();
    final formatted = _richTextPayload?.text.trim() == text
        ? _richTextPayload!
        : parseTelegramMarkdown(text);
    if (channel == null || (text.isEmpty && _attachments.isEmpty) || _sending) {
      return;
    }
    setState(() => _sending = true);
    try {
      if (_attachments.isEmpty) {
        await _sendTextPost(channel, formatted);
      } else {
        final requests = buildAttachmentSendRequests(
          chatId: channel.id,
          attachments: _attachments,
          caption: formatted.text,
          captionEntities: formatted.entities,
        );
        for (final request in requests) {
          request['options'] = {
            '@type': 'messageSendOptions',
            'disable_notification': !_notifySubscribers,
          };
          await TdClient.shared.query(request);
        }
      }
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.momentsPostedTo, {'value1': channel.title}),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.momentsPostFailed, {'value1': e}),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendTextPost(
    ChatSummary channel,
    FormattedTextPayload formatted,
  ) {
    return TdClient.shared.query({
      '@type': 'sendMessage',
      'chat_id': channel.id,
      'options': {
        '@type': 'messageSendOptions',
        'disable_notification': !_notifySubscribers,
      },
      'input_message_content': {
        '@type': 'inputMessageText',
        'text': formatted.toTdJson(),
      },
    });
  }
}

class ChannelPostRow extends StatelessWidget {
  const ChannelPostRow({
    super.key,
    required this.post,
    required this.meName,
    this.mePhoto,
    this.onOpenPost,
    this.onComment,
    this.showInlineReply = true,
    this.showInlineComments = true,
  });

  final ChannelPost post;
  final String meName;
  final TdFileRef? mePhoto;
  final ValueChanged<ChannelPost>? onOpenPost;
  final void Function(ChannelPost post, BuildContext anchorContext)? onComment;
  final bool showInlineReply;
  final bool showInlineComments;

  ChatSummary get channel => post.channel;
  ChatMessage get message => post.message;
  List<ChatMessage> get messages => post.messages;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = _displayText;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpenPost == null ? null : () => onOpenPost!(post),
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
                  title: channel.title,
                  photo: channel.photo,
                  size: 48,
                  square: true,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              channel.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: c.linkBlue,
                              ),
                            ),
                          ),
                          _ChannelPostOverflowButton(post: post),
                        ],
                      ),
                      Row(
                        children: [
                          if (_hasSignedAuthor) ...[
                            PhotoAvatar(
                              title: post.authorName!,
                              photo: post.authorPhoto,
                              size: 16,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                post.authorName!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: c.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            DateText.listLabel(message.date),
                            style: TextStyle(
                              fontSize: 12,
                              color: c.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (text.isNotEmpty) ...[
              const SizedBox(height: 12),
              TelegramRichText(
                text: text,
                entities: _displayTextMessage?.textEntities ?? const [],
                quoteBackgroundColor: _momentQuoteFill(c),
                style: TextStyle(
                  fontSize: 15,
                  height: 1.35,
                  color: c.textPrimary,
                ),
                onMentionTap: (userId, name) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ProfileDetailView(userId: userId, name: name),
                    ),
                  );
                },
              ),
            ],
            if (_hasReplyQuote) ...[
              SizedBox(height: text.isNotEmpty ? 8 : 12),
              _PostReplyQuote(message: message),
            ],
            if (_imageMessages.isNotEmpty) ...[
              const SizedBox(height: 10),
              _PostImageGroup(
                messages: _imageMessages,
                sourceChatId: channel.id,
              ),
            ],
            const SizedBox(height: 12),
            _PostActions(
              post: post,
              canComment: _canReply && onComment != null,
              onComment: (post) => onComment?.call(post, context),
            ),
            if (showInlineComments && _hasInlineComments) ...[
              const SizedBox(height: 8),
              _InlineComments(post: post),
            ],
            if (showInlineReply && _canReply && onComment != null) ...[
              const SizedBox(height: 10),
              _InlineQuickReply(
                meName: meName,
                mePhoto: mePhoto,
                onTap: (context) => onComment?.call(post, context),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String get _displayText {
    return _displayTextMessage?.text.trim() ?? '';
  }

  ChatMessage? get _displayTextMessage {
    for (final message in messages) {
      final text = message.text.trim();
      if (text.isNotEmpty && !(text.startsWith('[') && text.endsWith(']'))) {
        return message;
      }
    }
    return null;
  }

  List<ChatMessage> get _imageMessages =>
      messages.where((message) => message.isAlbumVisualMedia).toList();

  bool get _hasInlineComments =>
      message.commentCount > 0 || (post.comments?.isNotEmpty ?? false);

  bool get _canReply => post.threadTarget != null || message.hasCommentThread;

  bool get _hasSignedAuthor =>
      !_isChannelSelfPost(post) && post.authorName?.trim().isNotEmpty == true;

  bool get _hasReplyQuote =>
      message.replyToMessageId != null &&
      (message.replyToPreview?.trim().isNotEmpty ?? false);
}

class _PostReplyQuote extends StatelessWidget {
  const _PostReplyQuote({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sender = message.replyToSender?.trim();
    final preview = message.replyToPreview?.trim() ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
      decoration: BoxDecoration(
        color: _momentQuoteFill(c),
        borderRadius: BorderRadius.circular(12),
      ),
      child: RichText(
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: TextStyle(fontSize: 15, height: 1.35, color: c.textPrimary),
          children: [
            if (sender != null && sender.isNotEmpty)
              TextSpan(
                text: '$sender: ',
                style: TextStyle(
                  color: c.linkBlue,
                  fontWeight: FontWeight.w500,
                ),
              ),
            TextSpan(text: preview.replaceAll('\n', ' ')),
          ],
        ),
      ),
    );
  }
}

class _InlineQuickReply extends StatelessWidget {
  const _InlineQuickReply({
    required this.meName,
    this.mePhoto,
    required this.onTap,
  });

  final String meName;
  final TdFileRef? mePhoto;
  final ValueChanged<BuildContext> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(context),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _momentQuoteFill(c),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            PhotoAvatar(title: meName, photo: mePhoto, size: 26),
            const SizedBox(width: 9),
            Text(
              AppStringKeys.momentsCommentPlaceholder.l10n(context),
              style: TextStyle(fontSize: 14, color: c.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineComments extends StatelessWidget {
  const _InlineComments({required this.post});

  final ChannelPost post;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final comments = post.comments ?? const <ChannelPostComment>[];
    if (comments.isEmpty) {
      return Text(
        AppStrings.t(AppStringKeys.momentsCommentCount, {
          'value1': post.message.commentCount,
        }),
        style: TextStyle(fontSize: 13, color: c.linkBlue),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final comment in comments)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatView(
                  chatId: comment.chatId,
                  title: post.channel.title,
                  initialMessageId: comment.messageId,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Wrap(
                children: [
                  Text(
                    '${comment.senderName}: ',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.25,
                      color: c.linkBlue,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  TelegramRichText(
                    text: comment.text,
                    entities: comment.entities,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    quoteBackgroundColor: _momentQuoteFill(c),
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.25,
                      color: c.textPrimary,
                    ),
                    onMentionTap: (userId, name) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ProfileDetailView(userId: userId, name: name),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        if (post.message.commentCount > comments.length)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              AppStringKeys.momentsMore.l10n(context),
              style: TextStyle(fontSize: 13, color: c.linkBlue),
            ),
          ),
      ],
    );
  }
}

class _PostImageGroup extends StatelessWidget {
  const _PostImageGroup({required this.messages, required this.sourceChatId});

  final List<ChatMessage> messages;
  final int sourceChatId;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width - 28;
    final visible = messages.take(9).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    final layout = buildTelegramMediaAlbumLayout(
      items: [
        for (final message in visible)
          MediaAlbumItem(
            width: message.imageWidth,
            height: message.imageHeight,
          ),
      ],
      maxWidth: width,
      minSingleHeight: 140,
      maxSingleHeight: 420,
      minRowHeight: 92,
      maxRowHeight: 280,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        width: layout.width,
        height: layout.height,
        child: Stack(
          children: [
            for (var i = 0; i < visible.length; i++)
              Positioned.fromRect(
                rect: layout.tiles[i],
                child: _tappableTile(
                  context: context,
                  index: i,
                  child: _PostImageTile(
                    message: visible[i],
                    width: layout.tiles[i].width,
                    height: layout.tiles[i].height,
                    extraCount: i == visible.length - 1
                        ? math.max(0, messages.length - visible.length)
                        : 0,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tappableTile({
    required BuildContext context,
    required int index,
    required Widget child,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openMedia(context, messages[index]),
      child: child,
    );
  }

  void _openMedia(BuildContext context, ChatMessage message) {
    final video = message.video;
    if (video != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => VideoPlayerView(
            video: video,
            thumb: message.image,
            width: message.imageWidth,
            height: message.imageHeight,
            sourceChatId: sourceChatId,
            messageId: message.id,
          ),
        ),
      );
      return;
    }
    _openImage(context, message);
  }

  void _openImage(BuildContext context, ChatMessage startMessage) {
    final photoMessages = messages
        .where((message) => message.isPhoto && message.image != null)
        .toList();
    final refs = photoMessages.map((message) => message.image!).toList();
    if (refs.isEmpty) return;
    final startIndex = photoMessages.indexWhere(
      (message) => message.id == startMessage.id,
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullImageViewer(
          items: refs,
          startIndex: (startIndex < 0 ? 0 : startIndex).clamp(
            0,
            refs.length - 1,
          ),
        ),
      ),
    );
  }
}

class _PostImageTile extends StatelessWidget {
  const _PostImageTile({
    required this.message,
    required this.width,
    required this.height,
    this.extraCount = 0,
  });

  final ChatMessage message;
  final double width;
  final double height;
  final int extraCount;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            TDImage(
              photo: message.image,
              cornerRadius: 3,
              cacheWidth: (width * MediaQuery.of(context).devicePixelRatio)
                  .round(),
              cacheHeight: (height * MediaQuery.of(context).devicePixelRatio)
                  .round(),
            ),
            if (message.video != null)
              Center(
                child: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const AppIcon(
                    HeroAppIcons.play,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            if (extraCount > 0)
              Container(
                color: Colors.black.withValues(alpha: 0.42),
                alignment: Alignment.center,
                child: Text(
                  '+$extraCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PostActions extends StatelessWidget {
  const _PostActions({
    required this.post,
    required this.canComment,
    required this.onComment,
  });

  final ChannelPost post;
  final bool canComment;
  final ValueChanged<ChannelPost> onComment;

  ChatSummary get channel => post.channel;
  ChatMessage get message => post.message;

  static const double _actionSize = 32;
  static const double _actionGap = 8;
  static const double _iconSize = 22;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reactionCount = _reactionCount;
    final likeText = _likeText(reactionCount);
    return Row(
      children: [
        Text(likeText, style: TextStyle(fontSize: 13, color: c.linkBlue)),
        const Spacer(),
        _actionButton(
          context,
          HeroAppIcons.thumbsUp,
          onTap: () => _react(context),
        ),
        if (canComment) ...[
          const SizedBox(width: _actionGap),
          _actionButton(
            context,
            HeroAppIcons.comment,
            onTap: () => onComment(post),
          ),
        ],
        const SizedBox(width: _actionGap),
        _actionButton(
          context,
          HeroAppIcons.share,
          onTap: () => _forward(context),
        ),
      ],
    );
  }

  Widget _actionButton(
    BuildContext context,
    AppIconData icon, {
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox.square(
        dimension: _actionSize,
        child: Center(
          child: AppIcon(
            icon,
            size: _iconSize,
            color: context.colors.textPrimary,
          ),
        ),
      ),
    );
  }

  int get _reactionCount =>
      message.reactions.fold<int>(0, (sum, reaction) => sum + reaction.count);

  String _likeText(int reactionCount) {
    if (reactionCount <= 0) return '';
    final names = post.likeNames;
    if (names == null || names.isEmpty) {
      return AppStrings.t(AppStringKeys.momentsLikedByCount, {
        'value1': reactionCount,
      });
    }
    final shown = names.take(3).join(AppStrings.t(AppStringKeys.listSeparator));
    if (reactionCount > names.length || names.length > 3) {
      return AppStrings.t(AppStringKeys.momentsLikedByListWithOthers, {
        'value1': shown,
        'value2': reactionCount,
      });
    }
    return AppStrings.t(AppStringKeys.momentsUserLiked, {'value1': shown});
  }

  Future<void> _react(BuildContext context) async {
    try {
      await TdClient.shared.query({
        '@type': 'addMessageReaction',
        'chat_id': channel.id,
        'message_id': message.id,
        'reaction_type': {'@type': 'reactionTypeEmoji', 'emoji': '👍'},
        'is_big': false,
        'update_recent_reactions': true,
      });
      if (context.mounted) {
        showToast(context, AppStringKeys.momentsLiked);
      }
    } catch (e) {
      if (context.mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.momentsLikeFailed, {'value1': e}),
        );
      }
    }
  }

  Future<void> _forward(BuildContext context) async {
    final result = await Navigator.of(context).push<ChatPickerResult>(
      MaterialPageRoute(
        builder: (_) => const ChatPickerView(
          title: AppStringKeys.chatForwardToTitle,
          showForwardOptions: true,
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    final target = result.chat;
    try {
      await forwardMessagesWithOptions(
        client: TdClient.shared,
        targetChatId: target.id,
        fromChatId: channel.id,
        messageIds: [message.id],
        options: result.forwardOptions,
      );
      if (context.mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.chatForwardedToName, {
            'value1': target.title,
          }),
        );
      }
    } catch (e) {
      if (context.mounted) {
        showToast(
          context,
          isForwardProtectedError(e)
              ? AppStringKeys.chatForwardProtected
              : AppStrings.t(AppStringKeys.chatForwardFailed, {'value1': e}),
        );
      }
    }
  }
}

class StoriesView extends StatefulWidget {
  const StoriesView({super.key, this.showBackButton = true});

  final bool showBackButton;

  @override
  State<StoriesView> createState() => _StoriesViewState();
}

class _StoriesViewState extends State<StoriesView> {
  final _model = MomentsViewModel();

  @override
  void initState() {
    super.initState();
    _model.addListener(() {
      if (mounted) setState(() {});
    });
    _model.start();
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.groupedBackground,
      child: Column(
        children: [
          NavHeader(
            title: AppStringKeys.momentsStories,
            onBack: widget.showBackButton
                ? () => Navigator.of(context).pop()
                : null,
          ),
          Expanded(child: _content()),
        ],
      ),
    );
  }

  Widget _content() {
    final c = context.colors;
    if (_model.groups.isEmpty && _model.loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(AppStrings.t(AppStringKeys.momentsLoadingPosts).l10n(context)),
          ],
        ),
      );
    }
    if (_model.groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(HeroAppIcons.circleNotch, size: 46, color: AppTheme.brand),
            const SizedBox(height: 12),
            Text(
              AppStrings.t(AppStringKeys.momentsNoFriendPosts).l10n(context),
              style: TextStyle(fontSize: 15, color: c.textSecondary),
            ),
          ],
        ),
      );
    }
    return Container(
      color: c.background,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: _model.groups.length,
        itemBuilder: (context, i) {
          final group = _model.groups[i];
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _row(group),
              if (i != _model.groups.length - 1)
                const InsetDivider(leadingInset: 80),
            ],
          );
        },
      ),
    );
  }

  Widget _row(StoryGroup group) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) =>
              StoryViewerView(chatId: group.chatId, storyIds: group.storyIds),
        ),
      ),
      child: Container(
        height: 72,
        color: c.background,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: group.hasUnread ? AppTheme.brandGradient : null,
              ),
              child: PhotoAvatar(
                title: group.name,
                photo: group.photo,
                size: 54,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppStrings.t(AppStringKeys.momentsNewPostsCount, {
                      'value1': group.storyIds.length,
                    }),
                    style: TextStyle(fontSize: 13, color: c.textSecondary),
                  ),
                ],
              ),
            ),
            Text(
              DateText.listLabel(group.order),
              style: TextStyle(fontSize: 12, color: c.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class MomentsViewModel extends ChangeNotifier {
  List<StoryGroup> groups = [];
  bool loading = false;
  final Map<int, StoryGroup> _map = {};
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    loading = true;
    notifyListeners();
    TdClient.shared.subscribe().listen((update) {
      if (update.type == 'updateChatActiveStories') _handle(update);
    });
    _loadAll();
  }

  /// TDLib paginates active stories: each loadActiveStories pulls the next batch
  /// of friends with active stories (surfaced via updateChatActiveStories) and
  /// returns a 404 once the list is exhausted. A single call only ever shows the
  /// first few friends, so loop until done (capped) to surface everyone.
  Future<void> _loadAll() async {
    for (var i = 0; i < 15; i++) {
      var more = true;
      try {
        await TdClient.shared
            .query({
              '@type': 'loadActiveStories',
              'story_list': {'@type': 'storyListMain'},
            })
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        // 404 (all loaded), a timeout, or any error → stop paging. Crucially we
        // must still drop the spinner below so the tab can't hang on a black
        // loading screen forever.
        more = false;
      }
      // First page settled (or failed) → clear the spinner and show whatever
      // arrived; later pages keep filling in via updateChatActiveStories.
      if (loading) {
        loading = false;
        notifyListeners();
      }
      if (!more) break;
    }
  }

  Future<void> _handle(Map<String, dynamic> update) async {
    final a = update.obj('active_stories');
    if (a == null) return;
    final chatId = a.int64('chat_id') ?? 0;
    if (chatId == 0) return;
    final order = a.int64('order') ?? 0;
    final infos = a.objects('stories') ?? const <Map<String, dynamic>>[];
    final storyIds = infos
        .map((s) => s.int64('story_id'))
        .whereType<int>()
        .toList();

    if (storyIds.isEmpty) {
      _map.remove(chatId);
      _publish();
      loading = false;
      return;
    }

    final maxRead = a.integer('max_read_story_id') ?? 0;
    final hasUnread = storyIds.any((id) => id > maxRead);

    var name = '';
    TdFileRef? photo;
    try {
      final chat = await TdClient.shared.query({
        '@type': 'getChat',
        'chat_id': chatId,
      });
      name = chat.str('title') ?? '';
      photo = TDParse.smallPhoto(chat.obj('photo'));
    } catch (_) {}
    if (name.isEmpty) {
      name = _map[chatId]?.name ?? AppStringKeys.momentsUnknown;
    }

    _map[chatId] = StoryGroup(
      chatId: chatId,
      name: name,
      photo: photo,
      storyIds: storyIds,
      hasUnread: hasUnread,
      order: order,
    );
    _publish();
    loading = false;
  }

  void _publish() {
    groups = _map.values.toList()..sort((a, b) => b.order.compareTo(a.order));
    notifyListeners();
  }
}
