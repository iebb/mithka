// Persisted representation of an item in the message quick-reaction strip.

import 'package:flutter/foundation.dart';

@immutable
class QuickReactionChoice {
  const QuickReactionChoice.emoji(this.emoji) : customEmojiId = 0;

  const QuickReactionChoice.custom(this.customEmojiId) : emoji = '';

  final String emoji;
  final int customEmojiId;

  bool get isCustom => customEmojiId != 0;

  String get storageValue =>
      isCustom ? 'custom:$customEmojiId' : 'emoji:$emoji';

  static QuickReactionChoice? fromStorage(String value) {
    if (value.startsWith('custom:')) {
      final id = int.tryParse(value.substring('custom:'.length));
      return id == null || id == 0 ? null : QuickReactionChoice.custom(id);
    }
    final emoji = value.startsWith('emoji:')
        ? value.substring('emoji:'.length)
        : value;
    return emoji.isEmpty ? null : QuickReactionChoice.emoji(emoji);
  }

  @override
  bool operator ==(Object other) =>
      other is QuickReactionChoice &&
      other.emoji == emoji &&
      other.customEmojiId == customEmojiId;

  @override
  int get hashCode => Object.hash(emoji, customEmojiId);
}

const defaultQuickReactions = <QuickReactionChoice>[
  QuickReactionChoice.emoji('👍'),
  QuickReactionChoice.emoji('❤️'),
  QuickReactionChoice.emoji('🔥'),
  QuickReactionChoice.emoji('🎉'),
  QuickReactionChoice.emoji('😁'),
  QuickReactionChoice.emoji('😢'),
  QuickReactionChoice.emoji('😡'),
];

List<QuickReactionChoice> effectiveQuickReactions(
  Iterable<QuickReactionChoice> configured, {
  required bool allowCustomEmoji,
}) {
  final available = configured
      .where((reaction) => allowCustomEmoji || !reaction.isCustom)
      .toList(growable: false);
  return available.isEmpty ? defaultQuickReactions : available;
}

const availableStandardReactions = <String>[
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
