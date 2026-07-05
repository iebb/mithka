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
import '../components/toast.dart';
import 'package:provider/provider.dart';

import '../channels/forum_topic_browser_view.dart';
import '../chat/chat_view.dart';
import '../chat/custom_emoji.dart';
import '../components/confirm_dialog.dart';
import '../components/drawer_controller.dart' as dc;
import '../components/photo_avatar.dart';
import '../components/app_icons.dart';
import '../contacts/add_people_view.dart';
import '../contacts/create_group_view.dart';
import '../profile/emoji_status_picker.dart';
import '../settings/edit_field_view.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'archived_chats_view.dart';
import 'chat_list_view_model.dart';
import 'chat_row_view.dart';
import 'search_view.dart';
import 'package:mithka/l10n/app_localizations.dart';

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

class ChatListView extends StatefulWidget {
  const ChatListView({
    super.key,
    this.controller,
    this.onChatSelected,
    this.selectedChatId,
  });

  final ChatListController? controller;
  final ValueChanged<ChatListSelection>? onChatSelected;
  final int? selectedChatId;

  @override
  State<ChatListView> createState() => _ChatListViewState();
}

class _ChatListViewState extends State<ChatListView> {
  final ChatListViewModel _model = ChatListViewModel();
  late ScrollController _scrollController = _newScrollController();
  String _meName = AppStringKeys.chatMeLabel;
  TdFileRef? _mePhoto;
  int _meStatusId = 0; // current emoji status, shown after the name
  bool _meIsPremium = false;
  int? _meId;
  StreamSubscription? _userSub;
  int? _openSwipeChat;
  int _lastVisibleRows = 1;
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
  bool _didApplyTopAssistantInitialOffset = false;

  ScrollController _newScrollController({double initialScrollOffset = 0}) {
    return ScrollController(initialScrollOffset: initialScrollOffset)
      ..addListener(_onScroll);
  }

