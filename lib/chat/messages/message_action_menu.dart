//
//  message_action_menu.dart
//
//  The dark, rounded HUD menu shown when a message bubble is long-pressed. A
//  grid of context actions (复制 / 回复 / 转发 / 收藏 / 删除, plus 存表情 for
//  stickers). Fixed dark colors on purpose — a floating HUD, not themed surface.
//  Port of the Swift `MessageActionMenu`.
//

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../components/app_icons.dart';
import '../../components/app_press_ripple.dart';
import '../../platform/adaptive_platform.dart';
import '../../settings/translation_controller.dart';
import '../../tdlib/td_models.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../stickers/custom_emoji.dart';
import '../stickers/emoji_store.dart';
import 'message_text_quote.dart';
import 'quick_reaction_choice.dart';

enum MessageAction {
  copy(HeroAppIcons.file, AppStringKeys.messageActionCopy),
  copyImage(HeroAppIcons.image, AppStringKeys.messageActionCopyImage),
  copyMessageLink(
    HeroAppIcons.link,
    AppStringKeys.messageActionCopyMessageLink,
  ),
  edit(HeroAppIcons.pen, AppStringKeys.messageActionEdit),
  suggestOffer(HeroAppIcons.penToSquare, AppStringKeys.suggestedPostEditOffer),
  translate(HeroAppIcons.language, AppStringKeys.messageActionTranslate),
  displayOriginal(HeroAppIcons.eye, AppStringKeys.messageActionDisplayOriginal),
  displayTranslation(
    HeroAppIcons.language,
    AppStringKeys.messageActionDisplayTranslation,
  ),
  reply(HeroAppIcons.quoteLeft, AppStringKeys.chatInputBarReply),
  quote(HeroAppIcons.quoteLeft, AppStringKeys.messageActionQuote),
  replies(HeroAppIcons.comments, AppStringKeys.messageActionReplies),
  forward(HeroAppIcons.forward, AppStringKeys.messageActionForward),
  repeat(HeroAppIcons.circlePlus, AppStringKeys.messageActionRepeat),
  report(HeroAppIcons.triangleExclamation, AppStringKeys.messageActionReport),
  block(HeroAppIcons.ban, AppStringKeys.messageActionBlock),
  hideSender(HeroAppIcons.eyeSlash, AppStringKeys.messageActionHideSender),
  playMuted(HeroAppIcons.volumeXmark, AppStringKeys.messageActionPlayMuted),
  addToPlaylist(HeroAppIcons.music, AppStringKeys.musicPlayerAddToPlaylist),
  saveToPhotos(HeroAppIcons.download, AppStringKeys.messageActionSaveToPhotos),
  saveAs(HeroAppIcons.download, AppStringKeys.messageActionSaveAs),
  multiSelect(HeroAppIcons.circleCheck, AppStringKeys.messageActionMultiSelect),
  pinTodo(HeroAppIcons.pin, AppStringKeys.messageActionSetTodo),
  unpinTodo(HeroAppIcons.pin, AppStringKeys.messageActionUnsetTodo),
  save(HeroAppIcons.thumbtack, AppStringKeys.messageActionFavorite),
  saveSticker(HeroAppIcons.circlePlus, AppStringKeys.imageEditAdd),
  viewStickerSet(HeroAppIcons.tableCells, AppStringKeys.messageActionSticker),
  viewEdits(HeroAppIcons.clock, AppStringKeys.messageActionViewEdits),
  removeMirror(HeroAppIcons.trash, AppStringKeys.historyRemoveFromMirrorAction),
  delete(HeroAppIcons.trash, AppStringKeys.chatDelete);

  const MessageAction(this.glyph, this.label);

  final AppIconData glyph;
  final String label;

  bool get isDestructive =>
      this == MessageAction.delete ||
      this == MessageAction.report ||
      this == MessageAction.block ||
      this == MessageAction.removeMirror;
}

enum MessageActionSource { normal, video }

enum MessageActionMenuLayout { adaptive, grid, vertical }

/// Where the phone overlay puts its two pieces, in overlay coordinates.
@immutable
class MessageActionOverlayPlacement {
  const MessageActionOverlayPlacement({
    required this.stripTop,
    required this.menuTop,
    required this.menuHeight,
  });

  /// Top edge of the reaction strip (unused when no strip is drawn).
  final double stripTop;

  /// Top edge of the action menu.
  final double menuTop;

  /// Height the menu is given; it scrolls when the height is a shortfall.
  final double menuHeight;
}

