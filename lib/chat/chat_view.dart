//
//  chat_view.dart
//
//  The conversation screen. A gray canvas hosting a scrolling transcript of
//  bubbles, time separators and system banners, with a flat header and a pinned
//  input bar. Backed by ChatViewModel. Port of the Swift `ChatView`.
//

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../components/toast.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../call/call_manager.dart';
import '../components/photo_avatar.dart';
import '../components/sf_symbols.dart';
import '../components/ui_components.dart';
import '../profile/profile_detail_view.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../tdlib/td_models.dart';
import 'chat_info_view.dart';
import 'chat_input_bar.dart';
import 'chat_picker_view.dart';
import 'custom_emoji.dart';
import 'emoji_store.dart';
import 'chat_view_model.dart';
import 'full_image_viewer.dart';
import 'message_action_menu.dart';
import 'message_bubble.dart';
import 'sticker_set_detail_view.dart';
import 'video_player_view.dart';

class ChatView extends StatefulWidget {
  const ChatView({
    super.key,
    required this.chatId,
    required this.title,
    this.initialMessageId,
  });
  final int chatId;
  final String title;
  final int? initialMessageId;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _TranscriptEntry {
  const _TranscriptEntry(this.messages, this.startIndex);

  final List<ChatMessage> messages;
  final int startIndex;

  ChatMessage get first => messages.first;
  bool get isImageGroup => messages.length > 1;
}

class _ChatViewState extends State<ChatView> {
  late final ChatViewModel _vm = ChatViewModel(
    chatId: widget.chatId,
    title: widget.title,
    initialMessageId: widget.initialMessageId,
  );
  final _scroll = ScrollController();
  final _pinnedKey = GlobalKey(); // the pinned message's row, for scroll-to
  final _targetKey = GlobalKey(); // arbitrary linked/anchored message row
  final _unreadKey = GlobalKey(); // the "以下为新消息" divider, for entry scroll
  ChatMessage? _actionTarget;
  Rect? _actionRect; // global bounds of the long-pressed bubble
  bool _reactionExpanded = false; // full reaction picker vs. quick bar
  String _reactionTab = 'standard'; // 'standard' or a custom-emoji pack id
  int _lastCount = 0;
  bool _didInitialScroll = false; // one-time entry positioning has run
  bool _showJumpDown = false; // scrolled up → show jump-to-bottom button
  bool _bannerDismissed = false; // "N条新消息" banner dismissed / caught up
  Timer? _bannerTimer; // auto-hides the banner a few seconds after it appears
  int? _scrollTargetId;

  /// Gap (seconds) between messages that triggers a fresh time separator.
  static const _separatorGap = 300;

  @override
  void initState() {
    super.initState();
    _vm.addListener(_onModel);
    _scroll.addListener(_onScroll);
    _scrollTargetId = widget.initialMessageId;
    _vm.onAppear();
    // Load premium status early so the message menu can correctly hide the
    // emoji add/表情包 actions for non-premium users (the menu reads it).
    EmojiStore.shared.loadIfNeeded();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels < 500) _vm.loadOlder();
    // Show the jump-to-bottom button once scrolled up from the newest message.
    final show = pos.maxScrollExtent - pos.pixels > 120;
    if (show != _showJumpDown) setState(() => _showJumpDown = show);
  }

