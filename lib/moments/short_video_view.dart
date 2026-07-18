import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/app_navigator.dart';
import '../chat/chat_picker_view.dart';
import '../chat/chat_view.dart';
import '../chat/video_player_view.dart';
import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';

class ShortVideoLauncher {
  const ShortVideoLauncher._();

  static Future<void> open(BuildContext context) async {
    final chat = await pushAppChatRoute<ChatSummary>(
      context,
      MaterialPageRoute(builder: (_) => const _ShortVideoChatPicker()),
    );
    if (chat == null || !context.mounted) return;
    await pushAppChatRoute<void>(
      context,
      MaterialPageRoute(builder: (_) => ShortVideoView(chat: chat)),
    );
  }
}

class _ShortVideoChatPicker extends StatefulWidget {
  const _ShortVideoChatPicker();

  @override
  State<_ShortVideoChatPicker> createState() => _ShortVideoChatPickerState();
}

class _ShortVideoChatPickerState extends State<_ShortVideoChatPicker> {
  Set<int>? _eligibleChatIds;

  @override
  void initState() {
    super.initState();
    unawaited(_loadEligibleChats());
  }

  Future<void> _loadEligibleChats() async {
    final preferences = await SharedPreferences.getInstance();
    final key = 'shortVideo.maxDurationSeconds.${TdClient.shared.activeSlot}';
    final maxSeconds = (preferences.getInt(key) ?? 179).clamp(15, 600);
    final ids = <int>{};
    await Future.wait([
      _scanChatList({'@type': 'chatListMain'}, maxSeconds, ids),
      _scanChatList({'@type': 'chatListArchive'}, maxSeconds, ids),
    ]);
    if (mounted) setState(() => _eligibleChatIds = ids);
  }

