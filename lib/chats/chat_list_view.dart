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
import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../app/adaptive_split_layout.dart';
import '../app/app_navigator.dart';
import '../app/desktop_chat_list_title_bar_anchors.dart';
import '../app/desktop_chat_window.dart';
import '../auth/account_store.dart';
import '../auth/auth_manager.dart';
import '../channels/forum_topic_browser_view.dart';
import '../chat/chat_view.dart';
import '../chat/custom_emoji.dart';
import '../chat/link_handler.dart';
import '../communities/community_models.dart';
import '../communities/community_view.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/app_press_ripple.dart';
import '../components/drawer_controller.dart' as dc;
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../contacts/add_people_view.dart';
import '../contacts/create_group_view.dart';
import '../l10n/telegram_language_controller.dart';
import '../profile/emoji_status_picker.dart';
import '../security/local_app_lock_controller.dart';
import '../settings/edit_field_view.dart';
import '../settings/topic_group_display_mode.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'archived_chats_view.dart';
import 'chat_delete_dialog.dart';
import 'chat_delete_policy.dart';
import 'chat_list_preview.dart';
import 'chat_list_view_model.dart';
import 'chat_row_view.dart';
import 'filtered_chats_view.dart';
import 'qr_scanner_view.dart';
import 'search_view.dart';

class ChatListController extends ChangeNotifier {
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

class ChatListSelection {
  const ChatListSelection({
    required this.chatId,
    required this.title,
    this.chat,
    this.resolvedKind,
    this.initialMessageId,
    this.composerFocusRequestId = 0,
  });

  ChatListSelection.fromChat(
    ChatSummary chat, {
    this.composerFocusRequestId = 0,
  }) : chatId = chat.id,
       title = chat.title,
       chat = chat,
       resolvedKind = chat.kind,
       initialMessageId = null;

