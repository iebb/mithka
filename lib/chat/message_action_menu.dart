//
//  message_action_menu.dart
//
//  The dark, rounded HUD menu shown when a message bubble is long-pressed. A
//  grid of context actions (复制 / 引用 / 转发 / 收藏 / 删除, plus 存表情 for
//  stickers). Fixed dark colors on purpose — a floating HUD, not themed surface.
//  Port of the Swift `MessageActionMenu`.
//

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../components/app_icons.dart';
import '../l10n/telegram_language_controller.dart';
import '../settings/translation_controller.dart';
import '../tdlib/td_models.dart';
import 'emoji_store.dart';

enum MessageAction {
  copy(HeroAppIcons.file, AppStringKeys.messageActionCopy),
  selectText(HeroAppIcons.font, AppStringKeys.messageActionSelectText),
  edit(HeroAppIcons.pen, AppStringKeys.messageActionEdit),
  translate(HeroAppIcons.language, AppStringKeys.messageActionTranslate),
  reply(HeroAppIcons.quoteLeft, AppStringKeys.messageActionQuote),
  replies(HeroAppIcons.comments, AppStringKeys.messageActionReplies),
  forward(HeroAppIcons.share, AppStringKeys.messageActionForward),
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

class MessageActionMenu extends StatelessWidget {
  const MessageActionMenu({
    super.key,
    required this.message,
    required this.isPinned,
    required this.onSelect,
    this.source = MessageActionSource.normal,
  });
  final ChatMessage message;
  final bool isPinned;
  final ValueChanged<MessageAction> onSelect;
  final MessageActionSource source;

  static const _surface = Color(0xFF2C2C2E);
  static const _destructive = Color(0xFFFF6961);
  static const _horizontalPadding = 8.0;
  static const _actionWidth = 68.0;
  static const preferredHeight = 152.0;

  bool get _isEditableTextMessage =>
      message.text.isNotEmpty &&
      (message.contentType == 'messageText' ||
       message.contentType == 'messagePhoto' ||
       message.contentType == 'messageVideo');

  bool get _hasCopyableText => message.text.trim().isNotEmpty;

  List<MessageAction> _actions(bool translationEnabled) {
    // Call logs / special messages: only 删除 (no copy/reply/forward/react).
    if (message.isCall) return [MessageAction.delete];
    final result = <MessageAction>[];
    if (_hasCopyableText) {
      result.add(MessageAction.copy);
      result.add(MessageAction.selectText);
      if (message.isOutgoing && _isEditableTextMessage) {
        result.add(MessageAction.edit);
      }
      if (translationEnabled) result.add(MessageAction.translate);
    }
    result.add(MessageAction.reply);
    if (message.hasActualReplies) {
      result.add(MessageAction.replies);
    }
    result.add(MessageAction.forward);
    if (message.video != null && source == MessageActionSource.video) {
      result.add(MessageAction.playMuted);
    }
    if (message.music?.file != null) {
      result.add(MessageAction.addToPlaylist);
    }
    if (message.isPhoto || message.video != null) {
      result.add(MessageAction.saveToPhotos);
    }
    result.add(MessageAction.multiSelect);
    result.add(isPinned ? MessageAction.unpinTodo : MessageAction.pinTodo);
    result.add(MessageAction.save);
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

  @override
  Widget build(BuildContext context) {
    final actions = _actions(context.watch<TranslationController>().enabled);
    final firstRowCount = actions.length <= 5
        ? actions.length
        : actions.length <= 10
        ? 5
        : (actions.length + 1) ~/ 2;
    final firstRow = actions.take(firstRowCount).toList();
    final secondRow = actions.skip(firstRowCount).toList();
    final columnCount = secondRow.isEmpty
        ? firstRow.length
        : firstRow.length > secondRow.length
        ? firstRow.length
        : secondRow.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = (MediaQuery.of(context).size.width - 24) * 0.8;
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth.clamp(0.0, maxWidth)
            : maxWidth;
        final contentWidth =
            (math.max(columnCount, 1) * _actionWidth) +
            (_horizontalPadding * 2);
        final menuWidth = contentWidth.clamp(0.0, availableWidth);
        return Container(
          width: menuWidth,
          padding: const EdgeInsets.symmetric(vertical: 13),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(16),
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
                      const SizedBox(height: 12),
                      Container(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      const SizedBox(height: 12),
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
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(action),
            child: SizedBox(
              width: MessageActionMenu._actionWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    action.glyph,
                    size: 22,
                    color: action.isDestructive
                        ? MessageActionMenu._destructive
                        : Colors.white,
                  ),
                  const SizedBox(height: 7),
                  Text(
                    telegramText(action.label),
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
