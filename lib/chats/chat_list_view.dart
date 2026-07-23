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

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../app/app_navigator.dart';
import '../auth/account_store.dart';
import '../auth/auth_manager.dart';
import '../channels/forum_topic_browser_view.dart';
import '../chat/chat_view.dart';
import '../chat/custom_emoji.dart';
import '../chat/link_handler.dart';
import '../chat/saved_messages_view.dart';
import '../communities/community_models.dart';
import '../communities/community_view.dart';
import '../components/app_icons.dart';
import '../components/drawer_controller.dart' as dc;
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../contacts/add_people_view.dart';
import '../contacts/create_group_view.dart';
import '../l10n/telegram_language_controller.dart';
import '../profile/emoji_status_picker.dart';
import '../settings/edit_field_view.dart';
import '../settings/topic_group_display_mode.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'archived_chats_view.dart';
import 'chat_delete_dialog.dart';
import 'chat_list_view_model.dart';
import 'chat_row_view.dart';
import 'filtered_chats_view.dart';
import 'qr_scanner_view.dart';
import 'search_view.dart';

class ChatListController extends ChangeNotifier {
  int _scrollToFirstUnreadRequests = 0;
  int _toggleFirstUnreadRequests = 0;
  int _markAllReadRequests = 0;
  bool _toggleRequestMayHaveUnread = false;
  int get scrollToFirstUnreadRequests => _scrollToFirstUnreadRequests;
  int get toggleFirstUnreadRequests => _toggleFirstUnreadRequests;
  int get markAllReadRequests => _markAllReadRequests;
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
}

class ChatListSelection {
  const ChatListSelection({
    required this.chatId,
    required this.title,
    this.chat,
    this.initialMessageId,
  });

  ChatListSelection.fromChat(ChatSummary chat)
    : this(chatId: chat.id, title: chat.title, chat: chat);

  final int chatId;
  final String title;
  final ChatSummary? chat;
  final int? initialMessageId;

