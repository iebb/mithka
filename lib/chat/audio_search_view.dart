//
//  audio_search_view.dart
//
//  Telegram audio search for the composer 音频 action. Uses TDLib's global
//  searchMessages + searchMessagesFilterAudio, then copies the selected audio
//  message into the current chat.
//

import 'dart:async';

import 'package:flutter/material.dart';

import '../components/photo_avatar.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../components/toast.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';

class AudioSearchView extends StatefulWidget {
  const AudioSearchView({
    super.key,
    this.onSend,
    this.onPickLocal,
    this.initialQuery = '',
    this.selectOnly = false,
  });

  final Future<void> Function(int sourceChatId, ChatMessage message)? onSend;
  final Future<void> Function()? onPickLocal;
  final String initialQuery;
  final bool selectOnly;

  @override
  State<AudioSearchView> createState() => _AudioSearchViewState();
}

class _AudioResult {
  _AudioResult({required this.sourceChatId, required this.message});
  final int sourceChatId;
  final ChatMessage message;
}

class _SourceInfo {
  const _SourceInfo(this.title, this.photo);
  final String title;
  final TdFileRef? photo;
}

class _AudioSearchViewState extends State<AudioSearchView> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final TdClient _client = TdClient.shared;
  final Map<int, _SourceInfo> _sources = {};
  Timer? _debounce;
  String _query = '';
  bool _loading = false;
  int? _sendingMessageId;
  List<_AudioResult> _results = [];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQuery.trim();
    if (initial.isNotEmpty) {
      _controller.text = initial;
      _query = initial;
      unawaited(_search(initial));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.selectOnly && initial.isNotEmpty) return;
      _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        _loading = false;
        _results = [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final res = await _client.query({
        '@type': 'searchMessages',
        'chat_list': {'@type': 'chatListMain'},
        'query': q,
        'offset_date': 0,
        'offset_chat_id': 0,
        'offset_message_id': 0,
        'limit': 50,
        'filter': {'@type': 'searchMessagesFilterAudio'},
        'min_date': 0,
        'max_date': 0,
      });
      final raw = res.objects('messages') ?? const <Map<String, dynamic>>[];
      final results = <_AudioResult>[];
      for (final object in raw) {
        final sourceChatId = object.int64('chat_id');
        final message = TDParse.message(object);
        if (sourceChatId == null || message == null || message.music == null) {
          continue;
        }
        results.add(_AudioResult(sourceChatId: sourceChatId, message: message));
      }
      for (final r in results.take(12)) {
        _resolveSource(r.sourceChatId);
      }
      if (!mounted || q != _query.trim()) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast(context, '音频搜索失败');
    }
  }

  Future<void> _resolveSource(int chatId) async {
    if (_sources.containsKey(chatId)) return;
    try {
      final chat = await _client.query({'@type': 'getChat', 'chat_id': chatId});
      final info = _SourceInfo(
        chat.str('title') ?? '聊天',
        TDParse.smallPhoto(chat.obj('photo')),
      );
      if (!mounted) return;
      setState(() => _sources[chatId] = info);
    } catch (_) {}
  }

  Future<void> _send(_AudioResult result) async {
    if (widget.selectOnly) {
      Navigator.of(context).pop((result.sourceChatId, result.message));
      return;
    }
    final send = widget.onSend;
    if (send == null) return;
    if (_sendingMessageId != null) return;
    setState(() => _sendingMessageId = result.message.id);
    try {
      await send(result.sourceChatId, result.message);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _sendingMessageId = null);
      showToast(context, '发送音频失败');
    }
  }

  Future<void> _pickLocal() async {
    final action = widget.onPickLocal;
    if (action == null) return;
    Navigator.of(context).pop();
    await action();
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
              Expanded(child: _searchField()),
              if (widget.onPickLocal != null) ...[
                const SizedBox(width: 10),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _pickLocal,
                  child: FaIcon(
                    FontAwesomeIcons.solidFolder,
                    size: 21,
                    color: AppTheme.brand,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchField() {
    final c = context.colors;
    return Container(
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
                hintText: '搜索 Telegram 音频',
                border: InputBorder.none,
                isCollapsed: true,
              ),
              onChanged: _onChanged,
              onSubmitted: (v) => _search(v.trim()),
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
          '搜索歌曲、歌手或文件名',
          style: TextStyle(fontSize: 14, color: c.textSecondary),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          '没有找到音频',
          style: TextStyle(fontSize: 14, color: c.textSecondary),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _results.length,
      itemBuilder: (context, index) => _row(_results[index]),
    );
  }

  Widget _row(_AudioResult result) {
    final c = context.colors;
    final music = result.message.music!;
    final source = _sources[result.sourceChatId];
    final sending = _sendingMessageId == result.message.id;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: sending ? null : () => _send(result),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: c.background,
          border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
        ),
        child: Row(
          children: [
            _cover(music.cover),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    music.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    (music.performer ?? '').trim().isEmpty
                        ? DateText.listLabel(result.message.date)
                        : music.performer!.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: c.textSecondary),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      PhotoAvatar(
                        title: source?.title ?? '聊天',
                        photo: source?.photo,
                        size: 16,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          source?.title ?? '正在获取来源…',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: c.textTertiary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  )
                : FaIcon(
                    FontAwesomeIcons.solidPaperPlane,
                    size: 19,
                    color: AppTheme.brand,
                  ),
          ],
        ),
      ),
    );
  }

  Widget _cover(TdFileRef? cover) {
    final c = context.colors;
    if (cover != null) {
      return SizedBox(
        width: 48,
        height: 48,
        child: TDImage(photo: cover, cornerRadius: 8, fit: BoxFit.cover),
      );
    }
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.brand.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: FaIcon(
        FontAwesomeIcons.compactDisc,
        size: 25,
        color: c.textSecondary,
      ),
    );
  }
}
