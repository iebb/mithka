//
//  chat_list_view.dart
//
//  The 消息 tab: a custom reference header (avatar → profile drawer, name +
//  online, trailing "+") over a search pill and the chat list. Rows use a custom
//  left-swipe that reveals flush, full-height action blocks (置顶 / 标为未读 /
//  删除), matching the reference rather than the rounded native swipe. The "+"
//  opens a dropdown of create actions. Port of the Swift `ChatListView`.
//

import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../components/toast.dart';
import 'package:provider/provider.dart';

import '../chat/chat_view.dart';
import '../components/drawer_controller.dart' as dc;
import '../components/photo_avatar.dart';
import '../components/sf_symbols.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'archived_chats_view.dart';
import 'chat_list_view_model.dart';
import 'chat_row_view.dart';
import 'search_view.dart';

class ChatListView extends StatefulWidget {
  const ChatListView({super.key});

  @override
  State<ChatListView> createState() => _ChatListViewState();
}

class _ChatListViewState extends State<ChatListView> {
  final ChatListViewModel _model = ChatListViewModel();
  String _meName = '我';
  TdFileRef? _mePhoto;
  int? _openSwipeChat;

  @override
  void initState() {
    super.initState();
    _model.onAppear();
    _model.addListener(_onModel);
    _loadMe();
  }

  void _onModel() {
    if (_model.notice != null && mounted) {
      final text = _model.notice!;
      _model.clearNotice();
      showToast(context, text);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
      ],
    );
  }

  // MARK: - Header

  Widget _header() {
    final c = context.colors;
    return Container(
      color: c.listHeaderTint,
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => context.read<dc.DrawerController>().open(),
              child: PhotoAvatar(title: _meName, photo: _mePhoto, size: 40),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _meName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: AppTheme.onlineDot,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '在线',
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
            const Spacer(),
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
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: c.searchFill,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              Icon(sfIcon('magnifyingglass'), size: 16, color: c.textTertiary),
              const SizedBox(width: 6),
              Text('搜索', style: TextStyle(fontSize: 14, color: c.textTertiary)),
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
          const rowH = AppTheme.rowHeight + 0.5;
          final visibleRows = math.max(1, (geo.maxHeight / rowH).ceil());
          final chats = _model.chats;
          final hasArchive = _model.archived.isNotEmpty;
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
                              fontSize: 15,
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
