//
//  message_action_menu.dart
//
//  The dark, rounded HUD menu shown when a message bubble is long-pressed. A
//  grid of context actions (复制 / 引用 / 转发 / 收藏 / 删除, plus 存表情 for
//  stickers). Fixed dark colors on purpose — a floating HUD, not themed surface.
//  Port of the Swift `MessageActionMenu`.
//

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/sf_symbols.dart';
import '../settings/translation_controller.dart';
import '../tdlib/td_models.dart';
import 'emoji_store.dart';

enum MessageAction {
  copy('doc', '复制'),
  edit('pencil', '编辑'),
  translate('character.book.closed', '翻译'),
  reply('quote.bubble', '引用'),
  forward('arrowshape.turn.up.right', '转发'),
  playPiP('pip.enter', '画中画'),
  playSplit('rectangle.split.2x1', '分屏'),
  multiSelect('checkmark.circle', '多选'),
  pinTodo('pin.fill', '设为待办'),
  unpinTodo('pin.fill', '撤回待办'),
  save('star.fill', '收藏'),
  saveSticker('plus.circle', '添加'),
  viewStickerSet('square.grid.2x2', '表情包'),
  delete('trash', '删除');

  const MessageAction(this.glyph, this.label);
  final String glyph;
  final String label;

  bool get isDestructive => this == MessageAction.delete;
}

class MessageActionMenu extends StatelessWidget {
  const MessageActionMenu({
    super.key,
    required this.message,
    required this.isPinned,
    required this.onSelect,
  });
  final ChatMessage message;
  final bool isPinned;
  final ValueChanged<MessageAction> onSelect;

  static const _surface = Color(0xFF2C2C2E);
  static const _destructive = Color(0xFFFF6961);

  bool get _isTextMessage =>
      message.image == null &&
      message.document == null &&
      message.animatedSticker == null;

  bool get _isEditableTextMessage =>
      message.contentType == 'messageText' && message.text.isNotEmpty;

  List<MessageAction> _actions(bool translationEnabled) {
    // Call logs / special messages: only 删除 (no copy/reply/forward/react).
    if (message.isCall) return [MessageAction.delete];
    final result = <MessageAction>[];
    if (_isTextMessage && message.text.isNotEmpty) {
      result.add(MessageAction.copy);
      if (message.isOutgoing && _isEditableTextMessage) {
        result.add(MessageAction.edit);
      }
      if (translationEnabled) result.add(MessageAction.translate);
    }
    result.add(MessageAction.reply);
    result.add(MessageAction.forward);
    if (message.video != null) {
      result.add(MessageAction.playPiP);
      result.add(MessageAction.playSplit);
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
    // A single content-width row — never pad out to a second row when there
    // are only a handful of actions. Wraps to a second line only past 5.
    // Single horizontal row (scrolls if it ever overflows) — never a 5+1 wrap.
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width - 24,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final action in actions)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(action),
                child: SizedBox(
                  width: 52,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        sfIcon(action.glyph),
                        size: 22,
                        color: action.isDestructive
                            ? _destructive
                            : Colors.white,
                      ),
                      const SizedBox(height: 7),
                      Text(
                        action.label,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 12,
                          color: action.isDestructive
                              ? _destructive
                              : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
