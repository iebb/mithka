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
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../app/app_navigator.dart';
import '../chat/chat_picker_view.dart';
import '../chat/chat_view.dart';
import '../chat/custom_emoji.dart';
import '../chat/forward_options.dart';
import '../chat/image_preview.dart';
import '../chat/media_album_layout.dart';
import '../chat/message_reaction_availability.dart';
import '../chat/outgoing_attachment.dart';
import '../chat/quick_reaction_choice.dart';
import '../chat/rich_text_composer_view.dart';
import '../chat/rich_text_format.dart';
import '../chat/shared_media_view.dart';
import '../chat/telegram_rich_text.dart';
import '../chat/video_playback_queue.dart';
import '../chat/video_player_view.dart';
import '../chats/chat_list_view_model.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/desktop_content_constraint.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../media/app_asset_picker.dart';
import '../platform/adaptive_platform.dart';
import '../profile/adaptive_profile_launcher.dart';
import '../settings/accent_color_picker_view.dart';
import '../tdlib/chat_membership.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import '../theme/theme_controller.dart';
import 'short_video_availability.dart';
import 'short_video_view.dart';
import 'story_authoring_view.dart';
import 'story_management_view.dart';
import 'story_service.dart';
import 'story_viewer_view.dart';

class StoryGroup {
  StoryGroup({
    required this.chatId,
    required this.name,
    this.photo,
    required this.storyIds,
    required this.hasUnread,
    required this.order,
    required this.date,
  });
  final int chatId;
  final String name;
  final TdFileRef? photo;
  final List<int> storyIds;
  final bool hasUnread;

  /// TDLib sort weight — `last_story.date` plus flag bits (unread/premium/…).
  /// Sort by this, but never render it as a timestamp.
  final int order;

  /// Unix time of the newest story; what rows display.
  final int date;
}

class ChannelPost {
  ChannelPost({
    required this.channel,
    required this.message,
    required this.accountSlot,
    this.threadTarget,
    this.authorName,
    this.authorPhoto,
    this.likeNames,
    this.comments,
    List<ChatMessage>? messages,
  }) : messages = messages ?? <ChatMessage>[message];

  final ChatSummary channel;
  final ChatMessage message;
  final int accountSlot;
  final List<ChatMessage> messages;
  ChannelPostThreadTarget? threadTarget;
  String? authorName;
  TdFileRef? authorPhoto;
  List<String>? likeNames;
  List<ChannelPostComment>? comments;

  /// Bumped when metadata hydration fills this post in place. The feed row
  /// listens to it, so a resolved author/like/comment rebuilds that one row
  /// instead of every visible row through a feed-wide setState.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
}

class ChannelPostThreadTarget {
  const ChannelPostThreadTarget({
    required this.chatId,
    required this.messageThreadId,
  });

  final int chatId;
  final int messageThreadId;
}

class _MomentsFeedScrollAnchor {
  const _MomentsFeedScrollAnchor({required this.key, required this.leading});

  final GlobalKey key;
  final double leading;
}

final Map<String, double> _channelMomentsScrollOffsets = {};

