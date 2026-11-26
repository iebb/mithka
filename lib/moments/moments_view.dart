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
import '../app/bottom_bar_layout.dart';
import '../app/chat_deep_link_controller.dart';
import '../app/ipad_window_chrome.dart';
import '../chat/chat_picker_view.dart';
import '../chat/chat_view.dart';
import '../chat/composer/outgoing_attachment.dart';
import '../chat/composer/rich_text_composer_view.dart';
import '../chat/composer/rich_text_format.dart';
import '../chat/forward_handoff.dart';
import '../chat/media/image_preview.dart';
import '../chat/media/music_player_controller.dart';
import '../chat/media/shared_media_view.dart';
import '../chat/media/video_playback_queue.dart';
import '../chat/media/video_player_view.dart';
import '../chat/messages/forward_markdown.dart';
import '../chat/messages/media_album_layout.dart';
import '../chat/messages/media_spoiler.dart';
import '../chat/messages/message_reaction_availability.dart';
import '../chat/messages/pangu_spacing.dart';
import '../chat/messages/quick_reaction_choice.dart';
import '../chat/messages/telegram_rich_text.dart';
import '../chat/stickers/animated_sticker_view.dart';
import '../chat/stickers/custom_emoji.dart';
import '../chat/stickers/video_sticker_view.dart';
import '../chats/chat_list_view_model.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/app_text_selection_toolbar.dart';
import '../components/desktop_content_constraint.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../components/vip_badge.dart';
import '../l10n/app_localizations.dart';
import '../media/app_asset_picker.dart';
import '../platform/adaptive_platform.dart';
import '../profile/adaptive_profile_launcher.dart';
import '../profile/profile_header_background.dart';
import '../tdlib/chat_membership.dart';
import '../tdlib/display_text.dart';
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

part 'moments_post_detail_composer.dart';
part 'moments_post_widgets.dart';
part 'moments_stories.dart';

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

/// The `getMessageThreadHistory` request for a channel post's comments.
///
/// A post's own coordinates (`chat_id` = the channel, `message_id` = the post)
/// make TDLib resolve the thread itself, and for a post nobody has commented on
/// yet that resolution ends in a 500 "Receive messages in an unexpected chat":
/// the reply search returns nothing, so the linked discussion chat the result
/// has to be replayed in stays unknown, while the thread it already resolved
/// points exactly there. The thread coordinates `getMessageThread` returns
/// address the same thread without that resolution and answer an empty list for
/// a fresh post. Only a post whose thread is not resolved yet falls back to its
/// own coordinates.
@visibleForTesting
Map<String, dynamic> channelPostCommentsRequest({
  required ChannelPost post,
  ChannelPostThreadTarget? target,
  int fromMessageId = 0,
  int offset = 0,
  int limit = 100,
}) => {
  '@type': 'getMessageThreadHistory',
  'chat_id': target?.chatId ?? post.channel.id,
  'message_id': target?.messageThreadId ?? post.message.id,
  'from_message_id': fromMessageId,
  'offset': offset,
  'limit': limit,
};

/// One walk through a channel's history for the Moments feed.
@visibleForTesting
class ChannelHistoryLoad {
  const ChannelHistoryLoad({
    required this.messages,
    required this.reachedStart,
    required this.reconnected,
    this.oldestMessageId,
    this.oldestDate,
  });

  /// Every message the walk read below its starting cursor, service
  /// messages included; the feed filters those itself.
  final List<ChatMessage> messages;

  /// A page held nothing older than its cursor: the channel's first message
  /// has been read.
  final bool reachedStart;

  /// A walk from the newest message met the history loaded before it, so
  /// nothing between the two was skipped.
  final bool reconnected;

  /// The lowest message id read, and that message's date. Everything newer
  /// than it, back to the cursor, is in [messages].
  final int? oldestMessageId;
  final int? oldestDate;
}

typedef ChannelHistoryQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

