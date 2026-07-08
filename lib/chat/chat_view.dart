//
//  chat_view.dart
//
//  The conversation screen. A gray canvas hosting a scrolling transcript of
//  bubbles, time separators and system banners, with a flat header and a pinned
//  input bar. Backed by ChatViewModel. Port of the Swift `ChatView`.
//

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../app/video_split_controller.dart';
import '../call/call_manager.dart';
import '../channels/topic_chat_view.dart';
import '../components/app_icons.dart';
import '../components/confirm_dialog.dart';
import '../components/drawer_controller.dart' as dc;
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/telegram_language_controller.dart';
import '../profile/profile_detail_view.dart';
import '../settings/edit_field_view.dart';
import '../settings/topic_group_display_mode.dart';
import '../settings/translation_api.dart';
import '../settings/translation_controller.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import '../theme/theme_controller.dart';
import 'chat_info_view.dart';
import 'chat_input_bar.dart';
import 'chat_picker_view.dart';
import 'chat_view_model.dart';
import 'custom_emoji.dart';
import 'emoji_store.dart';
import 'forward_options.dart';
import 'full_image_viewer.dart';
import 'link_handler.dart';
import 'media_album_layout.dart';
import 'message_action_menu.dart';
import 'message_bubble.dart';
import 'music_player_controller.dart';
import 'sticker_set_detail_view.dart';
import 'sticker_viewer.dart';
import 'video_player_view.dart';

class _MessageDeleteOptions {
  const _MessageDeleteOptions({
    required this.deleteMessage,
    required this.reportSpam,
    required this.blockSender,
    required this.deleteAllFromSender,
  });

  final bool deleteMessage;
  final bool reportSpam;
  final bool blockSender;
  final bool deleteAllFromSender;

  bool get hasAny =>
      deleteMessage || reportSpam || blockSender || deleteAllFromSender;
}

class _MessageDeleteOptionsDialog extends StatefulWidget {
  const _MessageDeleteOptionsDialog({
    required this.canActOnSender,
    required this.canDeleteAllFromSender,
    required this.senderName,
  });

  final bool canActOnSender;
  final bool canDeleteAllFromSender;
  final String senderName;

  @override
  State<_MessageDeleteOptionsDialog> createState() =>
      _MessageDeleteOptionsDialogState();
}