  @override
  void initState() {
    super.initState();
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
          _meStatusId =
              me.obj('emoji_status')?.obj('type')?.int64('custom_emoji_id') ??
              me.obj('emoji_status')?.int64('custom_emoji_id') ??
              0;
          _meIsPremium = me.boolean('is_premium') ?? false;
          _meId = me.int64('id');
        });
      }
    } catch (_) {}
  }

  void _openChat(ChatSummary chat) {
    final onChatSelected = widget.onChatSelected;
    if (onChatSelected != null) {
      onChatSelected(ChatListSelection.fromChat(chat));
      return;
    }
    if (chat.isForum) {
      final railChats = <int, ChatSummary>{};
      for (final summary in [..._model.chats, ..._model.archived]) {
        railChats[summary.id] = summary;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ForumTopicBrowserView(
            chats: railChats.values.toList(),
            initialChat: chat,
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatView(
          chatId: chat.id,
          title: chat.title,
          seedMessage: chat.lastChatMessage,
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
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatView(chatId: id, title: title),
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
      case AppStringKeys.chatListCreateGroup:
        _createGroup();
      case AppStringKeys.chatListCreateChannel:
        _createChannel();
      case AppStringKeys.chatListAddFriendOrGroup:
        _showAddMenu();
    }
  }

  void _selectFilter(ChatFilterOption filter) {
    setState(() => _showFilterMenu = false);
    _model.selectFilter(filter);
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
    final chats = _model.chats;
    final chatIndex = chats.indexWhere((chat) => chat.showsRedUnreadIndicator);
    if (chatIndex < 0) return null;

    var itemIndex = chatIndex;
    if (_model.isAllFilter && _model.archived.isNotEmpty) {
      final placement = context.read<ThemeController>().groupAssistantPlacement;
      final assistantIndex = _assistantInsertionIndex(
        chats,
        _lastVisibleRows,
        placement,
      );
      if (assistantIndex <= chatIndex) itemIndex++;
    }

    final rowH = context.read<ThemeController>().rowHeight + 0.5;
    final searchOffset = context.read<ThemeController>().showChatListSearch
        ? AppSpacing.md + AppMetric.searchHeight + AppSpacing.sm
        : 0.0;
    return math.min(
      searchOffset + itemIndex * rowH,
      _scrollController.position.maxScrollExtent,
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
    final useFilterMenu = context.watch<ThemeController>().showChatFolderFilter;
    if (!useFilterMenu && !_model.isAllFilter) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_model.isAllFilter) {
          _model.selectFilter(_model.filters.first);
        }
      });
    }
    return Stack(
      children: [
        Container(
          color: c.background,
          child: Column(
            children: [
              _header(),
              Expanded(child: _chatList()),
            ],
          ),
        ),
        if (_showPlusMenu) _plusMenuOverlay(),
        if (useFilterMenu && _showFilterMenu) _filterMenuOverlay(),
      ],
    );
  }

  // MARK: - Header

  Widget _header() {
    final c = context.colors;
    final useFilterMenu = context.watch<ThemeController>().showChatFolderFilter;
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
                            fontSize: AppTextSize.title,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      if (_meStatusId != 0) ...[
                        const SizedBox(width: AppSpacing.xs + 1),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => showEmojiStatusPicker(
                            context,
                            currentStatusId: _meStatusId,
                          ),
                          child: CustomEmojiView(
                            id: _meStatusId,
                            size: 18,
                            color: c.textPrimary,
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
                  const SizedBox(height: AppSpacing.xxs),
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
                        AppStringKeys.chatOnline.l10n(context),
                        style: TextStyle(
                          fontSize: AppTextSize.caption,
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
            if (useFilterMenu)
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
    final showSearch = context.watch<ThemeController>().showChatListSearch;
    final assistantPlacement = context
        .watch<ThemeController>()
        .groupAssistantPlacement;
    return Container(
      color: c.background,
      child: LayoutBuilder(
        builder: (context, geo) {
          final rowH = context.watch<ThemeController>().rowHeight + 0.5;
          final visibleRows = math.max(1, (geo.maxHeight / rowH).ceil());
          _lastVisibleRows = visibleRows;
          final chats = _model.chats;
          if (chats.isEmpty && _model.isInitialLoading) {
            return ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: visibleRows + (showSearch ? 1 : 0),
              itemBuilder: (context, i) {
                if (showSearch && i == 0) return _searchPill();
                return const _ChatRowPlaceholder();
              },
            );
          }
          if (chats.isEmpty) {
            final searchHeight = showSearch
                ? AppSpacing.md + AppMetric.searchHeight + AppSpacing.sm
                : 0.0;
            return ListView(
              padding: EdgeInsets.zero,
              children: [
                if (showSearch) _searchPill(),
                SizedBox(
                  height: math.max(180, geo.maxHeight - searchHeight),
                  child: _emptyChatList(),
                ),
              ],
            );
          }
          final hasArchive = _model.isAllFilter && _model.archived.isNotEmpty;
          final topAssistant =
              hasArchive && assistantPlacement == GroupAssistantPlacement.top;
          if (!topAssistant) _didApplyTopAssistantInitialOffset = false;
          final assistantIndex = _assistantInsertionIndex(
            chats,
            visibleRows,
            assistantPlacement,
          );

          if (topAssistant &&
              !_didApplyTopAssistantInitialOffset &&
              !_scrollController.hasClients) {
            _didApplyTopAssistantInitialOffset = true;
            _scrollController.removeListener(_onScroll);
            _scrollController.dispose();
            _scrollController = _newScrollController(initialScrollOffset: rowH);
          } else if (topAssistant && !_didApplyTopAssistantInitialOffset) {
            _didApplyTopAssistantInitialOffset = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || !_scrollController.hasClients) return;
              final max = _scrollController.position.maxScrollExtent;
              if (_scrollController.position.pixels < rowH * 0.5) {
                _scrollController.jumpTo(math.min(rowH, max));
              }
            });
          }

          final showInlineAssistant = !topAssistant && hasArchive;
          final itemCount =
              chats.length +
              (topAssistant ? 1 : 0) +
              (showSearch ? 1 : 0) +
              (showInlineAssistant ? 1 : 0);
          return ListView.builder(
            controller: _scrollController,
            padding:
                EdgeInsets.zero, // header already consumed the top safe-area
            itemCount: itemCount,
            itemBuilder: (context, index) => _chatListItem(
              index: index,
              chats: chats,
              showSearch: showSearch,
              topAssistant: topAssistant,
              showInlineAssistant: showInlineAssistant,
              assistantIndex: assistantIndex,
            ),
          );
        },
      ),
    );
  }

  Widget _chatListItem({
    required int index,
    required List<ChatSummary> chats,
    required bool showSearch,
    required bool topAssistant,
    required bool showInlineAssistant,
    required int assistantIndex,
  }) {
    var chatIndex = index;
    if (topAssistant) {
      if (chatIndex == 0) return _assistantRow();
      chatIndex -= 1;
    }
    if (showSearch) {
      if (chatIndex == 0) return _searchPill();
      chatIndex -= 1;
    }
    if (showInlineAssistant) {
      if (chatIndex == assistantIndex) return _assistantRow();
      if (chatIndex > assistantIndex) chatIndex -= 1;
    }
    return _swipeRow(chats[chatIndex]);
  }

  int _assistantInsertionIndex(
    List<ChatSummary> chats,
    int visibleRows,
    GroupAssistantPlacement placement,
  ) {
    if (chats.isEmpty) return 0;
    return switch (placement) {
      GroupAssistantPlacement.top => 0,
      GroupAssistantPlacement.secondScreen => math.min(
        visibleRows + 1,
        chats.length,
      ),
      GroupAssistantPlacement.chronological => _chronologicalAssistantIndex(
        chats,
      ),
    };
  }

  int _chronologicalAssistantIndex(List<ChatSummary> chats) {
    final archiveDate = _model.archived.isEmpty
        ? 0
        : _model.archived.first.date;
    if (archiveDate <= 0) return chats.length;
    final index = chats.indexWhere((chat) => chat.date < archiveDate);
    return index < 0 ? chats.length : index;
  }

  Widget _swipeRow(ChatSummary chat) {
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
              title: AppStringKeys.chatDelete,
              color: const Color(0xFFFA5151),
              onTap: () => _confirmDeleteChat(chat),
            ),
          ];
    return ChatSwipeRow(
      rowId: chat.id,
      openRowId: _openSwipeChat,
      onOpenChanged: (id) => setState(() => _openSwipeChat = id),
      onTap: () => _openChat(chat),
      actions: actions,
      child: ChatRowView(
        chat: chat,
        selected: widget.selectedChatId == chat.id,
        onClearUnread: () => _model.markRead(chat),
      ),
    );
  }

  Future<void> _confirmDeleteChat(ChatSummary chat) async {
    final isGroup = chat.kind == ChatKind.group;
    final confirmed = await confirmDialog(
      context,
      title: isGroup
          ? AppStringKeys.chatInfoLeaveGroup
          : AppStringKeys.chatListDeleteChatQuestion,
      message: isGroup
          ? AppStrings.t(
              AppStringKeys.chatListLeaveAndDeleteGroupConfirmation,
              {'value1': chat.title},
            )
          : AppStrings.t(AppStringKeys.chatInfoClearHistoryDescription),
      confirmText: isGroup
          ? AppStringKeys.chatInfoLeaveGroup
          : AppStringKeys.chatDelete,
      destructive: true,
    );
    if (!mounted || !confirmed) return;
    try {
      if (isGroup) {
        await _model.leaveAndDeleteChat(chat);
      } else {
        await _model.deleteChat(chat);
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
      child: GroupAssistantRow(
        archived: _model.archived,
        onClearUnread: _model.markAllRead,
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
            child: PlusMenu(onSelect: _selectPlusMenuItem),
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
  const PlusMenu({super.key, required this.onSelect});
  final ValueChanged<String> onSelect;

  static const _items = [
    (HeroAppIcons.circlePlus, AppStringKeys.chatListCreateGroup),
    (HeroAppIcons.grip, AppStringKeys.chatListCreateChannel),
    (HeroAppIcons.userPlus, AppStringKeys.chatListAddFriendOrGroup),
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
                          child: Icon(
                            item.$1.data,
                            size: AppIconSize.lg + 1,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xl),
                        Text(
                          item.$2.l10n(context),
                          style: TextStyle(
                            fontSize: AppTextSize.bodyLarge,
                            color: c.textPrimary,
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
                      Icon(
                        filter.isAll
                            ? HeroAppIcons.inbox.data
                            : HeroAppIcons.folder.data,
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
  });

  final int rowId;
  final int? openRowId;
  final ValueChanged<int?> onOpenChanged;
  final List<SwipeActionItem> actions;
  final VoidCallback onTap;
  final Widget child;

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
              onLongPressStart: (_) =>
                  setState(() => _longPressHighlighted = true),
              onLongPressEnd: (_) =>
                  setState(() => _longPressHighlighted = false),
              onLongPressCancel: () =>
                  setState(() => _longPressHighlighted = false),
              onHorizontalDragStart: (_) => _stopAnimation(),
              onHorizontalDragUpdate: (d) {
                setState(
                  () => _offset = _rubberBandOffset(_offset + d.delta.dx),
                );
              },
              onHorizontalDragEnd: (d) {
                final vx = d.primaryVelocity ?? 0;
                if (vx < -520 || (vx <= 360 && _offset < -_totalWidth * 0.38)) {
                  _animateTo(-_totalWidth);
                  widget.onOpenChanged(widget.rowId);
                } else {
                  _animateTo(0);
                  if (widget.openRowId == widget.rowId) {
                    widget.onOpenChanged(null);
                  }
                }
              },
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