  Future<void> _scanChatList(
    Map<String, dynamic> chatList,
    int maxSeconds,
    Set<int> result,
  ) async {
    var offsetDate = 0;
    var offsetChatId = 0;
    var offsetMessageId = 0;
    for (var page = 0; page < 20; page++) {
      try {
        final response = await TdClient.shared.query({
          '@type': 'searchMessages',
          'chat_list': chatList,
          'query': '',
          'offset_date': offsetDate,
          'offset_chat_id': offsetChatId,
          'offset_message_id': offsetMessageId,
          'limit': 100,
          'filter': {'@type': 'searchMessagesFilterVideo'},
          'min_date': 0,
          'max_date': 0,
        });
        final rawMessages =
            response.objects('messages') ?? const <Map<String, dynamic>>[];
        for (final raw in rawMessages) {
          final message = TDParse.message(raw);
          final duration = message?.videoDuration ?? 0;
          final chatId = message?.chatId;
          if (chatId != null && duration > 0 && duration <= maxSeconds) {
            result.add(chatId);
          }
        }
        if (rawMessages.length < 100) break;
        final last = rawMessages.last;
        final nextDate = last.integer('date') ?? 0;
        final nextChatId = last.integer('chat_id') ?? 0;
        final nextMessageId = last.integer('id') ?? 0;
        if (nextDate == offsetDate &&
            nextChatId == offsetChatId &&
            nextMessageId == offsetMessageId) {
          break;
        }
        offsetDate = nextDate;
        offsetChatId = nextChatId;
        offsetMessageId = nextMessageId;
      } catch (_) {
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final eligible = _eligibleChatIds;
    if (eligible == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF111214),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    return ChatPickerView(
      title: '选择短视频聊天',
      allowedChatIds: eligible,
      allowContacts: false,
      emptyText: '没有找到包含符合时长短视频的聊天',
    );
  }
}

class ShortVideoView extends StatefulWidget {
  const ShortVideoView({super.key, required this.chat});

  final ChatSummary chat;

  @override
  State<ShortVideoView> createState() => _ShortVideoViewState();
}

class _ShortVideoViewState extends State<ShortVideoView> {
  static const _defaultMaxSeconds = 179;
  static const _minimumMaxSeconds = 15;
  static const _maximumMaxSeconds = 600;

  final _pageController = PageController();
  List<ChatMessage> _videos = const [];
  bool _loading = true;
  int _currentPage = 0;
  int _maxSeconds = _defaultMaxSeconds;

  String get _preferenceKey =>
      'shortVideo.maxDurationSeconds.${TdClient.shared.activeSlot}';

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final preferences = await SharedPreferences.getInstance();
    _maxSeconds = (preferences.getInt(_preferenceKey) ?? _defaultMaxSeconds)
        .clamp(_minimumMaxSeconds, _maximumMaxSeconds);
    await _loadVideos();
  }

  Future<void> _loadVideos() async {
    if (mounted) setState(() => _loading = true);
    try {
      final response = await TdClient.shared.query({
        '@type': 'searchChatMessages',
        'chat_id': widget.chat.id,
        'query': '',
        'sender_id': null,
        'from_message_id': 0,
        'offset': 0,
        'limit': 100,
        'filter': {'@type': 'searchMessagesFilterVideo'},
      });
      final videos = (response.objects('messages') ?? const [])
          .map(TDParse.message)
          .whereType<ChatMessage>()
          .where(
            (message) =>
                message.video != null &&
                (message.videoDuration ?? 0) > 0 &&
                message.videoDuration! <= _maxSeconds,
          )
          .toList();
      if (!mounted) return;
      setState(() {
        _videos = videos;
        _currentPage = 0;
        _loading = false;
      });
      _prefetchNextVideo(0);
      if (_pageController.hasClients) _pageController.jumpToPage(0);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _configureDuration() async {
    var draft = _maxSeconds.toDouble();
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF171719),
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '最长短视频时长',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _durationLabel(draft.round()),
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
                Slider(
                  value: draft,
                  min: _minimumMaxSeconds.toDouble(),
                  max: _maximumMaxSeconds.toDouble(),
                  divisions: 39,
                  activeColor: Colors.white,
                  inactiveColor: Colors.white24,
                  onChanged: (value) => setSheetState(() => draft = value),
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () =>
                        Navigator.of(sheetContext).pop(draft.round()),
                    child: const Text('应用'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected == null || selected == _maxSeconds) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_preferenceKey, selected);
    if (!mounted) return;
    setState(() => _maxSeconds = selected);
    await _loadVideos();
  }

  String _durationLabel(int seconds) {
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    if (minutes == 0) return '$remainder 秒';
    if (remainder == 0) return '$minutes 分钟';
    return '$minutes 分 ${remainder.toString().padLeft(2, '0')} 秒';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) < -280) {
            Navigator.of(context).maybePop();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_loading)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            else if (_videos.isEmpty)
              _emptyState()
            else
              PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                itemCount: _videos.length,
                onPageChanged: (page) {
                  setState(() => _currentPage = page);
                  _prefetchNextVideo(page);
                },
                itemBuilder: (context, index) => _videoPage(index),
              ),
            _topBar(),
          ],
        ),
      ),
    );
  }

  Widget _videoPage(int index) {
    final message = _videos[index];
    final active = index == _currentPage;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (active)
          VideoPlayerView(
            key: ValueKey('short-video-${message.video!.id}'),
            video: message.video!,
            thumb: message.image,
            width: message.imageWidth,
            height: message.imageHeight,
            presentation: VideoPlayerPresentation.embedded,
            compactControls: true,
            sourceChatId: widget.chat.id,
            messageId: message.id,
            onClose: () => Navigator.of(context).maybePop(),
          )
        else
          _thumbnail(message),
        Positioned(
          left: 18,
          right: 82,
          bottom: MediaQuery.paddingOf(context).bottom + 28,
          child: IgnorePointer(child: _caption(message)),
        ),
        Positioned(
          right: 14,
          bottom: MediaQuery.paddingOf(context).bottom + 88,
          child: _engagementActions(message),
        ),
      ],
    );
  }

  void _prefetchNextVideo(int currentPage) {
    final nextPage = currentPage + 1;
    if (nextPage >= _videos.length) return;
    final next = _videos[nextPage].video;
    if (next == null) return;
    unawaited(TdFileCenter.shared.path(next.id));
  }

  Widget _engagementActions(ChatMessage message) {
    final chosen = message.reactions.any((reaction) => reaction.chosen);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _engagementButton(
          icon: HeroAppIcons.heart,
          active: chosen,
          onTap: () => _toggleLike(message),
        ),
        const SizedBox(height: 16),
        _engagementButton(
          icon: HeroAppIcons.comments,
          onTap: () => _openComments(message),
        ),
      ],
    );
  }

  Widget _engagementButton({
    required AppIconData icon,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: AppIcon(
            icon,
            size: 27,
            color: active ? const Color(0xFFFF4D67) : Colors.white,
          ),
        ),
      ),
    );
  }

  Future<void> _toggleLike(ChatMessage message) async {
    final previous = message.reactions;
    final chosen = previous.where((reaction) => reaction.chosen).firstOrNull;
    final type =
        chosen?.type ?? const {'@type': 'reactionTypeEmoji', 'emoji': '❤️'};
    if (chosen != null) {
      message.reactions = [
        for (final reaction in previous)
          if (identical(reaction, chosen))
            if (reaction.count > 1)
              MessageReaction(
                emoji: reaction.emoji,
                customEmojiId: reaction.customEmojiId,
                count: reaction.count - 1,
                chosen: false,
              )
            else
              reaction,
      ];
    } else {
      message.reactions = [
        ...previous,
        const MessageReaction(emoji: '❤️', count: 1, chosen: true),
      ];
    }
    setState(() {});
    try {
      await TdClient.shared.query({
        '@type': chosen == null
            ? 'addMessageReaction'
            : 'removeMessageReaction',
        'chat_id': widget.chat.id,
        'message_id': message.id,
        'reaction_type': type,
        if (chosen == null) 'is_big': false,
        if (chosen == null) 'update_recent_reactions': true,
      });
    } catch (_) {
      message.reactions = previous;
      if (mounted) setState(() {});
    }
  }

  void _openComments(ChatMessage message) {
    pushAppChatRoute(
      context,
      MaterialPageRoute(
        builder: (_) => ChatView(
          chatId: widget.chat.id,
          title: widget.chat.title,
          initialMessageId: message.id,
          seedMessage: message,
        ),
      ),
    );
  }

  Widget _thumbnail(ChatMessage message) {
    final mini = message.image?.miniThumb ?? message.video?.miniThumb;
    return ColoredBox(
      color: Colors.black,
      child: mini == null
          ? const SizedBox.expand()
          : Image.memory(mini, fit: BoxFit.contain, gaplessPlayback: true),
    );
  }

  Widget _caption(ChatMessage message) {
    final caption = message.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            PhotoAvatar(
              title: message.senderName ?? widget.chat.title,
              photo: message.senderPhoto ?? widget.chat.photo,
              size: 34,
              square: widget.chat.usesSquareAvatar,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message.senderName ?? widget.chat.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(blurRadius: 8)],
                ),
              ),
            ),
          ],
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            caption,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.32,
              shadows: [Shadow(blurRadius: 10)],
            ),
          ),
        ],
      ],
    );
  }

  Widget _topBar() {
    return Positioned(
      left: 8,
      right: 8,
      top: MediaQuery.paddingOf(context).top + 6,
      child: Row(
        children: [
          _roundButton(
            icon: HeroAppIcons.chevronLeft,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.chat.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                shadows: [Shadow(blurRadius: 8)],
              ),
            ),
          ),
          _roundButton(icon: HeroAppIcons.gear, onTap: _configureDuration),
        ],
      ),
    );
  }

  Widget _roundButton({
    required AppIconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: const BoxDecoration(
          color: Color(0x66000000),
          shape: BoxShape.circle,
        ),
        child: Center(child: AppIcon(icon, size: 21, color: Colors.white)),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppIcon(HeroAppIcons.video, size: 48, color: Colors.white54),
            const SizedBox(height: 16),
            const Text(
              '没有符合时长的短视频',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '当前最多接受 ${_durationLabel(_maxSeconds)}的视频',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 14),
            ),
            const SizedBox(height: 18),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
              ),
              onPressed: _configureDuration,
              child: const Text('调整时长'),
            ),
          ],
        ),
      ),
    );
  }
}
