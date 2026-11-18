//
//  message_bubble.dart
//
//  One conversation message, reference-styled. Plain rounded bubbles (no tail).
//  Renders text (with highlighted links), inline images (tap → full-screen
//  viewer), stickers (.tgs Lottie), voice notes, location cards, and document
//  cards. Shows a "+1" quick-repeat badge for a duplicate tail. Swipe the row
//  left to reply. Port of the Swift `MessageBubble`.
//

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox, SelectedContent;
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../call/call_elapsed_text.dart';
import '../../components/app_icons.dart';
import '../../components/document_file_icon.dart';
import '../../components/photo_avatar.dart';
import '../../components/toast.dart';
import '../../components/ui_components.dart';
import '../../media/media_metadata.dart';
import '../../platform/adaptive_platform.dart';
import '../../profile/profile_detail_view.dart';
import '../../settings/sensitive_content_controller.dart';
import '../../settings/translation_controller.dart';
import '../../tdlib/json_helpers.dart';
import '../../tdlib/td_client.dart';
import '../../tdlib/td_models.dart';
import '../../theme/app_theme.dart';
import '../../theme/content_size.dart';
import '../../theme/date_text.dart';
import '../../theme/message_bubble_background.dart';
import '../../theme/message_name_colors.dart';
import '../../theme/telegram_cloud_theme.dart';
import '../../theme/theme_controller.dart';
import '../appearance/chat_appearance_preview.dart';
import '../links_search/link_handler.dart';
import '../media/file_detail_view.dart';
import '../media/inline_video_autoplay.dart';
import '../media/looping_video_view.dart';
import '../media/music_player_controller.dart';
import '../media/voice_audio.dart';
import '../stickers/animated_sticker_view.dart';
import '../stickers/custom_emoji.dart';
import '../stickers/video_sticker_view.dart';
import 'bot_button_presentation.dart';
import 'desktop_message_quote_source.dart';
import 'desktop_message_text_selection.dart';
import 'gift_details_sheet.dart';
import 'gram_transfer_sheet.dart';
import 'location_detail_view.dart';
import 'media_preview_geometry.dart';
import 'media_spoiler.dart';
import 'message_action_menu.dart';
import 'message_direction.dart';
import 'message_gift_card.dart';
import 'message_gram_envelope.dart';
import 'message_reaction_chips.dart';
import 'message_reply_count_badge.dart';
import 'message_special_content.dart';
import 'message_swipe_reply.dart';
import 'message_text_entity_runs.dart';
import 'mobile_message_text_selection.dart';
import 'pangu_spacing.dart';
import 'sensitive_content_reveal_prompt.dart';
import 'stretchable_message_bubble_background.dart';

part 'message_bubble_widgets.dart';
part 'message_bubble_rich_blocks.dart';
part 'message_bubble_text_entities.dart';
part 'message_bubble_media_cards.dart';

typedef ImageGalleryOpenCallback =
    void Function({required List<TdFileRef> items, required int startIndex});

/// Inner padding of an ordinary text message bubble.
const EdgeInsets messageTextBubblePadding = EdgeInsets.symmetric(
  horizontal: 12,
  vertical: 9,
);

/// Corner radius of an ordinary text message bubble.
const double messageTextBubbleRadius = 6;

/// Decoded side, in pixels, of the softened fill around a letterboxed photo.
const int _letterboxFillPx = 12;

/// The widest a message bubble may grow in a conversation lane [layoutWidth]
/// wide: three quarters of the lane, capped on desktop windows.
double messageBubbleMaxWidth(double layoutWidth, [TargetPlatform? platform]) {
  final proportional = math.max(1.0, layoutWidth * 0.75);
  return isDesktopTargetPlatform(platform)
      ? math.min(proportional, 720)
      : proportional;
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.groupedMedia = const <ChatMessage>[],
    this.targetMediaMessageId,
    this.targetMediaKey,
    this.translationDisplayStyle = TranslationDisplayStyle.quote,
    this.showOriginalTranslationMessageIds = const <int>{},
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
    this.mobileTextSelectionAreaKey,
    this.onMobileTextSelectionChanged,
    this.onMobileTextSelectionDisposed,
    this.onDesktopQuoteChanged,
    this.onReply,
    this.onAvatarTap,
    this.onAvatarLongPress,
    this.onOpenReply,
    this.onOpenForwarded,
    this.onTapViaBot,
    this.onOpenImage,
    this.onOpenImageGallery,
    this.onApplyMessageBubble,
    this.onOpenSticker,
    this.onPlayVideo,
    this.onPlayMusic,
    this.onButtonTap,
    this.onBotCommandTap,
    this.onHashtagTap,
    this.onOpenComments,
    this.showCommentAttachment = false,
    this.channelHasLinkedDiscussion = false,
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
    this.messageColors,
    this.hasCustomChatTheme = false,
    this.selected = false,
    this.sensitiveContentController,
  });

  final ChatMessage message;
  final TranslationDisplayStyle translationDisplayStyle;
  final Set<int> showOriginalTranslationMessageIds;

  /// Selected messages take their own bubble fill. Telegram keys this
  /// separately (chat_inBubbleSelected / chat_outBubbleSelected) rather than
  /// tinting the base fill, so a theme can define the state outright.
  final bool selected;

  final List<ChatMessage> groupedMedia;
  final int? targetMediaMessageId;
  final GlobalKey? targetMediaKey;
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
  final GlobalKey<SelectionAreaState>? mobileTextSelectionAreaKey;
  final ValueChanged<SelectedContent?>? onMobileTextSelectionChanged;
  final VoidCallback? onMobileTextSelectionDisposed;
  final DesktopQuoteChanged? onDesktopQuoteChanged;
  final ValueChanged<ChatMessage>? onReply;
  final ValueChanged<ChatMessage>? onAvatarTap;
  final ValueChanged<ChatMessage>? onAvatarLongPress;
  final ValueChanged<int>? onOpenReply;
  final ValueChanged<ChatMessage>? onOpenForwarded;
  final ValueChanged<ChatMessage>? onTapViaBot;
  final ValueChanged<ChatMessage>? onOpenImage;
  final ImageGalleryOpenCallback? onOpenImageGallery;
  final ValueChanged<ChatMessage>? onApplyMessageBubble;
  final ValueChanged<ChatMessage>? onOpenSticker;
  final ValueChanged<ChatMessage>? onPlayVideo;
  final ValueChanged<ChatMessage>? onPlayMusic;
  final void Function(ChatMessage message, MessageButton button)? onButtonTap;
  final ValueChanged<String>? onBotCommandTap;
  final ValueChanged<String>? onHashtagTap;
  final ValueChanged<ChatMessage>? onOpenComments;
  final bool showCommentAttachment;
  final bool channelHasLinkedDiscussion;
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
  final bool isRead;
  final Color? outgoingBubbleColor;
  final Color? outgoingBubbleTextColor;
  final Color? incomingBubbleColor;
  final Color? incomingBubbleTextColor;
  final TelegramMessageColors? messageColors;
  final bool hasCustomChatTheme;
  final SensitiveContentController? sensitiveContentController;

  @override
  Widget build(BuildContext context) =>
      ContentSizeScope(child: _ScopedMessageBubble(bubble: this));
}

class _ScopedMessageBubble extends StatefulWidget {
  const _ScopedMessageBubble({required this.bubble});
  final MessageBubble bubble;