  bool get isForum => chat?.isForum ?? false;
}

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
    this.selectedChatId,
    this.selectedCommunityId,
  });

  final ChatListController? controller;
  final ValueChanged<ChatListSelection>? onChatSelected;
  final ValueChanged<CommunityListSelection>? onCommunitySelected;
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
  int _pendingScrollAttempts = 0;
  bool _toggleUnreadTargetNext = true;
  bool _archiveRevealed = false;
  double _archivePullDistance = 0;
  double _archiveDragOffset = 0;
  double _refreshPullDistance = 0;
  bool _isRefreshing = false;
  int _lastVisibleRows = 1;
  final Map<int, Offset> _gesturePointers = <int, Offset>{};
  Offset? _threeFingerSwipeOrigin;
  bool _threeFingerSwipeHandled = false;

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
    _userSub = TdClient.shared.subscribe().listen((u) {
      if (u.type != 'updateUser') return;
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

  void _onModel() {
    if (_model.notice != null && mounted) {
      final text = _model.notice!;
      _model.clearNotice();
      showToast(context, text);
    }
    if (mounted) setState(() {});
    if (_pendingScrollToFirstUnreadRequest != null) {
      _tryScrollToFirstUnread();
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final rowHeight = context.read<ThemeController>().rowHeight;
    if (_scrollController.position.extentAfter < rowHeight * 8) {
      _model.loadMore();
    }
  }

  @override
  void dispose() {
    _userSub?.cancel();
    widget.controller?.removeListener(_onControllerRequest);
    _folderTransition.dispose();
    _folderTransitionController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
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

  Future<void> _openChat(ChatSummary chat) async {
    final onChatSelected = widget.onChatSelected;
    if (onChatSelected != null) {
      onChatSelected(ChatListSelection.fromChat(chat));
      return;
    }
    if (chat.isSavedMessages) {
      final bookmarkView = context
          .read<ThemeController>()
          .savedMessagesBookmarkView;
      unawaited(
        pushAppChatRoute(
          context,
          _chatEntryRoute(
            bookmarkView
                ? const SavedMessagesView()
                : ChatView(
                    chatId: chat.id,
                    title: AppStrings.t(AppStringKeys.savedMessages),
                    seedMessage: chat.lastChatMessage,
                  ),
          ),
        ),
      );
      return;
    }
    if (chat.isForum) {
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
          _chatEntryRoute(
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
      _archivePullDistance = 0;
      _archiveDragOffset = 0;
      _refreshPullDistance = 0;
    });
    _model.selectFilter(filter);
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _folderTransitionController.value = 1;
    } else {
      _folderTransitionController.forward(from: 0);
    }
  }

  void _onControllerRequest() {
    final markAllRequest = widget.controller?.markAllReadRequests ?? 0;
    if (markAllRequest > _lastHandledMarkAllReadRequest) {
      _lastHandledMarkAllReadRequest = markAllRequest;
      _model.markAllRead();
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
    final archiveMode = context
        .read<ThemeController>()
        .archivedChatsDisplayMode;
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
      leadingExtent: context.read<ThemeController>().showChatListSearch
          ? _searchPillExtent
          : 0,
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
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleGesturePointerDown,
      onPointerMove: _handleGesturePointerMove,
      onPointerUp: _handleGesturePointerEnd,
      onPointerCancel: _handleGesturePointerEnd,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            color: c.background,
            child: Column(
              children: [
                _header(),
                if (folderMode == ChatFolderDisplayMode.tabs &&
                    _model.filters.length > 1)
                  _chatFolderTabs(),
                Expanded(child: _chatList()),
              ],
            ),
          ),
          if (_showPlusMenu) _plusMenuOverlay(),
          if (folderMode == ChatFolderDisplayMode.menu && _showFilterMenu)
            _filterMenuOverlay(),
        ],
      ),
    );
  }

  Offset _gestureCentroid() {
    var dx = 0.0;
    var dy = 0.0;
    for (final position in _gesturePointers.values) {
      dx += position.dx;
      dy += position.dy;
    }
    return Offset(dx / _gesturePointers.length, dy / _gesturePointers.length);
  }

  void _handleGesturePointerDown(PointerDownEvent event) {
    _gesturePointers[event.pointer] = event.position;
    if (_gesturePointers.length == 3) {
      _threeFingerSwipeOrigin = _gestureCentroid();
      _threeFingerSwipeHandled = false;
    } else if (_gesturePointers.length > 3) {
      _threeFingerSwipeOrigin = null;
    }
  }

  void _handleGesturePointerMove(PointerMoveEvent event) {
    if (!_gesturePointers.containsKey(event.pointer)) return;
    _gesturePointers[event.pointer] = event.position;
    final origin = _threeFingerSwipeOrigin;
    if (_gesturePointers.length != 3 ||
        origin == null ||
        _threeFingerSwipeHandled) {
      return;
    }
    final delta = _gestureCentroid() - origin;
    if (delta.dx.abs() < 64 || delta.dx.abs() < delta.dy.abs() * 1.25) return;
    _threeFingerSwipeHandled = true;
    _performThreeFingerSwipe(delta.dx);
  }

  void _handleGesturePointerEnd(PointerEvent event) {
    _gesturePointers.remove(event.pointer);
    if (_gesturePointers.length < 3) {
      _threeFingerSwipeOrigin = null;
      _threeFingerSwipeHandled = false;
    }
  }

  void _performThreeFingerSwipe(double horizontalDelta) {
    switch (context.read<ThemeController>().threeFingerSwipeBehavior) {
      case ThreeFingerSwipeBehavior.switchFolders:
        _switchFolderBySwipe(horizontalDelta < 0 ? -1000 : 1000);
        return;
      case ThreeFingerSwipeBehavior.switchAccounts:
        _switchAccountBySwipe(horizontalDelta);
        return;
      case ThreeFingerSwipeBehavior.disabled:
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
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() {
                _showPlusMenu = true;
                _showFilterMenu = false;
              }),
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
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: _model.filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 28),
        itemBuilder: (context, index) {
          final filter = _model.filters[index];
          final selected = filter.folderId == selectedFolderId;
          return GestureDetector(
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
      ),
    );
  }

  // MARK: - Search

  Widget _searchPill() {
    final c = context.colors;
    return GestureDetector(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const SearchView())),
      child: Container(
        color: c.listHeaderTint,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
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
      ),
    );
  }

  // MARK: - List

  Widget _chatList() {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    final showSearch = theme.showChatListSearch;
    final archiveMode = theme.archivedChatsDisplayMode;
    return Container(
      color: c.background,
      child: LayoutBuilder(
        builder: (context, geo) {
          final rowH = theme.rowHeight + 0.5;
          final searchHeight = showSearch ? _searchPillExtent : 0.0;
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
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.zero,
              itemCount:
                  visibleRows +
                  (showSearch ? 1 : 0) +
                  (hasPullDownArchiveSlot ? 1 : 0),
              itemBuilder: (context, index) {
                if (showSearch && index == 0) {
                  return _archivePullSearchPill(hasPullDownArchiveSlot);
                }
                if (hasPullDownArchiveSlot &&
                    index ==
                        chatListPullDownArchiveItemIndex(
                          showSearch: showSearch,
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
                if (showSearch) _archivePullSearchPill(hasPullDownArchiveSlot),
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
                  (showSearch ? 1 : 0) +
                  entries.length +
                  (hasPullDownArchiveSlot ? 1 : 0) +
                  (showInlineArchive ? 1 : 0) +
                  (hasFiltered ? 1 : 0),
              itemBuilder: (context, index) {
                if (showSearch && index == 0) {
                  return _archivePullSearchPill(hasPullDownArchiveSlot);
                }
                final contentIndex = showSearch ? index - 1 : index;
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
            onNotification: (notification) => _handleChatListPull(
              notification,
              archiveEnabled:
                  hasArchive &&
                  archiveMode == ArchivedChatsDisplayMode.pullDown,
              rowHeight: rowH,
            ),
            child: list,
          );
          if (!theme.chatListFolderSwipeSwitching ||
              _model.filters.length < 2) {
            // No horizontal folder gesture wrapper is needed.
          } else {
            list = GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (details) =>
                  _switchFolderBySwipe(details.primaryVelocity),
              child: list,
            );
          }
          list = _folderSwitchTransition(list);

          return list;
        },
      ),
    );
  }

  Widget _archivePullSearchPill(bool pinDuringArchivePull) {
    final offset = pinDuringArchivePull ? -_archiveDragOffset : 0.0;
    return Transform.translate(offset: Offset(0, offset), child: _searchPill());
  }

  Widget _pullDownArchiveSlot({
    required double rowHeight,
    required bool visible,
  }) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.none,
      child: visible
          ? Transform.translate(
              offset: Offset(0, -_archiveDragOffset),
              child: SizedBox(height: rowHeight, child: _assistantRow()),
            )
          : const SizedBox(width: double.infinity),
    );
  }

  bool _handleChatListPull(
    ScrollNotification notification, {
    required bool archiveEnabled,
    required double rowHeight,
  }) {
    _handleArchivePull(
      notification,
      enabled: archiveEnabled,
      rowHeight: rowHeight,
    );
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

  bool _handleArchivePull(
    ScrollNotification notification, {
    required bool enabled,
    required double rowHeight,
  }) {
    if (!enabled) return false;
    if (notification is ScrollStartNotification) {
      _archivePullDistance = 0;
      if (_archiveDragOffset != 0) {
        setState(() => _archiveDragOffset = 0);
      }
    } else if (notification is OverscrollNotification &&
        notification.overscroll < 0) {
      _archivePullDistance = math.max(
        _archivePullDistance + -notification.overscroll,
        math.max(0, -notification.metrics.pixels),
      );
      final positionPull = math
          .max(0.0, -notification.metrics.pixels)
          .toDouble();
      _updateArchivePullVisual(
        rowHeight,
        visualPull: positionPull > 0
            ? positionPull
            : math.min(_archivePullDistance, rowHeight * 2),
      );
    } else if (notification is ScrollUpdateNotification) {
      if (notification.metrics.pixels < 0) {
        _archivePullDistance = -notification.metrics.pixels;
        _updateArchivePullVisual(
          rowHeight,
          visualPull: -notification.metrics.pixels,
        );
      } else if (_archiveRevealed &&
          notification.metrics.pixels > rowHeight * 0.5) {
        setState(() {
          _archiveRevealed = false;
          _archiveDragOffset = 0;
        });
      } else if (_archiveDragOffset != 0) {
        setState(() => _archiveDragOffset = 0);
      }
    } else if (notification is ScrollEndNotification) {
      _archivePullDistance = 0;
      if (_archiveDragOffset != 0) {
        setState(() => _archiveDragOffset = 0);
      }
    }
    return false;
  }

  void _updateArchivePullVisual(
    double rowHeight, {
    required double visualPull,
  }) {
    final shouldReveal =
        _archiveRevealed || _archivePullDistance >= rowHeight * 0.45;
    final nextOffset = shouldReveal ? visualPull : 0.0;
    if (_archiveRevealed == shouldReveal &&
        (_archiveDragOffset - nextOffset).abs() < 0.5) {
      return;
    }
    setState(() {
      _archiveRevealed = shouldReveal;
      _archiveDragOffset = nextOffset;
    });
  }

  void _switchFolderBySwipe(double? velocity) {
    if (velocity == null || velocity.abs() < 240) return;
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
    final theme = context.watch<ThemeController>();
    final holdForActions =
        theme.chatListSwipeBehavior == ChatListSwipeBehavior.switchFolders &&
        theme.chatListHoldSwipeActions;
    if (theme.disableChatListSwipeActions && !holdForActions) {
      return GestureDetector(
        key: ValueKey(chat.id),
        behavior: HitTestBehavior.opaque,
        onTap: () => _openChat(chat),
        child: ChatRowView(
          chat: chat,
          selected: widget.selectedChatId == chat.id,
          onClearUnread: () => _model.markRead(chat),
        ),
      );
    }
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
      actions: actions,
      requiresLongPressDrag: holdForActions,
      child: ChatRowView(
        chat: chat,
        selected: widget.selectedChatId == chat.id,
        onClearUnread: () => _model.markRead(chat),
      ),
    );
  }

  Future<void> _confirmDeleteChat(ChatSummary chat) async {
    final isGroupOrChannel =
        chat.kind == ChatKind.group || chat.kind == ChatKind.channel;
    final capabilities = await _model.deleteCapabilities(chat);
    if (!mounted) return;
    if (!capabilities.canDelete) {
      showToast(context, AppStringKeys.chatDeleteUnavailable);
      return;
    }
    final scope = await showChatDeleteScopeDialog(
      context,
      title: AppStringKeys.chatListDeleteChatQuestion,
      selfOnlyDescription: isGroupOrChannel
          ? AppStrings.t(
              AppStringKeys.chatListLeaveAndDeleteGroupConfirmation,
              {'value1': chat.title},
            )
          : AppStrings.t(AppStringKeys.chatInfoClearHistoryDescription),
      capabilities: capabilities,
      isGroupOrChannel: isGroupOrChannel,
    );
    if (!mounted || scope == null) return;
    try {
      await _model.deleteChat(chat, scope: scope);
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
    if (chat.kind == ChatKind.channel) {
      return AppStringKeys.topicChatLeaveChannel;
    }
    if (chat.kind == ChatKind.group) return AppStringKeys.chatInfoLeaveGroup;
    return AppStringKeys.chatDelete;
  }

  PageRoute<T> _chatEntryRoute<T>(Widget child) {
    return MaterialPageRoute<T>(builder: (_) => child);
  }

  Widget _assistantRow() {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ArchivedChatsView(
            chats: _model.archived,
            onClearUnread: _model.markRead,
          ),
        ),
      ),
      child: ArchivedChatsRow(
        archived: _model.archived,
        onClearUnread: () => _model.markChatsRead(_model.archived),
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

  Widget _plusMenuOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _showPlusMenu = false),
        child: Container(
          color: Colors.black.withValues(alpha: 0.12),
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 48,
            right: 10,
          ),
          alignment: Alignment.topRight,
          child: GestureDetector(
            onTap: () {},
            child: PlusMenu(
              onSelect: _selectPlusMenuItem,
              showCommunities:
                  context.watch<ThemeController>().communitiesEnabled &&
                  _model.availableCommunities.isNotEmpty,
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterMenuOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _showFilterMenu = false),
        child: Container(
          color: Colors.black.withValues(alpha: 0.12),
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 48,
            right: 10,
          ),
          alignment: Alignment.topRight,
          child: GestureDetector(
            onTap: () {},
            child: ChatFilterMenu(
              filters: _model.filters,
              selected: _model.selectedFilter,
              onSelect: _selectFilter,
            ),
          ),
        ),
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
    this.requiresLongPressDrag = false,
  });

  final int rowId;
  final int? openRowId;
  final ValueChanged<int?> onOpenChanged;
  final List<SwipeActionItem> actions;
  final VoidCallback onTap;
  final Widget child;
  final bool requiresLongPressDrag;

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
  bool _longPressHighlighted = false;
  double _longPressStartOffset = 0;

  double get _totalWidth => widget.actions.length * _buttonWidth;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
  }

  @override
  void didUpdateWidget(ChatSwipeRow old) {
    super.didUpdateWidget(old);
    // Another row opened — snap this one shut.
    if (widget.openRowId != widget.rowId && _offset != 0) {
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
    final anim = Tween<double>(
      begin: _offset,
      end: target,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
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
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _offset != 0 ? _close() : widget.onTap(),
              onLongPressStart: (_) {
                _stopAnimation();
                _longPressStartOffset = _offset;
                setState(() => _longPressHighlighted = true);
              },
              onLongPressMoveUpdate: widget.requiresLongPressDrag
                  ? (details) {
                      setState(() {
                        _offset = _rubberBandOffset(
                          _longPressStartOffset +
                              details.localOffsetFromOrigin.dx,
                        );
                      });
                    }
                  : null,
              onLongPressEnd: (details) {
                setState(() => _longPressHighlighted = false);
                if (widget.requiresLongPressDrag) {
                  _settle(details.velocity.pixelsPerSecond.dx);
                }
              },
              onLongPressCancel: () =>
                  setState(() => _longPressHighlighted = false),
              onHorizontalDragStart: widget.requiresLongPressDrag
                  ? null
                  : (_) => _stopAnimation(),
              onHorizontalDragUpdate: widget.requiresLongPressDrag
                  ? null
                  : (details) {
                      setState(
                        () => _offset = _rubberBandOffset(
                          _offset + details.delta.dx,
                        ),
                      );
                    },
              onHorizontalDragEnd: widget.requiresLongPressDrag
                  ? null
                  : (details) => _settle(details.primaryVelocity ?? 0),
              child: Stack(
                children: [
                  widget.child,
                  if (_longPressHighlighted)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
