//
//  chat_list_view.dart
//
//  The 消息 tab: a custom reference header (avatar → profile drawer, name +
//  online, trailing "+") over a search pill and the chat list. Rows use a custom
//  left-swipe that reveals flush, full-height action blocks (置顶 / 标为未读 /
//  删除), matching the reference rather than the rounded native swipe. The "+"
//  opens a dropdown of create actions. Port of the Swift `ChatListView`.
//

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../app/adaptive_split_layout.dart';
import '../app/app_navigator.dart';
import '../app/bottom_bar_layout.dart';
import '../app/desktop_chat_list_title_bar_anchors.dart';
import '../app/desktop_chat_window.dart';
import '../app/horizontal_safe_viewport.dart';
import '../app/ipad_window_chrome.dart';
import '../auth/account_store.dart';
import '../auth/auth_manager.dart';
import '../chat/chat_picker_view.dart';
import '../chat/chat_view.dart';
import '../chat/custom_emoji.dart';
import '../chat/link_handler.dart';
import '../communities/community_models.dart';
import '../communities/community_view.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/app_press_ripple.dart';
import '../components/chat_folder_icons.dart';
import '../components/drawer_controller.dart' as dc;
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../contacts/add_people_view.dart';
import '../contacts/create_group_view.dart';
import '../platform/adaptive_platform.dart' show isTouchTargetPlatform;
import '../profile/emoji_status_picker.dart';
import '../security/local_app_lock_controller.dart';
import '../settings/chat_folder_management_view.dart';
import '../settings/chat_folder_service.dart';
import '../settings/edit_field_view.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'archived_chats_view.dart';
import 'chat_delete_dialog.dart';
import 'chat_delete_policy.dart';
import 'chat_folder_tab_menu.dart';
import 'chat_folder_tag_controller.dart';
import 'chat_list_preview.dart';
import 'chat_list_view_model.dart';
import 'chat_removal_actions.dart';
import 'chat_row_metrics.dart';
import 'chat_row_view.dart';
import 'filtered_chats_view.dart';
import 'qr_scanner_view.dart';
import 'search_view.dart';

class ChatListController extends ChangeNotifier {
  final sideFolders = ValueNotifier<Widget?>(null);
  Object? _sideFoldersOwner;
  bool _disposed = false;

  void publishSideFolders(Object owner, Widget? child) {
    if (_disposed) return;
    _sideFoldersOwner = owner;
    sideFolders.value = child;
  }

  void clearSideFolders(Object owner) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && identical(owner, _sideFoldersOwner)) {
        sideFolders.value = null;
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    sideFolders.dispose();
    super.dispose();
  }

  int _scrollToFirstUnreadRequests = 0;
  int _toggleFirstUnreadRequests = 0;
  int _markAllReadRequests = 0;
  int _newChatRequests = 0;
  int _focusSearchRequests = 0;
  bool _toggleRequestMayHaveUnread = false;
  int get scrollToFirstUnreadRequests => _scrollToFirstUnreadRequests;
  int get toggleFirstUnreadRequests => _toggleFirstUnreadRequests;
  int get markAllReadRequests => _markAllReadRequests;
  int get newChatRequests => _newChatRequests;
  int get focusSearchRequests => _focusSearchRequests;
  bool get toggleRequestMayHaveUnread => _toggleRequestMayHaveUnread;

  void scrollToFirstUnread() {
    _scrollToFirstUnreadRequests++;
    notifyListeners();
  }

  void toggleFirstUnreadOrTop({required bool mayHaveUnread}) {
    _toggleRequestMayHaveUnread = mayHaveUnread;
    _toggleFirstUnreadRequests++;
    notifyListeners();
  }

  void markAllRead() {
    _markAllReadRequests++;
    notifyListeners();
  }

  void openNewChat() {
    _newChatRequests++;
    notifyListeners();
  }

  void focusSearch() {
    _focusSearchRequests++;
    notifyListeners();
  }
}

class ChatFolderRail extends StatelessWidget {
  const ChatFolderRail({
    super.key,
    required this.filters,
    required this.selectedFolderId,
    this.onSelect,
    this.keyForFolder,
    this.onMenu,
    this.highlights = const {},
    this.showUnreadBadges = false,
    this.badgeOverflowMode = UnreadBadgeOverflowMode.capped,
  });
  final List<ChatFilterOption> filters;
  final int? selectedFolderId;
  final ValueChanged<ChatFilterOption>? onSelect;
  final Key? Function(int? folderId)? keyForFolder;

  /// Opens the folder's command sheet. A secondary click on the row reaches it
  /// on desktop; a primary click still selects the folder.
  final ValueChanged<ChatFilterOption>? onMenu;

  /// Live page-transition highlights; omitted for a settled folder rail.
  final Map<int?, double> highlights;

  /// Whether folder labels carry their unread-chat count.
  final bool showUnreadBadges;

  /// Formats the badge count; capped by default like every other unread
  /// badge until the user asks for exact numbers.
  final UnreadBadgeOverflowMode badgeOverflowMode;