  void _animateToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// Jump to the first unread incoming message (where the "以下为新消息" divider
  /// sits); fall back to the bottom if none is loaded.
  void _jumpToFirstUnread() {
    setState(() => _bannerDismissed = true);
    final i = _vm.messages.indexWhere(
      (m) => !m.isOutgoing && !m.isService && m.id > _vm.lastReadInboxId,
    );
    if (i < 0 || !_scroll.hasClients) {
      _animateToBottom();
      return;
    }
    final max = _scroll.position.maxScrollExtent;
    final target = (max * (i / _vm.messages.length)).clamp(0.0, max);
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _onModel() {
    if (!mounted) return;
    if (_vm.messages.length != _lastCount) {
      final restore = _vm.consumeRestoreTop();
      _lastCount = _vm.messages.length;
      // Keep pinned to the bottom while history streams in; the one-time entry
      // positioning below repositions to the first unread once it's all loaded.
      if (restore == null && _scrollTargetId == null && !_vm.anchoredHistory) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    }
    final target = _vm.consumePendingScrollToId();
    if (target != null) {
      _scrollTargetId = target;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureMessageVisible(target);
      });
    }
    // Telegram-style entry: once the initial history (incl. the unread
    // boundary) is loaded, jump to the first unread message — or stay at the
    // bottom when caught up. Runs exactly once per chat open.
    if (!_didInitialScroll && _vm.initialLoaded && _vm.messages.isNotEmpty) {
      _didInitialScroll = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _initialScroll());
    }
    // The "N条新消息" banner shows on entry, then auto-hides after a few seconds.
    if (_vm.unreadCount > 0 && _bannerTimer == null && !_bannerDismissed) {
      _bannerTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _bannerDismissed = true);
      });
    }
    setState(() {});
  }

  int _firstUnreadIndex() => _vm.messages.indexWhere(
    (m) => !m.isOutgoing && !m.isService && m.id > _vm.lastReadInboxId,
  );

  /// One-time positioning when a chat opens: land on the first unread message
  /// (the "以下为新消息" divider near the top), or on the latest message when
  /// caught up. Because the list is lazily built, the divider's context may not
  /// exist yet — jump approximately first to build it, then snap precisely.
  void _initialScroll() {
    if (!_scroll.hasClients) return;
    final target = widget.initialMessageId;
    if (target != null) {
      _scrollTargetId = target;
      _ensureMessageVisible(target);
      return;
    }
    final i = _firstUnreadIndex();
    final boundaryLoaded =
        _vm.messages.isNotEmpty && _vm.messages.first.id <= _vm.lastReadInboxId;
    if (_vm.unreadCount <= 0 || i < 0 || !boundaryLoaded) {
      _scrollToBottom();
      return;
    }
    final max = _scroll.position.maxScrollExtent;
    final approx = (max * (i / _vm.messages.length)).clamp(0.0, max);
    _scroll.jumpTo(approx);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _unreadKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.12, // divider just below the top of the viewport
          duration: const Duration(milliseconds: 180),
        );
      }
    });
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _vm.removeListener(_onModel);
    _vm.onDisappear();
    _vm.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _needsUnreadDivider(int index) {
    if (_vm.unreadCount <= 0) return false;
    final m = _vm.messages[index];
    if (m.isOutgoing || m.isService || m.id <= _vm.lastReadInboxId) {
      return false;
    }
    if (index == 0) return true;
    return _vm.messages[index - 1].id <= _vm.lastReadInboxId;
  }

  Widget _unreadDivider() {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: c.divider, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '以下为新消息',
              style: TextStyle(fontSize: 12, color: c.textSecondary),
            ),
          ),
          Expanded(child: Divider(color: c.divider, height: 1)),
        ],
      ),
    );
  }

  bool _needsSeparator(int index) {
    if (index == 0) return true;
    return _vm.messages[index].date - _vm.messages[index - 1].date >
        _separatorGap;
  }

  bool _isRepeatTail(int index) {
    final messages = _vm.messages;
    if (index != messages.length - 1 || index == 0) return false;
    final a = messages[index], b = messages[index - 1];
    if (a.isService || b.isService) return false;
    // 复读 (+1) only echoes identical plain-text OR identical photos. Audio,
    // voice, location, stickers, polls, files, videos, contacts and call logs
    // are never repeatable — even when their placeholder text happens to match.
    if (a.isPlainText && b.isPlainText) {
      final ta = a.text.trim(), tb = b.text.trim();
      return ta.isNotEmpty && ta == tb;
    }
    if (a.isPhoto && b.isPhoto) {
      return a.image != null && b.image != null && a.image!.id == b.image!.id;
    }
    return false;
  }

  void _playVideo(ChatMessage message) {
    final v = message.video;
    if (v == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => VideoPlayerView(
          video: v,
          thumb: message.image,
          width: message.imageWidth,
          height: message.imageHeight,
        ),
      ),
    );
  }

  void _openImage(ChatMessage message) {
    final pairs = _vm.messages
        .where((m) => m.isPhoto && m.image != null)
        .toList();
    final items = pairs.map((m) => m.image!).toList();
    final start = pairs.indexWhere((m) => m.id == message.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            FullImageViewer(items: items, startIndex: start < 0 ? 0 : start),
      ),
    );
  }

  void _perform(MessageAction action, ChatMessage message) {
    setState(() => _actionTarget = null);
    switch (action) {
      case MessageAction.copy:
        Clipboard.setData(ClipboardData(text: message.text));
      case MessageAction.reply:
        _vm.setReply(message);
      case MessageAction.forward:
        _forwardMessage(message);
      case MessageAction.save:
        _vm.saveToFavorites(message.id);
      case MessageAction.saveSticker:
        final id = message.stickerFileId ?? message.animatedSticker?.id;
        if (id != null) {
          _vm.saveFavoriteSticker(id);
          showToast(context, '已添加到表情');
        }
      case MessageAction.viewStickerSet:
        final sid = message.stickerSetId;
        if (sid != null) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => StickerSetDetailView(setId: sid)),
          );
        }
      case MessageAction.delete:
        _vm.deleteMessage(message.id);
    }
  }

  void _openSenderProfile(ChatMessage m) {
    final uid = _vm.isGroup ? m.senderId : _vm.peerUserId;
    if (uid == null || uid <= 0) {
      return; // channels post as the chat, not a user
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ProfileDetailView(userId: uid, name: m.senderName ?? _vm.peerTitle),
      ),
    );
  }

  void _startCall(bool isVideo) {
    final uid = _vm.peerUserId;
    if (uid == null) {
      showToast(context, '仅支持与联系人通话');
      return;
    }
    context.read<CallManager>().startCall(uid, isVideo);
  }

  Future<void> _forwardMessage(ChatMessage message) async {
    final target = await Navigator.of(context).push<ChatSummary>(
      MaterialPageRoute(builder: (_) => const ChatPickerView(title: '转发到')),
    );
    if (target == null || !mounted) return;
    _vm.forward(message.id, target.id);
    showToast(context, '已转发到 ${target.title}');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Not a member, joinable, and nothing to preview → a QQ-style join screen
    // (header + centered card) instead of the transcript + composer.
    if (!_vm.isMember && _vm.canJoin && _vm.messages.isEmpty) {
      return Scaffold(
        backgroundColor: c.groupedBackground,
        body: _joinScreenBody(),
      );
    }
    return Scaffold(
      backgroundColor: c.chatBackground,
      // The input bar manages the keyboard inset itself (see ChatInputBar), so
      // an open emoji/+ panel sits flush instead of leaving a keyboard-sized gap.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Column(
            children: [
              _header(),
              if (_vm.pinnedMessage != null && !_vm.pinnedDismissed)
                _pinnedBar(_vm.pinnedMessage!),
              // Both scroll affordances float INSIDE the transcript area, so the
              // banner sits just below the pinned bar and the jump button just
              // above the input bar — no overlap, no magic offsets.
              Expanded(
                child: Stack(
                  children: [
                    _transcript(),
                    if (_vm.unreadCount > 0 && !_bannerDismissed)
                      Positioned(
                        top: 8,
                        right: 12,
                        child: _newMessagesBanner(),
                      ),
                    if (_showJumpDown)
                      Positioned(
                        right: 16,
                        bottom: 12,
                        child: _jumpToBottomButton(),
                      ),
                  ],
                ),
              ),
              _composerArea(),
            ],
          ),
          if (_actionTarget != null) _actionMenuOverlay(),
        ],
      ),
    );
  }

  /// Small button (bottom-right of the transcript) to return to the newest
  /// message; shown only when the user has scrolled up.
  Widget _jumpToBottomButton() {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _animateToBottom,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: c.navBar,
          shape: BoxShape.circle,
          border: Border.all(color: c.divider, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(sfIcon('chevron.down'), size: 20, color: c.textSecondary),
      ),
    );
  }

  /// Top-right "N条新消息" pill; tap jumps up to the first unread message.
  Widget _newMessagesBanner() {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _jumpToFirstUnread,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: c.navBar,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.divider, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(sfIcon('arrow.up'), size: 14, color: AppTheme.brand),
            const SizedBox(width: 5),
            Text(
              '${_vm.unreadCount}条新消息',
              style: TextStyle(
                fontSize: 13,
                color: c.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // MARK: - Composer area (input bar / join bar / disabled bar)

  Widget _composerArea() {
    if (_vm.canSendMessages) {
      return ChatInputBar(vm: _vm, onStartCall: _startCall);
    }
    if (!_vm.isMember && _vm.canJoin) return _joinBar();
    // Subscribed to a channel you can't post in → mute/unmute (like official).
    if (_vm.isChannel && _vm.isMember) return _channelMuteBar();
    return _disabledComposer(_vm.sendDisabledReason);
  }

  Widget _channelMuteBar() {
    final c = context.colors;
    final muted = _vm.isMuted;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _vm.toggleMute(),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          16,
          14,
          16,
          14 + MediaQuery.of(context).padding.bottom,
        ),
        decoration: BoxDecoration(
          color: c.navBar,
          border: Border(top: BorderSide(color: c.divider, width: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(sfIcon('bell.fill'), size: 18, color: AppTheme.brand),
            const SizedBox(width: 8),
            Text(
              muted ? '取消静音' : '静音',
              style: TextStyle(fontSize: 16, color: AppTheme.brand),
            ),
          ],
        ),
      ),
    );
  }

  /// Bottom bar with a 加入 / 申请加入 button for a joinable chat you can preview.
  Widget _joinBar() {
    final c = context.colors;
    final requested = _vm.joinRequested;
    final label = requested ? '已申请加入' : (_vm.joinByRequest ? '申请加入' : '加入群组');
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: requested ? null : () => _vm.joinChat(),
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: requested ? null : AppTheme.brandGradient,
            color: requested ? c.searchFill : null,
            borderRadius: BorderRadius.circular(23),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: requested ? c.textSecondary : Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  /// Static bar shown when sending is blocked (muted / channel / removed).
  Widget _disabledComposer(String reason) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        16,
        14,
        16,
        14 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      alignment: Alignment.center,
      child: Text(
        reason.isEmpty ? '你无法在此聊天中发送消息' : reason,
        style: TextStyle(fontSize: 14, color: c.textSecondary),
      ),
    );
  }

  /// QQ-style join screen for a joinable chat with no previewable content.
  Widget _joinScreenBody() {
    final c = context.colors;
    final requested = _vm.joinRequested;
    final label = requested
        ? '已申请加入，等待审核'
        : (_vm.joinByRequest ? '申请加入' : '加入群组');
    return Column(
      children: [
        _header(),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PhotoAvatar(
                    title: _vm.peerTitle,
                    photo: _vm.peerPhoto,
                    size: 88,
                    square:
                        _vm.isGroup &&
                        !context.watch<ThemeController>().circularGroupAvatars,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _vm.peerTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                  if (_vm.memberCount > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${_vm.memberCount} 名成员',
                      style: TextStyle(fontSize: 14, color: c.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 28),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: requested ? null : () => _vm.joinChat(),
                    child: Container(
                      height: 46,
                      constraints: const BoxConstraints(minWidth: 200),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      decoration: BoxDecoration(
                        gradient: requested ? null : AppTheme.brandGradient,
                        color: requested ? c.searchFill : null,
                        borderRadius: BorderRadius.circular(23),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: requested ? c.textSecondary : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _header() {
    final c = context.colors;
    final subtitle = _vm.subtitle;
    final typing = subtitle.endsWith('正在输入…');
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(
                    sfIcon('chevron.left'),
                    size: 22,
                    color: c.textPrimary,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _vm.headerTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: c.textPrimary,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: typing ? AppTheme.brand : c.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatInfoView(
                      chatId: widget.chatId,
                      title: _vm.peerTitle,
                    ),
                  ),
                ),
                child: Icon(
                  sfIcon('line.3.horizontal'),
                  size: 22,
                  color: c.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pinnedBar(ChatMessage pinned) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _scrollToMessage(pinned.id),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: c.navBar,
          border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Container(width: 3, height: 28, color: AppTheme.brand),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '置顶消息',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.brand,
                    ),
                  ),
                  Text(
                    pinned.text.isEmpty
                        ? '[消息]'
                        : pinned.text.replaceAll('\n', ' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: c.textSecondary),
                  ),
                ],
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _vm.dismissPinned,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(sfIcon('xmark'), size: 16, color: c.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Scrolls the transcript to a message. If it is not loaded, ask TDLib for a
  /// page centered around that id instead of fetching the whole middle history.
  Future<void> _scrollToMessage(int messageId) async {
    _scrollTargetId = messageId;
    if (_vm.messages.any((m) => m.id == messageId)) {
      await _ensureMessageVisible(messageId);
      return;
    }
    final loaded = await _vm.loadAroundMessage(messageId);
    if (!loaded || !mounted) return;
    await _ensureMessageVisible(messageId);
  }

  Future<void> _ensureMessageVisible(int messageId) async {
    for (var tries = 0; tries < 6; tries++) {
      final ctx = _targetKey.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(
          ctx,
          alignment: 0.3,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
        return;
      }
      if (!_scroll.hasClients) return;
      final index = _vm.messages.indexWhere((m) => m.id == messageId);
      if (index >= 0) {
        final max = _scroll.position.maxScrollExtent;
        final frac = _vm.messages.length <= 1
            ? 0.0
            : index / _vm.messages.length;
        _scroll.jumpTo((max * frac).clamp(0.0, max));
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
    }
  }

  Widget _transcript() {
    final groupImages = context.watch<ThemeController>().groupImageMessages;
    final entries = groupImages ? _groupedTranscript() : _plainTranscript();
    return Container(
      color: context.colors.chatBackground,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          final message = entry.first;
          final messageIndex = entry.startIndex;
          final isTarget = entry.messages.any((m) => m.id == _scrollTargetId);
          final isPinned = entry.messages.any(
            (m) => m.id == _vm.pinnedMessage?.id,
          );
          return Column(
            key: isTarget
                ? _targetKey
                : isPinned
                ? _pinnedKey
                : null,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_needsUnreadDivider(messageIndex))
                KeyedSubtree(key: _unreadKey, child: _unreadDivider()),
              if (_needsSeparator(messageIndex))
                TimeSeparator(unix: message.date),
              if (message.isService)
                SystemBanner(text: message.text)
              else if (entry.isImageGroup)
                _imageGroupBubble(entry.messages)
              else
                MessageBubble(
                  message: message,
                  peerTitle: _vm.peerTitle,
                  peerPhoto: _vm.peerPhoto,
                  isGroup: _vm.isGroup,
                  meName: _vm.meName,
                  mePhoto: _vm.mePhoto,
                  showRepeat: _isRepeatTail(messageIndex),
                  onRepeat: () => _vm.repeatMessage(message),
                  onLongPress: (m, rect) => setState(() {
                    _actionTarget = m;
                    _actionRect = rect;
                    _reactionExpanded = false;
                    _reactionTab = 'standard';
                  }),
                  onReply: (m) => _vm.setReply(m),
                  onAvatarTap: _openSenderProfile,
                  onAvatarLongPress: (m) {
                    if (_vm.isGroup && (m.senderName?.isNotEmpty ?? false)) {
                      _vm.insertMention(m.senderName!);
                    }
                  },
                  onOpenImage: _openImage,
                  onPlayVideo: _playVideo,
                  isRead: _vm.isRead(message),
                  onToggleReaction: (r) => _vm.toggleReaction(message, r),
                  onRedial: _startCall,
                ),
            ],
          );
        },
      ),
    );
  }

  List<_TranscriptEntry> _plainTranscript() {
    final messages = _vm.messages;
    return [
      for (var i = 0; i < messages.length; i++)
        _TranscriptEntry([messages[i]], i),
    ];
  }

  List<_TranscriptEntry> _groupedTranscript() {
    final messages = _vm.messages;
    final entries = <_TranscriptEntry>[];
    var i = 0;
    while (i < messages.length) {
      final first = messages[i];
      if (!_canGroupImage(first)) {
        entries.add(_TranscriptEntry([first], i));
        i++;
        continue;
      }

      final group = <ChatMessage>[first];
      var j = i + 1;
      while (j < messages.length) {
        final next = messages[j];
        if (_needsSeparator(j) || _needsUnreadDivider(j)) break;
        if (!_sameImageGroup(group.last, next)) break;
        group.add(next);
        j++;
      }

      entries.add(_TranscriptEntry(group, i));
      i = j;
    }
    return entries;
  }

  bool _canGroupImage(ChatMessage message) {
    return !message.isService && message.isPhoto && message.image != null;
  }

  bool _sameImageGroup(ChatMessage previous, ChatMessage next) {
    if (!_canGroupImage(next)) return false;
    if (previous.isOutgoing != next.isOutgoing) return false;
    if (previous.senderId != next.senderId) return false;
    if (previous.mediaAlbumId != 0 || next.mediaAlbumId != 0) {
      return previous.mediaAlbumId != 0 &&
          previous.mediaAlbumId == next.mediaAlbumId;
    }
    return (next.date - previous.date).abs() <= 20;
  }

  Widget _imageGroupBubble(List<ChatMessage> group) {
    final c = context.colors;
    final first = group.first;
    final outgoing = first.isOutgoing;
    final avatarTitle = outgoing
        ? _vm.meName
        : (_vm.isGroup && (first.senderName?.isNotEmpty ?? false))
        ? first.senderName!
        : _vm.peerTitle;
    final avatarPhoto = outgoing
        ? _vm.mePhoto
        : (_vm.isGroup ? first.senderPhoto : _vm.peerPhoto);
    final captions = group
        .map((m) => m.text.trim())
        .where((text) => text.isNotEmpty && text != '[图片]')
        .toList();
    final gallery = _imageGroupGallery(group, outgoing, captions);

    Widget avatar() => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: outgoing ? null : () => _openSenderProfile(first),
      onLongPress: outgoing
          ? null
          : () {
              if (_vm.isGroup && (first.senderName?.isNotEmpty ?? false)) {
                _vm.insertMention(first.senderName!);
              }
            },
      child: PhotoAvatar(title: avatarTitle, photo: avatarPhoto, size: 38),
    );

    Widget body = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => setState(() {
        _actionTarget = first;
        _actionRect = null;
        _reactionExpanded = false;
        _reactionTab = 'standard';
      }),
      child: outgoing
          ? gallery
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_vm.isGroup && (first.senderName?.isNotEmpty ?? false))
                  Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 4),
                    child: Text(
                      first.senderName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                  ),
                gallery,
              ],
            ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: outgoing
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: outgoing
            ? [
                Flexible(
                  child: Align(alignment: Alignment.centerRight, child: body),
                ),
                const SizedBox(width: 8),
                avatar(),
              ]
            : [avatar(), const SizedBox(width: 8), Flexible(child: body)],
      ),
    );
  }

  Widget _imageGroupGallery(
    List<ChatMessage> group,
    bool outgoing,
    List<String> captions,
  ) {
    final c = context.colors;
    const maxWidth = 252.0;
    const gap = 4.0;
    final visible = group.take(9).toList();
    final columns = visible.length <= 2 ? visible.length : 3;
    final tile = (maxWidth - gap * (columns - 1)) / columns;
    return Container(
      constraints: const BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: outgoing ? AppTheme.bubbleOutgoing : c.bubbleIncoming,
        borderRadius: BorderRadius.circular(8),
        border: outgoing ? null : Border.all(color: c.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var i = 0; i < visible.length; i++)
                _imageGroupTile(
                  visible[i],
                  width: tile,
                  height: tile,
                  extraCount: i == visible.length - 1
                      ? math.max(0, group.length - visible.length)
                      : 0,
                ),
            ],
          ),
          if (captions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 7, 6, 3),
              child: Text(
                captions.first,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.25,
                  color: outgoing ? AppTheme.bubbleOutgoingText : c.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _imageGroupTile(
    ChatMessage message, {
    required double width,
    required double height,
    required int extraCount,
  }) {
    return GestureDetector(
      onTap: () => _openImage(message),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            TDImage(photo: message.image, cornerRadius: 5, fit: BoxFit.cover),
            if (extraCount > 0)
              Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '+$extraCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static const _quickReactions = ['👍', '❤️', '🔥', '🎉', '😁', '😢', '😡'];

  /// The fuller set shown when the quick bar is expanded.
  static const _allReactions = [
    '👍',
    '👎',
    '❤️',
    '🔥',
    '🥰',
    '👏',
    '😁',
    '🤔',
    '🤯',
    '😱',
    '🤬',
    '😢',
    '🎉',
    '🤩',
    '🤮',
    '💩',
    '🙏',
    '👌',
    '🕊️',
    '🤡',
    '🥱',
    '🥴',
    '😍',
    '🐳',
    '🌚',
    '🌭',
    '💯',
    '🤣',
    '⚡',
    '🍌',
    '🏆',
    '💔',
    '🤨',
    '😐',
    '🍓',
    '🍾',
    '💋',
    '🖕',
    '😈',
    '😴',
  ];

  void _react(String emoji) {
    final target = _actionTarget;
    setState(() {
      _actionTarget = null;
      _reactionExpanded = false;
    });
    if (target != null) _vm.addReaction(target.id, emoji);
  }

  void _reactCustom(int customEmojiId) {
    final target = _actionTarget;
    setState(() {
      _actionTarget = null;
      _reactionExpanded = false;
    });
    if (target != null) _vm.addCustomReaction(target.id, customEmojiId);
  }

  Widget _actionMenuOverlay() {
    final media = MediaQuery.of(context);
    final screenH = media.size.height;
    final topSafe = media.padding.top + 8;
    final bottomSafe = screenH - media.padding.bottom - 8;
    final outgoing = _actionTarget!.isOutgoing;
    final rect = _actionRect;

    final reactionH = _reactionExpanded ? 268.0 : 48.0;
    const menuH = 84.0;
    const gap = 8.0;

    double reactionTop, menuTop;
    if (rect != null) {
      // Reaction bar above the message, action menu below it.
      reactionTop = (rect.top - reactionH - gap).clamp(
        topSafe,
        bottomSafe - reactionH,
      );
      menuTop = (rect.bottom + gap).clamp(topSafe, bottomSafe - menuH);
    } else {
      reactionTop = (screenH - reactionH - menuH - gap) / 2;
      menuTop = reactionTop + reactionH + gap;
    }
    final align = outgoing ? Alignment.centerRight : Alignment.centerLeft;

    void dismiss() => setState(() {
      _actionTarget = null;
      _actionRect = null;
      _reactionExpanded = false;
    });

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: dismiss,
              child: Container(color: Colors.black.withValues(alpha: 0.25)),
            ),
          ),
          // Call logs and other special messages aren't reactable — no +1 bar.
          if (!_actionTarget!.isCall)
            Positioned(
              top: reactionTop,
              left: 10,
              right: 10,
              child: Align(
                alignment: align,
                child: _reactionExpanded
                    ? _expandedReactionPicker()
                    : _quickReactionBar(),
              ),
            ),
          Positioned(
            top: menuTop,
            left: 10,
            right: 10,
            child: Align(
              alignment: align,
              child: MessageActionMenu(
                message: _actionTarget!,
                onSelect: (action) => _perform(action, _actionTarget!),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickReactionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in _quickReactions)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _react(e),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(e, style: const TextStyle(fontSize: 28)),
              ),
            ),
          // Expand → full (tabbed, for premium) reaction picker.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              EmojiStore.shared.loadIfNeeded();
              setState(() => _reactionExpanded = true);
            },
            child: Container(
              margin: const EdgeInsets.only(left: 2),
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: Color(0xFF3A3A3C),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.keyboard_arrow_down,
                size: 22,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _expandedReactionPicker() {
    final store = EmojiStore.shared;
    final packs = store.isPremium ? store.customPacks : const [];
    return Container(
      width: 300,
      height: 268,
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(child: _reactionContent(packs)),
          if (packs.isNotEmpty) _reactionTabStrip(packs),
        ],
      ),
    );
  }

  Widget _reactionContent(List packs) {
    if (_reactionTab != 'standard') {
      final id = int.tryParse(_reactionTab);
      CustomEmojiPack? pack;
      for (final p in packs) {
        if (p.id == id) {
          pack = p;
          break;
        }
      }
      if (pack != null) {
        return GridView.count(
          crossAxisCount: 6,
          padding: const EdgeInsets.all(10),
          children: [
            for (final item in pack.emoji)
              if (item.customEmojiId != 0)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _reactCustom(item.customEmojiId),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: CustomEmojiView(
                      id: item.customEmojiId,
                      size: 34,
                      color: Colors.white,
                    ),
                  ),
                ),
          ],
        );
      }
    }
    return GridView.count(
      crossAxisCount: 7,
      padding: const EdgeInsets.all(10),
      children: [
        for (final e in _allReactions)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _react(e),
            child: Center(child: Text(e, style: const TextStyle(fontSize: 26))),
          ),
      ],
    );
  }

  Widget _reactionTabStrip(List packs) {
    return Container(
      height: 46,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF3A3A3C), width: 0.5)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        children: [
          _reactionTab2(
            'standard',
            const Icon(
              Icons.emoji_emotions_outlined,
              size: 22,
              color: Colors.white70,
            ),
          ),
          for (final pack in packs)
            _reactionTab2(
              pack.id.toString(),
              pack.emoji.isNotEmpty && pack.emoji.first.customEmojiId != 0
                  ? CustomEmojiView(
                      id: pack.emoji.first.customEmojiId,
                      size: 26,
                      color: Colors.white,
                    )
                  : const Icon(
                      Icons.workspaces_outline,
                      size: 20,
                      color: Colors.white70,
                    ),
            ),
        ],
      ),
    );
  }

  Widget _reactionTab2(String key, Widget child) {
    final selected = _reactionTab == key;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _reactionTab = key),
      child: Container(
        width: 40,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF4A4A4E) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: SizedBox(width: 28, height: 28, child: Center(child: child)),
      ),
    );
  }
}
