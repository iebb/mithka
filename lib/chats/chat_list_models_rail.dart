part of 'chat_list_view.dart';

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
                      // The count floats over the glyph's top-right corner,
                      // like the app-icon badge above the rail, so the label
                      // keeps the full rail width.
                      SizedBox.square(
                        dimension: 22,
                        child: Stack(
                          clipBehavior: Clip.none,
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
                            if (showBadges &&
                                !filter.isAll &&
                                filter.unreadChatCount > 0)
                              Positioned(
                                key: ValueKey(
                                  'side-folder-badge-${filter.folderId}',
                                ),
                                right: -12,
                                top: -6,
                                child: FolderUnreadBadge(
                                  label: badgeOverflowMode.format(
                                    filter.unreadChatCount,
                                  ),
                                  accent: filter.hasUnmutedUnread,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
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
    this.pendingForwardHandoff,
  });

  ChatListSelection.fromChat(
    ChatSummary chat, {
    this.composerFocusRequestId = 0,
  }) : chatId = chat.id,
       title = chat.title,
       chat = chat,
       resolvedKind = chat.kind,
       initialMessageId = null,
       forumTopicId = null,
       pendingForwardHandoff = null;

  final int chatId;
  final String title;
  final ChatSummary? chat;
  final ChatKind? resolvedKind;
  final int? initialMessageId;

  /// The forum topic shown as an ordinary transcript when topics are folded
  /// into the group chat; null shows the whole chat.
  final int? forumTopicId;
  final int composerFocusRequestId;

  /// A forward picked in another chat (forward-to-chat). Non-null only on the
  /// selection a forward flow creates; it is handed to the transcript's
  /// composer once and never re-applied on rebuilds.
  final ForwardMessagesHandoff? pendingForwardHandoff;

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
    pendingForwardHandoff: pendingForwardHandoff,
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
    pendingForwardHandoff: pendingForwardHandoff,
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
    this.onToggleMute,
  });

  final List<ChatSummary> Function() chatsProvider;
  final Listenable updates;
  final ValueChanged<ChatSummary> onClearUnread;
  final ValueChanged<ChatSummary>? onUnarchive;
  final ValueChanged<ChatSummary>? onToggleMute;
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

/// Scroll physics for the chat list.
///
/// With a pull-down archive slot, top overscroll must move the viewport (the
/// archive row is revealed by the negative offset itself), so the list keeps
/// elastic physics on every platform. Without the slot there is nothing to
/// reveal and the list falls back to the platform default — an Android-style
/// glow with zero content displacement instead of a long rubber-band. This
/// mirrors how the reference client gates its archive pull-down on
/// `hasHiddenArchive()`: the elasticity is a property of the interaction being
/// available, not of the list.
///
/// While a folder swipe drag is steering the pager [folderDragActive] the list
/// is not draggable at all, so a vertical scroll already in flight is cancelled
/// instead of stacking on top of the horizontal folder travel — the Flutter
/// counterpart of the reference client calling
/// requestDisallowInterceptTouchEvent from its pager.
///
/// The branches use different physics *types* on purpose: Scrollable only
/// rebuilds its ScrollPosition when the physics type chain changes, so a
/// same-type physics whose flag flipped would keep driving the position with
/// the stale instance.
ScrollPhysics _chatListScrollPhysics(
  bool pullDownArchiveSlot, {
  bool folderDragActive = false,
}) => folderDragActive
    ? const NeverScrollableScrollPhysics()
    : pullDownArchiveSlot
    ? const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics())
    : const AlwaysScrollableScrollPhysics();

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

/// Whether forward scrolling has moved far enough to collapse the revealed
/// archive row. The travel threshold is half a row; the actual departure is a
/// single collapse animation that folds the archive row and the search row
/// away together (see [_pinnedSearchPill] and [ChatListPullDownArchiveSlot],
/// which share one AnimatedSize clock).
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
                // Own layer: the spin runs for as long as the app is
                // connecting and would otherwise repaint the whole header.
                child: RepaintBoundary(
                  child: CircularProgressIndicator(
                    strokeWidth: 1.4,
                    color: c.textSecondary,
                    backgroundColor: c.textTertiary.withValues(alpha: 0.22),
                  ),
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
            // The status word is the only flexible part of the row: a scaled
            // up label (or a long locale) shrinks it to an ellipsis instead of
            // overflowing the header beside the dot.
            Flexible(
              child: Text(
                label,
                key: labelKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppTextSize.tiny,
                  color: muted ? c.textTertiary : c.textSecondary,
                ),
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