/// The floating overlay's palette, taken from the app theme: a light card with
/// dark ink in day mode, the raised dark surface at night.
///
/// The menu and the reaction strip above it draw from one palette so the pair
/// reads as a single themed surface instead of a fixed dark HUD parked over a
/// light chat.
@immutable
class MessageActionPalette {
  const MessageActionPalette({
    required this.surface,
    required this.foreground,
    required this.divider,
    required this.destructive,
    required this.shadow,
    required this.chip,
  });

  factory MessageActionPalette.of(BuildContext context) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return MessageActionPalette(
      // The raised surface the rest of the app floats over a page: white in
      // day mode, the nav-bar grey at night.
      surface: dark ? c.navBar : c.card,
      foreground: c.textPrimary,
      divider: c.divider,
      destructive: dark ? _nightDestructive : AppTheme.tagRed,
      shadow: Colors.black.withValues(alpha: dark ? 0.36 : 0.16),
      chip: dark ? c.searchFill : c.groupedBackground,
    );
  }

  /// The lighter red the dark HUD always used; the day palette takes the
  /// app's own destructive red, which reads on a white card.
  static const _nightDestructive = Color(0xFFFF6961);

  final Color surface;
  final Color foreground;
  final Color divider;
  final Color destructive;
  final Color shadow;

  /// Fill for a small control sitting on [surface] (the expand button, the
  /// reaction tab strip).
  final Color chip;
}

/// The line box a reaction glyph occupies at [fontSize] in the style it
/// inherits, before any layout constraint.
///
/// Both strips draw their emoji with the app's text style (only the size
/// differs), so the glyph's box follows the UI font, not the emoji font: a CJK
/// text font's line box runs 1.35–1.45em, taller than the ~1.18em the emoji
/// itself needs. Sizing the slot on a fixed constant (34pt for a 28pt emoji)
/// therefore clipped the glyph top and bottom — `Text` clips to the paragraph's
/// own box once the inherited line box outgrows the slot.
double _reactionGlyphExtent(BuildContext context, double fontSize) {
  final style = DefaultTextStyle.of(
    context,
  ).style.merge(TextStyle(fontSize: fontSize));
  final painter = TextPainter(
    text: TextSpan(text: '😀', style: style),
    textDirection: Directionality.of(context),
    textScaler: TextScaler.noScaling,
    maxLines: 1,
  )..layout();
  final extent = painter.height;
  painter.dispose();
  return extent;
}

class QuickReactionBar extends StatelessWidget {
  const QuickReactionBar({
    super.key,
    required this.reactions,
    required this.onReaction,
    required this.onExpand,
  });

  static const maxFittedButtonCount = 10;
  static const emojiSize = 28.0;
  static const _horizontalPadding = 8.0;
  static const _verticalPadding = 6.0;

  /// The slot never shrinks below the size the pill was designed around; it
  /// GROWS when the inherited line box is taller than that constant, so the
  /// glyph is never clipped by a font the strip does not control.
  static const _minSlotExtent = 34.0;

  /// Headroom around the measured line box for raster overshoot.
  static const _glyphSlop = 2.0;

  /// One emoji slot's height for [context]'s text metrics.
  static double _slotExtent(BuildContext context) => math.max(
    _minSlotExtent,
    _reactionGlyphExtent(context, emojiSize) + _glyphSlop,
  );

  /// The pill's height at [context]'s text metrics — the host places the
  /// action menu against exactly this, so it must not be a constant either.
  static double heightFor(BuildContext context) =>
      _slotExtent(context) + _verticalPadding * 2;

  final List<QuickReactionChoice> reactions;
  final ValueChanged<QuickReactionChoice> onReaction;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final palette = MessageActionPalette.of(context);
    final buttonCount = reactions.length + 1;
    final slotExtent = _slotExtent(context);
    return Container(
      key: const ValueKey('quick-reaction-bar'),
      width: MessageActionMenu.widthForAvailable(
        MediaQuery.sizeOf(context).width - 24,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: _horizontalPadding,
        vertical: _verticalPadding,
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        boxShadow: [BoxShadow(color: palette.shadow, blurRadius: 12)],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final buttons = <Widget>[
            for (final emoji in reactions)
              _reactionButton(emoji, palette, slotExtent),
            _expandButton(palette, slotExtent),
          ];
          if (buttonCount <= maxFittedButtonCount) {
            return Row(
              children: [for (final button in buttons) Expanded(child: button)],
            );
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(mainAxisSize: MainAxisSize.min, children: buttons),
          );
        },
      ),
    );
  }

  Widget _reactionButton(
    QuickReactionChoice reaction,
    MessageActionPalette palette,
    double slotExtent,
  ) {
    return GestureDetector(
      key: ValueKey('quick-reaction-${reaction.storageValue}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => onReaction(reaction),
      child: SizedBox(
        width: 40,
        height: slotExtent,
        child: Center(
          child: reaction.isCustom
              ? CustomEmojiView(
                  id: reaction.customEmojiId,
                  size: emojiSize,
                  color: palette.foreground,
                )
              : Text(
                  reaction.emoji,
                  textScaler: TextScaler.noScaling,
                  style: const TextStyle(fontSize: emojiSize),
                ),
        ),
      ),
    );
  }

  Widget _expandButton(MessageActionPalette palette, double slotExtent) {
    return GestureDetector(
      key: const ValueKey('quick-reaction-expand'),
      behavior: HitTestBehavior.opaque,
      onTap: onExpand,
      child: SizedBox(
        width: 40,
        height: slotExtent,
        child: Center(
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.chip,
              shape: BoxShape.circle,
            ),
            child: AppIcon(
              HeroAppIcons.chevronDown,
              size: 22,
              color: palette.foreground,
            ),
          ),
        ),
      ),
    );
  }
}

