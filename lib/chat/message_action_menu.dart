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

import '../components/app_icons.dart';
import '../platform/adaptive_platform.dart';
import '../settings/translation_controller.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'custom_emoji.dart';
import 'emoji_store.dart';
import 'quick_reaction_choice.dart';

enum MessageAction {
  copy(HeroAppIcons.file, AppStringKeys.messageActionCopy),
  edit(HeroAppIcons.pen, AppStringKeys.messageActionEdit),
  suggestOffer(HeroAppIcons.penToSquare, AppStringKeys.suggestedPostEditOffer),
  translate(HeroAppIcons.language, AppStringKeys.messageActionTranslate),
  displayOriginal(HeroAppIcons.eye, AppStringKeys.messageActionDisplayOriginal),
  displayTranslation(
    HeroAppIcons.language,
    AppStringKeys.messageActionDisplayTranslation,
  ),
  reply(HeroAppIcons.quoteLeft, AppStringKeys.chatInputBarReply),
  replies(HeroAppIcons.comments, AppStringKeys.messageActionReplies),
  forward(HeroAppIcons.forward, AppStringKeys.messageActionForward),
  repeat(HeroAppIcons.circlePlus, AppStringKeys.messageActionRepeat),
  report(HeroAppIcons.triangleExclamation, AppStringKeys.messageActionReport),
  block(HeroAppIcons.ban, AppStringKeys.messageActionBlock),
  playMuted(HeroAppIcons.volumeXmark, AppStringKeys.messageActionPlayMuted),
  addToPlaylist(HeroAppIcons.music, AppStringKeys.musicPlayerAddToPlaylist),
  saveToPhotos(HeroAppIcons.download, AppStringKeys.messageActionSaveToPhotos),
  multiSelect(HeroAppIcons.circleCheck, AppStringKeys.messageActionMultiSelect),
  pinTodo(HeroAppIcons.thumbtack, AppStringKeys.messageActionSetTodo),
  unpinTodo(HeroAppIcons.thumbtack, AppStringKeys.messageActionUnsetTodo),
  save(HeroAppIcons.solidStar, AppStringKeys.messageActionFavorite),
  saveSticker(HeroAppIcons.circlePlus, AppStringKeys.imageEditAdd),
  viewStickerSet(HeroAppIcons.tableCells, AppStringKeys.messageActionSticker),
  delete(HeroAppIcons.trash, AppStringKeys.chatDelete);

  const MessageAction(this.glyph, this.label);
  final AppIconData glyph;
  final String label;

  bool get isDestructive =>
      this == MessageAction.delete ||
      this == MessageAction.report ||
      this == MessageAction.block;
}

enum MessageActionSource { normal, video }

enum MessageActionMenuLayout { adaptive, grid, vertical }

class QuickReactionBar extends StatelessWidget {
  const QuickReactionBar({
    super.key,
    required this.reactions,
    required this.onReaction,
    required this.onExpand,
  });

  static const maxFittedButtonCount = 10;