class _MessageDeleteOptionsDialogState
    extends State<_MessageDeleteOptionsDialog> {
  bool _deleteMessage = true;
  bool _reportSpam = false;
  bool _blockSender = false;
  bool _deleteAllFromSender = false;

  _MessageDeleteOptions get _options => _MessageDeleteOptions(
    deleteMessage: _deleteMessage,
    reportSpam: _reportSpam,
    blockSender: _blockSender,
    deleteAllFromSender: _deleteAllFromSender,
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final options = _options;
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: math.min(MediaQuery.of(context).size.width - 40, 420),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 26,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AppStringKeys.chatDeleteSingleMessageQuestion.l10n(context),
                style: TextStyle(
                  fontSize: 19,
                  height: 1.28,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 22),
              _optionRow(
                label: AppStringKeys.chatDeleteOptionDeleteMessage.l10n(
                  context,
                ),
                value: _deleteMessage,
                onTap: () => setState(() => _deleteMessage = !_deleteMessage),
              ),
              if (widget.canActOnSender) ...[
                _optionRow(
                  label: AppStringKeys.chatDeleteOptionReportSpam.l10n(context),
                  value: _reportSpam,
                  onTap: () => setState(() => _reportSpam = !_reportSpam),
                ),
                _optionRow(
                  label: AppStringKeys.chatDeleteOptionBlockSender.l10n(
                    context,
                  ),
                  value: _blockSender,
                  onTap: () => setState(() => _blockSender = !_blockSender),
                ),
                if (widget.canDeleteAllFromSender)
                  _optionRow(
                    label: AppStrings.t(
                      AppStringKeys.chatDeleteOptionDeleteAllFromSender,
                      {'value1': widget.senderName},
                    ),
                    value: _deleteAllFromSender,
                    onTap: () => setState(
                      () => _deleteAllFromSender = !_deleteAllFromSender,
                    ),
                  ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _dialogButton(
                    label: AppStringKeys.countryPickerCancel.l10n(context),
                    color: c.textSecondary,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  _dialogButton(
                    label: AppStringKeys.chatDelete.l10n(context),
                    color: options.hasAny
                        ? const Color(0xFFFF6961)
                        : c.textTertiary,
                    onTap: options.hasAny
                        ? () => Navigator.of(context).pop(options)
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _optionRow({
    required String label,
    required bool value,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: value ? AppTheme.brand : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: value ? AppTheme.brand : c.textTertiary,
                  width: 2,
                ),
              ),
              child: value
                  ? const AppIcon(
                      HeroAppIcons.check,
                      size: 17,
                      color: Colors.white,
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 17,
                  height: 1.25,
                  color: c.textPrimary,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogButton({
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: color,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

class ChatView extends StatefulWidget {
  const ChatView({
    super.key,
    required this.chatId,
    required this.title,
    this.initialMessageId,
    this.seedMessage,
    this.showBackButton = true,
    this.headerHeight = 48,
    this.headerColor,
    this.showHeaderDivider = true,
    this.onBack,
  });
  final int chatId;
  final String title;
  final int? initialMessageId;
  final ChatMessage? seedMessage;
  final bool showBackButton;
  final double headerHeight;
  final Color? headerColor;
  final bool showHeaderDivider;
  final VoidCallback? onBack;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _TranscriptEntry {
  _TranscriptEntry(this.messages, this.startIndex);

  final List<ChatMessage> messages;
  final int startIndex;

  ChatMessage get first => messages.first;
  bool get isImageGroup => messages.length > 1;

  /// Stable identity for element reuse across index shifts (history pages
  /// prepend and shift every index).
  late final Key key = ValueKey(
    isImageGroup
        ? 'album-${messages.map((m) => m.id).join('-')}'
        : 'message-${first.id}',
  );
}

class _ChatScrollSnapshot {
  const _ChatScrollSnapshot({
    required this.pixels,
    required this.wasAtLoadedBottom,
  });

  final double pixels;
  final bool wasAtLoadedBottom;
}

class _ChatViewState extends State<ChatView> {
  late final bool _openAtLatest;
  late final _ChatScrollSnapshot? _sessionScrollSnapshot;
  late final ChatViewModel _vm;
  late final ScrollController _scroll;
  final _pinnedKey = GlobalKey(); // the pinned message's row, for scroll-to
  final _targetKey = GlobalKey(); // arbitrary linked/anchored message row
  final _unreadKey = GlobalKey(); // the "以下为新消息" divider, for entry scroll
  ChatMessage? _actionTarget;
  Rect? _actionRect; // global bounds of the long-pressed bubble
  MessageActionSource _actionSource = MessageActionSource.normal;
  bool _reactionExpanded = false; // full reaction picker vs. quick bar
  String _reactionTab = 'standard'; // 'standard' or a custom-emoji pack id
  int _lastCount = 0;
  bool _didInitialScroll = false; // one-time entry positioning has run
  bool _showJumpDown = false; // scrolled up → show jump-to-bottom button
  bool _bannerDismissed = false; // "N条新消息" banner dismissed / caught up
  Timer? _bannerTimer; // auto-hides the banner a few seconds after it appears
  int? _scrollTargetId;
  int? _lastNewestMessageId;
  int _liveNewMessageCount = 0;
  double _keyboardInset = 0;
  bool _shortTranscriptFillScheduled = false;
  bool _isFillingShortTranscript = false;
  bool _loadingLatestFromAnchor = false;
  int _bottomSettleGeneration = 0;
  final Set<int> _selectedMessageIds = {};
  int? _selectionAnchorId;
  bool _selectionScrollingUp = false;
  double _lastScrollPixels = 0;
  double _backSwipeDx = 0;
  double _backSwipeDy = 0;
  bool _backSwipePopping = false;
  bool _loadingOlderFromScroll = false;
  VelocityTracker? _backSwipeVelocity;
  dc.TabBarVisibility? _tabBarVisibility;

  /// Gap (seconds) between messages that triggers a fresh time separator.
  static const _separatorGap = 300;
  static const _initialBottomScrollOffset = 1000000000.0;
  static const _initialTargetAlignment = 0.30;
  static const _initialUnreadAlignment = 0.12;
  static OverlayEntry? _globalPictureInPictureVideo;
  static final Map<int, _ChatScrollSnapshot> _sessionScrollSnapshots = {};

  double _messageMediaMaxWidth([double? chatWidth]) {
    final width = chatWidth ?? MediaQuery.sizeOf(context).width;
    return math.max(1.0, width * 0.75);
  }

  @override
  void initState() {
    super.initState();
    _openAtLatest = context.read<ThemeController>().openChatsAtLatest;
    _sessionScrollSnapshot = widget.initialMessageId == null
        ? _sessionScrollSnapshots[widget.chatId]
        : null;
    _scroll = ScrollController(
      initialScrollOffset: _shouldRestoreSessionScroll
          ? _sessionScrollSnapshot!.pixels
          : (_openAtLatest ? _initialBottomScrollOffset : 0),
    )..addListener(_onScroll);
    _vm = ChatViewModel(
      chatId: widget.chatId,
      title: widget.title,
      markReadOnOpen: _openAtLatest,
      initialMessageId: widget.initialMessageId,
      seedMessage: widget.seedMessage,
    );
    _vm.addListener(_onModel);
    _scrollTargetId = widget.initialMessageId;
    _vm.onAppear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _retainTabBarSuppression();
    });
    // Load premium status early so the message menu can correctly hide the
    // emoji add/表情包 actions for non-premium users (the menu reads it).
    EmojiStore.shared.loadIfNeeded();
  }

  bool get _shouldRestoreSessionScroll {
    final snapshot = _sessionScrollSnapshot;
    if (snapshot == null || widget.initialMessageId != null) return false;
    if (snapshot.wasAtLoadedBottom && _openAtLatest) return false;
    return true;
  }

  void _retainTabBarSuppression() {
    if (!mounted) return;
    dc.TabBarVisibility? tabBarVisibility;
    try {
      tabBarVisibility = context.read<dc.TabBarVisibility>();
    } on ProviderNotFoundException {
      tabBarVisibility = null;
    }
    if (identical(_tabBarVisibility, tabBarVisibility)) return;
    _tabBarVisibility?.releaseChatSuppression();
    _tabBarVisibility = tabBarVisibility;
    _tabBarVisibility?.retainChatSuppression();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final scrollingUp = pos.pixels < _lastScrollPixels;
    _lastScrollPixels = pos.pixels;
    _saveSessionScrollSnapshot();
    if (_selectionAnchorId != null && scrollingUp != _selectionScrollingUp) {
      setState(() => _selectionScrollingUp = scrollingUp);
    }
    if (pos.userScrollDirection == ScrollDirection.forward &&
        pos.pixels < 500) {
      unawaited(_loadOlderPreservingOffset());
    }
    if (_vm.anchoredHistory &&
        pos.userScrollDirection == ScrollDirection.reverse &&
        pos.maxScrollExtent - pos.pixels < 36) {
      unawaited(_returnToLatest());
    }
    final nearBottom = _isNearBottom(80);
    if (nearBottom &&
        (_liveNewMessageCount > 0 ||
            (!_openAtLatest && !_bannerDismissed && _vm.unreadCount > 0))) {
      setState(() {
        _liveNewMessageCount = 0;
        _bannerDismissed = true;
      });
    }
    if (nearBottom) _markReadAtBottomIfNeeded();
    // Show the jump-to-bottom button once scrolled up from the newest message.
    final show =
        !_isAtLoadedBottom() &&
        (_vm.anchoredHistory || pos.maxScrollExtent - pos.pixels > 120);
    if (show != _showJumpDown) setState(() => _showJumpDown = show);
  }

  void _saveSessionScrollSnapshot() {
    if (!_didInitialScroll ||
        !_scroll.hasClients ||
        widget.initialMessageId != null) {
      return;
    }
    final pos = _scroll.position;
    if (!pos.hasContentDimensions) return;
    _sessionScrollSnapshots[widget.chatId] = _ChatScrollSnapshot(
      pixels: pos.pixels.clamp(pos.minScrollExtent, pos.maxScrollExtent),
      wasAtLoadedBottom: _isAtLoadedBottom(),
    );
  }

  bool _isNearBottom([double threshold = 160]) {
    if (!_scroll.hasClients) return true;
    final pos = _scroll.position;
    return pos.maxScrollExtent - pos.pixels <= threshold;
  }

  bool _isAtLoadedBottom([double threshold = 24]) {
    return !_vm.anchoredHistory && _isNearBottom(threshold);
  }

  void _clearBottomIndicatorsIfNeeded() {
    if (!_scroll.hasClients || !_isAtLoadedBottom()) return;
    var changed = false;
    if (_showJumpDown) {
      _showJumpDown = false;
      changed = true;
    }
    if (_liveNewMessageCount > 0) {
      _liveNewMessageCount = 0;
      changed = true;
    }
    if (!_bannerDismissed) {
      _bannerDismissed = true;
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  bool get _isUserScrolling =>
      _scroll.hasClients && _scroll.position.isScrollingNotifier.value;

  Future<void> _loadOlderPreservingOffset() async {
    if (_loadingOlderFromScroll ||
        _isFillingShortTranscript ||
        !_scroll.hasClients ||
        !_vm.canLoadOlder) {
      return;
    }
    _loadingOlderFromScroll = true;
    final oldPixels = _scroll.position.pixels;
    final oldMax = _scroll.position.maxScrollExtent;
    try {
      final loaded = await _vm.loadOlder();
      if (!loaded) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scroll.hasClients || _scrollTargetId != null) return;
      final delta = _scroll.position.maxScrollExtent - oldMax;
      if (delta > 1) {
        final target = (oldPixels + delta).clamp(
          _scroll.position.minScrollExtent,
          _scroll.position.maxScrollExtent,
        );
        _scroll.jumpTo(target);
      }
    } finally {
      _loadingOlderFromScroll = false;
    }
  }

  void _syncKeyboardInset(double inset) {
    if ((_keyboardInset - inset).abs() < 0.5) return;
    final wasNearBottom = _isNearBottom(260);
    final opening = inset > _keyboardInset;
    _keyboardInset = inset;
    if ((wasNearBottom || opening) && _scrollTargetId == null) {
      _scheduleScrollToBottom(keyboardSettle: true, force: opening);
    }
  }

  void _scheduleScrollToBottom({
    bool animated = true,
    bool keyboardSettle = false,
    bool force = false,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _animateToBottom(
        animated: animated,
        keyboardSettle: keyboardSettle,
        force: force,
      );
    });
  }

  void _animateToBottom({
    bool animated = true,
    bool keyboardSettle = false,
    bool force = false,
  }) {
    if (!_scroll.hasClients) return;
    final target = _scroll.position.maxScrollExtent;
    if (!animated || (target - _scroll.position.pixels).abs() < 48) {
      _scroll.jumpTo(target);
      _settleAtBottom(keyboardSettle: keyboardSettle, force: force);
      return;
    }
    _scroll
        .animateTo(
          target,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          if (mounted) {
            _settleAtBottom(keyboardSettle: keyboardSettle, force: force);
          }
        });
  }

  Future<void> _returnToLatest() async {
    if (_loadingLatestFromAnchor) return;
    if (!_vm.anchoredHistory) {
      _scrollTargetId = null;
      if (_liveNewMessageCount > 0) {
        setState(() {
          _liveNewMessageCount = 0;
          _bannerDismissed = _vm.unreadCount <= 0;
        });
      }
      _animateToBottom(force: true);
      unawaited(_vm.markLoadedMessagesRead());
      return;
    }
    _loadingLatestFromAnchor = true;
    _scrollTargetId = null;
    try {
      final ok = await _vm.loadLatestHistory();
      if (!mounted || !ok) return;
      setState(() {
        _liveNewMessageCount = 0;
        _bannerDismissed = _vm.unreadCount <= 0;
      });
      _scheduleScrollToBottom(force: true);
      unawaited(_vm.markLoadedMessagesRead());
    } finally {
      _loadingLatestFromAnchor = false;
    }
  }

  void _markReadAtBottomIfNeeded() {
    if (!_vm.initialLoaded || _vm.messages.isEmpty || _vm.anchoredHistory) {
      return;
    }
    unawaited(_vm.markLoadedMessagesRead());
  }

  /// Jump to the first unread incoming message (where the "以下为新消息" divider
  /// sits); fall back to the bottom if none is loaded.
  void _jumpToFirstUnread() {
    setState(() {
      _liveNewMessageCount = 0;
      _bannerDismissed = true;
    });
    final i = _vm.messages.indexWhere(
      (m) => !m.isOutgoing && !m.isService && m.id > _vm.lastReadInboxId,
    );
    if (i < 0 || !_scroll.hasClients) {
      _animateToBottom(force: true);
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
      final wasNearBottom = _isNearBottom(72);
      final previousNewestId = _lastNewestMessageId;
      final newest = _vm.messages.isEmpty ? null : _vm.messages.last;
      final appendedNewest =
          newest != null &&
          newest.id != previousNewestId &&
          (previousNewestId == null || newest.id > previousNewestId);
      final restore = _vm.consumeRestoreTop();
      _lastCount = _vm.messages.length;
      _lastNewestMessageId = newest?.id ?? _lastNewestMessageId;
      final shouldAutoScroll =
          _didInitialScroll &&
          restore == null &&
          _scrollTargetId == null &&
          !_vm.anchoredHistory &&
          appendedNewest &&
          (newest.isOutgoing || (wasNearBottom && !_isUserScrolling));
      if (shouldAutoScroll) {
        _liveNewMessageCount = 0;
        _scheduleScrollToBottom(
          animated: newest.isOutgoing,
          keyboardSettle: newest.isOutgoing,
          force: newest.isOutgoing,
        );
      } else if (_didInitialScroll &&
          restore == null &&
          appendedNewest &&
          !newest.isOutgoing &&
          !newest.isService &&
          !wasNearBottom) {
        _liveNewMessageCount++;
        _bannerDismissed = false;
        _bannerTimer?.cancel();
        _bannerTimer = null;
      }
    }
    final target = _vm.consumePendingScrollToId();
    if (target != null) {
      _scrollTargetId = target;
      if (_didInitialScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _ensureMessageVisible(target);
        });
      }
    }
    // Telegram-style entry: once the initial history (incl. the unread
    // boundary) is loaded, jump to the first unread message — or stay at the
    // bottom when caught up. Runs exactly once per chat open.
    if (!_didInitialScroll && _vm.initialLoaded) {
      _didInitialScroll = true;
      if (_vm.messages.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_completeInitialScroll());
        });
      }
    } else if (_vm.initialLoaded && _vm.messages.isNotEmpty) {
      _scheduleShortTranscriptFill();
    }
    // Keep the entry unread banner visible; only live-new-message banners
    // should auto-hide after a short delay.
    final keepEntryUnreadBanner = _liveNewMessageCount == 0;
    if (_vm.unreadCount > 0 &&
        _liveNewMessageCount == 0 &&
        _bannerTimer == null &&
        !_bannerDismissed &&
        !keepEntryUnreadBanner) {
      _bannerTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _bannerDismissed = true);
      });
    }
    setState(() {});
  }

  int _firstUnreadIndex() => _vm.messages.indexWhere(
    (m) => !m.isOutgoing && !m.isService && m.id > _vm.lastReadInboxId,
  );

  /// One-time positioning when a chat opens. This must never block painting:
  /// a hidden transcript reads as a black screen in dark mode. We jump to the
  /// deterministic estimate immediately and then do one zero-duration correction
  /// after layout, without waiting to reveal the UI.
  Future<void> _completeInitialScroll() async {
    if (_shouldRestoreSessionScroll) {
      unawaited(_restoreSessionScrollPosition());
    } else {
      unawaited(_positionInitialTranscript());
      _scheduleShortTranscriptFill();
    }
  }

  Future<void> _restoreSessionScrollPosition() async {
    final snapshot = _sessionScrollSnapshot;
    if (snapshot == null || !_scroll.hasClients) return;
    _jumpToSessionScrollSnapshot(snapshot);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scroll.hasClients) return;

    var guard = 0;
    while (mounted &&
        _scroll.hasClients &&
        _vm.canLoadOlder &&
        _scroll.position.maxScrollExtent + 24 < snapshot.pixels &&
        guard < 6) {
      final loaded = await _vm.loadOlderLocal(restorePosition: false);
      if (!loaded) break;
      await WidgetsBinding.instance.endOfFrame;
      guard++;
    }

    if (!mounted || !_scroll.hasClients) return;
    _jumpToSessionScrollSnapshot(snapshot);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scroll.hasClients) return;
    _jumpToSessionScrollSnapshot(snapshot);
    _saveSessionScrollSnapshot();
  }

  void _jumpToSessionScrollSnapshot(_ChatScrollSnapshot snapshot) {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final target = snapshot.pixels.clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    _scroll.jumpTo(target);
  }

  Future<void> _positionInitialTranscript() async {
    if (!_scroll.hasClients) return;
    _jumpToInitialEstimate();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scroll.hasClients) return;
    await _correctInitialPosition();
  }

  void _jumpToInitialEstimate() {
    if (!_scroll.hasClients || _vm.messages.isEmpty) return;
    final position = _initialPositionEstimate();
    if (position == null) return;
    _scroll.jumpTo(position);
  }

  double? _initialPositionEstimate() {
    if (!_scroll.hasClients || _vm.messages.isEmpty) return null;
    final max = _scroll.position.maxScrollExtent;
    final target = widget.initialMessageId ?? _scrollTargetId;
    if (target != null) {
      _scrollTargetId = target;
      return _estimateMessageOffset(target, _initialTargetAlignment);
    }
    if (_vm.anchoredHistory) {
      return null;
    }
    if (_openAtLatest) {
      return max;
    }
    final i = _firstUnreadIndex();
    final boundaryLoaded = _isUnreadBoundaryLoaded();
    if (_vm.unreadCount <= 0 || i < 0 || !boundaryLoaded) {
      if (_vm.unreadCount > 0 && _vm.lastReadInboxId > 0) {
        _scrollTargetId = _vm.lastReadInboxId;
        return _estimateMessageOffset(
          _vm.lastReadInboxId,
          _initialTargetAlignment,
        );
      }
      return max;
    }
    return _estimateMessageOffset(
      _vm.messages[i].id,
      _initialUnreadAlignment,
      beforeUnreadDivider: true,
    );
  }

  Future<bool> _correctInitialPosition() async {
    if (!_scroll.hasClients) return false;
    final target = widget.initialMessageId ?? _scrollTargetId;
    if (target != null) {
      _scrollTargetId = target;
      final corrected = await _ensureKeyVisible(
        _targetKey,
        alignment: _initialTargetAlignment,
      );
      if (corrected && mounted && _scrollTargetId == target) {
        setState(() => _scrollTargetId = null);
      }
      return corrected;
    }
    if (_vm.anchoredHistory) return true;
    if (_openAtLatest) {
      _scrollToBottom(settle: true, forceSettle: true);
      unawaited(_vm.markLoadedMessagesRead());
      return true;
    }
    final i = _firstUnreadIndex();
    final boundaryLoaded = _isUnreadBoundaryLoaded();
    if (_vm.unreadCount > 0 && i >= 0 && boundaryLoaded) {
      final corrected = await _ensureKeyVisible(
        _unreadKey,
        alignment: _initialUnreadAlignment,
      );
      if (corrected) return true;
      return false;
    }
    if (_vm.unreadCount > 0 && _vm.lastReadInboxId > 0) {
      _scrollTargetId = _vm.lastReadInboxId;
      final corrected = await _ensureKeyVisible(
        _targetKey,
        alignment: _initialTargetAlignment,
      );
      if (corrected) return true;
    }
    _scrollToBottom();
    return true;
  }

  Future<bool> _ensureKeyVisible(
    GlobalKey key, {
    required double alignment,
  }) async {
    final ctx = key.currentContext;
    if (ctx == null || !ctx.mounted) return false;
    await Scrollable.ensureVisible(ctx, alignment: alignment);
    return true;
  }

  double? _estimateMessageOffset(
    int messageId,
    double alignment, {
    bool beforeUnreadDivider = false,
  }) {
    final entries = _transcriptEntries(
      context.read<ThemeController>().groupImageMessages,
    );
    if (entries.isEmpty || !_scroll.hasClients) return null;
    final entryIndex = entries.indexWhere(
      (entry) => entry.messages.any((message) => message.id == messageId),
    );
    if (entryIndex < 0) return null;
    final estimatedContentExtent = _estimatedTranscriptExtent(entries);
    if (estimatedContentExtent <= 0) return null;
    var before = 8.0; // ListView vertical padding top
    for (var i = 0; i < entryIndex; i++) {
      before += _estimatedEntryExtent(entries[i]);
    }
    final entry = entries[entryIndex];
    final messages = _transcriptCacheMessages ?? _vm.messages;
    if (!beforeUnreadDivider &&
        _needsUnreadDivider(entry.startIndex, messages: messages)) {
      before += _estimatedUnreadDividerExtent;
    }
    final viewport = _scroll.position.viewportDimension;
    final estimatedScrollable = math.max(
      1.0,
      estimatedContentExtent - viewport,
    );
    final actualScrollable = math.max(1.0, _scroll.position.maxScrollExtent);
    final scale = actualScrollable / estimatedScrollable;
    final raw = (before - viewport * alignment) * scale;
    return raw.clamp(0.0, _scroll.position.maxScrollExtent);
  }

  double _estimatedTranscriptExtent(List<_TranscriptEntry> entries) {
    var extent = 16.0; // ListView vertical padding
    for (final entry in entries) {
      extent += _estimatedEntryExtent(entry);
    }
    return extent;
  }

  static const _estimatedUnreadDividerExtent = 33.0;
  static const _estimatedSeparatorExtent = 34.0;

  double _estimatedEntryExtent(_TranscriptEntry entry) {
    var extent = 0.0;
    final messages = _transcriptCacheMessages ?? _vm.messages;
    if (_needsUnreadDivider(entry.startIndex, messages: messages)) {
      extent += _estimatedUnreadDividerExtent;
    }
    if (_needsSeparator(entry.startIndex, messages: messages)) {
      extent += _estimatedSeparatorExtent;
    }
    final first = entry.first;
    if (first.isService) return extent + 38;
    if (entry.isImageGroup) {
      return extent + _estimatedImageGroupExtent(entry);
    }
    return extent + _estimatedMessageExtent(first);
  }

  double _estimatedImageGroupExtent(_TranscriptEntry entry) {
    final width = MediaQuery.sizeOf(context).width;
    final maxWidth = _messageMediaMaxWidth(width);
    final layout = buildTelegramMediaAlbumLayout(
      items: [
        for (final message in entry.messages.take(9))
          MediaAlbumItem(
            width: message.imageWidth,
            height: message.imageHeight,
          ),
      ],
      maxWidth: maxWidth - 8,
      gap: 4,
      maxSingleHeight: 300,
      minRowHeight: 82,
      maxRowHeight: 230,
    );
    final hasCaption = entry.messages.any((m) => m.text.trim().isNotEmpty);
    return layout.height + (hasCaption ? 38 : 0) + 16;
  }

  double _estimatedMessageExtent(ChatMessage message) {
    if (message.animatedSticker != null || message.videoSticker != null) {
      return 180;
    }
    if (message.image != null || message.video != null) {
      final h = message.imageHeight ?? 180;
      final w = message.imageWidth ?? 180;
      final scaled = w <= 0 ? 180.0 : _messageMediaMaxWidth() * h / w;
      return scaled.clamp(120.0, 310.0) + 16;
    }
    if (message.document != null ||
        message.music != null ||
        message.voice != null ||
        message.location != null ||
        message.isCall) {
      return 78;
    }
    if (message.diceEmoji != null || message.stickerFileId != null) {
      return 94;
    }
    final text = message.text.trim();
    final width = MediaQuery.sizeOf(context).width;
    final charsPerLine = math.max(10, (width * 0.52 / 15).floor());
    final lines = text.isEmpty
        ? 1
        : (text.length / charsPerLine).ceil().clamp(1, 8);
    final sender = _vm.isGroup && !message.isOutgoing ? 18.0 : 0.0;
    final reply = message.replyToMessageId != null ? 42.0 : 0.0;
    final buttons = message.buttonRows.isNotEmpty
        ? message.buttonRows.length * 38.0
        : 0.0;
    return 30 + sender + reply + lines * 22.0 + buttons;
  }

  void _scrollToBottom({bool settle = false, bool forceSettle = false}) {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
    _markReadAtBottomIfNeeded();
    _clearBottomIndicatorsIfNeeded();
    if (settle) {
      _settleAtBottom(keyboardSettle: true, force: forceSettle);
    }
  }

  void _settleAtBottom({bool keyboardSettle = false, bool force = false}) {
    final generation = ++_bottomSettleGeneration;
    () async {
      final delays = keyboardSettle
          ? const <Duration>[
              Duration.zero,
              Duration(milliseconds: 16),
              Duration(milliseconds: 48),
              Duration(milliseconds: 120),
              Duration(milliseconds: 240),
              Duration(milliseconds: 360),
            ]
          : const <Duration>[
              Duration.zero,
              Duration(milliseconds: 16),
              Duration(milliseconds: 48),
              Duration(milliseconds: 120),
            ];
      for (final delay in delays) {
        if (delay > Duration.zero) {
          await Future<void>.delayed(delay);
        }
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || generation != _bottomSettleGeneration) return;
        if (_scroll.hasClients && (force || _isNearBottom(420))) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
          _markReadAtBottomIfNeeded();
          _clearBottomIndicatorsIfNeeded();
        }
      }
    }();
  }

  void _scheduleShortTranscriptFill() {
    if (_shortTranscriptFillScheduled || _isFillingShortTranscript) return;
    _shortTranscriptFillScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shortTranscriptFillScheduled = false;
      unawaited(_fillShortTranscript());
    });
  }

  Future<void> _fillShortTranscript() async {
    if (!mounted ||
        !_scroll.hasClients ||
        !_vm.initialLoaded ||
        _vm.anchoredHistory ||
        _scrollTargetId != null ||
        !_vm.canLoadOlder) {
      return;
    }
    if (_scroll.position.maxScrollExtent > 24) return;

    _isFillingShortTranscript = true;
    try {
      var guard = 0;
      while (mounted &&
          _scroll.hasClients &&
          _vm.canLoadOlder &&
          _scroll.position.maxScrollExtent <= 24 &&
          guard < 8) {
        final loaded = await _vm.loadOlder();
        if (!loaded) break;
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || !_scroll.hasClients) break;
        _positionAfterShortFill();
        guard++;
      }
    } finally {
      _isFillingShortTranscript = false;
    }
  }

  void _positionAfterShortFill() {
    if (_openAtLatest) {
      _scrollToBottom(settle: true, forceSettle: true);
      return;
    }
    final i = _firstUnreadIndex();
    final boundaryLoaded = _isUnreadBoundaryLoaded();
    if (_vm.unreadCount > 0 && i >= 0 && boundaryLoaded) {
      final ctx = _unreadKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: 0.12);
        return;
      }
    }
    _scrollToBottom();
  }

  bool _isUnreadBoundaryLoaded() {
    if (_vm.messages.isEmpty) return false;
    return _vm.lastReadInboxId <= 0 ||
        _vm.messages.first.id <= _vm.lastReadInboxId;
  }

  bool get _canBackSwipe =>
      widget.showBackButton && !_isSelecting && _actionTarget == null;

  void _onBackSwipePointerDown(PointerDownEvent event) {
    if (!_canBackSwipe) return;
    _backSwipeDx = 0;
    _backSwipeDy = 0;
    _backSwipeVelocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _onBackSwipePointerMove(PointerMoveEvent event) {
    final tracker = _backSwipeVelocity;
    if (tracker == null || !_canBackSwipe) return;
    _backSwipeDx += event.delta.dx;
    _backSwipeDy += event.delta.dy;
    tracker.addPosition(event.timeStamp, event.position);
  }

  void _onBackSwipePointerEnd(PointerEvent event) {
    final tracker = _backSwipeVelocity;
    if (tracker == null) return;
    final velocity = tracker.getVelocity().pixelsPerSecond.dx;
    final horizontal = _backSwipeDx.abs() > _backSwipeDy.abs() * 1.65;
    final shouldPop =
        _canBackSwipe &&
        horizontal &&
        _backSwipeDx > 72 &&
        (velocity > 520 || _backSwipeDx > 118);
    _backSwipeVelocity = null;
    _backSwipeDx = 0;
    _backSwipeDy = 0;
    if (shouldPop) unawaited(_popFromBackSwipe());
  }

  Future<void> _popFromBackSwipe() async {
    if (_backSwipePopping || !mounted) return;
    _backSwipePopping = true;
    try {
      final onBack = widget.onBack;
      if (onBack != null) {
        onBack();
      } else {
        await Navigator.of(context).maybePop();
      }
    } finally {
      _backSwipePopping = false;
    }
  }

  bool get _isSelecting => _selectionAnchorId != null;

  void _enterSelection(ChatMessage message) {
    setState(() {
      _actionTarget = null;
      _actionRect = null;
      _actionSource = MessageActionSource.normal;
      _reactionExpanded = false;
      _selectionAnchorId = message.id;
      _selectedMessageIds
        ..clear()
        ..add(message.id);
      _selectionScrollingUp = false;
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionAnchorId = null;
      _selectedMessageIds.clear();
    });
  }

  void _toggleSelection(Iterable<ChatMessage> messages) {
    final ids = messages.where((m) => !m.isService).map((m) => m.id).toList();
    if (ids.isEmpty) return;
    setState(() {
      final allSelected = ids.every(_selectedMessageIds.contains);
      if (allSelected) {
        _selectedMessageIds.removeAll(ids);
      } else {
        _selectedMessageIds.addAll(ids);
      }
      if (_selectedMessageIds.isEmpty) _selectionAnchorId = null;
    });
  }

  List<int> _orderedSelectedIds() => _vm.messages
      .where((m) => _selectedMessageIds.contains(m.id))
      .map((m) => m.id)
      .toList();

  int _approxVisibleMessageIndex({required bool topEdge}) {
    if (!_scroll.hasClients || _vm.messages.isEmpty) return 0;
    final pos = _scroll.position;
    final max = math.max(pos.maxScrollExtent, 1.0);
    final viewport = math.max(pos.viewportDimension, 1.0);
    final pixels = topEdge
        ? pos.pixels
        : math.min(pos.maxScrollExtent, pos.pixels + viewport);
    final frac = (pixels / max).clamp(0.0, 1.0);
    return (frac * (_vm.messages.length - 1)).round().clamp(
      0,
      _vm.messages.length - 1,
    );
  }

  void _selectToVisibleEdge() {
    final anchorId = _selectionAnchorId;
    if (anchorId == null || _vm.messages.isEmpty) return;
    final anchorIndex = _vm.messages.indexWhere((m) => m.id == anchorId);
    if (anchorIndex < 0) return;
    final edgeIndex = _approxVisibleMessageIndex(
      topEdge: _selectionScrollingUp,
    );
    final start = math.min(anchorIndex, edgeIndex);
    final end = math.max(anchorIndex, edgeIndex);
    setState(() {
      for (final message in _vm.messages.getRange(start, end + 1)) {
        if (!message.isService) _selectedMessageIds.add(message.id);
      }
    });
  }

  Future<void> _forwardSelected() async {
    final ids = _orderedSelectedIds();
    if (ids.isEmpty) return;
    final result = await Navigator.of(context).push<ChatPickerResult>(
      MaterialPageRoute(
        builder: (_) => const ChatPickerView(
          title: AppStringKeys.chatForwardToTitle,
          showForwardOptions: true,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final target = result.chat;
    try {
      await _vm.forwardMany(ids, target.id, options: result.forwardOptions);
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.chatMessagesForwardedCount, {
          'value1': ids.length,
        }),
      );
      _exitSelection();
    } catch (e) {
      if (!mounted) return;
      _showForwardFailure(e);
    }
  }

  Future<void> _saveSelected() async {
    final ids = _orderedSelectedIds();
    if (ids.isEmpty) return;
    try {
      await _vm.saveToFavoritesMany(ids);
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.chatMessagesSavedCount, {
          'value1': ids.length,
        }),
      );
      _exitSelection();
    } catch (e) {
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.chatSaveFailed, {'value1': e}),
      );
    }
  }

  Future<void> _deleteSelected() async {
    final ids = _orderedSelectedIds();
    if (ids.isEmpty) return;
    final confirmed = await confirmDialog(
      context,
      title: AppStringKeys.chatDeleteMessagesQuestion,
      message: AppStrings.t(
        AppStringKeys.chatDeleteSelectedMessagesConfirmation,
        {'value1': ids.length},
      ),
      confirmText: AppStringKeys.chatDelete,
      destructive: true,
    );
    if (!mounted || !confirmed) return;
    _vm.deleteMessages(ids);
    _exitSelection();
  }

  @override
  void dispose() {
    _saveSessionScrollSnapshot();
    _tabBarVisibility?.releaseChatSuppression();
    _bannerTimer?.cancel();
    _vm.removeListener(_onModel);
    _vm.onDisappear();
    _vm.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _needsUnreadDivider(int index, {List<ChatMessage>? messages}) {
    messages ??= _vm.messages;
    if (_vm.unreadCount <= 0) return false;
    if (index < 0 || index >= messages.length) return false;
    final m = messages[index];
    if (m.isOutgoing || m.isService || m.id <= _vm.lastReadInboxId) {
      return false;
    }
    if (index == 0) return true;
    return messages[index - 1].id <= _vm.lastReadInboxId;
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
              AppStringKeys.chatNewMessagesDivider.l10n(context),
              style: TextStyle(fontSize: 12, color: c.textSecondary),
            ),
          ),
          Expanded(child: Divider(color: c.divider, height: 1)),
        ],
      ),
    );
  }

  bool _needsSeparator(int index, {List<ChatMessage>? messages}) {
    messages ??= _vm.messages;
    if (index < 0 || index >= messages.length) return false;
    if (index == 0) return true;
    return messages[index].date - messages[index - 1].date > _separatorGap;
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

  void _playVideo(ChatMessage message, {bool muted = false}) {
    final v = message.video;
    if (v == null) return;
    final session = _videoSession(message);
    if (VideoSplitController.instance.isOpen) {
      VideoSplitController.instance.play(session);
      return;
    }
    if (VideoPiPController.instance.isOpen) {
      VideoPiPController.instance.play(session);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (routeContext) => VideoPlayerView(
          video: v,
          thumb: message.image,
          width: message.imageWidth,
          height: message.imageHeight,
          sourceChatId: widget.chatId,
          messageId: message.id,
          initialMuted: muted,
          onSwitchMode: (mode) => _switchVideoMode(routeContext, message, mode),
        ),
      ),
    );
  }

  VideoSplitSession _videoSession(ChatMessage message) {
    return VideoSplitSession(
      chatId: widget.chatId,
      title: widget.title,
      video: message.video!,
      thumb: message.image,
      width: message.imageWidth,
      height: message.imageHeight,
      messageId: message.id,
    );
  }

  void _switchVideoMode(
    BuildContext routeContext,
    ChatMessage message,
    VideoDisplayMode mode,
  ) {
    switch (mode) {
      case VideoDisplayMode.fullscreen:
        break;
      case VideoDisplayMode.pictureInPicture:
        _showVideoPictureInPicture(
          routeContext,
          message,
          widget.chatId,
          widget.title,
        );
        Navigator.of(routeContext).maybePop();
      case VideoDisplayMode.split:
        VideoSplitController.instance.play(
          VideoSplitSession(
            chatId: widget.chatId,
            title: widget.title,
            video: message.video!,
            thumb: message.image,
            width: message.imageWidth,
            height: message.imageHeight,
            messageId: message.id,
          ),
        );
        Navigator.of(routeContext).maybePop();
    }
  }

  static void _showVideoPictureInPicture(
    BuildContext context,
    ChatMessage message,
    int chatId,
    String title,
  ) {
    final v = message.video;
    if (v == null) return;
    final initialSession = VideoSplitSession(
      chatId: chatId,
      title: title,
      video: v,
      thumb: message.image,
      width: message.imageWidth,
      height: message.imageHeight,
      messageId: message.id,
    );
    final pip = VideoPiPController.instance;
    if (_globalPictureInPictureVideo != null) {
      pip.play(initialSession);
      return;
    }
    if (pip.isOpen) {
      pip.play(initialSession);
      return;
    }
    pip.play(initialSession);
    _globalPictureInPictureVideo?.remove();
    _globalPictureInPictureVideo = null;

    final overlay = Overlay.of(context, rootOverlay: true);
    final screen = MediaQuery.sizeOf(context);
    const margin = 16.0;
    var aspect = _sessionAspect(initialSession);
    var boxWidth = (screen.width * 0.46).clamp(220.0, 360.0);
    var boxHeight = (boxWidth / aspect).clamp(130.0, 260.0);
    boxWidth = boxHeight * aspect;
    var displayedVideoId = initialSession.video.id;
    var offset = Offset(
      screen.width - boxWidth - margin,
      screen.height - boxHeight - MediaQuery.paddingOf(context).bottom - 110,
    );

    late final OverlayEntry entry;
    void close() {
      entry.remove();
      if (_globalPictureInPictureVideo == entry) {
        _globalPictureInPictureVideo = null;
      }
      if (pip.session?.video.id == displayedVideoId) {
        pip.close();
      }
    }

    entry = OverlayEntry(
      builder: (overlayContext) => StatefulBuilder(
        builder: (context, setOverlayState) {
          final media = MediaQuery.sizeOf(context);
          final padding = MediaQuery.paddingOf(context);
          void clampOffset() {
            offset = Offset(
              offset.dx.clamp(margin, media.width - boxWidth - margin),
              offset.dy.clamp(
                padding.top + margin,
                media.height - boxHeight - padding.bottom - margin,
              ),
            );
          }

          void syncSession(VideoSplitSession session) {
            if (session.video.id == displayedVideoId) return;
            displayedVideoId = session.video.id;
            aspect = _sessionAspect(session);
            boxHeight = (boxWidth / aspect).clamp(110.0, media.height * 0.72);
            boxWidth = boxHeight * aspect;
            clampOffset();
          }

          void move(DragUpdateDetails details) {
            setOverlayState(() {
              offset += details.delta;
              clampOffset();
            });
          }

          void resizeFromCorner(
            DragUpdateDetails details, {
            required int horizontalSign,
            required int verticalSign,
          }) {
            setOverlayState(() {
              final oldWidth = boxWidth;
              final oldHeight = boxHeight;
              final minW = math.min(180.0, media.width - margin * 2);
              final maxW = math.max(minW, media.width - margin * 2);
              final widthFromX = boxWidth + details.delta.dx * horizontalSign;
              final widthFromY =
                  boxWidth + details.delta.dy * verticalSign * aspect;
              final nextWidth =
                  (widthFromX - boxWidth).abs() > (widthFromY - boxWidth).abs()
                  ? widthFromX
                  : widthFromY;
              boxWidth = nextWidth.clamp(minW, maxW);
              boxHeight = boxWidth / aspect;
              if (boxHeight > media.height * 0.72) {
                boxHeight = media.height * 0.72;
                boxWidth = boxHeight * aspect;
              }
              if (boxHeight < 110) {
                boxHeight = 110;
                boxWidth = boxHeight * aspect;
              }
              if (horizontalSign < 0) {
                offset = offset.translate(oldWidth - boxWidth, 0);
              }
              if (verticalSign < 0) {
                offset = offset.translate(0, oldHeight - boxHeight);
              }
              clampOffset();
            });
          }

          return AnimatedBuilder(
            animation: pip,
            builder: (context, _) {
              final session = pip.session;
              if (session == null) return const SizedBox.shrink();
              syncSession(session);
              return Positioned(
                left: offset.dx,
                top: offset.dy,
                width: boxWidth,
                height: boxHeight,
                child: Material(
                  type: MaterialType.transparency,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          onPanUpdate: move,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: VideoPlayerView(
                              key: ValueKey(session.video.id),
                              video: session.video,
                              thumb: session.thumb,
                              width: session.width,
                              height: session.height,
                              presentation:
                                  VideoPlayerPresentation.pictureInPicture,
                              compactControls: true,
                              onClose: close,
                              sourceChatId: session.chatId,
                              messageId: session.messageId,
                              currentMode: VideoDisplayMode.pictureInPicture,
                              onSwitchMode: (mode) => _switchPiPSessionMode(
                                context,
                                close,
                                mode,
                                session,
                              ),
                            ),
                          ),
                        ),
                      ),
                      _PiPCornerHandle(
                        alignment: Alignment.topLeft,
                        onDrag: (details) => resizeFromCorner(
                          details,
                          horizontalSign: -1,
                          verticalSign: -1,
                        ),
                      ),
                      _PiPCornerHandle(
                        alignment: Alignment.topRight,
                        onDrag: (details) => resizeFromCorner(
                          details,
                          horizontalSign: 1,
                          verticalSign: -1,
                        ),
                      ),
                      _PiPCornerHandle(
                        alignment: Alignment.bottomLeft,
                        onDrag: (details) => resizeFromCorner(
                          details,
                          horizontalSign: -1,
                          verticalSign: 1,
                        ),
                      ),
                      _PiPCornerHandle(
                        alignment: Alignment.bottomRight,
                        onDrag: (details) => resizeFromCorner(
                          details,
                          horizontalSign: 1,
                          verticalSign: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
    _globalPictureInPictureVideo = entry;
    overlay.insert(entry);
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

  void _openSticker(ChatMessage message) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StickerViewer(message: message),
      ),
    );
  }

  Future<void> _pressMessageButton(
    ChatMessage message,
    MessageButton button,
  ) async {
    final url = button.url;
    if (url != null && url.isNotEmpty) {
      await openLink(context, url);
      return;
    }
    final userId = button.userId;
    if (userId != null && userId > 0) {
      await openLink(context, 'tg://user?id=$userId');
      return;
    }
    final copyText = button.copyText;
    if (copyText != null && copyText.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: copyText));
      if (mounted) {
        showToast(context, AppStringKeys.topicPostContentCopied);
      }
      return;
    }
    if (button.isCallback) {
      try {
        final answer = await _vm.answerCallbackButton(message.id, button);
        if (!mounted) return;
        final answerUrl = answer.str('url');
        if (answerUrl != null && answerUrl.isNotEmpty) {
          await openLink(context, answerUrl);
          return;
        }
        final text = answer.str('text');
        if (text != null && text.isNotEmpty) {
          showToast(context, text);
        }
      } catch (e) {
        if (!mounted) return;
        showToast(context, AppStringKeys.topicPostContentActionFailed);
      }
      return;
    }
    if (button.isReplyKeyboard && button.type == 'keyboardButtonTypeText') {
      _vm.sendKeyboardButtonText(button.text);
      return;
    }
    if (button.switchInlineQuery != null) {
      showToast(context, AppStringKeys.chatInlineSwitchButtonUnsupported);
      return;
    }
    showToast(context, AppStringKeys.chatButtonUnsupported);
  }

  Future<void> _perform(MessageAction action, ChatMessage message) async {
    setState(() {
      _actionTarget = null;
      _actionSource = MessageActionSource.normal;
    });
    switch (action) {
      case MessageAction.copy:
        unawaited(Clipboard.setData(ClipboardData(text: message.text)));
      case MessageAction.selectText:
        await _showTextSelection(message);
      case MessageAction.edit:
        unawaited(_editMessage(message));
      case MessageAction.translate:
        unawaited(_translateMessage(message));
      case MessageAction.reply:
        _vm.setReply(message);
      case MessageAction.forward:
        unawaited(_forwardMessage(message));
      case MessageAction.report:
        final confirmed = await confirmDialog(
          context,
          title: AppStringKeys.chatReportTitle,
          message: AppStringKeys.chatReportMessage,
          confirmText: AppStringKeys.chatReportConfirm,
          destructive: true,
        );
        if (!mounted || !confirmed) return;
        try {
          await _vm.reportMessage(message);
          if (!mounted) return;
          showToast(context, AppStringKeys.chatReportSent);
        } catch (e) {
          if (!mounted) return;
          showToast(
            context,
            AppStrings.t(AppStringKeys.chatReportFailed, {'value1': e}),
          );
        }
      case MessageAction.block:
        final confirmed = await confirmDialog(
          context,
          title: AppStringKeys.chatBlockUserTitle,
          message: AppStringKeys.chatBlockUserMessage,
          confirmText: AppStringKeys.chatBlockUserConfirm,
          destructive: true,
        );
        if (!mounted || !confirmed) return;
        try {
          await _vm.blockAndReportSender(message);
          if (!mounted) return;
          showToast(context, AppStringKeys.chatBlockUserDone);
        } catch (e) {
          if (!mounted) return;
          showToast(
            context,
            AppStrings.t(AppStringKeys.chatBlockUserFailed, {'value1': e}),
          );
        }
      case MessageAction.playMuted:
        _playVideo(message, muted: true);
      case MessageAction.addToPlaylist:
        final added = MusicPlayerController.shared.addToPlaylist(message);
        showToast(
          context,
          added
              ? AppStringKeys.musicPlayerAddedToPlaylist
              : AppStringKeys.musicPlayerAlreadyInPlaylist,
        );
      case MessageAction.multiSelect:
        _enterSelection(message);
      case MessageAction.pinTodo:
        try {
          await _vm.pinTodo(message);
          if (!mounted) return;
          showToastOverlay(
            Overlay.of(context),
            telegramText(AppStringKeys.chatTodoSetSuccess),
          );
        } catch (e) {
          if (!mounted) return;
          showToast(
            context,
            AppStrings.t(AppStringKeys.chatTodoSetFailed, {'value1': e}),
          );
        }
      case MessageAction.unpinTodo:
        try {
          await _vm.unpinTodo(message);
          if (!mounted) return;
          showToastOverlay(
            Overlay.of(context),
            telegramText(AppStringKeys.chatTodoUnsetSuccess),
          );
        } catch (e) {
          if (!mounted) return;
          showToast(
            context,
            AppStrings.t(AppStringKeys.chatTodoUnsetFailed, {'value1': e}),
          );
        }
      case MessageAction.save:
        try {
          await _vm.saveToFavorites(message.id);
          if (!mounted) return;
          showToast(context, AppStringKeys.chatSavedToSavedMessages);
        } catch (e) {
          if (!mounted) return;
          showToast(
            context,
            AppStrings.t(AppStringKeys.chatSaveFailed, {'value1': e}),
          );
        }
      case MessageAction.saveSticker:
        final id = message.stickerFileId ?? message.animatedSticker?.id;
        if (id != null) {
          _vm.saveFavoriteSticker(id);
          showToast(context, AppStringKeys.chatStickerAddSuccess);
        }
      case MessageAction.viewStickerSet:
        final sid = message.stickerSetId;
        if (sid != null) {
          unawaited(
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => StickerSetDetailView(setId: sid),
              ),
            ),
          );
        }
      case MessageAction.delete:
        await _performDeleteAction(message);
    }
  }

  Future<void> _performDeleteAction(ChatMessage message) async {
    final options = await _confirmMessageDeleteOptions(message);
    if (!mounted || options == null) return;
    try {
      if (options.reportSpam && !options.blockSender) {
        await _vm.reportMessage(message);
      }
      if (options.blockSender) {
        await _vm.blockAndReportSender(message);
      }
      if (options.deleteAllFromSender) {
        await _vm.deleteMessagesFromSender(message);
      } else if (options.deleteMessage) {
        _vm.deleteMessage(message.id);
      }
      if (!mounted) return;
      showToast(context, AppStringKeys.chatDeleteActionsDone);
    } catch (e) {
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.chatDeleteActionsFailed, {'value1': e}),
      );
    }
  }

  Future<_MessageDeleteOptions?> _confirmMessageDeleteOptions(
    ChatMessage message,
  ) {
    final senderName = _deleteSenderName(message);
    return showGeneralDialog<_MessageDeleteOptions>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppStrings.t(AppStringKeys.countryPickerCancel),
      barrierColor: Colors.black.withValues(alpha: 0.42),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, _) => _MessageDeleteOptionsDialog(
        canActOnSender: !message.isOutgoing && message.senderId != null,
        canDeleteAllFromSender:
            !message.isOutgoing &&
            message.senderId != null &&
            _vm.canDeleteMessagesBySender,
        senderName: senderName,
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  String _deleteSenderName(ChatMessage message) {
    final name = (message.senderName ?? message.senderTitle ?? '').trim();
    if (name.isNotEmpty) return name;
    return AppStrings.t(AppStringKeys.topicChatUsers);
  }

  Future<void> _showTextSelection(ChatMessage message) async {
    if (message.text.isEmpty || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _MessageTextSelectionSheet(text: message.text),
    );
  }

  Future<void> _showReactionUsers(
    ChatMessage message,
    MessageReaction reaction,
  ) async {
    if (!mounted || message.reactions.isEmpty) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppStrings.t(AppStringKeys.musicPlayerClose),
      barrierColor: Colors.black.withValues(alpha: 0.46),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, _, _) => _ReactionUsersSheet(
        viewModel: _vm,
        message: message,
        initialReaction: reaction,
      ),
      transitionBuilder: (context, animation, _, child) {
        final offset =
            Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
        return SlideTransition(position: offset, child: child);
      },
    );
  }

  Future<bool> _translateMessage(
    ChatMessage message, {
    bool showErrors = true,
  }) async {
    final translation = context.read<TranslationController>();
    if (!translation.enabled) return true;
    final sourceText = _translationSourceText(message);
    if (sourceText.trim().isEmpty) return true;
    final targetLanguage = _translationTargetLanguage(translation);
    try {
      if (translation.provider == TranslationProvider.iosSystem ||
          translation.provider == TranslationProvider.androidMlKit) {
        await _vm.translateMessageExternally(
          message.id,
          targetLanguage,
          () => NativeTranslationApi.translate(
            text: sourceText,
            sourceLanguageCode: 'autodetect',
            targetLanguageCode: targetLanguage,
          ),
          showLoading: defaultTargetPlatform != TargetPlatform.iOS,
        );
      } else if (translation.provider == TranslationProvider.tdlib) {
        await _vm.translateMessage(message.id, targetLanguage);
      } else {
        await _vm.translateMessageExternally(
          message.id,
          targetLanguage,
          () => ThirdPartyTranslationApi.translate(
            provider: translation.provider,
            text: sourceText,
            sourceLanguageCode: 'autodetect',
            targetLanguageCode: targetLanguage,
            lingvaEndpoint: translation.lingvaEndpoint,
            libreTranslateEndpoint: translation.libreTranslateEndpoint,
            libreTranslateApiKey: translation.libreTranslateApiKey,
          ),
        );
      }
      return true;
    } catch (e) {
      if (!mounted) return false;
      if (showErrors) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.chatTranslateFailed, {'value1': e}),
        );
      }
      return false;
    }
  }

  String _translationSourceText(ChatMessage message) {
    final parts = [
      message.text,
      message.linkPreview?.title ?? '',
      message.linkPreview?.description ?? '',
    ].where((p) => p.trim().isNotEmpty);
    return parts.join('\n');
  }

  String _translationTargetLanguage(TranslationController translation) {
    if (translation.targetLanguageCode != 'auto') {
      return translation.targetLanguageCode;
    }
    final locale = Localizations.localeOf(context);
    final country = locale.countryCode?.toUpperCase();
    if (locale.languageCode == 'zh') {
      return switch (country) {
        'TW' || 'HK' || 'MO' => 'zh-Hant',
        _ => 'zh-Hans',
      };
    }
    return locale.languageCode;
  }

  Future<void> _editMessage(ChatMessage message) async {
    final edited = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EditFieldView(
          title: AppStringKeys.chatEditMessageTitle,
          initial: message.text,
          hint: AppStringKeys.tabMessages,
          multiline: true,
          maxLength: 4096,
        ),
      ),
    );
    if (!mounted || edited == null || edited == message.text) return;
    if (edited.trim().isEmpty) {
      showToast(context, AppStringKeys.chatMessageRequired);
      return;
    }
    _vm.editMessageText(message.id, edited);
  }

  void _openSenderProfile(ChatMessage m) {
    final uid = m.isOutgoing
        ? _vm.meId
        : (_vm.isGroup ? m.senderId : _vm.peerUserId);
    if (uid == null || uid <= 0) {
      return; // channels post as the chat, not a user
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileDetailView(
          userId: uid,
          name: m.isOutgoing ? _vm.meName : (m.senderName ?? _vm.peerTitle),
        ),
      ),
    );
  }

  void _startCall(bool isVideo) {
    final uid = _vm.peerUserId;
    if (uid == null) {
      showToast(context, AppStringKeys.chatContactCallsOnly);
      return;
    }
    context.read<CallManager>().startCall(uid, isVideo);
  }

  Future<void> _forwardMessage(ChatMessage message) async {
    final result = await Navigator.of(context).push<ChatPickerResult>(
      MaterialPageRoute(
        builder: (_) => const ChatPickerView(
          title: AppStringKeys.chatForwardToTitle,
          showForwardOptions: true,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final target = result.chat;
    try {
      await _vm.forward(message.id, target.id, options: result.forwardOptions);
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.chatForwardedToName, {
          'value1': target.title,
        }),
      );
    } catch (e) {
      if (!mounted) return;
      _showForwardFailure(e);
    }
  }

  void _showForwardFailure(Object error) {
    showToast(
      context,
      isForwardProtectedError(error)
          ? AppStringKeys.chatForwardProtected
          : AppStrings.t(AppStringKeys.chatForwardFailed, {'value1': error}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    _syncKeyboardInset(keyboardInset);
    // Not a member, joinable, and nothing to preview → a custom join screen
    // (header + centered card) instead of the transcript + composer.
    if (!_vm.isMember && _vm.canJoin && _vm.messages.isEmpty) {
      return Scaffold(
        backgroundColor: c.groupedBackground,
        body: _joinScreenBody(),
      );
    }
    return Scaffold(
      backgroundColor: c.inputBarBackground,
      resizeToAvoidBottomInset: true,
      body: ColoredBox(
        color: c.chatBackground,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onBackSwipePointerDown,
          onPointerMove: _onBackSwipePointerMove,
          onPointerUp: _onBackSwipePointerEnd,
          onPointerCancel: _onBackSwipePointerEnd,
          child: Stack(
            children: [
              Positioned.fill(
                child: Column(
                  children: [
                    _isSelecting ? _selectionHeader() : _header(),
                    Expanded(child: _transcriptLayer()),
                    _isSelecting ? _selectionActionBar() : _composerArea(),
                  ],
                ),
              ),
              if (_actionTarget != null && !_isSelecting) _actionMenuOverlay(),
              if (_vm.isTelegramTosRestricted) _restrictedChatOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _restrictedChatOverlay() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mask = isDark
        ? Colors.black.withValues(alpha: 0.56)
        : Colors.black.withValues(alpha: 0.18);
    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: ColoredBox(color: mask, child: const SizedBox.expand()),
          ),
          Center(child: _restrictedChatCard()),
        ],
      ),
    );
  }

  Widget _restrictedChatCard() {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.dark.card : AppColors.light.card;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.34 : 0.16),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppStringKeys.chatRestrictedTitle.l10n(context),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              AppStringKeys.chatRestrictedTelegramTosMessage.l10n(context),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 14,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _restrictedActionButton(
                    label: AppStringKeys.chatInfoLeaveGroup.l10n(context),
                    color: Colors.redAccent,
                    onTap: _leaveRestrictedChat,
                  ),
                ),
                Container(width: 0.5, height: 24, color: c.divider),
                Expanded(
                  child: _restrictedActionButton(
                    label: AppStringKeys.chatRestrictedAcknowledge.l10n(
                      context,
                    ),
                    color: AppTheme.brand,
                    onTap: _acknowledgeRestrictedChat,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _restrictedActionButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 44,
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  void _acknowledgeRestrictedChat() {
    final onBack = widget.onBack;
    if (onBack != null) {
      onBack();
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  Future<void> _leaveRestrictedChat() async {
    try {
      await _vm.leaveChat();
      if (!mounted) return;
      final onBack = widget.onBack;
      if (onBack != null) {
        onBack();
      } else {
        final navigator = Navigator.of(context);
        if (navigator.canPop()) navigator.pop();
      }
    } catch (error) {
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.chatRestrictedLeaveFailed, {
          'value1': error,
        }),
      );
    }
  }

  Widget _transcriptLayer() {
    final showPinnedTodo =
        !_isSelecting && _vm.pinnedMessage != null && !_vm.pinnedDismissed;
    return Stack(
      children: [
        _transcript(),
        if (showPinnedTodo)
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: _pinnedBar(_vm.pinnedMessage!),
          ),
        if (_isSelecting) _selectToHereButton(),
        if (_shouldShowNewMessagesBanner)
          _openAtLatest
              ? Positioned(
                  top: showPinnedTodo ? 72 : 8,
                  right: 12,
                  child: _newMessagesBanner(pointsDown: false),
                )
              : Positioned(
                  right: 16,
                  bottom: 12,
                  child: _newMessagesBanner(pointsDown: true),
                ),
        if (_showJumpDown && !(!_openAtLatest && _shouldShowNewMessagesBanner))
          Positioned(right: 16, bottom: 12, child: _jumpToBottomButton()),
      ],
    );
  }

  bool get _shouldShowNewMessagesBanner {
    if ((_vm.unreadCount + _liveNewMessageCount) <= 0 || _bannerDismissed) {
      return false;
    }
    if (_isAtLoadedBottom()) return false;
    return _openAtLatest || !_isNearBottom(80);
  }

  /// Small button (bottom-right of the transcript) to return to the newest
  /// message; shown only when the user has scrolled up.
  Widget _jumpToBottomButton() {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _returnToLatest,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
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
        child: AppIcon(
          HeroAppIcons.angleDown,
          size: 22,
          color: c.textSecondary,
        ),
      ),
    );
  }

  /// "N条新消息" pill. In latest-on-open mode it points up to the unread
  /// boundary; in unread-boundary mode it points down to the newest message.
  Widget _newMessagesBanner({required bool pointsDown}) {
    final c = context.colors;
    final count = _vm.unreadCount + _liveNewMessageCount;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: pointsDown ? _returnToLatest : _jumpToFirstUnread,
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
            AppIcon(
              pointsDown ? HeroAppIcons.arrowDown : HeroAppIcons.arrowUp,
              size: 14,
              color: AppTheme.brand,
            ),
            const SizedBox(width: 5),
            Text(
              AppStrings.t(AppStringKeys.chatNewMessagesCount, {
                'value1': count,
              }),
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
    if (_vm.peerIsBot &&
        _vm.initialLoaded &&
        _vm.messages.isEmpty &&
        !_vm.botStartSent &&
        _vm.canSendMessages) {
      return _botStartBar();
    }
    if (_vm.canSendMessages) {
      return ChatInputBar(vm: _vm, onStartCall: _startCall);
    }
    if (!_vm.isMember && _vm.canJoin) return _joinBar();
    // Subscribed to a channel you can't post in → mute/unmute (like official).
    if (_vm.isChannel && _vm.isMember) return _channelMuteBar();
    return _disabledComposer(_vm.sendDisabledReason);
  }

  Widget _botStartBar() {
    final c = context.colors;
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
        onTap: _vm.sendBotStart,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: AppTheme.brandGradient,
            borderRadius: BorderRadius.circular(23),
          ),
          child: Text(
            AppStringKeys.startButton.l10n(context),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
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
            AppIcon(HeroAppIcons.solidBell, size: 18, color: AppTheme.brand),
            const SizedBox(width: 8),
            Text(
              (muted ? AppStringKeys.chatUnmute : AppStringKeys.callMute).l10n(
                context,
              ),
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
    final label = requested
        ? AppStringKeys.chatJoinRequestSent
        : (_vm.joinByRequest
              ? AppStringKeys.chatRequestToJoin
              : AppStringKeys.chatJoinGroup);
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
            telegramText(label),
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
        (reason.isEmpty ? AppStringKeys.chatCannotSendMessages : reason).l10n(
          context,
        ),
        style: TextStyle(fontSize: 14, color: c.textSecondary),
      ),
    );
  }

  /// custom join screen for a joinable chat with no previewable content.
  Widget _joinScreenBody() {
    final c = context.colors;
    final requested = _vm.joinRequested;
    final label = requested
        ? AppStringKeys.chatJoinRequestPending
        : (_vm.joinByRequest
              ? AppStringKeys.chatRequestToJoin
              : AppStringKeys.chatJoinGroup);
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
                      AppStrings.t(AppStringKeys.chatMemberCount, {
                        'value1': _vm.memberCount,
                      }),
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
                        telegramText(label),
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
    final actionActive = _vm.hasActiveChatAction;
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: BoxDecoration(
        color: widget.headerColor ?? c.navBar,
        border: widget.showHeaderDivider
            ? Border(bottom: BorderSide(color: c.divider, width: 0.5))
            : null,
      ),
      child: SizedBox(
        height: widget.headerHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              if (widget.showBackButton)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onBack ?? () => Navigator.of(context).pop(),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: AppIcon(
                      HeroAppIcons.chevronLeft,
                      size: 22,
                      color: c.textPrimary,
                    ),
                  ),
                )
              else
                const SizedBox(width: 4),
              Expanded(child: _headerTitleBlock(subtitle, actionActive)),
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
                child: AppIcon(
                  HeroAppIcons.bars,
                  size: 22,
                  color: c.textPrimary,
                ),
              ),
              if (_vm.isForum) ...[
                const SizedBox(width: 18),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _openTopicMode,
                  child: AppIcon(
                    HeroAppIcons.hashtag,
                    size: 22,
                    color: c.textPrimary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerTitleBlock(String subtitle, bool actionActive) {
    final c = context.colors;
    final title = Text(
      _vm.headerTitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: c.textPrimary,
      ),
    );
    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_vm.isForum)
          Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: 4),
              AppIcon(
                HeroAppIcons.chevronDown,
                size: 14,
                color: c.textSecondary,
              ),
            ],
          )
        else
          title,
        if (subtitle.isNotEmpty)
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: actionActive ? AppTheme.brand : c.textSecondary,
            ),
          ),
      ],
    );
    if (!_vm.isForum) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _showTopicSelector,
      child: content,
    );
  }

  ChatSummary _topicChatSummary() => ChatSummary(
    id: widget.chatId,
    title: _vm.peerTitle,
    lastMessage: '',
    lastMessageId: 0,
    date: 0,
    unreadCount: _vm.unreadCount,
    order: 0,
    isMuted: _vm.isMuted,
    kind: _vm.isChannel ? ChatKind.channel : ChatKind.group,
    photo: _vm.peerPhoto,
    isForum: true,
  );

  Future<void> _openTopicMode([int? threadId]) async {
    await TopicGroupDisplayPreference.set(TopicGroupDisplayMode.channel);
    if (!mounted) return;
    unawaited(
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => TopicChatView(
            chat: _topicChatSummary(),
            initialThreadId: threadId,
          ),
        ),
      ),
    );
  }

  Future<void> _showTopicSelector() async {
    if (!_vm.isForum) return;
    if (_vm.forumTopics.isEmpty && !_vm.forumTopicsLoading) {
      await _vm.loadForumTopics();
    }
    if (!mounted) return;
    final topics = _vm.forumTopics;
    if (topics.isEmpty) {
      showToast(
        context,
        _vm.forumTopicsLoading
            ? AppStringKeys.chatLoadingTopics
            : AppStringKeys.chatNoTopics,
      );
      return;
    }
    final c = context.colors;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: topics.length + 1,
          separatorBuilder: (_, _) =>
              Divider(height: 1, indent: 56, color: c.divider),
          itemBuilder: (_, index) {
            final all = index == 0;
            final topic = all ? null : topics[index - 1];
            return ListTile(
              leading: _forumTopicIcon(topic, all, c),
              title: Text(
                (all ? AppStringKeys.topicChatAllTopics : topic!.name).l10n(
                  context,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.textPrimary, fontSize: 16),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openTopicMode(topic?.id);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _forumTopicIcon(ForumTopicOption? topic, bool all, AppColors c) {
    if (all) {
      return AppIcon(HeroAppIcons.hashtag, color: AppTheme.brand, size: 24);
    }
    final iconId = topic?.iconCustomEmojiId ?? 0;
    if (iconId != 0) return CustomEmojiView(id: iconId, size: 24);
    final rawColor = topic?.iconColor ?? 0;
    final color = rawColor == 0
        ? c.textSecondary
        : Color(0xFF000000 | (rawColor & 0xFFFFFF));
    return AppIcon(HeroAppIcons.solidMessage, color: color, size: 24);
  }

  Widget _selectionHeader() {
    final c = context.colors;
    final count = _selectedMessageIds.length;
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _exitSelection,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  AppStringKeys.countryPickerCancel.l10n(context),
                  style: TextStyle(fontSize: 16, color: c.textPrimary),
                ),
              ),
            ),
            Expanded(
              child: Text(
                AppStrings.t(AppStringKeys.chatSelectedMessagesCount, {
                  'value1': count,
                }),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppIcon(
                HeroAppIcons.magnifyingGlass,
                size: 22,
                color: c.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectToHereButton() {
    final c = context.colors;
    final align = _selectionScrollingUp
        ? Alignment.topLeft
        : Alignment.bottomLeft;
    final margin = EdgeInsets.only(
      left: 12,
      top: _selectionScrollingUp ? 12 : 0,
      bottom: _selectionScrollingUp ? 0 : 12,
    );
    return Align(
      alignment: align,
      child: Padding(
        padding: margin,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _selectToVisibleEdge,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: c.navBar,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _selectionScrollingUp
                      ? HeroAppIcons.arrowUp.data
                      : HeroAppIcons.chevronDown.data,
                  size: 18,
                  color: AppTheme.brand,
                ),
                const SizedBox(width: 5),
                Text(
                  AppStringKeys.chatSelectUntilHere.l10n(context),
                  style: TextStyle(fontSize: 15, color: AppTheme.brand),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectionActionBar() {
    final c = context.colors;
    final enabled = _selectedMessageIds.isNotEmpty;
    final color = enabled ? c.textPrimary : c.textTertiary;
    Widget button(IconData icon, VoidCallback onTap) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: 58,
        height: 52,
        child: Icon(icon, size: 26, color: color),
      ),
    );
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SizedBox(
        height: 58,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            button(HeroAppIcons.share.data, _forwardSelected),
            button(HeroAppIcons.star.data, _saveSelected),
            button(HeroAppIcons.trash.data, _deleteSelected),
            button(
              HeroAppIcons.ellipsis.data,
              () =>
                  showToast(context, AppStringKeys.chatMoreActionsUnsupported),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pinnedBar(ChatMessage pinned) {
    final c = context.colors;
    final text = pinned.text.trim().isEmpty
        ? AppStringKeys.chatSearchMessageResultLabel
        : pinned.text.replaceAll('\n', ' ');
    final canPrevious = _vm.hasPreviousPinnedMessage;
    final canNext = _vm.hasNextPinnedMessage;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openPinnedFromBar(pinned),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.card.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: c.divider.withValues(alpha: 0.55),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFFFB300), width: 2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const AppIcon(
                HeroAppIcons.check,
                size: 15,
                color: Color(0xFFFFB300),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: text,
                      style: TextStyle(color: c.textSecondary),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: c.textPrimary),
              ),
            ),
            const SizedBox(width: 12),
            if (_vm.pinnedMessages.length > 1) ...[
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _pinnedNavButton(
                    icon: HeroAppIcons.chevronUp.data,
                    enabled: canPrevious,
                    onTap: _goToPreviousPinned,
                  ),
                  _pinnedNavButton(
                    icon: HeroAppIcons.chevronDown.data,
                    enabled: canNext,
                    onTap: _goToNextPinned,
                  ),
                ],
              ),
              const SizedBox(width: 4),
            ],
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _vm.dismissPinned,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: AppIcon(
                  HeroAppIcons.xmark,
                  size: 16,
                  color: c.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pinnedNavButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: 24,
        height: 18,
        child: Icon(
          icon,
          size: 14,
          color: c.textTertiary.withValues(alpha: enabled ? 1 : 0.28),
        ),
      ),
    );
  }

  Future<void> _openPinnedFromBar(ChatMessage pinned) async {
    if (_vm.pinnedMessage?.id == pinned.id && _isKeyMostlyVisible(_pinnedKey)) {
      return;
    }
    await _scrollToMessage(pinned.id, pinnedJump: true);
  }

  void _goToPreviousPinned() {
    final pinned = _vm.previousPinnedMessage();
    if (pinned != null) {
      unawaited(_scrollToMessage(pinned.id, pinnedJump: true));
    }
  }

  void _goToNextPinned() {
    final pinned = _vm.nextPinnedMessage();
    if (pinned != null) {
      unawaited(_scrollToMessage(pinned.id, pinnedJump: true));
    }
  }

  /// Scrolls the transcript to a message. If it is not loaded, ask TDLib for a
  /// page centered around that id instead of fetching the whole middle history.
  Future<void> _scrollToMessage(
    int messageId, {
    bool pinnedJump = false,
  }) async {
    if (mounted) {
      setState(() => _scrollTargetId = messageId);
    } else {
      _scrollTargetId = messageId;
    }
    if (_vm.messages.any((m) => m.id == messageId)) {
      await _ensureMessageVisible(messageId, pinnedJump: pinnedJump);
      return;
    }
    final loaded = await _vm.loadAroundMessage(messageId);
    if (!loaded || !mounted) return;
    await _ensureMessageVisible(messageId, pinnedJump: pinnedJump);
  }

  Future<void> _ensureMessageVisible(
    int messageId, {
    bool pinnedJump = false,
    bool instant = false,
  }) async {
    for (var tries = 0; tries < 6; tries++) {
      final activeKey = _scrollTargetId == messageId ? _targetKey : _pinnedKey;
      final ctx = activeKey.currentContext;
      if (ctx != null && ctx.mounted) {
        if (pinnedJump && _isKeyMostlyVisible(activeKey)) {
          if (mounted && _scrollTargetId == messageId) {
            setState(() => _scrollTargetId = null);
          }
          return;
        }
        await Scrollable.ensureVisible(
          ctx,
          alignment: pinnedJump ? 0.08 : 0.3,
          duration: instant
              ? Duration.zero
              : pinnedJump
              ? const Duration(milliseconds: 140)
              : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignmentPolicy: pinnedJump
              ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
              : ScrollPositionAlignmentPolicy.explicit,
        );
        if (mounted && _scrollTargetId == messageId) {
          setState(() => _scrollTargetId = null);
        }
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
    if (mounted && _scrollTargetId == messageId) {
      setState(() => _scrollTargetId = null);
    }
  }

  bool _isKeyMostlyVisible(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return false;
    final renderObject = ctx.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return false;
    final media = MediaQuery.of(context);
    final origin = renderObject.localToGlobal(Offset.zero);
    final rect = origin & renderObject.size;
    final viewportTop =
        media.padding.top +
        widget.headerHeight +
        (widget.showHeaderDivider ? 1 : 0);
    final viewportBottom =
        media.size.height - media.viewInsets.bottom - media.padding.bottom - 72;
    return rect.top >= viewportTop - 24 && rect.bottom <= viewportBottom + 24;
  }

  Widget _transcript() {
    final groupImages = context.watch<ThemeController>().groupImageMessages;
    final entries = _transcriptEntries(groupImages);
    final messages = _transcriptCacheMessages ?? _vm.messages;
    return Container(
      color: context.colors.chatBackground,
      child: ListView.builder(
        controller: _scroll,
        physics: const ClampingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        scrollCacheExtent: ScrollCacheExtent.pixels(
          defaultTargetPlatform == TargetPlatform.android ? 260 : 420,
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: entries.length,
        // Lets keyed children be reused when history pages shift indices
        // instead of being torn down and rebuilt.
        findChildIndexCallback: (key) => _transcriptIndexByKey[key],
        itemBuilder: (context, index) {
          final entry = entries[index];
          final message = entry.first;
          final messageIndex = entry.startIndex;
          final isTarget = entry.messages.any((m) => m.id == _scrollTargetId);
          final isPinned = entry.messages.any(
            (m) => m.id == _vm.pinnedMessage?.id,
          );
          final content = Column(
            key: isTarget
                ? _targetKey
                : isPinned
                ? _pinnedKey
                : null,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_needsUnreadDivider(messageIndex, messages: messages))
                KeyedSubtree(key: _unreadKey, child: _unreadDivider()),
              if (_needsSeparator(messageIndex, messages: messages))
                TimeSeparator(unix: message.date),
              if (message.isService)
                SystemBanner(text: message.text)
              else if (entry.isImageGroup)
                _selectionEntry(entry, _imageGroupBubble(entry.messages))
              else
                _selectionEntry(
                  entry,
                  MessageBubble(
                    message: message,
                    peerTitle: _vm.peerTitle,
                    peerPhoto: _vm.peerPhoto,
                    isGroup: _vm.isGroup,
                    meName: _vm.meName,
                    mePhoto: _vm.mePhoto,
                    showRepeat: _isRepeatTail(messageIndex),
                    onRepeat: () => _vm.repeatMessage(message),
                    onLongPress: _isSelecting
                        ? null
                        : _showActionMenuForMessage,
                    onReply: (m) => _vm.setReply(m),
                    onAvatarTap: _openSenderProfile,
                    onAvatarLongPress: (m) {
                      if (_vm.isGroup && (m.senderName?.isNotEmpty ?? false)) {
                        _vm.insertMention(m);
                      }
                    },
                    onOpenReply: _scrollToMessage,
                    onOpenImage: _openImage,
                    onOpenSticker: _openSticker,
                    onPlayVideo: _playVideo,
                    onButtonTap: _pressMessageButton,
                    onBotCommandTap: _vm.sendCommand,
                    isRead: _vm.isRead(message),
                    onToggleReaction: (r) => _vm.toggleReaction(message, r),
                    onShowReactionUsers: _showReactionUsers,
                    onRedial: _startCall,
                  ),
                ),
            ],
          );
          return KeyedSubtree(
            key: entry.key,
            child: RepaintBoundary(child: content),
          );
        },
      ),
    );
  }

  // The transcript is rebuilt on every view-model notification (send/read/
  // typing/file progress); grouping a few hundred messages each time is
  // avoidable garbage, so entries are memoized on their actual inputs.
  List<_TranscriptEntry>? _transcriptCache;
  Map<Key, int> _transcriptIndexByKey = const {};
  List<ChatMessage>? _transcriptCacheMessages;
  bool _transcriptCacheGrouped = false;
  int _transcriptCacheUnreadCount = -1;
  int _transcriptCacheLastReadInboxId = -1;

  List<_TranscriptEntry> _transcriptEntries(bool groupImages) {
    final messages = _vm.messages;
    final cached = _transcriptCache;
    if (cached != null &&
        identical(_transcriptCacheMessages, messages) &&
        _transcriptCacheGrouped == groupImages &&
        _transcriptCacheUnreadCount == _vm.unreadCount &&
        _transcriptCacheLastReadInboxId == _vm.lastReadInboxId) {
      return cached;
    }
    final entries = groupImages ? _groupedTranscript() : _plainTranscript();
    _transcriptCache = entries;
    _transcriptCacheMessages = messages;
    _transcriptCacheGrouped = groupImages;
    _transcriptCacheUnreadCount = _vm.unreadCount;
    _transcriptCacheLastReadInboxId = _vm.lastReadInboxId;
    _transcriptIndexByKey = {
      for (var i = 0; i < entries.length; i++) entries[i].key: i,
    };
    return entries;
  }

  Widget _selectionEntry(_TranscriptEntry entry, Widget child) {
    if (!_isSelecting) return child;
    final selectable = entry.messages.where((m) => !m.isService).toList();
    if (selectable.isEmpty) return child;
    final selected = selectable.every(
      (m) => _selectedMessageIds.contains(m.id),
    );
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggleSelection(selectable),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? AppTheme.brand : Colors.transparent,
              border: Border.all(
                color: selected ? AppTheme.brand : c.textTertiary,
                width: selected ? 0 : 1.4,
              ),
            ),
            child: selected
                ? const AppIcon(
                    HeroAppIcons.check,
                    size: 17,
                    color: Colors.white,
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(child: IgnorePointer(child: child)),
        ],
      ),
    );
  }

  void _showActionMenuForMessage(
    ChatMessage message,
    Rect? rect, [
    MessageActionSource source = MessageActionSource.normal,
  ]) {
    setState(() {
      _actionTarget = message;
      _actionRect = rect;
      _actionSource = source;
      _reactionExpanded = false;
      _reactionTab = 'standard';
    });
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
        if (_needsSeparator(j, messages: messages) ||
            _needsUnreadDivider(j, messages: messages)) {
          break;
        }
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
    return !message.isService && message.isAlbumVisualMedia;
  }

  bool _sameImageGroup(ChatMessage previous, ChatMessage next) {
    if (!_canGroupImage(next)) return false;
    if (previous.isOutgoing != next.isOutgoing) return false;
    if (previous.senderId != next.senderId) return false;
    if (previous.mediaAlbumId != 0 || next.mediaAlbumId != 0) {
      return previous.mediaAlbumId != 0 &&
          previous.mediaAlbumId == next.mediaAlbumId;
    }
    return false;
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
        .where(
          (text) =>
              text.isNotEmpty &&
              text != AppStringKeys.composerImagePreview &&
              text != AppStringKeys.chatVideoPlaceholder,
        )
        .toList();
    Widget avatar() => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openSenderProfile(first),
      onLongPress: outgoing
          ? null
          : () {
              if (_vm.isGroup && (first.senderName?.isNotEmpty ?? false)) {
                _vm.insertMention(first);
              }
            },
      child: PhotoAvatar(title: avatarTitle, photo: avatarPhoto, size: 38),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final chatWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final gallery = _imageGroupGallery(
          group,
          outgoing,
          captions,
          maxWidth: _messageMediaMaxWidth(chatWidth),
        );
        final Widget body = outgoing
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
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: body,
                      ),
                    ),
                    const SizedBox(width: 8),
                    avatar(),
                  ]
                : [avatar(), const SizedBox(width: 8), Flexible(child: body)],
          ),
        );
      },
    );
  }

  Widget _imageGroupGallery(
    List<ChatMessage> group,
    bool outgoing,
    List<String> captions, {
    required double maxWidth,
  }) {
    final c = context.colors;
    final visible = group.take(9).toList();
    const padding = 4.0;
    final layout = buildTelegramMediaAlbumLayout(
      items: [
        for (final message in visible)
          MediaAlbumItem(
            width: message.imageWidth,
            height: message.imageHeight,
          ),
      ],
      maxWidth: maxWidth - padding * 2,
      gap: 4,
      maxSingleHeight: 300,
      minRowHeight: 82,
      maxRowHeight: 230,
    );
    return Container(
      constraints: BoxConstraints(maxWidth: layout.width + padding * 2),
      padding: const EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: outgoing ? AppTheme.bubbleOutgoing : c.bubbleIncoming,
        borderRadius: BorderRadius.circular(8),
        border: outgoing ? null : Border.all(color: c.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: layout.width,
            height: layout.height,
            child: Stack(
              children: [
                for (var i = 0; i < visible.length; i++)
                  Positioned.fromRect(
                    rect: layout.tiles[i],
                    child: _imageGroupTile(
                      visible[i],
                      width: layout.tiles[i].width,
                      height: layout.tiles[i].height,
                      extraCount: i == visible.length - 1
                          ? math.max(0, group.length - visible.length)
                          : 0,
                    ),
                  ),
              ],
            ),
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
    final tileKey = GlobalKey();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (message.video != null) {
          _playVideo(message);
        } else {
          _openImage(message);
        }
      },
      onLongPress: _isSelecting
          ? null
          : () {
              final box =
                  tileKey.currentContext?.findRenderObject() as RenderBox?;
              final rect = box != null && box.hasSize
                  ? box.localToGlobal(Offset.zero) & box.size
                  : null;
              _showActionMenuForMessage(
                message,
                rect,
                message.video != null
                    ? MessageActionSource.video
                    : MessageActionSource.normal,
              );
            },
      child: SizedBox(
        key: tileKey,
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            TDImage(
              photo: message.image,
              cornerRadius: 5,
              cacheWidth: _cachePx(width),
              cacheHeight: _cachePx(height),
              showProgress: true,
            ),
            if (message.video != null)
              Center(
                child: Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const AppIcon(
                    HeroAppIcons.play,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
              ),
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

  int _cachePx(double logical) =>
      (logical * MediaQuery.devicePixelRatioOf(context)).ceil();

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
      _actionSource = MessageActionSource.normal;
      _reactionExpanded = false;
    });
    if (target != null) _vm.addReaction(target.id, emoji);
  }

  void _reactCustom(int customEmojiId) {
    final target = _actionTarget;
    setState(() {
      _actionTarget = null;
      _actionSource = MessageActionSource.normal;
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
    final showActionMenu = !_reactionExpanded;

    final reactionH = _reactionExpanded ? 268.0 : 48.0;
    final menuH = showActionMenu ? MessageActionMenu.preferredHeight : 0.0;
    const gap = 8.0;
    final menuGap = showActionMenu ? gap : 0.0;

    double reactionTop, menuTop;
    if (rect != null) {
      // Reaction picker stays near the pressed message; the action menu is
      // hidden while the picker is expanded.
      reactionTop = (rect.top - reactionH - gap).clamp(
        topSafe,
        bottomSafe - reactionH,
      );
      menuTop = (rect.bottom + gap).clamp(topSafe, bottomSafe - menuH);
    } else {
      reactionTop = (screenH - reactionH - menuH - menuGap) / 2;
      menuTop = reactionTop + reactionH + menuGap;
    }
    final align = outgoing ? Alignment.centerRight : Alignment.centerLeft;

    void dismiss() => setState(() {
      _actionTarget = null;
      _actionRect = null;
      _actionSource = MessageActionSource.normal;
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
          if (showActionMenu)
            Positioned(
              top: menuTop,
              left: 10,
              right: 10,
              child: Align(
                alignment: align,
                child: MessageActionMenu(
                  message: _actionTarget!,
                  isPinned: _vm.pinnedMessage?.id == _actionTarget!.id,
                  source: _actionSource,
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
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xFF3A3A3C),
                shape: BoxShape.circle,
              ),
              child: const AppIcon(
                HeroAppIcons.chevronDown,
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
    const reactionEmojiSize = 26.0;
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
          crossAxisCount: 7,
          padding: const EdgeInsets.all(10),
          children: [
            for (final item in pack.emoji)
              if (item.customEmojiId != 0)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _reactCustom(item.customEmojiId),
                  child: Center(
                    child: CustomEmojiView(
                      id: item.customEmojiId,
                      size: reactionEmojiSize,
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
            child: Center(
              child: Text(
                e,
                style: const TextStyle(fontSize: reactionEmojiSize),
              ),
            ),
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
            const AppIcon(
              HeroAppIcons.solidFaceSmile,
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
                  : const AppIcon(
                      HeroAppIcons.objectGroup,
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

class _MessageTextSelectionSheet extends StatefulWidget {
  const _MessageTextSelectionSheet({required this.text});

  final String text;

  @override
  State<_MessageTextSelectionSheet> createState() =>
      _MessageTextSelectionSheetState();
}

class _ReactionUsersSheet extends StatefulWidget {
  const _ReactionUsersSheet({
    required this.viewModel,
    required this.message,
    required this.initialReaction,
  });

  final ChatViewModel viewModel;
  final ChatMessage message;
  final MessageReaction initialReaction;

  @override
  State<_ReactionUsersSheet> createState() => _ReactionUsersSheetState();
}

class _ReactionUsersSheetState extends State<_ReactionUsersSheet> {
  late MessageReaction _selected;
  final Map<String, Future<List<MessageReactionUser>>> _loads = {};

  @override
  void initState() {
    super.initState();
    final initialKey = _reactionKey(widget.initialReaction);
    _selected = widget.message.reactions.firstWhere(
      (reaction) => _reactionKey(reaction) == initialKey,
      orElse: () => widget.message.reactions.first,
    );
  }

  Future<List<MessageReactionUser>> _load(MessageReaction reaction) {
    final key = _reactionKey(reaction);
    return _loads.putIfAbsent(
      key,
      () => widget.viewModel.reactionUsers(widget.message, reaction),
    );
  }

  String _reactionKey(MessageReaction reaction) => reaction.customEmojiId != 0
      ? 'custom:${reaction.customEmojiId}'
      : 'emoji:${reaction.emoji ?? ''}';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final height = math.min(MediaQuery.sizeOf(context).height * 0.62, 560.0);
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          child: ColoredBox(
            color: c.card,
            child: SizedBox(
              height: height,
              width: double.infinity,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: c.divider,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _reactionTabs(c),
                  Divider(height: 1, thickness: 0.5, color: c.divider),
                  Expanded(child: _reactionUsers(c)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _reactionTabs(AppColors c) {
    return SizedBox(
      height: 52,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final reaction in widget.message.reactions)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _reactionTab(c, reaction),
              ),
          ],
        ),
      ),
    );
  }

  Widget _reactionTab(AppColors c, MessageReaction reaction) {
    final selected = _reactionKey(reaction) == _reactionKey(_selected);
    final foreground = selected ? Colors.white : c.textSecondary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _selected = reaction),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppTheme.brand : c.searchFill,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _reactionGlyph(reaction, selected ? Colors.white : c.textSecondary),
            const SizedBox(width: 7),
            Text(
              '${reaction.count}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reactionUsers(AppColors c) {
    return FutureBuilder<List<MessageReactionUser>>(
      future: _load(_selected),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: Text(
              AppStrings.t(AppStringKeys.contactsLoading),
              style: TextStyle(fontSize: 14, color: c.textSecondary),
            ),
          );
        }
        final users = snapshot.data ?? const <MessageReactionUser>[];
        if (users.isEmpty) {
          return Center(
            child: Text(
              AppStrings.t(AppStringKeys.sharedMediaEmpty),
              style: TextStyle(fontSize: 14, color: c.textSecondary),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: users.length,
          itemBuilder: (context, index) => _reactionUserRow(c, users[index]),
        );
      },
    );
  }

  Widget _reactionUserRow(AppColors c, MessageReactionUser user) {
    final time = DateText.listLabel(user.date);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      child: Row(
        children: [
          PhotoAvatar(title: user.title, photo: user.photo, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              user.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 17, color: c.textPrimary),
            ),
          ),
          if (time.isNotEmpty) ...[
            const SizedBox(width: 10),
            Text(time, style: TextStyle(fontSize: 12, color: c.textTertiary)),
          ],
        ],
      ),
    );
  }

  Widget _reactionGlyph(MessageReaction reaction, Color color) {
    if (reaction.customEmojiId != 0) {
      return CustomEmojiView(
        id: reaction.customEmojiId,
        size: 18,
        color: color,
      );
    }
    return Text(reaction.emoji ?? '', style: const TextStyle(fontSize: 16));
  }
}

class _MessageTextSelectionSheetState
    extends State<_MessageTextSelectionSheet> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.text.length,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Material(
        color: c.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(36, 22, 36, 34),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.divider,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.62,
                ),
                child: Scrollbar(
                  child: SingleChildScrollView(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      readOnly: true,
                      autofocus: true,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isCollapsed: true,
                      ),
                      style: TextStyle(
                        fontSize: 32,
                        height: 1.35,
                        color: c.textPrimary,
                      ),
                      selectionControls: materialTextSelectionControls,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _switchPiPSessionMode(
  BuildContext context,
  VoidCallback close,
  VideoDisplayMode mode,
  VideoSplitSession session,
) {
  if (mode == VideoDisplayMode.pictureInPicture) return;
  final navigator = Navigator.of(context, rootNavigator: true);
  close();
  switch (mode) {
    case VideoDisplayMode.pictureInPicture:
      break;
    case VideoDisplayMode.split:
      VideoSplitController.instance.play(session);
    case VideoDisplayMode.fullscreen:
      navigator.push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (routeContext) => VideoPlayerView(
            video: session.video,
            thumb: session.thumb,
            width: session.width,
            height: session.height,
            sourceChatId: session.chatId,
            messageId: session.messageId,
            onSwitchMode: (nextMode) {
              switch (nextMode) {
                case VideoDisplayMode.fullscreen:
                  break;
                case VideoDisplayMode.pictureInPicture:
                  VideoPiPController.instance.play(session);
                  Navigator.of(routeContext).maybePop();
                case VideoDisplayMode.split:
                  VideoSplitController.instance.play(session);
                  Navigator.of(routeContext).maybePop();
              }
            },
          ),
        ),
      );
  }
}

double _sessionAspect(VideoSplitSession session) {
  return (session.width != null &&
          session.height != null &&
          session.width! > 0 &&
          session.height! > 0)
      ? session.width! / session.height!
      : 16 / 9;
}

class _PiPCornerHandle extends StatelessWidget {
  const _PiPCornerHandle({required this.alignment, required this.onDrag});

  final Alignment alignment;
  final GestureDragUpdateCallback onDrag;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: alignment.x < 0 ? -8 : null,
      right: alignment.x > 0 ? -8 : null,
      top: alignment.y < 0 ? -8 : null,
      bottom: alignment.y > 0 ? -8 : null,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: onDrag,
        child: const SizedBox(width: 44, height: 44),
      ),
    );
  }
}