/// Pages a channel's history backwards from [fromMessageId] (0 = newest).
///
/// TDLib chooses how many messages a `getChatHistory` page carries, and the
/// first page of a channel it has not cached yet usually holds only the last
/// message. Reading one page per channel left a channel's earlier posts —
/// an album an hour older than its latest text, say — out of the feed. The
/// walk keeps paging until [wanted] messages arrived, the channel's start was
/// reached, or [maxPages] pages were read. With [knownNewestMessageId] (a
/// refresh of a channel already in the feed) it instead pages until it meets
/// that loaded history again.
///
/// `from_message_id` is inclusive, so a page repeats its cursor; only ids
/// below it count. A first-page failure is rethrown; a later one keeps what
/// already arrived.
@visibleForTesting
Future<ChannelHistoryLoad> loadChannelHistory({
  required ChannelHistoryQuery query,
  required int chatId,
  required int fromMessageId,
  required int wanted,
  int? knownNewestMessageId,
  int maxPages = 5,
  bool Function()? cancelled,
}) async {
  final messages = <ChatMessage>[];
  var cursor = fromMessageId;
  var reachedStart = false;
  var reconnected = false;
  int? oldestId;
  int? oldestDate;
  for (var page = 0; page < maxPages; page++) {
    final Map<String, dynamic> response;
    try {
      response = await query({
        '@type': 'getChatHistory',
        'chat_id': chatId,
        'from_message_id': cursor,
        'offset': 0,
        'limit': wanted,
        'only_local': false,
      });
    } catch (_) {
      if (page == 0) rethrow;
      break;
    }
    if (cancelled?.call() == true) break;
    var advanced = false;
    for (final raw
        in response.objects('messages') ?? const <Map<String, dynamic>>[]) {
      final id = raw.int64('id');
      if (id == null || (cursor != 0 && id >= cursor)) continue;
      advanced = true;
      if (oldestId == null || id < oldestId) {
        oldestId = id;
        oldestDate = raw.integer('date') ?? oldestDate;
      }
      final message = TDParse.message(raw);
      if (message != null) messages.add(message);
    }
    if (!advanced) {
      reachedStart = true;
      break;
    }
    cursor = oldestId!;
    if (knownNewestMessageId != null) {
      if (cursor <= knownNewestMessageId) {
        reconnected = true;
        break;
      }
    } else if (messages.length >= wanted) {
      break;
    }
  }
  return ChannelHistoryLoad(
    messages: messages,
    reachedStart: reachedStart,
    reconnected: reconnected,
    oldestMessageId: oldestId,
    oldestDate: oldestDate,
  );
}

/// The date the merged feed is complete after: every post newer than it is
/// loaded.
///
/// Each channel has been read back to its own boundary. Below the newest of
/// those, a channel that still has unread history may own posts that sort
/// between the ones already loaded, so rendering them would show a gap that
/// later fills in above the reader. Channels whose start was reached impose
/// no boundary. The boundary second itself is not complete: an album shares
/// one date, and a page can end inside it.
@visibleForTesting
int channelFeedCompleteSince(
  Map<int, int> loadedSinceByChannel,
  Set<int> exhaustedChannels,
) {
  var since = 0;
  for (final entry in loadedSinceByChannel.entries) {
    if (exhaustedChannels.contains(entry.key)) continue;
    if (entry.value > since) since = entry.value;
  }
  return since;
}

class _MomentsFeedScrollAnchor {
  const _MomentsFeedScrollAnchor({required this.key, required this.leading});

  final GlobalKey key;
  final double leading;
}

final Map<String, double> _channelMomentsScrollOffsets = {};

class _MomentsHistorySnapshot {
  const _MomentsHistorySnapshot(
    this.posts,
    this.offset,
    this.nonMutedOnly,
    this.postableChannels,
    this.completeSince,
  );

  final List<ChannelPost> posts;
  final double offset;
  final bool nonMutedOnly;
  final List<ChatSummary> postableChannels;

  /// The retained posts are every loaded post newer than this date, so each
  /// restored channel is complete back to it.
  final int completeSince;
}

String _channelMomentsScrollKey({
  required int accountSlot,
  required bool isRootTab,
  required List<ChatSummary> initialChannels,
  ChatSummary? channel,
}) {
  if (channel != null) return '$accountSlot:channel:${channel.id}';
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
    this.replyToChatId,
    this.replyToMessageId,
    this.replyToSenderName,
    this.reactionCount = 0,
  });

  final int chatId;
  final int messageId;
  final String senderName;
  final String text;
  final List<MessageTextEntity> entities;
  final TdFileRef? senderPhoto;
  final int date;
  final int? replyToChatId;
  final int? replyToMessageId;
  final String? replyToSenderName;
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
  // Owned by the Moments root, not a process-wide cache of account messages.
  PageStorageBucket _channelHistory = PageStorageBucket();
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
      _channelHistory = PageStorageBucket();
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
        historyStorage: _channelHistory,
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
              padding: EdgeInsets.only(
                top: AppSpacing.md,
                bottom: BottomBarInset.of(context),
              ),
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
    this.channel,
    this.onOpenDetail,
    this.historyStorage,
  });

  final bool isRootTab;
  final String title;
  final List<ChatSummary> initialChannels;

  /// Shows only this channel — its whole history as one feed — instead of
  /// merging every joined channel. [title] and [initialChannels] are unused.
  final ChatSummary? channel;
  final ValueChanged<Widget>? onOpenDetail;
  final PageStorageBucket? historyStorage;

  @override
  State<ChannelMomentsView> createState() => _ChannelMomentsViewState();
}

