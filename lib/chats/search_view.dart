//
//  search_view.dart
//
//  Chat search — a pushed secondary screen. Custom header (back chevron +
//  rounded search field) on the list-header wash, with a live list of matching
//  chats below. Port of the Swift `SearchView` / `SearchViewModel`.
//

import 'dart:async';

import 'package:flutter/material.dart';

import '../chat/chat_view.dart';
import '../components/photo_avatar.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'chat_row_view.dart';

class SearchView extends StatefulWidget {
  const SearchView({super.key});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _vm = SearchViewModel();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _vm.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) _focus.requestFocus();
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _vm.dispose();
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
          Expanded(child: _results()),
        ],
      ),
    );
  }

  Widget _header() {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: BoxDecoration(
        color: c.listHeaderTint,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: FaIcon(
                    FontAwesomeIcons.chevronLeft,
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
                      FaIcon(
                        FontAwesomeIcons.magnifyingGlass,
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
                          decoration: const InputDecoration(
                            hintText: '搜索',
                            border: InputBorder.none,
                            isCollapsed: true,
                          ),
                          onChanged: (q) {
                            setState(() => _query = q);
                            _vm.search(q);
                          },
                        ),
                      ),
                      if (_query.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _controller.clear();
                            setState(() => _query = '');
                            _vm.search('');
                          },
                          child: FaIcon(
                            FontAwesomeIcons.xmark,
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

  Widget _results() {
    final c = context.colors;
    if (_query.trim().isEmpty) return _empty('搜索聊天、联系人');
    if (_vm.results.isEmpty) return _empty('未找到相关聊天');
    return Container(
      color: c.background,
      child: ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: _vm.results.length,
        itemBuilder: (context, i) {
          final hit = _vm.results[i];
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _open(hit),
                child: hit.chat != null
                    ? ChatRowView(chat: hit.chat!)
                    : _hitRow(hit),
              ),
              const InsetDivider(leadingInset: 78),
            ],
          );
        },
      ),
    );
  }

  Future<void> _open(SearchHit hit) async {
    final chat = hit.chat;
    if (chat != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatView(chatId: chat.id, title: chat.title),
        ),
      );
      return;
    }
    final userId = hit.userId;
    if (userId == null) return;
    try {
      final chat = await TdClient.shared.query({
        '@type': 'createPrivateChat',
        'user_id': userId,
        'force': false,
      });
      final summary = TDParse.chat(chat);
      if (!mounted || summary == null) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatView(chatId: summary.id, title: summary.title),
        ),
      );
    } catch (_) {}
  }

  Widget _hitRow(SearchHit hit) {
    final c = context.colors;
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: c.background,
      child: Row(
        children: [
          PhotoAvatar(title: hit.title, photo: hit.photo, size: 54),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hit.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hit.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: c.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(String text) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      color: c.groupedBackground,
      alignment: Alignment.center,
      child: Text(text, style: TextStyle(fontSize: 14, color: c.textTertiary)),
    );
  }
}

class SearchViewModel extends ChangeNotifier {
  List<SearchHit> results = [];
  String _currentQuery = '';

  void search(String q) {
    final trimmed = q.trim();
    _currentQuery = trimmed;
    if (trimmed.isEmpty) {
      results = [];
      notifyListeners();
      return;
    }
    _run(trimmed);
  }

  Future<void> _run(String trimmed) async {
    try {
      final out = <SearchHit>[];
      final seenChats = <int>{};
      final seenUsers = <int>{};

      Future<void> addChat(int id, {String? subtitle}) async {
        if (!seenChats.add(id)) return;
        try {
          final chat = await TdClient.shared.query({
            '@type': 'getChat',
            'chat_id': id,
          });
          final s = TDParse.chat(chat);
          if (s == null) return;
          out.add(SearchHit.chat(s, subtitle: subtitle));
          final uid = s.peerUserId;
          if (uid != null) seenUsers.add(uid);
        } catch (_) {}
      }

      final local = await TdClient.shared.query({
        '@type': 'searchChats',
        'query': trimmed,
        'limit': 50,
      });
      for (final id in (local.int64Array('chat_ids') ?? const <int>[]).take(
        50,
      )) {
        await addChat(id);
      }

      try {
        final contacts = await TdClient.shared.query({
          '@type': 'searchContacts',
          'query': trimmed,
          'limit': 50,
        });
        for (final id in contacts.int64Array('user_ids') ?? const <int>[]) {
          if (!seenUsers.add(id)) continue;
          try {
            final user = await TdClient.shared.query({
              '@type': 'getUser',
              'user_id': id,
            });
            out.add(SearchHit.user(id, user));
          } catch (_) {}
        }
      } catch (_) {}

      try {
        final public = await TdClient.shared.query({
          '@type': 'searchPublicChats',
          'query': trimmed,
        });
        for (final id in (public.int64Array('chat_ids') ?? const <int>[]).take(
          30,
        )) {
          await addChat(id, subtitle: '公开群组/频道');
        }
      } catch (_) {}

      final handle = _usernameOf(trimmed);
      if (handle != null) {
        try {
          final chat = await TdClient.shared.query({
            '@type': 'searchPublicChat',
            'username': handle,
          });
          final id = chat.int64('id');
          if (id != null) await addChat(id, subtitle: '@$handle');
        } catch (_) {}
      }

      if (trimmed != _currentQuery) return; // stale
      results = out;
      notifyListeners();
    } catch (_) {}
  }

  String? _usernameOf(String q) {
    var s = q.trim();
    final link = RegExp(
      r'(?:https?://)?(?:t\.me|telegram\.me)/(@?[A-Za-z0-9_]+)',
      caseSensitive: false,
    ).firstMatch(s);
    if (link != null) s = link.group(1)!;
    if (s.startsWith('@')) s = s.substring(1);
    return RegExp(r'^[A-Za-z0-9_]{3,32}$').hasMatch(s) ? s : null;
  }
}

class SearchHit {
  SearchHit({
    required this.title,
    required this.subtitle,
    this.photo,
    this.chat,
    this.userId,
  });

  factory SearchHit.chat(ChatSummary chat, {String? subtitle}) => SearchHit(
    title: chat.title,
    subtitle: subtitle ?? _chatSubtitle(chat),
    photo: chat.photo,
    chat: chat,
    userId: chat.peerUserId,
  );

  factory SearchHit.user(int id, Map<String, dynamic> user) {
    final username = user.obj('usernames')?.str('editable_username');
    return SearchHit(
      title: TDParse.userName(user),
      subtitle: username != null && username.isNotEmpty
          ? '@$username'
          : TDParse.userStatus(user),
      photo: TDParse.smallPhoto(user.obj('profile_photo')),
      userId: id,
    );
  }

  final String title;
  final String subtitle;
  final TdFileRef? photo;
  final ChatSummary? chat;
  final int? userId;

  static String _chatSubtitle(ChatSummary chat) {
    if (chat.kind == ChatKind.group) return '群组';
    if (chat.kind == ChatKind.channel) return '频道';
    if (chat.kind == ChatKind.bot) return '机器人';
    return chat.lastMessage.isEmpty ? '聊天' : chat.lastMessage;
  }
}
