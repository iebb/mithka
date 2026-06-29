//
//  chat_search_view.dart
//
//  In-chat message search (查找聊天记录). Runs `searchChatMessages` for the open
//  chat and lists matching messages with sender, snippet and date. Opened from
//  the chat-info screen.
//

import 'dart:async';

import 'package:flutter/material.dart';

import '../components/photo_avatar.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';

class ChatSearchView extends StatefulWidget {
  const ChatSearchView({super.key, required this.chatId, required this.title});
  final int chatId;
  final String title;

  @override
  State<ChatSearchView> createState() => _ChatSearchViewState();
}

class _ChatSearchViewState extends State<ChatSearchView> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final TdClient _client = TdClient.shared;
  Timer? _debounce;
  String _query = '';
  bool _loading = false;
  List<ChatMessage> _results = [];

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

  void _onChanged(String q) {
    setState(() => _query = q);
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(q));
  }

  Future<void> _run(String q) async {
    setState(() => _loading = true);
    try {
      final res = await _client.query({
        '@type': 'searchChatMessages',
        'chat_id': widget.chatId,
        'query': q,
        'sender_id': null,
        'from_message_id': 0,
        'offset': 0,
        'limit': 50,
        'filter': {'@type': 'searchMessagesFilterEmpty'},
      });
      final list = res.objects('messages') ?? const <Map<String, dynamic>>[];
      final parsed = list
          .map(TDParse.message)
          .whereType<ChatMessage>()
          .toList();
      if (!mounted || q != _query) return;
      setState(() {
        _results = parsed;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
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
                            hintText: '搜索聊天记录',
                            border: InputBorder.none,
                            isCollapsed: true,
                          ),
                          onChanged: _onChanged,
                        ),
                      ),
                      if (_query.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _controller.clear();
                            _onChanged('');
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

  Widget _body() {
    final c = context.colors;
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
          '搜索本聊天的消息',
          style: TextStyle(fontSize: 14, color: c.textSecondary),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          '没有找到相关消息',
          style: TextStyle(fontSize: 14, color: c.textSecondary),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _results.length,
      itemBuilder: (context, i) => _row(_results[i]),
    );
  }

  Widget _row(ChatMessage m) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.background,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PhotoAvatar(
            title: m.senderName ?? widget.title,
            photo: m.senderPhoto,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        m.senderName ?? widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      DateText.listLabel(m.date),
                      style: TextStyle(fontSize: 12, color: c.textTertiary),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  m.text.isEmpty ? '[消息]' : m.text.replaceAll('\n', ' '),
                  maxLines: 2,
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
}