/// The reaction strip that rides on top of the desktop context menu.
///
/// Drawn as the menu's own upper storey: same surface, same 9pt radius, same
/// hairline border, laid out to the menu's width so the two read as one
/// stack rather than a pill parked above a card. Touch keeps the rounded
/// [QuickReactionBar], which floats free of its grid menu.
class MenuReactionBar extends StatelessWidget {
  const MenuReactionBar({
    super.key,
    required this.reactions,
    required this.onReaction,
    required this.onExpand,
  });

  /// Six plus the expand button divide the menu's 220pt width into 30pt
  /// slots. More would either narrow the slots below a comfortable target or
  /// push the strip wider than the menu it sits on.
  static const maxReactionCount = 6;
  static const emojiSize = 22.0;
  static const _padding = 5.0;

  /// The slot keeps the strip's designed 30pt floor and grows for an inherited
  /// line box taller than that (see [_reactionGlyphExtent]).
  static const _minSlotExtent = 30.0;
  static const _glyphSlop = 2.0;

  static double _slotExtent(BuildContext context) => math.max(
    _minSlotExtent,
    _reactionGlyphExtent(context, emojiSize) + _glyphSlop,
  );

  /// The strip's height at [context]'s text metrics. Desktop places the menu
  /// below it by this figure, so it is measured, never assumed.
  static double heightFor(BuildContext context) =>
      _slotExtent(context) + _padding * 2;

