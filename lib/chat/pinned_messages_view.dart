//
//  pinned_messages_view.dart
//
//  精华消息: pinned-message browser for a chat. Opens pinned messages from
//  TDLib's searchMessagesFilterPinned and can jump back to the original message.
//

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../l10n/telegram_language_controller.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import 'chat_view.dart';
import 'full_image_viewer.dart';
import 'video_player_view.dart';

class PinnedMessagesView extends StatefulWidget {
  const PinnedMessagesView({
    super.key,
    required this.chatId,
    required this.title,
  });

  final int chatId;
  final String title;

  @override
  State<PinnedMessagesView> createState() => _PinnedMessagesViewState();
}

class _PinnedMessagesViewState extends State<PinnedMessagesView> {
  final TdClient _client = TdClient.shared;
  final Map<int, String> _names = {};
  final Map<int, TdFileRef?> _photos = {};
  bool _loading = true;
  List<ChatMessage> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _client.query({
        '@type': 'searchChatMessages',
        'chat_id': widget.chatId,
        'query': '',
        'sender_id': null,
        'from_message_id': 0,
        'offset': 0,
        'limit': 100,
        'filter': {'@type': 'searchMessagesFilterPinned'},
      });
      final list = res.objects('messages') ?? const <Map<String, dynamic>>[];
      final parsed = list
          .map(TDParse.message)
          .whereType<ChatMessage>()
          .toList();
      for (final message in parsed) {
        await _resolveSender(message);
      }
      if (!mounted) return;
      setState(() {
        _items = parsed;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolveSender(ChatMessage message) async {
    final id = message.senderId;
    if (id == null || _names.containsKey(id)) return;
    try {
      if (id > 0) {
        final user = await _client.query({'@type': 'getUser', 'user_id': id});
        _names[id] = TDParse.userName(user);
        _photos[id] = TDParse.smallPhoto(user.obj('profile_photo'));
      } else {
        final chat = await _client.query({'@type': 'getChat', 'chat_id': id});
        _names[id] = chat.str('title') ?? widget.title;
        _photos[id] = TDParse.smallPhoto(chat.obj('photo'));
      }
    } catch (_) {
      _names[id] = widget.title;
      _photos[id] = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
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
                  child: AppIcon(
                    HeroAppIcons.chevronLeft,
                    size: 22,
                    color: c.textPrimary,
                  ),
                ),
              ),
            ),
            Text(
              telegramText(AppStringKeys.chatInfoPinnedHighlights),
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

  Widget _body() {
    final c = context.colors;
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator.adaptive(strokeWidth: 2),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          telegramText(AppStringKeys.pinnedMessagesEmpty),
          style: TextStyle(fontSize: 14, color: c.textSecondary),
        ),
      );
    }
    return RefreshIndicator.adaptive(
      color: AppTheme.brand,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        itemCount: _items.length,
        itemBuilder: (context, i) => _card(_items[i]),
      ),
    );
  }

  Widget _card(ChatMessage message) {
    final c = context.colors;
    final senderId = message.senderId;
    final name = senderId == null
        ? widget.title
        : (_names[senderId] ?? widget.title);
    final photo = senderId == null ? null : _photos[senderId];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatView(
            chatId: widget.chatId,
            title: widget.title,
            initialMessageId: message.id,
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PhotoAvatar(title: name, photo: photo, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        telegramText(AppStringKeys.pinnedMessagesSentBy, {
                          'value1': DateText.listLabel(message.date),
                        }),
                        style: TextStyle(fontSize: 13, color: c.textTertiary),
                      ),
                    ],
                  ),
                ),
                AppIcon(HeroAppIcons.ellipsis, size: 22, color: c.textTertiary),
              ],
            ),
            const SizedBox(height: 12),
            _messageBody(message),
          ],
        ),
      ),
    );
  }

  Widget _messageBody(ChatMessage message) {
    final c = context.colors;
    final caption = _caption(message);
    final media = message.image;
    if (media != null) {
      final size = _mediaSize(message);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openMedia(message),
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TDImage(photo: media, fit: BoxFit.contain),
                  if (message.video != null)
                    Center(
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: const AppIcon(
                          HeroAppIcons.play,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 8),
            Text(
              caption,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 17, height: 1.3, color: c.textPrimary),
            ),
          ],
        ],
      );
    }

    final text = message.text.trim().isEmpty
        ? telegramText(AppStringKeys.chatSearchMessageResultLabel)
        : message.text.replaceAll('\n', ' ');
    return Text(
      text,
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 18, height: 1.3, color: c.textPrimary),
    );
  }

  String? _caption(ChatMessage message) {
    final text = message.text.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('[') && text.endsWith(']')) return null;
    return text.replaceAll('\n', ' ');
  }

  Size _mediaSize(ChatMessage message) {
    const maxW = 320.0;
    const maxH = 360.0;
    final w = message.imageWidth;
    final h = message.imageHeight;
    if (w == null || h == null || w <= 0 || h <= 0) {
      return const Size(maxW, 220);
    }
    final aspect = w / h;
    var dw = maxW;
    var dh = dw / aspect;
    if (dh > maxH) {
      dh = maxH;
      dw = dh * aspect;
    }
    return Size(dw, dh);
  }

  void _openMedia(ChatMessage message) {
    if (message.video != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => VideoPlayerView(
            video: message.video!,
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
    if (message.image == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FullImageViewer(items: [message.image!]),
      ),
    );
  }
}
