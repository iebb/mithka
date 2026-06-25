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

import '../chat/chat_view.dart';
import '../chat/custom_emoji.dart';
import '../components/drawer_controller.dart' as dc;
import '../components/photo_avatar.dart';
import '../components/sf_symbols.dart';
import '../components/ui_components.dart';
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

class ChatListController extends ChangeNotifier {
  int _scrollToFirstUnreadRequests = 0;
  int get scrollToFirstUnreadRequests => _scrollToFirstUnreadRequests;

  void scrollToFirstUnread() {
    _scrollToFirstUnreadRequests++;
    notifyListeners();
  }
}

class ChatListView extends StatefulWidget {
  const ChatListView({super.key, this.controller});

  final ChatListController? controller;

  @override
  State<ChatListView> createState() => _ChatListViewState();
}

class _ChatListViewState extends State<ChatListView> {
  final ChatListViewModel _model = ChatListViewModel();
  final ScrollController _scrollController = ScrollController();
  String _meName = '我';
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
  int _lastHandledScrollToFirstUnreadRequest = 0;
  int _pendingScrollAttempts = 0;

  @override
  void initState() {
    super.initState();
    _model.onAppear();
    _model.addListener(_onModel);
    _scrollController.addListener(_onScroll);
    widget.controller?.addListener(_onScrollToFirstUnreadRequest);
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
    oldWidget.controller?.removeListener(_onScrollToFirstUnreadRequest);
    widget.controller?.addListener(_onScrollToFirstUnreadRequest);
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
    widget.controller?.removeListener(_onScrollToFirstUnreadRequest);
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatView(chatId: chat.id, title: chat.title),
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
        builder: (_) =>
            const EditFieldView(title: '创建频道', initial: '', hint: '频道名称'),
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
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatView(chatId: id, title: title),
        ),
      );
    } catch (_) {
      if (mounted) showToast(context, '创建频道失败');
    }
  }

  void _selectPlusMenuItem(String label) {
    setState(() => _showPlusMenu = false);
    switch (label) {
      case '创建群聊':
        _createGroup();
      case '创建频道':
        _createChannel();
      case '加好友/群':
        _showAddMenu();
    }
  }

  void _selectFilter(ChatFilterOption filter) {
    setState(() => _showFilterMenu = false);
    _model.selectFilter(filter);
  }

  void _onScrollToFirstUnreadRequest() {
    final request = widget.controller?.scrollToFirstUnreadRequests ?? 0;
    if (request <= _lastHandledScrollToFirstUnreadRequest) return;
    _pendingScrollToFirstUnreadRequest = request;
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
      final target = _firstUnreadScrollOffset();
      if (target == null) {
        _model.loadMore();
        _retryScrollToFirstUnread();
        return;
      }

      _lastHandledScrollToFirstUnreadRequest =
          _pendingScrollToFirstUnreadRequest!;
      _pendingScrollToFirstUnreadRequest = null;
      _pendingScrollAttempts = 0;
      _scrollController.jumpTo(target);
    });
  }

  void _retryScrollToFirstUnread() {
    _pendingScrollAttempts++;
    if (_pendingScrollAttempts > 160) {
      _pendingScrollToFirstUnreadRequest = null;
      _pendingScrollAttempts = 0;
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
      final assistantIndex = math.min(_lastVisibleRows + 1, chats.length);
      if (assistantIndex <= chatIndex) itemIndex++;
    }

    final rowH = context.read<ThemeController>().rowHeight + 0.5;
    return math.min(
      itemIndex * rowH,
      _scrollController.position.maxScrollExtent,
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
              _searchPill(),
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
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
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
                        '在线',
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
                  activeFilter.title,
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
                  child: Icon(
                    Icons.filter_list_rounded,
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
                child: Icon(
                  sfIcon('plus'),
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
            children: [
              Icon(
                sfIcon('magnifyingglass'),
                size: AppMetric.searchIcon,
                color: c.textTertiary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '搜索',
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
    return Container(
      color: c.background,
      child: LayoutBuilder(
        builder: (context, geo) {
          final rowH = context.watch<ThemeController>().rowHeight + 0.5;
          final visibleRows = math.max(1, (geo.maxHeight / rowH).ceil());
          _lastVisibleRows = visibleRows;
          final chats = _model.chats;
          final hasArchive = _model.isAllFilter && _model.archived.isNotEmpty;
          final assistantIndex = math.min(visibleRows + 1, chats.length);

          // Build flat item list with the 群助手 entry interleaved.
          final items = <Widget>[];
          for (var i = 0; i < chats.length; i++) {
            if (hasArchive && i == assistantIndex) items.add(_assistantRow());
            items.add(_swipeRow(chats[i]));
          }
          if (hasArchive && assistantIndex >= chats.length) {
            items.add(_assistantRow());
          }

          return ListView.builder(
            controller: _scrollController,
            itemExtent: rowH,
            padding:
                EdgeInsets.zero, // header already consumed the top safe-area
            itemCount: items.length,
            itemBuilder: (context, i) => items[i],
          );
        },
      ),
    );
  }

  Widget _rowContainer(Widget child) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [child, const InsetDivider(leadingInset: 78)],
  );

  Widget _swipeRow(ChatSummary chat) {
    return ChatSwipeRow(
      rowId: chat.id,
      openRowId: _openSwipeChat,
      onOpenChanged: (id) => setState(() => _openSwipeChat = id),
      onTap: () => _openChat(chat),
      actions: [
        SwipeActionItem(
          title: chat.isPinned ? '取消置顶' : '置顶',
          color: const Color(0xFF3C8CF0),
          onTap: () => _model.togglePin(chat),
        ),
        SwipeActionItem(
          title: '标为未读',
          color: const Color(0xFFF5A623),
          onTap: () => _model.markUnread(chat),
        ),
        SwipeActionItem(
          title: '删除',
          color: const Color(0xFFFA5151),
          onTap: () => _model.deleteChat(chat),
        ),
      ],
      child: _rowContainer(ChatRowView(chat: chat)),
    );
  }

  Widget _assistantRow() {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ArchivedChatsView(chats: _model.archived),
        ),
      ),
      child: _rowContainer(GroupAssistantRow(archived: _model.archived)),
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
}

/// Reference-style "+" dropdown of create actions.
class PlusMenu extends StatelessWidget {
  const PlusMenu({super.key, required this.onSelect});
  final ValueChanged<String> onSelect;

  static const _items = [
    ('plus.circle', '创建群聊'),
    ('square.grid.2x2.fill', '创建频道'),
    ('person.badge.plus', '加好友/群'),
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
                            sfIcon(item.$1),
                            size: AppIconSize.lg + 1,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xl),
                        Text(
                          item.$2,
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
                            ? Icons.all_inbox_rounded
                            : Icons.folder_outlined,
                        size: AppIconSize.lg + 1,
                        color: c.textPrimary,
                      ),
                      const SizedBox(width: AppSpacing.xl),
                      Expanded(
                        child: Text(
                          filter.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppTextSize.bodyLarge,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      if (selectedFilter)
                        Icon(Icons.check, size: 18, color: AppTheme.brand),
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

// MARK: - QQ-style swipe row

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
  double _offset = 0;

  double get _totalWidth => widget.actions.length * _buttonWidth;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
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
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    final anim = Tween<double>(
      begin: _offset,
      end: target,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    void listener() => setState(() => _offset = anim.value);
    _controller.reset();
    anim.addListener(listener);
    _controller.forward().whenComplete(() {
      anim.removeListener(listener);
      _offset = target;
    });
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
                            item.title,
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
              onHorizontalDragUpdate: (d) {
                setState(
                  () =>
                      _offset = (_offset + d.delta.dx).clamp(-_totalWidth, 0.0),
                );
              },
              onHorizontalDragEnd: (_) {
                if (_offset < -_totalWidth * 0.4) {
                  _animateTo(-_totalWidth);
                  widget.onOpenChanged(widget.rowId);
                } else {
                  _animateTo(0);
                  if (widget.openRowId == widget.rowId) {
                    widget.onOpenChanged(null);
                  }
                }
              },
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}