  final List<QuickReactionChoice> reactions;
  final ValueChanged<QuickReactionChoice> onReaction;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final buttonCount = reactions.length + 1;
    return Container(
      key: const ValueKey('quick-reaction-bar'),
      width: MessageActionMenu.widthForAvailable(
        MediaQuery.sizeOf(context).width - 24,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final buttons = <Widget>[
            for (final emoji in reactions) _reactionButton(emoji),
            _expandButton(),
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

  Widget _reactionButton(QuickReactionChoice reaction) {
    return GestureDetector(
      key: ValueKey('quick-reaction-${reaction.storageValue}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => onReaction(reaction),
      child: SizedBox(
        width: 40,
        height: 34,
        child: Center(
          child: reaction.isCustom
              ? CustomEmojiView(
                  id: reaction.customEmojiId,
                  size: 28,
                  color: Colors.white,
                )
              : Text(
                  reaction.emoji,
                  textScaler: TextScaler.noScaling,
                  style: const TextStyle(fontSize: 28),
                ),
        ),
      ),
    );
  }

  Widget _expandButton() {
    return GestureDetector(
      key: const ValueKey('quick-reaction-expand'),
      behavior: HitTestBehavior.opaque,
      onTap: onExpand,
      child: SizedBox(
        width: 40,
        height: 34,
        child: Center(
          child: Container(
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
    this.allowSuggestedPostOffer = false,
    this.source = MessageActionSource.normal,
    this.showingOriginalTranslation = false,
    this.layout = MessageActionMenuLayout.adaptive,
  });
  final ChatMessage message;
  final bool isPinned;
  final ValueChanged<MessageAction> onSelect;
  final bool allowForwarding;
  final bool allowTranslation;
  final bool allowSuggestedPostOffer;
  final MessageActionSource source;
  final bool showingOriginalTranslation;
  final MessageActionMenuLayout layout;

  static const _surface = Color(0xFF2C2C2E);
  static const _destructive = Color(0xFFFF6961);
  static const _horizontalPadding = 6.0;
  static const _actionWidth = 58.0;
  static const _maxContentSizedActionCount = 10;
  static const preferredWidth = 332.0;
  static const preferredHeight = 152.0;
  static const desktopPreferredWidth = 220.0;
  static const _desktopActionHeight = 36.0;
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

  List<MessageAction> _actions(TranslationController translation) {
    if (message.isCall) return [MessageAction.delete];
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
    if (!_hasCopyableText && message.isOutgoing && _isEditableMessage) {
      result.add(MessageAction.edit);
    }
    if (allowSuggestedPostOffer && !message.isService && _isEditableMessage) {
      result.add(MessageAction.suggestOffer);
    }
    result.add(MessageAction.reply);
    if (message.hasActualReplies) {
      result.add(MessageAction.replies);
    }
    if (allowForwarding) {
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
      result.add(MessageAction.saveToPhotos);
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
    result.add(MessageAction.delete);
    return result;
  }

  double preferredHeightFor(BuildContext context) {
    if (!_usesVerticalLayout(context)) {
      return preferredHeight;
    }
    return desktopHeightForActionCount(
      _actions(context.read<TranslationController>()).length,
      availableHeight: MediaQuery.sizeOf(context).height - 24,
    );
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions(context.watch<TranslationController>());
    if (_usesVerticalLayout(context)) {
      return _VerticalActionList(actions: actions, onSelect: onSelect);
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
        final maxWidth = MediaQuery.of(context).size.width - 24;
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
        return Container(
          key: const ValueKey('message-action-menu-surface'),
          width: menuWidth,
          padding: const EdgeInsets.symmetric(vertical: 11),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
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
                    _ActionRow(actions: firstRow, onSelect: onSelect),
                    if (secondRow.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      const SizedBox(height: 10),
                      _ActionRow(actions: secondRow, onSelect: onSelect),
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
  const _VerticalActionList({required this.actions, required this.onSelect});

  final List<MessageAction> actions;
  final ValueChanged<MessageAction> onSelect;

  @override
  Widget build(BuildContext context) {
    final availableWidth = MediaQuery.sizeOf(context).width - 20;
    final availableHeight = MediaQuery.sizeOf(context).height - 24;
    final width = math.min(
      MessageActionMenu.desktopPreferredWidth,
      availableWidth,
    );
    final height = MessageActionMenu.desktopHeightForActionCount(
      actions.length,
      availableHeight: availableHeight,
    );
    return Container(
      key: const ValueKey('message-action-menu-surface'),
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: MessageActionMenu._surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.22),
          width: 0.75,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
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
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              GestureDetector(
                key: ValueKey('message-action-${action.name}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(action),
                child: SizedBox(
                  height: MessageActionMenu._desktopActionHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        AppIcon(
                          action.glyph,
                          size: 17,
                          color: action.isDestructive
                              ? MessageActionMenu._destructive
                              : Colors.white,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            AppStrings.t(action.label),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: action.isDestructive
                                  ? MessageActionMenu._destructive
                                  : Colors.white,
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
        },
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.actions, required this.onSelect});

  final List<MessageAction> actions;
  final ValueChanged<MessageAction> onSelect;

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
                    const SizedBox(
                      height: 22,
                      child: Center(
                        child: Text(
                          '+1',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    )
                  else
                    AppIcon(
                      action.glyph,
                      size: 22,
                      color: action.isDestructive
                          ? MessageActionMenu._destructive
                          : Colors.white,
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
                          ? MessageActionMenu._destructive
                          : Colors.white,
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