String _channelMomentsScrollKey({
  required int accountSlot,
  required bool isRootTab,
  required List<ChatSummary> initialChannels,
}) {
  final ids = initialChannels.map((channel) => channel.id).toList()..sort();
  return '$accountSlot:$isRootTab:${ids.join(',')}';
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

@visibleForTesting
enum MomentsReactionAction { hidden, sendThumbsUp, openSelector }

@visibleForTesting
MomentsReactionAction momentsReactionAction(
  MessageReactionAvailability? availability,
) {
  if (availability == null || !availability.canAdd) {
    return MomentsReactionAction.hidden;
  }
  return availability.allows(const QuickReactionChoice.emoji('👍'))
      ? MomentsReactionAction.sendThumbsUp
      : MomentsReactionAction.openSelector;
}

const double desktopMomentsFeedMaxWidth = 760;

/// Keeps the desktop timeline readable without changing phone/tablet sizing.
class MomentsDesktopFeedLane extends StatelessWidget {
  const MomentsDesktopFeedLane({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopTargetPlatform()) return child;
    return ColoredBox(
      key: const ValueKey('desktop-moments-feed-lane'),
      color: context.colors.groupedBackground,
      child: DesktopContentConstraint(
        maxWidth: desktopMomentsFeedMaxWidth,
        child: child,
      ),
    );
  }
}

class MomentsView extends StatefulWidget {
  const MomentsView({
    super.key,
    this.onOpenDetail,
    this.storyService,
    this.desktopSidebar = false,
  });

  final ValueChanged<Widget>? onOpenDetail;
  final StoryService? storyService;
  final bool desktopSidebar;

  @override
  State<MomentsView> createState() => _MomentsViewState();
}

class _MomentsViewState extends State<MomentsView> {
  final _channels = ChatListViewModel();
  final _stories = MomentsViewModel();
  late final StoryService _storyService = widget.storyService ?? StoryService();
  StreamSubscription<int>? _accountSub;
  bool _canPublishStories = false;
  int _storyPermissionGeneration = 0;

  @override
  void initState() {
    super.initState();
    _channels.addListener(_onChannels);
    _stories.addListener(_onStories);
    _channels.onAppear();
    _stories.start();
    _accountSub = TdClient.shared.subscribeActiveSlotChanges().listen((_) {
      if (mounted) setState(() => _canPublishStories = false);
      unawaited(_loadStoryPublishingPermission());
    });
    unawaited(_loadStoryPublishingPermission());
  }

  @override
  void dispose() {
    _channels.removeListener(_onChannels);
    _stories.removeListener(_onStories);
    _accountSub?.cancel();
    _channels.dispose();
    _stories.dispose();
    super.dispose();
  }

  void _onChannels() {
    if (mounted) setState(() {});
  }

  void _onStories() {
    if (mounted) setState(() {});
  }

  Future<void> _loadStoryPublishingPermission() async {
    final generation = ++_storyPermissionGeneration;
    var allowed = false;
    try {
      allowed = await _storyService.canPostAnyStory();
    } catch (_) {}
    if (mounted && generation == _storyPermissionGeneration) {
      setState(() => _canPublishStories = allowed);
    }
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

  Future<void> _createStory() async {
    if (!_canPublishStories) return;
    final changed = await Navigator.of(context, rootNavigator: true).push<bool>(
      AppPageRoute<bool>(
        fullscreenDialog: true,
        pageBuilder: (_, _, _) => StoryAuthoringView(service: _storyService),
      ),
    );
    if (changed == true) _stories.refresh();
    await _loadStoryPublishingPermission();
  }

  Future<void> _manageStories() async {
    try {
      final chatId = await _storyService.savedMessagesChatId();
      if (!mounted) return;
      await Navigator.of(context).push(
        AppPageRoute<void>(
          pageBuilder: (_, _, _) =>
              StoryManagementView(chatId: chatId, service: _storyService),
        ),
      );
      _stories.refresh();
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          context.l10n.t(AppStringKeys.storiesOpenFailed, {'value1': error}),
        );
      }
    }
  }

  void _openChannelMoments() {
    _openDetail(
      ChannelMomentsView(
        isRootTab: widget.onOpenDetail != null,
        title: widget.onOpenDetail == null
            ? AppStrings.t(AppStringKeys.tabMoments)
            : AppStrings.t(AppStringKeys.tabFriendMoments),
        initialChannels: _allChannels,
      ),
    );
  }

  void _openMusic() {
    _openDetail(
      SharedMediaView(
        chatId: 0,
        title: AppStrings.t(AppStringKeys.momentsMusic),
        initialTab: 5,
        displayTitle: AppStringKeys.momentsMusic,
        lockedTab: true,
      ),
    );
  }

  void _openVideos() {
    _openDetail(
      SharedMediaView(
        chatId: 0,
        title: AppStrings.t(AppStringKeys.sharedMediaVideos),
        initialTab: 4,
        displayTitle: AppStringKeys.sharedMediaVideos,
        lockedTab: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    final useDesktopSidebar =
        widget.desktopSidebar && isDesktopTargetPlatform();
    if (useDesktopSidebar) return _desktopSidebar(c);
    return Material(
      color: c.groupedBackground,
      child: Column(
        children: [
          if (!widget.desktopSidebar)
            const NavHeader(title: AppStringKeys.tabMoments),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              children: [
                StoryShelf(
                  model: _stories,
                  canPublish: _canPublishStories,
                  onCreate: _createStory,
                  onManage: _manageStories,
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  color: c.background,
                  child: Column(
                    children: [
                      _menuRow(
                        icon: HeroAppIcons.star.data,
                        iconColor: const Color(0xFFFFBE00),
                        title: AppStrings.t(AppStringKeys.tabMoments),
                        trailing: _channelActivity(),
                        onTap: _openChannelMoments,
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
                        title: AppStrings.t(AppStringKeys.momentsMusic),
                        onTap: _openMusic,
                      ),
                      _menuRow(
                        icon: HeroAppIcons.video.data,
                        iconColor: const Color(0xFF7B61FF),
                        title: AppStrings.t(AppStringKeys.sharedMediaVideos),
                        onTap: _openVideos,
                      ),
                    ],
                  ),
                ),
                if (theme.showShortVideos &&
                    shortVideosAvailableOnPlatform()) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    color: c.background,
                    child: _menuRow(
                      icon: HeroAppIcons.solidFileVideo.data,
                      iconColor: const Color(0xFFFF4D67),
                      title: AppStrings.t(AppStringKeys.momentsShortVideos),
                      onTap: () => ShortVideoLauncher.open(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopSidebar(AppColors c) {
    return Material(
      key: const ValueKey('desktop-moments-sidebar'),
      color: c.groupedBackground,
      child: Column(
        children: [
          Container(
            key: const ValueKey('desktop-moments-header'),
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: c.background,
              border: Border(
                bottom: BorderSide(color: c.divider, width: AppMetric.divider),
              ),
            ),
            child: Text(
              AppStringKeys.tabMoments.l10n(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  child: StoryShelf(
                    model: _stories,
                    canPublish: _canPublishStories,
                    onCreate: _createStory,
                    onManage: _manageStories,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _desktopMenuCard([
                  _desktopMenuRow(
                    key: const ValueKey('desktop-moments-friends'),
                    icon: HeroAppIcons.star,
                    iconColor: const Color(0xFFFFBE00),
                    title: AppStringKeys.tabFriendMoments.l10n(context),
                    trailing: _channelActivity(),
                    onTap: _openChannelMoments,
                  ),
                ]),
                const SizedBox(height: AppSpacing.md),
                _desktopMenuCard([
                  _desktopMenuRow(
                    key: const ValueKey('desktop-moments-music'),
                    icon: HeroAppIcons.music,
                    iconColor: const Color(0xFFFF8A2A),
                    title: AppStringKeys.momentsMusic.l10n(context),
                    onTap: _openMusic,
                  ),
                  Divider(height: 1, indent: 58, color: c.divider),
                  _desktopMenuRow(
                    key: const ValueKey('desktop-moments-videos'),
                    icon: HeroAppIcons.video,
                    iconColor: const Color(0xFF7B61FF),
                    title: AppStrings.t(
                      AppStringKeys.sharedMediaVideos,
                    ).l10n(context),
                    onTap: _openVideos,
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopMenuCard(List<Widget> children) {
    final c = context.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.divider, width: AppMetric.divider),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _desktopMenuRow({
    required Key key,
    required AppIconData icon,
    required Color iconColor,
    required String title,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final c = context.colors;
    return AppInteractiveSurface(
      key: key,
      semanticLabel: title,
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: SizedBox(
        height: 58,
        child: Row(
          children: [
            const SizedBox(width: AppSpacing.md),
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: AppIcon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: c.textPrimary,
                ),
              ),
            ),
            if (trailing != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 132),
                child: trailing,
              ),
            const SizedBox(width: AppSpacing.sm),
            AppIcon(HeroAppIcons.chevronRight, size: 16, color: c.textTertiary),
            const SizedBox(width: AppSpacing.md),
          ],
        ),
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
  late final String _scrollSessionKey;
  final Map<String, GlobalKey> _postWidgetKeys = {};
  double? _pendingScrollOffset;
  bool _scrollRestoreScheduled = false;
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
  String _meName = AppStrings.t(AppStringKeys.chatMeLabel);
  TdFileRef? _mePhoto;
  int _meAccentColorId = -1;
  int _meProfileAccentColorId = -1;
  bool _loadingPosts = false;
  bool _loadingPostableChannels = false;
  bool _refreshingLiveUpdates = false;
  bool _refreshingLatest = false;
  bool _nonMutedOnly = false;
  int _feedLoadGeneration = 0;
  static const _perChannelPageSize = 30;
  static const _metadataHydrationLimit = 60;
  static const _feedLimit = 500;

  @override
  void initState() {
    super.initState();
    _scrollSessionKey = _channelMomentsScrollKey(
      accountSlot: TdClient.shared.activeSlot,
      isRootTab: widget.isRootTab,
      initialChannels: widget.initialChannels,
    );
    _pendingScrollOffset = _channelMomentsScrollOffsets[_scrollSessionKey];
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
    _scheduleScrollRestore();
  }

  @override
  void dispose() {
    if (_scroll.hasClients) {
      _channelMomentsScrollOffsets[_scrollSessionKey] = _scroll.offset;
    }
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
    _channelMomentsScrollOffsets[_scrollSessionKey] = _scroll.offset;
    if (_scroll.position.extentAfter < 600) _loadChannelPosts(loadOlder: true);
  }

  void _scheduleScrollRestore() {
    if (_pendingScrollOffset == null || _scrollRestoreScheduled) return;
    _scrollRestoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollRestoreScheduled = false;
      if (!mounted || !_scroll.hasClients) return;
      final pending = _pendingScrollOffset;
      if (pending == null) return;
      final position = _scroll.position;
      // Initial history loads arrive asynchronously. Do not clamp a saved
      // position to the first short page; wait for the feed to finish loading
      // so reopening lands at the same history location.
      if (pending > position.maxScrollExtent &&
          (_loadingPosts || (_posts.isEmpty && _channels.isNotEmpty))) {
        _scheduleScrollRestore();
        return;
      }
      if (pending > position.maxScrollExtent &&
          _channels.any(
            (channel) => !_exhaustedChannels.contains(channel.id),
          )) {
        _loadChannelPosts(loadOlder: true);
        _scheduleScrollRestore();
        return;
      }
      final next = pending.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      _scroll.jumpTo(next);
      _pendingScrollOffset = null;
      _channelMomentsScrollOffsets[_scrollSessionKey] = next;
    });
  }

  _MomentsFeedScrollAnchor? _captureFeedScrollAnchor() {
    if (!_scroll.hasClients) return null;
    final current = _scroll.offset;
    final viewportExtent = _scroll.position.viewportDimension;
    for (final post in _posts) {
      final key = _postKey(post);
      final render = key.currentContext?.findRenderObject();
      if (render == null || !render.attached) continue;
      final viewport = RenderAbstractViewport.of(render);
      final leading = viewport.getOffsetToReveal(render, 0).offset - current;
      final extent = render.paintBounds.height;
      if (leading + extent > 0 && leading < viewportExtent) {
        return _MomentsFeedScrollAnchor(key: key, leading: leading);
      }
    }
    return null;
  }

  void _restoreFeedScrollAnchor(
    _MomentsFeedScrollAnchor? anchor,
    double fallbackOffset,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      var next = fallbackOffset;
      final render = anchor?.key.currentContext?.findRenderObject();
      if (render != null && render.attached) {
        final viewport = RenderAbstractViewport.of(render);
        next = viewport.getOffsetToReveal(render, 0).offset - anchor!.leading;
      }
      final position = _scroll.position;
      next = next.clamp(position.minScrollExtent, position.maxScrollExtent);
      _scroll.jumpTo(next);
      _channelMomentsScrollOffsets[_scrollSessionKey] = next;
    });
  }

  void _onModel() {
    _feedChatIds = null; // channel set may have changed
    _invalidateChannels();
    if (mounted) setState(() {});
    _scheduleScrollRestore();
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
        _markChatDirty(update);
        _scheduleLiveRefresh();

      // Membership changed: the joined/exhausted caches for that chat are
      // stale — a left channel kept feeding posts, and a newly joined one
      // could never load until the view was rebuilt.
      case 'updateChatAddedToList':
      case 'updateChatRemovedFromList':
        final chatId = update.int64('chat_id');
        if (chatId == null) return;
        if (_joinedChannelCache.remove(chatId) == null) return;
        _invalidateChannels();
        _exhaustedChannels.remove(chatId);
        if (update.type == 'updateChatRemovedFromList') {
          _postsByChannel.remove(chatId);
          _invalidateFeed();
          if (mounted) setState(() {});
        }
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

  // Which chats changed during the debounce window. A single incoming message
  // used to refetch 30 messages of history for EVERY joined channel and
  // re-parse them all; only the chats that actually moved need a refetch.
  final Set<int> _dirtyChatIds = {};
  bool _dirtyAllChannels = false;

  void _markChatDirty(Map<String, dynamic> update) {
    final chatId =
        update.int64('chat_id') ?? update.obj('message')?.int64('chat_id');
    if (chatId == null) {
      _dirtyAllChannels = true;
      return;
    }
    _dirtyChatIds.add(chatId);
  }

  void _scheduleLiveRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 450), _refreshFeedNow);
  }

  Future<void> _refreshFeedNow() async {
    if (!mounted) return;
    if (_refreshingLiveUpdates) {
      // A refresh now only covers the chats it drained, so dropping this tick
      // would strand whatever was marked dirty while it was in flight.
      if (_dirtyAllChannels || _dirtyChatIds.isNotEmpty) _scheduleLiveRefresh();
      return;
    }
    final channels = _channels;
    if (channels.isEmpty) return;
    final List<ChatSummary> targets;
    if (_dirtyAllChannels) {
      targets = channels;
    } else {
      final dirty = Set<int>.of(_dirtyChatIds);
      targets = channels
          .where((channel) => dirty.contains(channel.id))
          .toList(growable: false);
    }
    _dirtyChatIds.clear();
    _dirtyAllChannels = false;
    if (targets.isEmpty) {
      // The update landed in a discussion chat, not a feed channel: the cached
      // likes/comments were already dropped, so a rehydrate is the whole job.
      _schedulePostMetadataHydration();
      if (mounted) setState(() {});
      return;
    }
    final anchor = _captureFeedScrollAnchor();
    final fallbackOffset = _scroll.hasClients ? _scroll.offset : 0.0;
    _refreshingLiveUpdates = true;
    _loadingPosts = true;
    if (mounted) setState(() {});
    final futures = <Future<void>>[];
    for (final channel in targets) {
      if (!await _isJoinedChannel(channel)) continue;
      if (!_loadingChannels.add(channel.id)) continue;
      futures.add(
        _loadPostsForChannel(channel, fromMessageId: 0, notify: false),
      );
    }
    try {
      await Future.wait(futures);
    } finally {
      _refreshingLiveUpdates = false;
      _loadingPosts = _loadingChannels.isNotEmpty;
      if (mounted) setState(() {});
      _restoreFeedScrollAnchor(anchor, fallbackOffset);
    }
  }

  Future<void> _refreshLatest() async {
    if (_refreshingLatest || _refreshingLiveUpdates) return;
    final channels = _channels;
    if (channels.isEmpty) return;
    final anchor = _captureFeedScrollAnchor();
    final fallbackOffset = _scroll.hasClients ? _scroll.offset : 0.0;
    _refreshingLatest = true;
    _loadingPosts = true;
    if (mounted) setState(() {});
    final futures = <Future<void>>[];
    for (final channel in channels) {
      if (!await _isJoinedChannel(channel)) continue;
      if (!_loadingChannels.add(channel.id)) continue;
      futures.add(
        _loadPostsForChannel(channel, fromMessageId: 0, notify: false),
      );
    }
    try {
      await Future.wait(futures);
      _schedulePostMetadataHydration();
    } finally {
      _refreshingLatest = false;
      _loadingPosts = _loadingChannels.isNotEmpty;
      if (mounted) setState(() {});
      _restoreFeedScrollAnchor(anchor, fallbackOffset);
    }
  }

  // Memoized: this getter used to rebuild the dedup map on every access, and
  // it is read from build() and the per-update feed paths. Every site that
  // changes its inputs (model chats, joined cache, mute filter) already
  // clears _feedChatIds — _invalidateChannels() piggybacks on those.
  List<ChatSummary>? _channelsCache;

  void _invalidateChannels() => _channelsCache = null;

  List<ChatSummary> get _channels {
    final cached = _channelsCache;
    if (cached != null) return cached;
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
    return _channelsCache = byId.values.toList(growable: false);
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

  GlobalKey _postKey(ChannelPost post) {
    final identity = 'post-${post.channel.id}-${post.message.id}';
    return _postWidgetKeys.putIfAbsent(identity, GlobalKey.new);
  }

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
          accountSlot: primary.accountSlot,
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
    // Near the bottom of the feed the scroll listener calls this on every
    // tick; only a changed spinner state is worth a rebuild.
    final loading = _loadingChannels.isNotEmpty;
    if (loading == _loadingPosts) return;
    _loadingPosts = loading;
    if (mounted) setState(() {});
  }

  Future<bool> _isJoinedChannel(ChatSummary channel) async {
    final cached = _joinedChannelCache[channel.id];
    if (cached != null) return cached;
    final joined = await isJoinedGroupOrChannelChat(channel.id);
    _joinedChannelCache[channel.id] = joined;
    _feedChatIds = null; // joined-state feeds the _channels filter
    _invalidateChannels();
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
    bool notify = true,
  }) async {
    final accountSlot = TdClient.shared.activeSlot;
    try {
      final response = await TdClient.shared.queryForSlot({
        '@type': 'getChatHistory',
        'chat_id': channel.id,
        'from_message_id': fromMessageId,
        'offset': 0,
        'limit': _perChannelPageSize,
        'only_local': false,
      }, accountSlot);
      final messages =
          (response.objects('messages') ?? const <Map<String, dynamic>>[])
              .map(TDParse.message)
              .whereType<ChatMessage>()
              .where((message) => !message.isService)
              .map(
                (message) => ChannelPost(
                  channel: channel,
                  message: message,
                  accountSlot: accountSlot,
                ),
              )
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
        // A batched refresh rebuilds once when the whole batch lands.
        if (notify && mounted) setState(() {});
        _scheduleScrollRestore();
      }
    }
  }

  void _toggleNonMutedOnly() {
    setState(() {
      _nonMutedOnly = !_nonMutedOnly;
      _invalidateChannels();
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

  // Hydration resolves one post at a time; a setState here rebuilt every
  // visible row (each one re-laying out its rich text) on nearly every frame
  // of the settle window. Bumping the revision repaints just that row.
  void _notifyPost(ChannelPost post) {
    if (!mounted) return;
    post.revision.value++;
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
      _notifyPost(post);
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
      if (shouldNotify) _notifyPost(post);
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
            senderName:
                senderName ?? AppStrings.t(AppStringKeys.topicChatUsers),
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
      _notifyPost(post);
    }
  }

  String _commentText(ChatMessage message) {
    return message.text.trim();
  }

  String _replyPreview(ChatMessage message) {
    if (message.document != null) {
      return AppStrings.t(AppStringKeys.composerFilePreview, {
        'value1': message.document!.fileName,
      });
    }
    if (message.voice != null) {
      return AppStrings.t(AppStringKeys.composerVoicePreview);
    }
    if (message.location != null) {
      return AppStrings.t(AppStringKeys.composerLocationPreview);
    }
    if (message.animatedSticker != null) {
      return AppStrings.t(AppStringKeys.composerAnimatedEmojiPreview);
    }
    if (message.video != null) {
      return message.text;
    }
    if (message.image != null) {
      return message.text;
    }
    final text = message.text.trim();
    return text.isEmpty
        ? AppStrings.t(AppStringKeys.chatSearchMessageResultLabel)
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
    final previousName = post.authorName;
    final previousPhoto = post.authorPhoto;
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
    // Anonymous channel posts resolve to the same nothing they started with.
    if (post.authorName == previousName && post.authorPhoto == previousPhoto) {
      return;
    }
    _notifyPost(post);
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
      _notifyPost(post);
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
    final useDesktopLayout = isDesktopTargetPlatform();
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
                  key: const ValueKey('moments-refresh-latest'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _refreshingLatest ? null : _refreshLatest,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
                    child: AppIcon(
                      HeroAppIcons.arrowsRotate,
                      size: 22,
                      color: _refreshingLatest ? c.textTertiary : c.textPrimary,
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
          Expanded(child: _feed(posts, useDesktopLayout: useDesktopLayout)),
          if (_replyPost != null) _quickReplyBar(),
        ],
      ),
    );
  }

  Widget _feed(List<ChannelPost> posts, {required bool useDesktopLayout}) {
    final c = context.colors;
    final list = ListView.builder(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: useDesktopLayout
          ? const EdgeInsets.symmetric(vertical: AppSpacing.lg)
          : EdgeInsets.zero,
      itemCount: posts.isEmpty ? 2 : posts.length + 1,
      findChildIndexCallback: (key) => _feedIndexByKey[key],
      itemBuilder: (context, i) {
        if (i == 0) {
          final composer = _MomentsComposerHeader(
            meName: _meName,
            mePhoto: _mePhoto,
            backgroundColor: _profileHeaderColor(context),
            canCompose: _postableChannels.isNotEmpty,
            onCompose: _openNewPostComposer,
          );
          return KeyedSubtree(
            key: _composerHeaderKey,
            child: useDesktopLayout ? _desktopFeedCard(composer) : composer,
          );
        }
        if (posts.isEmpty) {
          final empty = SizedBox(height: 260, child: _empty());
          return useDesktopLayout ? _desktopFeedCard(empty) : empty;
        }
        final post = posts[i - 1];
        // Listening to the post's own revision keeps metadata hydration from
        // rebuilding (and re-laying out the rich text of) every other row.
        final row = ValueListenableBuilder<int>(
          valueListenable: post.revision,
          builder: (context, _, _) => ChannelPostRow(
            post: post,
            meName: _meName,
            mePhoto: _mePhoto,
            onOpenPost: _openPostDetail,
            onComment: _beginReplyFromInline,
          ),
        );
        return KeyedSubtree(
          key: _postKey(post),
          child: useDesktopLayout
              ? _desktopFeedCard(row)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    row,
                    if (i != posts.length) const InsetDivider(leadingInset: 0),
                  ],
                ),
        );
      },
    );
    final refreshable = RefreshIndicator(
      onRefresh: _refreshLatest,
      color: AppTheme.brand,
      backgroundColor: c.background,
      notificationPredicate: (notification) => notification.depth == 0,
      child: list,
    );
    if (!useDesktopLayout) {
      return ColoredBox(color: c.background, child: refreshable);
    }
    return MomentsDesktopFeedLane(child: refreshable);
  }

  Widget _desktopFeedCard(Widget child) {
    final c = context.colors;
    final media = MediaQuery.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: c.divider, width: AppMetric.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.16
                    : 0.035,
              ),
              blurRadius: 14,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => MediaQuery(
            data: media.copyWith(
              size: Size(constraints.maxWidth, media.size.height),
            ),
            child: child,
          ),
        ),
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
                  borderRadius: BorderRadius.circular(AppRadius.md),
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
          SizedBox(
            height: 166,
            child: Stack(
              children: [
                Positioned.fill(
                  child: mePhoto == null
                      ? ColoredBox(color: backgroundColor)
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            ImageFiltered(
                              imageFilter: ui.ImageFilter.blur(
                                sigmaX: 28,
                                sigmaY: 28,
                              ),
                              child: TDImage(photo: mePhoto, cornerRadius: 0),
                            ),
                            ColoredBox(
                              color: Colors.black.withValues(alpha: 0.18),
                            ),
                          ],
                        ),
                ),
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
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 25,
                                  height: 1.08,
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
                  borderRadius: BorderRadius.circular(AppRadius.card),
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
    final accountSlot = TdClient.shared.activeSlot;
    try {
      final response = await TdClient.shared.queryForSlot({
        '@type': 'searchChatMessages',
        'chat_id': channel.id,
        'query': query,
        'sender_id': null,
        'from_message_id': 0,
        'offset': 0,
        'limit': 30,
        'filter': {'@type': 'searchMessagesFilterEmpty'},
      }, accountSlot);
      final rawMessages =
          response.objects('messages') ?? const <Map<String, dynamic>>[];
      return [
        for (final raw in rawMessages)
          if ((raw.int64('chat_id') ?? channel.id) == channel.id)
            if (TDParse.message(raw) case final message?)
              if (!message.isService)
                ChannelPost(
                  channel: channel,
                  message: message,
                  accountSlot: accountSlot,
                ),
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
  pushAppChatRoute(
    context,
    AppChatPageRoute<void>(
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
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.card),
    ),
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
  String _meName = AppStrings.t(AppStringKeys.chatMeLabel);
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
      final kept = <_LoadedPostComment>[];
      for (final raw in rawMessages) {
        final message = TDParse.message(raw);
        if (message == null ||
            message.isService ||
            message.id == post.message.id ||
            message.id == target.messageThreadId ||
            _commentText(message).isEmpty) {
          continue;
        }
        kept.add(
          _LoadedPostComment(
            chatId: raw.int64('chat_id') ?? target.chatId,
            message: message,
          ),
        );
      }
      // One query per distinct sender, in parallel. Resolving inline below
      // serialized up to 120 getUser/getChat round-trips, mostly repeats.
      final firstBySender = <int, ChatMessage>{};
      for (final entry in kept) {
        final senderId = entry.message.senderId;
        if (senderId != null) {
          firstBySender.putIfAbsent(senderId, () => entry.message);
        }
      }
      final senders = <int, _CommentSender>{};
      await Future.wait(
        firstBySender.entries.map((entry) async {
          senders[entry.key] = await _commentSender(entry.value);
        }),
      );
      final comments = <ChannelPostComment>[];
      for (final entry in kept) {
        final message = entry.message;
        final senderId = message.senderId;
        final cached = senderId == null ? null : senders[senderId];
        final sender = cached ?? await _commentSender(message);
        comments.add(
          ChannelPostComment(
            chatId: entry.chatId,
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
    return message.text.trim();
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
          name: name.isNotEmpty
              ? name
              : title ?? AppStrings.t(AppStringKeys.topicChatUsers),
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
              ? title ?? AppStrings.t(AppStringKeys.topicChatUsers)
              : name,
          photo: TDParse.smallPhoto(chat.obj('photo')),
        );
      }
    } catch (_) {}
    return _CommentSender(
      name: title == null || title.isEmpty
          ? AppStrings.t(AppStringKeys.topicChatUsers)
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
            // Slivers, not a Column of every comment: a thread of 120 rebuilt
            // and laid out all of its tiles on each incoming-comment refresh.
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: ChannelPostRow(
                    post: post,
                    meName: '',
                    showInlineReply: false,
                    showInlineComments: false,
                  ),
                ),
                const SliverToBoxAdapter(child: InsetDivider(leadingInset: 14)),
                if (_loading && _comments.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else
                  _CommentThreadList(
                    post: post,
                    comments: _comments,
                    onReply: _beginReply,
                    onReactionSent: () => unawaited(_loadComments()),
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
                borderRadius: BorderRadius.circular(AppRadius.card),
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

/// One flattened row of the comment thread: a root or one of its replies.
class _ThreadEntry {
  const _ThreadEntry({
    required this.comment,
    required this.endsGroup,
    this.prefix,
    this.nested = false,
  });

  final ChannelPostComment comment;
  final String? prefix;
  final bool nested;

  /// Last tile of a root-plus-replies group — carries the gap that used to be
  /// a SizedBox between groups.
  final bool endsGroup;
}

class _CommentThreadList extends StatelessWidget {
  const _CommentThreadList({
    required this.post,
    required this.comments,
    required this.onReply,
    required this.onReactionSent,
  });

  final ChannelPost post;
  final List<ChannelPostComment> comments;
  final ValueChanged<ChannelPostComment> onReply;
  final VoidCallback onReactionSent;

  @override
  Widget build(BuildContext context) {
    if (comments.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: Text(
              AppStringKeys.momentsNoComments.l10n(context),
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textTertiary,
              ),
            ),
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
    // Flattened once per build so the tiles themselves can be built lazily.
    final entries = <_ThreadEntry>[];
    for (final root in roots) {
      final children =
          childrenByRoot[root.messageId] ?? const <ChannelPostComment>[];
      entries.add(_ThreadEntry(comment: root, endsGroup: children.isEmpty));
      for (var i = 0; i < children.length; i++) {
        entries.add(
          _ThreadEntry(
            comment: children[i],
            prefix: _replyPrefix(children[i], root, byId),
            nested: true,
            endsGroup: i == children.length - 1,
          ),
        );
      }
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
      sliver: SliverList.builder(
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          final tile = _DetailCommentTile(
            comment: entry.comment,
            accountSlot: post.accountSlot,
            prefix: entry.prefix,
            nested: entry.nested,
            onReply: onReply,
            onReactionSent: onReactionSent,
          );
          if (!entry.endsGroup) return tile;
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: tile,
          );
        },
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
    required this.accountSlot,
    required this.onReply,
    required this.onReactionSent,
    this.prefix,
    this.nested = false,
  });

  final ChannelPostComment comment;
  final int accountSlot;
  final String? prefix;
  final bool nested;
  final ValueChanged<ChannelPostComment> onReply;
  final VoidCallback onReactionSent;

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
                          unawaited(
                            openAdaptiveUserProfile(
                              context,
                              userId: userId,
                              name: name,
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
            _MomentsReactionControl(
              accountSlot: accountSlot,
              chatId: comment.chatId,
              messageId: comment.messageId,
              keyNamespace: 'moments-comment-reaction-${comment.messageId}',
              onReactionSent: onReactionSent,
              hiddenBuilder: _reactionContent,
              contentBuilder: _reactionContent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _reactionContent(BuildContext context, [AppIconData? icon]) {
    final c = context.colors;
    return SizedBox(
      width: 34,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) AppIcon(icon, size: 21, color: c.textTertiary),
          if (comment.reactionCount > 0) ...[
            if (icon != null) const SizedBox(height: 3),
            Text(
              _compactCount(comment.reactionCount),
              key: ValueKey(
                'moments-comment-reaction-count-${comment.messageId}',
              ),
              style: TextStyle(fontSize: 12, color: c.textTertiary),
            ),
          ],
        ],
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
        OutgoingAttachmentKind.voiceNote => HeroAppIcons.microphone,
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
    final selected = await showAppModalSheet<ChatSummary>(
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
    if (channel == null || (text.isEmpty && _attachments.isEmpty) || _sending) {
      return;
    }
    setState(() => _sending = true);
    try {
      final formatted = _richTextPayload?.text.trim() == text
          ? _richTextPayload!
          : await parseTelegramMarkdownWithTdLib(
              text,
              query: TdClient.shared.query,
            );
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
                  allowAnimation: false,
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
                              allowAnimation: false,
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
                  unawaited(
                    openAdaptiveUserProfile(
                      context,
                      userId: userId,
                      name: name,
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
                accountSlot: post.accountSlot,
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
      ((message.replyToPreview?.trim().isNotEmpty ?? false) ||
          message.replyToImage != null);
}

class _PostReplyQuote extends StatelessWidget {
  const _PostReplyQuote({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sender = message.replyToSender?.trim();
    final preview = message.replyToPreview?.trim() ?? '';
    final image = message.replyToImage;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final hasText = (sender?.isNotEmpty ?? false) || preview.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
      decoration: BoxDecoration(
        color: _momentQuoteFill(c),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (image != null) ...[
            SizedBox(
              key: const ValueKey('momentsReplyMediaPreview'),
              width: 52,
              height: 52,
              child: TDImage(
                photo: image,
                cornerRadius: 6,
                cacheWidth: (52 * pixelRatio).round(),
                cacheHeight: (52 * pixelRatio).round(),
              ),
            ),
            if (hasText) const SizedBox(width: 10),
          ],
          if (hasText)
            Expanded(
              child: RichText(
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    color: c.textPrimary,
                  ),
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
            ),
        ],
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
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          children: [
            PhotoAvatar(
              title: meName,
              photo: mePhoto,
              size: 26,
              allowAnimation: false,
            ),
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
        AppStrings.plural(
          AppStringKeys.momentsCommentCount,
          post.message.commentCount,
        ),
        style: TextStyle(fontSize: 13, color: c.linkBlue),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final comment in comments)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => pushAppChatRoute(
              context,
              AppChatPageRoute<void>(
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
                      unawaited(
                        openAdaptiveUserProfile(
                          context,
                          userId: userId,
                          name: name,
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
  const _PostImageGroup({
    required this.messages,
    required this.sourceChatId,
    required this.accountSlot,
  });

  final List<ChatMessage> messages;
  final int sourceChatId;
  final int accountSlot;

  @override
  Widget build(BuildContext context) {
    // sizeOf, not of: depending on the whole MediaQueryData rebuilt every
    // album in the viewport on each frame of the keyboard animation.
    final width = MediaQuery.sizeOf(context).width - 28;
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
                    accountSlot: accountSlot,
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
          builder: (_) => VideoOnDemandPlayerView(queue: _videoQueue(message)),
        ),
      );
      return;
    }
    _openImage(context, message);
  }

  VideoPlaybackQueue _videoQueue(ChatMessage current) {
    final videos = messages.where((message) => message.video != null).toList();
    if (!videos.any((message) => message.id == current.id)) videos.add(current);
    final index = videos.indexWhere((message) => message.id == current.id);
    return VideoPlaybackQueue(
      items: [
        for (final message in videos)
          VideoPlaybackItem(
            video: message.video!,
            accountSlot: accountSlot,
            thumb: message.image,
            width: message.imageWidth,
            height: message.imageHeight,
            durationSeconds: message.videoDuration,
            sourceChatId: sourceChatId,
            messageId: message.id,
            title: message.text.trim().replaceAll('\n', ' '),
          ),
      ],
      index: index < 0 ? 0 : index,
    );
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
    unawaited(
      openImagePreview(
        context,
        items: refs,
        startIndex: (startIndex < 0 ? 0 : startIndex).clamp(0, refs.length - 1),
      ),
    );
  }
}

class _PostImageTile extends StatelessWidget {
  const _PostImageTile({
    required this.message,
    required this.width,
    required this.height,
    required this.accountSlot,
    this.extraCount = 0,
  });

  final ChatMessage message;
  final double width;
  final double height;
  final int accountSlot;
  final int extraCount;

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
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
              cacheWidth: (width * pixelRatio).round(),
              cacheHeight: (height * pixelRatio).round(),
              showProgress: true,
              accountSlot: accountSlot,
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
                    fontWeight: FontWeight.w600,
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
        _MomentsReactionControl(
          accountSlot: post.accountSlot,
          chatId: channel.id,
          messageId: message.id,
          keyNamespace: 'moments-reaction',
          contentBuilder: (context, icon) => SizedBox.square(
            dimension: _actionSize,
            child: Center(
              child: AppIcon(
                icon,
                size: _iconSize,
                color: context.colors.textPrimary,
              ),
            ),
          ),
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
          HeroAppIcons.forward,
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
    final shownNames = names.take(3).toList();
    final shown = shownNames.join(AppStrings.t(AppStringKeys.listSeparator));
    if (reactionCount > names.length || names.length > 3) {
      return AppStrings.t(AppStringKeys.momentsLikedByListWithOthers, {
        'value1': shown,
        // Every locale's template reads "and N others" — the remainder
        // beyond the listed names, not the total like count.
        'value2': math.max(1, reactionCount - shownNames.length),
      });
    }
    return AppStrings.t(AppStringKeys.momentsUserLiked, {'value1': shown});
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

class _MomentsReactionControl extends StatefulWidget {
  const _MomentsReactionControl({
    required this.accountSlot,
    required this.chatId,
    required this.messageId,
    required this.keyNamespace,
    required this.contentBuilder,
    this.hiddenBuilder,
    this.onReactionSent,
  });

  final int accountSlot;
  final int chatId;
  final int messageId;
  final String keyNamespace;
  final Widget Function(BuildContext context, AppIconData icon) contentBuilder;
  final WidgetBuilder? hiddenBuilder;
  final VoidCallback? onReactionSent;

  @override
  State<_MomentsReactionControl> createState() =>
      _MomentsReactionControlState();
}

class _MomentsReactionControlState extends State<_MomentsReactionControl> {
  static const _thumbsUp = QuickReactionChoice.emoji('👍');

  MessageReactionAvailability? _availability;
  List<QuickReactionChoice> _arbitraryCustomChoices = const [];
  int _availabilityGeneration = 0;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadAvailability();
  }

  @override
  void didUpdateWidget(_MomentsReactionControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_matchesTarget(
      oldWidget.accountSlot,
      oldWidget.chatId,
      oldWidget.messageId,
    )) {
      _availability = null;
      _arbitraryCustomChoices = const [];
      _sending = false;
      _loadAvailability();
    }
  }

  bool _matchesTarget(int accountSlot, int chatId, int messageId) =>
      widget.accountSlot == accountSlot &&
      widget.chatId == chatId &&
      widget.messageId == messageId;

  Future<MessageReactionAvailability> _fetchAvailability({
    required int accountSlot,
    required int chatId,
    required int messageId,
  }) async {
    final client = TdClient.shared;
    final responses = await Future.wait([
      client.queryForSlot({
        '@type': 'getMessageAvailableReactions',
        'chat_id': chatId,
        'message_id': messageId,
        'row_size': 25,
      }, accountSlot),
      client.queryForSlot({
        '@type': 'getOption',
        'name': 'is_premium',
      }, accountSlot),
    ]);
    return MessageReactionAvailability.fromTd(
      responses.first,
      isPremium: responses.last.boolean('value') ?? false,
    );
  }

  Future<void> _loadAvailability() async {
    final accountSlot = widget.accountSlot;
    final chatId = widget.chatId;
    final messageId = widget.messageId;
    final generation = ++_availabilityGeneration;
    MessageReactionAvailability? availability;
    var arbitraryCustomChoices = const <QuickReactionChoice>[];
    try {
      availability = await _fetchAvailability(
        accountSlot: accountSlot,
        chatId: chatId,
        messageId: messageId,
      );
      if (availability.allowArbitraryCustom) {
        arbitraryCustomChoices = await _cachedInstalledCustomReactionChoices(
          accountSlot,
        );
      }
    } catch (_) {
      // Fail closed: global reaction defaults are not authoritative for this
      // particular message and can trigger MESSAGE_REACTION_INVALID.
    }
    if (!mounted ||
        !_matchesTarget(accountSlot, chatId, messageId) ||
        generation != _availabilityGeneration) {
      return;
    }
    setState(() {
      _availability = availability;
      _arbitraryCustomChoices = arbitraryCustomChoices;
    });
  }

  @override
  Widget build(BuildContext context) {
    var action = momentsReactionAction(_availability);
    if (action == MomentsReactionAction.openSelector &&
        _availability!.choices.isEmpty &&
        _arbitraryCustomChoices.isEmpty) {
      // TDLib permits arbitrary custom emoji, but this account has none to
      // present. Do not expose a selector that contains zero choices.
      action = MomentsReactionAction.hidden;
    }
    if (action == MomentsReactionAction.hidden) {
      return widget.hiddenBuilder?.call(context) ?? const SizedBox.shrink();
    }
    final icon = action == MomentsReactionAction.sendThumbsUp
        ? HeroAppIcons.thumbsUp
        : HeroAppIcons.solidFaceSmile;
    return GestureDetector(
      key: ValueKey('${widget.keyNamespace}-action'),
      behavior: HitTestBehavior.opaque,
      onTap: _sending
          ? null
          : action == MomentsReactionAction.sendThumbsUp
          ? () => unawaited(_sendReaction(_thumbsUp))
          : () => unawaited(_openSelector()),
      onLongPress: _sending ? null : () => unawaited(_openSelector()),
      child: widget.contentBuilder(context, icon),
    );
  }

  Future<void> _openSelector() async {
    final accountSlot = widget.accountSlot;
    final chatId = widget.chatId;
    final messageId = widget.messageId;
    final generation = _availabilityGeneration;
    final availability = _availability;
    if (availability == null) return;
    final choices = <QuickReactionChoice>[
      ...availability.choices,
      for (final choice in _arbitraryCustomChoices)
        if (!availability.choices.contains(choice)) choice,
    ];
    if (choices.isEmpty) return;
    final selected = await showAppModalSheet<QuickReactionChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _MomentsReactionSelector(choices: choices),
    );
    if (selected == null ||
        !mounted ||
        !_matchesTarget(accountSlot, chatId, messageId) ||
        generation != _availabilityGeneration) {
      return;
    }
    await _sendReaction(selected);
  }

  Future<void> _sendReaction(QuickReactionChoice requested) async {
    if (_sending) return;
    final accountSlot = widget.accountSlot;
    final chatId = widget.chatId;
    final messageId = widget.messageId;
    final generation = _availabilityGeneration;
    setState(() => _sending = true);
    try {
      // Availability can change while a row or selector is onscreen. Re-read
      // it immediately before mutation and send TDLib's canonical value.
      final fresh = await _fetchAvailability(
        accountSlot: accountSlot,
        chatId: chatId,
        messageId: messageId,
      );
      final freshArbitraryCustomChoices = fresh.allowArbitraryCustom
          ? await _cachedInstalledCustomReactionChoices(accountSlot)
          : const <QuickReactionChoice>[];
      if (!mounted ||
          !_matchesTarget(accountSlot, chatId, messageId) ||
          generation != _availabilityGeneration) {
        return;
      }
      setState(() {
        _availability = fresh;
        // A message can become restricted while its selector is open. Never
        // retain account-wide custom choices after the authoritative response
        // stops allowing them for this message.
        _arbitraryCustomChoices = freshArbitraryCustomChoices;
      });
      final reaction = fresh.canonicalChoice(requested);
      if (reaction == null) return;
      await TdClient.shared.queryForSlot({
        '@type': 'addMessageReaction',
        'chat_id': chatId,
        'message_id': messageId,
        'reaction_type': reaction.isCustom
            ? {
                '@type': 'reactionTypeCustomEmoji',
                'custom_emoji_id': reaction.customEmojiId,
              }
            : {'@type': 'reactionTypeEmoji', 'emoji': reaction.emoji},
        'is_big': false,
        'update_recent_reactions': true,
      }, accountSlot);
      if (!mounted || !_matchesTarget(accountSlot, chatId, messageId)) return;
      widget.onReactionSent?.call();
      showToast(context, AppStringKeys.momentsLiked);
    } catch (_) {
      if (mounted && _matchesTarget(accountSlot, chatId, messageId)) {
        showToast(context, AppStringKeys.topicPostContentActionFailed);
      }
    } finally {
      if (mounted && _matchesTarget(accountSlot, chatId, messageId)) {
        setState(() => _sending = false);
      }
    }
  }
}

class _MomentsReactionSelector extends StatelessWidget {
  const _MomentsReactionSelector({required this.choices});

  final List<QuickReactionChoice> choices;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      child: Container(
        key: const ValueKey('moments-reaction-selector'),
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 320),
        margin: const EdgeInsets.all(AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: c.divider, width: AppMetric.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: GridView.builder(
          shrinkWrap: true,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: AppSpacing.xs,
            crossAxisSpacing: AppSpacing.xs,
          ),
          itemCount: choices.length,
          itemBuilder: (context, index) {
            final reaction = choices[index];
            return GestureDetector(
              key: ValueKey('moments-reaction-choice-${reaction.storageValue}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(reaction),
              child: SizedBox.square(
                dimension: 42,
                child: Center(
                  child: reaction.isCustom
                      ? CustomEmojiView(
                          id: reaction.customEmojiId,
                          size: 29,
                          color: c.textPrimary,
                        )
                      : Text(
                          reaction.emoji,
                          textScaler: TextScaler.noScaling,
                          style: const TextStyle(fontSize: 29),
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

const _installedCustomReactionClientCacheLimit = 8;
const _installedCustomReactionSetLimit = 24;
const _installedCustomReactionChoiceLimit = 280;
const _installedCustomReactionCacheLifetime = Duration(minutes: 10);

class _InstalledCustomReactionChoiceCacheEntry {
  const _InstalledCustomReactionChoiceCacheEntry({
    required this.createdAt,
    required this.value,
  });

  final DateTime createdAt;
  final Future<List<QuickReactionChoice>> value;
}

final Map<int, _InstalledCustomReactionChoiceCacheEntry>
_installedCustomReactionChoiceCache = {};

@visibleForTesting
void resetMomentsInstalledCustomReactionChoiceCache() {
  _installedCustomReactionChoiceCache.clear();
}

Future<List<QuickReactionChoice>> _cachedInstalledCustomReactionChoices(
  int accountSlot,
) {
  final clientId = TdClient.shared.clientId(accountSlot);
  if (clientId == null) return Future.value(const <QuickReactionChoice>[]);
  final now = DateTime.now();
  final cached = _installedCustomReactionChoiceCache.remove(clientId);
  if (cached != null &&
      now.difference(cached.createdAt) <
          _installedCustomReactionCacheLifetime) {
    _installedCustomReactionChoiceCache[clientId] = cached;
    return cached.value;
  }

  // Store the in-flight future before issuing pack requests. Every visible
  // post/comment for this client then joins the same bounded load.
  final value = _loadInstalledCustomReactionChoices(
    accountSlot,
  ).then((choices) => choices, onError: (_) => const <QuickReactionChoice>[]);
  _installedCustomReactionChoiceCache[clientId] =
      _InstalledCustomReactionChoiceCacheEntry(createdAt: now, value: value);
  while (_installedCustomReactionChoiceCache.length >
      _installedCustomReactionClientCacheLimit) {
    _installedCustomReactionChoiceCache.remove(
      _installedCustomReactionChoiceCache.keys.first,
    );
  }
  return value;
}

Future<List<QuickReactionChoice>> _loadInstalledCustomReactionChoices(
  int accountSlot,
) async {
  final client = TdClient.shared;
  final installed = await client.queryForSlot({
    '@type': 'getInstalledStickerSets',
    'sticker_type': {'@type': 'stickerTypeCustomEmoji'},
  }, accountSlot);
  final infos = installed.objects('sets') ?? const <Map<String, dynamic>>[];
  final sets = await Future.wait(
    infos.take(_installedCustomReactionSetLimit).map((info) async {
      final setId = info.int64('id');
      if (setId == null) return null;
      try {
        return await client.queryForSlot({
          '@type': 'getStickerSet',
          'set_id': setId,
        }, accountSlot);
      } catch (_) {
        return null;
      }
    }),
  );
  final choices = <QuickReactionChoice>[];
  final seen = <int>{};
  for (final set in sets.whereType<Map<String, dynamic>>()) {
    for (final sticker
        in set.objects('stickers') ?? const <Map<String, dynamic>>[]) {
      final id = sticker.obj('full_type')?.int64('custom_emoji_id') ?? 0;
      if (id != 0 && seen.add(id)) {
        choices.add(QuickReactionChoice.custom(id));
        if (choices.length >= _installedCustomReactionChoiceLimit) {
          return List.unmodifiable(choices);
        }
      }
    }
  }
  return List.unmodifiable(choices);
}

class StoryShelf extends StatelessWidget {
  const StoryShelf({
    super.key,
    required this.model,
    required this.canPublish,
    required this.onCreate,
    required this.onManage,
  });

  final MomentsViewModel model;
  final bool canPublish;
  final VoidCallback onCreate;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final groups = model.groups;
    final showLoader = model.loading && groups.isEmpty;
    return Container(
      color: c.background,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  AppStringKeys.momentsStories.l10n(context),
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 91,
            // Lazy: the eager children form built a tile per friend with active
            // stories on every rebuild, and paging emits one update per friend.
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: 1 + groups.length + (showLoader ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return _StoryActionTile(
                    key: const ValueKey('my-story-action'),
                    label: AppStringKeys.storiesMy.l10n(context),
                    icon: HeroAppIcons.inbox,
                    photo: model.selfPhoto,
                    photoTitle: model.selfName,
                    onTap: model.ownGroup == null
                        ? onManage
                        : () => _openStory(context, model.ownGroup!),
                    onBadgeTap: canPublish ? onCreate : null,
                    showBadge: canPublish,
                    prominent: model.ownGroup == null && canPublish,
                  );
                }
                if (i > groups.length) {
                  return const SizedBox(
                    width: 66,
                    child: Center(child: AppActivityIndicator(size: 24)),
                  );
                }
                final group = groups[i - 1];
                return _StoryGroupTile(
                  key: ValueKey('story-group-${group.chatId}'),
                  group: group,
                  onTap: () => _openStory(context, group),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static void _openStory(BuildContext context, StoryGroup group) {
    Navigator.of(context).push(
      AppPageRoute<void>(
        fullscreenDialog: true,
        pageBuilder: (_, _, _) =>
            StoryViewerView(chatId: group.chatId, storyIds: group.storyIds),
      ),
    );
  }
}

class _StoryActionTile extends StatelessWidget {
  const _StoryActionTile({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.prominent = false,
    this.photo,
    this.photoTitle = '',
    this.onBadgeTap,
    this.showBadge = true,
  });

  final String label;
  final AppIconData icon;
  final VoidCallback onTap;
  final bool prominent;
  final TdFileRef? photo;
  final String photoTitle;
  final VoidCallback? onBadgeTap;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              SizedBox(
                width: 62,
                height: 62,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: prominent ? AppTheme.brandGradient : null,
                        border: prominent
                            ? null
                            : Border.all(color: c.divider, width: 1.5),
                      ),
                      child: photo != null
                          ? PhotoAvatar(
                              title: photoTitle,
                              photo: photo,
                              size: 57,
                              allowAnimation: false,
                            )
                          : DecoratedBox(
                              decoration: BoxDecoration(
                                color: prominent
                                    ? c.background
                                    : c.groupedBackground,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: AppIcon(
                                  icon,
                                  size: 25,
                                  color: prominent
                                      ? AppTheme.brand
                                      : c.textSecondary,
                                ),
                              ),
                            ),
                    ),
                    if (showBadge)
                      Positioned(
                        right: -1,
                        bottom: -1,
                        child: GestureDetector(
                          key: const ValueKey('story-create-badge'),
                          behavior: HitTestBehavior.opaque,
                          onTap: onBadgeTap,
                          child: Container(
                            constraints: const BoxConstraints(
                              minWidth: 21,
                              minHeight: 21,
                            ),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppTheme.brand,
                              borderRadius: BorderRadius.circular(
                                AppRadius.card,
                              ),
                              border: Border.all(color: c.background, width: 2),
                            ),
                            child: const AppIcon(
                              HeroAppIcons.plus,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoryGroupTile extends StatelessWidget {
  const _StoryGroupTile({super.key, required this.group, required this.onTap});

  final StoryGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label:
          '${group.name}, ${context.l10n.t(group.hasUnread ? AppStringKeys.storiesCountNew : AppStringKeys.storiesCountViewed, {'value1': group.storyIds.length})}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              Container(
                width: 62,
                height: 62,
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: group.hasUnread ? AppTheme.brandGradient : null,
                  border: group.hasUnread
                      ? null
                      : Border.all(color: c.divider, width: 1.5),
                ),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: c.background,
                    shape: BoxShape.circle,
                  ),
                  child: PhotoAvatar(
                    title: group.name,
                    photo: group.photo,
                    size: 53,
                    allowAnimation: false,
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                group.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: group.hasUnread ? c.textPrimary : c.textSecondary,
                  fontSize: 12,
                  fontWeight: group.hasUnread
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StoriesView extends StatefulWidget {
  const StoriesView({super.key, this.showBackButton = true, this.service});

  final bool showBackButton;
  final StoryService? service;

  @override
  State<StoriesView> createState() => _StoriesViewState();
}

class _StoriesViewState extends State<StoriesView> {
  final _model = MomentsViewModel();
  late final StoryService _service = widget.service ?? StoryService();
  bool _canPublish = false;

  Future<void> _loadPublishingPermission() async {
    var allowed = false;
    try {
      allowed = await _service.canPostAnyStory();
    } catch (_) {}
    if (mounted) setState(() => _canPublish = allowed);
  }

  Future<void> _createStory() async {
    if (!_canPublish) return;
    final changed = await Navigator.of(context, rootNavigator: true).push<bool>(
      AppPageRoute<bool>(
        fullscreenDialog: true,
        pageBuilder: (_, _, _) => StoryAuthoringView(service: _service),
      ),
    );
    if (changed == true) _model.refresh();
    await _loadPublishingPermission();
  }

  Future<void> _manageStories() async {
    try {
      final chatId = await _service.savedMessagesChatId();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              StoryManagementView(chatId: chatId, service: _service),
        ),
      );
      _model.refresh();
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          context.l10n.t(AppStringKeys.storiesOpenFailed, {'value1': error}),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _model.addListener(() {
      if (mounted) setState(() {});
    });
    _model.start();
    unawaited(_loadPublishingPermission());
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
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _model.refresh,
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: AppIcon(
                      HeroAppIcons.arrowsRotate,
                      size: 20,
                      color: AppTheme.brand,
                    ),
                  ),
                ),
                if (_canPublish) ...[
                  const SizedBox(width: 12),
                  GestureDetector(
                    key: const ValueKey('stories-publish-action'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _createStory,
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: AppIcon(
                        HeroAppIcons.plus,
                        size: 22,
                        color: AppTheme.brand,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(child: _content()),
        ],
      ),
    );
  }

  Widget _content() {
    final c = context.colors;
    final groups = _model.groups;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      children: [
        Row(
          children: [
            if (_canPublish) ...[
              Expanded(
                child: _primaryAction(
                  icon: HeroAppIcons.camera,
                  title: AppStringKeys.storiesNew.l10n(context),
                  subtitle: AppStringKeys.storiesPhotoVideo.l10n(context),
                  onTap: _createStory,
                  prominent: true,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: _primaryAction(
                icon: HeroAppIcons.inbox,
                title: AppStringKeys.storiesMy.l10n(context),
                subtitle: AppStringKeys.storiesProfileArchive.l10n(context),
                onTap: _manageStories,
              ),
            ),
          ],
        ),
        if (_model.ownGroup case final own?) ...[
          const SizedBox(height: 12),
          _ownStoryCard(own),
        ],
        const SizedBox(height: 22),
        Row(
          children: [
            Text(
              AppStringKeys.storiesRecent.l10n(context),
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (_model.loading) const AppActivityIndicator(size: 18),
          ],
        ),
        const SizedBox(height: 10),
        if (groups.isEmpty && _model.loading)
          _loadingCard()
        else if (groups.isEmpty)
          _emptyCard()
        else
          for (final group in groups) ...[
            _row(group),
            if (group != groups.last) const SizedBox(height: 8),
          ],
      ],
    );
  }

  Widget _primaryAction({
    required AppIconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool prominent = false,
  }) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 84,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            gradient: prominent ? AppTheme.brandGradient : null,
            color: prominent ? null : c.background,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: prominent ? null : Border.all(color: c.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: prominent
                      ? Colors.white.withValues(alpha: 0.2)
                      : AppTheme.brand.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: AppIcon(
                  icon,
                  size: 22,
                  color: prominent ? Colors.white : AppTheme.brand,
                ),
              ),
              const SizedBox(width: 11),
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
                        color: prominent ? Colors.white : c.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: prominent
                            ? Colors.white.withValues(alpha: 0.78)
                            : c.textSecondary,
                        fontSize: 11,
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

  Widget _ownStoryCard(StoryGroup group) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openGroup(group),
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.brand.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppTheme.brand.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            PhotoAvatar(
              title: _model.selfName,
              photo: _model.selfPhoto,
              size: 42,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStringKeys.storiesYourActive.l10n(context),
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.t(AppStringKeys.storiesActiveCount, {
                      'value1': group.storyIds.length,
                    }),
                    style: TextStyle(color: c.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            AppIcon(HeroAppIcons.chevronRight, size: 17, color: c.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _loadingCard() => Container(
    height: 150,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: context.colors.background,
      borderRadius: BorderRadius.circular(AppRadius.lg),
    ),
    child: const AppActivityIndicator(size: 30),
  );

  Widget _emptyCard() {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.brand.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: AppIcon(
              HeroAppIcons.images,
              size: 28,
              color: AppTheme.brand,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            AppStringKeys.storiesEmptyTitle.l10n(context),
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppStringKeys.storiesEmptyDescription.l10n(context),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          if (_canPublish) ...[
            const SizedBox(height: 18),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _createStory,
              child: Container(
                height: 42,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: AppTheme.brand,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Text(
                  AppStringKeys.storiesCreate.l10n(context),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(StoryGroup group) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openGroup(group),
      child: Container(
        height: 78,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: c.divider),
        ),
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: group.hasUnread ? AppTheme.brandGradient : null,
                border: group.hasUnread
                    ? null
                    : Border.all(color: c.divider, width: 1.5),
              ),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: c.background,
                  shape: BoxShape.circle,
                ),
                child: PhotoAvatar(
                  title: group.name,
                  photo: group.photo,
                  allowAnimation: false,
                ),
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
                    group.hasUnread
                        ? context.l10n.t(AppStringKeys.storiesCountNew, {
                            'value1': group.storyIds.length,
                          })
                        : context.l10n.t(AppStringKeys.storiesCountViewed, {
                            'value1': group.storyIds.length,
                          }),
                    style: TextStyle(
                      fontSize: 12,
                      color: group.hasUnread ? AppTheme.brand : c.textSecondary,
                      fontWeight: group.hasUnread
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  // order is a sort weight with flag bits, not a timestamp.
                  DateText.listLabel(group.date),
                  style: TextStyle(fontSize: 11, color: c.textTertiary),
                ),
                const SizedBox(height: 7),
                AppIcon(
                  HeroAppIcons.chevronRight,
                  size: 16,
                  color: c.textTertiary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openGroup(StoryGroup group) {
    Navigator.of(context).push(
      AppPageRoute<void>(
        fullscreenDialog: true,
        pageBuilder: (_, _, _) =>
            StoryViewerView(chatId: group.chatId, storyIds: group.storyIds),
      ),
    );
  }
}

class MomentsViewModel extends ChangeNotifier {
  List<StoryGroup> groups = [];
  StoryGroup? ownGroup;
  String selfName = '';
  TdFileRef? selfPhoto;
  bool loading = false;
  final Map<int, StoryGroup> _map = {};
  int? _selfChatId;
  bool _started = false;
  StreamSubscription? _sub;

  void start() {
    if (_started) return;
    _started = true;
    loading = true;
    notifyListeners();
    _sub = TdClient.shared.subscribe().listen((update) {
      if (update.type == 'updateChatActiveStories') _handle(update);
    });
    unawaited(_loadSelf());
    unawaited(_loadAll());
  }

  void refresh() {
    if (!_started) return;
    loading = true;
    notifyListeners();
    unawaited(_loadAll());
  }

  Future<void> _loadSelf() async {
    try {
      final me = await TdClient.shared.query({'@type': 'getMe'});
      final userId = me.int64('id');
      if (userId == null) return;
      final chat = await TdClient.shared.query({
        '@type': 'createPrivateChat',
        'user_id': userId,
        'force': false,
      });
      _selfChatId = chat.int64('id');
      selfName = TDParse.userName(me);
      selfPhoto = TDParse.smallPhoto(me.obj('profile_photo'));
      _publish();
    } catch (_) {}
  }

  @override
  void dispose() {
    // Without this the leaked listener keeps notifying a disposed notifier
    // (and issuing getChat calls) after every Stories visit.
    unawaited(_sub?.cancel());
    _sub = null;
    super.dispose();
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
    final newestDate = infos
        .map((s) => s.integer('date') ?? 0)
        .fold(0, math.max);

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
      name = _map[chatId]?.name ?? AppStrings.t(AppStringKeys.momentsUnknown);
    }

    _map[chatId] = StoryGroup(
      chatId: chatId,
      name: name,
      photo: photo,
      storyIds: storyIds,
      hasUnread: hasUnread,
      order: order,
      date: newestDate,
    );
    _publish();
    loading = false;
  }

  void _publish() {
    ownGroup = _selfChatId == null ? null : _map[_selfChatId];
    groups = _map.values.where((group) => group.chatId != _selfChatId).toList()
      ..sort((a, b) => b.order.compareTo(a.order));
    notifyListeners();
  }
}