  final int chatId;
  final String title;
  final ChatSummary? chat;
  final ChatKind? resolvedKind;
  final int? initialMessageId;
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
  });

  final List<ChatSummary> Function() chatsProvider;
  final Listenable updates;
  final ValueChanged<ChatSummary> onClearUnread;
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
}) {
  if (!isWeb &&
      isDesktopTargetPlatform(platform) &&
      requested == ArchivedChatsDisplayMode.pullDown) {
    return ArchivedChatsDisplayMode.firstPosition;
  }
  return requested;
}

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

  bool get isActive => _activePositions.isNotEmpty;
  bool get suppressRowSwipes => isActive && _peakPointerCount > 1;

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
    }
    if (_peakPointerCount > 3) _blocked = true;
    return true;
  }

  void pointerMove({required int pointer, required Offset position}) {
    if (_activePositions.containsKey(pointer)) {
      _activePositions[pointer] = position;
    }
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
    final decision = !_blocked && _mode == currentMode
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
  static const _folderTransitionDuration = Duration(milliseconds: 210);
  static const _folderTransitionDistance = 22.0;
  static const _searchPillExtent =
      AppSpacing.md + AppMetric.searchHeight + AppSpacing.sm;

  final ChatListViewModel _model = ChatListViewModel();
  late final ScrollController _scrollController = _newScrollController();
  late final AnimationController _folderTransitionController;
  late final CurvedAnimation _folderTransition;
  double _folderTransitionDirection = 1;
  String _meName = AppStrings.t(AppStringKeys.chatMeLabel);
  TdFileRef? _mePhoto;
  int _meStatusId = 0; // current emoji status, shown after the name
  bool _meIsPremium = false;
  int? _meId;
  StreamSubscription? _userSub;
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
  bool _reactivationSyncScheduled = false;
  int _lastVisibleRows = 1;
  final ChatListSwipeSession _chatListSwipeSession = ChatListSwipeSession();
  final ScrollController _folderTabScrollController = ScrollController();
  final Map<int?, GlobalKey> _folderTabKeys = {};
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
    _folderTransitionController = AnimationController(
      vsync: this,
      duration: _folderTransitionDuration,
      value: 1,
    );
    _folderTransition = CurvedAnimation(
      parent: _folderTransitionController,
      curve: Curves.easeOutCubic,
    );
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
        _reactivationSyncScheduled) {
      return;
    }
    _reactivationSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reactivationSyncScheduled = false;
      if (!mounted || !_viewTickerEnabled || !_modelDirtyWhileInactive) return;
      _onModel();
    });
  }

  void _onModel() {
    if (!mounted) return;
    if (!_viewTickerEnabled) {
      _modelDirtyWhileInactive = true;
      return;
    }
    _modelDirtyWhileInactive = false;
    if (_model.notice != null && mounted) {
      final text = _model.notice!;
      _model.clearNotice();
      showToast(context, text);
    }
    setState(() {});
    if (_pendingScrollToFirstUnreadRequest != null) {
      _tryScrollToFirstUnread();
    }
  }

  void _onScroll() {
    if (!mounted) return;
    final positions = _scrollController.positions;
    if (positions.length != 1) return;
    final position = positions.single;
    final theme = context.read<ThemeController>();
    final rowHeight = theme.rowHeight + 0.5;
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
    if (position.extentAfter < theme.rowHeight * 8) {
      _model.loadMore();
    }
  }

  @override
  void dispose() {
    _dismissDesktopChatMenu();
    _dismissDesktopPlusMenu();
    _userSub?.cancel();
    widget.controller?.removeListener(_onControllerRequest);
    _folderTransition.dispose();
    _folderTransitionController.dispose();
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
      final mode = await TopicGroupDisplayPreference.load();
      if (!mounted) return;
      if (mode.isChat) {
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
      final railChats = <int, ChatSummary>{};
      for (final summary in [..._model.chats, ..._model.archived]) {
        railChats[summary.id] = summary;
      }
      unawaited(
        pushAppChatRoute(
          context,
          _standardEntryRoute(
            ForumTopicBrowserView(
              chats: railChats.values.toList(),
              initialChat: chat,
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

  void _openCommunity(CommunityGroupEntry entry) {
    if (!context.read<ThemeController>().communitiesEnabled) return;
    final selection = CommunityListSelection(
      community: entry.community,
      chats: _model.chatsInCommunity(entry.community.id),
      viewableChats: _model.viewableChatsInCommunity(entry.community.id),
      onCollapsedChanged: (value) =>
          _model.setCommunityCollapsed(entry.community.id, value),
      updates: _model,
      chatsProvider: () => _model.chatsInCommunity(entry.community.id),
      viewableChatsProvider: () =>
          _model.viewableChatsInCommunity(entry.community.id),
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

    setState(() {
      _showPlusMenu = false;
      _showFilterMenu = false;
    });
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _DesktopTitleBarPlusMenuOverlay(
        link: DesktopChatListTitleBarAnchors.add,
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

  void _selectFilter(ChatFilterOption filter) {
    setState(() => _showFilterMenu = false);
    _switchToFilter(filter);
  }

  void _switchToFilter(ChatFilterOption filter) {
    final currentFolderId = _model.selectedFilter.folderId;
    if (filter.folderId == currentFolderId) return;

    final filters = _model.filters;
    final currentIndex = filters.indexWhere(
      (candidate) => candidate.folderId == currentFolderId,
    );
    final targetIndex = filters.indexWhere(
      (candidate) => candidate.folderId == filter.folderId,
    );
    final direction = currentIndex >= 0 && targetIndex >= 0
        ? (targetIndex > currentIndex ? 1.0 : -1.0)
        : 1.0;

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    setState(() {
      _folderTransitionDirection = direction;
      _openSwipeChat = null;
      _archiveRevealed = false;
      _refreshPullDistance = 0;
    });
    _model.selectFilter(filter);
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _folderTransitionController.value = 1;
    } else {
      _folderTransitionController.forward(from: 0);
    }
    _ensureFolderTabVisible(filter.folderId);
  }

  void _ensureFolderTabVisible(int? folderId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _folderTabKeys[folderId];
      final ctx = key?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 250),
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

    var itemIndex = entryIndex;
    if (_model.isAllFilter && _model.filtered.isNotEmpty) itemIndex++;
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
      if (archiveIndex <= entryIndex) itemIndex++;
    }
    return chatListItemScrollOffset(
      itemIndex: itemIndex,
      rowHeight: context.read<ThemeController>().rowHeight,
      maxScrollExtent: _scrollController.position.maxScrollExtent,
      leadingExtent: _leadingListControlsExtent(
        context.read<ThemeController>(),
      ),
    );
  }

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
    final folderMode = context.watch<ThemeController>().chatFolderDisplayMode;
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
              if (folderMode == ChatFolderDisplayMode.tabs &&
                  _model.filters.length > 1)
                _chatFolderTabs(),
              Expanded(
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _handleGesturePointerDown,
                  onPointerMove: _handleGesturePointerMove,
                  onPointerUp: _handleGesturePointerUp,
                  onPointerCancel: _handleGesturePointerCancel,
                  child: _chatList(),
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
        _switchFolderBySwipe(decision!.horizontalDelta < 0 ? -1000 : 1000);
      case ChatListSwipeAction.switchAccounts:
        _switchAccountBySwipe(decision!.horizontalDelta);
      case ChatListSwipeAction.none:
      case null:
        return;
    }
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
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: AppSpacing.md + AppSpacing.xxs,
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => context.read<dc.DrawerController>().open(),
              child: PhotoAvatar(
                title: _meName,
                photo: _mePhoto,
                size: AppMetric.headerAvatarSize,
                allowAnimation: false,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
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
                  Row(
                    children: [
                      Container(
                        width: AppMetric.onlineDot,
                        height: AppMetric.onlineDot,
                        decoration: BoxDecoration(
                          color: AppTheme.onlineDot,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        telegramPresenceText(TelegramPresenceLabel.online),
                        style: TextStyle(
                          fontSize: AppTextSize.tiny,
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
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
              behavior: HitTestBehavior.opaque,
              onTap: _openPlusMenu,
              child: SizedBox(
                width: AppMetric.hitTarget,
                height: AppMetric.hitTarget,
                child: AppIcon(
                  HeroAppIcons.plus,
                  size: AppIconSize.add,
                  color: c.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chatFolderTabs() {
    final c = context.colors;
    final selectedFolderId = _model.selectedFilter.folderId;
    final transitionDuration =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false
        ? Duration.zero
        : _folderTransitionDuration;
    return Container(
      height: 44,
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
          final key = _folderTabKeys.putIfAbsent(
            filter.folderId,
            () => GlobalKey(),
          );
          return GestureDetector(
            key: key,
            behavior: HitTestBehavior.opaque,
            onTap: () => _selectFilter(filter),
            child: SizedBox(
              height: 44,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(
                        filter.isAll ? HeroAppIcons.inbox : HeroAppIcons.folder,
                        size: 17,
                        color: selected ? AppTheme.brand : c.textSecondary,
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
                    ],
                  ),
                  const SizedBox(height: 7),
                  AnimatedContainer(
                    duration: transitionDuration,
                    curve: Curves.easeOutCubic,
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.brand : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      )._withChatFolderMouseDrag(context),
    );
  }

  // MARK: - Search

  Widget _searchPill() {
    final c = context.colors;
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
                fontSize: AppTextSize.callout,
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

  Widget _chatList() {
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
          final rowH = theme.rowHeight + 0.5;
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
              padding: EdgeInsets.zero,
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
              padding: EdgeInsets.zero,
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
              padding: EdgeInsets.zero,
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

          list = NotificationListener<ScrollNotification>(
            onNotification: _handleChatListPull,
            child: list,
          );
          // One-finger horizontal drags belong exclusively to ChatSwipeRow.
          // Folder and account switching are observed by the two/three-finger
          // raw-pointer handler around the complete chat list.
          list = _folderSwitchTransition(list);

          return list;
        },
      ),
    );
  }

  double _leadingListControlsExtent(ThemeController theme) {
    if (!widget.desktopSidebar) {
      return theme.showChatListSearch ? _searchPillExtent : 0;
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
      rowHeight: rowHeight,
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

  Widget _folderSwitchTransition(Widget child) {
    // Keep one ListView mounted: retaining outgoing and incoming children would
    // attach the shared scroll controller to both during the transition.
    return ClipRect(
      child: AnimatedBuilder(
        animation: _folderTransition,
        child: child,
        builder: (context, child) {
          final progress = _folderTransition.value;
          return Opacity(
            opacity: 0.78 + 0.22 * progress,
            child: Transform.translate(
              offset: Offset(
                _folderTransitionDirection *
                    _folderTransitionDistance *
                    (1 - progress),
                0,
              ),
              child: child,
            ),
          );
        },
      ),
    );
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

  Widget _swipeRow(ChatSummary chat) {
    final selected = widget.selectedChatId == chat.id;
    final swipeMode = context.watch<ThemeController>().chatListSwipeMode;
    final desktopContextMenu =
        !kIsWeb && isDesktopTargetPlatform(defaultTargetPlatform);
    final actions = chat.isPinned
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
      horizontalSwipeEnabled:
          !desktopContextMenu &&
          chatListRowSwipeActionsEnabled(
            mode: swipeMode,
            multiTouchActive: _chatListSwipeSession.suppressRowSwipes,
          ),
      pressRippleEnabled: !desktopContextMenu,
      actions: actions,
      child: ChatListSelectionHighlight(
        selected: selected,
        child: ChatRowView(
          chat: chat,
          selected: selected,
          onClearUnread: () => _model.markRead(chat),
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

    entry = OverlayEntry(
      builder: (_) => DesktopChatContextMenu(
        anchor: anchor,
        isPinned: chat.isPinned,
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
        onDeleteOrLeave: () => unawaited(_confirmDeleteChat(chat)),
      ),
    );
    _desktopChatMenuEntry = entry;
    overlay.insert(entry);
  }

  Future<void> _openChatInSeparateWindow(ChatSummary chat) async {
    final theme = context.read<ThemeController>();
    final accounts = context.read<AccountStore>();
    final activeAccount = accounts.summaries
        .where((account) => account.slot == accounts.activeSlot)
        .firstOrNull;
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
    final accounts = context.read<AccountStore>();
    final activeAccount = accounts.summaries
        .where((account) => account.slot == accounts.activeSlot)
        .firstOrNull;
    final avatarPath = activeAccount?.avatarPath?.trim();
    unawaited(
      showChatListPreview(
        context,
        chat: chat,
        meName: activeAccount?.name,
        mePhoto: avatarPath == null || avatarPath.isEmpty
            ? null
            : TdFileRef(id: 0, localPath: avatarPath),
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
            label: chat.isPinned
                ? AppStringKeys.chatListUnpin
                : AppStringKeys.chatInfoPin,
            icon: HeroAppIcons.thumbtack,
            onSelected: () => _model.togglePin(chat),
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
      final message = error is TdError ? error.message : error.toString();
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

  PageRoute<T> _standardEntryRoute<T>(Widget child) {
    return AppPageRoute<T>(pageBuilder: (_, _, _) => child);
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
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArchivedChatsView(
          chats: _model.archived,
          onClearUnread: _model.markRead,
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
    required this.link,
    required this.onDismiss,
    required this.child,
  });

  final LayerLink link;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onDismiss,
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.12)),
        ),
        CompositedTransformFollower(
          link: link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 6),
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
    final rowHeight = context.watch<ThemeController>().rowHeight;
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
    return Material(
      color: Colors.transparent,
      child: Container(
        width: AppMetric.menuWidth,
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
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
                  height: AppMetric.menuRowHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxl,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: AppMetric.menuIconSlot,
                          child: AppIcon(
                            item.$1,
                            size: AppIconSize.lg + 1,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xl),
                        Expanded(
                          child: Text(
                            item.$2.l10n(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppTextSize.bodyLarge,
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
        width: AppMetric.menuWidth,
        constraints: const BoxConstraints(maxHeight: 360),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
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
                height: AppMetric.menuRowHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxl,
                  ),
                  child: Row(
                    children: [
                      AppIcon(
                        filter.isAll ? HeroAppIcons.inbox : HeroAppIcons.folder,
                        size: AppIconSize.lg + 1,
                        color: c.textPrimary,
                      ),
                      const SizedBox(width: AppSpacing.xl),
                      Expanded(
                        child: Text(
                          filter.title.l10n(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppTextSize.bodyLarge,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      if (selectedFilter)
                        AppIcon(
                          HeroAppIcons.check,
                          size: 18,
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

  double get _menuHeight =>
      verticalPadding * 2 +
      rowHeight * (onOpenSeparateWindow == null ? 4 : 5) +
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
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.card,
                      border: Border.all(color: c.divider, width: 0.5),
                      borderRadius: BorderRadius.circular(10),
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
      borderRadius: BorderRadius.circular(6),
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
    final horizontalDragEnabled =
        widget.horizontalSwipeEnabled && !widget.requiresLongPressDrag;
    final rowGesture = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _offset != 0 ? _close() : widget.onTap(),
      onLongPress: widget.requiresLongPressDrag
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
    return ClipRect(
      child: Stack(
        children: [
          // Revealed action blocks behind the row.
          Positioned.fill(
            child: Align(
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
                ? AppPressRipple(child: rowGesture)
                : rowGesture,
          ),
        ],
      ),
    );
  }
}
