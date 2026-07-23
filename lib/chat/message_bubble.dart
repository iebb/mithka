//
//  message_bubble.dart
//
//  One conversation message, reference-styled. Plain rounded bubbles (no tail).
//  Renders text (with highlighted links), inline images (tap → full-screen
//  viewer), stickers (.tgs Lottie), voice notes, location cards, and document
//  cards. Shows a "+1" quick-repeat badge for a duplicate tail. Swipe a bubble
//  left to reply. Port of the Swift `MessageBubble`.
//

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../components/app_icons.dart';
import '../components/confirm_dialog.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/telegram_language_controller.dart';
import '../profile/profile_detail_view.dart';
import '../settings/sensitive_content_controller.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import '../theme/message_name_colors.dart';
import '../theme/theme_controller.dart';
import 'animated_sticker_view.dart';
import 'bot_button_presentation.dart';
import 'chat_appearance_preview.dart';
import 'custom_emoji.dart';
import 'file_detail_view.dart';
import 'link_handler.dart';
import 'location_detail_view.dart';
import 'looping_video_view.dart';
import 'message_action_menu.dart';
import 'message_special_content.dart';
import 'music_player_controller.dart';
import 'video_sticker_view.dart';
import 'voice_audio.dart';

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.groupedMedia = const <ChatMessage>[],
    required this.peerTitle,
    this.peerPhoto,
    required this.isGroup,
    this.meName = AppStringKeys.chatMeLabel,
    this.mePhoto,
    this.meId,
    this.showRepeat = false,
    this.forceShowTimestamp = false,
    this.onRepeat,
    this.onLongPress,
    this.onDoubleTap,
    this.onReply,
    this.onAvatarTap,
    this.onAvatarLongPress,
    this.onOpenReply,
    this.onOpenImage,
    this.onOpenSticker,
    this.onPlayVideo,
    this.onPlayMusic,
    this.onButtonTap,
    this.onBotCommandTap,
    this.onHashtagTap,
    this.onOpenComments,
    this.showCommentAttachment = false,
    this.onToggleReaction,
    this.onShowReactionUsers,
    this.onRedial,
    this.onOpenContact,
    this.onVotePoll,
    this.onStopPoll,
    this.onAddPollOption,
    this.onShowPollResults,
    this.onToggleChecklistTask,
    this.onAddChecklistTask,
    this.onOpenStory,
    this.onTranscribeVoice,
    this.onSummarizeMessage,
    this.isRead = false,
    this.outgoingBubbleColor,
    this.outgoingBubbleTextColor,
    this.incomingBubbleColor,
    this.incomingBubbleTextColor,
  });

  final ChatMessage message;
  final List<ChatMessage> groupedMedia;
  final String peerTitle;
  final TdFileRef? peerPhoto;
  final bool isGroup;
  final String meName;
  final TdFileRef? mePhoto;
  final int? meId;
  final bool showRepeat;
  final bool forceShowTimestamp;
  final VoidCallback? onRepeat;
  final void Function(
    ChatMessage message,
    Rect? bounds,
    MessageActionSource source,
  )?
  onLongPress;
  final ValueChanged<ChatMessage>? onDoubleTap;
  final ValueChanged<ChatMessage>? onReply;
  final ValueChanged<ChatMessage>? onAvatarTap;
  final ValueChanged<ChatMessage>? onAvatarLongPress;
  final ValueChanged<int>? onOpenReply;
  final ValueChanged<ChatMessage>? onOpenImage;
  final ValueChanged<ChatMessage>? onOpenSticker;
  final ValueChanged<ChatMessage>? onPlayVideo;
  final ValueChanged<ChatMessage>? onPlayMusic;
  final void Function(ChatMessage message, MessageButton button)? onButtonTap;
  final ValueChanged<String>? onBotCommandTap;
  final ValueChanged<String>? onHashtagTap;
  final ValueChanged<ChatMessage>? onOpenComments;
  final bool showCommentAttachment;
  final ValueChanged<MessageReaction>? onToggleReaction;
  final void Function(ChatMessage message, MessageReaction reaction)?
  onShowReactionUsers;
  final ValueChanged<bool>?
  onRedial; // tap a call log to redial (bool = isVideo)
  final ValueChanged<ChatMessage>? onOpenContact;
  final void Function(ChatMessage message, int optionIndex)? onVotePoll;
  final ValueChanged<ChatMessage>? onStopPoll;
  final ValueChanged<ChatMessage>? onAddPollOption;
  final ValueChanged<ChatMessage>? onShowPollResults;
  final void Function(ChatMessage message, MessageChecklistTask task)?
  onToggleChecklistTask;
  final ValueChanged<ChatMessage>? onAddChecklistTask;
  final ValueChanged<ChatMessage>? onOpenStory;
  final ValueChanged<ChatMessage>? onTranscribeVoice;
  final ValueChanged<ChatMessage>? onSummarizeMessage;
  final bool isRead; // outgoing message read by the peer (two delivery dots)
  final Color? outgoingBubbleColor;
  final Color? outgoingBubbleTextColor;
  final Color? incomingBubbleColor;
  final Color? incomingBubbleTextColor;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with SingleTickerProviderStateMixin {
  static const double _replyTrigger = 48;
  static const double _replyRestingLimit = 72;
  static const double _replyHardLimit = 104;
  static const double _bubbleMaxWidthFraction = 0.75;

  final VoicePlayer _voice = VoicePlayer();
  final GlobalKey _bubbleKey = GlobalKey();
  final List<TapGestureRecognizer> _linkRecognizers = [];
  late final AnimationController _swipeController;
  bool _stickerReady = false;
  bool _videoStickerReady = false;
  bool _musicPressed = false;
  bool _showTappedTimestamp = false;
  DateTime? _lastTapAt;
  bool _skipNextTap = false;
  double _swipeX = 0;
  double? _layoutWidth;
  final Set<String> _expandedQuotes = {};
  final Set<String> _revealedSpoilers = {};
  bool _showRestrictedContent = false;

  void _handleLongPress([
    MessageActionSource source = MessageActionSource.normal,
  ]) {
    _lastTapAt = null;
    if (_shouldOfferSensitiveContentUnblock) {
      unawaited(_showSensitiveContentUnblockDialog());
      return;
    }
    if (message.hasRestrictedRevealContent) {
      setState(() => _showRestrictedContent = !_showRestrictedContent);
      return;
    }
    final box = _bubbleKey.currentContext?.findRenderObject() as RenderBox?;
    Rect? bounds;
    if (box != null && box.hasSize) {
      bounds = box.localToGlobal(Offset.zero) & box.size;
    }
    widget.onLongPress?.call(message, bounds, source);
  }

  bool get _shouldOfferSensitiveContentUnblock {
    if (!message.isContentRestricted || _showRestrictedContent) return false;
    if (SensitiveContentController.shared.enabled) return false;
    return TDParse.isPornographicRestrictionText(
          message.restrictionReasonCode,
        ) ||
        TDParse.isPornographicRestrictionText(message.restrictionReason) ||
        TDParse.isPornographicRestrictionText(message.text);
  }

  Future<void> _showSensitiveContentUnblockDialog() async {
    final ok = await confirmDialog(
      context,
      title: AppStringKeys.sensitiveContentUnblockTitle,
      message: AppStringKeys.sensitiveContentUnblockMessage,
      confirmText: AppStringKeys.sensitiveContentUnblockConfirm,
    );
    if (!ok) return;
    try {
      await SensitiveContentController.shared.setEnabled(true);
      if (!mounted) return;
      showToast(
        context,
        AppStringKeys.sensitiveContentUnblockDone.l10n(context),
      );
      if (message.hasRestrictedRevealContent) {
        setState(() => _showRestrictedContent = true);
      }
    } catch (error) {
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.sensitiveContentUnblockFailed, {
          'value1': error.toString(),
        }),
      );
    }
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.onDoubleTap == null) return;
    final now = DateTime.now();
    final previous = _lastTapAt;
    _lastTapAt = now;
    if (previous == null ||
        now.difference(previous) > const Duration(milliseconds: 280)) {
      return;
    }
    _lastTapAt = null;
    _skipNextTap = true;
    widget.onDoubleTap?.call(message);
  }

  void _handleTap(bool alwaysShowTime) {
    if (_skipNextTap) {
      _skipNextTap = false;
      return;
    }
    if (!alwaysShowTime) {
      setState(() => _showTappedTimestamp = !_showTappedTimestamp);
    }
  }

  ChatMessage get message => widget.message;

  Color get _outgoingBubbleColor =>
      widget.outgoingBubbleColor ?? AppTheme.bubbleOutgoing;

  Color get _outgoingTextColor =>
      widget.outgoingBubbleTextColor ??
      (_outgoingBubbleColor.computeLuminance() > 0.64
          ? const Color(0xFF171717)
          : AppTheme.bubbleOutgoingText);

  Color get _incomingBubbleColor =>
      widget.incomingBubbleColor ?? context.colors.bubbleIncoming;

  Color get _incomingTextColor =>
      widget.incomingBubbleTextColor ?? context.colors.bubbleIncomingText;

  bool get _showsAttachedComments =>
      !message.isContentRestricted &&
      widget.showCommentAttachment &&
      message.commentCount > 0;

  BorderRadius _messageBorderRadius(
    double radius, {
    bool directlyAttached = true,
  }) {
    final corner = Radius.circular(radius);
    return BorderRadius.only(
      topLeft: corner,
      topRight: corner,
      bottomLeft: _showsAttachedComments && directlyAttached
          ? Radius.zero
          : corner,
      bottomRight: corner,
    );
  }

  double _bubbleMaxWidth() {
    final width = _layoutWidth ?? MediaQuery.sizeOf(context).width;
    return math.max(1.0, width * _bubbleMaxWidthFraction);
  }

  double _mediaMaxWidth() => _bubbleMaxWidth();

  double _chatFontSize(double base) =>
      context.watch<ThemeController>().chatTextSize(base);

  @override
  void initState() {
    super.initState();
    _swipeController = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        if (mounted) setState(() => _swipeX = _swipeController.value);
      });
  }

  @override
  void dispose() {
    _swipeController.dispose();
    _voice.dispose();
    for (final r in _linkRecognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (message.isService) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        _layoutWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return Stack(
          alignment: Alignment.centerRight,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Opacity(
                opacity: (math.min(1, math.max(0, -_swipeX) / 50)).toDouble(),
                child: AppIcon(
                  HeroAppIcons.reply,
                  size: 18,
                  color: AppTheme.brand,
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(_swipeX, 0),
              child: _row(
                widget.meId != null
                    ? message.senderId == widget.meId
                    : message.isOutgoing,
              ),
            ),
          ],
        );
      },
    );
  }

  double _rubberBandSwipe(double value) {
    if (value >= -_replyRestingLimit) {
      return value.clamp(-_replyHardLimit, 0).toDouble();
    }
    final extra = -value - _replyRestingLimit;
    final damped = _replyRestingLimit + extra * 0.34;
    return -damped.clamp(0, _replyHardLimit).toDouble();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _swipeController.stop();
    final next = _rubberBandSwipe(_swipeX + d.delta.dx);
    _swipeController.value = next;
  }

  void _onDragEnd(DragEndDetails d) {
    if (_swipeX < -_replyTrigger ||
        d.primaryVelocity != null && d.primaryVelocity! < -650) {
      widget.onReply?.call(message);
    }
    _swipeController.animateTo(
      0,
      duration: const Duration(milliseconds: 190),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _row(bool outgoing) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    final showMemberTags = theme.showMemberTags;
    final showSenderRole = switch (message.senderRole) {
      null => false,
      MemberRole.member =>
        theme.showPlainMemberRoleTags ||
            (showMemberTags &&
                (message.senderTitle?.trim().isNotEmpty ?? false)),
      _ => true,
    };
    final cloudTheme = theme.cloudThemeFor(Theme.of(context).brightness);
    final senderNameColor = messageNameColorForSender(
      theme: cloudTheme,
      accentColorId: message.senderAccentColorId,
      showNameColors: theme.chatNameColorAudience.shows(
        isPremium: message.senderIsPremium,
      ),
      nameColorsDisabledFallback: cloudTheme?.senderNameColor ?? c.linkBlue,
    );
    final showStatus =
        theme.chatStatusEmojiMode.visible && message.senderEmojiStatusId != 0;
    final senderTitle = message.senderTitle?.trim();
    final outgoingAvatarTitle = message.senderIsChat
        ? (message.senderName ?? widget.meName)
        : widget.meName.l10n(context);
    final outgoingAvatarPhoto = message.senderIsChat
        ? message.senderPhoto
        : widget.mePhoto;
    final alwaysShowTime =
        widget.forceShowTimestamp || theme.alwaysShowMessageTime;
    final body = GestureDetector(
      key: _bubbleKey,
      behavior: HitTestBehavior.opaque,
      onTapDown: _handleTapDown,
      onTap: () => _handleTap(alwaysShowTime),
      onLongPress: _handleLongPress,
      onHorizontalDragStart: (_) => _swipeController.stop(),
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Column(
        key: ValueKey('messageTapTarget-${message.id}'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: outgoing
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          _contentBody(outgoing),
          if (_showTappedTimestamp || alwaysShowTime) ...[
            const SizedBox(height: 3),
            Text(
              DateText.messageDetailLabel(message.date),
              key: const ValueKey('messageTappedTimestamp'),
              style: TextStyle(fontSize: 10, color: c.textTertiary),
            ),
          ],
        ],
      ),
    );
    final contentWidget = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: _bubbleMaxWidth()),
      child: message.reactions.isEmpty
          ? body
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: outgoing
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                body,
                const SizedBox(height: 4),
                _reactionChips(outgoing),
              ],
            ),
    );
    final content = message.buttonRows.isNotEmpty
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: outgoing
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              contentWidget,
              const SizedBox(height: 6),
              _buttonRows(outgoing),
            ],
          )
        : contentWidget;
    final ownPhotoRepeat = outgoing && message.isPhoto && widget.showRepeat;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: outgoing
            ? [
                Expanded(
                  child: ownPhotoRepeat
                      ? Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _repeatBadge(),
                              const SizedBox(width: 6),
                              Flexible(child: content),
                            ],
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (widget.showRepeat) _repeatBadge(),
                            if (widget.showRepeat) const SizedBox(width: 6),
                            Flexible(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: content,
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onAvatarTap?.call(message),
                  child: PhotoAvatar(
                    title: outgoingAvatarTitle,
                    photo: outgoingAvatarPhoto,
                    size: 38,
                  ),
                ),
              ]
            : [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onAvatarTap?.call(message),
                  onLongPress: () => widget.onAvatarLongPress?.call(message),
                  child: PhotoAvatar(
                    title: widget.isGroup
                        ? (message.senderName ?? widget.peerTitle)
                        : widget.peerTitle,
                    photo: widget.isGroup
                        ? message.senderPhoto
                        : widget.peerPhoto,
                    size: 38,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.isGroup && message.senderName != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 3),
                          child: Row(
                            children: [
                              Flexible(
                                child: SenderIdentityPills(
                                  enabled: theme.showSenderNameReadabilityPlate,
                                  bubbleColor: _incomingBubbleColor,
                                  name: message.senderName!,
                                  nameStyle: TextStyle(
                                    fontSize: 12,
                                    color: senderNameColor,
                                    fontWeight: message.senderIsPremium
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                  role: showSenderRole
                                      ? message.senderRole
                                      : null,
                                  roleTitle: showSenderRole && showMemberTags
                                      ? senderTitle
                                      : null,
                                ),
                              ),
                              if (showStatus) ...[
                                const SizedBox(width: 3),
                                StatusEmojiView(
                                  id: message.senderEmojiStatusId,
                                  size: 14,
                                  color: senderNameColor,
                                  animate: theme.chatStatusEmojiMode.animate,
                                ),
                              ],
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          Flexible(child: content),
                          if (widget.showRepeat) const SizedBox(width: 6),
                          if (widget.showRepeat) _repeatBadge(),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
      ),
    );
  }

  Widget _reactionChips(bool outgoing) {
    final c = context.colors;
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      alignment: outgoing ? WrapAlignment.end : WrapAlignment.start,
      children: [
        for (final r in message.reactions)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onToggleReaction?.call(r),
            onLongPress: () => widget.onShowReactionUsers?.call(message, r),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: r.chosen
                    ? AppTheme.brand.withValues(alpha: 0.18)
                    : c.searchFill,
                borderRadius: BorderRadius.circular(12),
                border: r.chosen ? Border.all(color: AppTheme.brand) : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  r.customEmojiId != 0
                      ? CustomEmojiView(
                          id: r.customEmojiId,
                          size: 16,
                          color: r.chosen ? AppTheme.brand : c.textSecondary,
                        )
                      : Text(
                          r.emoji ?? '',
                          style: const TextStyle(fontSize: 14),
                        ),
                  if (r.count > 1) ...[
                    const SizedBox(width: 4),
                    Text(
                      '${r.count}',
                      style: TextStyle(
                        fontSize: 12,
                        color: r.chosen ? AppTheme.brand : c.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _repeatBadge() => GestureDetector(
    key: const ValueKey('messageRepeatBadge'),
    onTap: widget.onRepeat,
    child: Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.brand, width: 1.2),
      ),
      child: Text(
        '+1',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppTheme.brand,
        ),
      ),
    ),
  );

  // MARK: - Content router

  Widget _contentBody(bool outgoing) {
    late final Widget body;
    if (message.isContentRestricted && !_showRestrictedContent) {
      body = _textBubble(message.text, outgoing);
      return _withCommentsOnly(_withFloatingMeta(body, outgoing), outgoing);
    }
    if (message.isCall) {
      body = _callBubble(outgoing);
      return _withCommentsOnly(_withFloatingMeta(body, outgoing), outgoing);
    }
    final specialBackground = outgoing
        ? _outgoingBubbleColor
        : _incomingBubbleColor;
    final specialForeground = outgoing
        ? _outgoingTextColor
        : _incomingTextColor;
    final specialSecondary = specialForeground.withValues(alpha: 0.68);
    if (message.contact != null) {
      body = MessageContactCardContent(
        contact: message.contact!,
        background: specialBackground,
        foreground: specialForeground,
        secondary: specialSecondary,
        borderRadius: _messageBorderRadius(9),
        onOpen: () => widget.onOpenContact?.call(message),
      );
      return _withCommentsOnly(_withFloatingMeta(body, outgoing), outgoing);
    }
    if (message.poll != null) {
      body = MessagePollContent(
        poll: message.poll!,
        background: specialBackground,
        foreground: specialForeground,
        secondary: specialSecondary,
        borderRadius: _messageBorderRadius(9),
        onVote: message.poll!.isClosed
            ? null
            : (index) => widget.onVotePoll?.call(message, index),
        onStop: message.isOutgoing && !message.poll!.isClosed
            ? () => widget.onStopPoll?.call(message)
            : null,
        onAddOption: message.poll!.canAddOption
            ? () => widget.onAddPollOption?.call(message)
            : null,
        onShowResults: message.poll!.canGetVoters
            ? () => widget.onShowPollResults?.call(message)
            : null,
      );
      return _withCommentsOnly(_withFloatingMeta(body, outgoing), outgoing);
    }
    if (message.checklist != null) {
      body = MessageChecklistContent(
        checklist: message.checklist!,
        background: specialBackground,
        foreground: specialForeground,
        secondary: specialSecondary,
        borderRadius: _messageBorderRadius(9),
        onToggleTask: message.checklist!.canMarkTasksAsDone
            ? (task) => widget.onToggleChecklistTask?.call(message, task)
            : null,
        onAddTask: message.checklist!.canAddTasks
            ? () => widget.onAddChecklistTask?.call(message)
            : null,
      );
      return _withCommentsOnly(_withFloatingMeta(body, outgoing), outgoing);
    }
    if (message.story != null) {
      body = MessageStoryContent(
        story: message.story!,
        background: specialBackground,
        foreground: specialForeground,
        secondary: specialSecondary,
        borderRadius: _messageBorderRadius(9),
        onOpen: () => widget.onOpenStory?.call(message),
      );
      return _withCommentsOnly(_withFloatingMeta(body, outgoing), outgoing);
    }
    if (message.summaryCard != null) {
      body = MessageSummaryCardContent(
        card: message.summaryCard!,
        background: specialBackground,
        foreground: specialForeground,
        secondary: specialSecondary,
        borderRadius: _messageBorderRadius(9),
      );
      return _withCommentsOnly(_withFloatingMeta(body, outgoing), outgoing);
    }
    if (message.animatedSticker != null) {
      final s = _stickerSize();
      body = SizedBox(
        width: s.width,
        height: s.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (message.image != null && !_stickerReady)
              TDImage(
                photo: message.image,
                cacheWidth: _cachePx(s.width),
                cacheHeight: _cachePx(s.height),
              ),
            AnimatedStickerView(
              file: message.animatedSticker!,
              onReady: () => setState(() => _stickerReady = true),
            ),
          ],
        ),
      );
      return _withCommentsOnly(
        _withFloatingMeta(_stickerTap(body), outgoing),
        outgoing,
      );
    }
    if (message.videoSticker != null) {
      final s = _stickerSize();
      body = SizedBox(
        width: s.width,
        height: s.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Static thumbnail until the webm decodes its first frame.
            if (message.image != null && !_videoStickerReady)
              TDImage(
                photo: message.image,
                cacheWidth: _cachePx(s.width),
                cacheHeight: _cachePx(s.height),
              ),
            VideoStickerView(
              file: message.videoSticker!,
              fallback: message.image,
              onReady: () => setState(() => _videoStickerReady = true),
            ),
          ],
        ),
      );
      return _withCommentsOnly(
        _withFloatingMeta(_stickerTap(body), outgoing),
        outgoing,
      );
    }
    if (message.isDice) {
      body = _diceBubble(outgoing);
    } else if (message.video != null) {
      body = switch (message.contentType) {
        'messageVideoNote' => _videoNoteContent(),
        'messageAnimation' => _animationContent(outgoing),
        _ => _videoContent(outgoing),
      };
    } else if (message.stickerFileId != null && message.image != null) {
      body = _staticStickerContent(message.image!);
    } else if (message.image != null) {
      body = _imageContent(message.image!, outgoing);
    } else if (message.music != null) {
      body = _musicCard(message.music!, outgoing);
    } else if (message.location != null) {
      body = _locationBubble(message.location!);
    } else if (message.voice != null) {
      body = _attachmentWithCaption(
        _voiceBubble(message.voice!, outgoing),
        outgoing,
      );
    } else if (_groupedDocumentMessages case final documents?) {
      body = _fileAlbumCard(documents, outgoing);
    } else if (message.document != null) {
      body = _fileCard(message.document!, outgoing);
    } else {
      body = _textBubble(_activeMessageText, outgoing);
    }
    return _withCommentsOnly(_withFloatingMeta(body, outgoing), outgoing);
  }

  List<ChatMessage>? get _groupedDocumentMessages {
    final grouped = widget.groupedMedia;
    if (grouped.length < 2 ||
        grouped.any(
          (member) =>
              member.contentType != 'messageDocument' ||
              member.document == null,
        )) {
      return null;
    }
    return grouped;
  }

  Widget _videoNoteContent() {
    const size = 220.0;
    final duration = message.videoDuration ?? 0;
    final transcription = message.videoNoteTranscription;
    final showsTranscription =
        transcription.isNotEmpty ||
        message.videoNoteTranscriptionPending ||
        message.videoNoteTranscriptionError != null ||
        widget.onTranscribeVoice != null;
    final transcriptionColor = message.isOutgoing
        ? _outgoingTextColor.withValues(alpha: 0.88)
        : context.colors.textSecondary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          key: const ValueKey('messageVideoNote'),
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onPlayVideo?.call(message),
          child: SizedBox(
            width: size,
            height: size,
            child: ClipOval(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (message.image != null)
                    TDImage(
                      photo: message.image,
                      cornerRadius: 0,
                      cacheWidth: _cachePx(size),
                      cacheHeight: _cachePx(size),
                    )
                  else
                    ColoredBox(color: AppTheme.brand.withValues(alpha: 0.16)),
                  Center(
                    child: Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.42),
                        shape: BoxShape.circle,
                      ),
                      child: const AppIcon(
                        HeroAppIcons.play,
                        size: 23,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (duration > 0)
                    Positioned(
                      left: 76,
                      right: 76,
                      bottom: 12,
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.42),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          _formatCallDuration(duration),
                          style: const TextStyle(
                            fontSize: 11,
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
        if (showsTranscription) ...[
          const SizedBox(height: 7),
          GestureDetector(
            key: const ValueKey('videoNoteTranscription'),
            behavior: HitTestBehavior.opaque,
            onTap: message.videoNoteTranscriptionPending
                ? null
                : () => widget.onTranscribeVoice?.call(message),
            child: SizedBox(
              width: size,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppIcon(
                    HeroAppIcons.microphone,
                    size: 15,
                    color: transcriptionColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      transcription.isNotEmpty
                          ? transcription
                          : message.videoNoteTranscriptionPending
                          ? 'Transcribing…'
                          : message.videoNoteTranscriptionError ??
                                'Transcribe video message',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.25,
                        color: transcriptionColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  String get _activeMessageText {
    if (message.isContentRestricted && _showRestrictedContent) {
      return message.restrictedContentText ?? '';
    }
    return message.text;
  }

  List<MessageTextEntity> get _activeTextEntities {
    if (message.isContentRestricted && _showRestrictedContent) {
      return message.restrictedContentTextEntities;
    }
    if (message.isContentRestricted) return const [];
    return message.textEntities;
  }

  List<RichMessageBlock> get _activeRichBlocks {
    if (message.isContentRestricted && !_showRestrictedContent) return const [];
    return message.richBlocks;
  }

  MessageLinkPreview? get _activeLinkPreview {
    if (message.isContentRestricted && !_showRestrictedContent) return null;
    return message.linkPreview;
  }

  Widget _withFloatingMeta(Widget child, bool outgoing) {
    final show = message.isEdited || outgoing;
    if (!show) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(right: 5, bottom: 3, child: _floatingMeta(outgoing)),
      ],
    );
  }

  Widget _floatingMeta(bool outgoing) {
    final c = context.colors;
    final faint = outgoing
        ? _outgoingTextColor.withValues(alpha: 0.72)
        : c.textTertiary;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: outgoing
              ? Colors.black.withValues(alpha: 0.10)
              : c.card.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.isEdited)
                AppIcon(HeroAppIcons.pen, size: 13, color: faint),
              if (message.isEdited && outgoing) const SizedBox(width: 3),
              if (outgoing)
                _deliveryDots(diameter: 4, color: _outgoingTextColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stickerTap(Widget child) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => widget.onOpenSticker?.call(message),
    child: child,
  );

  Widget _withCommentsOnly(Widget body, bool outgoing) {
    if (message.isContentRestricted) return body;
    final showComments = _showsAttachedComments;
    final showSuggestedPost = message.suggestedPostInfo != null;
    if (!showComments && !showSuggestedPost) {
      return body;
    }
    final foreground = outgoing ? _outgoingTextColor : _incomingTextColor;
    final extras = <Widget>[
      if (showSuggestedPost)
        MessageSuggestedPostStatusContent(
          info: message.suggestedPostInfo!,
          background: outgoing ? _outgoingBubbleColor : _incomingBubbleColor,
          foreground: foreground,
          secondary: foreground.withValues(alpha: 0.68),
          borderRadius: _messageBorderRadius(9),
        ),
      if (showComments) _commentThreadRow(outgoing),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: outgoing
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        body,
        for (var index = 0; index < extras.length; index++) ...[
          if (index == 0 && showSuggestedPost) const SizedBox(height: 6),
          extras[index],
        ],
      ],
    );
  }

  Widget _commentThreadRow(bool outgoing) {
    final c = context.colors;
    final count = message.commentCount;
    final label = AppStrings.t(AppStringKeys.momentsCommentCount, {
      'value1': count,
    });
    final bg = outgoing
        ? _outgoingTextColor.withValues(alpha: 0.16)
        : c.card.withValues(alpha: 0.92);
    final fg = outgoing ? _outgoingTextColor : c.textPrimary;
    final sub = outgoing
        ? _outgoingTextColor.withValues(alpha: 0.72)
        : c.linkBlue;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onOpenComments?.call(message),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _bubbleMaxWidth()),
        child: Container(
          key: ValueKey('messageCommentsAttachment-${message.id}'),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
            border: Border.all(
              color: outgoing
                  ? _outgoingTextColor.withValues(alpha: 0.12)
                  : c.divider.withValues(alpha: 0.7),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(HeroAppIcons.comments, size: 18, color: sub),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: fg,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              AppIcon(HeroAppIcons.chevronRight, size: 17, color: sub),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buttonRows(bool outgoing) {
    final maxWidth = _bubbleMaxWidth();
    return SizedBox(
      width: maxWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < message.buttonRows.length; i++) ...[
            if (i > 0) const SizedBox(height: 5),
            Row(
              children: [
                for (var j = 0; j < message.buttonRows[i].length; j++) ...[
                  if (j > 0) const SizedBox(width: 5),
                  Expanded(
                    child: _buttonCell(message.buttonRows[i][j], outgoing),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buttonCell(MessageButton button, bool outgoing) {
    final c = context.colors;
    final colors = botButtonPalette(
      button.style,
      primary: AppTheme.brand,
      standard: (
        background: outgoing
            ? Colors.white.withValues(alpha: 0.92)
            : _incomingBubbleColor,
        foreground: outgoing ? AppTheme.brand : c.linkBlue,
        border: outgoing ? Colors.white.withValues(alpha: 0.65) : c.divider,
      ),
    );
    return Material(
      key: ValueKey('message-button-${button.text}'),
      color: colors.background,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => widget.onButtonTap?.call(message, button),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.border, width: 0.5),
          ),
          child: BotButtonLabel(
            button: button,
            color: colors.foreground,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // MARK: - Text bubble

  Widget _diceBubble(bool outgoing) {
    final c = context.colors;
    final value = message.diceValue;
    return Container(
      constraints: BoxConstraints(maxWidth: _bubbleMaxWidth()),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 11),
      decoration: BoxDecoration(
        color: outgoing ? _outgoingBubbleColor : _incomingBubbleColor,
        borderRadius: _messageBorderRadius(10),
        border: outgoing ? null : Border.all(color: c.divider, width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.88, end: 1),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Text(
              message.diceEmoji ?? message.text,
              style: const TextStyle(fontSize: 64, height: 1),
            ),
          ),
          if (value != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: outgoing
                    ? _outgoingTextColor.withValues(alpha: 0.16)
                    : c.searchFill,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$value',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: outgoing ? _outgoingTextColor : c.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _textBubble(String text, bool outgoing) {
    final c = context.colors;
    final baseColor = outgoing ? _outgoingTextColor : _incomingTextColor;
    final linkColor = outgoing ? _outgoingTextColor : c.linkBlue;
    for (final r in _linkRecognizers) {
      r.dispose();
    }
    _linkRecognizers.clear();
    final emojiOnly = _isEmojiOnlyText(text);
    final textFontSize = emojiOnly ? 34.0 : 16.0;
    return Container(
      key: ValueKey('messageTextBubble-${message.id}'),
      constraints: BoxConstraints(maxWidth: _bubbleMaxWidth()),
      padding: emojiOnly
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 7)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: outgoing ? _outgoingBubbleColor : _incomingBubbleColor,
        borderRadius: _messageBorderRadius(6),
        border: outgoing ? null : Border.all(color: c.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if ((message.forwardOrigin ?? '').isNotEmpty) ...[
            _forwardHeader(outgoing),
            const SizedBox(height: 3),
          ],
          if (message.replyToPreview != null) ...[
            _replyQuote(outgoing),
            const SizedBox(height: 5),
          ],
          if (_activeLinkPreview?.showAboveText ?? false) ...[
            _linkPreviewCard(_activeLinkPreview!, outgoing),
            if (text.isNotEmpty) const SizedBox(height: 6),
          ],
          ..._richTextWidgets(
            text,
            baseColor,
            linkColor,
            outgoing,
            false,
            _activeTextEntities,
            textFontSize,
          ),
          if (_activeRichBlocks.isNotEmpty) ...[
            if (text.isNotEmpty) const SizedBox(height: 8),
            ..._richBlockWidgets(_activeRichBlocks, outgoing),
          ],
          if (_activeLinkPreview != null &&
              !_activeLinkPreview!.showAboveText) ...[
            if (text.isNotEmpty || _activeRichBlocks.isNotEmpty)
              const SizedBox(height: 7),
            _linkPreviewCard(_activeLinkPreview!, outgoing),
          ],
          if (_showsTranslation) ...[
            const SizedBox(height: 7),
            _translationBlock(outgoing),
          ],
          if (_showsAiSummary) ...[
            const SizedBox(height: 7),
            _aiSummaryBlock(outgoing),
          ] else if (message.summaryLanguageCode.isNotEmpty &&
              widget.onSummarizeMessage != null) ...[
            const SizedBox(height: 7),
            GestureDetector(
              key: const ValueKey('messageSummarizeAction'),
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onSummarizeMessage?.call(message),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.brand.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      HeroAppIcons.wandMagicSparkles,
                      size: 15,
                      color: AppTheme.brand,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      AppStrings.t(AppStringKeys.messageBubbleSummarize),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.brand,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _isEmojiOnlyText(String text) {
    final stripped = text.replaceAll(RegExp(r'\s+'), '');
    if (stripped.isEmpty) return false;
    var count = 0;
    for (final cluster in stripped.characters) {
      if (!_isEmojiCluster(cluster)) return false;
      count++;
    }
    return count > 1;
  }

  bool _isEmojiCluster(String cluster) {
    final runes = cluster.runes.toList();
    final keycap = runes.contains(0x20E3);
    for (final rune in runes) {
      if (_isEmojiModifier(rune)) continue;
      if (keycap && _isKeycapBase(rune)) continue;
      if (!_isEmojiCodepoint(rune)) return false;
    }
    return true;
  }

  bool _isEmojiModifier(int rune) =>
      rune == 0x200D ||
      rune == 0xFE0E ||
      rune == 0xFE0F ||
      rune == 0x20E3 ||
      (rune >= 0x1F3FB && rune <= 0x1F3FF);

  bool _isKeycapBase(int rune) =>
      (rune >= 0x30 && rune <= 0x39) || rune == 0x23 || rune == 0x2A;

  bool _isEmojiCodepoint(int rune) =>
      rune == 0x00A9 ||
      rune == 0x00AE ||
      rune == 0x203C ||
      rune == 0x2049 ||
      rune == 0x2122 ||
      rune == 0x2139 ||
      rune == 0x3030 ||
      rune == 0x303D ||
      rune == 0x3297 ||
      rune == 0x3299 ||
      (rune >= 0x2194 && rune <= 0x21AA) ||
      (rune >= 0x2300 && rune <= 0x23FF) ||
      (rune >= 0x2600 && rune <= 0x27BF) ||
      (rune >= 0x2934 && rune <= 0x2935) ||
      (rune >= 0x1F000 && rune <= 0x1FAFF);

  List<Widget> _richBlockWidgets(List<RichMessageBlock> blocks, bool outgoing) {
    final widgets = <Widget>[];
    for (var index = 0; index < blocks.length; index++) {
      final block = blocks[index];
      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 8));
      final widget = _richBlockWidget(block, outgoing);
      if (widget != null) {
        widgets.add(
          KeyedSubtree(
            key: ValueKey('rich-message-block-$index-${block.kind.name}'),
            child: widget,
          ),
        );
      }
    }
    return widgets;
  }

  Widget? _richBlockWidget(RichMessageBlock block, bool outgoing) {
    return switch (block.kind) {
      RichMessageBlockKind.paragraph ||
      RichMessageBlockKind.heading ||
      RichMessageBlockKind.preformatted ||
      RichMessageBlockKind.footer ||
      RichMessageBlockKind.thinking => _richTextBlock(block, outgoing),
      RichMessageBlockKind.divider => Divider(
        height: 12,
        color: context.colors.divider,
      ),
      RichMessageBlockKind.math => _richMathBlock(
        block.mathExpression ?? '',
        outgoing,
      ),
      RichMessageBlockKind.anchor => const SizedBox.shrink(),
      RichMessageBlockKind.list => _richListBlock(block, outgoing),
      RichMessageBlockKind.blockQuote ||
      RichMessageBlockKind.pullQuote => _richQuoteContainer(block, outgoing),
      RichMessageBlockKind.animation ||
      RichMessageBlockKind.audio ||
      RichMessageBlockKind.photo ||
      RichMessageBlockKind.video ||
      RichMessageBlockKind.voiceNote => _richMediaBlock(block, outgoing),
      RichMessageBlockKind.collage => _richCollageBlock(block, outgoing),
      RichMessageBlockKind.slideshow => _richSlideshowBlock(block, outgoing),
      RichMessageBlockKind.table => _richTableBlock(block, outgoing),
      RichMessageBlockKind.details => _richDetailsBlock(block, outgoing),
      RichMessageBlockKind.map => _richMapBlock(block, outgoing),
    };
  }

  Widget _richTextBlock(RichMessageBlock block, bool outgoing) {
    final c = context.colors;
    final base = block.kind == RichMessageBlockKind.footer
        ? c.textSecondary
        : (outgoing ? _outgoingTextColor : _incomingTextColor);
    final link = outgoing ? _outgoingTextColor : c.linkBlue;
    final entities = <MessageTextEntity>[...block.textEntities];
    final fontSize = switch (block.kind) {
      RichMessageBlockKind.heading => switch (block.size.clamp(1, 6)) {
        1 => 24.0,
        2 => 22.0,
        3 => 20.0,
        4 => 18.0,
        5 => 16.0,
        _ => 15.0,
      },
      RichMessageBlockKind.footer => 13.0,
      _ => 15.0,
    };
    if (block.text.isNotEmpty && block.kind == RichMessageBlockKind.heading) {
      entities.add(
        MessageTextEntity(
          offset: 0,
          length: block.text.length,
          type: 'textEntityTypeBold',
        ),
      );
    }
    if (block.text.isNotEmpty && block.kind == RichMessageBlockKind.thinking) {
      entities.add(
        MessageTextEntity(
          offset: 0,
          length: block.text.length,
          type: 'textEntityTypeItalic',
        ),
      );
    }
    if (block.text.isNotEmpty &&
        block.kind == RichMessageBlockKind.preformatted) {
      entities.add(
        MessageTextEntity(
          offset: 0,
          length: block.text.length,
          type: 'textEntityTypePreCode',
          language: block.language,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: _richTextWidgets(
        block.text,
        base,
        link,
        outgoing,
        false,
        entities,
        fontSize,
      ),
    );
  }

  Widget _richListBlock(RichMessageBlock block, bool outgoing) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < block.listItems.length; index++)
          Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 26,
                  child: block.listItems[index].hasCheckbox
                      ? AppIcon(
                          block.listItems[index].isChecked
                              ? HeroAppIcons.check
                              : HeroAppIcons.square,
                          size: 16,
                          color: outgoing
                              ? _outgoingTextColor
                              : c.textSecondary,
                        )
                      : Text(
                          _richListLabel(block.listItems[index], index),
                          style: TextStyle(
                            fontSize: 15,
                            color: outgoing
                                ? _outgoingTextColor
                                : c.textSecondary,
                          ),
                        ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: _richBlockWidgets(
                      block.listItems[index].blocks,
                      outgoing,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _richListLabel(RichMessageListItem item, int index) {
    if (item.label.isNotEmpty) return item.label;
    if (item.value > 0 || item.numberingType.isNotEmpty) {
      return '${item.value > 0 ? item.value : index + 1}.';
    }
    return '•';
  }

  Widget _richQuoteContainer(RichMessageBlock block, bool outgoing) {
    final c = context.colors;
    final base = outgoing ? _outgoingTextColor : _incomingTextColor;
    final link = outgoing ? _outgoingTextColor : c.linkBlue;
    final body = block.kind == RichMessageBlockKind.pullQuote
        ? _richTextWidgets(block.text, base, link, outgoing, false, [
            ...block.textEntities,
            if (block.text.isNotEmpty)
              MessageTextEntity(
                offset: 0,
                length: block.text.length,
                type: 'textEntityTypeItalic',
              ),
          ])
        : _richBlockWidgets(block.children, outgoing);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.07),
        border: Border(left: BorderSide(color: base, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: block.kind == RichMessageBlockKind.pullQuote
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ...body,
          if (block.caption.isNotEmpty) ...[
            const SizedBox(height: 5),
            ..._richTextWidgets(
              block.caption,
              base.withValues(alpha: 0.78),
              link,
              outgoing,
              false,
              block.captionEntities,
              13,
            ),
          ],
        ],
      ),
    );
  }

  Widget _richDetailsBlock(RichMessageBlock block, bool outgoing) {
    final c = context.colors;
    final base = outgoing ? _outgoingTextColor : _incomingTextColor;
    final link = outgoing ? _outgoingTextColor : c.linkBlue;
    return _RichDetailsBlock(
      initiallyOpen: block.isOpen,
      color: base,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: _richTextWidgets(
          block.text,
          base,
          link,
          outgoing,
          false,
          block.textEntities,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: _richBlockWidgets(block.children, outgoing),
      ),
    );
  }

  Widget _richMediaBlock(RichMessageBlock block, bool outgoing) {
    return switch (block.kind) {
      RichMessageBlockKind.photo => _richPhotoBlock(block, outgoing),
      RichMessageBlockKind.video ||
      RichMessageBlockKind.animation => _richVideoBlock(block, outgoing),
      RichMessageBlockKind.audio => _richAudioBlock(block, outgoing),
      RichMessageBlockKind.voiceNote => _richVoiceBlock(block, outgoing),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _richPhotoBlock(RichMessageBlock block, bool outgoing) {
    final image = block.image;
    if (image == null) return _richMissingMedia(HeroAppIcons.image, outgoing);
    final maxWidth = _mediaMaxWidth();
    final size = _fitSize(
      width: block.imageWidth,
      height: block.imageHeight,
      maxWidth: maxWidth,
      maxHeight: maxWidth,
      fallback: Size(maxWidth, maxWidth * 0.72),
    );
    Widget media = GestureDetector(
      onTap: () => widget.onOpenImage?.call(_richMediaMessage(block)),
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: TDImage(
          photo: image,
          fit: BoxFit.contain,
          cacheWidth: _cachePx(size.width),
          cacheHeight: _cachePx(size.height),
          showProgress: true,
        ),
      ),
    );
    if (block.hasSpoiler) {
      media = _RichSpoiler(color: context.colors.card, child: media);
    }
    return _richMediaWithCaption(media, block, outgoing);
  }

  Widget _richVideoBlock(RichMessageBlock block, bool outgoing) {
    final maxWidth = _mediaMaxWidth();
    final size = _fitSize(
      width: block.imageWidth,
      height: block.imageHeight,
      maxWidth: maxWidth,
      maxHeight: maxWidth,
      fallback: Size(maxWidth, maxWidth * 0.62),
    );
    Widget media = GestureDetector(
      onTap: block.video == null
          ? null
          : () => widget.onPlayVideo?.call(_richMediaMessage(block)),
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: block.image == null
                  ? ColoredBox(color: context.colors.searchFill)
                  : TDImage(
                      photo: block.image,
                      cacheWidth: _cachePx(size.width),
                      cacheHeight: _cachePx(size.height),
                      showProgress: true,
                    ),
            ),
            const Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0x99000000),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: EdgeInsets.all(11),
                  child: AppIcon(
                    HeroAppIcons.play,
                    size: 22,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (block.hasSpoiler) {
      media = _RichSpoiler(color: context.colors.card, child: media);
    }
    return _richMediaWithCaption(media, block, outgoing);
  }

  Widget _richAudioBlock(RichMessageBlock block, bool outgoing) {
    final music = block.music;
    if (music == null) return _richMissingMedia(HeroAppIcons.music, outgoing);
    final synthetic = _richMediaMessage(block);
    final player = MusicPlayerController.shared;
    final canPlay = music.file != null && widget.onPlayMusic != null;
    return _richMediaWithCaption(
      AnimatedBuilder(
        animation: player,
        builder: (context, _) {
          final active = player.isActive(music.file);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: canPlay ? () => widget.onPlayMusic!(synthetic) : null,
            child: Container(
              width: math.min(_mediaMaxWidth(), 300),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.colors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.colors.divider, width: 0.5),
              ),
              child: Row(
                children: [
                  AppIcon(
                    active && player.isPlaying
                        ? HeroAppIcons.pause
                        : HeroAppIcons.play,
                    size: 22,
                    color: outgoing ? _outgoingTextColor : AppTheme.brand,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          music.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: context.colors.textPrimary,
                          ),
                        ),
                        if ((music.performer ?? '').trim().isNotEmpty)
                          Text(
                            music.performer!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.colors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      block,
      outgoing,
    );
  }

  Widget _richVoiceBlock(RichMessageBlock block, bool outgoing) {
    final voice = block.voice;
    if (voice == null) {
      return _richMissingMedia(HeroAppIcons.microphone, outgoing);
    }
    return _richMediaWithCaption(
      AnimatedBuilder(
        animation: _voice,
        builder: (context, _) {
          final active = _voice.isActive(voice.file);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _voice.toggleVoice(voice.file),
            child: Container(
              width: math.min(_mediaMaxWidth(), 250),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: context.colors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.colors.divider, width: 0.5),
              ),
              child: Row(
                children: [
                  AppIcon(
                    active && _voice.isPlaying
                        ? HeroAppIcons.pause
                        : HeroAppIcons.play,
                    size: 22,
                    color: outgoing ? _outgoingTextColor : AppTheme.brand,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: active && _voice.total.inMilliseconds > 0
                          ? (_voice.position.inMilliseconds /
                                    _voice.total.inMilliseconds)
                                .clamp(0, 1)
                                .toDouble()
                          : 0,
                      minHeight: 3,
                      color: outgoing ? _outgoingTextColor : AppTheme.brand,
                      backgroundColor: context.colors.divider,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _durationString(voice.duration),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      block,
      outgoing,
    );
  }

  Widget _richCollageBlock(RichMessageBlock block, bool outgoing) {
    final media = block.children
        .where((child) => _isRichMediaKind(child.kind))
        .toList();
    if (media.isEmpty) return _richMissingMedia(HeroAppIcons.images, outgoing);
    final width = _mediaMaxWidth();
    final cellWidth = media.length == 1 ? width : (width - 4) / 2;
    final collage = Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final child in media)
          SizedBox(
            width: cellWidth,
            height: media.length == 1 ? width * 0.7 : cellWidth,
            child: _richMediaThumbnail(child, outgoing),
          ),
      ],
    );
    return _richMediaWithCaption(collage, block, outgoing);
  }

  Widget _richSlideshowBlock(RichMessageBlock block, bool outgoing) {
    final media = block.children
        .where((child) => _isRichMediaKind(child.kind))
        .toList();
    if (media.isEmpty) {
      return _richMissingMedia(HeroAppIcons.tableColumns, outgoing);
    }
    final width = _mediaMaxWidth();
    final slideshow = SizedBox(
      width: width,
      height: width * 0.68,
      child: PageView.builder(
        itemCount: media.length,
        itemBuilder: (_, index) => Padding(
          padding: EdgeInsets.only(right: index == media.length - 1 ? 0 : 4),
          child: _richMediaThumbnail(media[index], outgoing),
        ),
      ),
    );
    return _richMediaWithCaption(slideshow, block, outgoing);
  }

  bool _isRichMediaKind(RichMessageBlockKind kind) =>
      kind == RichMessageBlockKind.photo ||
      kind == RichMessageBlockKind.video ||
      kind == RichMessageBlockKind.animation ||
      kind == RichMessageBlockKind.audio ||
      kind == RichMessageBlockKind.voiceNote;

  Widget _richMediaThumbnail(RichMessageBlock block, bool outgoing) {
    if (block.kind == RichMessageBlockKind.photo && block.image != null) {
      return GestureDetector(
        onTap: () => widget.onOpenImage?.call(_richMediaMessage(block)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: TDImage(photo: block.image),
        ),
      );
    }
    if ((block.kind == RichMessageBlockKind.video ||
            block.kind == RichMessageBlockKind.animation) &&
        block.image != null) {
      return GestureDetector(
        onTap: () => widget.onPlayVideo?.call(_richMediaMessage(block)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: TDImage(photo: block.image),
            ),
            const Center(
              child: AppIcon(HeroAppIcons.play, size: 25, color: Colors.white),
            ),
          ],
        ),
      );
    }
    return Center(child: _richMediaBlock(block, outgoing));
  }

  Widget _richMediaWithCaption(
    Widget media,
    RichMessageBlock block,
    bool outgoing,
  ) {
    if (block.caption.trim().isEmpty) return media;
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        media,
        const SizedBox(height: 5),
        ..._richTextWidgets(
          block.caption,
          outgoing ? _outgoingTextColor : _incomingTextColor,
          outgoing ? _outgoingTextColor : c.linkBlue,
          outgoing,
          false,
          block.captionEntities,
          13,
        ),
      ],
    );
  }

  Widget _richMissingMedia(AppIconData icon, bool outgoing) {
    return Container(
      width: math.min(_mediaMaxWidth(), 250),
      height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.colors.searchFill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: AppIcon(
        icon,
        size: 24,
        color: outgoing ? _outgoingTextColor : context.colors.textSecondary,
      ),
    );
  }

  ChatMessage _richMediaMessage(RichMessageBlock block) {
    final contentType = switch (block.kind) {
      RichMessageBlockKind.photo => 'messagePhoto',
      RichMessageBlockKind.video => 'messageVideo',
      RichMessageBlockKind.animation => 'messageAnimation',
      RichMessageBlockKind.audio => 'messageAudio',
      RichMessageBlockKind.voiceNote => 'messageVoiceNote',
      _ => 'messageRichMessage',
    };
    return ChatMessage(
      id: message.id,
      chatId: message.chatId,
      isOutgoing: message.isOutgoing,
      text: block.caption.trim().isEmpty ? '' : block.caption,
      date: message.date,
      contentType: contentType,
      image: block.image,
      imageWidth: block.imageWidth,
      imageHeight: block.imageHeight,
      video: block.video,
      videoDuration: block.videoDuration,
      music: block.music,
      voice: block.voice,
    );
  }

  Widget _richMathBlock(String expression, bool outgoing) {
    final c = context.colors;
    final base = outgoing ? _outgoingTextColor : c.textPrimary;
    final fill = outgoing
        ? _outgoingTextColor.withValues(alpha: 0.14)
        : c.searchFill.withValues(alpha: 0.72);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: outgoing
              ? _outgoingTextColor.withValues(alpha: 0.14)
              : c.divider.withValues(alpha: 0.8),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: _LatexView(
          expression: expression,
          style: TextStyle(fontSize: 15, color: base),
          display: true,
        ),
      ),
    );
  }

  Widget _richMapBlock(RichMessageBlock block, bool outgoing) {
    final location = block.mapLocation!;
    final c = context.colors;
    final base = outgoing ? _outgoingTextColor : c.textPrimary;
    final link = outgoing ? _outgoingTextColor : c.linkBlue;
    final sourceWidth = math.max(block.mapWidth, 1);
    final sourceHeight = math.max(block.mapHeight, 1);
    final previewHeight = (220 * sourceHeight / sourceWidth).clamp(100, 220);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LocationDetailView(location: location),
        ),
      ),
      child: Container(
        key: const ValueKey('rich-message-map'),
        width: double.infinity,
        decoration: BoxDecoration(
          color: outgoing
              ? _outgoingTextColor.withValues(alpha: 0.08)
              : c.card.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: outgoing
                ? _outgoingTextColor.withValues(alpha: 0.18)
                : c.divider,
            width: 0.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _MapThumbnail(
              latitude: location.latitude,
              longitude: location.longitude,
              zoom: block.mapZoom,
              height: previewHeight.toDouble(),
            ),
            if (block.caption.isNotEmpty)
              Padding(
                key: const ValueKey('rich-message-map-caption'),
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: _richTextWidgets(
                    block.caption,
                    base,
                    link,
                    outgoing,
                    false,
                    block.captionEntities,
                    13.5,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _richTableBlock(RichMessageBlock block, bool outgoing) {
    final c = context.colors;
    final base = outgoing ? _outgoingTextColor : c.textPrimary;
    final secondary = outgoing
        ? _outgoingTextColor.withValues(alpha: 0.72)
        : c.textSecondary;
    final link = outgoing ? _outgoingTextColor : c.linkBlue;
    final border = outgoing
        ? _outgoingTextColor.withValues(alpha: 0.22)
        : c.divider.withValues(alpha: 0.9);
    final headerFill = outgoing
        ? _outgoingTextColor.withValues(alpha: 0.16)
        : c.searchFill.withValues(alpha: 0.9);
    final cellFill = outgoing
        ? _outgoingTextColor.withValues(alpha: 0.07)
        : c.card.withValues(alpha: 0.88);
    final stripedFill = outgoing
        ? _outgoingTextColor.withValues(alpha: 0.11)
        : c.searchFill.withValues(alpha: 0.72);
    final maxColumns = block.tableRows.fold<int>(
      0,
      (max, row) => row.length > max ? row.length : max,
    );
    if (maxColumns == 0) return const SizedBox.shrink();
    final rows = <TableRow>[];
    for (var rowIndex = 0; rowIndex < block.tableRows.length; rowIndex++) {
      final row = block.tableRows[rowIndex];
      rows.add(
        TableRow(
          children: [
            for (var column = 0; column < maxColumns; column++)
              _richTableCell(
                column < row.length ? row[column] : null,
                isFallbackHeader: rowIndex == 0,
                base: base,
                link: link,
                secondary: secondary,
                fill:
                    column < row.length &&
                        (row[column].isHeader || rowIndex == 0)
                    ? headerFill
                    : block.isStriped && rowIndex.isOdd
                    ? stripedFill
                    : cellFill,
              ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (block.caption.isNotEmpty) ...[
          ..._richTextWidgets(
            block.caption,
            base,
            link,
            outgoing,
            false,
            block.captionEntities,
          ),
          const SizedBox(height: 6),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: block.isBordered
                  ? TableBorder.all(color: border, width: 0.8)
                  : null,
              children: rows,
            ),
          ),
        ),
      ],
    );
  }

  Widget _richTableCell(
    RichMessageTableCell? cell, {
    required bool isFallbackHeader,
    required Color base,
    required Color link,
    required Color secondary,
    required Color fill,
  }) {
    final isHeader = cell?.isHeader ?? isFallbackHeader;
    final text = cell?.text ?? '';
    final horizontal = switch (cell?.horizontalAlignment) {
      'center' => 0.0,
      'right' => 1.0,
      _ => -1.0,
    };
    final vertical = switch (cell?.verticalAlignment) {
      'middle' => 0.0,
      'bottom' => 1.0,
      _ => -1.0,
    };
    return TableCell(
      verticalAlignment: switch (cell?.verticalAlignment) {
        'middle' => TableCellVerticalAlignment.middle,
        'bottom' => TableCellVerticalAlignment.bottom,
        _ => TableCellVerticalAlignment.top,
      },
      child: Container(
        constraints: const BoxConstraints(
          minWidth: 72,
          maxWidth: 180,
          minHeight: 38,
        ),
        color: fill,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        alignment: Alignment(horizontal, vertical),
        child: text.isEmpty
            ? Text('', style: TextStyle(fontSize: 13, color: secondary))
            : Column(
                crossAxisAlignment: switch (cell?.horizontalAlignment) {
                  'center' => CrossAxisAlignment.center,
                  'right' => CrossAxisAlignment.end,
                  _ => CrossAxisAlignment.start,
                },
                mainAxisSize: MainAxisSize.min,
                children: _richTextWidgets(
                  text,
                  base,
                  link,
                  false,
                  false,
                  cell?.entities ?? const [],
                  isHeader ? 13.5 : 13,
                ),
              ),
      ),
    );
  }

  bool get _showsTranslation => _showsTranslationFor(message);

  bool _showsTranslationFor(ChatMessage source) =>
      source.isTranslating ||
      (source.translationText?.trim().isNotEmpty ?? false);

  bool get _showsAiSummary =>
      message.aiSummaryLoading ||
      (message.aiSummaryText?.trim().isNotEmpty ?? false);

  Widget _aiSummaryBlock(bool outgoing, {double? width}) {
    final c = context.colors;
    final base = outgoing ? _outgoingTextColor : c.textPrimary;
    final secondary = outgoing
        ? _outgoingTextColor.withValues(alpha: 0.70)
        : c.textSecondary;
    final link = outgoing ? _outgoingTextColor : c.linkBlue;
    return Container(
      key: const ValueKey('messageAiSummaryBlock'),
      width: width ?? _bubbleMaxWidth(),
      decoration: BoxDecoration(
        color: outgoing
            ? _outgoingTextColor.withValues(alpha: 0.10)
            : AppTheme.brand.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(7),
        border: Border(left: BorderSide(color: AppTheme.brand, width: 2.5)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
      child: message.aiSummaryLoading
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppActivityIndicator(size: 13, color: secondary),
                const SizedBox(width: 8),
                Text(
                  AppStrings.t(
                    AppStringKeys.messageBubbleSummarizingPrivatelyWithTelegram,
                  ),
                  style: TextStyle(fontSize: 13, color: secondary),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      HeroAppIcons.wandMagicSparkles,
                      size: 14,
                      color: secondary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      AppStrings.t(AppStringKeys.messageBubbleAISummary),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ..._richTextWidgets(
                  message.aiSummaryText ?? '',
                  base,
                  link,
                  outgoing,
                  false,
                  message.aiSummaryEntities,
                ),
              ],
            ),
    );
  }

  Widget _translationBlock(
    bool outgoing, {
    double? width,
    ChatMessage? source,
  }) {
    source ??= message;
    final c = context.colors;
    final base = outgoing ? _outgoingTextColor : c.textPrimary;
    final secondary = outgoing
        ? _outgoingTextColor.withValues(alpha: 0.70)
        : c.textSecondary;
    final link = outgoing ? _outgoingTextColor : c.linkBlue;
    return Container(
      key: const ValueKey('messageTranslationBlock'),
      width: width ?? _bubbleMaxWidth(),
      decoration: BoxDecoration(
        color: outgoing
            ? _outgoingTextColor.withValues(alpha: 0.10)
            : c.searchFill.withValues(alpha: 0.80),
        borderRadius: BorderRadius.circular(7),
        border: Border(left: BorderSide(color: secondary, width: 2.5)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
      child: source.isTranslating
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(secondary),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  AppStringKeys.messageBubbleTranslating.l10n(context),
                  style: TextStyle(fontSize: 13, color: secondary),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppStringKeys.messageActionTranslate.l10n(context),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: secondary,
                  ),
                ),
                const SizedBox(height: 4),
                ..._richTextWidgets(
                  source.translationText ?? '',
                  base,
                  link,
                  outgoing,
                  false,
                  source.translationEntities,
                ),
              ],
            ),
    );
  }

  Widget _linkPreviewCard(MessageLinkPreview preview, bool outgoing) {
    final c = context.colors;
    final base = outgoing ? _outgoingTextColor : c.textPrimary;
    final secondary = outgoing
        ? _outgoingTextColor.withValues(alpha: 0.75)
        : c.textSecondary;
    final link = outgoing ? _outgoingTextColor : c.linkBlue;
    final maxWidth = _bubbleMaxWidth();
    final media = _linkPreviewMedia(preview, maxWidth);
    final textChildren = <Widget>[
      if (preview.siteName.isNotEmpty)
        Text(
          preview.siteName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: link,
          ),
        ),
      if (preview.title.isNotEmpty)
        Text(
          preview.title,
          style: TextStyle(
            fontSize: 15,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: base,
          ),
        ),
      if (preview.description.isNotEmpty)
        ..._richTextWidgets(
          preview.description,
          base,
          link,
          outgoing,
          false,
          preview.descriptionEntities,
        ),
      if (preview.displayUrl.isNotEmpty)
        Text(
          preview.displayUrl,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: secondary),
        ),
    ];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: preview.url.isEmpty ? null : () => openLink(context, preview.url),
      child: Container(
        width: maxWidth,
        decoration: BoxDecoration(
          color: outgoing
              ? _outgoingTextColor.withValues(alpha: 0.10)
              : c.searchFill.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(7),
          border: Border(
            left: BorderSide(
              color: outgoing ? _outgoingTextColor : link,
              width: 3,
            ),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (media != null && preview.showMediaAboveDescription) media,
            if (textChildren.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < textChildren.length; i++) ...[
                      if (i > 0) const SizedBox(height: 4),
                      textChildren[i],
                    ],
                  ],
                ),
              ),
            if (media != null && !preview.showMediaAboveDescription) media,
          ],
        ),
      ),
    );
  }

  Widget? _linkPreviewMedia(MessageLinkPreview preview, double maxWidth) {
    final media = preview.image;
    if (media == null) return null;
    final large =
        preview.showLargeMedia || preview.type == 'linkPreviewTypePhoto';
    final width = large ? maxWidth : math.min(maxWidth, 210.0);
    final size = _fitSize(
      width: preview.imageWidth,
      height: preview.imageHeight,
      maxWidth: width,
      maxHeight: large ? 180 : 120,
      fallback: Size(width, large ? 140 : 96),
    );
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          TDImage(
            photo: media,
            cornerRadius: 0,
            cacheWidth: _cachePx(size.width),
            cacheHeight: _cachePx(size.height),
          ),
          if (preview.video != null)
            Center(
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const AppIcon(
                  HeroAppIcons.play,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // MARK: - Music

  Widget _musicCard(MessageMusic music, bool outgoing) {
    final c = context.colors;
    final maxWidth = math.min(MediaQuery.sizeOf(context).width * 0.70, 300.0);
    final caption = _caption();
    final performer = (music.performer ?? '').trim();
    final player = MusicPlayerController.shared;
    final canPlay = music.file != null && widget.onPlayMusic != null;
    final toggle = canPlay ? () => widget.onPlayMusic!(message) : null;
    final card = AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final active = player.isActive(music.file);
        final playing = active && player.isPlaying;
        final loading = active && player.isLoading;
        final total = active && player.total.inMilliseconds > 0
            ? player.total
            : Duration(seconds: music.duration);
        final position = active ? player.position : Duration.zero;
        final totalMs = math.max(1, total.inMilliseconds);
        final value = (position.inMilliseconds / totalMs).clamp(0.0, 1.0);

        return Container(
          width: maxWidth,
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: _messageBorderRadius(
              10,
              directlyAttached: caption == null,
            ),
            border: Border.all(color: c.divider, width: 0.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            music.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18,
                              height: 1.25,
                              fontWeight: FontWeight.w500,
                              color: c.textPrimary,
                            ),
                          ),
                          if (performer.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              performer,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.25,
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _musicCover(
                      music.cover,
                      loading: loading,
                      playing: playing,
                      onTap: toggle,
                      pressed: _musicPressed,
                      onTapDown: canPlay
                          ? () => setState(() => _musicPressed = true)
                          : null,
                      onTapEnd: canPlay
                          ? () => setState(() => _musicPressed = false)
                          : null,
                    ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 0.5, color: c.divider),
              active || loading
                  ? _musicProgressBar(
                      value: value.toDouble(),
                      position: position,
                      total: total,
                      canPlay: canPlay,
                      onChanged: player.seekFraction,
                      onChangeEnd: player.seekFraction,
                    )
                  : _musicProviderBar(),
            ],
          ),
        );
      },
    );
    return _attachmentWithCaption(card, outgoing, caption: caption);
  }

  Widget _attachmentWithCaption(
    Widget attachment,
    bool outgoing, {
    String? caption,
  }) {
    caption ??= _caption();
    if (caption == null) return attachment;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: outgoing
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        attachment,
        const SizedBox(height: 4),
        _textBubble(caption, outgoing),
      ],
    );
  }

  Widget _musicProviderBar() {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 7, 14, 8),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFF3B30),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const AppIcon(
              HeroAppIcons.music,
              color: Colors.white,
              size: 14,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            AppStringKeys.netemoMusicLabel.l10n(context),
            style: TextStyle(fontSize: 14, color: c.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _musicProgressBar({
    required double value,
    required Duration position,
    required Duration total,
    required bool canPlay,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 14, 0),
      child: Row(
        children: [
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: AppTheme.brand,
                inactiveTrackColor: c.divider,
                thumbColor: AppTheme.brand,
                overlayColor: AppTheme.brand.withValues(alpha: 0.12),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 13),
              ),
              child: Slider(
                value: value,
                onChanged: canPlay ? onChanged : null,
                onChangeEnd: canPlay ? onChangeEnd : null,
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 70,
            child: Text(
              '${_durationString(position.inSeconds)}/'
              '${total.inSeconds > 0 ? _durationString(total.inSeconds) : '--:--'}',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, color: c.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _musicCover(
    TdFileRef? cover, {
    required bool loading,
    required bool playing,
    required bool pressed,
    VoidCallback? onTap,
    VoidCallback? onTapDown,
    VoidCallback? onTapEnd,
  }) {
    final c = context.colors;
    const size = 58.0;
    final art = cover != null
        ? TDImage(
            photo: cover,
            cacheWidth: _cachePx(size),
            cacheHeight: _cachePx(size),
          )
        : Container(
            color: AppTheme.brand.withValues(alpha: 0.12),
            alignment: Alignment.center,
            child: AppIcon(
              HeroAppIcons.compactDisc,
              size: 28,
              color: c.textSecondary,
            ),
          );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onTapDown: (_) => onTapDown?.call(),
      onTapCancel: onTapEnd,
      onTapUp: (_) => onTapEnd?.call(),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            art,
            AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              color: Colors.black.withValues(alpha: pressed ? 0.34 : 0.18),
            ),
            Center(
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.42),
                  shape: BoxShape.circle,
                ),
                child: loading
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : AppIcon(
                        playing ? HeroAppIcons.pause : HeroAppIcons.play,
                        color: Colors.white,
                        size: 17,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // MARK: - Call log bubble (custom: icon + status, tap to redial)

  /// A messageCall rendered like the reference app's call-log bubble: a phone/video glyph plus
  /// the call's outcome (通话时长 MM:SS when it connected, otherwise 已取消 /
  /// 未接听 / 已拒绝). Tapping the bubble places the same kind of call again
  /// (点击重拨). The glyph sits toward the bubble's outer edge like profile.
  Widget _callBubble(bool outgoing) {
    final c = context.colors;
    final isVideo = message.callIsVideo;
    final connected = message.callDuration > 0;
    final baseColor = outgoing ? _outgoingTextColor : _incomingTextColor;

    String label;
    bool missed = false;
    if (connected) {
      label = AppStrings.t(AppStringKeys.messageBubbleCallDuration, {
        'value1': _formatCallDuration(message.callDuration),
      });
    } else {
      switch (message.callDiscardReason) {
        case 'callDiscardReasonDeclined':
          label = AppStrings.t(
            outgoing
                ? AppStringKeys.messageBubbleCallDeclinedByOther
                : AppStringKeys.messageBubbleCallDeclined,
          );
          missed = !outgoing;
        case 'callDiscardReasonMissed':
          label = AppStrings.t(
            outgoing
                ? AppStringKeys.messageBubbleCallNoAnswer
                : AppStringKeys.messageBubbleCallMissed,
          );
          missed = !outgoing;
        default: // HungUp / Empty / Disconnected with no duration
          label = AppStrings.t(AppStringKeys.messageBubbleCallCanceled);
      }
    }
    final accent = missed ? const Color(0xFFFF3B30) : baseColor;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onRedial?.call(isVideo),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: outgoing ? _outgoingBubbleColor : _incomingBubbleColor,
          borderRadius: _messageBorderRadius(6),
          border: outgoing ? null : Border.all(color: c.divider, width: 0.5),
        ),
        // Call glyph always on the left of the status, both directions.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isVideo ? HeroAppIcons.video.data : HeroAppIcons.phone.data,
              size: 18,
              color: accent,
            ),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 15, color: accent)),
          ],
        ),
      ),
    );
  }

  String _formatCallDuration(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    String two(int v) => v.toString().padLeft(2, '0');
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    return h > 0 ? '${two(h)}:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
  }

  /// 转发 attribution shown above forwarded content: `转发自 …`.
  Widget _forwardHeader(bool outgoing) {
    final c = context.colors;
    final accent = outgoing ? _outgoingTextColor : AppTheme.brand;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(
          HeroAppIcons.share,
          size: 11,
          color: accent.withValues(alpha: 0.9),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            telegramText(AppStringKeys.messageBubbleForwardedFrom, {
              'value1': message.forwardOrigin,
            }),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: outgoing ? _outgoingTextColor : c.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  /// 引用 quote block shown above a reply's text.
  Widget _replyQuote(bool outgoing) {
    final c = context.colors;
    final labelColor = outgoing ? _outgoingTextColor : c.textPrimary;
    final faded = outgoing
        ? _outgoingTextColor.withValues(alpha: 0.72)
        : c.textSecondary;
    final sender = message.replyToSender ?? '';
    final time = DateText.quoteLabel(message.replyToDate ?? 0);
    final targetId = message.replyToMessageId;
    return Container(
      key: const ValueKey('messageReplyQuote'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 9),
      decoration: BoxDecoration(
        color: _replyQuoteBackground(outgoing),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.replyToImage != null) ...[
            SizedBox(
              key: const ValueKey('messageReplyMediaPreview'),
              width: 44,
              height: 44,
              child: TDImage(
                photo: message.replyToImage,
                cornerRadius: 6,
                cacheWidth: _cachePx(44),
                cacheHeight: _cachePx(44),
              ),
            ),
            const SizedBox(width: 9),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      if (sender.isNotEmpty)
                        TextSpan(
                          text: sender,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      if (time.isNotEmpty)
                        TextSpan(text: sender.isEmpty ? time : ' $time'),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: labelColor),
                ),
                if ((message.replyToPreview ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    message.replyToPreview!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, height: 1.22, color: faded),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            key: const ValueKey('messageReplyOpenOriginal'),
            behavior: HitTestBehavior.opaque,
            onTap: targetId == null
                ? null
                : () => widget.onOpenReply?.call(targetId),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 1, 4, 9),
              child: AppIcon(HeroAppIcons.arrowUp, size: 18, color: faded),
            ),
          ),
        ],
      ),
    );
  }

  Color _replyQuoteBackground(bool outgoing) {
    final base = outgoing ? _outgoingBubbleColor : _incomingBubbleColor;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Color.lerp(base, dark ? Colors.white : Colors.black, 0.10)!;
  }

  // URLs (group 1), @username mentions (group 2), and #hashtags (group 3).
  // The lookbehind stops email local-parts (user@host), @@ and ## from being
  // matched as mentions/tags.
  static final _linkRegExp = RegExp(
    r'((?:https?:\/\/|www\.|t\.me\/|tg:\/\/)[^\s]+)|(?<![\w@])(@[A-Za-z0-9_]{4,32})|(?<![\w#])(#[A-Za-z0-9_\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]+)',
    caseSensitive: false,
    unicode: true,
  );

  /// Trailing inline meta after the text: time + edited pencil + delivery dots.
  InlineSpan _metaSpan(bool outgoing) {
    final faint = outgoing
        ? _outgoingTextColor.withValues(alpha: 0.65)
        : context.colors.textTertiary;
    return WidgetSpan(
      child: Padding(
        padding: const EdgeInsets.only(left: 6, top: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.message.isEdited)
              AppIcon(HeroAppIcons.pen, size: 11, color: faint),
            if (widget.message.isEdited && outgoing) const SizedBox(width: 4),
            if (outgoing)
              _deliveryDots(diameter: 3.5, color: _outgoingTextColor),
          ],
        ),
      ),
    );
  }

  Widget _deliveryDots({required double diameter, required Color color}) {
    Widget dot(int index) => Container(
      key: ValueKey('messageDeliveryDot-$index'),
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot(0),
        if (widget.isRead) ...[SizedBox(width: diameter * 0.75), dot(1)],
      ],
    );
  }

  List<Widget> _richTextWidgets(
    String text,
    Color base,
    Color link,
    bool outgoing,
    bool appendMeta, [
    List<MessageTextEntity>? entities,
    double fontSize = 15,
  ]) {
    final sourceEntities = entities ?? message.textEntities;
    final blocks =
        sourceEntities.where((e) => e.isBlockQuote || e.isPreBlock).toList()
          ..sort((a, b) => a.offset.compareTo(b.offset));
    if (blocks.isEmpty) {
      return [
        _richText(
          text,
          base,
          link,
          0,
          text.length,
          outgoing,
          appendMeta,
          entities: sourceEntities,
          fontSize: fontSize,
        ),
      ];
    }

    final widgets = <Widget>[];
    var cursor = 0;
    var metaAdded = false;
    for (final block in blocks) {
      final start = block.offset.clamp(0, text.length).toInt();
      final end = block.end.clamp(start, text.length).toInt();
      if (end <= cursor) continue;
      if (start > cursor) {
        widgets.add(
          _richText(
            text,
            base,
            link,
            cursor,
            start,
            outgoing,
            false,
            entities: sourceEntities,
            fontSize: fontSize,
          ),
        );
        widgets.add(const SizedBox(height: 5));
      }
      widgets.add(
        block.isPreBlock
            ? _preBlock(
                block,
                text,
                start,
                end,
                base,
                link,
                sourceEntities,
                fontSize,
              )
            : _quoteBlock(
                block,
                text,
                start,
                end,
                base,
                link,
                sourceEntities,
                fontSize,
              ),
      );
      cursor = end;
    }
    if (cursor < text.length) {
      widgets.add(const SizedBox(height: 5));
      widgets.add(
        _richText(
          text,
          base,
          link,
          cursor,
          text.length,
          outgoing,
          appendMeta,
          entities: sourceEntities,
          fontSize: fontSize,
        ),
      );
      metaAdded = appendMeta;
    }
    if (appendMeta && !metaAdded) {
      widgets.add(
        Align(
          alignment: Alignment.centerRight,
          child: RichText(text: TextSpan(children: [_metaSpan(outgoing)])),
        ),
      );
    }
    return widgets;
  }

  Widget _richText(
    String text,
    Color base,
    Color link,
    int start,
    int end,
    bool outgoing,
    bool appendMeta, {
    int? maxLines,
    List<MessageTextEntity>? entities,
    double fontSize = 15,
  }) {
    final effectiveFontSize = _chatFontSize(fontSize);
    final children = _entitySpans(
      text,
      start,
      end,
      base,
      link,
      entities ?? message.textEntities,
      effectiveFontSize,
    );
    if (appendMeta) children.add(_metaSpan(outgoing));
    final style = DefaultTextStyle.of(
      context,
    ).style.merge(TextStyle(fontSize: effectiveFontSize, color: base));
    return RichText(
      maxLines: maxLines,
      overflow: maxLines == null ? TextOverflow.clip : TextOverflow.fade,
      text: TextSpan(style: style, children: children),
    );
  }

  Widget _quoteBlock(
    MessageTextEntity quote,
    String text,
    int start,
    int end,
    Color base,
    Color link,
    List<MessageTextEntity> entities,
    double fontSize,
  ) {
    final c = context.colors;
    final key = '${quote.offset}:${quote.length}';
    final expanded =
        !quote.isExpandableBlockQuote || _expandedQuotes.contains(key);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: quote.isExpandableBlockQuote
          ? () {
              setState(() {
                if (expanded) {
                  _expandedQuotes.remove(key);
                } else {
                  _expandedQuotes.add(key);
                }
              });
            }
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: c.searchFill.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(6),
          border: Border(left: BorderSide(color: AppTheme.brand, width: 3)),
        ),
        padding: const EdgeInsets.fromLTRB(9, 7, 8, 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _richText(
              text,
              base,
              link,
              start,
              end,
              false,
              false,
              maxLines: expanded ? null : 3,
              entities: entities,
              fontSize: fontSize,
            ),
            if (quote.isExpandableBlockQuote) ...[
              const SizedBox(height: 4),
              Text(
                AppStrings.t(
                  expanded
                      ? AppStringKeys.messageBubbleCollapse
                      : AppStringKeys.messageBubbleExpandQuote,
                ),
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.brand,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _preBlock(
    MessageTextEntity pre,
    String text,
    int start,
    int end,
    Color base,
    Color link,
    List<MessageTextEntity> entities,
    double fontSize,
  ) {
    final c = context.colors;
    final language = (pre.language ?? '').trim();
    final codeBackground = _codeBackgroundColor;
    return GestureDetector(
      key: const ValueKey('message-code-block'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _copyMonospaceText(text.substring(start, end)),
      child: Container(
        width: _bubbleMaxWidth(),
        decoration: BoxDecoration(
          color: codeBackground,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: c.divider, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (language.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(10, 5, 10, 4),
                color:
                    (Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black)
                        .withValues(alpha: 0.045),
                child: Text(
                  language,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: c.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
              child: _richText(
                text,
                base,
                link,
                start,
                end,
                false,
                false,
                entities: entities,
                fontSize: math.max(13.0, fontSize - 1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color get _codeBackgroundColor {
    return (Theme.of(context).brightness == Brightness.dark
            ? Colors.white
            : Colors.black)
        .withValues(alpha: 0.10);
  }

  void _copyMonospaceText(String text) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text)).then((_) {
      if (mounted) {
        showToast(context, AppStringKeys.topicPostContentCopied);
      }
    });
  }

  List<InlineSpan> _entitySpans(
    String text,
    int start,
    int end,
    Color base,
    Color link,
    List<MessageTextEntity> sourceEntities,
    double fontSize,
  ) {
    final entities =
        sourceEntities
            .where((e) => !e.isBlockQuote && e.offset < end && e.end > start)
            .toList()
          ..sort((a, b) => a.offset.compareTo(b.offset));
    final spans = <InlineSpan>[];
    var cursor = start;
    while (cursor < end) {
      MessageTextEntity? emoji;
      for (final e in entities) {
        if (e.isCustomEmoji &&
            e.customEmojiId != null &&
            e.offset == cursor &&
            e.end <= end) {
          emoji = e;
          break;
        }
      }
      if (emoji != null) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0.5),
              child: CustomEmojiView(
                id: emoji.customEmojiId!,
                size: math.max(20, fontSize * 1.15),
                color: base,
              ),
            ),
          ),
        );
        cursor = emoji.end.clamp(cursor + 1, end).toInt();
        continue;
      }

      var next = end;
      for (final e in entities) {
        final eStart = e.offset.clamp(start, end).toInt();
        final eEnd = e.end.clamp(start, end).toInt();
        if (eStart > cursor) next = math.min(next, eStart);
        if (eStart <= cursor && eEnd > cursor) next = math.min(next, eEnd);
      }
      if (next <= cursor) next = cursor + 1;
      final active = entities
          .where((e) => e.offset <= cursor && e.end >= next)
          .toList();
      final segment = text.substring(cursor, next);
      if (segment == '\n') {
        spans.add(const TextSpan(text: '\n'));
        cursor = next;
        continue;
      }
      spans.addAll(_textSegmentSpans(segment, active, base, link, fontSize));
      cursor = next;
    }
    return spans;
  }

  List<InlineSpan> _textSegmentSpans(
    String segment,
    List<MessageTextEntity> active,
    Color base,
    Color link,
    double fontSize,
  ) {
    final spoilerKey = _spoilerKey(active);
    final spoilerHidden =
        spoilerKey != null && !_revealedSpoilers.contains(spoilerKey);
    if (spoilerHidden) {
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          if (!mounted) return;
          setState(() => _revealedSpoilers.add(spoilerKey));
        };
      _linkRecognizers.add(recognizer);
      return [
        TextSpan(
          text: segment,
          style: _entityStyle(active, base, link),
          recognizer: recognizer,
        ),
      ];
    }

    final effectiveActive = spoilerKey == null
        ? active
        : active
              .where((e) => e.type != 'textEntityTypeSpoiler')
              .toList(growable: false);
    final style = _entityStyle(effectiveActive, base, link);
    if (_hasMath(effectiveActive)) {
      return [_inlineMathSpan(segment, style, fontSize)];
    }
    if (_hasInlineCode(effectiveActive)) {
      return [_inlineCodeSpan(segment, style, fontSize)];
    }
    final userId = _entityMentionUserId(effectiveActive);
    if (userId != null) {
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProfileDetailView(userId: userId, name: segment),
            ),
          );
        };
      _linkRecognizers.add(recognizer);
      return [TextSpan(text: segment, style: style, recognizer: recognizer)];
    }
    final target = _entityTapTarget(segment, effectiveActive);
    if (target == '__bot_command__') {
      final recognizer = TapGestureRecognizer()
        ..onTap = () => widget.onBotCommandTap?.call(segment.trim());
      _linkRecognizers.add(recognizer);
      return [TextSpan(text: segment, style: style, recognizer: recognizer)];
    }
    if (target == '__hashtag__') {
      if (widget.onHashtagTap == null) {
        return [TextSpan(text: segment, style: style)];
      }
      final recognizer = TapGestureRecognizer()
        ..onTap = () => widget.onHashtagTap?.call(_normalizeHashtag(segment));
      _linkRecognizers.add(recognizer);
      return [TextSpan(text: segment, style: style, recognizer: recognizer)];
    }
    if (target != null) {
      final recognizer = TapGestureRecognizer()
        ..onTap = () => openLink(context, target);
      _linkRecognizers.add(recognizer);
      return [TextSpan(text: segment, style: style, recognizer: recognizer)];
    }
    if (_hasPreCode(active)) return [TextSpan(text: segment, style: style)];
    return _linkSpansStyled(segment, style, link);
  }

  InlineSpan _inlineCodeSpan(String segment, TextStyle style, double fontSize) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: GestureDetector(
        key: const ValueKey('message-inline-code'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _copyMonospaceText(segment),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: _codeBackgroundColor,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(segment, style: style.copyWith(fontSize: fontSize)),
        ),
      ),
    );
  }

  InlineSpan _inlineMathSpan(String segment, TextStyle style, double fontSize) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: _LatexView(
        expression: segment,
        style: style.copyWith(fontSize: fontSize),
      ),
    );
  }

  bool _hasInlineCode(List<MessageTextEntity> active) {
    return active.any((e) => e.type == 'textEntityTypeCode');
  }

  bool _hasMath(List<MessageTextEntity> active) {
    return active.any((e) => e.isMathematicalExpression);
  }

  bool _hasPreCode(List<MessageTextEntity> active) {
    return active.any(
      (e) => e.type == 'textEntityTypePre' || e.type == 'textEntityTypePreCode',
    );
  }

  String? _spoilerKey(List<MessageTextEntity> active) {
    for (final e in active) {
      if (e.type == 'textEntityTypeSpoiler') return '${e.offset}:${e.length}';
    }
    return null;
  }

  TextStyle _entityStyle(
    List<MessageTextEntity> active,
    Color base,
    Color link,
  ) {
    var color = base;
    var weight = FontWeight.w400;
    FontStyle? fontStyle;
    Color? backgroundColor;
    var useCodeFont = false;
    var fontFeatures = const <FontFeature>[];
    final decorations = <TextDecoration>[];
    for (final e in active) {
      switch (e.type) {
        case 'textEntityTypeBold':
          weight = FontWeight.w600;
        case 'textEntityTypeItalic':
          fontStyle = FontStyle.italic;
        case 'textEntityTypeUnderline':
          decorations.add(TextDecoration.underline);
        case 'textEntityTypeStrikethrough':
          decorations.add(TextDecoration.lineThrough);
        case 'textEntityTypeCode':
          useCodeFont = true;
        case 'textEntityTypePre':
        case 'textEntityTypePreCode':
          useCodeFont = true;
        case 'textEntityTypeSpoiler':
          color = base.withValues(alpha: 0.06);
          backgroundColor = base.withValues(alpha: 0.34);
        case 'textEntityTypeTextUrl':
        case 'textEntityTypeUrl':
        case 'textEntityTypeMention':
        case 'textEntityTypeMentionName':
        case 'textEntityTypeHashtag':
        case 'textEntityTypeCashtag':
        case 'textEntityTypeBotCommand':
        case 'textEntityTypeEmailAddress':
        case 'textEntityTypePhoneNumber':
        case 'textEntityTypeBankCardNumber':
          color = link;
          decorations.add(TextDecoration.underline);
        case 'textEntityTypeMediaTimestamp':
          color = link;
          weight = FontWeight.w600;
        case 'textEntityTypeMarked':
          backgroundColor = Colors.amber.withValues(alpha: 0.32);
        case 'textEntityTypeSubscript':
          fontFeatures = const [FontFeature.subscripts()];
        case 'textEntityTypeSuperscript':
          fontFeatures = const [FontFeature.superscripts()];
        case 'textEntityTypeDateTime':
          color = link;
      }
    }
    final style = TextStyle(
      color: color,
      fontWeight: weight,
      fontStyle: fontStyle,
      backgroundColor: backgroundColor,
      decoration: decorations.isEmpty
          ? null
          : TextDecoration.combine(decorations),
      decorationColor: color,
      fontFeatures: fontFeatures.isEmpty ? null : fontFeatures,
    );
    return useCodeFont
        ? context.watch<ThemeController>().codeTextStyle(style)
        : style;
  }

  String? _entityTapTarget(String segment, List<MessageTextEntity> active) {
    for (final e in active.reversed) {
      switch (e.type) {
        case 'textEntityTypeTextUrl':
          return e.url;
        case 'textEntityTypeUrl':
          return segment;
        case 'textEntityTypeMention':
          return segment.startsWith('@')
              ? 'https://t.me/${segment.substring(1)}'
              : null;
        case 'textEntityTypeHashtag':
          return '__hashtag__';
        case 'textEntityTypeCashtag':
        case 'textEntityTypeBotCommand':
          return e.type == 'textEntityTypeBotCommand'
              ? '__bot_command__'
              : null;
        case 'textEntityTypeEmailAddress':
          return 'mailto:$segment';
        case 'textEntityTypePhoneNumber':
          return 'tel:${segment.replaceAll(RegExp(r'[^0-9+]'), '')}';
        case 'textEntityTypeBankCardNumber':
          return null;
        case 'textEntityTypeMentionName':
          return null;
      }
    }
    return null;
  }

  int? _entityMentionUserId(List<MessageTextEntity> active) {
    for (final e in active.reversed) {
      if (e.type == 'textEntityTypeMentionName' && e.userId != null) {
        return e.userId;
      }
    }
    return null;
  }

  List<InlineSpan> _linkSpansStyled(
    String text,
    TextStyle baseStyle,
    Color link,
  ) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _linkRegExp.allMatches(text)) {
      if (m.start > last) {
        spans.add(
          TextSpan(text: text.substring(last, m.start), style: baseStyle),
        );
      }
      final matched = text.substring(m.start, m.end);
      final isMention = m.group(2) != null;
      final isHashtag = m.group(3) != null;
      final target = isMention
          ? 'https://t.me/${matched.substring(1)}'
          : matched;
      if (isHashtag && widget.onHashtagTap == null) {
        spans.add(
          TextSpan(
            text: matched,
            style: baseStyle.copyWith(color: link),
          ),
        );
        last = m.end;
        continue;
      }
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          if (isHashtag) {
            widget.onHashtagTap?.call(_normalizeHashtag(matched));
          } else {
            openLink(context, target);
          }
        };
      _linkRecognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: matched,
          style: baseStyle.copyWith(
            color: link,
            decoration: isMention || isHashtag
                ? baseStyle.decoration
                : TextDecoration.underline,
            decorationColor: link,
          ),
          recognizer: recognizer,
        ),
      );
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: baseStyle));
    }
    return spans;
  }

  String _normalizeHashtag(String tag) {
    final trimmed = tag.trim();
    return trimmed.startsWith('#') ? trimmed : '#$trimmed';
  }

  // MARK: - Image

  int _cachePx(double logical) =>
      (logical * MediaQuery.devicePixelRatioOf(context)).ceil();

  Widget _imageContent(TdFileRef image, bool outgoing) {
    final imageSize = _imageDisplaySize();
    final caption = _caption();
    final usesBlurredFrame =
        caption != null && _usesBlurredImageFrame(imageSize);
    final frameSize = usesBlurredFrame
        ? Size(_mediaMaxWidth(), imageSize.height)
        : imageSize;
    final grouped = _groupsMediaCaption(caption);
    final mediaRadius = grouped ? 0.0 : 10.0;
    final mediaBorderRadius = _messageBorderRadius(
      mediaRadius,
      directlyAttached: caption == null,
    );
    final media = GestureDetector(
      onTap: () => widget.onOpenImage?.call(message),
      child: SizedBox(
        width: frameSize.width,
        height: frameSize.height,
        child: usesBlurredFrame
            ? _blurredImageFrame(image, imageSize, frameSize, mediaBorderRadius)
            : ClipRRect(
                borderRadius: mediaBorderRadius,
                child: TDImage(
                  photo: image,
                  cornerRadius: 0,
                  fit: BoxFit.contain,
                  cacheWidth: _cachePx(imageSize.width),
                  cacheHeight: _cachePx(imageSize.height),
                  showProgress: true,
                ),
              ),
      ),
    );
    return _mediaWithCaption(
      media: media,
      caption: caption,
      outgoing: outgoing,
    );
  }

  Widget _blurredImageFrame(
    TdFileRef image,
    Size imageSize,
    Size frameSize,
    BorderRadius borderRadius,
  ) {
    final frameCacheWidth = _cachePx(frameSize.width);
    final frameCacheHeight = _cachePx(frameSize.height);
    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Transform.scale(
              scale: 1.08,
              child: TDImage(
                photo: image,
                cornerRadius: 0,
                cacheWidth: frameCacheWidth,
                cacheHeight: frameCacheHeight,
              ),
            ),
          ),
          ColoredBox(color: Colors.black.withValues(alpha: 0.10)),
          Center(
            child: SizedBox(
              width: imageSize.width,
              height: imageSize.height,
              child: TDImage(
                photo: image,
                cornerRadius: 0,
                fit: BoxFit.contain,
                cacheWidth: _cachePx(imageSize.width),
                cacheHeight: _cachePx(imageSize.height),
                showProgress: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _groupsMediaCaption(String? caption) =>
      caption != null && context.watch<ThemeController>().groupImageMessages;

  Widget _mediaWithCaption({
    required Widget media,
    required String? caption,
    required bool outgoing,
  }) {
    if (!_groupsMediaCaption(caption)) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: outgoing
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          media,
          if (caption != null) ...[
            const SizedBox(height: 4),
            _textBubble(caption, outgoing),
          ],
        ],
      );
    }

    final c = context.colors;
    final baseColor = outgoing ? _outgoingTextColor : _incomingTextColor;
    final linkColor = outgoing ? _outgoingTextColor : c.linkBlue;
    return Container(
      decoration: BoxDecoration(
        color: outgoing ? _outgoingBubbleColor : _incomingBubbleColor,
        borderRadius: _messageBorderRadius(8),
        border: outgoing ? null : Border.all(color: c.divider, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          media,
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 7, 6, 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ..._richTextWidgets(
                  caption!,
                  baseColor,
                  linkColor,
                  outgoing,
                  false,
                ),
                if (_showsTranslation) ...[
                  const SizedBox(height: 7),
                  _translationBlock(outgoing, width: double.infinity),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _staticStickerContent(TdFileRef image) {
    final size = _stickerSize();
    return _stickerTap(
      SizedBox(
        width: size.width,
        height: size.height,
        child: TDImage(
          photo: image,
          fit: BoxFit.contain,
          cacheWidth: _cachePx(size.width),
          cacheHeight: _cachePx(size.height),
        ),
      ),
    );
  }

  /// A video message: its thumbnail with a play button + duration badge.
  /// Tapping opens the fullscreen player (which downloads + plays the file).
  Widget _videoContent(bool outgoing) {
    final size = _imageDisplaySize();
    final caption = _caption();
    final dur = message.videoDuration ?? 0;
    final grouped = _groupsMediaCaption(caption);
    final mediaRadius = grouped ? 0.0 : 10.0;
    final media = GestureDetector(
      onTap: () => widget.onPlayVideo?.call(message),
      onLongPress: () => _handleLongPress(MessageActionSource.video),
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: _messageBorderRadius(
                mediaRadius,
                directlyAttached: caption == null,
              ),
              child: message.image != null
                  ? TDImage(
                      photo: message.image,
                      cornerRadius: 0,
                      cacheWidth: _cachePx(size.width),
                      cacheHeight: _cachePx(size.height),
                      showProgress: true,
                    )
                  : Container(color: Colors.black26),
            ),
            // Play button.
            Center(
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const AppIcon(
                  HeroAppIcons.play,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
            // Duration badge.
            if (dur > 0)
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _durationString(dur),
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return _mediaWithCaption(
      media: media,
      caption: caption,
      outgoing: outgoing,
    );
  }

  /// Telegram GIFs arrive as silent MP4 animations. Start them inline and
  /// repeat indefinitely; tapping still opens the full media viewer.
  Widget _animationContent(bool outgoing) {
    final size = _imageDisplaySize();
    final caption = _caption();
    final grouped = _groupsMediaCaption(caption);
    final mediaRadius = grouped ? 0.0 : 10.0;
    final media = GestureDetector(
      onTap: () => widget.onPlayVideo?.call(message),
      onLongPress: () => _handleLongPress(MessageActionSource.video),
      child: ClipRRect(
        borderRadius: _messageBorderRadius(
          mediaRadius,
          directlyAttached: caption == null,
        ),
        child: SizedBox(
          key: ValueKey('message-animation-${message.id}'),
          width: size.width,
          height: size.height,
          child: LoopingVideoView(
            file: message.video!,
            fallback: message.image,
            showDownloadProgress: true,
          ),
        ),
      ),
    );
    return _mediaWithCaption(
      media: media,
      caption: caption,
      outgoing: outgoing,
    );
  }

  String? _caption() {
    final text = _activeMessageText;
    return text.trim().isEmpty ? null : text;
  }

  Size _imageDisplaySize() {
    final maxWidth = _mediaMaxWidth();
    return _fitSize(
      width: message.imageWidth,
      height: message.imageHeight,
      maxWidth: maxWidth,
      maxHeight: maxWidth,
      fallback: Size(maxWidth, maxWidth),
    );
  }

  bool _usesBlurredImageFrame(Size imageSize) {
    final w = message.imageWidth;
    final h = message.imageHeight;
    if (w == null || h == null || w <= 0 || h <= 0) return false;
    final maxWidth = _mediaMaxWidth();
    final sourceAspect = w / h;
    return sourceAspect <= 0.68 && imageSize.width < maxWidth * 0.78;
  }

  Size _fitSize({
    required int? width,
    required int? height,
    required double maxWidth,
    required double maxHeight,
    required Size fallback,
  }) {
    final w = width, h = height;
    if (w == null || h == null || w <= 0 || h <= 0) {
      return fallback;
    }
    final aspect = w / h;
    var dw = maxWidth;
    var dh = dw / aspect;
    if (dh > maxHeight) {
      dh = maxHeight;
      dw = dh * aspect;
    }
    return Size(dw, dh);
  }

  Size _stickerSize() {
    const maxSide = 120.0;
    final w = message.imageWidth, h = message.imageHeight;
    if (w == null || h == null || w <= 0 || h <= 0) {
      return const Size(maxSide, maxSide);
    }
    final aspect = w / h;
    return aspect >= 1
        ? Size(maxSide, maxSide / aspect)
        : Size(maxSide * aspect, maxSide);
  }

  // MARK: - Voice

  Widget _voiceBubble(MessageVoice voice, bool outgoing) {
    final c = context.colors;
    final fg = outgoing ? _outgoingTextColor : AppTheme.brand;
    final track = outgoing
        ? _outgoingTextColor.withValues(alpha: 0.35)
        : AppTheme.brand.withValues(alpha: 0.25);
    return AnimatedBuilder(
      animation: _voice,
      builder: (context, _) {
        final total = _voice.total.inMilliseconds > 0
            ? _voice.total
            : Duration(seconds: voice.duration);
        final frac = total.inMilliseconds > 0
            ? (_voice.position.inMilliseconds / total.inMilliseconds).clamp(
                0.0,
                1.0,
              )
            : 0.0;
        final played = _voice.isPlaying || _voice.position > Duration.zero;
        final timeText = played
            ? _durationString(_voice.position.inSeconds)
            : _durationString(voice.duration);
        return Container(
          width: 210,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: outgoing ? _outgoingBubbleColor : _incomingBubbleColor,
            borderRadius: _messageBorderRadius(
              6,
              directlyAttached: _caption() == null,
            ),
            border: outgoing ? null : Border.all(color: c.divider, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => _voice.toggleVoice(voice.file),
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: outgoing
                            ? _outgoingTextColor.withValues(alpha: 0.25)
                            : AppTheme.brand.withValues(alpha: 0.12),
                      ),
                      child: _voice.isLoading
                          ? AppActivityIndicator(size: 14, color: fg)
                          : AppIcon(
                              _voice.isPlaying
                                  ? HeroAppIcons.pause
                                  : HeroAppIcons.play,
                              size: 14,
                              color: fg,
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (ctx, box) {
                        final w = box.maxWidth;
                        void seekAt(double dx) =>
                            _voice.seekFraction(dx / w, voice.duration);
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (d) => seekAt(d.localPosition.dx),
                          onHorizontalDragStart: (d) =>
                              seekAt(d.localPosition.dx),
                          onHorizontalDragUpdate: (d) =>
                              seekAt(d.localPosition.dx),
                          child: SizedBox(
                            height: 22,
                            child: Stack(
                              alignment: Alignment.centerLeft,
                              children: [
                                Container(
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: track,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                FractionallySizedBox(
                                  widthFactor: frac,
                                  child: Container(
                                    height: 3,
                                    decoration: BoxDecoration(
                                      color: fg,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment(frac * 2 - 1, 0),
                                  child: Container(
                                    width: 11,
                                    height: 11,
                                    decoration: BoxDecoration(
                                      color: fg,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 7),
                  GestureDetector(
                    key: const ValueKey('voicePlaybackSpeed'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _voice.cycleSpeed,
                    child: Text(
                      _voice.speed == 1
                          ? timeText
                          : '${_voice.speed.toStringAsFixed(_voice.speed == 1.5 ? 1 : 0)}×',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: _voice.speed == 1
                            ? FontWeight.w400
                            : FontWeight.w700,
                        color: outgoing
                            ? _outgoingTextColor.withValues(alpha: 0.9)
                            : c.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              if (voice.transcription.isNotEmpty ||
                  voice.transcriptionPending ||
                  voice.transcriptionError != null ||
                  widget.onTranscribeVoice != null) ...[
                const SizedBox(height: 7),
                GestureDetector(
                  key: const ValueKey('voiceTranscription'),
                  behavior: HitTestBehavior.opaque,
                  onTap: voice.transcriptionPending
                      ? null
                      : () => widget.onTranscribeVoice?.call(message),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppIcon(HeroAppIcons.microphone, size: 15, color: fg),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          voice.transcription.isNotEmpty
                              ? voice.transcription
                              : voice.transcriptionPending
                              ? 'Transcribing…'
                              : voice.transcriptionError ?? 'Transcribe voice',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.25,
                            color: outgoing
                                ? _outgoingTextColor.withValues(alpha: 0.88)
                                : c.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static String _durationString(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  // MARK: - Location

  Widget _locationBubble(MessageLocation location) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LocationDetailView(location: location),
        ),
      ),
      child: Container(
        width: 220,
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: _messageBorderRadius(10),
          border: Border.all(color: c.divider, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (location.title?.isNotEmpty ?? false)
                        ? location.title!
                        : AppStrings.t(AppStringKeys.composerLocation),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: _incomingTextColor,
                    ),
                  ),
                  if (location.address?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 3),
                    Text(
                      location.address!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            _MapThumbnail(
              latitude: location.latitude,
              longitude: location.longitude,
            ),
          ],
        ),
      ),
    );
  }

  // MARK: - File card

  Widget _fileCard(MessageDocument _, bool outgoing) =>
      _fileAlbumCard(<ChatMessage>[message], outgoing);

  Widget _fileAlbumCard(List<ChatMessage> sources, bool outgoing) {
    final c = context.colors;
    ChatMessage? captionSource;
    var caption = '';
    for (final source in sources) {
      if (source.document == null) continue;
      final candidate = _fileCaptionText(source);
      if (candidate.isEmpty) continue;
      captionSource = source;
      caption = candidate;
      break;
    }
    ChatMessage? translationSource = captionSource;
    if (translationSource == null) {
      for (final source in sources) {
        if (_showsTranslationFor(source)) {
          translationSource = source;
          break;
        }
      }
    }
    final singleGif =
        sources.length == 1 && _isGifDocument(sources.single.document!);
    return Container(
      key: ValueKey('messageDocumentAlbumCard-${message.id}'),
      width: 244,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: _messageBorderRadius(6),
        border: Border.all(color: c.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < sources.length; index++) ...[
            if (index > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Container(height: 0.5, color: c.divider),
              ),
            _fileAlbumItem(sources[index]),
          ],
          if (captionSource != null) ...[
            SizedBox(height: sources.length == 1 ? 10 : 2),
            if (!singleGif)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Container(height: 0.5, color: c.divider),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _richTextWidgets(
                  caption,
                  c.textPrimary,
                  c.linkBlue,
                  outgoing,
                  false,
                  captionSource.textEntities,
                ),
              ),
            ),
          ],
          if (translationSource != null &&
              _showsTranslationFor(translationSource)) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: _translationBlock(
                outgoing,
                width: double.infinity,
                source: translationSource,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fileAlbumItem(ChatMessage source) {
    final doc = source.document!;
    final isGif = _isGifDocument(doc);
    final itemKey = GlobalKey();
    return GestureDetector(
      key: ValueKey('messageDocumentAlbumFile-${source.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => FileDetailView(doc: doc))),
      onLongPress: () => _handleGroupedFileLongPress(source, itemKey),
      child: isGif && doc.file != null
          ? SizedBox(
              key: itemKey,
              width: 236,
              height: 180,
              child: TDImage(
                photo: doc.file,
                fit: BoxFit.contain,
                cornerRadius: 4,
                showProgress: true,
              ),
            )
          : Padding(
              key: itemKey,
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc.fileName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            color: _incomingTextColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _byteString(doc.size),
                          style: TextStyle(
                            fontSize: 12,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _fileGlyph(doc.ext),
                ],
              ),
            ),
    );
  }

  void _handleGroupedFileLongPress(ChatMessage source, GlobalKey itemKey) {
    _lastTapAt = null;
    final box = itemKey.currentContext?.findRenderObject() as RenderBox?;
    final bounds = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    widget.onLongPress?.call(source, bounds, MessageActionSource.normal);
  }

  bool _isGifDocument(MessageDocument document) =>
      document.ext.toLowerCase() == 'gif' ||
      document.fileName.toLowerCase().endsWith('.gif');

  String _fileCaptionText(ChatMessage source) {
    final text = source.text;
    return text.trim().isEmpty ? '' : text;
  }

  Widget _fileGlyph(String ext) {
    return SizedBox(
      width: 44,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AppIcon(HeroAppIcons.solidFile, size: 40, color: _fileColor(ext)),
          Positioned(
            bottom: 8,
            child: Text(
              _fileBadge(ext),
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          Positioned(
            right: -2,
            bottom: 2,
            child: Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.brand,
                shape: BoxShape.circle,
                border: Border.all(color: c.card, width: 1.5),
              ),
              child: const AppIcon(
                HeroAppIcons.arrowDown,
                size: 11,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  AppColors get c => context.colors;

  static String _byteString(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var size = bytes / 1024;
    var i = 0;
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(size >= 100 ? 0 : 1)} ${units[i]}';
  }

  static Color _fileColor(String ext) {
    switch (ext) {
      case 'DOC':
      case 'DOCX':
        return const Color(0xFF2B7CD3);
      case 'XLS':
      case 'XLSX':
      case 'CSV':
        return const Color(0xFF21A366);
      case 'PPT':
      case 'PPTX':
        return const Color(0xFFD24726);
      case 'PDF':
        return const Color(0xFFE2453C);
      case 'ZIP':
      case 'RAR':
      case '7Z':
        return const Color(0xFFF4A100);
      default:
        return AppColors.light.textTertiary;
    }
  }

  static String _fileBadge(String ext) {
    switch (ext) {
      case 'DOC':
      case 'DOCX':
        return 'W';
      case 'XLS':
      case 'XLSX':
        return 'X';
      case 'PPT':
      case 'PPTX':
        return 'P';
      case '':
        return 'FILE';
      default:
        return ext.length > 4 ? ext.substring(0, 4) : ext;
    }
  }
}

class _RichDetailsBlock extends StatefulWidget {
  const _RichDetailsBlock({
    required this.initiallyOpen,
    required this.color,
    required this.header,
    required this.child,
  });

  final bool initiallyOpen;
  final Color color;
  final Widget header;
  final Widget child;

  @override
  State<_RichDetailsBlock> createState() => _RichDetailsBlockState();
}

class _RichDetailsBlockState extends State<_RichDetailsBlock> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: widget.color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Expanded(child: widget.header),
                  const SizedBox(width: 8),
                  AppIcon(
                    _open
                        ? HeroAppIcons.chevronDown
                        : HeroAppIcons.chevronRight,
                    size: 16,
                    color: widget.color,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 9),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}

class _RichSpoiler extends StatefulWidget {
  const _RichSpoiler({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  State<_RichSpoiler> createState() => _RichSpoilerState();
}

class _RichSpoilerState extends State<_RichSpoiler> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (!_revealed)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _revealed = true),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: AppIcon(
                    HeroAppIcons.eye,
                    size: 22,
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Static map preview for a location message. Telegram renders the map tile via
/// getMapThumbnailFile (no marker); we overlay a centre pin.
class _MapThumbnail extends StatefulWidget {
  const _MapThumbnail({
    required this.latitude,
    required this.longitude,
    this.zoom = 16,
    this.height = 120,
  });
  final double latitude;
  final double longitude;
  final int zoom;
  final double height;

  @override
  State<_MapThumbnail> createState() => _MapThumbnailState();
}

class _MapThumbnailState extends State<_MapThumbnail> {
  TdFileRef? _ref;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await TdClient.shared.query({
        '@type': 'getMapThumbnailFile',
        'location': {
          '@type': 'location',
          'latitude': widget.latitude,
          'longitude': widget.longitude,
        },
        'zoom': widget.zoom.clamp(1, 20),
        'width': 220,
        'height': widget.height.round().clamp(40, 1024),
        'scale': 2,
        'chat_id': 0,
      });
      final id = res.integer('id');
      if (mounted && id != null) setState(() => _ref = TdFileRef(id: id));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_ref != null)
            TDImage(photo: _ref, cornerRadius: 0)
          else
            Container(color: c.groupedBackground),
          Center(
            child: AppIcon(
              HeroAppIcons.locationPin,
              size: 32,
              color: AppTheme.brand,
            ),
          ),
        ],
      ),
    );
  }
}

class _LatexView extends StatelessWidget {
  const _LatexView({
    required this.expression,
    required this.style,
    this.display = false,
  });

  final String expression;
  final TextStyle style;
  final bool display;

  @override
  Widget build(BuildContext context) {
    try {
      return Math.tex(
        expression,
        textStyle: style,
        mathStyle: display ? MathStyle.display : MathStyle.text,
        onErrorFallback: (error) => Text(expression, style: style),
      );
    } catch (_) {
      return Text(expression, style: style);
    }
  }
}