class _ChannelMomentsViewState extends State<ChannelMomentsView> {
  final _model = ChatListViewModel();
  final _replyController = TextEditingController();
  final _replyFocus = FocusNode();
  late final ScrollController _scroll;
  double _lastScrollOffset = 0;
  late final String _scrollSessionKey;
  final Map<String, GlobalKey> _postWidgetKeys = {};
  double? _pendingScrollOffset;
  bool _scrollRestoreScheduled = false;
  StreamSubscription? _tdSub;
  Timer? _refreshTimer;
  Timer? _metadataHydrationTimer;
  Timer? _windowHydrationTimer;
  final Map<int, List<ChannelPost>> _postsByChannel = {};
  final Map<int, int> _oldestMessageByChannel = {};

  /// Per channel, the date of the oldest message read; see
  /// [channelFeedCompleteSince].
  final Map<int, int> _loadedSinceByChannel = {};
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
  int _meProfileIconId = 0;
  int _meEmojiStatusId = 0;
  bool _meIsPremium = false;
  bool _loadingPosts = false;
  bool _loadingPostableChannels = false;
  bool _refreshingLiveUpdates = false;
  bool _refreshingLatest = false;
  bool _nonMutedOnly = false;
  int _feedLoadGeneration = 0;
  int _lastBuiltPostIndex = 0;
  int _hydratedWindowStart = 0;
  int _hydratedWindowEnd = 0;
  static const _perChannelPageSize = 30;
  static const _metadataHydrationLimit = 60;
  static const _feedLimit = 500;
  static const _olderChannelsPerRound = 4;

  ChatSummary? get _scopedChannel => widget.channel;

  /// One channel's own feed has no cap: it is that channel's whole history.
  int? get _postLimit => _scopedChannel == null ? _feedLimit : null;