  double _highlight(ChatFilterOption filter) =>
      highlights[filter.folderId] ??
      (filter.folderId == selectedFolderId ? 1 : 0);
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final showBadges = showUnreadBadges;
    return ListView(
      key: const PageStorageKey('side-chat-folders'),
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        for (final filter in filters)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapDown: onMenu == null || !isDesktopTargetPlatform()
                ? null
                : (_) => onMenu!(filter),
            child: _FolderNameHint(
              key: ValueKey((filter.folderId, filter.title.l10n(context))),
              message: filter.title.l10n(context),
              hintKey: ValueKey(
                'side-folder-name-tooltip-${filter.folderId ?? 'all'}',
              ),
              child: AppInteractiveSurface(
                key: keyForFolder?.call(filter.folderId),
                semanticLabel: filter.title.l10n(context),
                selected: filter.folderId == selectedFolderId,
                borderRadius: BorderRadius.circular(AppRadius.control),
                onTap: () => onSelect?.call(filter),
                child: Container(
                  key: ValueKey('side-folder-${filter.folderId ?? 'all'}'),
                  constraints: const BoxConstraints(minHeight: 56),
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 2,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    color: c.linkBlue.withValues(
                      alpha: 0.10 * _highlight(filter),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ChatFolderIcon(
                        filter.isAll ? 'All' : filter.iconName,
                        size: 22,
                        color: Color.lerp(
                          c.textSecondary,
                          c.linkBlue,
                          _highlight(filter),
                        )!,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              filter.title.l10n(context),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.15,
                                fontWeight: _highlight(filter) >= 0.5
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: Color.lerp(
                                  c.textSecondary,
                                  c.linkBlue,
                                  _highlight(filter),
                                ),
                              ),
                            ),
                          ),
                          if (showBadges &&
                              !filter.isAll &&
                              filter.unreadChatCount > 0) ...[
                            const SizedBox(width: 3),
                            Flexible(
                              child: FolderUnreadBadge(
                                label: badgeOverflowMode.format(
                                  filter.unreadChatCount,
                                ),
                                accent: filter.hasUnmutedUnread,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The rail's full-name hover label uses owned styling and no touch gesture.
class _FolderNameHint extends StatefulWidget {
  const _FolderNameHint({
    super.key,
    required this.message,
    required this.hintKey,
    required this.child,
  });

  final String message;
  final Key hintKey;
  final Widget child;

  @override
  State<_FolderNameHint> createState() => _FolderNameHintState();
}

class _FolderNameHintState extends State<_FolderNameHint> {
  final _overlay = OverlayPortalController();
  Timer? _timer;

  void _hide() {
    _timer?.cancel();
    _timer = null;
    _overlay.hide();
  }

  void _enter() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 450), () {
      _timer = null;
      if (mounted) _overlay.show();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OverlayPortal.overlayChildLayoutBuilder(
    controller: _overlay,
    overlayChildBuilder: (context, info) {
      final anchor = MatrixUtils.transformRect(
        info.childPaintTransform,
        Offset.zero & info.childSize,
      );
      if (!anchor.overlaps(Offset.zero & info.overlaySize)) {
        return const SizedBox.shrink();
      }
      final c = context.colors;
      return IgnorePointer(
        child: ExcludeSemantics(
          // AppInteractiveSurface already exposes the complete folder name.
          child: CustomSingleChildLayout(
            delegate: _FolderNameHintLayout(anchor),
            child: Container(
              key: widget.hintKey,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: c.panelBackground,
                border: Border.all(color: c.divider),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Text(
                widget.message,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 12,
                  height: 1.2,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      );
    },
    child: MouseRegion(
      onEnter: (_) => _enter(),
      onExit: (_) => _hide(),
      child: Listener(
        onPointerDown: (_) => _hide(),
        onPointerSignal: (_) => _hide(),
        child: widget.child,
      ),
    ),
  );
}

class _FolderNameHintLayout extends SingleChildLayoutDelegate {
  const _FolderNameHintLayout(this.anchor);
  final Rect anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(
          math.min(320, math.max(0, constraints.maxWidth - 16)),
          math.max(0, constraints.maxHeight - 16),
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxX = math.max(0.0, size.width - childSize.width);
    final maxY = math.max(0.0, size.height - childSize.height);
    final marginX = math.min(8.0, maxX / 2);
    final marginY = math.min(8.0, maxY / 2);
    final right = anchor.right + 6;
    final left = right + childSize.width <= size.width - 8
        ? right
        : anchor.left - childSize.width - 6;
    return Offset(
      left.clamp(marginX, maxX - marginX),
      (anchor.center.dy - childSize.height / 2).clamp(marginY, maxY - marginY),
    );
  }

  @override
  bool shouldRelayout(_FolderNameHintLayout oldDelegate) =>
      anchor != oldDelegate.anchor;
}

class ChatListSelection {
  const ChatListSelection({
    required this.chatId,
    required this.title,
    this.chat,
    this.resolvedKind,
    this.initialMessageId,
    this.forumTopicId,
    this.composerFocusRequestId = 0,
  });

  ChatListSelection.fromChat(
    ChatSummary chat, {
    this.composerFocusRequestId = 0,
  }) : chatId = chat.id,
       title = chat.title,
       chat = chat,
       resolvedKind = chat.kind,
       initialMessageId = null,
       forumTopicId = null;

  final int chatId;
  final String title;
  final ChatSummary? chat;
  final ChatKind? resolvedKind;
  final int? initialMessageId;

  /// The forum topic shown as an ordinary transcript when topics are folded
  /// into the group chat; null shows the whole chat.
  final int? forumTopicId;
  final int composerFocusRequestId;

  ChatKind? get kind => chat?.kind ?? resolvedKind;
  bool get isForum => chat?.isForum ?? false;
  bool get supportsTopics => chat?.supportsTopics ?? false;

  ChatListSelection withResolvedKind(ChatKind kind) => ChatListSelection(
    chatId: chatId,
    title: title,
    chat: chat,
    resolvedKind: kind,
    initialMessageId: initialMessageId,
    forumTopicId: forumTopicId,
    composerFocusRequestId: composerFocusRequestId,
  );

  /// Whether [other] would land on the transcript this selection already
  /// shows — same conversation, same topic, same jump target, and no fresh
  /// composer-focus request that needs its own build.
  ///
  /// A caller uses this to decide that tapping the row means "go to the newest
  /// message" rather than "open something else".
  bool showsSameTranscript(ChatListSelection other) =>
      chatId == other.chatId &&
      forumTopicId == other.forumTopicId &&
      initialMessageId == other.initialMessageId &&
      composerFocusRequestId == other.composerFocusRequestId;

  ChatListSelection withForumTopic(int? topicId) => ChatListSelection(
    chatId: chatId,
    title: title,
    chat: chat,
    resolvedKind: resolvedKind,
    forumTopicId: topicId,
    composerFocusRequestId: composerFocusRequestId,
  );
}

/// Keeps the active conversation visually anchored in split layouts.
///
/// The subtle wash composes the user-selected brand color over the row's
/// current themed surface. The short leading rail stays crisp in both light
/// and dark/custom themes without changing the row's hit testing.
class ChatListSelectionHighlight extends StatelessWidget {
  const ChatListSelectionHighlight({
    super.key,
    required this.selected,
    required this.child,
  });

  static const tintKey = ValueKey('chat-list-selected-tint');
  static const railKey = ValueKey('chat-list-selected-rail');
  static const semanticsKey = ValueKey('chat-list-selected-semantics');

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!selected) return child;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brand = AppTheme.brand;
    return Semantics(
      key: semanticsKey,
      container: true,
      selected: true,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                key: tintKey,
                color: brand.withValues(alpha: isDark ? 0.13 : 0.08),
              ),
            ),
          ),
          PositionedDirectional(
            start: 0,
            top: AppSpacing.sm,
            bottom: AppSpacing.sm,
            child: IgnorePointer(
              child: Container(
                key: railKey,
                width: 3,
                decoration: BoxDecoration(
                  color: brand,
                  borderRadius: const BorderRadiusDirectional.horizontal(
                    end: Radius.circular(2),
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

/// Live archive-list data handed to the adaptive shell when Archived Chats
/// should replace only the list pane.
///
/// The chat list remains mounted behind that pane, so [chatsProvider] and
/// [updates] continue to expose current archive contents while it is open.
class ArchivedChatListSelection {
  const ArchivedChatListSelection({
    required this.chatsProvider,
    required this.updates,
    required this.onClearUnread,
    this.onUnarchive,
  });

  final List<ChatSummary> Function() chatsProvider;
  final Listenable updates;
  final ValueChanged<ChatSummary> onClearUnread;
  final ValueChanged<ChatSummary>? onUnarchive;
}

bool chatListPreviewSupportsQuickReply(ChatSummary chat) =>
    !chat.supportsTopics &&
    switch (chat.kind) {
      ChatKind.privateChat ||
      ChatKind.group ||
      ChatKind.bot ||
      ChatKind.secret => true,
      ChatKind.channel || ChatKind.unknown => false,
    };

/// Returns the exact leading offset for a chat-list item.
///
/// Chat rows do not include a separator in their layout, so even a fractional
/// per-row adjustment accumulates into a visible error for targets farther
/// down the list.
double chatListItemScrollOffset({
  required int itemIndex,
  required double rowHeight,
  required double maxScrollExtent,
  double leadingExtent = 0,
}) => math.min(leadingExtent + itemIndex * rowHeight, maxScrollExtent);

/// Keeps the pull-down archive slot after the search row when search is shown.
int chatListPullDownArchiveItemIndex({required bool showSearch}) =>
    showSearch ? 1 : 0;

/// Keeps the touch-first pull-down archive interaction on mobile while making
/// the same preference explicitly reachable with a mouse on native desktop.
ArchivedChatsDisplayMode effectiveChatListArchiveDisplayMode(
  ArchivedChatsDisplayMode requested, {
  TargetPlatform? platform,
  bool isWeb = kIsWeb,
}) => requested.effectiveForPlatform(platform: platform, isWeb: isWeb);

/// Returns the distance that leading chat-list content must move up to cancel
/// the viewport's native top overscroll in the same frame.
double chatListTopOverscrollOffset(
  double scrollPixels, {
  double minScrollExtent = 0,
}) => math.max(0.0, minScrollExtent - scrollPixels).toDouble();

/// Whether the current pull has crossed the archive reveal threshold.
bool chatListShouldRevealPullDownArchive({
  required double pullOffset,
  required double rowHeight,
}) => pullOffset >= rowHeight * 0.45;

/// Whether forward scrolling has moved far enough to hide the archive row.
bool chatListShouldHidePullDownArchive({
  required double scrollPixels,
  required double minScrollExtent,
  required double rowHeight,
}) => scrollPixels - minScrollExtent > rowHeight * 0.5;

/// Keeps leading pull-down content visually fixed while the surrounding list
/// uses bouncing scroll physics.
class ChatListTopOverscrollPin extends StatelessWidget {
  const ChatListTopOverscrollPin({
    super.key,
    required this.controller,
    required this.child,
    this.enabled = true,
  });

  final ScrollController controller;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        final positions = controller.positions;
        final position = positions.length == 1 ? positions.single : null;
        final pullOffset = position != null && position.hasContentDimensions
            ? chatListTopOverscrollOffset(
                position.pixels,
                minScrollExtent: position.minScrollExtent,
              )
            : 0.0;
        return Transform.translate(
          offset: Offset(0, -pullOffset),
          child: child,
        );
      },
    );
  }
}

/// Animates the pull-down archive row without letting viewport overscroll move
/// the row's painted position.
class ChatListPullDownArchiveSlot extends StatelessWidget {
  const ChatListPullDownArchiveSlot({
    super.key,
    required this.controller,
    required this.rowHeight,
    required this.visible,
    required this.child,
    this.duration = const Duration(milliseconds: 180),
  });

  final ScrollController controller;
  final double rowHeight;
  final bool visible;
  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return ChatListTopOverscrollPin(
      controller: controller,
      child: AnimatedSize(
        duration: duration,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: visible
            ? SizedBox(height: rowHeight, child: child)
            : const SizedBox(width: double.infinity),
      ),
    );
  }
}

enum ChatListSwipeAction { none, switchFolders, switchAccounts }

@visibleForTesting
enum ChatListConnectionStatus { online, connecting, disconnected }

@visibleForTesting
ChatListConnectionStatus chatListConnectionStatusForTdState(String? stateType) {
  return switch (stateType) {
    'connectionStateReady' ||
    'connectionStateUpdating' => ChatListConnectionStatus.online,
    'connectionStateWaitingForNetwork' => ChatListConnectionStatus.disconnected,
    _ => ChatListConnectionStatus.connecting,
  };
}

@visibleForTesting
class ChatListConnectionStatusView extends StatelessWidget {
  const ChatListConnectionStatusView({super.key, required this.status});

  static const indicatorKey = ValueKey('chat-list-connection-indicator');
  static const labelKey = ValueKey('chat-list-connection-label');

  final ChatListConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = switch (status) {
      ChatListConnectionStatus.online => AppStrings.t(
        AppStringKeys.presenceOnline,
      ),
      ChatListConnectionStatus.connecting => AppStrings.t(
        AppStringKeys.presenceConnecting,
      ),
      ChatListConnectionStatus.disconnected => AppStrings.t(
        AppStringKeys.presenceDisconnected,
      ),
    };
    final muted = status == ChatListConnectionStatus.disconnected;

    return Semantics(
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (status == ChatListConnectionStatus.connecting)
              SizedBox(
                key: indicatorKey,
                width: AppMetric.onlineDot + 2,
                height: AppMetric.onlineDot + 2,
                child: CircularProgressIndicator(
                  strokeWidth: 1.4,
                  color: c.textSecondary,
                  backgroundColor: c.textTertiary.withValues(alpha: 0.22),
                ),
              )
            else
              Container(
                key: indicatorKey,
                width: AppMetric.onlineDot,
                height: AppMetric.onlineDot,
                decoration: BoxDecoration(
                  color: status == ChatListConnectionStatus.online
                      ? AppTheme.onlineDot
                      : c.textTertiary,
                  shape: BoxShape.circle,
                ),
              ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              key: labelKey,
              style: TextStyle(
                fontSize: AppTextSize.tiny,
                color: muted ? c.textTertiary : c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatListSwipeDecision {
  const ChatListSwipeDecision(this.action, this.horizontalDelta);

  static const none = ChatListSwipeDecision(ChatListSwipeAction.none, 0);

  final ChatListSwipeAction action;
  final double horizontalDelta;
}

ChatListSwipeDecision chatListSwipeDecision({
  required ChatListSwipeMode mode,
  required int peakPointerCount,
  required List<Offset> pointerDeltas,
  double distanceThreshold = 64,
  double individualDistanceThreshold = 24,
}) {
  final action = switch ((mode, peakPointerCount)) {
    (ChatListSwipeMode.chatActions, 2) => ChatListSwipeAction.switchFolders,
    (ChatListSwipeMode.chatActions, 3) => ChatListSwipeAction.switchAccounts,
    (ChatListSwipeMode.switchFolders, 1) => ChatListSwipeAction.switchFolders,
    (ChatListSwipeMode.switchFolders, 3) => ChatListSwipeAction.switchAccounts,
    _ => ChatListSwipeAction.none,
  };
  if (action == ChatListSwipeAction.none ||
      pointerDeltas.length != peakPointerCount ||
      pointerDeltas.isEmpty) {
    return ChatListSwipeDecision.none;
  }
  final direction = pointerDeltas.first.dx.sign;
  if (direction == 0 ||
      pointerDeltas.any(
        (delta) =>
            delta.dx.sign != direction ||
            delta.dx.abs() < individualDistanceThreshold,
      )) {
    return ChatListSwipeDecision.none;
  }
  final centroidDelta =
      pointerDeltas.reduce((a, b) => a + b) / pointerDeltas.length.toDouble();
  if (centroidDelta.dx.abs() < distanceThreshold ||
      centroidDelta.dx.abs() < centroidDelta.dy.abs() * 1.25) {
    return ChatListSwipeDecision.none;
  }
  return ChatListSwipeDecision(action, centroidDelta.dx);
}

bool chatListRowSwipeActionsEnabled({
  required ChatListSwipeMode mode,
  required bool multiTouchActive,
}) => mode == ChatListSwipeMode.chatActions && !multiTouchActive;

/// Travel that arms the live folder drag. Matching the framework's touch slop
/// means the list only starts following once a tap has already been ruled out,
/// and it is the same distance at which a vertical drag would claim the scroll.
const double chatListFolderDragActivation = kTouchSlop;

/// Where the list sits for a given finger travel. Inside the folder list the
/// list tracks the finger one to one; past the first or last folder it rubber
/// bands towards a limit so the edge is felt rather than dead.
double chatListFolderDragOffset({
  required double travel,
  required double width,
  required bool hasNeighbour,
}) {
  if (width <= 0) return 0;
  if (hasNeighbour) return travel.clamp(-width, width);
  final limit = width * 0.2;
  final damped = limit * (1 - 1 / (travel.abs() / limit + 1));
  return travel.isNegative ? -damped : damped;
}

/// Whether letting go here lands on the neighbouring folder. A flick commits on
/// its own; a slow drag has to have carried the list most of the way.
bool chatListFolderDragShouldCommit({
  required double offset,
  required double width,
  required double velocity,
  double distanceFraction = 0.3,
  double velocityThreshold = 380,
}) {
  if (width <= 0 || offset == 0) return false;
  final directedVelocity = velocity * (offset.isNegative ? -1 : 1);
  if (directedVelocity < -velocityThreshold) return false;
  return directedVelocity > velocityThreshold ||
      offset.abs() >= width * distanceFraction;
}

/// Holds the live chat list and the folder a swipe is heading for one page
/// apart, and slides the pair together as [offset] changes. [peekSide] is +1
/// when the incoming folder waits to the right.
///
/// Only the two transforms rebuild while the pair travels, so a drag never
/// rebuilds either list.
class ChatListFolderPanes extends StatelessWidget {
  const ChatListFolderPanes({
    super.key,
    required this.offset,
    required this.peekSide,
    required this.width,
    required this.current,
    this.peek,
  });

  static const peekKey = ValueKey('chat-list-folder-peek');

  final ValueListenable<double> offset;
  final double peekSide;
  final double width;
  final Widget current;
  final Widget? peek;

  @override
  Widget build(BuildContext context) {
    final peek = this.peek;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The live list stays first so its element, and with it the shared
          // scroll position, survives the peek coming and going.
          _pane(child: current, adjacent: false),
          if (peek != null) _pane(key: peekKey, child: peek, adjacent: true),
        ],
      ),
    );
  }

  Widget _pane({Key? key, required Widget child, required bool adjacent}) {
    return AnimatedBuilder(
      key: key,
      animation: offset,
      child: child,
      builder: (context, child) => Transform.translate(
        offset: Offset(offset.value + (adjacent ? peekSide * width : 0), 0),
        child: child,
      ),
    );
  }
}

/// Tracks one uninterrupted touch contact sequence and classifies it only
/// after every finger lifts. Deferring dispatch prevents a two-finger folder
/// swipe from also becoming a three-finger account swipe when the third finger
/// lands slightly later.
class ChatListSwipeSession {
  final Map<int, Offset> _activePositions = <int, Offset>{};
  final Map<int, Offset> _candidateOrigins = <int, Offset>{};
  final Map<int, Offset> _finalPositions = <int, Offset>{};
  ChatListSwipeMode? _mode;
  int _peakPointerCount = 0;
  bool _blocked = false;
  bool _hadPointerEnd = false;
  bool _axisResolved = false;
  bool _scrolling = false;

  bool get isActive => _activePositions.isNotEmpty;
  bool get suppressRowSwipes => isActive && _peakPointerCount > 1;

  /// Centroid travel of the fingers that opened this sequence, or null once one
  /// of them has lifted or a new one has joined. Unlike the release decision it
  /// keeps reporting after the gesture has been classified, so the list can
  /// follow the finger back past its start.
  Offset? get liveCentroidDelta {
    if (_blocked ||
        _hadPointerEnd ||
        _peakPointerCount == 0 ||
        _activePositions.length != _peakPointerCount) {
      return null;
    }
    var total = Offset.zero;
    for (final entry in _candidateOrigins.entries) {
      final current = _activePositions[entry.key];
      if (current == null) return null;
      total += current - entry.value;
    }
    return total / _peakPointerCount.toDouble();
  }

  /// Classifies the gesture while the fingers are still down, using a short
  /// activation distance so the list starts moving with them.
  ChatListSwipeDecision liveDecision(ChatListSwipeMode currentMode) {
    if (_mode != currentMode || _scrolling || liveCentroidDelta == null) {
      return ChatListSwipeDecision.none;
    }
    // A non-null centroid guarantees every origin still has a finger on it.
    final deltas = [
      for (final entry in _candidateOrigins.entries)
        _activePositions[entry.key]! - entry.value,
    ];
    return chatListSwipeDecision(
      mode: currentMode,
      peakPointerCount: _peakPointerCount,
      pointerDeltas: deltas,
      distanceThreshold: chatListFolderDragActivation,
      individualDistanceThreshold: chatListFolderDragActivation * 0.5,
    );
  }

  bool pointerDown({
    required int pointer,
    required Offset position,
    required ui.PointerDeviceKind kind,
    required ChatListSwipeMode mode,
  }) {
    if (kind != ui.PointerDeviceKind.touch ||
        _activePositions.containsKey(pointer)) {
      return false;
    }
    if (_activePositions.isEmpty) {
      _reset();
      _mode = mode;
    } else if (_hadPointerEnd || _mode != mode) {
      _blocked = true;
    }
    _activePositions[pointer] = position;
    if (_activePositions.length > _peakPointerCount) {
      _peakPointerCount = _activePositions.length;
      _candidateOrigins
        ..clear()
        ..addAll(_activePositions);
      _finalPositions.clear();
      _axisResolved = false;
      _scrolling = false;
    }
    if (_peakPointerCount > 3) _blocked = true;
    return true;
  }

  void pointerMove({required int pointer, required Offset position}) {
    if (!_activePositions.containsKey(pointer)) return;
    _activePositions[pointer] = position;
    if (_axisResolved) return;
    // Whichever axis clears the activation distance first owns the gesture, so
    // a list already being scrolled cannot be turned sideways halfway through.
    final travel = liveCentroidDelta;
    if (travel == null) return;
    if (travel.dx.abs() < chatListFolderDragActivation &&
        travel.dy.abs() < chatListFolderDragActivation) {
      return;
    }
    _axisResolved = true;
    _scrolling = travel.dy.abs() > travel.dx.abs();
  }

  ChatListSwipeDecision? pointerEnd({
    required int pointer,
    required Offset position,
    required ChatListSwipeMode currentMode,
    bool canceled = false,
  }) {
    if (!_activePositions.containsKey(pointer)) return null;
    _activePositions[pointer] = position;
    _finalPositions[pointer] = position;
    _activePositions.remove(pointer);
    _hadPointerEnd = true;
    if (canceled) _blocked = true;
    if (_activePositions.isNotEmpty) return null;

    final deltas = <Offset>[];
    for (final entry in _candidateOrigins.entries) {
      final finalPosition = _finalPositions[entry.key];
      if (finalPosition == null) {
        _blocked = true;
        break;
      }
      deltas.add(finalPosition - entry.value);
    }
    final decision = !_blocked && !_scrolling && _mode == currentMode
        ? chatListSwipeDecision(
            mode: currentMode,
            peakPointerCount: _peakPointerCount,
            pointerDeltas: deltas,
          )
        : ChatListSwipeDecision.none;
    _reset();
    return decision;
  }

  void _reset() {
    _activePositions.clear();
    _candidateOrigins.clear();
    _finalPositions.clear();
    _mode = null;
    _peakPointerCount = 0;
    _blocked = false;
    _hadPointerEnd = false;
    _axisResolved = false;
    _scrolling = false;
  }
}

Set<ui.PointerDeviceKind> chatFolderTabDragDevices(
  Set<ui.PointerDeviceKind> inherited,
) => {...inherited, ui.PointerDeviceKind.mouse};

extension on Widget {
  Widget _withChatFolderMouseDrag(BuildContext context) {
    final inheritedScrollBehavior = ScrollConfiguration.of(context);
    return ScrollConfiguration(
      behavior: inheritedScrollBehavior.copyWith(
        dragDevices: chatFolderTabDragDevices(
          inheritedScrollBehavior.dragDevices,
        ),
      ),
      child: this,
    );
  }
}

class CommunityListSelection {
  const CommunityListSelection({
    required this.community,
    required this.chats,
    required this.viewableChats,
    required this.onCollapsedChanged,
    this.updates,
    this.chatsProvider,
    this.viewableChatsProvider,
  });

  final CommunitySummary community;
  final List<ChatSummary> chats;
  final List<ChatSummary> viewableChats;
  final ValueChanged<bool> onCollapsedChanged;
  final Listenable? updates;
  final List<ChatSummary> Function()? chatsProvider;
  final List<ChatSummary> Function()? viewableChatsProvider;
}

class ChatListView extends StatefulWidget {
  const ChatListView({
    super.key,
    this.controller,
    this.onChatSelected,
    this.onCommunitySelected,
    this.onOpenArchived,
    this.onOpenChatInSeparateWindow,
    this.desktopSidebar = false,
    this.selectedChatId,
    this.selectedCommunityId,
  });

  final ChatListController? controller;
  final ValueChanged<ChatListSelection>? onChatSelected;
  final ValueChanged<CommunityListSelection>? onCommunitySelected;
  final ValueChanged<ArchivedChatListSelection>? onOpenArchived;
  final Future<void> Function(ChatSummary)? onOpenChatInSeparateWindow;
  final bool desktopSidebar;
  final int? selectedChatId;
  final int? selectedCommunityId;

  @override
  State<ChatListView> createState() => _ChatListViewState();
}

class _ChatListViewState extends State<ChatListView>
    with SingleTickerProviderStateMixin {
  static const _searchPillExtent =
      AppSpacing.md + AppMetric.searchHeight + AppSpacing.sm;

  final ChatListViewModel _model = ChatListViewModel();
  late final ScrollController _scrollController = _newScrollController();

  /// Drives the folder swipe. [_folderDrag] is the live horizontal travel of
  /// the chat list in pixels; it is kept out of `setState` so a drag repaints
  /// two transforms instead of rebuilding the whole tab.
  final ValueNotifier<double> _folderDrag = ValueNotifier<double>(0);
  late final AnimationController _folderSettleController;
  late final Animation<double> _folderSettle;
  ChatFilterOption? _folderPeek;
  double _folderPeekSide = 1;
  bool _folderDragActive = false;
  bool _folderDragHandled = false;
  double _folderDragOrigin = 0;
  double _folderPagerWidth = 0;
  double _folderSettleFrom = 0;
  double _folderSettleTo = 0;
  ChatFilterOption? _folderSettleTarget;
  VelocityTracker? _folderDragVelocity;
  String _meName = AppStrings.t(AppStringKeys.chatMeLabel);
  TdFileRef? _mePhoto;
  int _meStatusId = 0; // current emoji status, shown after the name
  bool _meIsPremium = false;
  int? _meId;
  StreamSubscription? _userSub;
  StreamSubscription? _connectionSub;
  StreamSubscription? _activeSlotSub;
  ChatListConnectionStatus _connectionStatus =
      ChatListConnectionStatus.connecting;
  int? _openSwipeChat;
  bool _showPlusMenu = false;
  bool _showFilterMenu = false;
  int? _pendingScrollToFirstUnreadRequest;
  bool _pendingScrollShouldToggle = false;
  bool _pendingToggleMayHaveUnread = false;
  int _lastHandledScrollToFirstUnreadRequest = 0;
  int _lastHandledToggleFirstUnreadRequest = 0;
  int _lastHandledMarkAllReadRequest = 0;
  int _lastHandledNewChatRequest = 0;
  int _lastHandledFocusSearchRequest = 0;
  int _pendingScrollAttempts = 0;
  bool _toggleUnreadTargetNext = true;
  bool _archiveRevealed = false;
  double _refreshPullDistance = 0;
  bool _isRefreshing = false;
  bool _viewTickerEnabled = true;
  bool _modelDirtyWhileInactive = false;
  bool _reactivationFollowUpPending = false;
  int _lastVisibleRows = 1;
  double? _lastRowWidth;
  final ChatListSwipeSession _chatListSwipeSession = ChatListSwipeSession();
  final ScrollController _folderTabScrollController = ScrollController();
  final Map<int?, GlobalKey> _folderTabKeys = {};
  final Map<int?, GlobalKey> _sideFolderKeys = {};
  bool _foldersInSideRail = false;
  int _nextComposerFocusRequestId = 0;
  OverlayEntry? _desktopChatMenuEntry;
  OverlayEntry? _desktopPlusMenuEntry;

  static const double _refreshPullThreshold = 72;

  ScrollController _newScrollController({double initialScrollOffset = 0}) {
    return ScrollController(initialScrollOffset: initialScrollOffset)
      ..addListener(_onScroll);
  }

  @override
  void initState() {
    super.initState();
    _folderSettleController = AnimationController(
      vsync: this,
      duration: AppMotion.deliberate,
    )..addStatusListener(_onFolderSettleStatus);
    _folderSettle = _folderSettleController.drive(
      CurveTween(curve: AppMotion.standard),
    );
    _folderSettleController.addListener(_onFolderSettleTick);
    _model.onAppear();
    _model.addListener(_onModel);
    widget.controller?.addListener(_onControllerRequest);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onControllerRequest();
    });
    _loadMe();
    // Keep the header's name/status/photo live — TDLib emits updateUser for us
    // when the status or profile changes.
    _userSub = TdClient.shared.updatesOf('updateUser').listen((u) {
      if (u.obj('user')?.int64('id') == _meId) _loadMe();
    });
    _connectionSub = TdClient.shared
        .updatesOf('updateConnectionState')
        .listen(_applyConnectionUpdate);
    _activeSlotSub = TdClient.shared.subscribeActiveSlotChanges().listen((_) {
      _refreshConnectionStatus();
    });
    _refreshConnectionStatus();
  }

  @override
  void didUpdateWidget(covariant ChatListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller?.removeListener(_onControllerRequest);
    widget.controller?.addListener(_onControllerRequest);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    final reactivated = !_viewTickerEnabled && tickerEnabled;
    _viewTickerEnabled = tickerEnabled;
    if (!reactivated ||
        !_modelDirtyWhileInactive ||
        _reactivationFollowUpPending) {
      return;
    }
    // TickerMode.valuesOf registers an inherited-widget dependency, so the flip
    // that brings this list back already rebuilds it in this same frame with
    // everything the model applied while a conversation covered it. Only the
    // work that needs a finished frame is still owed: scheduling a second full
    // rebuild for the next frame put it in the middle of the returning
    // transition, where the list is rasterizing itself again anyway.
    _modelDirtyWhileInactive = false;
    _reactivationFollowUpPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reactivationFollowUpPending = false;
      if (!mounted) return;
      if (!_viewTickerEnabled) {
        // Covered again before the frame ended: keep the follow-up owed so the
        // next reactivation runs it.
        _modelDirtyWhileInactive = true;
        return;
      }
      _showModelNotice();
      _runPendingScrollRequest();
    });
  }

  void _onModel() {
    if (!mounted) return;
    if (!_viewTickerEnabled) {
      _modelDirtyWhileInactive = true;
      return;
    }
    _modelDirtyWhileInactive = false;
    _showModelNotice();
    setState(() {});
    _runPendingScrollRequest();
  }

  void _showModelNotice() {
    final notice = _model.notice;
    if (notice == null || !mounted) return;
    _model.clearNotice();
    showToast(context, notice);
  }

  void _runPendingScrollRequest() {
    if (_pendingScrollToFirstUnreadRequest == null) return;
    _tryScrollToFirstUnread();
  }

  void _onScroll() {
    if (!mounted) return;
    final positions = _scrollController.positions;
    if (positions.length != 1) return;
    final position = positions.single;
    final theme = context.read<ThemeController>();
    final rowHeight = chatListRowExtentFor(
      context,
      listen: false,
      width: _lastRowWidth,
    );
    final archiveMode = effectiveChatListArchiveDisplayMode(
      theme.archivedChatsDisplayMode,
    );
    final archiveEnabled =
        _model.isAllFilter &&
        _model.archived.isNotEmpty &&
        archiveMode == ArchivedChatsDisplayMode.pullDown;
    if (archiveEnabled && position.hasContentDimensions) {
      final pullOffset = chatListTopOverscrollOffset(
        position.pixels,
        minScrollExtent: position.minScrollExtent,
      );
      if (!_archiveRevealed &&
          chatListShouldRevealPullDownArchive(
            pullOffset: pullOffset,
            rowHeight: rowHeight,
          )) {
        setState(() => _archiveRevealed = true);
      } else if (_archiveRevealed &&
          chatListShouldHidePullDownArchive(
            scrollPixels: position.pixels,
            minScrollExtent: position.minScrollExtent,
            rowHeight: rowHeight,
          )) {
        setState(() => _archiveRevealed = false);
      }
    }
    if (position.extentAfter < rowHeight * 8) {
      _model.loadMore();
    }
  }

  @override
  void dispose() {
    widget.controller?.clearSideFolders(this);
    _dismissDesktopChatMenu();
    _dismissDesktopPlusMenu();
    _userSub?.cancel();
    _connectionSub?.cancel();
    _activeSlotSub?.cancel();
    widget.controller?.removeListener(_onControllerRequest);
    _folderSettleController.dispose();
    _folderDrag.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _folderTabScrollController.dispose();
    _model.removeListener(_onModel);
    _model.dispose();
    super.dispose();
  }

  Future<void> _loadMe() async {
    try {
      final me = await TdClient.shared.query({'@type': 'getMe'});
      final name = TDParse.userName(me);
      if (mounted) {
        setState(() {
          if (name.isNotEmpty) _meName = name;
          _mePhoto = TDParse.smallPhoto(me.obj('profile_photo'));
          _meStatusId = TDParse.emojiStatusCustomEmojiId(
            me.obj('emoji_status'),
          );
          _meIsPremium = me.boolean('is_premium') ?? false;
          _meId = me.int64('id');
          _model.meId = _meId;
        });
      }
    } catch (_) {}
  }

  void _applyConnectionUpdate(Map<String, dynamic> update) {
    _setConnectionStatus(
      chatListConnectionStatusForTdState(update.obj('state')?.type),
    );
  }

  void _setConnectionStatus(ChatListConnectionStatus status) {
    if (!mounted || status == _connectionStatus) return;
    setState(() => _connectionStatus = status);
  }

  /// Seeds the header from the last connection state TDLib reported for the
  /// active account.
  ///
  /// `updateConnectionState` is push-only and TDLib sends it just once per
  /// change, so a view that mounts after the account settled would otherwise
  /// have nothing to read. There is no request to ask with: TDLib has no
  /// `getConnectionState`, and `getCurrentState` would serialise the whole
  /// account to answer about one field. An unknown answer stays `connecting` —
  /// never `disconnected`, which would claim a state TDLib never reported.
  void _refreshConnectionStatus() {
    if (!mounted) return;
    final stateType = TdClient.shared.latestConnectionStateUpdate
        ?.obj('state')
        ?.type;
    _setConnectionStatus(
      stateType == null
          ? ChatListConnectionStatus.connecting
          : chatListConnectionStatusForTdState(stateType),
    );
  }

  Future<void> _openChat(ChatSummary chat, {bool focusComposer = false}) async {
    final composerFocusRequestId = focusComposer
        ? ++_nextComposerFocusRequestId
        : 0;
    final onChatSelected = widget.onChatSelected;
    if (onChatSelected != null) {
      onChatSelected(
        ChatListSelection.fromChat(
          chat,
          composerFocusRequestId: composerFocusRequestId,
        ),
      );
      return;
    }
    if (chat.isSavedMessages) {
      unawaited(
        pushAppChatRoute(
          context,
          _chatEntryRoute(
            ChatView(
              chatId: chat.id,
              title: AppStrings.t(AppStringKeys.savedMessages),
              seedMessage: chat.lastChatMessage,
              requestComposerFocusOnReady: focusComposer,
            ),
          ),
        ),
      );
      return;
    }
    if (chat.supportsTopics) {
      // Forum/topic chats always open in the regular chat transcript; the
      // topic feed surface is gone.
      unawaited(
        pushAppChatRoute(
          context,
          _chatEntryRoute(
            ChatView(
              chatId: chat.id,
              title: chat.title,
              seedMessage: chat.lastChatMessage,
              requestComposerFocusOnReady: focusComposer,
            ),
          ),
        ),
      );
      return;
    }
    unawaited(
      pushAppChatRoute(
        context,
        _chatEntryRoute(
          ChatView(
            chatId: chat.id,
            title: chat.title,
            seedMessage: chat.lastChatMessage,
            requestComposerFocusOnReady: focusComposer,
          ),
        ),
      ),
    );
  }

  void _openCommunity(CommunityGroupEntry entry) =>
      _openCommunityHub(entry.community);

  /// Opens the community hub, whether the caller came from the folded
  /// chat-list row or from a member chat's corner badge.
  void _openCommunityHub(CommunitySummary community) {
    if (!context.read<ThemeController>().communitiesEnabled) return;
    final selection = CommunityListSelection(
      community: community,
      chats: _model.chatsInCommunity(community.id),
      viewableChats: _model.viewableChatsInCommunity(community.id),
      onCollapsedChanged: (value) =>
          _model.setCommunityCollapsed(community.id, value),
      updates: _model,
      chatsProvider: () => _model.chatsInCommunity(community.id),
      viewableChatsProvider: () =>
          _model.viewableChatsInCommunity(community.id),
    );
    final onCommunitySelected = widget.onCommunitySelected;
    if (onCommunitySelected != null) {
      onCommunitySelected(selection);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CommunityView(
          community: selection.community,
          chats: selection.chats,
          viewableChats: selection.viewableChats,
          updates: selection.updates,
          chatsProvider: selection.chatsProvider,
          viewableChatsProvider: selection.viewableChatsProvider,
          onCollapsedChanged: selection.onCollapsedChanged,
        ),
      ),
    );
  }

  void _showAddMenu() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AddPeopleView()));
  }

  void _createGroup() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CreateGroupView()));
  }

