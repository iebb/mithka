//
//  message_action_menu.dart
//
//  The dark, rounded HUD menu shown when a message bubble is long-pressed. A
//  grid of context actions (复制 / 引用 / 转发 / 收藏 / 删除, plus 存表情 for
//  stickers). Fixed dark colors on purpose — a floating HUD, not themed surface.
//  Port of the Swift `MessageActionMenu`.
//

import 'package:flutter/material.dart';

import '../components/sf_symbols.dart';
import '../tdlib/td_models.dart';

enum MessageAction {
  copy('doc', '复制'),
  reply('arrowshape.turn.up.left', '引用'),
  forward('arrowshape.turn.up.left', '转发'),
  save('star.fill', '收藏'),
  saveSticker('plus.circle', '添加'),
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
    required this.onSelect,
  });
  final ChatMessage message;
  final ValueChanged<MessageAction> onSelect;

  static const _surface = Color(0xFF2C2C2E);
  static const _destructive = Color(0xFFFF6961);

  bool get _isTextMessage =>
      message.image == null &&
      message.document == null &&
      message.animatedSticker == null;

  List<MessageAction> get _actions {
    // Call logs / special messages: only 删除 (no copy/reply/forward/react).
    if (message.isCall) return [MessageAction.delete];
    final result = <MessageAction>[];
    if (_isTextMessage && message.text.isNotEmpty) {
      result.add(MessageAction.copy);
    }
    result.add(MessageAction.reply);
    result.add(MessageAction.forward);
    result.add(MessageAction.save);
    // 添加 — add any sticker (tgs / webm / webp) to favorites.
    if (message.stickerFileId != null) result.add(MessageAction.saveSticker);
    result.add(MessageAction.delete);
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions;
    // A single content-width row — never pad out to a second row when there
    // are only a handful of actions. Wraps to a second line only past 5.
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
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
      child: Wrap(
        alignment: WrapAlignment.center,
        children: [
          for (final action in actions)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(action),
              child: SizedBox(
                width: 56,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      sfIcon(action.glyph),
                      size: 22,
                      color: action.isDestructive ? _destructive : Colors.white,
                    ),
                    const SizedBox(height: 7),
                    Text(
                      action.label,
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
    );
  }
}
