//
//  sticker_item_parse_test.dart
//
//  parseStickers fixture coverage: set_id flows into StickerItem.setId and
//  stays 0 when TDLib omits it, .tgs marks the sticker animated, and a
//  stickerFullTypeCustomEmoji full_type carries its custom_emoji_id through.
//

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/stickers/custom_emoji.dart';

/// Same shape as emoji_store_owner_test's _stickerSet(): @type sticker, the
/// file object, format, width/height, emoji, and full_type.
Map<String, dynamic> _sticker({
  int? setId,
  String format = 'stickerFormatWebp',
  Map<String, dynamic>? fullType,
}) => {
  '@type': 'sticker',
  'set_id': ?setId,
  'sticker': {'@type': 'file', 'id': 9001},
  'format': {'@type': format},
  'width': 512,
  'height': 512,
  'emoji': '🙂',
  'full_type': fullType ?? {'@type': 'stickerFullTypeRegular'},
};

void main() {
  test('sticker without set_id parses to setId 0', () {
    final items = parseStickers([_sticker()]);
    expect(items, hasLength(1));
    expect(items.single.setId, 0);
  });

  test('sticker set_id is carried through', () {
    final items = parseStickers([_sticker(setId: 12345)]);
    expect(items, hasLength(1));
    expect(items.single.setId, 12345);
  });

  test('stickerFormatTgs marks the sticker animated', () {
    final items = parseStickers([_sticker(format: 'stickerFormatTgs')]);
    expect(items.single.isAnimated, isTrue);
    expect(items.single.isVideo, isFalse);
  });

  test('custom emoji full_type carries custom_emoji_id', () {
    final items = parseStickers([
      _sticker(
        fullType: {
          '@type': 'stickerFullTypeCustomEmoji',
          'custom_emoji_id': 777,
          'needs_repainting': false,
        },
      ),
    ]);
    expect(items.single.customEmojiId, 777);
  });
}
