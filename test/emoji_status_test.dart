import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  group('TDParse.emojiStatusCustomEmojiId', () {
    test('parses a regular custom emoji status', () {
      final id = TDParse.emojiStatusCustomEmojiId({
        '@type': 'emojiStatus',
        'type': {
          '@type': 'emojiStatusTypeCustomEmoji',
          'custom_emoji_id': '123456789',
        },
      });

      expect(id, 123456789);
    });

    test('uses the model emoji for an upgraded gift status', () {
      final id = TDParse.emojiStatusCustomEmojiId({
        '@type': 'emojiStatus',
        'type': {
          '@type': 'emojiStatusTypeUpgradedGift',
          'upgraded_gift_id': '99',
          'model_custom_emoji_id': '987654321',
          'symbol_custom_emoji_id': '111222333',
        },
      });

      expect(id, 987654321);
    });

    test('keeps compatibility with the legacy flat status shape', () {
      expect(
        TDParse.emojiStatusCustomEmojiId({
          '@type': 'emojiStatus',
          'custom_emoji_id': '42',
        }),
        42,
      );
    });
  });
}
