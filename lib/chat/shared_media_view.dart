//
//  shared_media_view.dart
//
//  Shared-content browser for a chat (群相册 / 文件). Tabs run `searchChatMessages`
//  with a media filter — photos/videos in a grid, documents / links / voice in
//  lists. Opened from the chat-info screen.
//

import 'package:flutter/material.dart';

import '../components/photo_avatar.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import 'file_detail_view.dart';
import 'full_image_viewer.dart';
import 'link_handler.dart';
import 'video_player_view.dart';

class _MediaTab {
  const _MediaTab(this.label, this.filter, this.grid, {this.videoOnly = false});
  final String label;
  final String filter;
  final bool grid;
  final bool videoOnly;
}

class SharedMediaView extends StatefulWidget {
  const SharedMediaView({
    super.key,
    required this.chatId,
    required this.title,
    this.initialTab = 0,
    this.displayTitle = '聊天文件',
    this.lockedTab = false,
  });
  final int chatId;
  final String title;
  final int initialTab; // 0 图片视频, 1 文件, 2 链接, 3 语音, 4 视频
  final String displayTitle;
  final bool lockedTab;

  @override
  State<SharedMediaView> createState() => _SharedMediaViewState();
}

class _SharedMediaViewState extends State<SharedMediaView> {
  static const _tabs = [
    _MediaTab('图片视频', 'searchMessagesFilterPhotoAndVideo', true),
    _MediaTab('文件', 'searchMessagesFilterDocument', false),
    _MediaTab('链接', 'searchMessagesFilterUrl', false),
    _MediaTab('语音', 'searchMessagesFilterVoiceNote', false),
    _MediaTab('视频', 'searchMessagesFilterVideo', true, videoOnly: true),
  ];

  final TdClient _client = TdClient.shared;
  late int _tab = widget.initialTab;
  final Map<int, List<ChatMessage>> _cache = {};
  final Set<int> _loading = {};

  @override
  void initState() {
    super.initState();
    _load(_tab);
  }

  Future<void> _load(int tab) async {
    if (_cache.containsKey(tab) || _loading.contains(tab)) return;
    _loading.add(tab);
    try {
      final res = await _client.query({
        '@type': 'searchChatMessages',
        'chat_id': widget.chatId,
        'query': '',
        'sender_id': null,
        'from_message_id': 0,
        'offset': 0,
        'limit': 80,
        'filter': {'@type': _tabs[tab].filter},
      });
      final list = res.objects('messages') ?? const <Map<String, dynamic>>[];
      final parsed = list
          .map(TDParse.message)
          .whereType<ChatMessage>()
          .toList();
      if (!mounted) return;
      setState(() {
        _cache[tab] = parsed;
        _loading.remove(tab);
      });
    } catch (_) {
      if (mounted) setState(() => _loading.remove(tab));
    }
  }

  void _select(int tab) {
    setState(() => _tab = tab);
    _load(tab);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          _header(),
          if (!widget.lockedTab) _tabStrip(),
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
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: FaIcon(
                    FontAwesomeIcons.chevronLeft,
                    size: 22,
                    color: c.textPrimary,
                  ),
                ),
              ),
            ),
            Text(
              widget.displayTitle,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabStrip() {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _select(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: _tab == i ? AppTheme.brand : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    _tabs[i].label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: _tab == i ? FontWeight.w600 : FontWeight.w400,
                      color: _tab == i ? AppTheme.brand : c.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    final c = context.colors;
    final items = _cache[_tab];
    if (items == null) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator.adaptive(strokeWidth: 2),
        ),
      );
    }
    if (items.isEmpty) {
      return Center(
        child: Text(
          '暂无内容',
          style: TextStyle(fontSize: 14, color: c.textSecondary),
        ),
      );
    }
    return _tabs[_tab].grid ? _grid(items) : _list(items);
  }

  Widget _grid(List<ChatMessage> items) {
    final tab = _tabs[_tab];
    final media = items
        .where((m) => tab.videoOnly ? m.video != null : m.image != null)
        .toList();
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _mediaGridColumns(context),
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: media.length,
      itemBuilder: (context, i) {
        final m = media[i];
        return _mediaTile(m, media);
      },
    );
  }

  int _mediaGridColumns(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return (width / 110).floor().clamp(4, 10).toInt();
  }

  Widget _mediaTile(ChatMessage message, List<ChatMessage> media) {
    final video = message.video;
    return GestureDetector(
      onTap: () {
        if (video != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => VideoPlayerView(
                video: video,
                thumb: message.image,
                width: message.imageWidth,
                height: message.imageHeight,
                sourceChatId: widget.chatId,
                messageId: message.id,
              ),
            ),
          );
          return;
        }
        final photos = media
            .where((m) => m.video == null && m.image != null)
            .map((m) => m.image!)
            .toList();
        final photo = message.image;
        if (photo == null) return;
        final index = photos.indexWhere((item) => item.id == photo.id);
        Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => FullImageViewer(
              items: photos,
              startIndex: index < 0 ? 0 : index,
            ),
          ),
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          TDImage(photo: message.image, fit: BoxFit.cover),
          if (video != null) ...[
            Container(color: Colors.black.withValues(alpha: 0.16)),
            Center(
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.48),
                  shape: BoxShape.circle,
                ),
                child: FaIcon(
                  FontAwesomeIcons.play,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
            if ((message.videoDuration ?? 0) > 0)
              Positioned(
                right: 5,
                bottom: 5,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _duration(message.videoDuration!),
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _list(List<ChatMessage> items) {
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: items.length,
      itemBuilder: (context, i) => _listRow(items[i]),
    );
  }

  Widget _listRow(ChatMessage m) {
    final c = context.colors;
    final isVoice = m.voice != null;
    final isLink = m.document == null && !isVoice;
    final title =
        m.document?.fileName ??
        (isVoice ? '语音消息' : (m.text.isEmpty ? '链接' : m.text));
    final subtitle = m.document != null
        ? _fileSize(m.document!.size)
        : DateText.listLabel(m.date);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (m.document != null) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => FileDetailView(doc: m.document!)),
          );
        } else if (isLink && m.text.isNotEmpty) {
          openLink(context, m.text);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: c.background,
          border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.brand.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isVoice
                    ? FontAwesomeIcons.microphone.data
                    : isLink
                    ? FontAwesomeIcons.link.data
                    : FontAwesomeIcons.solidFile.data,
                size: 20,
                color: AppTheme.brand,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.replaceAll('\n', ' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: c.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: c.textTertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fileSize(int bytes) {
    if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
    if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  String _duration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    String two(int value) => value.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }
}