  @override
  void initState() {
    super.initState();
    _scrollSessionKey = _channelMomentsScrollKey(
      accountSlot: TdClient.shared.activeSlot,
      isRootTab: widget.isRootTab,
      initialChannels: widget.initialChannels,
      channel: _scopedChannel,
    );
    // A channel's own feed opens at its newest post, like its chat does.
    _pendingScrollOffset = _scopedChannel == null
        ? _channelMomentsScrollOffsets[_scrollSessionKey]
        : null;
    final saved = widget.historyStorage?.readState(
      context,
      identifier: _scrollSessionKey,
    );
    if (saved is _MomentsHistorySnapshot) {
      for (final post in saved.posts) {
        (_postsByChannel[post.channel.id] ??= []).add(post);
        _oldestMessageByChannel.update(
          post.channel.id,
          (id) => math.min(id, post.message.id),
          ifAbsent: () => post.message.id,
        );
        _loadedSinceByChannel[post.channel.id] = saved.completeSince;
      }
      _nonMutedOnly = saved.nonMutedOnly;
      _postableChannels = saved.postableChannels;
      _lastScrollOffset = saved.offset;
      _pendingScrollOffset = null;
    }
    _scroll = ScrollController(initialScrollOffset: _lastScrollOffset);
    // A single channel needs no chat list; loading one would only invalidate
    // and reload this feed every time any chat moved.
    if (_scopedChannel == null) _model.addListener(_onModel);
    _scroll.addListener(_onScroll);
    _tdSub = TdClient.shared
        .updatesOfAny(const [
          'updateNewMessage',
          'updateMessageContent',
          'updateMessageEdited',
          'updateMessageInteractionInfo',
          'updateMessageUnreadReactions',
          'updateDeleteMessages',
          'updateChatAddedToList',
          'updateChatRemovedFromList',
          'updateUser',
          'updateAccentColors',
          'updateProfileAccentColors',
        ])
        .listen(_handleTdUpdate);
    if (_scopedChannel == null) _model.onAppear();
    _loadMe();
    if (widget.initialChannels.isNotEmpty || _scopedChannel != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (saved is _MomentsHistorySnapshot) {
          // The first frame already contains the same rows and metadata. New
          // history then merges using the existing visible-post anchor.
          unawaited(_refreshLatest());
        } else {
          unawaited(_loadChannelPosts());
        }
      });
    }
    _scheduleScrollRestore();
  }

  @override
  void dispose() {
    if (_scroll.hasClients) {
      _channelMomentsScrollOffsets[_scrollSessionKey] = _scroll.offset;
      _lastScrollOffset = _scroll.offset;
    }
    // Retain exactly the rendered feed, including every member of its albums.
    // Capping raw messages at 500 would truncate a 500-post album-heavy feed.
    final rendered = _posts;
    final retainedIds = {
      for (final post in rendered)
        for (final message in post.messages) (post.channel.id, message.id),
    };
    var completeSince = channelFeedCompleteSince(
      _loadedSinceByChannel,
      _exhaustedChannels,
    );
    final limit = _postLimit;
    if (limit != null && rendered.length >= limit) {
      // The cap cut the feed inside its complete range: only posts newer
      // than the last rendered one are all retained.
      completeSince = math.max(
        completeSince,
        rendered.last.messages.map((message) => message.date).reduce(math.min),
      );
    }
    final retained = _postsByChannel.values
        .expand((posts) => posts)
        .where(
          (post) => retainedIds.contains((post.channel.id, post.message.id)),
        )
        .toList();
    widget.historyStorage?.writeState(
      context,
      _MomentsHistorySnapshot(
        retained,
        _lastScrollOffset,
        _nonMutedOnly,
        List.of(_postableChannels),
        completeSince,
      ),
      identifier: _scrollSessionKey,
    );
    _model.removeListener(_onModel);
    _model.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _tdSub?.cancel();
    _refreshTimer?.cancel();
    _metadataHydrationTimer?.cancel();
    _windowHydrationTimer?.cancel();
    _replyController.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    _lastScrollOffset = _scroll.offset;
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
      if (pending > position.maxScrollExtent && _canLoadOlder) {
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
      if (!mounted) return;
      setState(() => _applyMe(me));
      unawaited(_loadPostableChannels());
    } catch (_) {}
  }

  void _applyMe(Map<String, dynamic> me) {
    final name = TDParse.userName(me).trim();
    _meUserId = me.int64('id');
    if (name.isNotEmpty) _meName = name;
    _mePhoto = TDParse.smallPhoto(me.obj('profile_photo'));
    _meAccentColorId = me.integer('accent_color_id') ?? -1;
    _meProfileAccentColorId = me.integer('profile_accent_color_id') ?? -1;
    _meProfileIconId = me.int64('profile_background_custom_emoji_id') ?? 0;
    _meEmojiStatusId = TDParse.emojiStatusCustomEmojiId(me.obj('emoji_status'));
    _meIsPremium = me.boolean('is_premium') ?? false;
  }

  void _handleTdUpdate(Map<String, dynamic> update) {
    switch (update.type) {
      case 'updateAccentColors':
      case 'updateProfileAccentColors':
        if (mounted) setState(() {});

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
        _invalidateFeed();
        if (update.type == 'updateChatRemovedFromList') {
          _postsByChannel.remove(chatId);
          _loadedSinceByChannel.remove(chatId);
          if (mounted) setState(() {});
        }

      // A color, profile icon or status changed in another view or on another
      // device repaints the header straight away.
      case 'updateUser':
        final user = update.obj('user');
        if (user == null || _meUserId == null) return;
        if (user.int64('id') != _meUserId || !mounted) return;
        setState(() => _applyMe(user));
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
    final scoped = _scopedChannel;
    if (scoped != null) return _channelsCache = [scoped];
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
    final completeSince = channelFeedCompleteSince(
      _loadedSinceByChannel,
      _exhaustedChannels,
    );
    final posts =
        _postsByChannel.values
            .expand((items) => items)
            .where((post) => post.message.date > completeSince)
            .toList()
          ..sort((a, b) => b.message.date.compareTo(a.message.date));
    final grouped = _groupPostAlbums(posts);
    final limit = _postLimit;
    return _postsCache = limit == null ? grouped : grouped.take(limit).toList();
  }

  /// Whether paging older history can still extend the rendered feed.
  bool get _canLoadOlder {
    final limit = _postLimit;
    if (limit != null && _posts.length >= limit) return false;
    return _channels.any((channel) => !_exhaustedChannels.contains(channel.id));
  }

  /// The channels whose read history ends nearest to now. They hold the
  /// feed's completeness boundary up, so paging them is what extends it;
  /// paging every channel at each scroll end fetched history the feed could
  /// not show yet.
  Set<int> _channelsBoundingFeed() {
    final open =
        _loadedSinceByChannel.entries
            .where(
              (entry) =>
                  !_exhaustedChannels.contains(entry.key) &&
                  !_loadingChannels.contains(entry.key),
            )
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    return {for (final entry in open.take(_olderChannelsPerRound)) entry.key};
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
    if (loadOlder && !_canLoadOlder) return;
    final channels = allChannels;
    final generation = _feedLoadGeneration;
    final olderTargets = loadOlder ? _channelsBoundingFeed() : const <int>{};
    final loads = <Future<bool>>[];
    for (final channel in channels) {
      if (!await _isJoinedChannel(channel)) continue;
      final hasLoaded = _postsByChannel.containsKey(channel.id);
      if (_loadingChannels.contains(channel.id) ||
          _exhaustedChannels.contains(channel.id) ||
          (hasLoaded && !loadOlder)) {
        continue;
      }
      // Older pages go only to the channels holding the boundary up. One
      // whose last read failed has no boundary yet and is retried.
      if (hasLoaded &&
          _loadedSinceByChannel.containsKey(channel.id) &&
          !olderTargets.contains(channel.id)) {
        continue;
      }
      _loadingChannels.add(channel.id);
      loads.add(
        _loadPostsForChannel(
          channel,
          fromMessageId: loadOlder
              ? (_oldestMessageByChannel[channel.id] ?? 0)
              : 0,
          generation: generation,
        ),
      );
    }
    if (loads.isNotEmpty) {
      unawaited(_continueAfterLoads(loads, generation));
    }
    // Near the bottom of the feed the scroll listener calls this on every
    // tick; only a changed spinner state is worth a rebuild.
    final loading = _loadingChannels.isNotEmpty;
    if (loading == _loadingPosts) return;
    _loadingPosts = loading;
    if (mounted) setState(() {});
  }

  /// A round that moved the completeness boundary can still leave the end of
  /// the feed on screen — one busy channel holds the boundary just above the
  /// last rendered post. No scroll event follows then, so keep paging while
  /// the end is in reach.
  Future<void> _continueAfterLoads(
    List<Future<bool>> loads,
    int generation,
  ) async {
    final progressed = (await Future.wait(loads)).any((moved) => moved);
    if (!progressed || !mounted || generation != _feedLoadGeneration) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (_pendingScrollOffset != null) return; // the restore pages itself
      if (_scroll.position.extentAfter < 600) {
        _loadChannelPosts(loadOlder: true);
      }
    });
  }

  Future<bool> _isJoinedChannel(ChatSummary channel) async {
    // A channel's own feed reads whatever its chat can show, joined or not.
    if (_scopedChannel != null) return true;
    final cached = _joinedChannelCache[channel.id];
    if (cached != null) return cached;
    final joined = await isJoinedGroupOrChannelChat(channel.id);
    _joinedChannelCache[channel.id] = joined;
    _feedChatIds = null; // joined-state feeds the _channels filter
    _invalidateChannels();
    if (!joined) {
      _postsByChannel.remove(channel.id);
      _oldestMessageByChannel.remove(channel.id);
      _loadedSinceByChannel.remove(channel.id);
      _exhaustedChannels.add(channel.id);
      _invalidateFeed();
      if (mounted) setState(() {});
    }
    return joined;
  }

  /// Reads one round of [channel]'s history into the feed and reports whether
  /// the feed can now show more than before.
  ///
  /// [fromMessageId] 0 reads from the newest message: the first read of a
  /// channel, or a refresh that pages down until it meets the loaded posts.
  Future<bool> _loadPostsForChannel(
    ChatSummary channel, {
    required int fromMessageId,
    int? generation,
    bool notify = true,
  }) async {
    final accountSlot = TdClient.shared.activeSlot;
    bool isCurrent() =>
        mounted && (generation == null || generation == _feedLoadGeneration);
    final known = _postsByChannel[channel.id];
    final knownNewest = fromMessageId == 0 && known != null && known.isNotEmpty
        ? known.map((post) => post.message.id).reduce(math.max)
        : null;
    try {
      final load = await loadChannelHistory(
        query: (request) => TdClient.shared.queryForSlot(request, accountSlot),
        chatId: channel.id,
        fromMessageId: fromMessageId,
        wanted: _perChannelPageSize,
        knownNewestMessageId: knownNewest,
        cancelled: () => !isCurrent(),
      );
      if (!isCurrent()) return false;
      final previousSince = channelFeedCompleteSince(
        _loadedSinceByChannel,
        _exhaustedChannels,
      );
      final knownIds = {for (final post in known ?? const []) post.message.id};
      final posts = load.messages
          .where((message) => !message.isService)
          .map(
            (message) => ChannelPost(
              channel: channel,
              message: message,
              accountSlot: accountSlot,
            ),
          )
          .toList();
      final added = posts.any((post) => !knownIds.contains(post.message.id));
      _appendPosts(channel.id, posts);
      final oldestId = load.oldestMessageId;
      final oldestDate = load.oldestDate;
      if (oldestId != null && oldestDate != null) {
        // A refresh that ran out of pages before meeting the loaded posts
        // left a gap below it. Move the boundary up to what this walk read;
        // the next older read starts there and fills the gap.
        final gap =
            knownNewest != null && !load.reconnected && !load.reachedStart;
        final previousId = _oldestMessageByChannel[channel.id];
        final previousDate = _loadedSinceByChannel[channel.id];
        _oldestMessageByChannel[channel.id] = gap || previousId == null
            ? oldestId
            : math.min(previousId, oldestId);
        _loadedSinceByChannel[channel.id] = gap || previousDate == null
            ? oldestDate
            : math.min(previousDate, oldestDate);
      } else {
        // An empty channel still has a boundary: it has nothing to wait for.
        _loadedSinceByChannel.putIfAbsent(channel.id, () => 0);
      }
      if (load.reachedStart) _exhaustedChannels.add(channel.id);
      _invalidateFeed();
      _schedulePostMetadataHydration();
      return added ||
          channelFeedCompleteSince(_loadedSinceByChannel, _exhaustedChannels) !=
              previousSince;
    } catch (_) {
      if (!isCurrent()) return false;
      _postsByChannel.putIfAbsent(channel.id, () => const []);
      _invalidateFeed();
      return false;
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
      _loadedSinceByChannel.clear();
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
      _hydratePosts([
        ..._posts.take(_metadataHydrationLimit),
        ..._takeHydrationWindow(),
      ]);
    });
  }

  /// Rows past the head hydrate as they are built: a window around the first
  /// row built outside the previous window. A channel's own feed is read far
  /// deeper than the head.
  void _noteBuiltPost(int index) {
    if (index < _metadataHydrationLimit ||
        (index >= _hydratedWindowStart && index < _hydratedWindowEnd)) {
      return;
    }
    _lastBuiltPostIndex = index;
    _windowHydrationTimer?.cancel();
    _windowHydrationTimer = Timer(const Duration(milliseconds: 220), () {
      if (mounted) _hydratePosts(_takeHydrationWindow());
    });
  }

  List<ChannelPost> _takeHydrationWindow() {
    final feed = _posts;
    _hydratedWindowStart = math.max(
      _metadataHydrationLimit,
      _lastBuiltPostIndex - 30,
    );
    _hydratedWindowEnd = math.min(feed.length, _lastBuiltPostIndex + 20);
    if (_hydratedWindowStart >= _hydratedWindowEnd) return const [];
    return feed.sublist(_hydratedWindowStart, _hydratedWindowEnd);
  }

  void _hydratePosts(List<ChannelPost> posts) {
    if (posts.isEmpty) return;
    _loadAuthors(posts);
    _loadForwardAttributions(posts);
    _loadReplyQuotes(posts);
    _loadLikeNames(posts);
    _loadThreadTargets(posts);
    _loadComments(posts);
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

  final Map<String, Future<String?>> _forwardNames = {};

  void _loadForwardAttributions(List<ChannelPost> posts) {
    for (final post in posts) {
      for (final message in post.messages) {
        if (message.forwardOrigin?.trim().isNotEmpty == true) continue;
        final userId = message.forwardFromUserId;
        final chatId = message.forwardFromChatId;
        if (userId == null && chatId == null) continue;
        final key = '${post.accountSlot}:$userId:$chatId';
        final pending = _forwardNames.putIfAbsent(key, () async {
          try {
            final raw = await TdClient.shared.queryForSlot({
              '@type': userId != null ? 'getUser' : 'getChat',
              if (userId != null) 'user_id': userId else 'chat_id': chatId,
            }, post.accountSlot);
            return userId != null ? TDParse.userName(raw) : raw.str('title');
          } catch (_) {
            return null;
          }
        });
        unawaited(
          pending.then((name) {
            if (name == null || name.trim().isEmpty) {
              _forwardNames.remove(key);
              return;
            }
            message.forwardOrigin = name;
            _notifyPost(post);
          }),
        );
      }
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
      final raw = await TdClient.shared.queryForSlot({
        '@type': 'getMessage',
        'chat_id': post.channel.id,
        'message_id': replyToMessageId,
      }, post.accountSlot);
      final quoted = TDParse.message(raw);
      if (quoted == null) return;
      message.replyToPreview = _replyPreview(quoted);
      message.replyToImage = quoted.previewImage;
      message.replyToImageWidth = quoted.imageWidth;
      message.replyToImageHeight = quoted.imageHeight;
      message.replyToSender =
          await _senderName(quoted, accountSlot: post.accountSlot) ??
          post.channel.title;
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
        final properties = await TdClient.shared.queryForSlot({
          '@type': 'getMessageProperties',
          'chat_id': post.channel.id,
          'message_id': post.message.id,
        }, post.accountSlot);
        if (properties.boolean('can_get_message_thread') == false) return null;
      } catch (_) {}
      final target = await _fetchChannelPostThreadTarget(post);
      if (target == null) return null;
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
      final response = await TdClient.shared.queryForSlot(
        channelPostCommentsRequest(post: post, target: target, limit: 5),
        post.accountSlot,
      );
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
        final senderName = await _senderName(
          message,
          accountSlot: post.accountSlot,
        );
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
    // The comment text is shown trimmed; keep the formatting by re-addressing
    // the entities to the trimmed string instead of dropping them all.
    return trimTextForDisplay(message.text, message.textEntities).entities;
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
        if (post.message.replyToMessageId ==
                previous.message.replyToMessageId &&
            post.message.replyToChatId == previous.message.replyToChatId) {
          post.message.replyToSender ??= previous.message.replyToSender;
          if (!post.message.isContentRestricted) {
            post.message.replyToPreview ??= previous.message.replyToPreview;
            post.message.replyToImage ??= previous.message.replyToImage;
            post.message.replyToImageWidth ??=
                previous.message.replyToImageWidth;
            post.message.replyToImageHeight ??=
                previous.message.replyToImageHeight;
          }
        }
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
        final user = await TdClient.shared.queryForSlot({
          '@type': 'getUser',
          'user_id': senderId,
        }, post.accountSlot);
        final name = TDParse.userName(user).trim();
        if (name.isNotEmpty) post.authorName = name;
        post.authorPhoto = TDParse.smallPhoto(user.obj('profile_photo'));
      } else if (senderId != null && senderId < 0) {
        final chat = await TdClient.shared.queryForSlot({
          '@type': 'getChat',
          'chat_id': senderId,
        }, post.accountSlot);
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
      final response = await TdClient.shared.queryForSlot({
        '@type': 'getMessageAddedReactions',
        'chat_id': post.channel.id,
        'message_id': post.message.id,
        'reaction_type': {'@type': 'reactionTypeEmoji', 'emoji': '👍'},
        'offset': '',
        'limit': 4,
      }, post.accountSlot);
      final raw =
          response.objects('added_reactions') ??
          response.objects('reactions') ??
          const <Map<String, dynamic>>[];
      final names = <String>[];
      for (final item in raw) {
        final name = await _reactionSenderName(
          item.obj('sender_id'),
          accountSlot: post.accountSlot,
        );
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

  Future<String?> _reactionSenderName(
    Map<String, dynamic>? sender, {
    int? accountSlot,
  }) async {
    final slot = accountSlot ?? TdClient.shared.activeSlot;
    try {
      switch (sender?.type) {
        case 'messageSenderUser':
          final userId = sender?.int64('user_id');
          if (userId == null) return null;
          final user = await TdClient.shared.queryForSlot({
            '@type': 'getUser',
            'user_id': userId,
          }, slot);
          final name = TDParse.userName(user).trim();
          return name.isEmpty ? null : name;
        case 'messageSenderChat':
          final chatId = sender?.int64('chat_id');
          if (chatId == null) return null;
          final chat = await TdClient.shared.queryForSlot({
            '@type': 'getChat',
            'chat_id': chatId,
          }, slot);
          final name = chat.str('title')?.trim();
          return name == null || name.isEmpty ? null : name;
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _senderName(ChatMessage message, {int? accountSlot}) async {
    final slot = accountSlot ?? TdClient.shared.activeSlot;
    final senderId = message.senderId;
    if (senderId == null) {
      final title = message.senderTitle?.trim();
      return title != null && title.isNotEmpty ? title : null;
    }
    try {
      if (senderId > 0) {
        final user = await TdClient.shared.queryForSlot({
          '@type': 'getUser',
          'user_id': senderId,
        }, slot);
        final name = TDParse.userName(user).trim();
        return name.isEmpty ? null : name;
      }
      final chat = await TdClient.shared.queryForSlot({
        '@type': 'getChat',
        'chat_id': senderId,
      }, slot);
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
      await _sendThreadReply(target, text, accountSlot: post.accountSlot);
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
    String text, {
    int? accountSlot,
  }) async {
    final slot = accountSlot ?? TdClient.shared.activeSlot;
    final content = {
      '@type': 'inputMessageText',
      'text': {'@type': 'formattedText', 'text': text},
    };
    try {
      await TdClient.shared.queryForSlot({
        '@type': 'sendMessage',
        'chat_id': target.chatId,
        'topic_id': {
          '@type': 'messageTopicThread',
          'message_thread_id': target.messageThreadId,
        },
        'input_message_content': content,
      }, slot);
    } catch (_) {
      await TdClient.shared.queryForSlot({
        '@type': 'sendMessage',
        'chat_id': target.chatId,
        'reply_to': {
          '@type': 'inputMessageReplyToMessage',
          'message_id': target.messageThreadId,
        },
        'input_message_content': content,
      }, slot);
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
      _loadedSinceByChannel.remove(channel.id);
      _postsByChannel.remove(channel.id);
    }
    _invalidateFeed();
    _loadChannelPosts();
  }

  /// Telegram's profile color for the signed-in user, or their name color when
  /// no profile color is set. A single channel keeps its photo background.
  List<Color>? _profileHeaderColors(BuildContext context) {
    if (_scopedChannel != null) return null;
    final client = TdClient.shared;
    return profileHeaderColors(
          profileAccentColorId: _meProfileAccentColorId,
          accentColorId: _meAccentColorId >= 0
              ? _meAccentColorId
              : (_meUserId ?? 0) % 7,
          dark: Theme.of(context).brightness == Brightness.dark,
          profileAccentColors: client.latestProfileAccentColorsUpdate,
          accentColors: client.latestAccentColorsUpdate,
        ) ??
        [AppTheme.brand];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final posts = _posts;
    final useDesktopLayout = isDesktopTargetPlatform();
    final scoped = _scopedChannel;
    return Material(
      color: c.groupedBackground,
      child: Column(
        children: [
          NavHeader(
            title: scoped?.title ?? widget.title.l10n(context),
            onBack: widget.isRootTab ? null : () => Navigator.of(context).pop(),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Muting filters which channels merge; one channel has none.
                if (scoped == null) ...[
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
                ],
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
          // A channel's own feed is headed by the channel, like a profile.
          final scoped = _scopedChannel;
          final composer = _MomentsComposerHeader(
            name: scoped?.title ?? _meName,
            photo: scoped == null ? _mePhoto : scoped.photo,
            backgroundColor: AppTheme.brand.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.25
                  : 0.13,
            ),
            profileColors: _profileHeaderColors(context),
            profileIconId: scoped == null ? _meProfileIconId : 0,
            emojiStatusId: scoped == null ? _meEmojiStatusId : 0,
            isPremium: scoped == null && _meIsPremium,
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
        _noteBuiltPost(i - 1);
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
    _sub = TdClient.shared.updatesOf('updateChatActiveStories').listen(_handle);
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

/// The discussion thread holding [post]'s comments, or null when TDLib
/// reports none.
Future<ChannelPostThreadTarget?> _fetchChannelPostThreadTarget(
  ChannelPost post,
) async {
  final thread = await TdClient.shared.queryForSlot({
    '@type': 'getMessageThread',
    'chat_id': post.channel.id,
    'message_id': post.message.id,
  }, post.accountSlot);
  final chatId = thread.int64('chat_id');
  final threadId = thread.int64('message_thread_id');
  if (chatId == null || threadId == null || threadId == 0) return null;
  return ChannelPostThreadTarget(chatId: chatId, messageThreadId: threadId);
}