  final List<QuickReactionChoice> reactions;
  final ValueChanged<QuickReactionChoice> onReaction;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final palette = MessageActionPalette.of(context);
    final shown = reactions.take(maxReactionCount).toList(growable: false);
    final slotExtent = _slotExtent(context);
    return Container(
      key: const ValueKey('menu-reaction-bar'),
      height: heightFor(context),
      padding: const EdgeInsets.symmetric(horizontal: _padding),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: palette.divider, width: 0.75),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          for (final reaction in shown)
            Expanded(
              child: _MenuReactionSlot(
                key: ValueKey('menu-reaction-${reaction.storageValue}'),
                palette: palette,
                slotExtent: slotExtent,
                onTap: () => onReaction(reaction),
                child: reaction.isCustom
                    ? CustomEmojiView(
                        id: reaction.customEmojiId,
                        size: emojiSize,
                        color: palette.foreground,
                      )
                    : Text(
                        reaction.emoji,
                        textScaler: TextScaler.noScaling,
                        style: const TextStyle(fontSize: emojiSize),
                      ),
              ),
            ),
          Expanded(
            child: _MenuReactionSlot(
              key: const ValueKey('menu-reaction-expand'),
              palette: palette,
              slotExtent: slotExtent,
              onTap: onExpand,
              child: AppIcon(
                HeroAppIcons.faceSmile,
                size: 21,
                color: palette.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One slot of [MenuReactionBar]. A pointer gets a rounded fill under the
/// glyph it is over, matching how a row of the menu below lights up.
class _MenuReactionSlot extends StatefulWidget {
  const _MenuReactionSlot({
    super.key,
    required this.palette,
    required this.slotExtent,
    required this.onTap,
    required this.child,
  });

  final MessageActionPalette palette;

  /// The glyph box the strip measured for its emoji — never a constant.
  final double slotExtent;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_MenuReactionSlot> createState() => _MenuReactionSlotState();
}

class _MenuReactionSlotState extends State<_MenuReactionSlot> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.duration(context, AppMotion.quick),
          curve: AppMotion.standard,
          height: widget.slotExtent,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hovering
                ? widget.palette.foreground.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class MessageActionMenu extends StatelessWidget {
  const MessageActionMenu({
    super.key,
    required this.message,
    required this.isPinned,
    required this.onSelect,
    this.allowForwarding = true,
    this.allowTranslation = true,
    this.allowReply = true,
    this.allowQuote = false,
    this.hasSelectedQuote = false,
    this.allowSuggestedPostOffer = false,
    this.allowHideSender = false,
    this.allowCopyMessageLink = false,
    this.allowViewEdits = false,
    this.allowProtectedCopyForward = false,
    this.source = MessageActionSource.normal,
    this.showingOriginalTranslation = false,
    this.layout = MessageActionMenuLayout.adaptive,
  });
  final ChatMessage message;
  final bool isPinned;
  final ValueChanged<MessageAction> onSelect;
  final bool allowForwarding;
  final bool allowTranslation;

  /// Offer reply, and quote along with it: a quote is a reply carrying a
  /// quoted range, so it disappears wherever Telegram refuses the reply.
  final bool allowReply;
  final bool allowQuote;
  final bool hasSelectedQuote;
  final bool allowSuggestedPostOffer;

  /// Offer to hide this sender's messages on this device (groups only).
  final bool allowHideSender;

  /// Offer [MessageAction.copyMessageLink] (server-verified availability).
  final bool allowCopyMessageLink;

  /// Offer [MessageAction.viewEdits]: a kept edit trail exists for this
  /// message in the local mirror (compile-time gated feature).
  final bool allowViewEdits;

  /// Offer 转发 inside a protected chat: the kept-messages copy-forward
  /// toggle is on, so the selection re-sends as a copy instead of a forward
  /// (the route _forwardMessage takes). Repeat rides the same copy route —
  /// in a protected chat it is a no-quote copy re-send into the CURRENT
  /// chat, which is exactly what the toggle enables.
  final bool allowProtectedCopyForward;
  final MessageActionSource source;
  final bool showingOriginalTranslation;
  final MessageActionMenuLayout layout;

  static const _horizontalPadding = 6.0;
  static const _actionWidth = 58.0;
  static const _maxContentSizedActionCount = 10;
  static const preferredWidth = 332.0;
  static const preferredHeight = 152.0;
  static const desktopPreferredWidth = 220.0;
  static const _desktopActionHeight = 36.0;

  /// Touch dropdown geometry, at the reference client's popup scale: a full-height row
  /// per option, the menu's own text size, and a column that hugs its widest
  /// label between a comfortable minimum and a cap — instead of the desktop's
  /// pointer-sized rows squeezed into a fixed 220px column.
  static const mobileDropdownRowHeight = 44.0;
  static const mobileDropdownMinWidth = 196.0;
  static const mobileDropdownMaxWidth = 300.0;
  static const mobileDropdownVerticalInset = AppSpacing.md;
  static const mobileDropdownHorizontalPadding = AppSpacing.xxl;
  static const mobileDropdownIconSize = AppIconSize.xl;
  static const mobileDropdownIconGap = AppSpacing.lg;
  static const mobileDropdownTextSize = AppTextSize.bodyLarge;
  static const maxGridLabelCharacters = 8;

  @visibleForTesting
  static ({int first, int second}) rowCountsForActionCount(int count) {
    if (count <= 5) return (first: math.max(count, 0), second: 0);
    final first = (count + 1) ~/ 2;
    return (first: first, second: count - first);
  }

  static double widthForAvailable(double availableWidth) =>
      math.min(preferredWidth, availableWidth);

  @visibleForTesting
  static double mobileWidthForActionCount(int count, double availableWidth) {
    if (count > _maxContentSizedActionCount) {
      return widthForAvailable(availableWidth);
    }
    final rows = rowCountsForActionCount(count);
    final columns = math.max(rows.first, rows.second);
    final fitted =
        (_horizontalPadding * 2) + (math.max(columns, 1) * _actionWidth);
    return math.min(fitted, availableWidth);
  }

  @visibleForTesting
  static double desktopHeightForActionCount(
    int count, {
    required double availableHeight,
  }) =>
      math.min(math.max(0, count) * _desktopActionHeight + 12, availableHeight);

  /// Height of the touch dropdown: one full row per option between its insets.
  @visibleForTesting
  static double mobileDropdownHeightForActionCount(
    int count, {
    required double availableHeight,
  }) => math.min(
    math.max(0, count) * mobileDropdownRowHeight +
        mobileDropdownVerticalInset * 2,
    availableHeight,
  );

  /// Width of the touch dropdown: its widest label plus the glyph column and
  /// the row insets, between [mobileDropdownMinWidth] and
  /// [mobileDropdownMaxWidth], never wider than [availableWidth].
  @visibleForTesting
  static double mobileDropdownWidthFor({
    required double longestLabelWidth,
    double availableWidth = double.infinity,
  }) {
    final fitted =
        longestLabelWidth +
        mobileDropdownIconSize +
        mobileDropdownIconGap +
        mobileDropdownHorizontalPadding * 2 +
        _labelFitSlop;
    return math.min(
      fitted.clamp(mobileDropdownMinWidth, mobileDropdownMaxWidth),
      availableWidth,
    );
  }

  /// Rounding headroom so the widest label's own glyph raster never ellipsizes.
  static const _labelFitSlop = 2.0;

  static Rect rectInOverlay(
    Rect globalRect, {
    required Offset Function(Offset) globalToLocal,
  }) => Rect.fromPoints(
    globalToLocal(globalRect.topLeft),
    globalToLocal(globalRect.bottomRight),
  );

  static Rect? anchorRectForPresentation({
    required Rect? targetRect,
    required Offset? pointer,
    required bool usePointer,
  }) {
    if (usePointer && pointer != null) {
      return Rect.fromLTWH(pointer.dx, pointer.dy, 0, 0);
    }
    return targetRect;
  }

  /// Where the phone overlay puts its two pieces.
  ///
  /// The strip always rides ABOVE the menu — the pair reads as one stack in
  /// that order, so a message near the bottom lifts the whole pair instead of
  /// flipping the menu over the reactions.
  ///
  /// [menuStartsAtAnchorTop] is the dropdown (true), whose menu covers the
  /// bubble right under the strip; the grid (false) keeps its menu below the
  /// bubble and only lifts it when the bottom leaves no room. A null [anchor]
  /// centres the pair in the viewport.
  static MessageActionOverlayPlacement placeMobileOverlay({
    required Rect? anchor,
    required double preferredMenuHeight,
    required double stripHeight,
    required double topSafe,
    required double bottomSafe,
    required double viewportHeight,
    required bool menuStartsAtAnchorTop,
    double gap = 8,
  }) {
    final stripGap = stripHeight > 0 ? gap : 0.0;
    final menuHeight = math.min(
      preferredMenuHeight,
      math.max(0.0, bottomSafe - topSafe - stripHeight - stripGap),
    );
    final stackHeight = stripHeight + stripGap + menuHeight;

    if (anchor == null) {
      final top = ((viewportHeight - stackHeight) / 2)
          .clamp(topSafe, math.max(topSafe, bottomSafe - stackHeight))
          .toDouble();
      return MessageActionOverlayPlacement(
        stripTop: top,
        menuTop: top + stripHeight + stripGap,
        menuHeight: menuHeight,
      );
    }

    if (menuStartsAtAnchorTop) {
      // Dropdown: the strip sits above the bubble and the menu directly under
      // it. When the menu would run past the bottom, the pair slides up so the
      // menu ends at the safe area and the strip stays on top of it.
      final top = (anchor.top - stripHeight - stripGap)
          .clamp(topSafe, math.max(topSafe, bottomSafe - stackHeight))
          .toDouble();
      return MessageActionOverlayPlacement(
        stripTop: top,
        menuTop: top + stripHeight + stripGap,
        menuHeight: menuHeight,
      );
    }

    // Grid: strip above the bubble, menu under the bubble. Lift both only when
    // the bottom would cut the menu off, and keep the strip above the menu.
    final stripTop = (anchor.top - stripHeight - stripGap)
        .clamp(topSafe, math.max(topSafe, bottomSafe - stripHeight))
        .toDouble();
    var menuTop = anchor.bottom + stripGap;
    if (menuTop + menuHeight > bottomSafe) {
      menuTop = math.max(
        topSafe + stripHeight + stripGap,
        bottomSafe - menuHeight,
      );
    }
    final liftedStripTop = math
        .min(stripTop, math.max(topSafe, menuTop - stripGap - stripHeight))
        .toDouble();
    return MessageActionOverlayPlacement(
      stripTop: liftedStripTop,
      menuTop: menuTop,
      menuHeight: menuHeight,
    );
  }

  static Offset verticalOriginForPointer({
    required Offset pointer,
    required Size viewport,
    required Size menuSize,
    required double topSafe,
    required double bottomSafe,
    double horizontalMargin = 10,
  }) {
    final maxLeft = math.max(
      horizontalMargin,
      viewport.width - menuSize.width - horizontalMargin,
    );
    final maxTop = math.max(topSafe, bottomSafe - menuSize.height);
    return Offset(
      pointer.dx.clamp(horizontalMargin, maxLeft),
      pointer.dy.clamp(topSafe, maxTop),
    );
  }

  static Offset desktopOriginForPointer({
    required Offset pointer,
    required Size viewport,
    required Size menuSize,
    required double topSafe,
    required double bottomSafe,
    double horizontalMargin = 10,
  }) => verticalOriginForPointer(
    pointer: pointer,
    viewport: viewport,
    menuSize: menuSize,
    topSafe: topSafe,
    bottomSafe: bottomSafe,
    horizontalMargin: horizontalMargin,
  );

  @visibleForTesting
  static String gridLabel(String label) {
    final codePoints = label.runes.toList(growable: false);
    if (codePoints.length <= maxGridLabelCharacters) return label;
    final prefix = String.fromCharCodes(
      codePoints.take(maxGridLabelCharacters - 1),
    ).trimRight();
    return '$prefix…';
  }

  bool _usesVerticalLayout(BuildContext context) => switch (layout) {
    MessageActionMenuLayout.vertical => true,
    MessageActionMenuLayout.grid => false,
    MessageActionMenuLayout.adaptive => isDesktopTargetPlatform(
      Theme.of(context).platform,
    ),
  };

  bool get _isEditableMessage =>
      message.contentType == 'messageText' ||
      message.contentType == 'messageRichMessage' ||
      message.contentType == 'messagePhoto' ||
      message.contentType == 'messageVideo' ||
      message.contentType == 'messageAnimation' ||
      message.contentType == 'messageAudio' ||
      message.contentType == 'messageDocument' ||
      message.contentType == 'messageChecklist';

  bool get _hasCopyableText => message.text.trim().isNotEmpty;

  List<MessageAction> _actions(
    TranslationController translation, {
    required bool isDesktop,
    required bool isMacOS,
  }) {
    // Call logs aren't reactable, but their delivery metadata stays useful.
    if (message.isCall) {
      return [MessageAction.delete];
    }
    final result = <MessageAction>[];
    if (_hasCopyableText) {
      result.add(MessageAction.copy);
      if (message.isOutgoing && _isEditableMessage) {
        result.add(MessageAction.edit);
      }
      if (translation.displayStyle == TranslationDisplayStyle.translatedOnly &&
          (message.translationText?.trim().isNotEmpty ?? false)) {
        result.add(
          showingOriginalTranslation
              ? MessageAction.displayTranslation
              : MessageAction.displayOriginal,
        );
      }
      if (translation.enabled && allowTranslation) {
        result.add(MessageAction.translate);
      }
    }
    if (isMacOS &&
        allowForwarding &&
        message.isPhoto &&
        message.image != null &&
        !message.isContentRestricted) {
      result.add(MessageAction.copyImage);
    }
    // The availability flag already covers service messages, calls and
    // protected content — the menu never guesses it client-side.
    if (allowCopyMessageLink) {
      result.add(MessageAction.copyMessageLink);
    }
    if (!_hasCopyableText && message.isOutgoing && _isEditableMessage) {
      result.add(MessageAction.edit);
    }
    if (allowSuggestedPostOffer && !message.isService && _isEditableMessage) {
      result.add(MessageAction.suggestOffer);
    }
    if (allowReply) {
      // the reference client parity: quote lives in the text-selection flow (the
      // reply panel here), not as a separate long-press menu entry — a
      // desktop transcript selection becomes Quote directly; everywhere else
      // the single Reply action opens the banner whose panel quotes.
      final canQuote = allowQuote && canQuoteMessageText(message);
      result.add(
        isDesktop && canQuote && hasSelectedQuote
            ? MessageAction.quote
            : MessageAction.reply,
      );
    }
    if (message.hasActualReplies) {
      result.add(MessageAction.replies);
    }
    if (allowForwarding) {
      result.add(MessageAction.forward);
      result.add(MessageAction.repeat);
    } else if (allowProtectedCopyForward && !message.isService) {
      result.add(MessageAction.forward);
      result.add(MessageAction.repeat);
    }
    if (message.video != null && source == MessageActionSource.video) {
      result.add(MessageAction.playMuted);
    }
    if (allowForwarding && message.music?.file != null) {
      result.add(MessageAction.addToPlaylist);
    }
    if (message.isPhoto || message.video != null) {
      // A computer has no album to add to — it gets a save panel instead.
      result.add(isDesktop ? MessageAction.saveAs : MessageAction.saveToPhotos);
    }
    result.add(MessageAction.multiSelect);
    result.add(isPinned ? MessageAction.unpinTodo : MessageAction.pinTodo);
    if (allowForwarding) result.add(MessageAction.save);
    // 添加 — add any sticker (tgs / webm / webp) to favorites.
    // Non-premium users can't add custom emoji / emoji sets, so hide 添加 + 表情包
    // on single-emoji messages for them (regular stickers stay addable).
    final canAddEmoji = !message.isAnimatedEmoji || EmojiStore.shared.isPremium;
    if (message.stickerFileId != null && canAddEmoji) {
      result.add(MessageAction.saveSticker);
    }
    if (message.stickerSetId != null && canAddEmoji) {
      result.add(MessageAction.viewStickerSet);
    }
    if (allowHideSender) result.add(MessageAction.hideSender);
    if (allowViewEdits) result.add(MessageAction.viewEdits);
    if (message.mirrorEntry != null) result.add(MessageAction.removeMirror);
    result.add(MessageAction.delete);
    return result;
  }

  double preferredHeightFor(BuildContext context) {
    if (!_usesVerticalLayout(context)) {
      return preferredHeight;
    }
    final actions = _actions(
      context.read<TranslationController>(),
      isDesktop: isDesktopTargetPlatform(Theme.of(context).platform),
      isMacOS: Theme.of(context).platform == TargetPlatform.macOS,
    );
    final availableHeight = MediaQuery.sizeOf(context).height - 24;
    return isDesktopTargetPlatform(Theme.of(context).platform)
        ? desktopHeightForActionCount(
            actions.length,
            availableHeight: availableHeight,
          )
        : mobileDropdownHeightForActionCount(
            actions.length,
            availableHeight: availableHeight,
          );
  }

  /// The column's width: fixed and compact on a pointer, hugging its widest
  /// label on the touch dropdown. Used by the host, which sizes the menu it
  /// places so the placement math and the drawn surface agree.
  double preferredWidthFor(BuildContext context) {
    if (!_usesVerticalLayout(context)) return preferredWidth;
    final platform = Theme.of(context).platform;
    if (isDesktopTargetPlatform(platform)) return desktopPreferredWidth;
    final actions = _actions(
      context.read<TranslationController>(),
      isDesktop: false,
      isMacOS: platform == TargetPlatform.macOS,
    );
    return mobileDropdownWidthFor(
      longestLabelWidth: _widestLabelWidth(context, actions),
      availableWidth: math.max(0.0, MediaQuery.sizeOf(context).width - 20),
    );
  }

  /// How wide the touch dropdown's widest option label draws.
  static double _widestLabelWidth(
    BuildContext context,
    List<MessageAction> actions,
  ) {
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    var widest = 0.0;
    for (final action in actions) {
      painter.text = TextSpan(
        text: AppStrings.t(action.label),
        style: const TextStyle(fontSize: mobileDropdownTextSize),
      );
      painter.layout();
      widest = math.max(widest, painter.width);
    }
    painter.dispose();
    return widest;
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions(
      context.watch<TranslationController>(),
      isDesktop: isDesktopTargetPlatform(Theme.of(context).platform),
      isMacOS: Theme.of(context).platform == TargetPlatform.macOS,
    );
    if (_usesVerticalLayout(context)) {
      return _VerticalActionList(
        actions: actions,
        onSelect: onSelect,
        compact: isDesktopTargetPlatform(Theme.of(context).platform),
      );
    }
    final rowCounts = rowCountsForActionCount(actions.length);
    final firstRowCount = rowCounts.first;
    final firstRow = actions.take(firstRowCount).toList();
    final secondRow = actions.skip(firstRowCount).toList();
    final columnCount = secondRow.isEmpty
        ? firstRow.length
        : firstRow.length > secondRow.length
        ? firstRow.length
        : secondRow.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = MediaQuery.sizeOf(context).width - 24;
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth.clamp(0.0, maxWidth)
            : maxWidth;
        final menuWidth = mobileWidthForActionCount(
          actions.length,
          availableWidth,
        );
        final actionContentWidth =
            (math.max(columnCount, 1) * _actionWidth) +
            (_horizontalPadding * 2);
        final contentWidth = math.max(menuWidth, actionContentWidth);
        final palette = MessageActionPalette.of(context);
        return Container(
          key: const ValueKey('message-action-menu-surface'),
          width: menuWidth,
          padding: const EdgeInsets.symmetric(vertical: 11),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: palette.divider, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: palette.shadow,
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: SizedBox(
              width: contentWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _horizontalPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ActionRow(
                      actions: firstRow,
                      onSelect: onSelect,
                      palette: palette,
                    ),
                    if (secondRow.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(height: 1, color: palette.divider),
                      const SizedBox(height: 10),
                      _ActionRow(
                        actions: secondRow,
                        onSelect: onSelect,
                        palette: palette,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VerticalActionList extends StatelessWidget {
  const _VerticalActionList({
    required this.actions,
    required this.onSelect,
    required this.compact,
  });

  final List<MessageAction> actions;
  final ValueChanged<MessageAction> onSelect;

  /// Draw the pointer-sized column (the desktop context menu) instead of the
  /// touch dropdown's full-size rows.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final availableWidth = MediaQuery.sizeOf(context).width - 20;
    final availableHeight = MediaQuery.sizeOf(context).height - 24;
    final width = compact
        ? math.min(MessageActionMenu.desktopPreferredWidth, availableWidth)
        : MessageActionMenu.mobileDropdownWidthFor(
            longestLabelWidth: MessageActionMenu._widestLabelWidth(
              context,
              actions,
            ),
            availableWidth: availableWidth,
          );
    final height = compact
        ? MessageActionMenu.desktopHeightForActionCount(
            actions.length,
            availableHeight: availableHeight,
          )
        : MessageActionMenu.mobileDropdownHeightForActionCount(
            actions.length,
            availableHeight: availableHeight,
          );
    final dividerInset = compact ? 10.0 : AppSpacing.lg;
    final palette = MessageActionPalette.of(context);
    return Container(
      key: const ValueKey('message-action-menu-surface'),
      width: width,
      height: height,
      padding: EdgeInsets.symmetric(
        vertical: compact ? 6 : MessageActionMenu.mobileDropdownVerticalInset,
      ),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: palette.divider, width: 0.75),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ListView.builder(
        key: const ValueKey('message-action-menu-vertical-list'),
        padding: EdgeInsets.zero,
        itemCount: actions.length,
        itemBuilder: (context, index) {
          final action = actions[index];
          final startsDestructiveGroup =
              index > 0 &&
              action.isDestructive &&
              !actions[index - 1].isDestructive;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (startsDestructiveGroup)
                Container(
                  key: const ValueKey('message-action-destructive-divider'),
                  height: 1,
                  margin: EdgeInsets.symmetric(horizontal: dividerInset),
                  color: palette.divider,
                ),
              _VerticalActionRow(
                action: action,
                compact: compact,
                palette: palette,
                onTap: () => onSelect(action),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One option of the vertical column: glyph in its slot, label, and — on
/// touch — a full-height row with a press highlight, so the whole row answers
/// a fingertip instead of only the line of type.
class _VerticalActionRow extends StatelessWidget {
  const _VerticalActionRow({
    required this.action,
    required this.compact,
    required this.palette,
    required this.onTap,
  });

  final MessageAction action;
  final bool compact;
  final MessageActionPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = action.isDestructive
        ? palette.destructive
        : palette.foreground;
    final row = SizedBox(
      height: compact
          ? MessageActionMenu._desktopActionHeight
          : MessageActionMenu.mobileDropdownRowHeight,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact
              ? AppSpacing.lg
              : MessageActionMenu.mobileDropdownHorizontalPadding,
        ),
        child: Row(
          children: [
            AppIcon(
              action.glyph,
              size: compact ? 17 : MessageActionMenu.mobileDropdownIconSize,
              color: color,
            ),
            SizedBox(
              width: compact ? 10 : MessageActionMenu.mobileDropdownIconGap,
            ),
            Expanded(
              child: Text(
                AppStrings.t(action.label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact
                      ? AppTextSize.callout
                      : MessageActionMenu.mobileDropdownTextSize,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return GestureDetector(
      key: ValueKey('message-action-${action.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: compact
          ? row
          : AppPressRipple(color: palette.foreground, child: row),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.actions,
    required this.onSelect,
    required this.palette,
  });

  final List<MessageAction> actions;
  final ValueChanged<MessageAction> onSelect;
  final MessageActionPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final action in actions)
          GestureDetector(
            key: ValueKey('message-action-${action.name}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(action),
            child: SizedBox(
              width: MessageActionMenu._actionWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (action == MessageAction.repeat)
                    SizedBox(
                      height: 22,
                      child: Center(
                        child: Text(
                          '+1',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: palette.foreground,
                          ),
                        ),
                      ),
                    )
                  else
                    AppIcon(
                      action.glyph,
                      size: 22,
                      color: action.isDestructive
                          ? palette.destructive
                          : palette.foreground,
                    ),
                  const SizedBox(height: 5),
                  Text(
                    MessageActionMenu.gridLabel(AppStrings.t(action.label)),
                    semanticsLabel: AppStrings.t(action.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: action.isDestructive
                          ? palette.destructive
                          : palette.foreground,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