  @override
  State<_ScopedMessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_ScopedMessageBubble>
    with SingleTickerProviderStateMixin {
  void _updateState(VoidCallback fn) => setState(fn);

  final VoicePlayer _voice = VoicePlayer();

  final GlobalKey _bubbleKey = GlobalKey();

  final GlobalKey<SelectionAreaState> _desktopSelectionAreaKey = GlobalKey();

  final List<TapGestureRecognizer> _linkRecognizers = [];

  late final MessageSwipeReplyController _swipe;

  bool _stickerReady = false;

  bool _videoStickerReady = false;

  bool _musicPressed = false;

  bool _showTappedTimestamp = false;

  // Hover feeds nothing but the 10px detail timestamp, so it rides a notifier:
  // a setState here rebuilt the entire bubble on every pointer crossing, and on
  // desktop the cursor crosses a bubble boundary on most scroll frames.
  final ValueNotifier<bool> _hoveringTimestamp = ValueNotifier(false);

  double? _layoutWidth;

  final Set<String> _expandedQuotes = {};

  // Rich block quotes that measured taller than the fold cap. The measurement
  // is exact — the body is laid out at the incoming width — because a block
  // quote carries no expandable flag on the wire.
  final Set<String> _foldableRichQuotes = {};

  // A block quote folds at three lines of its body text. The quote frame's
  // padding sits outside that cap, so a folded rich quote shows the same three
  // lines plus frame as an entity quote does.
  static const int _richQuoteFoldLines = 3;

  static const EdgeInsets _richQuotePadding = EdgeInsets.fromLTRB(10, 7, 8, 7);

  final Set<String> _revealedSpoilers = {};

  // 盘古之白 results for this bubble's texts. A rebuild reuses the spaced text
  // and the very same entity list, so the paragraphs below keep their spans.
  final PanguDisplayMemo _panguSpacing = PanguDisplayMemo();

  bool _showRestrictedContent = false;

  int? _desktopSecondaryPointer;

  Offset? _desktopSecondaryPosition;

  bool _desktopSecondaryHandled = false;

  int _desktopSecondarySequence = 0;

  int? _desktopTouchPointer;

  Offset? _desktopTouchOrigin;

  VelocityTracker? _desktopTouchVelocity;

  Timer? _desktopTouchLongPressTimer;

  bool _desktopTouchHorizontal = false;

  bool _desktopTouchLongPressTriggered = false;

  SensitiveContentController get _sensitiveContentController =>
      widget.bubble.sensitiveContentController ??
      SensitiveContentController.shared;

  bool get _revealsRestrictedContent =>
      _showRestrictedContent ||
      _sensitiveContentController.enabled ||
      (_theme.autoRevealRestrictedMedia && message.hasRestrictedRevealContent);

  /// A long press flips the per-message reveal, so content uncovered by hand can
  /// be masked again. Reveals that come from the account option or from the
  /// auto-reveal preference are not per-message state: there the press belongs
  /// to the ordinary action menu.
  bool get _togglesRestrictedContentOnLongPress =>
      message.hasRestrictedRevealContent &&
      (_showRestrictedContent || !_revealsRestrictedContent);

  Rect? _bubbleBounds() {
    final box = _bubbleKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Widget _mobileSelectableText(Widget child) {
    final key = widget.bubble.mobileTextSelectionAreaKey;
    if (key == null) return child;
    return MobileMessageTextSelectionArea(
      selectionAreaKey: key,
      onSelectionChanged: widget.bubble.onMobileTextSelectionChanged,
      onDisposed: widget.bubble.onMobileTextSelectionDisposed ?? () {},
      child: child,
    );
  }

  Widget _desktopQuoteSource(
    ChatMessage source,
    String text,
    Widget child, {
    List<MessageTextEntity> entities = const [],
  }) {
    // The paragraphs paint the spaced text while a quote range still has to
    // address the stored message, so the selection is mapped back through the
    // very insertions the renderer made.
    final spaced = _displaySpacing(text, entities);
    final selectable = DesktopMessageQuoteSource(
      key: ValueKey((source.id, text)),
      message: source,
      displayedText: text,
      renderedText: spaced.text,
      renderedSpacing: spaced.insertedOffsets,
      onChanged: widget.bubble.onDesktopQuoteChanged,
      child: child,
    );
    if (source.id == message.id ||
        !isDesktopTargetPlatform(Theme.of(context).platform)) {
      return selectable;
    }
    // A grouped-file caption can belong to a message other than the row's
    // first item. Its context menu must address that same quote source.
    return Listener(
      onPointerUp: (event) {
        if (_desktopSecondaryPointer == event.pointer) {
          _handleGroupedFileSecondaryTap(source, event.position);
        }
      },
      child: selectable,
    );
  }

  void _handleLongPress([
    MessageActionSource source = MessageActionSource.normal,
  ]) {
    if (_claimDesktopTouchLongPress(message, source)) return;
    if (_shouldOfferSensitiveContentUnblock) {
      unawaited(_showSensitiveContentUnblockPrompt(anchor: _bubbleBounds()));
      return;
    }
    if (_togglesRestrictedContentOnLongPress) {
      setState(() => _showRestrictedContent = !_showRestrictedContent);
      return;
    }
    widget.bubble.onLongPress?.call(message, _bubbleBounds(), source);
  }

  void _handleSecondaryTapUp(
    TapUpDetails details, [
    MessageActionSource source = MessageActionSource.normal,
  ]) {
    _markDesktopSecondaryHandled();
    _handleSecondaryPress(details.globalPosition, source);
  }

  void _handleDesktopPointerDown(
    PointerDownEvent event, {
    required bool touchGesturesEnabled,
  }) {
    if ((event.buttons & kSecondaryMouseButton) != 0) {
      _desktopSecondarySequence += 1;
      _desktopSecondaryPointer = event.pointer;
      _desktopSecondaryPosition = event.position;
      _desktopSecondaryHandled = false;
    }
    if (!touchGesturesEnabled || event.kind != PointerDeviceKind.touch) return;
    if (_desktopTouchPointer != null) {
      _cancelDesktopTouchGesture();
      return;
    }
    _desktopTouchPointer = event.pointer;
    _desktopTouchOrigin = event.position;
    _desktopTouchVelocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
    _desktopTouchHorizontal = false;
    _desktopTouchLongPressTriggered = false;
    // Let media and file child recognizers reach the normal deadline first so
    // their more specific action source wins. Selectable text has no message
    // callback on desktop, so this fallback then opens the pointer menu.
    _desktopTouchLongPressTimer = Timer(
      kLongPressTimeout + const Duration(milliseconds: 30),
      () => _claimDesktopTouchLongPress(message, MessageActionSource.normal),
    );
  }

  void _handleDesktopPointerMove(PointerMoveEvent event) {
    if (_desktopTouchPointer != event.pointer) return;
    _desktopTouchVelocity?.addPosition(event.timeStamp, event.position);
    final origin = _desktopTouchOrigin;
    if (origin == null || _desktopTouchLongPressTriggered) return;
    final travel = event.position - origin;
    if (!_desktopTouchHorizontal) {
      if (travel.dx.abs() < kTouchSlop && travel.dy.abs() < kTouchSlop) {
        return;
      }
      _desktopTouchLongPressTimer?.cancel();
      _desktopTouchLongPressTimer = null;
      if (travel.dy.abs() >= travel.dx.abs()) {
        _cancelDesktopTouchGesture();
        return;
      }
      _desktopTouchHorizontal = true;
      _swipe.beginDrag();
    }
    _swipe.dragTo(math.min(0, travel.dx));
    _clearDesktopTouchSelection();
  }

  void _handleDesktopPointerUp(PointerUpEvent event) {
    if (_desktopSecondaryPointer == event.pointer) {
      final sequence = _desktopSecondarySequence;
      final position = _desktopSecondaryPosition ?? event.position;
      scheduleMicrotask(() {
        if (!mounted ||
            sequence != _desktopSecondarySequence ||
            _desktopSecondaryPointer != event.pointer) {
          return;
        }
        final handled = _desktopSecondaryHandled;
        _desktopSecondaryPointer = null;
        _desktopSecondaryPosition = null;
        _desktopSecondaryHandled = false;
        if (!handled) _handleSecondaryPress(position);
      });
    }
    if (_desktopTouchPointer != event.pointer) return;
    _desktopTouchLongPressTimer?.cancel();
    _desktopTouchVelocity?.addPosition(event.timeStamp, event.position);
    if (_desktopTouchHorizontal) {
      final velocity = _desktopTouchVelocity?.getVelocity().pixelsPerSecond.dx;
      _swipe.finish(onReply: _replyToThisMessage, primaryVelocity: velocity);
    }
    if (_desktopTouchHorizontal || _desktopTouchLongPressTriggered) {
      _clearDesktopTouchSelection();
    }
    _resetDesktopTouchGesture();
  }

  void _handleDesktopPointerCancel(PointerCancelEvent event) {
    if (_desktopSecondaryPointer == event.pointer) {
      _desktopSecondarySequence += 1;
      _desktopSecondaryPointer = null;
      _desktopSecondaryPosition = null;
      _desktopSecondaryHandled = false;
    }
    if (_desktopTouchPointer == event.pointer) {
      _cancelDesktopTouchGesture();
    }
  }

  bool _claimDesktopTouchLongPress(
    ChatMessage target,
    MessageActionSource source,
  ) {
    final position = _desktopTouchOrigin;
    if (_desktopTouchPointer == null || position == null) return false;
    if (_desktopTouchLongPressTriggered) return true;
    _desktopTouchLongPressTimer?.cancel();
    _desktopTouchLongPressTimer = null;
    _desktopTouchLongPressTriggered = true;
    _clearDesktopTouchSelection();
    if (identical(target, message)) {
      _handleSecondaryPress(position, source);
    } else {
      widget.bubble.onLongPress?.call(
        target,
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        source,
      );
    }
    return true;
  }

  void _clearDesktopTouchSelection() {
    _desktopSelectionAreaKey.currentState?.selectableRegion.clearSelection();
  }

  void _resetDesktopTouchGesture() {
    _desktopTouchLongPressTimer?.cancel();
    _desktopTouchLongPressTimer = null;
    _desktopTouchPointer = null;
    _desktopTouchOrigin = null;
    _desktopTouchVelocity = null;
    _desktopTouchHorizontal = false;
    _desktopTouchLongPressTriggered = false;
  }

  void _cancelDesktopTouchGesture() {
    if (_desktopTouchHorizontal) _swipe.cancel();
    _resetDesktopTouchGesture();
  }

  void _markDesktopSecondaryHandled() {
    if (_desktopSecondaryPointer != null) {
      _desktopSecondaryHandled = true;
    }
  }

  void _handleSecondaryPress(
    Offset position, [
    MessageActionSource source = MessageActionSource.normal,
  ]) {
    if (_shouldOfferSensitiveContentUnblock) {
      unawaited(
        _showSensitiveContentUnblockPrompt(
          anchor: Rect.fromLTWH(position.dx, position.dy, 0, 0),
        ),
      );
      return;
    }
    widget.bubble.onLongPress?.call(
      message,
      Rect.fromLTWH(position.dx, position.dy, 0, 0),
      source,
    );
  }

  bool get _shouldOfferSensitiveContentUnblock {
    if (!message.isContentRestricted || _revealsRestrictedContent) return false;
    return TDParse.isPornographicRestrictionText(
          message.restrictionReasonCode,
        ) ||
        TDParse.isPornographicRestrictionText(message.restrictionReason) ||
        TDParse.isPornographicRestrictionText(message.text);
  }

  Future<void> _showSensitiveContentUnblockPrompt({Rect? anchor}) async {
    final choice = await showSensitiveContentRevealPrompt(
      context,
      anchor: anchor,
    );
    if (!mounted || choice == SensitiveContentRevealChoice.keepOff) return;
    if (choice == SensitiveContentRevealChoice.revealOnce) {
      if (message.hasRestrictedRevealContent) {
        setState(() => _showRestrictedContent = true);
      }
      return;
    }
    try {
      await _sensitiveContentController.setEnabled(true);
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

  void _handleTap(bool alwaysShowTime) {
    if (!alwaysShowTime) {
      setState(() => _showTappedTimestamp = !_showTappedTimestamp);
    }
  }

  void _setTimestampHover(bool hovering) => _hoveringTimestamp.value = hovering;

  ChatMessage get message => widget.bubble.message;

  // Theme state resolved once per build by [_resolveTheme]. The colour helpers
  // below are read dozens of times while one bubble builds, and each read used
  // to run its own context.watch + Theme.of chain for the same answer.
  late ThemeController _theme;

  late AppColors _colors;

  late Brightness _brightness;

  late MessageBubbleBackgroundSpec _bubbleBackgroundStyle;

  late bool _showsMessageBubbleSurface;

  late TelegramCloudTheme? _activeCloudTheme;

  late TelegramMessageColors? _messageColors;

  void _resolveTheme() {
    _theme = context.watch<ThemeController>();
    _colors = context.colors;
    _brightness = Theme.of(context).brightness;
    _bubbleBackgroundStyle = _theme.effectiveMessageBubbleBackgroundSpecFor(
      outgoing: message.isOutgoing,
    );
    _showsMessageBubbleSurface = _theme.shouldRenderMessageBubbleSurface(
      outgoing: message.isOutgoing,
      brightness: _brightness,
      hasCustomChatTheme: widget.bubble.hasCustomChatTheme,
    );
    _activeCloudTheme = _theme.themingEnabled
        ? _theme.cloudThemeFor(_brightness)
        : null;
    _messageColors =
        !_showsMessageBubbleSurface ||
            !_theme.themingEnabled ||
            _usesDecorativeBubbleBackground
        ? null
        : widget.bubble.messageColors ?? _activeCloudTheme?.messageColors;
  }

  bool get _usesDecorativeBubbleBackground =>
      _showsMessageBubbleSurface && _bubbleBackgroundStyle.isDecorative;

  Color get _outgoingBubbleColor {
    if (!_showsMessageBubbleSurface) return _colors.card;
    final base =
        _bubbleBackgroundStyle.backgroundColor ??
        widget.bubble.outgoingBubbleColor ??
        _activeCloudTheme?.outgoingColor ??
        AppTheme.bubbleOutgoing;
    if (!widget.bubble.selected) return base;
    return _activeCloudTheme?.outgoingSelectedColor ?? _selectionWash(base);
  }

  /// Fallback for a theme that names no selected key. Telegram's own defaults
  /// are a wash over the base fill, and the base here can be a gradient or a
  /// user-picked colour, so there is nothing fixed to store instead.
  Color _selectionWash(Color base) =>
      Color.alphaBlend(_colors.linkBlue.withValues(alpha: 0.22), base);

  Color get _outgoingTextColor {
    if (!_showsMessageBubbleSurface) return _colors.textPrimary;
    if (!_theme.themingEnabled) {
      return AppTheme.bubbleOutgoingText;
    }
    // Last resort is the palette's own outgoing ink, not a measurement of the
    // fill — the fill can be a gradient or a picked colour, and guessing from
    // it is what produced ink that matched no theme.
    return _bubbleBackgroundStyle.foregroundColor ??
        widget.bubble.outgoingBubbleTextColor ??
        _activeCloudTheme?.outgoingTextColor ??
        _colors.bubbleOutgoingText;
  }

  Color get _incomingThemeBubbleColor {
    if (!_showsMessageBubbleSurface) {
      return widget.bubble.selected
          ? _selectionWash(_colors.card)
          : _colors.card;
    }
    final base =
        widget.bubble.incomingBubbleColor ??
        _activeCloudTheme?.incomingColor ??
        _colors.bubbleIncoming;
    if (!widget.bubble.selected) return base;
    return _activeCloudTheme?.incomingSelectedColor ?? _selectionWash(base);
  }

  Color get _incomingBubbleColor {
    if (!_showsMessageBubbleSurface) return _colors.card;
    return _bubbleBackgroundStyle.backgroundColor ?? _incomingThemeBubbleColor;
  }

  Color get _incomingTextColor {
    if (!_showsMessageBubbleSurface) return _colors.textPrimary;
    return _bubbleBackgroundStyle.foregroundColor ??
        widget.bubble.incomingBubbleTextColor ??
        _activeCloudTheme?.incomingTextColor ??
        _colors.bubbleIncomingText;
  }

  double get _messageAccentFillOpacity =>
      _brightness == Brightness.dark ? 0.12 : 0.10;

  Color _messageAccentFill(Color color) =>
      color.withValues(alpha: color.a * _messageAccentFillOpacity);

  Color _messageLinkColor(bool outgoing) {
    if (!_theme.themingEnabled) {
      return _disabledThemeLinkStyle(outgoing).color;
    }
    if (!_showsMessageBubbleSurface) return _colors.linkBlue;
    final base = outgoing ? _outgoingTextColor : _incomingTextColor;
    if (_usesDecorativeBubbleBackground) return base;
    final colors = _messageColors;
    if (colors == null) {
      return outgoing ? _outgoingTextColor : _colors.linkBlue;
    }
    return outgoing ? colors.outgoingLink : colors.incomingLink;
  }

  ReadableLinkStyle _disabledThemeLinkStyle(bool outgoing) => readableLinkStyle(
    background: outgoing ? _outgoingBubbleColor : _incomingBubbleColor,
    body: outgoing ? _outgoingTextColor : _incomingTextColor,
    preferred: _colors.linkBlue,
  );

  bool _underlinesLinks(Color body, Color link) => _theme.themingEnabled
      ? linkNeedsUnderline(body: body, link: link)
      : _disabledThemeLinkStyle(message.isOutgoing).underline;

  Color _messageQuoteColor(bool outgoing) {
    if (_usesDecorativeBubbleBackground) {
      return outgoing ? _outgoingTextColor : _incomingTextColor;
    }
    final colors = _messageColors;
    if (colors == null) return AppTheme.brand;
    return outgoing ? colors.outgoingQuote : colors.incomingQuote;
  }

  Color _messageReplyLineColor(bool outgoing) {
    if (_usesDecorativeBubbleBackground) {
      return outgoing ? _outgoingTextColor : _incomingTextColor;
    }
    final colors = _messageColors;
    if (colors == null) {
      return outgoing ? _outgoingTextColor : AppTheme.brand;
    }
    return outgoing ? colors.outgoingReplyLine : colors.incomingReplyLine;
  }

  Color _messageReplyNameColor(bool outgoing) {
    if (_usesDecorativeBubbleBackground) {
      return outgoing ? _outgoingTextColor : _incomingTextColor;
    }
    final colors = _messageColors;
    if (colors == null) {
      return outgoing ? _outgoingTextColor : _colors.textPrimary;
    }
    return outgoing ? colors.outgoingReplyName : colors.incomingReplyName;
  }

  Color _messageReplyTextColor(bool outgoing) {
    if (_usesDecorativeBubbleBackground) {
      final foreground = outgoing ? _outgoingTextColor : _incomingTextColor;
      return foreground.withValues(alpha: 0.72);
    }
    final colors = _messageColors;
    if (colors == null) {
      return outgoing
          ? _outgoingTextColor.withValues(alpha: 0.72)
          : _colors.textSecondary;
    }
    if (message.replyToImage != null &&
        (message.replyPreviewText?.trim().isEmpty ?? true)) {
      return outgoing
          ? colors.outgoingReplyMediaText
          : colors.incomingReplyMediaText;
    }
    return outgoing ? colors.outgoingReplyText : colors.incomingReplyText;
  }

  Color _messageForwardedNameColor(bool outgoing) {
    if (_usesDecorativeBubbleBackground) {
      return outgoing ? _outgoingTextColor : _incomingTextColor;
    }
    final colors = _messageColors;
    if (colors == null) {
      return outgoing ? _outgoingTextColor : _colors.textSecondary;
    }
    return outgoing
        ? colors.outgoingForwardedName
        : colors.incomingForwardedName;
  }

  Color _messagePreviewLineColor(bool outgoing) {
    if (_usesDecorativeBubbleBackground) {
      return outgoing ? _outgoingTextColor : _incomingTextColor;
    }
    final colors = _messageColors;
    if (colors == null) return _messageLinkColor(outgoing);
    return outgoing ? colors.outgoingPreviewLine : colors.incomingPreviewLine;
  }

  Color _messageSiteNameColor(bool outgoing) {
    if (_usesDecorativeBubbleBackground) {
      return outgoing ? _outgoingTextColor : _incomingTextColor;
    }
    final colors = _messageColors;
    if (colors == null) return _messageLinkColor(outgoing);
    return outgoing ? colors.outgoingSiteName : colors.incomingSiteName;
  }

  Color _messageTimeColor(bool outgoing) {
    if (_usesDecorativeBubbleBackground) {
      final foreground = outgoing ? _outgoingTextColor : _incomingTextColor;
      return foreground.withValues(alpha: 0.65);
    }
    final colors = _messageColors;
    if (colors == null) {
      return outgoing
          ? _outgoingTextColor.withValues(alpha: 0.65)
          : _colors.textTertiary;
    }
    return outgoing ? colors.outgoingTime : colors.incomingTime;
  }

  bool get _showsAttachedComments =>
      !message.isContentRestricted &&
      widget.bubble.showCommentAttachment &&
      (message.hasCommentThread ||
          message.commentCount > 0 ||
          (widget.bubble.channelHasLinkedDiscussion && !message.isService));

  bool get _showsCompactReplyCount =>
      !message.isContentRestricted &&
      widget.bubble.isGroup &&
      !widget.bubble.showCommentAttachment &&
      message.commentCount > 0;

  BorderRadius _messageBorderRadius(double radius) =>
      BorderRadius.circular(radius);

  Widget _bubbleBackground({
    Key? key,
    required bool outgoing,
    required Widget child,
    required EdgeInsetsGeometry padding,
    required BorderRadius borderRadius,
    BoxConstraints constraints = const BoxConstraints(),
    bool containsAttachedComments = false,
  }) {
    if (!_showsMessageBubbleSurface) {
      return Container(
        key: key,
        constraints: constraints,
        padding: padding,
        child: child,
      );
    }
    // When a comment action is present, the outer wrapper owns the only
    // rounded/background surface. Inner message content keeps its normal
    // padding but does not paint a second sliced image or rounded rectangle.
    if (_showsAttachedComments && !containsAttachedComments) {
      return Container(
        key: key,
        constraints: constraints,
        padding: _usesDecorativeBubbleBackground
            ? _bubbleBackgroundStyle.contentPadding
            : padding,
        child: child,
      );
    }
    return StretchableMessageBubbleBackground(
      key: key,
      background: _bubbleBackgroundStyle,
      fallbackColor: outgoing ? _outgoingBubbleColor : _incomingBubbleColor,
      fallbackBorderRadius: borderRadius,
      fallbackPadding: padding,
      fallbackBorder: outgoing || _messageColors != null
          ? null
          : Border.all(color: _colors.divider, width: 0.5),
      constraints: constraints,
      child: child,
    );
  }

  double _bubbleMaxWidth() =>
      messageBubbleMaxWidth(_layoutWidth ?? MediaQuery.sizeOf(context).width);

  double _mediaMaxWidth() =>
      math.min(_bubbleMaxWidth(), telegramDesktopMediaPreviewMaxSide);

  double _chatFontSize(double base) => _theme.chatTextSize(base);

  @override
  void initState() {
    super.initState();
    _sensitiveContentController.addListener(_handleSensitiveContentChange);
    _swipe = MessageSwipeReplyController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant _ScopedMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A bubble is stateful per list slot, not per message: a list rebinds the
    // same State object to another message as rows move. The manual reveal is
    // the reader's confirmation for ONE message, so it must not follow the
    // slot onto a message that was never confirmed.
    if (oldWidget.bubble.message.id != widget.bubble.message.id ||
        oldWidget.bubble.message.chatId != widget.bubble.message.chatId) {
      _showRestrictedContent = false;
    }
    final oldController =
        oldWidget.bubble.sensitiveContentController ??
        SensitiveContentController.shared;
    if (identical(oldController, _sensitiveContentController)) return;
    oldController.removeListener(_handleSensitiveContentChange);
    _sensitiveContentController.addListener(_handleSensitiveContentChange);
  }

  void _handleSensitiveContentChange() {
    if (mounted && message.isContentRestricted) setState(() {});
  }

  @override
  void dispose() {
    _desktopTouchLongPressTimer?.cancel();
    _sensitiveContentController.removeListener(_handleSensitiveContentChange);
    _swipe.dispose();
    _hoveringTimestamp.dispose();
    _voice.dispose();
    for (final r in _linkRecognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (message.isService) return const SizedBox.shrink();
    _resolveTheme();
    final outgoing = isOutgoingTranscriptMessage(message, widget.bubble.meId);
    final mobileSelectionArmed =
        widget.bubble.mobileTextSelectionAreaKey != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        _layoutWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        // The swipe claims the whole row rather than the bubble, so the drag
        // can start on the empty space beside a short bubble or on the avatar.
        // A desktop mouse drag selects text instead, and the desktop touch path
        // drives the same controller from raw pointers.
        return buildMessageSwipeReply(
          context: context,
          controller: _swipe,
          swipeEnabled: !mobileSelectionArmed,
          onReply: widget.bubble.onReply == null ? null : _replyToThisMessage,
          child: _row(outgoing),
        );
      },
    );
  }

  void _replyToThisMessage() => widget.bubble.onReply?.call(message);

  bool _supportsDesktopTouchGestures(TargetPlatform platform) =>
      platform == TargetPlatform.windows || platform == TargetPlatform.linux;

  Widget _row(bool outgoing) {
    final alwaysShowTime =
        widget.bubble.forceShowTimestamp || _theme.alwaysShowMessageTime;
    final showDetailTime = alwaysShowTime || _showTappedTimestamp;
    final timeInSenderHeader =
        widget.bubble.isGroup && !outgoing && message.senderName != null;
    final platform = Theme.of(context).platform;
    final desktopInteraction = isDesktopTargetPlatform(platform);
    final desktopTouchInteraction = _supportsDesktopTouchGestures(platform);
    final contentBody = _contentBody(outgoing);
    final body = GestureDetector(
      key: _bubbleKey,
      behavior: HitTestBehavior.opaque,
      onTap: () => _handleTap(alwaysShowTime),
      onLongPress:
          !desktopTouchInteraction &&
              widget.bubble.mobileTextSelectionAreaKey == null
          ? _handleLongPress
          : null,
      onSecondaryTapUp: desktopInteraction ? null : _handleSecondaryTapUp,
      child: KeyedSubtree(
        key: ValueKey('messageTapTarget-${message.id}'),
        child: desktopInteraction
            ? Listener(
                onPointerDown: (event) => _handleDesktopPointerDown(
                  event,
                  touchGesturesEnabled: desktopTouchInteraction,
                ),
                onPointerMove: _handleDesktopPointerMove,
                onPointerUp: _handleDesktopPointerUp,
                onPointerCancel: _handleDesktopPointerCancel,
                child: KeyedSubtree(
                  key: ValueKey('messageTextSelectionArea-${message.id}'),
                  child: DesktopMessageTextSelectionArea(
                    selectionAreaKey: _desktopSelectionAreaKey,
                    child: contentBody,
                  ),
                ),
              )
            : contentBody,
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
                MessageReactionChips(
                  message: message,
                  outgoing: outgoing,
                  onToggle: widget.bubble.onToggleReaction,
                  onShowUsers: widget.bubble.onShowReactionUsers,
                ),
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
    final messageRow = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: outgoing
            ? [
                Expanded(
                  child: widget.bubble.showRepeat
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
                      // Without a badge the Row and Flexible are pure overhead:
                      // the Align already fills the Expanded and puts the
                      // bubble on the right.
                      : Align(alignment: Alignment.centerRight, child: content),
                ),
                const SizedBox(width: 8),
                _avatarTapTarget(
                  PhotoAvatar(
                    // Resolved here rather than up front: an incoming message
                    // never needs it, and the fallback runs a localisation
                    // lookup.
                    title: message.senderIsChat
                        ? (message.senderName ?? widget.bubble.meName)
                        : widget.bubble.meName.l10n(context),
                    photo: message.senderIsChat
                        ? message.senderPhoto
                        : widget.bubble.mePhoto,
                    size: 38 * ContentSizeScope.of(context).appScale,
                  ),
                  withLongPress: false,
                ),
              ]
            : [
                _avatarTapTarget(
                  PhotoAvatar(
                    title: widget.bubble.isGroup
                        ? (message.senderName ?? widget.bubble.peerTitle)
                        : widget.bubble.peerTitle,
                    photo: widget.bubble.isGroup
                        ? message.senderPhoto
                        : widget.bubble.peerPhoto,
                    size: 38 * ContentSizeScope.of(context).appScale,
                    isDeleted: widget.bubble.isGroup && message.senderIsDeleted,
                  ),
                  withLongPress: true,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.bubble.isGroup && message.senderName != null)
                        _senderHeader(showDetailTime: showDetailTime),
                      // The badge Row is a no-op wrapper without a badge, and
                      // the Column already left-aligns the bubble.
                      if (widget.bubble.showRepeat)
                        Row(
                          children: [
                            Flexible(child: content),
                            const SizedBox(width: 6),
                            _repeatBadge(),
                          ],
                        )
                      else
                        content,
                    ],
                  ),
                ),
              ],
      ),
    );
    // The Stack and the Positioned stay put whatever the timestamp does: a tap
    // toggles _showTappedTimestamp and a late sender name flips
    // timeInSenderHeader, and dropping either wrapper would re-parent the whole
    // bubble and re-inflate every child element (spoilers, inline video, map
    // thumbnails). Hover therefore only ever swaps the Positioned's child.
    return MouseRegion(
      onEnter: (_) => _setTimestampHover(true),
      onExit: (_) => _setTimestampHover(false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          messageRow,
          if (!timeInSenderHeader)
            _detailTimestampOverlay(
              outgoing,
              showDetailTime
                  ? IgnorePointer(child: _messageDetailTimestamp())
                  : ValueListenableBuilder<bool>(
                      valueListenable: _hoveringTimestamp,
                      builder: (context, hovering, _) => hovering
                          ? IgnorePointer(child: _messageDetailTimestamp())
                          : const SizedBox.shrink(),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _detailTimestampOverlay(bool outgoing, Widget child) => Positioned(
    left: outgoing ? null : 58,
    right: outgoing ? 58 : null,
    bottom: -5,
    child: child,
  );

  /// Only an incoming group message reads any of this — a 1:1 chat used to pay
  /// for the name-colour resolution and the role switch on every message.
  Widget _senderHeader({required bool showDetailTime}) {
    final theme = _theme;
    final showMemberTags = theme.showMemberTags;
    final showSenderRole = switch (message.senderRole) {
      null => false,
      MemberRole.member =>
        theme.showPlainMemberRoleTags ||
            (showMemberTags &&
                (message.senderTitle?.trim().isNotEmpty ?? false)),
      _ => true,
    };
    final cloudTheme = theme.cloudThemeFor(_brightness);
    final senderNameColor = messageNameColorForSender(
      theme: cloudTheme,
      accentColorId: message.senderAccentColorId,
      showNameColors: theme.chatNameColorAudience.shows(
        isPremium: message.senderIsPremium,
      ),
      nameColorsDisabledFallback:
          cloudTheme?.senderNameColor ?? _colors.linkBlue,
    );
    final showStatus =
        theme.chatStatusEmojiMode.visible && message.senderEmojiStatusId != 0;
    final senderTitle = message.senderTitle?.trim();
    return Padding(
      key: ValueKey('messageSenderHeader-${message.id}'),
      padding: const EdgeInsets.only(left: 4, bottom: 3),
      child: Row(
        children: [
          Flexible(
            child: SenderIdentityPills(
              readabilityMode: theme.senderNameReadabilityMode,
              bubbleColor: _incomingBubbleColor,
              textColor: _incomingTextColor,
              name: message.senderName!,
              nameStyle: TextStyle(
                fontSize: 12,
                color: senderNameColor,
                fontWeight: FontWeight.w500,
              ),
              role: showSenderRole ? message.senderRole : null,
              roleTitle: showSenderRole && showMemberTags ? senderTitle : null,
              roleAfterName: isDesktopTargetPlatform(),
              trailing: showStatus
                  ? StatusEmojiView(
                      id: message.senderEmojiStatusId,
                      // The name beside it scales with the content text size
                      // (the app setting and the OS text size); the status
                      // emoji should grow with it instead of staying at a
                      // fixed pixel size.
                      size: MediaQuery.textScalerOf(context).scale(14),
                      color: senderNameColor,
                      animate: theme.chatStatusEmojiMode.animate,
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 5),
          SizedBox(
            width: 96,
            height: 14,
            child: showDetailTime
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: _messageDetailTimestamp(),
                  )
                : ValueListenableBuilder<bool>(
                    valueListenable: _hoveringTimestamp,
                    builder: (context, hovering, _) => hovering
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: _messageDetailTimestamp(),
                          )
                        : const SizedBox.shrink(),
                  ),
          ),
        ],
      ),
    );
  }

  /// The avatar only needs a recognizer when a caller actually wants the taps;
  /// previews and tests pass neither.
  Widget _avatarTapTarget(Widget avatar, {required bool withLongPress}) {
    final onTap = widget.bubble.onAvatarTap;
    final onLongPress = withLongPress ? widget.bubble.onAvatarLongPress : null;
    if (onTap == null && onLongPress == null) return avatar;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null ? null : () => onTap(message),
      onLongPress: onLongPress == null ? null : () => onLongPress(message),
      child: avatar,
    );
  }

  Widget _messageDetailTimestamp() => Text(
    DateText.messageDetailLabel(message.date),
    key: const ValueKey('messageTappedTimestamp'),
    maxLines: 1,
    textScaler: TextScaler.noScaling,
    style: TextStyle(fontSize: 10, height: 1.2, color: _colors.textTertiary),
  );

  Widget _repeatBadge() => GestureDetector(
    key: const ValueKey('messageRepeatBadge'),
    onTap: widget.bubble.onRepeat,
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
    // Every build allocates a fresh recognizer per link span. Drain them here,
    // once per build, instead of inside _textBubble: the grouped-caption and
    // file-album paths never reach it and used to grow the list until dispose.
    for (final r in _linkRecognizers) {
      r.dispose();
    }
    _linkRecognizers.clear();
    late final Widget body;
    if (message.isContentRestricted && !_revealsRestrictedContent) {
      body = _textBubble(message.text, outgoing);
      return _withCommentsOnly(_withFloatingMeta(body, outgoing), outgoing);
    }
    if (message.isCall) {
      body = _callBubble(outgoing);
      return _withCommentsOnly(_withFloatingMeta(body, outgoing), outgoing);
    }
    // Only the card-shaped contents below read these; text, media, sticker and
    // voice messages would otherwise resolve three colour chains and drop them.
    late final specialBackground = outgoing
        ? _outgoingBubbleColor
        : _incomingBubbleColor;
    late final specialForeground = outgoing
        ? _outgoingTextColor
        : _incomingTextColor;
    late final specialSecondary = specialForeground.withValues(alpha: 0.68);
    if (message.contact != null) {
      body = MessageContactCardContent(
        contact: message.contact!,
        background: specialBackground,
        foreground: specialForeground,
        secondary: specialSecondary,
        borderRadius: _messageBorderRadius(9),
        onOpen: () => widget.bubble.onOpenContact?.call(message),
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
            : (index) => widget.bubble.onVotePoll?.call(message, index),
        onStop: message.isOutgoing && !message.poll!.isClosed
            ? () => widget.bubble.onStopPoll?.call(message)
            : null,
        onAddOption: message.poll!.canAddOption
            ? () => widget.bubble.onAddPollOption?.call(message)
            : null,
        onShowResults: message.poll!.canGetVoters
            ? () => widget.bubble.onShowPollResults?.call(message)
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
            ? (task) => widget.bubble.onToggleChecklistTask?.call(message, task)
            : null,
        onAddTask: message.checklist!.canAddTasks
            ? () => widget.bubble.onAddChecklistTask?.call(message)
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
        onOpen: () => widget.bubble.onOpenStory?.call(message),
      );
      return _withCommentsOnly(_withFloatingMeta(body, outgoing), outgoing);
    }
    if (message.gift case final gift?) {
      final incomingToMe = gift.isIncomingToMe(
        outgoing: outgoing,
        meId: widget.bubble.meId,
      );
      body = MessageGiftCard(
        key: ValueKey('messageGiftCard-${message.id}'),
        gift: gift,
        incomingToMe: incomingToMe,
        maxWidth: _bubbleMaxWidth(),
        borderRadius: _messageBorderRadius(9),
        meta: _giftFooterMeta(outgoing),
        onTap: () => _openGift(gift, incomingToMe),
      );
      return _withCommentsOnly(
        _withFloatingMeta(body, outgoing, meta: false),
        outgoing,
      );
    }
    if (message.gramTransfer case final transfer?) {
      final state = transfer.state(
        messageOutgoing: outgoing,
        isSending: message.isSending,
      );
      final sender = _gramTransferSender(transfer, outgoing);
      body = MessageGramEnvelope(
        key: ValueKey('messageGramEnvelope-${message.id}'),
        transfer: transfer,
        state: state,
        sender: sender,
        maxWidth: _bubbleMaxWidth(),
        borderRadius: _messageBorderRadius(9),
        meta: _gramFooterMeta(outgoing, state),
        onTap: () => _openGramTransfer(transfer, state, outgoing, sender),
      );
      return _withCommentsOnly(
        _withFloatingMeta(body, outgoing, meta: false),
        outgoing,
      );
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
    final grouped = widget.bubble.groupedMedia;
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
        widget.bubble.onTranscribeVoice != null;
    final transcriptionColor = message.isOutgoing
        ? _outgoingTextColor.withValues(alpha: 0.88)
        : _colors.textSecondary;
    final inline = _autoplaysVideoInline && message.video != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          key: const ValueKey('messageVideoNote'),
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.bubble.onPlayVideo?.call(message),
          child: SizedBox(
            width: size,
            height: size,
            child: ClipOval(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (inline)
                    LoopingVideoView(
                      key: ValueKey('message-inline-video-note-${message.id}'),
                      file: message.video!,
                      fallback: message.image,
                      fit: BoxFit.cover,
                      showDownloadProgress: true,
                    )
                  else if (message.image != null)
                    TDImage(
                      photo: message.image,
                      cornerRadius: 0,
                      cacheWidth: _cachePx(size),
                      cacheHeight: _cachePx(size),
                    )
                  else
                    ColoredBox(color: AppTheme.brand.withValues(alpha: 0.16)),
                  if (!inline)
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
                          borderRadius: BorderRadius.circular(
                            AppRadius.control,
                          ),
                        ),
                        child: Text(
                          formatCallDuration(duration),
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
                : () => widget.bubble.onTranscribeVoice?.call(message),
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
    if (message.isContentRestricted && _revealsRestrictedContent) {
      return message.restrictedContentText ?? '';
    }
    return message.text;
  }

  List<MessageTextEntity> get _activeTextEntities {
    if (message.isContentRestricted && _revealsRestrictedContent) {
      return message.restrictedContentTextEntities;
    }
    if (message.isContentRestricted) return const [];
    return message.textEntities;
  }

  List<RichMessageBlock> get _activeRichBlocks {
    if (message.isContentRestricted && !_revealsRestrictedContent) {
      return const [];
    }
    return message.richBlocks;
  }

  MessageLinkPreview? get _activeLinkPreview {
    if (message.isContentRestricted && !_revealsRestrictedContent) return null;
    return message.linkPreview;
  }

  /// [meta] false leaves the delivery mark out, for content that draws it
  /// itself; the compact reply count still floats over it.
  Widget _withFloatingMeta(Widget child, bool outgoing, {bool meta = true}) {
    final showReplies = _showsCompactReplyCount;
    final showMeta = meta && (message.isEdited || outgoing);
    final show = showMeta || showReplies;
    if (!show) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (showReplies)
          Padding(padding: const EdgeInsets.only(bottom: 19), child: child)
        else
          child,
        Positioned(
          right: 2,
          bottom: showReplies ? 0 : 2,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showReplies)
                MessageReplyCountBadge(
                  key: ValueKey('messageCompactReplies-${message.id}'),
                  count: message.commentCount,
                  foreground: outgoing
                      ? _outgoingTextColor.withValues(alpha: 0.78)
                      : _colors.textSecondary,
                  background: outgoing
                      ? _outgoingBubbleColor.withValues(alpha: 0.82)
                      : _colors.card.withValues(alpha: 0.82),
                  onTap: widget.bubble.onOpenComments == null
                      ? null
                      : () => widget.bubble.onOpenComments?.call(message),
                ),
              if (showReplies && showMeta) const SizedBox(width: 4),
              if (showMeta) _floatingMeta(outgoing),
            ],
          ),
        ),
      ],
    );
  }

  Widget _floatingMeta(bool outgoing) {
    final usesMediaOverlayColor =
        message.animatedSticker != null ||
        message.videoSticker != null ||
        message.isDice ||
        (message.stickerFileId != null && message.image != null) ||
        ((message.video != null || message.image != null) &&
            (_caption()?.trim().isEmpty ?? true));
    final faint = _messageColors != null && !usesMediaOverlayColor
        ? _messageTimeColor(outgoing)
        : outgoing
        ? _outgoingTextColor.withValues(alpha: 0.72)
        : _colors.textTertiary;
    final content = Padding(
      padding: outgoing
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      // One glyph wide either way, so it needs no flex row to hold it.
      child: message.isEdited
          ? AppIcon(
              HeroAppIcons.penToSquare,
              key: const ValueKey('messageDeliveryEdited'),
              size: 10,
              color: faint,
            )
          : outgoing
          ? _deliveryTick()
          : const SizedBox.shrink(),
    );
    return IgnorePointer(
      child: outgoing
          ? content
          : DecoratedBox(
              decoration: BoxDecoration(
                color: _colors.card.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: content,
            ),
    );
  }

  /// The in-flight spinner is the only delivery state that needs a ticker, so
  /// the settled tick gets a plain painter instead of an AnimationController
  /// per outgoing bubble.
  Widget _deliveryTick({
    Color? sentColor,
    Color? pendingColor,
    Color readColor = AppTheme.readMark,
  }) {
    if (message.isSending && !message.isSendAcknowledged) {
      return _MessageDeliveryIndicator(
        pendingColor: pendingColor ?? _outgoingTextColor,
        size: 10,
      );
    }
    return _MessageDeliverySettled(
      isRead: widget.bubble.isRead,
      // The tick is ink on the bubble like the text is, so it follows the same
      // colour. Hardcoding white lost it entirely on a light outgoing fill.
      color: widget.bubble.isRead
          ? readColor
          : (sentColor ?? _outgoingTextColor),
      size: 10,
    );
  }

  /// The delivery mark of the gift card: the
  /// floating meta's glyphs, drawn inside the card's footer in secondary ink
  /// in both directions. A read tick stays green, a darker green on a light
  /// footer. Null when the message shows no meta.
  Widget? _giftFooterMeta(bool outgoing) {
    if (!message.isEdited && !outgoing) return null;
    final ink = _colors.textSecondary;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: message.isEdited
          ? AppIcon(
              HeroAppIcons.penToSquare,
              key: const ValueKey('messageDeliveryEdited'),
              size: 10,
              color: ink,
            )
          : _deliveryTick(
              sentColor: ink,
              pendingColor: ink,
              readColor: dark
                  ? AppTheme.readMark
                  : AppTheme.readMarkOnLightCard,
            ),
    );
  }

  /// Transfers show only their outgoing delivery ring, using the coordinated
  /// footer palette. A pending transfer keeps its spinner until it is sent.
  Widget? _gramFooterMeta(bool outgoing, GramTransferState state) {
    if (!outgoing || state == GramTransferState.failed) return null;
    final palette = GramTransferCardColors.of(context);
    return IgnorePointer(
      child: state == GramTransferState.sending
          ? _MessageDeliveryIndicator(pendingColor: palette.footerInk, size: 10)
          : _MessageDeliverySettled(
              isRead: widget.bubble.isRead,
              color: widget.bubble.isRead ? palette.readInk : palette.footerInk,
              size: 10,
            ),
    );
  }

  /// An upgraded gift opens its existing page; every other gift opens the
  /// read-only gift sheet.
  void _openGift(MessageGift gift, bool incomingToMe) {
    if (gift.opensUpgradedGiftPage) {
      unawaited(
        openInternalLinkType(context, {
          '@type': 'internalLinkTypeUpgradedGift',
          'name': gift.upgradedName,
        }),
      );
      return;
    }
    final bubble = widget.bubble;
    unawaited(
      showGiftDetailsSheet(
        context,
        gift: gift,
        incomingToMe: incomingToMe,
        meId: bubble.meId,
        mePhoto: bubble.mePhoto,
        meName: bubble.meName.l10n(context),
      ),
    );
  }

  /// The current user, as the transfer sheet names them.
  GramTransferParty _gramTransferMe() => GramTransferParty(
    name: AppStringKeys.chatMeLabel.l10n(context),
    photo: widget.bubble.mePhoto,
    avatarTitle: widget.bubble.meName.l10n(context),
  );

  /// The transfer's sender from what the bubble already shows (the current
  /// user for an outgoing transfer, else this message's own sender), else
  /// from the user cache. Null when they still have to be looked up, or are
  /// not a Telegram user.
  GramTransferParty? _gramTransferSender(
    MessageGramTransfer transfer,
    bool outgoing,
  ) {
    if (transfer.isOutgoing(messageOutgoing: outgoing)) {
      return _gramTransferMe();
    }
    final userId = transfer.senderUserId;
    if (userId == 0) return null;
    final bubble = widget.bubble;
    // An incoming transfer that names the current user as its sender came
    // from this message's sender.
    if (userId == bubble.meId ||
        (!message.senderIsChat && message.senderId == userId)) {
      return bubble.isGroup
          ? GramTransferParty(
              name: message.senderName ?? bubble.peerTitle,
              photo: message.senderPhoto,
            )
          : GramTransferParty(name: bubble.peerTitle, photo: bubble.peerPhoto);
    }
    return GramTransferParty.cached(userId);
  }

  void _openGramTransfer(
    MessageGramTransfer transfer,
    GramTransferState state,
    bool outgoing,
    GramTransferParty? sender,
  ) {
    final bubble = widget.bubble;
    unawaited(
      showGramTransferSheet(
        context,
        transfer: transfer,
        state: state,
        outgoing: transfer.isOutgoing(messageOutgoing: outgoing),
        date: message.date,
        me: _gramTransferMe(),
        meId: bubble.meId,
        sender: sender,
        // In a private chat the other side is the chat's peer.
        chatPeer: bubble.isGroup
            ? null
            : GramTransferParty(
                name: bubble.peerTitle,
                photo: bubble.peerPhoto,
              ),
      ),
    );
  }

  Widget _stickerTap(Widget child) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => widget.bubble.onOpenSticker?.call(message),
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
    final suggestedPost = showSuggestedPost
        ? MessageSuggestedPostStatusContent(
            info: message.suggestedPostInfo!,
            background: outgoing ? _outgoingBubbleColor : _incomingBubbleColor,
            foreground: foreground,
            secondary: foreground.withValues(alpha: 0.68),
            borderRadius: _messageBorderRadius(9),
          )
        : null;
    if (!showComments) {
      return IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            body,
            if (suggestedPost != null) ...[
              const SizedBox(height: 6),
              suggestedPost,
            ],
          ],
        ),
      );
    }
    return IntrinsicWidth(
      child: _bubbleBackground(
        key: ValueKey('messageCombinedBubble-${message.id}'),
        outgoing: outgoing,
        constraints: BoxConstraints(maxWidth: _bubbleMaxWidth()),
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(AppRadius.card),
        containsAttachedComments: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            body,
            if (suggestedPost != null) ...[
              const SizedBox(height: 6),
              suggestedPost,
            ],
            _commentThreadRow(outgoing),
          ],
        ),
      ),
    );
  }

  Widget _commentThreadRow(bool outgoing) {
    final c = _colors;
    final count = message.commentCount;
    final label = count == 0
        ? AppStrings.t(AppStringKeys.messageLeaveAComment)
        : AppStrings.plural(AppStringKeys.momentsCommentCount, count);
    final fg = outgoing ? _outgoingTextColor : _incomingTextColor;
    final sub = outgoing
        ? _outgoingTextColor.withValues(alpha: 0.72)
        : c.linkBlue;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.bubble.onOpenComments?.call(message),
      child: Container(
        constraints: BoxConstraints(maxWidth: _bubbleMaxWidth()),
        key: ValueKey('messageCommentsAttachment-${message.id}'),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: outgoing
                  ? _outgoingTextColor.withValues(alpha: 0.16)
                  : c.divider.withValues(alpha: 0.7),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            AppIcon(HeroAppIcons.comments, size: 18, color: sub),
            const SizedBox(width: 7),
            Expanded(
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
    final c = _colors;
    final colors = botButtonPalette(
      button.style,
      primary: AppTheme.brand,
      standard: (
        background: !_showsMessageBubbleSurface
            ? c.card
            : outgoing
            ? Colors.white.withValues(alpha: 0.92)
            : _incomingBubbleColor,
        foreground: !_showsMessageBubbleSurface
            ? c.linkBlue
            : outgoing
            ? AppTheme.brand
            : c.linkBlue,
        border: !_showsMessageBubbleSurface
            ? c.divider
            : outgoing
            ? Colors.white.withValues(alpha: 0.65)
            : c.divider,
      ),
    );
    return Material(
      key: ValueKey('message-button-${button.text}'),
      color: colors.background,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => widget.bubble.onButtonTap?.call(message, button),
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: colors.border, width: 0.5),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: botButtonBadgeIcon(button) != null ? 18 : 8,
                ),
                child: BotButtonLabel(
                  button: button,
                  color: colors.foreground,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (botButtonBadgeIcon(button) case final badgeIcon?)
                Positioned(
                  top: 4,
                  right: 5,
                  child: AppIcon(
                    badgeIcon,
                    key: ValueKey('message-button-badge-${button.text}'),
                    size: 11,
                    color: colors.foreground.withValues(alpha: 0.72),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // MARK: - Text bubble

  Widget _diceBubble(bool outgoing) {
    final c = _colors;
    final value = message.diceValue;
    return _bubbleBackground(
      outgoing: outgoing,
      constraints: BoxConstraints(maxWidth: _bubbleMaxWidth()),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 11),
      borderRadius: _messageBorderRadius(10),
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
                  fontWeight: FontWeight.w600,
                  color: outgoing ? _outgoingTextColor : c.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _textBubble(
    String text,
    bool outgoing, {
    bool includeForwardHeader = true,
    bool includeReplyQuote = true,
    ChatMessage? source,
  }) {
    source ??= message;
    final replacesOriginal = _translationReplacesOriginalFor(source);
    final displayText = replacesOriginal ? source.translationText ?? '' : text;
    final baseColor = replacesOriginal
        ? _translatedOnlyTextColor(outgoing)
        : outgoing
        ? _outgoingTextColor
        : _incomingTextColor;
    final linkColor = replacesOriginal
        ? Color.lerp(_messageLinkColor(outgoing), AppTheme.brand, 0.30)!
        : _messageLinkColor(outgoing);
    final displayEntities = replacesOriginal
        ? source.translationEntities
        : _activeTextEntities;
    final displayRichBlocks = replacesOriginal
        ? const <RichMessageBlock>[]
        : _activeRichBlocks;
    final emojiOnly = _isEmojiOnlyText(displayText);
    final textFontSize = emojiOnly ? 34.0 : AppTextSize.messageBody();
    final bubblePadding = emojiOnly
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 7)
        : messageTextBubblePadding;
    final effectivePadding = _usesDecorativeBubbleBackground
        ? _bubbleBackgroundStyle.contentPadding
        : bubblePadding;
    // Preview geometry must use the bubble's content box, not its outer
    // maximum. Otherwise the parent padding clamps only the width while the
    // preview keeps a height calculated for the wider outer box.
    final previewMaxWidth = math.max(
      1.0,
      _bubbleMaxWidth() - effectivePadding.horizontal,
    );
    final selectableParts = <Widget>[
      if (replacesOriginal)
        KeyedSubtree(
          key: const ValueKey('messageTranslatedOnlyText'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: _richTextWidgets(
              displayText,
              baseColor,
              linkColor,
              outgoing,
              false,
              displayEntities,
              textFontSize,
            ),
          ),
        )
      else
        _desktopQuoteSource(
          source,
          displayText,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: _richTextWidgets(
              displayText,
              baseColor,
              linkColor,
              outgoing,
              false,
              displayEntities,
              textFontSize,
            ),
          ),
          entities: displayEntities,
        ),
      if (displayRichBlocks.isNotEmpty) ...[
        if (displayText.isNotEmpty) const SizedBox(height: 8),
        ..._richBlockWidgets(displayRichBlocks, outgoing),
      ],
      if (_showsTranslationBlockFor(source)) ...[
        const SizedBox(height: 7),
        _translationBlock(outgoing, source: source),
      ],
    ];
    final selectableContent = selectableParts.length == 1
        ? selectableParts.first
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: selectableParts,
          );
    final messageSelectableParts = <Widget>[
      if (_activeLinkPreview?.showAboveText ?? false) ...[
        _linkPreviewCard(
          _activeLinkPreview!,
          outgoing,
          maxWidth: previewMaxWidth,
        ),
        if (displayText.isNotEmpty) const SizedBox(height: 6),
      ],
      selectableContent,
      if (_activeLinkPreview != null && !_activeLinkPreview!.showAboveText) ...[
        if (displayText.isNotEmpty || displayRichBlocks.isNotEmpty)
          const SizedBox(height: 7),
        _linkPreviewCard(
          _activeLinkPreview!,
          outgoing,
          maxWidth: previewMaxWidth,
        ),
      ],
    ];
    final messageSelectableContent = messageSelectableParts.length == 1
        ? messageSelectableParts.first
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: messageSelectableParts,
          );
    final parts = <Widget>[
      if (includeForwardHeader && message.hasForwardAttribution) ...[
        _forwardHeader(outgoing),
        const SizedBox(height: 3),
      ],
      if (includeForwardHeader && message.hasViaBotAttribution) ...[
        _viaBotHeader(outgoing),
        const SizedBox(height: 3),
      ],
      if (includeReplyQuote && message.replyPreviewText != null) ...[
        _replyQuote(outgoing),
        const SizedBox(height: 5),
      ],
      _mobileSelectableText(messageSelectableContent),
      if (_showsAiSummary) ...[
        const SizedBox(height: 7),
        _aiSummaryBlock(outgoing),
      ] else if (message.summaryLanguageCode.isNotEmpty &&
          widget.bubble.onSummarizeMessage != null) ...[
        const SizedBox(height: 7),
        GestureDetector(
          key: const ValueKey('messageSummarizeAction'),
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.bubble.onSummarizeMessage?.call(message),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.brand.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.control),
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
    ];
    return _bubbleBackground(
      key: ValueKey('messageTextBubble-${message.id}'),
      outgoing: outgoing,
      constraints: BoxConstraints(maxWidth: _bubbleMaxWidth()),
      padding: bubblePadding,
      borderRadius: _messageBorderRadius(messageTextBubbleRadius),
      // A plain text message is one span block; the column around it would
      // only re-derive the size the child already has.
      child: parts.length == 1
          ? parts.first
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: parts,
            ),
    );
  }

  String? _emojiOnlyKey;

  bool _emojiOnlyValue = false;

  Widget _richButtonRowBlock(RichMessageBlock block, bool outgoing) {
    final alignment = switch (block.horizontalAlignment) {
      'center' => WrapAlignment.center,
      'right' => WrapAlignment.end,
      _ => WrapAlignment.start,
    };
    return SizedBox(
      key: const ValueKey('rich-message-button-row'),
      width: _bubbleMaxWidth(),
      child: Wrap(
        alignment: alignment,
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final button in block.buttons)
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 88, maxWidth: 220),
              child: _buttonCell(button, outgoing),
            ),
        ],
      ),
    );
  }

  Widget _richTextBlock(
    RichMessageBlock block,
    bool outgoing, {
    Color? linkColor,
  }) {
    final c = _colors;
    final base = block.kind == RichMessageBlockKind.footer
        ? c.textSecondary
        : (outgoing ? _outgoingTextColor : _incomingTextColor);
    final link = linkColor ?? _messageLinkColor(outgoing);
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

  Widget _richListBlock(
    RichMessageBlock block,
    bool outgoing, {
    required String blockPath,
  }) {
    final c = _colors;
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
                      blockPath: '$blockPath.item$index',
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _richQuoteContainer(
    RichMessageBlock block,
    bool outgoing, {
    String blockKey = '',
  }) {
    final base = outgoing ? _outgoingTextColor : _incomingTextColor;
    final link = _messageLinkColor(outgoing);
    final quote = _messageColors == null ? base : _messageQuoteColor(outgoing);
    final quoteLink = !outgoing && _messageColors != null ? quote : link;
    final isPullQuote = block.kind == RichMessageBlockKind.pullQuote;
    final body = isPullQuote
        ? _richTextWidgets(block.text, base, quoteLink, outgoing, false, [
            ...block.textEntities,
            if (block.text.isNotEmpty)
              MessageTextEntity(
                offset: 0,
                length: block.text.length,
                type: 'textEntityTypeItalic',
              ),
          ])
        : _richBlockWidgets(
            block.children,
            outgoing,
            textLinkColor: quoteLink,
            blockPath: blockKey,
          );
    final key = 'rich:${message.chatId}:${message.id}:$blockKey';
    // A quote that carries media, a table or a map has no meaningful "three
    // lines": the cap would slice a photo into a sliver. Only a body made of
    // text blocks folds, which is also the only case where the entity quote's
    // behaviour applies.
    bool isTextOnly(RichMessageBlock child) => switch (child.kind) {
      RichMessageBlockKind.paragraph ||
      RichMessageBlockKind.heading ||
      RichMessageBlockKind.preformatted ||
      RichMessageBlockKind.footer ||
      RichMessageBlockKind.thinking ||
      RichMessageBlockKind.math ||
      RichMessageBlockKind.divider ||
      RichMessageBlockKind.anchor => true,
      RichMessageBlockKind.list => child.listItems.every(
        (item) => item.blocks.every(isTextOnly),
      ),
      _ => false,
    };
    final foldable = !isPullQuote && block.children.every(isTextOnly);
    final overflows = foldable && _foldableRichQuotes.contains(key);
    final expanded = !foldable || _expandedQuotes.contains(key);
    final lineHeight = foldable ? _richQuoteLineHeight() : 0.0;
    final content = Container(
      width: double.infinity,
      padding: _richQuotePadding,
      decoration: BoxDecoration(
        color: _messageColors == null
            ? base.withValues(alpha: 0.07)
            : _messageAccentFill(quote),
        border: Border(left: BorderSide(color: quote, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: isPullQuote
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (foldable)
            _QuoteFold(
              maxHeight: _richQuoteFoldLines * lineHeight,
              collapsed: !expanded,
              fadeExtent: lineHeight,
              onOverflowChanged: (overflows) =>
                  _handleRichQuoteOverflow(key, overflows),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: body,
              ),
            )
          else
            ...body,
          if (overflows) ...[
            const SizedBox(height: 4),
            SelectionContainer.disabled(
              child: Text(
                AppStrings.t(
                  expanded
                      ? AppStringKeys.messageBubbleCollapse
                      : AppStringKeys.messageBubbleExpandQuote,
                ),
                style: TextStyle(
                  fontSize: 12,
                  color: quote,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          if (block.caption.isNotEmpty) ...[
            const SizedBox(height: 5),
            ..._richTextWidgets(
              block.caption,
              base.withValues(alpha: 0.78),
              quoteLink,
              outgoing,
              false,
              block.captionEntities,
              13,
            ),
          ],
        ],
      ),
    );
    if (!foldable) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: overflows ? () => _toggleRichQuoteExpanded(key) : null,
      child: content,
    );
  }

  Widget _richDetailsBlock(
    RichMessageBlock block,
    bool outgoing, {
    required String blockPath,
  }) {
    final base = outgoing ? _outgoingTextColor : _incomingTextColor;
    final link = _messageLinkColor(outgoing);
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
        children: _richBlockWidgets(
          block.children,
          outgoing,
          blockPath: '$blockPath.details',
        ),
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
      maxHeight: _richMediaMaxHeight(maxWidth),
      fallback: Size(maxWidth, maxWidth * 0.72),
    );
    Widget media = GestureDetector(
      onTap: () => widget.bubble.onOpenImage?.call(_richMediaMessage(block)),
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
      media = MediaSpoiler(
        identity: (
          TdClient.shared.activeSlot,
          message.chatId,
          message.id,
          image.id,
        ),
        enabled: true,
        miniThumbnail: image.miniThumb,
        width: size.width,
        height: size.height,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: media,
      );
    }
    return _richMediaWithCaption(media, block, outgoing);
  }

  Widget _richVideoBlock(RichMessageBlock block, bool outgoing) {
    final maxWidth = _mediaMaxWidth();
    final size = _fitSize(
      width: block.imageWidth,
      height: block.imageHeight,
      maxWidth: maxWidth,
      maxHeight: _richMediaMaxHeight(maxWidth),
      fallback: Size(maxWidth, maxWidth * 0.62),
    );
    Widget media = GestureDetector(
      onTap: block.video == null
          ? null
          : () => widget.bubble.onPlayVideo?.call(_richMediaMessage(block)),
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: block.image == null
                  ? ColoredBox(color: _colors.searchFill)
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
      media = MediaSpoiler(
        identity: (
          TdClient.shared.activeSlot,
          message.chatId,
          message.id,
          block.video?.id,
        ),
        enabled: true,
        miniThumbnail: block.image?.miniThumb,
        width: size.width,
        height: size.height,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: media,
      );
    }
    return _richMediaWithCaption(media, block, outgoing);
  }

  Widget _richAudioBlock(RichMessageBlock block, bool outgoing) {
    final music = block.music;
    if (music == null) return _richMissingMedia(HeroAppIcons.music, outgoing);
    final synthetic = _richMediaMessage(block);
    final player = MusicPlayerController.shared;
    final canPlay = music.file != null && widget.bubble.onPlayMusic != null;
    return _richMediaWithCaption(
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canPlay ? () => widget.bubble.onPlayMusic!(synthetic) : null,
        child: Container(
          width: math.min(_mediaMaxWidth(), 300),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _colors.card,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: _colors.divider, width: 0.5),
          ),
          child: Row(
            children: [
              // Only the glyph depends on the player, and the player is a
              // global that notifies ~17 times a second while anything plays.
              AnimatedBuilder(
                animation: player,
                builder: (context, _) => AppIcon(
                  player.isActive(music.file) && player.isPlaying
                      ? HeroAppIcons.pause
                      : HeroAppIcons.play,
                  size: 22,
                  color: outgoing ? _outgoingTextColor : AppTheme.brand,
                ),
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
                        color: _colors.textPrimary,
                      ),
                    ),
                    if ((music.performer ?? '').trim().isNotEmpty)
                      Text(
                        music.performer!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: _colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
                color: _colors.card,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(color: _colors.divider, width: 0.5),
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
                      backgroundColor: _colors.divider,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    formatMediaDuration(voice.duration),
                    style: TextStyle(
                      fontSize: 12,
                      color: _colors.textSecondary,
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
    final photoGallery = _richPhotoGallery(media);
    final width = _mediaMaxWidth();
    final cellWidth = media.length == 1 ? width : (width - 4) / 2;
    final collage = Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final (index, child) in media.indexed)
          SizedBox(
            width: cellWidth,
            height: media.length == 1 ? width * 0.7 : cellWidth,
            child: _richMediaThumbnail(
              child,
              outgoing,
              photoGalleryItems: photoGallery.items,
              photoGalleryIndex: photoGallery.indexes[index],
            ),
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
    final photoGallery = _richPhotoGallery(media);
    final width = _mediaMaxWidth();
    final slideshow = SizedBox(
      width: width,
      height: width * 0.68,
      child: PageView.builder(
        itemCount: media.length,
        itemBuilder: (_, index) => Padding(
          padding: EdgeInsets.only(right: index == media.length - 1 ? 0 : 4),
          child: _richMediaThumbnail(
            media[index],
            outgoing,
            photoGalleryItems: photoGallery.items,
            photoGalleryIndex: photoGallery.indexes[index],
          ),
        ),
      ),
    );
    return _richMediaWithCaption(slideshow, block, outgoing);
  }

  Widget _richMediaThumbnail(
    RichMessageBlock block,
    bool outgoing, {
    List<TdFileRef> photoGalleryItems = const [],
    int? photoGalleryIndex,
  }) {
    final child = _richMediaThumbnailContent(
      block,
      outgoing,
      photoGalleryItems: photoGalleryItems,
      photoGalleryIndex: photoGalleryIndex,
    );
    if (!block.hasSpoiler) return child;
    return MediaSpoiler(
      identity: (
        TdClient.shared.activeSlot,
        message.chatId,
        message.id,
        block.image?.id,
        block.video?.id,
      ),
      enabled: true,
      miniThumbnail: block.image?.miniThumb,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: child,
    );
  }

  Widget _richMediaThumbnailContent(
    RichMessageBlock block,
    bool outgoing, {
    List<TdFileRef> photoGalleryItems = const [],
    int? photoGalleryIndex,
  }) {
    if (block.kind == RichMessageBlockKind.photo && block.image != null) {
      return GestureDetector(
        onTap: () {
          final openGallery = widget.bubble.onOpenImageGallery;
          if (block.hasSpoiler && openGallery != null) {
            openGallery(items: [block.image!], startIndex: 0);
            return;
          }
          if (openGallery != null &&
              photoGalleryIndex != null &&
              photoGalleryItems.isNotEmpty) {
            openGallery(
              items: photoGalleryItems,
              startIndex: photoGalleryIndex,
            );
            return;
          }
          widget.bubble.onOpenImage?.call(_richMediaMessage(block));
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: TDImage(photo: block.image),
        ),
      );
    }
    if ((block.kind == RichMessageBlockKind.video ||
            block.kind == RichMessageBlockKind.animation) &&
        block.image != null) {
      return GestureDetector(
        onTap: () => widget.bubble.onPlayVideo?.call(_richMediaMessage(block)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
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
    if (block.caption.trim().isEmpty) {
      return SelectionContainer.disabled(child: media);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SelectionContainer.disabled(child: media),
        const SizedBox(height: 5),
        ..._richTextWidgets(
          block.caption,
          outgoing ? _outgoingTextColor : _incomingTextColor,
          _messageLinkColor(outgoing),
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
        color: _colors.searchFill,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: AppIcon(
        icon,
        size: 24,
        color: outgoing ? _outgoingTextColor : _colors.textSecondary,
      ),
    );
  }

  Widget _richMathBlock(String expression, bool outgoing) {
    final c = _colors;
    final base = outgoing ? _outgoingTextColor : _incomingTextColor;
    final fill = outgoing
        ? _outgoingTextColor.withValues(alpha: 0.14)
        : c.searchFill.withValues(alpha: 0.72);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.md),
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
    final c = _colors;
    final base = outgoing ? _outgoingTextColor : _incomingTextColor;
    final link = _messageLinkColor(outgoing);
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
          borderRadius: BorderRadius.circular(AppRadius.md),
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
            SelectionContainer.disabled(
              child: _MapThumbnail(
                latitude: location.latitude,
                longitude: location.longitude,
                zoom: block.mapZoom,
                height: previewHeight.toDouble(),
              ),
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
    final c = _colors;
    final base = outgoing ? _outgoingTextColor : _incomingTextColor;
    final secondary = outgoing
        ? _outgoingTextColor.withValues(alpha: 0.72)
        : c.textSecondary;
    final link = _messageLinkColor(outgoing);
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
          borderRadius: BorderRadius.circular(AppRadius.md),
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
      verticalAlignment: TableCellVerticalAlignment.intrinsicHeight,
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

  bool get _showsAiSummary =>
      message.aiSummaryLoading ||
      (message.aiSummaryText?.trim().isNotEmpty ?? false);

  Widget _aiSummaryBlock(bool outgoing, {double? width}) {
    final c = _colors;
    final base = outgoing ? _outgoingTextColor : _incomingTextColor;
    final secondary = outgoing
        ? _outgoingTextColor.withValues(alpha: 0.70)
        : c.textSecondary;
    final link = _messageLinkColor(outgoing);
    return Container(
      key: const ValueKey('messageAiSummaryBlock'),
      width: width ?? _bubbleMaxWidth(),
      decoration: BoxDecoration(
        color: outgoing
            ? _outgoingTextColor.withValues(alpha: 0.10)
            : AppTheme.brand.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
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
    final c = _colors;
    final base = outgoing ? _outgoingTextColor : _incomingTextColor;
    final secondary = outgoing
        ? _outgoingTextColor.withValues(alpha: 0.70)
        : c.textSecondary;
    final link = _messageLinkColor(outgoing);
    if (source.isTranslating) {
      return SelectionContainer.disabled(
        child: Container(
          key: const ValueKey('messageTranslationBlock'),
          width: width ?? _bubbleMaxWidth(),
          decoration: BoxDecoration(
            color: outgoing
                ? _outgoingTextColor.withValues(alpha: 0.10)
                : c.searchFill.withValues(alpha: 0.80),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border(left: BorderSide(color: secondary, width: 2.5)),
          ),
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
          child: Row(
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
          ),
        ),
      );
    }
    if (widget.bubble.translationDisplayStyle == TranslationDisplayStyle.both) {
      final divider = outgoing
          ? _outgoingTextColor.withValues(alpha: 0.22)
          : c.divider;
      return Container(
        key: const ValueKey('messageTranslationBlock'),
        width: width ?? _bubbleMaxWidth(),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: divider, width: 0.5)),
        ),
        padding: const EdgeInsets.only(top: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: _richTextWidgets(
            source.translationText ?? '',
            base,
            link,
            outgoing,
            false,
            source.translationEntities,
          ),
        ),
      );
    }
    return Container(
      key: const ValueKey('messageTranslationBlock'),
      width: width ?? _bubbleMaxWidth(),
      decoration: BoxDecoration(
        color: outgoing
            ? _outgoingTextColor.withValues(alpha: 0.10)
            : c.searchFill.withValues(alpha: 0.80),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border(left: BorderSide(color: secondary, width: 2.5)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectionContainer.disabled(
            child: Text(
              AppStringKeys.messageActionTranslate.l10n(context),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: secondary,
              ),
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

  Widget _linkPreviewCard(
    MessageLinkPreview preview,
    bool outgoing, {
    required double maxWidth,
  }) {
    final c = _colors;
    final base = outgoing ? _outgoingTextColor : _incomingTextColor;
    final secondary = outgoing
        ? _outgoingTextColor.withValues(alpha: 0.75)
        : c.textSecondary;
    final link = _messageLinkColor(outgoing);
    final previewLine = _messagePreviewLineColor(outgoing);
    const accentWidth = 3.0;
    final media = _linkPreviewMedia(
      preview,
      math.max(1.0, maxWidth - accentWidth),
    );
    Widget mobileSelectionDisabled(Widget child) =>
        widget.bubble.mobileTextSelectionAreaKey == null
        ? child
        : SelectionContainer.disabled(child: child);
    final textChildren = <Widget>[
      if (preview.siteName.isNotEmpty)
        mobileSelectionDisabled(
          Text(
            preview.siteName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _messageSiteNameColor(outgoing),
            ),
          ),
        ),
      if (preview.title.isNotEmpty)
        mobileSelectionDisabled(
          Text(
            preview.title,
            style: TextStyle(
              fontSize: 15,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: base,
            ),
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
        mobileSelectionDisabled(
          Text(
            preview.displayUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: secondary),
          ),
        ),
    ];

    final translucentBackground = _messageColors == null
        ? outgoing
              ? _outgoingTextColor.withValues(alpha: 0.10)
              : c.searchFill.withValues(alpha: 0.85)
        : _messageAccentFill(previewLine);
    // Decorative bubbles may contain ornaments across their stretchable
    // center. Precomposing the preview fill keeps those pixels from showing
    // through the card while retaining the same tint.
    final cardBackground = _usesDecorativeBubbleBackground
        ? Color.alphaBlend(
            translucentBackground,
            outgoing ? _outgoingBubbleColor : _incomingBubbleColor,
          )
        : translucentBackground;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: preview.url.isEmpty ? null : () => openLink(context, preview.url),
      child: Container(
        key: ValueKey('messageLinkPreviewCard-${message.id}'),
        width: maxWidth,
        decoration: BoxDecoration(
          color: cardBackground,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border(
            left: BorderSide(color: previewLine, width: accentWidth),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (media != null && preview.showMediaAboveDescription)
              mobileSelectionDisabled(media),
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
            if (media != null && !preview.showMediaAboveDescription)
              mobileSelectionDisabled(media),
          ],
        ),
      ),
    );
  }

  // MARK: - Music

  Widget _musicCard(MessageMusic music, bool outgoing) {
    final c = _colors;
    final maxWidth = math.min(MediaQuery.sizeOf(context).width * 0.70, 300.0);
    final caption = _caption();
    final performer = (music.performer ?? '').trim();
    final player = MusicPlayerController.shared;
    final canPlay = music.file != null && widget.bubble.onPlayMusic != null;
    final toggle = canPlay ? () => widget.bubble.onPlayMusic!(message) : null;
    // The player notifies ~17 times a second while any track plays, and it is a
    // global singleton — so the card chrome, title and performer stay outside
    // the builders. Only the cover art and the progress row read the position.
    final card = Container(
      width: maxWidth,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: _messageBorderRadius(10),
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
                AnimatedBuilder(
                  animation: player,
                  builder: (context, _) {
                    final active = player.isActive(music.file);
                    return _musicCover(
                      music.cover,
                      loading: active && player.isLoading,
                      playing: active && player.isPlaying,
                      onTap: toggle,
                      pressed: _musicPressed,
                      onTapDown: canPlay
                          ? () => setState(() => _musicPressed = true)
                          : null,
                      onTapEnd: canPlay
                          ? () => setState(() => _musicPressed = false)
                          : null,
                    );
                  },
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 0.5, color: c.divider),
          AnimatedBuilder(
            animation: player,
            builder: (context, _) {
              if (!player.isActive(music.file)) return _musicProviderBar();
              final total = player.total.inMilliseconds > 0
                  ? player.total
                  : Duration(seconds: music.duration);
              final position = player.position;
              final totalMs = math.max(1, total.inMilliseconds);
              final value = (position.inMilliseconds / totalMs).clamp(0.0, 1.0);
              return _musicProgressBar(
                value: value.toDouble(),
                position: position,
                total: total,
                canPlay: canPlay,
                onChanged: player.seekFraction,
                onChangeEnd: player.seekFraction,
              );
            },
          ),
        ],
      ),
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
    final c = _colors;
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
    final c = _colors;
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
              '${formatMediaDuration(position.inSeconds)}/'
              '${total.inSeconds > 0 ? formatMediaDuration(total.inSeconds) : '--:--'}',
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
    final c = _colors;
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
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
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
    final isVideo = message.callIsVideo;
    final connected = message.callDuration > 0;
    final baseColor = outgoing ? _outgoingTextColor : _incomingTextColor;

    String label;
    bool missed = false;
    if (connected) {
      label = AppStrings.t(AppStringKeys.messageBubbleCallDuration, {
        'value1': formatCallDuration(message.callDuration),
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
      onTap: () => widget.bubble.onRedial?.call(isVideo),
      child: _bubbleBackground(
        outgoing: outgoing,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        borderRadius: _messageBorderRadius(6),
        // Call glyph always on the left of the status, both directions.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              isVideo ? HeroAppIcons.video : HeroAppIcons.phone,
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

  /// 转发 attribution shown above forwarded content: `转发自 …`.
  Widget _forwardHeader(bool outgoing) {
    final textColor = _messageForwardedNameColor(outgoing);
    final accent = _usesDecorativeBubbleBackground
        ? textColor
        : _messageColors == null && !outgoing
        ? AppTheme.brand
        : textColor;
    final canOpenOriginal =
        widget.bubble.onOpenForwarded != null &&
        message.forwardFromChatId != null &&
        message.forwardFromMessageId != null &&
        message.forwardFromMessageId! > 0;
    return GestureDetector(
      key: ValueKey('messageForwardHeader-${message.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: canOpenOriginal
          ? () => widget.bubble.onOpenForwarded!.call(message)
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(
            HeroAppIcons.forward,
            size: 11,
            color: accent.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              AppStrings.t(AppStringKeys.messageBubbleForwardedFrom, {
                'value1': message.forwardDisplayName,
              }),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Inline-bot attribution shown above inline-sent content: `via @bot`.
  Widget _viaBotHeader(bool outgoing) {
    final textColor = _messageForwardedNameColor(outgoing);
    return GestureDetector(
      key: ValueKey('messageViaBotHeader-${message.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: widget.bubble.onTapViaBot != null
          ? () => widget.bubble.onTapViaBot!.call(message)
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              AppStrings.t(AppStringKeys.messageBubbleViaBot, {
                'value1': message.viaBotDisplayName,
              }),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 引用 quote block shown above a reply's text.
  Widget _replyQuote(bool outgoing) {
    final labelColor = _messageReplyNameColor(outgoing);
    final faded = _messageReplyTextColor(outgoing);
    final line = _messageReplyLineColor(outgoing);
    final sender = message.replyToSender ?? '';
    final time = DateText.quoteLabel(message.replyToDate ?? 0);
    final targetId = message.replyToMessageId;
    final openOriginal = targetId == null || widget.bubble.onOpenReply == null
        ? null
        : () => widget.bubble.onOpenReply!.call(targetId);
    return GestureDetector(
      key: const ValueKey('messageReplyOpenOriginal'),
      behavior: HitTestBehavior.opaque,
      onTap: openOriginal,
      child: Container(
        key: const ValueKey('messageReplyQuote'),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 9),
        decoration: BoxDecoration(
          color: _replyQuoteBackground(outgoing),
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(AppRadius.control),
            bottomRight: Radius.circular(AppRadius.control),
          ),
          border: _messageColors == null
              ? null
              : Border(left: BorderSide(color: line, width: 3)),
        ),
        child: IgnorePointer(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.replyToImage != null) ...[
                SizedBox(
                  key: const ValueKey('messageReplyMediaPreview'),
                  width: 44,
                  height: 44,
                  child: TDImage(
                    // A 44pt slot: the small photo size is plenty, and it
                    // avoids downloading and decoding the full-size one.
                    photo:
                        message.replyToImage?.thumbnail ?? message.replyToImage,
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (time.isNotEmpty)
                            TextSpan(text: sender.isEmpty ? time : ' $time'),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: labelColor),
                    ),
                    if ((message.replyPreviewText ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _replyPreviewText(faded, outgoing),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 1, 4, 9),
                child: AppArrowUpToLineIcon(
                  key: const ValueKey('messageReplyNavigateUpIcon'),
                  color: faded,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // URLs (group 1), @username mentions (group 2), and #hashtags (group 3).
  // The lookbehind stops email local-parts (user@host), @@ and ## from being
  // matched as mentions/tags.
  static final _linkRegExp = RegExp(
    r'((?:https?:\/\/|www\.|t\.me\/|tg:\/\/)[^\s]+)|(?<![\w@])(@[A-Za-z0-9_]{4,32})|(?<![\w#])(#[A-Za-z0-9_\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]+)',
    caseSensitive: false,
    unicode: true,
  );

  /// The quoted reply's two-line preview, spaced like the body it answers.
  Widget _replyPreviewText(Color faded, bool outgoing) {
    final spaced = _displaySpacing(
      message.replyPreviewText ?? '',
      message.replyPreviewEntities,
    );
    return _richText(
      spaced.text,
      faded,
      faded,
      0,
      spaced.text.length,
      outgoing,
      false,
      maxLines: 2,
      entities: spaced.entities,
      fontSize: 14,
    );
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
    bool bodyLeading = true,
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
      outgoing,
    );
    if (appendMeta) children.add(_metaSpan(outgoing));
    final hasCustomEmoji = (entities ?? message.textEntities).any(
      (e) =>
          !e.isBlockQuote &&
          e.isCustomEmoji &&
          e.customEmojiId != null &&
          e.offset < end &&
          e.end > start,
    );
    // Apply leading to body-sized message runs, including quotes/captions,
    // never to an ancestor subtree. Code WidgetSpans resolve their own ambient
    // style; pre blocks and smaller UI retain their existing line metrics.
    final bodyStyle = bodyLeading && fontSize == AppTextSize.messageBody()
        ? AppTextStyle.messageBody(base)
        : const TextStyle();
    final style = DefaultTextStyle.of(context).style.merge(
      TextStyle(
        fontSize: effectiveFontSize,
        color: base,
        height: bodyStyle.height ?? (hasCustomEmoji ? 1.0 : null),
        leadingDistribution: bodyStyle.leadingDistribution,
      ),
    );
    // A fading paragraph wraps its inline children in a save layer and then
    // translates and restores the canvas. A resolved custom emoji composites
    // (tint filter, Lottie), which swaps the canvas mid-paint: the fade lands
    // as a dark band and everything painted after it in the bubble shifts out
    // of place. Inline widgets therefore truncate with an ellipsis instead.
    final overflow = maxLines == null
        ? TextOverflow.clip
        : children.any(_containsWidgetSpan)
        ? TextOverflow.ellipsis
        : TextOverflow.fade;
    return Builder(
      builder: (context) => RichText(
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: maxLines,
        overflow: overflow,
        textHeightBehavior: hasCustomEmoji
            ? const TextHeightBehavior(
                applyHeightToFirstAscent: false,
                applyHeightToLastDescent: false,
                leadingDistribution: TextLeadingDistribution.even,
              )
            : null,
        text: TextSpan(style: style, children: children),
        selectionRegistrar: SelectionContainer.maybeOf(context),
        selectionColor:
            Theme.of(context).textSelectionTheme.selectionColor ??
            AppTheme.brand.withValues(alpha: 0.28),
      ),
    );
  }

  static bool _containsWidgetSpan(InlineSpan span) {
    var found = false;
    span.visitChildren((child) {
      found = child is WidgetSpan;
      return !found;
    });
    return found;
  }

  Widget _quoteBlock(
    MessageTextEntity quote,
    String text,
    int start,
    int end,
    Color base,
    Color link,
    bool outgoing,
    List<MessageTextEntity> entities,
    double fontSize,
    bool bodyLeading,
  ) {
    final key = '${quote.offset}:${quote.length}';
    final quoteColor = _messageQuoteColor(outgoing);
    final quoteLink = !outgoing && _messageColors != null ? quoteColor : link;
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
        key: ValueKey('messageBlockQuote-${message.id}-$key'),
        decoration: BoxDecoration(
          color: _messageColors == null
              ? base.withValues(alpha: 0.07)
              : _messageAccentFill(quoteColor),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border(left: BorderSide(color: quoteColor, width: 3)),
        ),
        padding: const EdgeInsets.fromLTRB(9, 7, 8, 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _richText(
              text,
              base,
              quoteLink,
              start,
              end,
              false,
              false,
              maxLines: expanded ? null : 3,
              entities: entities,
              fontSize: fontSize,
              bodyLeading: bodyLeading,
            ),
            if (quote.isExpandableBlockQuote) ...[
              const SizedBox(height: 4),
              SelectionContainer.disabled(
                child: Text(
                  AppStrings.t(
                    expanded
                        ? AppStringKeys.messageBubbleCollapse
                        : AppStringKeys.messageBubbleExpandQuote,
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: quoteColor,
                    fontWeight: FontWeight.w600,
                  ),
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
    final c = _colors;
    final language = (pre.language ?? '').trim();
    final codeBackground = _codeBackgroundColor;
    return GestureDetector(
      key: ValueKey('message-code-block-${message.id}-$start-$end'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _copyMonospaceText(text.substring(start, end)),
      child: Container(
        width: _bubbleMaxWidth(),
        decoration: BoxDecoration(
          color: codeBackground,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: c.divider, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (language.isNotEmpty)
              SelectionContainer.disabled(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 5, 10, 4),
                  color:
                      (_brightness == Brightness.dark
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
    return (_brightness == Brightness.dark ? Colors.white : Colors.black)
        .withValues(alpha: 0.05);
  }

  Widget _imageContent(TdFileRef image, bool outgoing) {
    final geometry = _imagePreviewGeometry();
    final imageSize = geometry.contentSize;
    final caption = _caption();
    final grouped = _groupsMediaCaption(caption);
    final frameSize = Size(
      grouped
          ? _groupedMediaWidth(geometry.frameSize.width, caption!)
          : geometry.frameSize.width,
      geometry.frameSize.height,
    );
    final usesBlurredFrame =
        geometry.needsBlurredFill ||
        frameSize.width > geometry.frameSize.width + 0.5;
    final mediaRadius = grouped && _showsMessageBubbleSurface ? 0.0 : 10.0;
    final mediaBorderRadius = _messageBorderRadius(mediaRadius);
    final media = GestureDetector(
      onTap: () => widget.bubble.onOpenImage?.call(message),
      child: SizedBox(
        width: frameSize.width,
        height: frameSize.height,
        child: usesBlurredFrame
            ? _letterboxFrame(
                fillSource: image.thumbnail ?? image,
                childSize: imageSize,
                borderRadius: mediaBorderRadius,
                child: TDImage(
                  photo: image,
                  cornerRadius: 0,
                  fit: BoxFit.contain,
                  cacheWidth: _cachePx(imageSize.width),
                  cacheHeight: _cachePx(imageSize.height),
                  showProgress: true,
                ),
              )
            : ClipRRect(
                key: ValueKey('messageMediaClip-${message.id}'),
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
    final mediaWithApplyAction = widget.bubble.onApplyMessageBubble == null
        ? media
        : Stack(
            children: [
              media,
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: GestureDetector(
                  key: const ValueKey('messageBubbleApplyAction'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      widget.bubble.onApplyMessageBubble?.call(message),
                  child: Container(
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.brand,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon(
                          HeroAppIcons.palette,
                          size: 16,
                          color: AppTheme.onBrand,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          AppStrings.t(AppStringKeys.messageBubbleApply),
                          style: TextStyle(
                            color: AppTheme.onBrand,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
    return _mediaWithCaption(
      media: MessageMediaSpoiler(
        message: message,
        width: frameSize.width,
        height: frameSize.height,
        borderRadius: mediaBorderRadius,
        child: mediaWithApplyAction,
      ),
      mediaWidth: frameSize.width,
      caption: caption,
      outgoing: outgoing,
    );
  }

  /// Centres [child] in a wider or taller frame over a blurred-looking fill of
  /// [fillSource], the way official clients pad narrow or small media.
  Widget _letterboxFrame({
    required TdFileRef? fillSource,
    required Size childSize,
    required BorderRadius borderRadius,
    required Widget child,
  }) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // A few decoded pixels stretched over the frame read as the blur.
          // A gaussian here needs an image-filter layer inside the bubble's
          // clip, and on iOS that layer drew the photo and caption shifted
          // out of the bubble, leaving a blank card.
          if (fillSource != null)
            TDImage(
              photo: fillSource,
              cornerRadius: 0,
              cacheWidth: _letterboxFillPx,
              cacheHeight: _letterboxFillPx,
            )
          else
            const ColoredBox(color: Colors.black26),
          ColoredBox(color: Colors.black.withValues(alpha: 0.10)),
          Center(
            child: SizedBox(
              width: childSize.width,
              height: childSize.height,
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  Widget _mediaWithCaption({
    required Widget media,
    required double mediaWidth,
    required String? caption,
    required bool outgoing,
  }) {
    final hasForwardHeader = message.hasForwardAttribution;
    final hasViaBotHeader = message.hasViaBotAttribution;
    final hasAttributionHeader = hasForwardHeader || hasViaBotHeader;
    final hasReplyQuote = message.replyPreviewText != null;
    if (!_groupsMediaCaption(caption)) {
      final attributedMedia = hasAttributionHeader || hasReplyQuote
          ? _bubbleBackground(
              key: ValueKey(
                hasAttributionHeader
                    ? 'messageForwardedMedia-${message.id}'
                    : 'messageRepliedMedia-${message.id}',
              ),
              outgoing: outgoing,
              constraints: BoxConstraints.tightFor(width: mediaWidth),
              padding: EdgeInsets.zero,
              borderRadius: _messageBorderRadius(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasForwardHeader)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        10,
                        7,
                        10,
                        hasViaBotHeader ? 2 : 6,
                      ),
                      child: _forwardHeader(outgoing),
                    ),
                  if (hasViaBotHeader)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        10,
                        hasForwardHeader ? 0 : 7,
                        10,
                        6,
                      ),
                      child: _viaBotHeader(outgoing),
                    ),
                  if (hasReplyQuote)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        6,
                        hasAttributionHeader ? 0 : 6,
                        6,
                        6,
                      ),
                      child: _replyQuote(outgoing),
                    ),
                  media,
                ],
              ),
            )
          : media;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: outgoing
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          attributedMedia,
          if (caption != null) ...[
            const SizedBox(height: 4),
            _textBubble(
              caption,
              outgoing,
              includeForwardHeader: !hasAttributionHeader,
              includeReplyQuote: false,
            ),
          ],
        ],
      );
    }

    final c = _colors;
    final replacesOriginal = _translationReplacesOriginalFor(message);
    final displayCaption = replacesOriginal
        ? message.translationText ?? ''
        : caption!;
    final baseColor = replacesOriginal
        ? _translatedOnlyTextColor(outgoing)
        : outgoing
        ? _outgoingTextColor
        : _incomingTextColor;
    final linkColor = replacesOriginal
        ? Color.lerp(_messageLinkColor(outgoing), AppTheme.brand, 0.30)!
        : _messageLinkColor(outgoing);
    final captionEntities = replacesOriginal
        ? message.translationEntities
        : _activeTextEntities;
    return Container(
      // The media owns the attached bubble's width. Letting the caption (or
      // its translation/attribution) size this column leaves an empty strip
      // beside portrait previews, which have a smaller fixed width.
      width: mediaWidth,
      decoration: _showsMessageBubbleSurface
          ? BoxDecoration(
              color: outgoing ? _outgoingBubbleColor : _incomingBubbleColor,
              borderRadius: _messageBorderRadius(8),
              border: outgoing || _messageColors != null
                  ? null
                  : Border.all(color: c.divider, width: 0.5),
            )
          : null,
      clipBehavior: _showsMessageBubbleSurface ? Clip.antiAlias : Clip.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasForwardHeader)
            Padding(
              padding: EdgeInsets.fromLTRB(10, 7, 10, hasViaBotHeader ? 2 : 6),
              child: _forwardHeader(outgoing),
            ),
          if (hasViaBotHeader)
            Padding(
              padding: EdgeInsets.fromLTRB(10, hasForwardHeader ? 0 : 7, 10, 6),
              child: _viaBotHeader(outgoing),
            ),
          if (hasReplyQuote)
            Padding(
              padding: EdgeInsets.fromLTRB(
                6,
                hasAttributionHeader ? 0 : 6,
                6,
                6,
              ),
              child: _replyQuote(outgoing),
            ),
          media,
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 7, 6, 3),
            child: _mobileSelectableText(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (replacesOriginal)
                    KeyedSubtree(
                      key: const ValueKey('messageTranslatedOnlyText'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: _richTextWidgets(
                          displayCaption,
                          baseColor,
                          linkColor,
                          outgoing,
                          false,
                          captionEntities,
                        ),
                      ),
                    )
                  else
                    _desktopQuoteSource(
                      message,
                      displayCaption,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: _richTextWidgets(
                          displayCaption,
                          baseColor,
                          linkColor,
                          outgoing,
                          false,
                          captionEntities,
                        ),
                      ),
                      entities: captionEntities,
                    ),
                  if (_showsTranslationBlockFor(message)) ...[
                    const SizedBox(height: 7),
                    _translationBlock(outgoing, width: double.infinity),
                  ],
                ],
              ),
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

  /// Whether this message's video plays inside the bubble, the way official
  /// clients autoplay GIFs, video messages and short videos.
  bool get _autoplaysVideoInline => shouldAutoplayVideoInline(
    contentType: message.contentType,
    fileSizeBytes: message.videoFileSize,
    width: message.imageWidth,
    height: message.imageHeight,
  );

  /// A video message: a muted looping preview when it is small enough to play
  /// in place, otherwise its thumbnail with a play button. Both carry the
  /// duration badge, and tapping either opens the full player with sound.
  Widget _videoContent(bool outgoing) {
    final size = _imageDisplaySize();
    final caption = _caption();
    final dur = message.videoDuration ?? 0;
    final grouped = _groupsMediaCaption(caption);
    final mediaRadius = grouped && _showsMessageBubbleSurface ? 0.0 : 10.0;
    final inline = _autoplaysVideoInline && message.video != null;
    final media = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.bubble.onPlayVideo?.call(message),
      onLongPress: () => _handleLongPress(MessageActionSource.video),
      onSecondaryTapUp: (details) =>
          _handleSecondaryTapUp(details, MessageActionSource.video),
      child: SizedBox(
        key: inline ? ValueKey('message-inline-video-${message.id}') : null,
        width: size.width,
        height: size.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: _messageBorderRadius(mediaRadius),
              child: inline
                  ? LoopingVideoView(
                      file: message.video!,
                      fallback: message.image,
                      fit: BoxFit.cover,
                      showDownloadProgress: true,
                    )
                  : message.image != null
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
            if (!inline)
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
            // Duration badge, with the muted marker an inline preview needs.
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
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatMediaDuration(dur),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                      if (inline) ...[
                        const SizedBox(width: 4),
                        const AppIcon(
                          HeroAppIcons.volumeXmark,
                          color: Colors.white,
                          size: 12,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    final framed = _groupedVideoFrame(
      media,
      size,
      caption,
      _messageBorderRadius(mediaRadius),
    );
    return _mediaWithCaption(
      media: MessageMediaSpoiler(
        message: message,
        width: framed.width,
        height: size.height,
        borderRadius: _messageBorderRadius(mediaRadius),
        child: framed.media,
      ),
      mediaWidth: framed.width,
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
    final mediaRadius = grouped && _showsMessageBubbleSurface ? 0.0 : 10.0;
    final media = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.bubble.onPlayVideo?.call(message),
      onLongPress: () => _handleLongPress(MessageActionSource.video),
      onSecondaryTapUp: (details) =>
          _handleSecondaryTapUp(details, MessageActionSource.video),
      child: ClipRRect(
        borderRadius: _messageBorderRadius(mediaRadius),
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
    final framed = _groupedVideoFrame(
      media,
      size,
      caption,
      _messageBorderRadius(mediaRadius),
    );
    return _mediaWithCaption(
      media: MessageMediaSpoiler(
        message: message,
        width: framed.width,
        height: size.height,
        borderRadius: _messageBorderRadius(mediaRadius),
        child: framed.media,
      ),
      mediaWidth: framed.width,
      caption: caption,
      outgoing: outgoing,
    );
  }

  // MARK: - Voice

  Widget _voiceBubble(MessageVoice voice, bool outgoing) {
    final c = _colors;
    final decorative = _usesDecorativeBubbleBackground;
    final fg = outgoing
        ? _outgoingTextColor
        : decorative
        ? _incomingTextColor
        : AppTheme.brand;
    final track = fg.withValues(alpha: outgoing ? 0.35 : 0.25);
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
            ? formatMediaDuration(_voice.position.inSeconds)
            : formatMediaDuration(voice.duration);
        return _bubbleBackground(
          outgoing: outgoing,
          constraints: const BoxConstraints.tightFor(width: 210),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          borderRadius: _messageBorderRadius(6),
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
                            : FontWeight.w600,
                        color: outgoing
                            ? _outgoingTextColor.withValues(alpha: 0.9)
                            : decorative
                            ? _incomingTextColor.withValues(alpha: 0.9)
                            : c.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              if (voice.transcription.isNotEmpty ||
                  voice.transcriptionPending ||
                  voice.transcriptionError != null ||
                  widget.bubble.onTranscribeVoice != null) ...[
                const SizedBox(height: 7),
                GestureDetector(
                  key: const ValueKey('voiceTranscription'),
                  behavior: HitTestBehavior.opaque,
                  onTap: voice.transcriptionPending
                      ? null
                      : () => widget.bubble.onTranscribeVoice?.call(message),
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
                                : decorative
                                ? _incomingTextColor.withValues(alpha: 0.88)
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

  // MARK: - Location

  Widget _locationBubble(MessageLocation location) {
    final c = _colors;
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
    final c = _colors;
    final themed = _messageColors != null;
    final messageSurface = outgoing
        ? _outgoingBubbleColor
        : _incomingBubbleColor;
    final messageText = outgoing ? _outgoingTextColor : _incomingTextColor;
    final surface = themed ? messageSurface : c.card;
    final itemText = themed ? messageText : _incomingTextColor;
    final secondary = themed
        ? messageText.withValues(alpha: 0.70)
        : c.textSecondary;
    final divider = themed ? messageText.withValues(alpha: 0.16) : c.divider;
    final captionText = themed ? messageText : c.textPrimary;
    final captionLink = themed ? _messageLinkColor(outgoing) : c.linkBlue;
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
    final replacesOriginal =
        captionSource != null && _translationReplacesOriginalFor(captionSource);
    final displayCaption = replacesOriginal
        ? captionSource.translationText ?? ''
        : caption;
    final displayCaptionEntities = replacesOriginal
        ? captionSource.translationEntities
        : captionSource?.textEntities ?? const <MessageTextEntity>[];
    final displayCaptionColor = replacesOriginal
        ? _translatedOnlyTextColor(outgoing)
        : captionText;
    final displayCaptionLink = replacesOriginal
        ? Color.lerp(captionLink, AppTheme.brand, 0.30)!
        : captionLink;
    final singleGif =
        sources.length == 1 && _isGifDocument(sources.single.document!);
    return Container(
      key: ValueKey('messageDocumentAlbumCard-${message.id}'),
      width: _bubbleMaxWidth(),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: _messageBorderRadius(6),
        border: themed ? null : Border.all(color: c.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < sources.length; index++) ...[
            if (index > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Container(height: 0.5, color: divider),
              ),
            _fileAlbumItem(
              sources[index],
              primaryColor: itemText,
              secondaryColor: secondary,
              surfaceColor: surface,
            ),
          ],
          if (captionSource != null) ...[
            SizedBox(height: sources.length == 1 ? 10 : 2),
            if (!singleGif)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Container(height: 0.5, color: divider),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: _mobileSelectableText(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _desktopQuoteSource(
                      captionSource,
                      replacesOriginal ? '' : displayCaption,
                      KeyedSubtree(
                        key: replacesOriginal
                            ? const ValueKey('messageTranslatedOnlyText')
                            : null,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _richTextWidgets(
                            displayCaption,
                            displayCaptionColor,
                            displayCaptionLink,
                            outgoing,
                            false,
                            displayCaptionEntities,
                          ),
                        ),
                      ),
                      entities: displayCaptionEntities,
                    ),
                    if (translationSource != null &&
                        _showsTranslationBlockFor(translationSource)) ...[
                      const SizedBox(height: 4),
                      _translationBlock(
                        outgoing,
                        width: double.infinity,
                        source: translationSource,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          if (captionSource == null &&
              translationSource != null &&
              _showsTranslationBlockFor(translationSource)) ...[
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

  Widget _fileAlbumItem(
    ChatMessage source, {
    required Color primaryColor,
    required Color secondaryColor,
    required Color surfaceColor,
  }) {
    final doc = source.document!;
    final isGif = _isGifDocument(doc);
    final itemKey = GlobalKey();
    final layoutKey =
        source.id == widget.bubble.targetMediaMessageId &&
            widget.bubble.targetMediaKey != null
        ? widget.bubble.targetMediaKey
        : itemKey;
    return GestureDetector(
      key: ValueKey('messageDocumentAlbumFile-${source.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FileDetailView(
            doc: doc,
            chatId: source.chatId ?? message.chatId,
            messageId: source.id,
          ),
        ),
      ),
      onLongPress: () => _handleGroupedFileLongPress(source, itemKey),
      onSecondaryTapUp: (details) =>
          _handleGroupedFileSecondaryTap(source, details.globalPosition),
      child: isGif && doc.file != null
          ? SizedBox(
              key: layoutKey,
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
              key: layoutKey,
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
                          style: TextStyle(fontSize: 15, color: primaryColor),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _byteString(doc.size),
                          style: TextStyle(fontSize: 12, color: secondaryColor),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _fileGlyph(doc, source.id, surfaceColor: surfaceColor),
                ],
              ),
            ),
    );
  }

  Widget _fileGlyph(
    MessageDocument document,
    int messageId, {
    required Color surfaceColor,
  }) {
    return SizedBox(
      width: 44,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          DocumentFileIcon(
            key: ValueKey('documentFileIcon-$messageId'),
            fileName: document.fileName,
            extension: document.ext,
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
                border: Border.all(color: surfaceColor, width: 1.5),
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

  AppColors get c => _colors;

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
}