  Future<void> _createChannel() async {
    final title = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const EditFieldView(
          title: AppStringKeys.chatListCreateChannel,
          initial: '',
          hint: AppStringKeys.chatListChannelName,
        ),
      ),
    );
    if (title == null || title.isEmpty) return;
    try {
      final chat = await TdClient.shared.query({
        '@type': 'createNewSupergroupChat',
        'title': title,
        'is_channel': true,
        'description': '',
      });
      final id = chat.int64('id') ?? chat.int64('chat_id');
      if (!mounted || id == null) return;
      final selection = ChatListSelection(chatId: id, title: title);
      if (widget.onChatSelected != null) {
        widget.onChatSelected!(selection);
        return;
      }
      unawaited(
        pushAppChatRoute(
          context,
          _chatEntryRoute(ChatView(chatId: id, title: title)),
        ),
      );
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.chatListCreateChannelFailed);
      }
    }
  }

  void _selectPlusMenuItem(String label) {
    _dismissDesktopPlusMenu();
    setState(() => _showPlusMenu = false);
    switch (label) {
      case AppStringKeys.chatListScanQrCode:
        _openQrScanner();
      case AppStringKeys.chatListCreateGroup:
        _createGroup();
      case AppStringKeys.chatListCreateChannel:
        _createChannel();
      case AppStringKeys.chatListAddFriendOrGroup:
        _showAddMenu();
      case AppStringKeys.communityTitle:
        _openCommunityDirectory();
    }
  }

  void _openPlusMenu() {
    _dismissDesktopPlusMenu();
    if (!widget.desktopSidebar) {
      setState(() {
        _showPlusMenu = true;
        _showFilterMenu = false;
      });
      return;
    }

    // Without the title bar mounted there is nothing to hang the menu off;
    // fall back to the in-pane menu rather than dropping the tap.
    final globalAnchor = DesktopChatListTitleBarAnchors.addButtonRect();
    if (globalAnchor == null) {
      setState(() {
        _showPlusMenu = true;
        _showFilterMenu = false;
      });
      return;
    }

    setState(() {
      _showPlusMenu = false;
      _showFilterMenu = false;
    });
    final overlay = Overlay.of(context, rootOverlay: true);
    // addButtonRect reports global coordinates but Positioned lays out in the
    // overlay's own space, and the two only coincide when the overlay starts
    // at the window origin.
    final overlayBox = overlay.context.findRenderObject();
    final anchor = overlayBox is RenderBox
        ? Rect.fromPoints(
            overlayBox.globalToLocal(globalAnchor.topLeft),
            overlayBox.globalToLocal(globalAnchor.bottomRight),
          )
        : globalAnchor;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _DesktopTitleBarPlusMenuOverlay(
        anchor: anchor,
        onDismiss: () {
          if (identical(_desktopPlusMenuEntry, entry)) {
            _desktopPlusMenuEntry = null;
          }
          entry.remove();
        },
        child: PlusMenu(
          key: const ValueKey('desktop-title-bar-plus-menu'),
          onSelect: _selectPlusMenuItem,
          showCommunities:
              context.read<ThemeController>().communitiesEnabled &&
              _model.availableCommunities.isNotEmpty,
        ),
      ),
    );
    _desktopPlusMenuEntry = entry;
    overlay.insert(entry);
  }

  void _dismissDesktopPlusMenu() {
    final entry = _desktopPlusMenuEntry;
    _desktopPlusMenuEntry = null;
    entry?.remove();
  }

  void _openCommunityDirectory() {
    if (!context.read<ThemeController>().communitiesEnabled) return;
    final entries = [
      for (final community in _model.availableCommunities)
        CommunityGroupEntry(
          community: community,
          chats: [
            ..._model.chatsInCommunity(community.id),
            ..._model.viewableChatsInCommunity(community.id),
          ],
        ),
    ];
    if (entries.isEmpty) return;
    if (entries.length == 1) {
      _openCommunity(entries.single);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _CommunityDirectoryView(entries: entries, onOpen: _openCommunity),
      ),
    );
  }

  Future<void> _openQrScanner() async {
    final value = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const QrScannerView()));
    if (!mounted || value == null || value.trim().isEmpty) return;
    await openLink(context, value);
  }

  /// Opens the folder's command sheet.
  ///
  /// The "All chats" tab has no folder to edit or extend, so it offers only the
  /// list-wide read and order commands.
  Future<void> _showFolderMenu(ChatFilterOption filter) async {
    final folderId = filter.folderId;
    await showChatFolderActionSheet(
      context: context,
      title: filter.title.l10n(context),
      actions: [
        if (folderId != null)
          ChatFolderMenuAction(
            key: 'edit',
            label: AppStrings.t(AppStringKeys.chatFolderManagementEditFolder),
            icon: HeroAppIcons.pen,
            onSelected: () => unawaited(_editFolder(filter)),
          ),
        if (folderId != null)
          ChatFolderMenuAction(
            key: 'add-chat',
            label: AppStrings.t(AppStringKeys.chatFolderManagementAddChat),
            icon: HeroAppIcons.plus,
            onSelected: () => unawaited(_addChatToFolder(filter)),
          ),
        ChatFolderMenuAction(
          key: 'mark-read',
          label: AppStrings.t(AppStringKeys.chatFolderManagementMarkAllRead),
          icon: HeroAppIcons.check,
          onSelected: () => unawaited(_markFolderRead(filter)),
        ),
        ChatFolderMenuAction(
          key: 'reorder',
          label: AppStrings.t(AppStringKeys.chatFolderManagementReorderFolders),
          icon: HeroAppIcons.bars,
          onSelected: () => unawaited(_reorderFolders()),
        ),
      ],
    );
  }

  /// Opens the full folder editor and writes the returned draft back.
  Future<void> _editFolder(ChatFilterOption filter) async {
    final id = filter.folderId;
    if (id == null) return;
    final client = TdClient.shared;
    final clientId = client.activeClientId;
    final service = ChatFolderService(
      query: (request) => client.queryTo(request, clientId),
    );
    try {
      final raw = await service.getFolder(id);
      if (!mounted || client.activeClientId != clientId) return;
      final original = ChatFolderDraft.fromRaw(raw);
      final tagsEnabled =
          context.read<ChatFolderTagController?>()?.enabled ?? false;
      final edited = await Navigator.of(context, rootNavigator: true)
          .push<ChatFolderDraft>(
            AppPageRoute(
              pageBuilder: (_, _, _) => ChatFolderEditorView(
                initial: original,
                folderId: id,
                service: service,
                tagsEnabled: tagsEnabled,
              ),
            ),
          );
      if (edited == null || !mounted || client.activeClientId != clientId) {
        return;
      }
      await service.edit(id, edited);
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(
            AppStringKeys.chatFolderManagementCouldnTUpdateFolderValue1,
            {'value1': error},
          ),
        );
      }
    }
  }

  /// Adds one picked chat to the folder's included rules.
  ///
  /// The folder is re-read after the picker closes so the merge keeps rules
  /// that changed while the picker was open, and a chat that was explicitly
  /// excluded stops being excluded once it is included.
  Future<void> _addChatToFolder(ChatFilterOption filter) async {
    final id = filter.folderId;
    if (id == null) return;
    final client = TdClient.shared;
    final clientId = client.activeClientId;
    final accountSlot = client.activeSlot;
    final service = ChatFolderService(
      query: (request) => client.queryTo(request, clientId),
    );
    try {
      final picked = await Navigator.of(context).push<ChatSummary>(
        AppPageRoute(
          pageBuilder: (_, _, _) => ChatPickerView(
            title: AppStrings.t(AppStringKeys.chatFolderManagementAddChat),
            accountSlot: accountSlot,
          ),
        ),
      );
      if (picked == null || !mounted || client.activeClientId != clientId) {
        return;
      }
      final raw = await service.getFolder(id);
      if (!mounted || client.activeClientId != clientId) return;
      final draft = ChatFolderDraft.fromRaw(raw);
      final excluded = {...draft.excludedChatIds}..remove(picked.id);
      await service.edit(
        id,
        draft.copyWith(
          includedChatIds: {...draft.includedChatIds, picked.id},
          excludedChatIds: excluded,
        ),
      );
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(
            AppStringKeys.chatFolderManagementCouldnTUpdateFolderValue1,
            {'value1': error},
          ),
        );
      }
    }
  }

  Future<void> _markFolderRead(ChatFilterOption filter) async {
    final id = filter.folderId;
    try {
      if (id == null) {
        // "All chats" is the whole account, not whichever folder happens to be
        // selected: the main list is enumerated through TDLib so chats this
        // view never loaded are cleared too.
        await _model.markAllChatsRead();
      } else {
        await _model.markFolderRead(id);
      }
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(
            AppStringKeys.chatFolderManagementCouldnTMarkAllReadValue1,
            {'value1': error},
          ),
        );
      }
    }
  }

  /// Opens the order sheet with every folder the account currently has.
  Future<void> _reorderFolders() async {
    final client = TdClient.shared;
    final clientId = client.activeClientId;
    final service = ChatFolderService(
      query: (request) => client.queryTo(request, clientId),
    );
    final update = client.latestChatFoldersUpdate;
    try {
      var folders = await service.load(update);
      if (!mounted || client.activeClientId != clientId) return;
      if (folders.isEmpty) {
        // The bootstrap update may not be in the client cache yet; the tab
        // strip already knows the ids and names, and reorder only needs those.
        folders = [
          for (final option in _model.filters)
            if (option.folderId case final int folderId)
              ChatFolderRecord(
                id: folderId,
                title: option.title,
                raw: const <String, dynamic>{},
                hasInviteLinks: false,
              ),
        ];
      }
      if (folders.isEmpty) return;
      await showChatFolderReorderSheet(
        context: context,
        folders: folders,
        mainListPosition: update?.integer('main_chat_list_position') ?? 0,
        service: service,
        // The sheet outlives this surface; a save after the account changed
        // would write the old folder order into the replacement account.
        canSave: () => mounted && client.activeClientId == clientId,
      );
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(
            AppStringKeys.chatFolderManagementCouldnTLoadChatFoldersValue1,
            {'value1': error},
          ),
        );
      }
    }
  }

  void _selectFilter(ChatFilterOption filter) {
    if (!mounted) return;
    setState(() => _showFilterMenu = false);
    _switchToFilter(filter);
  }

  void _switchToFilter(ChatFilterOption filter) {
    if (_folderSettleController.isAnimating) {
      // Already on its way there: let the slide finish instead of restarting
      // it. Anything else in flight lands first, so the next slide starts from
      // a settled page rather than snapping back through zero.
      final pending = _folderSettleTarget;
      if (pending != null && pending.folderId == filter.folderId) return;
      _folderSettleController.stop();
      _finishFolderSettle();
    }
    final currentFolderId = _model.selectedFilter.folderId;
    if (filter.folderId == currentFolderId) return;
    final direction = _folderDirection(currentFolderId, filter.folderId);
    if (_folderPagerWidth <= 0 ||
        _folderDragActive ||
        AppMotion.isReduced(context)) {
      _folderDrag.value = 0;
      _commitFolderSwitch(filter, direction: direction);
      return;
    }
    // A tab tap gets the same slide a drag does, so both ways of changing
    // folders read as the list moving rather than the screen being swapped.
    setState(() {
      _folderPeek = filter;
      _folderPeekSide = direction;
    });
    _model.prefetchFolder(filter.folderId);
    _folderSettleTarget = filter;
    _ensureFolderTabVisible(filter.folderId, direction);
    _startFolderSettle(to: -direction * _folderPagerWidth, velocity: 0);
  }

  /// +1 when [toFolderId] sits after [fromFolderId] in the tab order, so the
  /// incoming list enters from the right.
  double _folderDirection(int? fromFolderId, int? toFolderId) {
    final filters = _model.filters;
    final from = filters.indexWhere((f) => f.folderId == fromFolderId);
    final to = filters.indexWhere((f) => f.folderId == toFolderId);
    if (from < 0 || to < 0) return 1;
    return to > from ? 1 : -1;
  }

  void _commitFolderSwitch(
    ChatFilterOption filter, {
    required double direction,
  }) {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    setState(() {
      _folderPeek = null;
      _openSwipeChat = null;
      _archiveRevealed = false;
      _refreshPullDistance = 0;
    });
    _model.selectFilter(filter);
    _ensureFolderTabVisible(filter.folderId, direction);
  }

  void _startFolderSettle({required double to, required double velocity}) {
    _folderSettleFrom = _folderDrag.value;
    _folderSettleTo = to;
    if (_folderSettleFrom == to) {
      _finishFolderSettle();
      return;
    }
    final distance = (to - _folderSettleFrom).abs();
    final width = math.max(_folderPagerWidth, 1);
    // Follow the release: a fast flick finishes in about the time the finger
    // would have needed to cover what is left.
    final coast = velocity.abs() > 1 ? distance / velocity.abs() * 1000 : null;
    final glide = 110 + 210 * (distance / width);
    _folderSettleController
      ..duration = Duration(
        milliseconds: (coast == null ? glide : math.min(glide, coast))
            .clamp(90, 320)
            .round(),
      )
      ..forward(from: 0);
  }

  void _onFolderSettleTick() {
    _folderDrag.value = ui.lerpDouble(
      _folderSettleFrom,
      _folderSettleTo,
      _folderSettle.value,
    )!;
  }

  void _onFolderSettleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _finishFolderSettle();
  }

  void _finishFolderSettle() {
    if (!mounted) return;
    final target = _folderSettleTarget;
    final direction = _folderPeekSide;
    _folderSettleTarget = null;
    // Dropping the travel and swapping the folder in the same frame hands the
    // peek's position straight to the real list, so nothing jumps on landing.
    _folderDrag.value = 0;
    if (target == null) {
      setState(() => _folderPeek = null);
      _ensureFolderTabVisible(_model.selectedFilter.folderId, -direction);
      return;
    }
    _commitFolderSwitch(target, direction: direction);
  }

  void _ensureFolderTabVisible(int? folderId, double direction) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = (_foldersInSideRail
          ? _sideFolderKeys
          : _folderTabKeys)[folderId];
      final ctx = key?.currentContext;
      if (ctx == null) return;
      final renderBox = ctx.findRenderObject() as RenderBox?;
      if (renderBox == null) return;

      // Scrollable.of asserts rather than returning null, so the row is either
      // inside a scrollable or this is a programming error worth surfacing.
      final scrollableState = Scrollable.of(ctx);
      final viewportBox =
          scrollableState.context.findRenderObject() as RenderBox?;
      if (viewportBox == null) return;

      final tabPos = renderBox.localToGlobal(Offset.zero);
      final viewPos = viewportBox.localToGlobal(Offset.zero);
      final vertical =
          axisDirectionToAxis(scrollableState.axisDirection) == Axis.vertical;
      final tabLeft = vertical ? tabPos.dy : tabPos.dx;
      final tabRight =
          tabLeft + (vertical ? renderBox.size.height : renderBox.size.width);
      final viewLeft = vertical ? viewPos.dy : viewPos.dx;
      final viewRight =
          viewLeft +
          (vertical ? viewportBox.size.height : viewportBox.size.width);

      double? alignment;
      if (direction > 0 && tabRight > viewRight) {
        alignment = 1.0;
      } else if (direction < 0 && tabLeft < viewLeft) {
        alignment = 0.0;
      } else {
        return;
      }

      Scrollable.ensureVisible(
        ctx,
        alignment: alignment,
        duration: AppMotion.duration(
          context,
          const Duration(milliseconds: 250),
        ),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _onControllerRequest() {
    final markAllRequest = widget.controller?.markAllReadRequests ?? 0;
    if (markAllRequest > _lastHandledMarkAllReadRequest) {
      _lastHandledMarkAllReadRequest = markAllRequest;
      _model.markAllRead();
    }

    final newChatRequest = widget.controller?.newChatRequests ?? 0;
    if (newChatRequest > _lastHandledNewChatRequest) {
      _lastHandledNewChatRequest = newChatRequest;
      _openPlusMenu();
    }

    final focusSearchRequest = widget.controller?.focusSearchRequests ?? 0;
    if (focusSearchRequest > _lastHandledFocusSearchRequest) {
      _lastHandledFocusSearchRequest = focusSearchRequest;
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const SearchView()));
    }

    final request = widget.controller?.scrollToFirstUnreadRequests ?? 0;
    if (request > _lastHandledScrollToFirstUnreadRequest) {
      _beginScrollRequest(request, toggle: false, mayHaveUnread: true);
    }

    final toggleRequest = widget.controller?.toggleFirstUnreadRequests ?? 0;
    if (toggleRequest > _lastHandledToggleFirstUnreadRequest) {
      _beginScrollRequest(
        toggleRequest,
        toggle: true,
        mayHaveUnread: widget.controller?.toggleRequestMayHaveUnread ?? false,
      );
    }
  }

  void _beginScrollRequest(
    int request, {
    required bool toggle,
    required bool mayHaveUnread,
  }) {
    _pendingScrollToFirstUnreadRequest = request;
    _pendingScrollShouldToggle = toggle;
    _pendingToggleMayHaveUnread = mayHaveUnread;
    _pendingScrollAttempts = 0;
    _model.selectAllFilter();
    _model.loadMore();
    _tryScrollToFirstUnread();
  }

  void _tryScrollToFirstUnread() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pendingScrollToFirstUnreadRequest == null) return;
      if (!_scrollController.hasClients ||
          !_scrollController.position.hasContentDimensions) {
        _retryScrollToFirstUnread();
        return;
      }
      final firstUnread = _firstUnreadScrollOffset();
      final target = _targetScrollOffsetForRequest(firstUnread);
      if (target == null ||
          (_pendingScrollShouldToggle &&
              _pendingToggleMayHaveUnread &&
              firstUnread == null)) {
        _model.loadMore();
        _retryScrollToFirstUnread();
        return;
      }

      if (_pendingScrollShouldToggle) {
        _lastHandledToggleFirstUnreadRequest =
            _pendingScrollToFirstUnreadRequest!;
        _toggleUnreadTargetNext = firstUnread == null || target == 0;
      } else {
        _lastHandledScrollToFirstUnreadRequest =
            _pendingScrollToFirstUnreadRequest!;
      }
      _pendingScrollToFirstUnreadRequest = null;
      _pendingScrollShouldToggle = false;
      _pendingToggleMayHaveUnread = false;
      _pendingScrollAttempts = 0;
      _animateListTo(target);
    });
  }

  double? _targetScrollOffsetForRequest(double? firstUnread) {
    if (!_pendingScrollShouldToggle) return firstUnread;
    if (firstUnread == null) return 0;
    return _toggleUnreadTargetNext ? firstUnread : 0;
  }

  void _retryScrollToFirstUnread() {
    _pendingScrollAttempts++;
    if (_pendingScrollAttempts > 160) {
      final request = _pendingScrollToFirstUnreadRequest;
      final wasToggle = _pendingScrollShouldToggle;
      _pendingScrollToFirstUnreadRequest = null;
      _pendingScrollShouldToggle = false;
      _pendingToggleMayHaveUnread = false;
      _pendingScrollAttempts = 0;
      if (wasToggle && request != null) {
        _lastHandledToggleFirstUnreadRequest = request;
        _toggleUnreadTargetNext = true;
        _animateListTo(0);
      }
      return;
    }
    Future<void>.delayed(const Duration(milliseconds: 35), () {
      if (mounted) _tryScrollToFirstUnread();
    });
  }

  double? _firstUnreadScrollOffset() {
    final entries = _model.chatListEntries(
      communitiesEnabled: context.read<ThemeController>().communitiesEnabled,
    );
    final entryIndex = entries.indexWhere(
      (entry) => entry.showsUnreadIndicator,
    );
    if (entryIndex < 0) return null;

    final preceding = <double>[
      for (final entry in entries.take(entryIndex)) _entryExtent(entry),
    ];
    if (_model.isAllFilter && _model.filtered.isNotEmpty) {
      preceding.add(
        _summaryExtent(FilteredChatsRow(chats: _model.filtered).summary),
      );
    }
    final archiveMode = effectiveChatListArchiveDisplayMode(
      context.read<ThemeController>().archivedChatsDisplayMode,
    );
    final pullDownArchiveVisible =
        archiveMode == ArchivedChatsDisplayMode.pullDown && _archiveRevealed;
    if (_model.isAllFilter &&
        _model.archived.isNotEmpty &&
        (archiveMode.isInline || pullDownArchiveVisible)) {
      final archiveIndex = pullDownArchiveVisible
          ? 0
          : archiveMode.insertionIndex(
              chatCount: entries.length,
              visibleRows: _lastVisibleRows,
            );
      if (archiveIndex <= entryIndex) preceding.add(_archiveExtent());
    }
    // These builders contain no inter-row Divider/SizedBox. Do not add the
    // former estimated 0.5px: it accumulated drift on long unread jumps.
    return math.min(
      _scrollController.position.maxScrollExtent,
      chatRowCumulativeOffset(
        preceding,
        leadingExtent: _leadingListControlsExtent(
          context.read<ThemeController>(),
        ),
      ),
    );
  }

  double _summaryExtent(
    ChatSummary summary, {
    bool? pinned,
    double trailingWidth = 0,
    double titleAccessoryWidth = 0,
  }) => chatRowMetricsFor(
    context,
    summary,
    listen: false,
    width: _lastRowWidth,
    pinned: pinned,
    trailingWidth: trailingWidth,
    titleAccessoryWidth: titleAccessoryWidth,
  ).extent;

  double _entryExtent(CommunityChatListEntry entry) => switch (entry) {
    CommunityChatEntry(:final chat) => _summaryExtent(
      chat,
      pinned: _model.isPinnedInSelectedList(chat),
      titleAccessoryWidth:
          (chat.kind == ChatKind.secret ? 18 : 0) +
          (chat.peerEmojiStatusId != 0 &&
                  context
                      .read<ThemeController>()
                      .chatListStatusEmojiMode
                      .visible
              ? 21
              : 0),
    ),
    CommunityGroupEntry() => _summaryExtent(
      CommunityChatListRow(entry: entry).summary,
      trailingWidth: isDesktopTargetPlatform() ? 0 : 13,
      titleAccessoryWidth: 22,
    ),
  };

  double _archiveExtent() =>
      _summaryExtent(ArchivedChatsRow(archived: _model.archived).summary);

  void _animateListTo(double target) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final clamped = target.clamp(0.0, position.maxScrollExtent).toDouble();
    final distance = (position.pixels - clamped).abs();
    if (distance < 1) return;
    final duration = Duration(
      milliseconds: (220 + distance * 0.22).clamp(260, 520).round(),
    );
    _scrollController.animateTo(
      clamped,
      duration: duration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    final folderMode = theme.chatFolderDisplayMode;
    final isBot = context.watch<AccountStore?>()?.activeIsBotApi ?? false;
    final tabCount = isBot
        ? 1
        : 1 +
              (theme.showChannelsTab ? 1 : 0) +
              (theme.showContactsTab ? 1 : 0) +
              (theme.showMomentsTab ? 1 : 0);
    final sideFolders =
        widget.controller != null &&
        !kIsWeb &&
        (widget.desktopSidebar ||
            (defaultTargetPlatform == TargetPlatform.iOS &&
                SideNavigationGeometry.of(
                      context,
                    )?.fits(tabCount, SideNavigationGeometry.itemExtent) ==
                    true));
    _foldersInSideRail = sideFolders;
    final folderRail =
        sideFolders &&
            folderMode == ChatFolderDisplayMode.tabs &&
            _model.filters.length > 1
        ? _chatFolderRail()
        : null;
    final controller = widget.controller;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(widget.controller, controller)) {
        controller?.publishSideFolders(this, folderRail);
      }
    });
    if (folderMode == ChatFolderDisplayMode.hidden && !_model.isAllFilter) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_model.isAllFilter) {
          _model.selectFilter(_model.filters.first);
        }
      });
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          color: c.background,
          child: Column(
            children: [
              if (!widget.desktopSidebar) _header(),
              if (!sideFolders &&
                  folderMode == ChatFolderDisplayMode.tabs &&
                  _model.filters.length > 1)
                _chatFolderTabs(),
              Expanded(
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _handleGesturePointerDown,
                  onPointerMove: _handleGesturePointerMove,
                  onPointerUp: _handleGesturePointerUp,
                  onPointerCancel: _handleGesturePointerCancel,
                  child: _folderPager(),
                ),
              ),
            ],
          ),
        ),
        _plusMenuOverlay(visible: _showPlusMenu),
        _filterMenuOverlay(
          visible: folderMode == ChatFolderDisplayMode.menu && _showFilterMenu,
        ),
      ],
    );
  }

  void _handleGesturePointerDown(PointerDownEvent event) {
    if (!kIsWeb && isDesktopTargetPlatform(defaultTargetPlatform)) return;
    final wasSuppressingRows = _chatListSwipeSession.suppressRowSwipes;
    final tracked = _chatListSwipeSession.pointerDown(
      pointer: event.pointer,
      position: event.position,
      kind: event.kind,
      mode: context.read<ThemeController>().chatListSwipeMode,
    );
    if (tracked &&
        wasSuppressingRows != _chatListSwipeSession.suppressRowSwipes) {
      setState(() {});
    }
  }

  void _handleGesturePointerMove(PointerMoveEvent event) {
    if (!kIsWeb && isDesktopTargetPlatform(defaultTargetPlatform)) return;
    _chatListSwipeSession.pointerMove(
      pointer: event.pointer,
      position: event.position,
    );
    _trackFolderDrag(event);
  }

  /// Steers the chat list with the fingers that are still down. The release
  /// classification stays as the fallback for gestures that never arm a drag.
  void _trackFolderDrag(PointerMoveEvent event) {
    final theme = context.read<ThemeController>();
    final mode = theme.chatListSwipeMode;
    final folderMode = theme.chatFolderDisplayMode;
    final travel = _chatListSwipeSession.liveCentroidDelta;
    if (_folderDragActive) {
      if (travel == null ||
          _chatListSwipeSession.liveDecision(mode).action !=
              ChatListSwipeAction.switchFolders) {
        // A late third finger turned this into an account switch.
        _cancelFolderDrag();
        return;
      }
      _folderDragVelocity?.addPosition(event.timeStamp, travel);
      _applyFolderDragTravel(travel.dx - _folderDragOrigin);
      return;
    }
    if (travel == null ||
        _folderPagerWidth <= 0 ||
        _model.filters.length < 2 ||
        folderMode == ChatFolderDisplayMode.hidden ||
        _chatListSwipeSession.liveDecision(mode).action !=
            ChatListSwipeAction.switchFolders) {
      return;
    }
    if (_folderSettleController.isAnimating) {
      // A second swipe arriving mid-slide lands the first one and picks up from
      // the folder it was heading to, so flicking through folders keeps up.
      _folderSettleController.stop();
      _finishFolderSettle();
    }
    _folderDragActive = true;
    _folderDragHandled = true;
    // Start from where the gesture was recognised so the list does not jump by
    // the activation distance.
    _folderDragOrigin = travel.dx;
    _folderDragVelocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, travel);
    _applyFolderDragTravel(0);
  }

  void _applyFolderDragTravel(double travel) {
    final neighbour = _folderNeighbour(travel);
    if (!identical(neighbour, _folderPeek)) {
      setState(() {
        _folderPeek = neighbour;
        if (neighbour != null) _folderPeekSide = travel.isNegative ? 1 : -1;
      });
      if (neighbour != null) {
        _model.prefetchFolder(neighbour.folderId);
        _ensureFolderTabVisible(neighbour.folderId, _folderPeekSide);
      }
    }
    _folderDrag.value = chatListFolderDragOffset(
      travel: travel,
      width: _folderPagerWidth,
      hasNeighbour: neighbour != null,
    );
  }

  ChatFilterOption? _folderNeighbour(double travel) {
    if (travel == 0) return null;
    final filters = _model.filters;
    final current = filters.indexWhere(
      (filter) => filter.folderId == _model.selectedFilter.folderId,
    );
    if (current < 0) return null;
    final next = current + (travel.isNegative ? 1 : -1);
    if (next < 0 || next >= filters.length) return null;
    return filters[next];
  }

  void _cancelFolderDrag() {
    if (!_folderDragActive) return;
    _folderDragActive = false;
    _folderDragVelocity = null;
    _folderSettleTarget = null;
    _startFolderSettle(to: 0, velocity: 0);
  }

  void _releaseFolderDrag({required bool canceled}) {
    _folderDragActive = false;
    final velocity =
        _folderDragVelocity?.getVelocity().pixelsPerSecond.dx ?? 0.0;
    _folderDragVelocity = null;
    final peek = _folderPeek;
    final commit =
        !canceled &&
        peek != null &&
        chatListFolderDragShouldCommit(
          offset: _folderDrag.value,
          width: _folderPagerWidth,
          velocity: velocity,
        );
    _folderSettleTarget = commit ? peek : null;
    if (AppMotion.isReduced(context)) {
      _finishFolderSettle();
      return;
    }
    _startFolderSettle(
      to: commit ? -_folderPeekSide * _folderPagerWidth : 0,
      velocity: velocity,
    );
  }

  void _handleGesturePointerUp(PointerUpEvent event) {
    if (!kIsWeb && isDesktopTargetPlatform(defaultTargetPlatform)) return;
    _handleGesturePointerEnd(event, canceled: false);
  }

  void _handleGesturePointerCancel(PointerCancelEvent event) {
    if (!kIsWeb && isDesktopTargetPlatform(defaultTargetPlatform)) return;
    _handleGesturePointerEnd(event, canceled: true);
  }

  void _handleGesturePointerEnd(PointerEvent event, {required bool canceled}) {
    final wasSuppressingRows = _chatListSwipeSession.suppressRowSwipes;
    if (_folderDragActive) _releaseFolderDrag(canceled: canceled);
    final decision = _chatListSwipeSession.pointerEnd(
      pointer: event.pointer,
      position: event.position,
      currentMode: context.read<ThemeController>().chatListSwipeMode,
      canceled: canceled,
    );
    if (wasSuppressingRows != _chatListSwipeSession.suppressRowSwipes) {
      setState(() {});
    }
    switch (decision?.action) {
      case ChatListSwipeAction.switchFolders:
        // A drag that followed the fingers has already settled itself.
        if (!_folderDragHandled) {
          _switchFolderBySwipe(decision!.horizontalDelta < 0 ? -1000 : 1000);
        }
      case ChatListSwipeAction.switchAccounts:
        _switchAccountBySwipe(decision!.horizontalDelta);
      case ChatListSwipeAction.none:
      case null:
        break;
    }
    if (decision != null) _folderDragHandled = false;
  }

  void _switchAccountBySwipe(double horizontalDelta) {
    final accounts = context.read<AccountStore>();
    final summaries = accounts.summaries;
    if (summaries.length < 2) return;
    final current = summaries.indexWhere(
      (account) => account.slot == accounts.activeSlot,
    );
    if (current < 0) return;
    final step = horizontalDelta < 0 ? 1 : -1;
    final next = (current + step) % summaries.length;
    accounts.switchTo(summaries[next].slot, context.read<AuthManager>());
  }

  // MARK: - Header

  Widget _header() {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    final appLock = context.watch<LocalAppLockController?>();
    final useFilterMenu =
        theme.chatFolderDisplayMode == ChatFolderDisplayMode.menu;
    final activeFilter = _model.selectedFilter;
    return Container(
      color: c.listHeaderTint,
      padding: headerChromePaddingOf(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: AppSpacing.md + AppSpacing.xxs,
        ),
        child: Row(
          children: [
            GestureDetector(
              key: const ValueKey('chat-list-header-avatar-hit'),
              behavior: HitTestBehavior.opaque,
              onTap: () => context.read<dc.DrawerController>().open(),
              child: SizedBox(
                width: AppMetric.chatHeaderHitTarget(),
                height: AppMetric.chatHeaderHitTarget(),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: PhotoAvatar(
                    title: _meName,
                    photo: _mePhoto,
                    size: AppMetric.chatHeaderAvatarSize(),
                    allowAnimation: false,
                  ),
                ),
              ),
            ),
            // The larger transparent hit box borrows from the existing 12pt
            // artwork/name gap, leaving artwork at the same 16pt inset.
            SizedBox(
              width:
                  AppSpacing.lg -
                  (AppMetric.chatHeaderHitTarget() -
                      AppMetric.chatHeaderAvatarSize()),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _meName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppTextSize.bodyLarge,
                            fontWeight: FontWeight.w500,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      if (_meStatusId != 0 &&
                          theme.chatListStatusEmojiMode.visible) ...[
                        const SizedBox(width: AppSpacing.xs + 1),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => showEmojiStatusPicker(
                            context,
                            currentStatusId: _meStatusId,
                          ),
                          child: StatusEmojiView(
                            id: _meStatusId,
                            size: 18,
                            color: c.textPrimary,
                            animate: theme.chatListStatusEmojiMode.animate,
                          ),
                        ),
                      ],
                      if (_meIsPremium && _meStatusId != 0) ...[
                        const SizedBox(width: AppSpacing.xs),
                        AppIcon(
                          HeroAppIcons.chevronDown,
                          size: 14,
                          color: c.textTertiary,
                        ),
                      ],
                    ],
                  ),
                  ChatListConnectionStatusView(status: _connectionStatus),
                ],
              ),
            ),
            if (useFilterMenu && !activeFilter.isAll) ...[
              const SizedBox(width: AppSpacing.md),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 132),
                child: Text(
                  activeFilter.title.l10n(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: AppTextSize.callout,
                    color: c.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
            ],
            if (useFilterMenu && _model.filters.isNotEmpty)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() {
                  _dismissDesktopPlusMenu();
                  _showFilterMenu = true;
                  _showPlusMenu = false;
                }),
                child: SizedBox(
                  width: AppMetric.hitTarget,
                  height: AppMetric.hitTarget,
                  child: AppIcon(
                    HeroAppIcons.folder,
                    size: AppIconSize.toolbar,
                    color: c.textPrimary,
                  ),
                ),
              ),
            if (appLock?.enabled == true) ...[
              const SizedBox(width: AppSpacing.xs),
              Semantics(
                button: true,
                label: AppStringKeys.appLockLockNow.l10n(context),
                child: GestureDetector(
                  key: const ValueKey('chat-list-app-lock'),
                  behavior: HitTestBehavior.opaque,
                  onTap: appLock!.lock,
                  child: SizedBox(
                    width: AppMetric.hitTarget,
                    height: AppMetric.hitTarget,
                    child: AppIcon(
                      HeroAppIcons.lock,
                      size: AppIconSize.toolbar,
                      color: c.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
            GestureDetector(
              key: const ValueKey('chat-list-header-add-hit'),
              behavior: HitTestBehavior.opaque,
              onTap: _openPlusMenu,
              child: SizedBox(
                width: AppMetric.chatHeaderHitTarget(),
                height: AppMetric.chatHeaderHitTarget(),
                child: AppIcon(
                  HeroAppIcons.plus,
                  size: AppMetric.chatHeaderAddSize(),
                  color: c.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// How lit a tab is right now: the selected one hands its highlight over to
  /// the folder being swiped in as the list travels, so the strip moves with
  /// the drag instead of flipping once it lands.
  double _folderTabHighlight({required bool selected, required bool peeked}) {
    final width = _folderPagerWidth;
    if (width <= 0 || _folderPeek == null) return selected ? 1 : 0;
    final progress = (_folderDrag.value.abs() / width).clamp(0.0, 1.0);
    if (selected) return 1 - progress;
    return peeked ? progress : 0;
  }

  Widget _chatFolderRail() => AnimatedBuilder(
    animation: _folderDrag,
    builder: (context, _) => ChatFolderRail(
      filters: _model.filters,
      showUnreadBadges: context.watch<ThemeController>().showFolderUnreadBadges,
      badgeOverflowMode: context
          .watch<ThemeController>()
          .unreadBadgeOverflowMode,
      selectedFolderId: _model.selectedFilter.folderId,
      highlights: {
        for (final filter in _model.filters)
          filter.folderId: _folderTabHighlight(
            selected: filter.folderId == _model.selectedFilter.folderId,
            peeked: filter.folderId == _folderPeek?.folderId,
          ),
      },
      onSelect: _selectFilter,
      onMenu: _showFolderMenu,
      keyForFolder: (id) => _sideFolderKeys.putIfAbsent(id, GlobalKey.new),
    ),
  );

  Widget _chatFolderTabs() {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    final showBadges = theme.showFolderUnreadBadges;
    final badgeOverflow = theme.unreadBadgeOverflowMode;
    final selectedFolderId = _model.selectedFilter.folderId;
    // The strip scrolls horizontally, so its height is fixed; grow it with the
    // label that sits above the selection indicator.
    final tabHeight = AppMetric.rowExtentFor(
      context,
      base: 44,
      lines: const [AppTextSize.callout],
    );
    return Container(
      height: tabHeight,
      decoration: BoxDecoration(
        color: c.listHeaderTint,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: ListView.separated(
        controller: _folderTabScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: _model.filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 28),
        itemBuilder: (context, index) {
          final filter = _model.filters[index];
          final selected = filter.folderId == selectedFolderId;
          final peeked = filter.folderId == _folderPeek?.folderId;
          final key = _folderTabKeys.putIfAbsent(
            filter.folderId,
            GlobalKey.new,
          );
          return GestureDetector(
            key: key,
            behavior: HitTestBehavior.opaque,
            onTap: () => _selectFilter(filter),
            onLongPress: () => _showFolderMenu(filter),
            child: SizedBox(
              height: tabHeight,
              child: AnimatedBuilder(
                animation: _folderDrag,
                builder: (context, _) {
                  final highlight = _folderTabHighlight(
                    selected: selected,
                    peeked: peeked,
                  );
                  final accent = Color.lerp(
                    c.textSecondary,
                    AppTheme.brand,
                    highlight,
                  );
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ChatFolderIcon(
                            filter.isAll ? 'All' : filter.iconName,
                            size: 17,
                            color: accent ?? c.textSecondary,
                          ),
                          const SizedBox(width: AppSpacing.xs + 1),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 168),
                            child: Text(
                              filter.title.l10n(context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppTextSize.callout,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                          if (showBadges &&
                              !filter.isAll &&
                              filter.unreadChatCount > 0) ...[
                            const SizedBox(width: 5),
                            FolderUnreadBadge(
                              label: badgeOverflow.format(
                                filter.unreadChatCount,
                              ),
                              accent: filter.hasUnmutedUnread,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 7),
                      Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.brand.withValues(alpha: highlight),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      )._withChatFolderMouseDrag(context),
    );
  }

  // MARK: - Search

  // Measure the same inherited font, locale and OS scaler as the visible
  // placeholder. The default remains 33pt; accessibility and tall custom fonts
  // grow the visual and its scroll allocation together instead of clipping.
  double _touchSearchVisualHeight() {
    final style = AppTextStyle.forSystemBoldTextMeasurement(
      DefaultTextStyle.of(context).style.merge(const TextStyle(fontSize: 16)),
      boldText: MediaQuery.boldTextOf(context),
    );
    final painter = TextPainter(
      text: TextSpan(
        text: AppStringKeys.topicChatSearch.l10n(context),
        style: style,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    )..layout();
    final height = math.max(AppMetric.chatSearchHeight(), painter.height + 8);
    painter.dispose();
    return height;
  }

  double _searchSlotExtent() =>
      isTouchTargetPlatform() && !widget.desktopSidebar
      ? math.max(_searchPillExtent, _touchSearchVisualHeight() + 17)
      : _searchPillExtent;

  Widget _searchPill() {
    final c = context.colors;
    if (isTouchTargetPlatform() && !widget.desktopSidebar) {
      return Container(
        key: const ValueKey('chat-list-inline-search'),
        color: c.listHeaderTint,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GestureDetector(
          key: const ValueKey('chat-list-search-hit'),
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SearchView())),
          child: SizedBox(
            height: _searchSlotExtent(),
            child: Center(
              child: Container(
                key: const ValueKey('chat-list-search-visual'),
                height: _touchSearchVisualHeight(),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                decoration: BoxDecoration(
                  color: c.searchFill,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppIcon(
                      HeroAppIcons.magnifyingGlass,
                      size: AppMetric.chatSearchIcon(),
                      color: c.textTertiary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        AppStringKeys.topicChatSearch.l10n(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, color: c.textTertiary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    final search = GestureDetector(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const SearchView())),
      child: Container(
        height: AppMetric.searchHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          color: c.searchFill,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(
              HeroAppIcons.magnifyingGlass,
              size: AppMetric.searchIcon,
              color: c.textTertiary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              AppStringKeys.topicChatSearch.l10n(context),
              style: TextStyle(
                fontSize: isTouchTargetPlatform() ? 16 : AppTextSize.callout,
                color: c.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
    if (!widget.desktopSidebar) {
      return Container(
        key: const ValueKey('chat-list-inline-search'),
        color: c.listHeaderTint,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: search,
      );
    }
    final theme = context.watch<ThemeController>();
    final showFolder =
        theme.chatFolderDisplayMode == ChatFolderDisplayMode.menu &&
        _model.filters.isNotEmpty;
    if (!showFolder) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('chat-list-desktop-toolbar'),
      color: c.listHeaderTint,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _desktopToolbarAction(
            key: const ValueKey('chat-list-desktop-folder'),
            icon: HeroAppIcons.folder,
            label: AppStringKeys.appearanceChatFolders.l10n(context),
            onTap: () => setState(() {
              _dismissDesktopPlusMenu();
              _showFilterMenu = true;
              _showPlusMenu = false;
            }),
          ),
        ],
      ),
    );
  }

  Widget _desktopToolbarAction({
    required Key key,
    required AppIconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    return AppInteractiveSurface(
      key: key,
      semanticLabel: label,
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Container(
        width: AppMetric.searchHeight,
        height: AppMetric.searchHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.searchFill,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: AppIcon(icon, size: 20, color: c.textPrimary),
      ),
    );
  }

  // MARK: - List

  /// Lays the live chat list and the folder it is being swiped towards side by
  /// side, then slides the pair with the finger. Only the transforms rebuild
  /// per frame; the lists themselves are untouched while they travel.
  Widget _folderPager() {
    return LayoutBuilder(
      builder: (context, geo) {
        _folderPagerWidth = geo.maxWidth;
        final peek = _folderPeek;
        return ChatListFolderPanes(
          offset: _folderDrag,
          peekSide: _folderPeekSide,
          width: geo.maxWidth,
          current: _chatList(),
          peek: peek == null ? null : _folderPeekList(peek),
        );
      },
    );
  }

  /// A read-only rendering of the folder a swipe is heading for. It never takes
  /// the shared scroll controller and never wires up row actions, so the list
  /// being left behind keeps its position and its gestures.
  Widget _folderPeekList(ChatFilterOption filter) => LayoutBuilder(
    builder: (context, constraints) => ChatRowWidth(
      width: constraints.maxWidth,
      child: Builder(
        builder: (context) => _folderPeekListContents(context, filter),
      ),
    ),
  );

  Widget _folderPeekListContents(
    BuildContext context,
    ChatFilterOption filter,
  ) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    final entries = _model.chatListEntriesForFolder(
      filter.folderId,
      communitiesEnabled: theme.communitiesEnabled,
    );
    final searchExtent = _leadingListControlsExtent(theme);
    final showSearch = searchExtent > 0;
    final archiveMode = effectiveChatListArchiveDisplayMode(
      theme.archivedChatsDisplayMode,
    );
    final showInlineArchive =
        filter.isAll && _model.archived.isNotEmpty && archiveMode.isInline;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Container(
          color: c.background,
          child: LayoutBuilder(
            builder: (context, geo) {
              final rowH = chatListRowExtentFor(context);
              if (entries.isEmpty && !showInlineArchive) {
                return ListView(
                  primary: false,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.only(bottom: BottomBarInset.of(context)),
                  children: [
                    if (showSearch) _searchPill(),
                    SizedBox(
                      height: math.max(180, geo.maxHeight - searchExtent),
                      child: _emptyChatList(),
                    ),
                  ],
                );
              }
              final archiveIndex = archiveMode.insertionIndex(
                chatCount: entries.length,
                visibleRows: math.max(1, (geo.maxHeight / rowH).ceil()),
              );
              return ListView.builder(
                primary: false,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.only(bottom: BottomBarInset.of(context)),
                itemCount:
                    (showSearch ? 1 : 0) +
                    entries.length +
                    (showInlineArchive ? 1 : 0),
                itemBuilder: (context, index) {
                  if (showSearch && index == 0) return _searchPill();
                  final listIndex = showSearch ? index - 1 : index;
                  if (showInlineArchive && listIndex == archiveIndex) {
                    return _assistantRow();
                  }
                  final entryIndex =
                      showInlineArchive && listIndex > archiveIndex
                      ? listIndex - 1
                      : listIndex;
                  final entry = entries[entryIndex];
                  return switch (entry) {
                    CommunityChatEntry(:final chat) => _peekRow(
                      chat,
                      filter.folderId,
                    ),
                    CommunityGroupEntry() => _communityRow(entry),
                  };
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _peekRow(ChatSummary chat, int? folderId) {
    final selected = widget.selectedChatId == chat.id;
    return ChatListSelectionHighlight(
      key: ValueKey(chat.id),
      selected: selected,
      child: ChatRowView(
        chat: chat,
        selected: selected,
        pinned: folderId == null
            ? null
            : _model.isPinnedInFolder(chat, folderId),
        avatarBadge: _communityBadge(
          chat,
          communitiesEnabled: context
              .read<ThemeController>()
              .communitiesEnabled,
        ),
      ),
    );
  }

  Widget _chatList() => LayoutBuilder(
    builder: (context, constraints) {
      _lastRowWidth = constraints.maxWidth;
      return ChatRowWidth(
        width: constraints.maxWidth,
        child: Builder(builder: _chatListContents),
      );
    },
  );

  Widget _chatListContents(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    final leadingControlsExtent = _leadingListControlsExtent(theme);
    final showLeadingControls = leadingControlsExtent > 0;
    final archiveMode = effectiveChatListArchiveDisplayMode(
      theme.archivedChatsDisplayMode,
    );
    return Container(
      color: c.background,
      child: LayoutBuilder(
        builder: (context, geo) {
          final rowH = chatListRowExtentFor(context);
          final searchHeight = leadingControlsExtent;
          final visibleRows = math.max(1, (geo.maxHeight / rowH).ceil());
          _lastVisibleRows = visibleRows;
          final entries = _model.chatListEntries(
            communitiesEnabled: theme.communitiesEnabled,
          );
          final hasFiltered = _model.isAllFilter && _model.filtered.isNotEmpty;
          final hasArchive = _model.isAllFilter && _model.archived.isNotEmpty;
          final showPulledDownArchive =
              hasArchive &&
              archiveMode == ArchivedChatsDisplayMode.pullDown &&
              _archiveRevealed;
          final hasPullDownArchiveSlot =
              hasArchive && archiveMode == ArchivedChatsDisplayMode.pullDown;
          final archiveIndex = archiveMode.insertionIndex(
            chatCount: entries.length,
            visibleRows: visibleRows,
          );
          final showInlineArchive = hasArchive && archiveMode.isInline;
          Widget list;
          if (entries.isEmpty &&
              _model.isInitialLoading &&
              !showInlineArchive &&
              !hasFiltered) {
            list = ListView.builder(
              controller: _scrollController,
              // Pull-down Archive depends on negative scroll extents, so this
              // list intentionally keeps elastic physics on every platform.
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.only(bottom: BottomBarInset.of(context)),
              itemCount:
                  visibleRows +
                  (showLeadingControls ? 1 : 0) +
                  (hasPullDownArchiveSlot ? 1 : 0),
              itemBuilder: (context, index) {
                if (showLeadingControls && index == 0) {
                  return _archivePullSearchPill(hasPullDownArchiveSlot);
                }
                if (hasPullDownArchiveSlot &&
                    index ==
                        chatListPullDownArchiveItemIndex(
                          showSearch: showLeadingControls,
                        )) {
                  return _pullDownArchiveSlot(
                    rowHeight: rowH,
                    visible: showPulledDownArchive,
                  );
                }
                return const _ChatRowPlaceholder();
              },
            );
          } else if (entries.isEmpty && !showInlineArchive && !hasFiltered) {
            list = ListView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.only(bottom: BottomBarInset.of(context)),
              children: [
                if (showLeadingControls)
                  _archivePullSearchPill(hasPullDownArchiveSlot),
                if (hasPullDownArchiveSlot)
                  _pullDownArchiveSlot(
                    rowHeight: rowH,
                    visible: showPulledDownArchive,
                  ),
                SizedBox(
                  height: math.max(
                    180,
                    geo.maxHeight -
                        BottomBarInset.of(context) -
                        searchHeight -
                        (showPulledDownArchive ? rowH : 0),
                  ),
                  child: _emptyChatList(),
                ),
              ],
            );
          } else {
            list = ListView.builder(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.only(bottom: BottomBarInset.of(context)),
              itemCount:
                  (showLeadingControls ? 1 : 0) +
                  entries.length +
                  (hasPullDownArchiveSlot ? 1 : 0) +
                  (showInlineArchive ? 1 : 0) +
                  (hasFiltered ? 1 : 0),
              itemBuilder: (context, index) {
                if (showLeadingControls && index == 0) {
                  return _archivePullSearchPill(hasPullDownArchiveSlot);
                }
                final contentIndex = showLeadingControls ? index - 1 : index;
                if (hasPullDownArchiveSlot && contentIndex == 0) {
                  return _pullDownArchiveSlot(
                    rowHeight: rowH,
                    visible: showPulledDownArchive,
                  );
                }
                final contentAfterPullDownArchive =
                    contentIndex - (hasPullDownArchiveSlot ? 1 : 0);
                if (hasFiltered && contentAfterPullDownArchive == 0) {
                  return _filteredChatsRow();
                }
                final listIndex = hasFiltered
                    ? contentAfterPullDownArchive - 1
                    : contentAfterPullDownArchive;
                if (showInlineArchive && listIndex == archiveIndex) {
                  return _assistantRow();
                }
                final entryIndex = showInlineArchive && listIndex > archiveIndex
                    ? listIndex - 1
                    : listIndex;
                final entry = entries[entryIndex];
                return switch (entry) {
                  CommunityChatEntry(:final chat) => _swipeRow(chat),
                  CommunityGroupEntry() => _communityRow(entry),
                };
              },
            );
          }

          return NotificationListener<ScrollNotification>(
            onNotification: _handleChatListPull,
            child: list,
          );
        },
      ),
    );
  }

  double _leadingListControlsExtent(ThemeController theme) {
    if (!widget.desktopSidebar) {
      return theme.showChatListSearch ? _searchSlotExtent() : 0;
    }
    final showFolder =
        theme.chatFolderDisplayMode == ChatFolderDisplayMode.menu &&
        _model.filters.isNotEmpty;
    return showFolder ? _searchPillExtent : 0;
  }

  Widget _archivePullSearchPill(bool pinDuringArchivePull) {
    return ChatListTopOverscrollPin(
      controller: _scrollController,
      enabled: pinDuringArchivePull,
      child: _searchPill(),
    );
  }

  Widget _pullDownArchiveSlot({
    required double rowHeight,
    required bool visible,
  }) {
    final duration = MediaQuery.maybeOf(context)?.disableAnimations ?? false
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return ChatListPullDownArchiveSlot(
      controller: _scrollController,
      rowHeight: _archiveExtent(),
      visible: visible,
      duration: duration,
      child: _assistantRow(),
    );
  }

  bool _handleChatListPull(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (_isRefreshing) return false;

    if (notification is ScrollStartNotification) {
      _refreshPullDistance = 0;
    } else if (notification is OverscrollNotification &&
        notification.overscroll < 0) {
      _refreshPullDistance += -notification.overscroll;
    } else if (notification is ScrollUpdateNotification &&
        notification.metrics.pixels < 0) {
      _refreshPullDistance = math.max(
        _refreshPullDistance,
        -notification.metrics.pixels,
      );
    } else if (notification is ScrollEndNotification) {
      final pull = _refreshPullDistance;
      _refreshPullDistance = 0;
      if (pull >= _refreshPullThreshold) {
        unawaited(_refreshChats());
      }
    }
    return false;
  }

  Future<void> _refreshChats() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      await _model.refresh();
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  void _switchFolderBySwipe(double? velocity) {
    if (velocity == null || velocity.abs() < 240) return;
    if (context.read<ThemeController>().chatFolderDisplayMode ==
        ChatFolderDisplayMode.hidden) {
      return;
    }
    final filters = _model.filters;
    if (filters.length < 2) return;
    final current = filters.indexWhere(
      (filter) => filter.folderId == _model.selectedFilter.folderId,
    );
    if (current < 0) return;
    final next = velocity < 0 ? current + 1 : current - 1;
    if (next < 0 || next >= filters.length) return;
    _switchToFilter(filters[next]);
  }

  Widget _communityRow(CommunityGroupEntry entry) {
    return GestureDetector(
      key: ValueKey('community-${entry.community.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _openCommunity(entry),
      child: CommunityChatListRow(
        entry: entry,
        selected: widget.selectedCommunityId == entry.community.id,
        onClearUnread: () {
          for (final chat in entry.chats) {
            _model.markRead(chat);
          }
        },
      ),
    );
  }

  /// A community's chats are ordinary rows again once "Show as One Chat" is
  /// off, and without this marker the hub has no entry point at all.
  Widget? _communityBadge(
    ChatSummary chat, {
    required bool communitiesEnabled,
  }) {
    final community = _model.communityBadgeFor(
      chat.id,
      communitiesEnabled: communitiesEnabled,
    );
    if (community == null) return null;
    return CommunityAvatarBadge(onTap: () => _openCommunityHub(community));
  }

  Widget _swipeRow(ChatSummary chat) {
    final selected = widget.selectedChatId == chat.id;
    final theme = context.watch<ThemeController>();
    final swipeMode = theme.chatListSwipeMode;
    final platform = Theme.of(context).platform;
    final desktopContextMenu = !kIsWeb && isDesktopTargetPlatform(platform);
    final desktopTouchGestures =
        desktopContextMenu &&
        (platform == TargetPlatform.windows ||
            platform == TargetPlatform.linux);
    final rowSwipeActionsEnabled = chatListRowSwipeActionsEnabled(
      mode: swipeMode,
      multiTouchActive: _chatListSwipeSession.suppressRowSwipes,
    );
    // The pin state of the list the user is looking at, not the Main list's.
    final pinnedInList = _model.isPinnedInSelectedList(chat);
    final actions = pinnedInList
        ? [
            SwipeActionItem(
              title: AppStringKeys.chatListMarkUnread,
              color: const Color(0xFFF5A623),
              onTap: () => _model.markUnread(chat),
            ),
            SwipeActionItem(
              title: AppStringKeys.chatListUnpin,
              color: const Color(0xFF8E8E93),
              onTap: () => _model.togglePin(chat),
            ),
            SwipeActionItem(
              title: _deleteOrLeaveTitle(chat),
              color: const Color(0xFFFA5151),
              onTap: () => _confirmDeleteChat(chat),
            ),
          ]
        : [
            SwipeActionItem(
              title: AppStringKeys.chatInfoPin,
              color: const Color(0xFF3C8CF0),
              onTap: () => _model.togglePin(chat),
            ),
            SwipeActionItem(
              title: AppStringKeys.chatListMarkUnread,
              color: const Color(0xFFF5A623),
              onTap: () => _model.markUnread(chat),
            ),
            SwipeActionItem(
              title: _deleteOrLeaveTitle(chat),
              color: const Color(0xFFFA5151),
              onTap: () => _confirmDeleteChat(chat),
            ),
          ];
    return ChatSwipeRow(
      key: ValueKey(chat.id),
      rowId: chat.id,
      openRowId: _openSwipeChat,
      onOpenChanged: (id) => setState(() => _openSwipeChat = id),
      onTap: () => _openChat(chat),
      onLongPress: desktopContextMenu ? null : () => _showChatPreview(chat),
      onSecondaryTapDown: desktopContextMenu
          ? (details) => _showDesktopChatMenu(chat, details.globalPosition)
          : null,
      // Windows and Linux still expose these actions to touchscreen users.
      // ChatSwipeRow filters that path to touch so a mouse drag never moves a
      // desktop row.
      horizontalSwipeEnabled:
          rowSwipeActionsEnabled &&
          (!desktopContextMenu || desktopTouchGestures),
      pressRippleEnabled: !desktopContextMenu,
      actions: actions,
      child: ChatListSelectionHighlight(
        selected: selected,
        child: ChatRowView(
          chat: chat,
          selected: selected,
          pinned: _model.isPinnedInSelectedList(chat),
          onClearUnread: () => _model.markRead(chat),
          avatarBadge: _communityBadge(
            chat,
            communitiesEnabled: theme.communitiesEnabled,
          ),
        ),
      ),
    );
  }

  void _dismissDesktopChatMenu() {
    final entry = _desktopChatMenuEntry;
    _desktopChatMenuEntry = null;
    entry?.remove();
  }

  void _showDesktopChatMenu(ChatSummary chat, Offset globalPosition) {
    if (kIsWeb || !isDesktopTargetPlatform(defaultTargetPlatform)) return;
    if (_openSwipeChat != null) setState(() => _openSwipeChat = null);
    _dismissDesktopChatMenu();

    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (overlayBox == null || !overlayBox.hasSize) return;
    final anchor = overlayBox.globalToLocal(globalPosition);
    final openInSeparateWindow =
        widget.onOpenChatInSeparateWindow ??
        (DesktopChatWindowService.instance.isSupported
            ? _openChatInSeparateWindow
            : null);

    late final OverlayEntry entry;
    void dismiss() {
      if (_desktopChatMenuEntry != entry) return;
      _dismissDesktopChatMenu();
    }

    final owner = ChatPreviewAccounts.defaultPreviewAccounts.pinActiveOwner();
    final pinnedInList = _model.isPinnedInSelectedList(chat);
    entry = OverlayEntry(
      builder: (_) => DesktopChatContextMenu(
        anchor: anchor,
        isPinned: pinnedInList,
        hasUnread: chat.unreadCount > 0 || chat.isMarkedUnread,
        isMuted: chat.isMuted,
        deleteOrLeaveLabel: _deleteOrLeaveTitle(chat),
        onDismiss: dismiss,
        onTogglePin: () => _model.togglePin(chat),
        onToggleRead: () => chat.unreadCount > 0 || chat.isMarkedUnread
            ? _model.markRead(chat)
            : _model.markUnread(chat),
        onOpenSeparateWindow: openInSeparateWindow == null
            ? null
            : () => unawaited(openInSeparateWindow(chat)),
        onToggleMute: () => _model.toggleMute(chat),
        onArchive: () => _model.archive(chat, owner: owner),
        onDeleteOrLeave: () => unawaited(_confirmDeleteChat(chat)),
      ),
    );
    _desktopChatMenuEntry = entry;
    overlay.insert(entry);
  }

  Future<void> _openChatInSeparateWindow(ChatSummary chat) async {
    final theme = context.read<ThemeController>();
    final accounts = context.read<AccountStore>();
    final activeAccount = accounts.activeSummary;
    final opened = await DesktopChatWindowService.instance.open(
      DesktopChatWindowArguments(
        accountSlot: accounts.activeSlot,
        accountUserId: activeAccount?.userId,
        accountName: activeAccount?.name ?? 'Mithka',
        accountAvatarPath: activeAccount?.avatarPath,
        chatId: chat.id,
        title: chat.title,
        localeTag: Localizations.localeOf(context).toLanguageTag(),
        dark: Theme.of(context).brightness == Brightness.dark,
        enterToSend: theme.enterToSend,
        palette: DesktopChatWindowPalette.fromColors(
          context.colors,
          brand: AppTheme.brand,
        ),
      ),
    );
    if (!opened && mounted) {
      showToast(context, AppStringKeys.desktopChatWindowUnavailable);
    }
  }

  void _showChatPreview(ChatSummary chat) {
    if (_openSwipeChat != null) setState(() => _openSwipeChat = null);
    final hasUnread = chat.unreadCount > 0 || chat.isMarkedUnread;
    // The preview's pin label/icon follow the list the row was opened from.
    final pinnedInList = _model.isPinnedInSelectedList(chat);
    final accounts = context.read<AccountStore>();
    final activeAccount = accounts.activeSummary;
    final avatarPath = activeAccount?.avatarPath?.trim();
    final owner = ChatPreviewAccounts.defaultPreviewAccounts.pinActiveOwner();
    unawaited(
      showChatListPreview(
        context,
        chat: chat,
        meName: activeAccount?.name,
        mePhoto: avatarPath == null || avatarPath.isEmpty
            ? null
            : TdFileRef(id: 0, localPath: avatarPath),
        pinned: pinnedInList,
        actions: [
          if (chatListPreviewSupportsQuickReply(chat))
            ChatListPreviewAction(
              label: AppStringKeys.chatInputBarReply,
              icon: HeroAppIcons.reply,
              onSelected: () => unawaited(_openChat(chat, focusComposer: true)),
            ),
          ChatListPreviewAction(
            label: AppStringKeys.linkHandlerOpenChat,
            icon: HeroAppIcons.message,
            onSelected: () => unawaited(_openChat(chat)),
          ),
          ChatListPreviewAction(
            label: hasUnread
                ? AppStringKeys.channelDirectMessagesMarkRead
                : AppStringKeys.chatListMarkUnread,
            icon: hasUnread ? HeroAppIcons.circleCheck : HeroAppIcons.eyeSlash,
            onSelected: () =>
                hasUnread ? _model.markRead(chat) : _model.markUnread(chat),
          ),
          ChatListPreviewAction(
            label: pinnedInList
                ? AppStringKeys.chatListUnpin
                : AppStringKeys.chatInfoPin,
            icon: HeroAppIcons.thumbtack,
            onSelected: () => _model.togglePin(chat),
          ),
          ChatListPreviewAction(
            label: AppStringKeys.chatListArchive,
            icon: HeroAppIcons.archiveBox,
            onSelected: () => _model.archive(chat, owner: owner),
          ),
          ChatListPreviewAction(
            label: chat.isMuted
                ? AppStringKeys.chatUnmute
                : AppStringKeys.callMute,
            icon: chat.isMuted ? HeroAppIcons.bell : HeroAppIcons.bellSlash,
            onSelected: () => _model.toggleMute(chat),
          ),
          ChatListPreviewAction(
            label: _deleteOrLeaveTitle(chat),
            icon: HeroAppIcons.trash,
            destructive: true,
            onSelected: () => unawaited(_confirmDeleteChat(chat)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteChat(ChatSummary chat) async {
    final isGroupOrChannel =
        chat.kind == ChatKind.group || chat.kind == ChatKind.channel;
    final savedMessagesResolution = await _model.resolveIsSavedMessages(chat);
    if (!mounted) return;
    if (savedMessagesResolution == null) {
      showToast(context, AppStringKeys.chatDeleteUnavailable);
      return;
    }
    final isSavedMessages = savedMessagesResolution;
    final capabilities = isSavedMessages
        ? const ChatDeleteCapabilities.selfOnly()
        : await _model.deleteCapabilities(chat);
    if (!mounted) return;
    if (!capabilities.canDelete) {
      showToast(context, AppStringKeys.chatDeleteUnavailable);
      return;
    }
    final scope = await showTwoStepChatDeleteDialog(
      context,
      title: AppStringKeys.chatListDeleteChatQuestion,
      selfOnlyDescription: isGroupOrChannel
          ? AppStrings.t(AppStringKeys.chatLeaveAndDeleteDescription, {
              'value1': chat.title,
            })
          : AppStrings.t(AppStringKeys.chatInfoClearHistoryDescription),
      capabilities: capabilities,
      isGroupOrChannel: isGroupOrChannel,
      isSavedMessages: isSavedMessages,
      chatTitle: chat.title,
      selfConfirmText: _deleteOrLeaveTitle(chat),
    );
    if (!mounted || scope == null) return;
    try {
      if (isSavedMessages) {
        await _model.clearSavedMessages(chat);
      } else {
        await _model.deleteChat(chat, scope: scope);
      }
    } catch (error) {
      if (!mounted) return;
      final message = switch (error) {
        ChatRemovalUnavailable() => AppStringKeys.chatDeleteUnavailable,
        ChatLeaveHistoryCleanupFailed() =>
          AppStringKeys.chatLeaveHistoryCleanupFailed,
        TdError() => error.message,
        _ => error.toString(),
      };
      showToast(
        context,
        message.trim().isEmpty ? AppStringKeys.chatDelete : message,
      );
    }
  }

  String _deleteOrLeaveTitle(ChatSummary chat) {
    if (chat.isSavedMessages) return AppStringKeys.savedMessagesClear;
    if (chat.kind == ChatKind.channel) {
      return AppStringKeys.topicChatLeaveChannel;
    }
    if (chat.kind == ChatKind.group) return AppStringKeys.chatInfoLeaveGroup;
    return AppStringKeys.chatDelete;
  }

  PageRoute<T> _chatEntryRoute<T>(ChatView child) {
    return AppChatPageRoute<T>(builder: (_) => child);
  }

  Widget _assistantRow() {
    return GestureDetector(
      onTap: _openArchivedChats,
      child: ArchivedChatsRow(
        archived: _model.archived,
        onClearUnread: () => _model.markChatsRead(_model.archived),
      ),
    );
  }

  void _openArchivedChats() {
    final onOpenArchived = widget.onOpenArchived;
    if (onOpenArchived != null) {
      onOpenArchived(
        ArchivedChatListSelection(
          chatsProvider: () => _model.archived,
          updates: _model,
          onClearUnread: _model.markRead,
          onUnarchive: _model.unarchive,
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LiveArchivedChatsView(
          updates: _model,
          chatsProvider: () => _model.archived,
          onClearUnread: _model.markRead,
          onUnarchive: _model.unarchive,
        ),
      ),
    );
  }

  Widget _filteredChatsRow() {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FilteredChatsView(
            chats: _model.filtered,
            onClearUnread: _model.markRead,
          ),
        ),
      ),
      child: FilteredChatsRow(
        chats: _model.filtered,
        onClearUnread: () => _model.markChatsRead(_model.filtered),
      ),
    );
  }

  // MARK: - "+" dropdown

  Widget _plusMenuOverlay({required bool visible}) {
    return _AnimatedAnchoredMenuOverlay(
      visible: visible,
      top: MediaQuery.paddingOf(context).top + 48,
      onDismiss: () => setState(() => _showPlusMenu = false),
      child: PlusMenu(
        onSelect: _selectPlusMenuItem,
        showCommunities:
            context.watch<ThemeController>().communitiesEnabled &&
            _model.availableCommunities.isNotEmpty,
      ),
    );
  }

  Widget _filterMenuOverlay({required bool visible}) {
    return _AnimatedAnchoredMenuOverlay(
      visible: visible,
      top: MediaQuery.paddingOf(context).top + 48,
      onDismiss: () => setState(() => _showFilterMenu = false),
      child: ChatFilterMenu(
        filters: _model.filters,
        selected: _model.selectedFilter,
        onSelect: _selectFilter,
      ),
    );
  }

  Widget _emptyChatList() {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(HeroAppIcons.message, size: 34, color: c.textTertiary),
            const SizedBox(height: 12),
            Text(
              AppStringKeys.chatListNoChats.l10n(context),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.35,
                color: c.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopTitleBarPlusMenuOverlay extends StatelessWidget {
  const _DesktopTitleBarPlusMenuOverlay({
    required this.anchor,
    required this.onDismiss,
    required this.child,
  });

  /// Gap between the button and the menu below it.
  static const _gap = 6.0;

  final Rect anchor;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    // Right-aligned to the button, and only pulled back if that would run the
    // menu off an edge — a button already at the window edge should still get
    // an exactly aligned menu.
    // Must match the width PlusMenu actually renders, which is denser on a
    // pointer — otherwise the menu no longer lines up with its button.
    final width = AppMetric.popupMenuWidth();
    final maxLeft = (screen.width - width).clamp(0.0, double.infinity);
    final left = (anchor.right - width).clamp(0.0, maxLeft);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: const ColoredBox(color: Color(0x14000000)),
          ),
        ),
        Positioned(
          left: left,
          top: anchor.bottom + _gap,
          child: TweenAnimationBuilder<double>(
            duration: AppMotion.duration(context, AppMotion.responsive),
            curve: AppMotion.emphasized,
            tween: Tween(begin: 0, end: 1),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: child,
            ),
            builder: (context, progress, child) => Opacity(
              opacity: progress,
              child: Transform.translate(
                offset: Offset(0, -6 * (1 - progress)),
                child: Transform.scale(
                  alignment: Alignment.topRight,
                  scale: 0.96 + 0.04 * progress,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Keeps anchored menus mounted through their reverse animation so the
/// barrier, hit testing, and menu surface leave as one coherent motion.
class _AnimatedAnchoredMenuOverlay extends StatefulWidget {
  const _AnimatedAnchoredMenuOverlay({
    required this.visible,
    required this.top,
    required this.onDismiss,
    required this.child,
  });

  final bool visible;
  final double top;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  State<_AnimatedAnchoredMenuOverlay> createState() =>
      _AnimatedAnchoredMenuOverlayState();
}

class _AnimatedAnchoredMenuOverlayState
    extends State<_AnimatedAnchoredMenuOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.responsive,
    reverseDuration: AppMotion.quick,
    value: widget.visible ? 1 : 0,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncDuration();
    if (AppMotion.isReduced(context)) {
      _controller.value = widget.visible ? 1 : 0;
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedAnchoredMenuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncDuration();
    if (oldWidget.visible == widget.visible) return;
    if (AppMotion.isReduced(context)) {
      _controller.value = widget.visible ? 1 : 0;
    } else if (widget.visible) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _syncDuration() {
    _controller.duration = AppMotion.duration(context, AppMotion.responsive);
    _controller.reverseDuration = AppMotion.duration(context, AppMotion.quick);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          if (_controller.isDismissed) return const SizedBox.shrink();
          final progress = AppMotion.emphasized.transform(_controller.value);
          return IgnorePointer(
            ignoring: _controller.value == 0,
            child: ExcludeSemantics(
              excluding: _controller.value == 0,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onDismiss,
                      child: ColoredBox(
                        color: Colors.black.withValues(
                          alpha: 0.12 * _controller.value,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: widget.top, right: 10),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {},
                        child: Opacity(
                          opacity: progress,
                          child: Transform.translate(
                            offset: Offset(0, -8 * (1 - progress)),
                            child: Transform.scale(
                              alignment: Alignment.topRight,
                              scale: 0.94 + 0.06 * progress,
                              child: child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ChatRowPlaceholder extends StatelessWidget {
  const _ChatRowPlaceholder();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rowHeight = chatListRowExtentFor(context);
    return SizedBox(
      height: rowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Row(
          children: [
            Container(
              width: AppMetric.avatarSize,
              height: AppMetric.avatarSize,
              decoration: BoxDecoration(
                color: c.searchFill,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(
                    widthFactor: 0.34,
                    child: _PlaceholderBar(height: 16, color: c.searchFill),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FractionallySizedBox(
                    widthFactor: 0.68,
                    child: _PlaceholderBar(height: 13, color: c.searchFill),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            _PlaceholderBar(width: 44, height: 12, color: c.searchFill),
          ],
        ),
      ),
    );
  }
}

class _CommunityDirectoryView extends StatelessWidget {
  const _CommunityDirectoryView({required this.entries, required this.onOpen});

  final List<CommunityGroupEntry> entries;
  final ValueChanged<CommunityGroupEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.communityTitle,
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.of(context).pop();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      onOpen(entry);
                    });
                  },
                  child: CommunityChatListRow(entry: entry),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderBar extends StatelessWidget {
  const _PlaceholderBar({
    required this.height,
    required this.color,
    this.width,
  });

  final double? width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }
}

/// Reference-style "+" dropdown of create actions.
class PlusMenu extends StatelessWidget {
  const PlusMenu({
    super.key,
    required this.onSelect,
    this.showCommunities = false,
  });
  final ValueChanged<String> onSelect;
  final bool showCommunities;

  static const _baseItems = [
    (HeroAppIcons.qrcode, AppStringKeys.chatListScanQrCode),
    (HeroAppIcons.circlePlus, AppStringKeys.chatListCreateGroup),
    (HeroAppIcons.grip, AppStringKeys.chatListCreateChannel),
    (HeroAppIcons.userPlus, AppStringKeys.chatListAddFriendOrGroup),
  ];

  List<(AppIconData, String)> get _items => [
    if (showCommunities)
      (HeroAppIcons.objectGroup, AppStringKeys.communityTitle),
    ..._baseItems,
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final inset = AppMetric.popupMenuInset();
    return Material(
      color: Colors.transparent,
      child: Container(
        width: AppMetric.popupMenuWidth(),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          // The card and the empty content area behind it are the same colour
          // in the light theme, so without an edge the menu did not read as a
          // surface at all.
          border: Border.all(color: c.divider, width: 0.75),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in _items)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(item.$2),
                child: SizedBox(
                  height: AppMetric.popupMenuRowHeight(),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: inset),
                    child: Row(
                      children: [
                        SizedBox(
                          width: AppMetric.popupMenuIconSlot(),
                          child: AppIcon(
                            item.$1,
                            size: AppMetric.popupMenuIconSlot() - 3,
                            color: c.textPrimary,
                          ),
                        ),
                        SizedBox(width: inset * 0.75),
                        Expanded(
                          child: Text(
                            item.$2.l10n(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppMetric.popupMenuTextSize(),
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ChatFilterMenu extends StatelessWidget {
  const ChatFilterMenu({
    super.key,
    required this.filters,
    required this.selected,
    required this.onSelect,
  });

  final List<ChatFilterOption> filters;
  final ChatFilterOption selected;
  final ValueChanged<ChatFilterOption> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: AppMetric.popupMenuWidth(),
        constraints: const BoxConstraints(maxHeight: 360),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ListView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          itemCount: filters.length,
          itemBuilder: (context, index) {
            final filter = filters[index];
            final selectedFilter = filter.folderId == selected.folderId;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(filter),
              child: SizedBox(
                height: AppMetric.popupMenuRowHeight(),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppMetric.popupMenuInset(),
                  ),
                  child: Row(
                    children: [
                      ChatFolderIcon(
                        filter.isAll ? 'All' : filter.iconName,
                        size: AppMetric.popupMenuIconSlot() - 3,
                        color: c.textPrimary,
                      ),
                      SizedBox(width: AppMetric.popupMenuInset() * 0.75),
                      Expanded(
                        child: Text(
                          filter.title.l10n(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppMetric.popupMenuTextSize(),
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      if (selectedFilter)
                        AppIcon(
                          HeroAppIcons.check,
                          size: AppMetric.popupMenuIconSlot() - 4,
                          color: AppTheme.brand,
                        ),
                    ],
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

// MARK: - custom swipe row

/// Resolves a pointer-anchored desktop menu without allowing it to escape the
/// visible overlay. The two-pixel offset keeps the pointer clear of the first
/// action while preserving the exact click location as the anchor.
Offset desktopChatContextMenuTopLeft({
  required Offset anchor,
  required Size viewport,
  required Size menuSize,
  double margin = DesktopChatContextMenu.viewportMargin,
}) {
  final requested = anchor + const Offset(2, 2);
  final maxX = math.max(margin, viewport.width - menuSize.width - margin);
  final maxY = math.max(margin, viewport.height - menuSize.height - margin);
  return Offset(
    requested.dx.clamp(margin, maxX).toDouble(),
    requested.dy.clamp(margin, maxY).toDouble(),
  );
}

/// Compact, project-owned context menu used only by native desktop chat rows.
class DesktopChatContextMenu extends StatelessWidget {
  const DesktopChatContextMenu({
    super.key,
    required this.anchor,
    required this.isPinned,
    required this.hasUnread,
    required this.isMuted,
    required this.deleteOrLeaveLabel,
    required this.onDismiss,
    required this.onTogglePin,
    required this.onToggleRead,
    required this.onToggleMute,
    required this.onDeleteOrLeave,
    required this.onArchive,
    this.onOpenSeparateWindow,
  });

  static const double menuWidth = 232;
  static const double rowHeight = 38;
  static const double verticalPadding = 4;
  static const double dividerHeight = 0.5;
  static const double viewportMargin = 8;

  final Offset anchor;
  final bool isPinned;
  final bool hasUnread;
  final bool isMuted;
  final String deleteOrLeaveLabel;
  final VoidCallback onDismiss;
  final VoidCallback onTogglePin;
  final VoidCallback onToggleRead;
  final VoidCallback? onOpenSeparateWindow;
  final VoidCallback onToggleMute;
  final VoidCallback onDeleteOrLeave;
  final VoidCallback onArchive;

  double get _menuHeight =>
      verticalPadding * 2 +
      rowHeight * (onOpenSeparateWindow == null ? 5 : 6) +
      dividerHeight;

  void _select(VoidCallback action) {
    onDismiss();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final resolvedWidth = math
            .min(menuWidth, math.max(0.0, viewport.width - viewportMargin * 2))
            .toDouble();
        final menuSize = Size(resolvedWidth, _menuHeight);
        final topLeft = desktopChatContextMenuTopLeft(
          anchor: anchor,
          viewport: viewport,
          menuSize: menuSize,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              key: const ValueKey('desktop-chat-context-barrier'),
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
              onSecondaryTap: onDismiss,
              child: const ColoredBox(color: Colors.transparent),
            ),
            Positioned(
              left: topLeft.dx,
              top: topLeft.dy,
              child: Container(
                key: const ValueKey('desktop-chat-context-menu'),
                width: resolvedWidth,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.card,
                      border: Border.all(color: c.divider, width: 0.5),
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: verticalPadding,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _DesktopChatContextMenuItem(
                            key: const ValueKey('desktop-chat-context-pin'),
                            icon: HeroAppIcons.thumbtack,
                            label: isPinned
                                ? AppStringKeys.chatListUnpin
                                : AppStringKeys.chatInfoPin,
                            onTap: () => _select(onTogglePin),
                          ),
                          _DesktopChatContextMenuItem(
                            key: const ValueKey('desktop-chat-context-read'),
                            icon: hasUnread
                                ? HeroAppIcons.circleCheck
                                : HeroAppIcons.eyeSlash,
                            label: hasUnread
                                ? AppStringKeys.channelDirectMessagesMarkRead
                                : AppStringKeys.chatListMarkUnread,
                            onTap: () => _select(onToggleRead),
                          ),
                          if (onOpenSeparateWindow case final openSeparate?)
                            _DesktopChatContextMenuItem(
                              key: const ValueKey(
                                'desktop-chat-context-separate',
                              ),
                              icon: HeroAppIcons.pictureInPicture,
                              label: AppStringKeys.desktopChatOpenSeparate,
                              onTap: () => _select(openSeparate),
                            ),
                          _DesktopChatContextMenuItem(
                            key: const ValueKey('desktop-chat-context-mute'),
                            icon: isMuted
                                ? HeroAppIcons.bell
                                : HeroAppIcons.bellSlash,
                            label: isMuted
                                ? AppStringKeys.chatUnmute
                                : AppStringKeys.callMute,
                            onTap: () => _select(onToggleMute),
                          ),
                          _DesktopChatContextMenuItem(
                            key: const ValueKey('desktop-chat-context-archive'),
                            icon: HeroAppIcons.archiveBox,
                            label: AppStringKeys.chatListArchive,
                            onTap: () => _select(onArchive),
                          ),
                          SizedBox(
                            height: dividerHeight,
                            child: ColoredBox(color: c.divider),
                          ),
                          _DesktopChatContextMenuItem(
                            key: const ValueKey('desktop-chat-context-delete'),
                            icon: HeroAppIcons.trash,
                            label: deleteOrLeaveLabel,
                            color: const Color(0xFFFA5151),
                            onTap: () => _select(onDeleteOrLeave),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DesktopChatContextMenuItem extends StatelessWidget {
  const _DesktopChatContextMenuItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedLabel = label.l10n(context);
    final foreground = color ?? context.colors.textPrimary;
    return AppInteractiveSurface(
      semanticLabel: resolvedLabel,
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        height: DesktopChatContextMenu.rowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: [
              SizedBox(
                width: AppMetric.menuIconSlot,
                child: AppIcon(icon, size: 18, color: foreground),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  resolvedLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: AppTextSize.callout,
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

class SwipeActionItem {
  SwipeActionItem({
    required this.title,
    required this.color,
    required this.onTap,
  });
  final String title;
  final Color color;
  final VoidCallback onTap;
}

/// Wraps a chat row so a left-swipe reveals flush, full-height action blocks.
/// Only one row stays open at a time, coordinated through [openRowId].
class ChatSwipeRow extends StatefulWidget {
  const ChatSwipeRow({
    super.key,
    required this.rowId,
    required this.openRowId,
    required this.onOpenChanged,
    required this.actions,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.requiresLongPressDrag = false,
    this.horizontalSwipeEnabled = true,
    this.pressRippleEnabled = true,
  });

  final int rowId;
  final int? openRowId;
  final ValueChanged<int?> onOpenChanged;
  final List<SwipeActionItem> actions;
  final VoidCallback onTap;
  final Widget child;
  final VoidCallback? onLongPress;
  final GestureTapDownCallback? onSecondaryTapDown;
  final bool requiresLongPressDrag;
  final bool horizontalSwipeEnabled;
  final bool pressRippleEnabled;

  @override
  State<ChatSwipeRow> createState() => _ChatSwipeRowState();
}

class _ChatSwipeRowState extends State<ChatSwipeRow>
    with SingleTickerProviderStateMixin {
  static const double _buttonWidth = 80;
  // Created eagerly in initState so the Ticker is bound while the context is
  // active — a lazy `late` initializer would run on first access in dispose()
  // (for never-swiped rows) and crash on a deactivated-ancestor TickerMode lookup.
  late final AnimationController _controller;
  Animation<double>? _animation;
  VoidCallback? _animationListener;
  double _offset = 0;
  double _longPressStartOffset = 0;
  int? _desktopTouchPointer;
  Offset? _desktopTouchOrigin;
  double _desktopTouchStartOffset = 0;
  VelocityTracker? _desktopTouchVelocity;
  Timer? _desktopTouchLongPressTimer;
  bool _desktopTouchHorizontal = false;
  bool _desktopTouchLongPressTriggered = false;

  double get _totalWidth => widget.actions.length * _buttonWidth;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.responsive,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = AppMotion.duration(context, AppMotion.responsive);
  }

  @override
  void didUpdateWidget(ChatSwipeRow old) {
    super.didUpdateWidget(old);
    final horizontalSwipeWasDisabled =
        old.horizontalSwipeEnabled && !widget.horizontalSwipeEnabled;
    if (horizontalSwipeWasDisabled && widget.openRowId == widget.rowId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !widget.horizontalSwipeEnabled &&
            widget.openRowId == widget.rowId) {
          widget.onOpenChanged(null);
        }
      });
    }
    // Snap shut when horizontal actions are disabled or another row opens.
    if (_offset != 0 &&
        (horizontalSwipeWasDisabled || widget.openRowId != widget.rowId)) {
      _animateTo(0);
    }
  }

  @override
  void dispose() {
    _desktopTouchLongPressTimer?.cancel();
    _clearAnimation();
    _controller.dispose();
    super.dispose();
  }

  void _clearAnimation() {
    final animation = _animation;
    final listener = _animationListener;
    if (animation != null && listener != null) {
      animation.removeListener(listener);
    }
    _animation = null;
    _animationListener = null;
  }

  void _stopAnimation() {
    _controller.stop();
    _clearAnimation();
  }

  void _animateTo(double target) {
    _stopAnimation();
    if (AppMotion.isReduced(context)) {
      setState(() => _offset = target);
      return;
    }
    final anim = Tween<double>(
      begin: _offset,
      end: target,
    ).animate(CurvedAnimation(parent: _controller, curve: AppMotion.standard));
    void listener() => setState(() => _offset = anim.value);
    _animation = anim;
    _animationListener = listener;
    _controller.reset();
    anim.addListener(listener);
    _controller.forward().whenComplete(() {
      _clearAnimation();
      _offset = target;
    });
  }

  double _rubberBandOffset(double value) {
    if (value >= -_totalWidth && value <= 0) return value;
    if (value < -_totalWidth) {
      final extra = -value - _totalWidth;
      return -_totalWidth - extra * 0.28;
    }
    return value * 0.28;
  }

  void _close() {
    _animateTo(0);
    if (widget.openRowId == widget.rowId) widget.onOpenChanged(null);
  }

  void _handleContextRequest() {
    if (_offset != 0) {
      _close();
      return;
    }
    widget.onLongPress?.call();
  }

  void _handleSecondaryTapDown(TapDownDetails details) {
    if (_offset != 0) _close();
    widget.onSecondaryTapDown?.call(details);
  }

  bool _supportsDesktopTouchGestures(TargetPlatform platform) =>
      widget.onSecondaryTapDown != null &&
      (platform == TargetPlatform.windows || platform == TargetPlatform.linux);

  void _handleDesktopTouchPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    if (_desktopTouchPointer != null) {
      _cancelDesktopTouchGesture();
      return;
    }
    _desktopTouchPointer = event.pointer;
    _desktopTouchOrigin = event.position;
    _desktopTouchStartOffset = _offset;
    _desktopTouchVelocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
    _desktopTouchHorizontal = false;
    _desktopTouchLongPressTriggered = false;
    _desktopTouchLongPressTimer = Timer(
      kLongPressTimeout + const Duration(milliseconds: 30),
      _handleDesktopTouchLongPress,
    );
  }

  void _handleDesktopTouchPointerMove(PointerMoveEvent event) {
    if (_desktopTouchPointer != event.pointer) return;
    _desktopTouchVelocity?.addPosition(event.timeStamp, event.position);
    final origin = _desktopTouchOrigin;
    if (origin == null || _desktopTouchLongPressTriggered) return;
    final travel = event.position - origin;
    if (!_desktopTouchHorizontal) {
      if (travel.dx.abs() < kTouchSlop && travel.dy.abs() < kTouchSlop) return;
      _desktopTouchLongPressTimer?.cancel();
      _desktopTouchLongPressTimer = null;
      if (travel.dy.abs() >= travel.dx.abs() ||
          !widget.horizontalSwipeEnabled ||
          widget.requiresLongPressDrag) {
        _cancelDesktopTouchGesture();
        return;
      }
      _desktopTouchHorizontal = true;
      _stopAnimation();
    }
    setState(() {
      _offset = _rubberBandOffset(_desktopTouchStartOffset + travel.dx);
    });
  }

  void _handleDesktopTouchPointerUp(PointerUpEvent event) {
    if (_desktopTouchPointer != event.pointer) return;
    _desktopTouchLongPressTimer?.cancel();
    _desktopTouchVelocity?.addPosition(event.timeStamp, event.position);
    if (_desktopTouchHorizontal) {
      _settle(_desktopTouchVelocity?.getVelocity().pixelsPerSecond.dx ?? 0);
    }
    _resetDesktopTouchGesture();
  }

  void _handleDesktopTouchPointerCancel(PointerCancelEvent event) {
    if (_desktopTouchPointer != event.pointer) return;
    if (_desktopTouchHorizontal) _animateTo(_desktopTouchStartOffset);
    _resetDesktopTouchGesture();
  }

  void _handleDesktopTouchLongPress() {
    final position = _desktopTouchOrigin;
    if (!mounted || _desktopTouchPointer == null || position == null) return;
    _desktopTouchLongPressTimer = null;
    _desktopTouchLongPressTriggered = true;
    _handleSecondaryTapDown(
      TapDownDetails(globalPosition: position, kind: PointerDeviceKind.touch),
    );
  }

  void _cancelDesktopTouchGesture() {
    if (_desktopTouchHorizontal) _animateTo(_desktopTouchStartOffset);
    _desktopTouchLongPressTimer?.cancel();
    _resetDesktopTouchGesture();
  }

  void _resetDesktopTouchGesture() {
    _desktopTouchLongPressTimer?.cancel();
    _desktopTouchLongPressTimer = null;
    _desktopTouchPointer = null;
    _desktopTouchOrigin = null;
    _desktopTouchVelocity = null;
    _desktopTouchHorizontal = false;
    _desktopTouchLongPressTriggered = false;
  }

  void _settle(double velocity) {
    if (velocity < -520 || (velocity <= 360 && _offset < -_totalWidth * 0.38)) {
      _animateTo(-_totalWidth);
      widget.onOpenChanged(widget.rowId);
    } else {
      _animateTo(0);
      if (widget.openRowId == widget.rowId) widget.onOpenChanged(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final desktopTouchGestures = _supportsDesktopTouchGestures(
      Theme.of(context).platform,
    );
    final horizontalDragEnabled =
        widget.horizontalSwipeEnabled &&
        !widget.requiresLongPressDrag &&
        !desktopTouchGestures;
    final rowGesture = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _offset != 0 ? _close() : widget.onTap(),
      onLongPress: desktopTouchGestures || widget.requiresLongPressDrag
          ? null
          : widget.onLongPress == null
          ? null
          : _handleContextRequest,
      onSecondaryTapDown: widget.onSecondaryTapDown == null
          ? null
          : _handleSecondaryTapDown,
      onLongPressStart: (_) {
        _stopAnimation();
        _longPressStartOffset = _offset;
      },
      onLongPressMoveUpdate: widget.requiresLongPressDrag
          ? (details) {
              setState(() {
                _offset = _rubberBandOffset(
                  _longPressStartOffset + details.localOffsetFromOrigin.dx,
                );
              });
            }
          : null,
      onLongPressEnd: (details) {
        if (widget.requiresLongPressDrag) {
          _settle(details.velocity.pixelsPerSecond.dx);
        }
      },
      onHorizontalDragStart: !horizontalDragEnabled
          ? null
          : (_) => _stopAnimation(),
      onHorizontalDragUpdate: !horizontalDragEnabled
          ? null
          : (details) {
              setState(
                () => _offset = _rubberBandOffset(_offset + details.delta.dx),
              );
            },
      onHorizontalDragEnd: !horizontalDragEnabled
          ? null
          : (details) => _settle(details.primaryVelocity ?? 0),
      child: widget.child,
    );
    final interactiveRow = desktopTouchGestures
        ? Listener(
            onPointerDown: _handleDesktopTouchPointerDown,
            onPointerMove: _handleDesktopTouchPointerMove,
            onPointerUp: _handleDesktopTouchPointerUp,
            onPointerCancel: _handleDesktopTouchPointerCancel,
            child: rowGesture,
          )
        : rowGesture;
    // At rest the row covers the blocks completely, so building them costs one
    // text layout + one paint per action on every row of every list rebuild.
    final actionsRevealed = _offset != 0 || widget.openRowId == widget.rowId;
    return ClipRect(
      child: Stack(
        children: [
          // Revealed action blocks behind the row.
          Positioned.fill(
            child: !actionsRevealed
                ? const SizedBox.shrink()
                : Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: _totalWidth,
                      child: Row(
                        children: [
                          for (final item in widget.actions)
                            GestureDetector(
                              onTap: () {
                                item.onTap();
                                setState(() => _offset = 0);
                                if (widget.openRowId == widget.rowId) {
                                  widget.onOpenChanged(null);
                                }
                              },
                              child: Container(
                                width: _buttonWidth,
                                color: item.color,
                                alignment: Alignment.center,
                                child: Text(
                                  item.title.l10n(context),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: AppTextSize.body,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
          // The row, sliding left to uncover the blocks.
          Transform.translate(
            offset: Offset(_offset, 0),
            child: widget.pressRippleEnabled
                ? AppPressRipple(child: interactiveRow)
                : interactiveRow,
          ),
        ],
      ),
    );
  }
}
