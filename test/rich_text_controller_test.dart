import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/emoji_text_controller.dart';

void main() {
  group('EmojiTextEditingController rich text', () {
    test('toggles selected formatting into TDLib entities', () {
      final controller = EmojiTextEditingController();
      addTearDown(controller.dispose);

      controller.text = 'hello world';
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      controller.toggleFormat('textEntityTypeBold');

      final (text, entities) = controller.toFormatted();
      expect(text, 'hello world');
      expect(entities, hasLength(1));
      expect(entities.single['offset'], 0);
      expect(entities.single['length'], 5);
      expect(entities.single['type'], {'@type': 'textEntityTypeBold'});

      controller.toggleFormat('textEntityTypeBold');
      expect(controller.toFormatted().$2, isEmpty);
    });

    test('remaps formatting offsets across custom emoji fallback text', () {
      final controller = EmojiTextEditingController();
      addTearDown(controller.dispose);

      controller.text = 'a ';
      controller.selection = const TextSelection.collapsed(offset: 2);
      controller.insertCustomEmoji(123, '🙂');
      controller.insertText(' b');
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
      controller.toggleFormat('textEntityTypeItalic');

      final (text, entities) = controller.toFormatted();
      expect(text, 'a 🙂 b');
      expect(
        entities,
        contains(
          allOf([
            containsPair('offset', 2),
            containsPair('length', '🙂'.length),
            containsPair('type', {
              '@type': 'textEntityTypeCustomEmoji',
              'custom_emoji_id': '123',
            }),
          ]),
        ),
      );
      expect(
        entities,
        contains(
          allOf([
            containsPair('offset', 0),
            containsPair('length', text.length),
            containsPair('type', {'@type': 'textEntityTypeItalic'}),
          ]),
        ),
      );
    });

    test('shifts entity ranges when editing before formatted text', () {
      final controller = EmojiTextEditingController();
      addTearDown(controller.dispose);

      controller.text = 'hello';
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 4,
      );
      controller.toggleFormat('textEntityTypeUnderline');
      controller.selection = const TextSelection.collapsed(offset: 0);
      controller.insertText('A');

      final (text, entities) = controller.toFormatted();
      expect(text, 'Ahello');
      expect(entities, hasLength(1));
      expect(entities.single['offset'], 2);
      expect(entities.single['length'], 3);
      expect(entities.single['type'], {'@type': 'textEntityTypeUnderline'});
    });

    test('rehydrates formatting metadata for message editing', () {
      final controller = EmojiTextEditingController();
      addTearDown(controller.dispose);

      controller.setFormattedText('open link', [
        {
          '@type': 'textEntity',
          'offset': 5,
          'length': 4,
          'type': {
            '@type': 'textEntityTypeTextUrl',
            'url': 'https://example.com',
          },
        },
      ]);

      final (text, entities) = controller.toFormatted();
      expect(text, 'open link');
      expect(entities, hasLength(1));
      expect(entities.single['offset'], 5);
      expect(entities.single['length'], 4);
      expect(entities.single['type'], {
        '@type': 'textEntityTypeTextUrl',
        'url': 'https://example.com',
      });
    });

    test('applies a text link to the selected range', () {
      final controller = EmojiTextEditingController();
      addTearDown(controller.dispose);

      controller.text = 'open Mithka';
      controller.applyEntityFormat(5, 11, {
        '@type': 'textEntityTypeTextUrl',
        'url': 'https://mithka.ieb.app',
      });

      final (text, entities) = controller.toFormatted();
      expect(text, 'open Mithka');
      expect(entities, hasLength(1));
      expect(entities.single['offset'], 5);
      expect(entities.single['length'], 6);
      expect(entities.single['type'], {
        '@type': 'textEntityTypeTextUrl',
        'url': 'https://mithka.ieb.app',
      });
    });

    test('keeps adjacent parameterized entities distinct after edits', () {
      final controller = EmojiTextEditingController();
      addTearDown(controller.dispose);

      controller.setFormattedText('oneTwo', [
        {
          '@type': 'textEntity',
          'offset': 0,
          'length': 3,
          'type': {
            '@type': 'textEntityTypeTextUrl',
            'url': 'https://one.example',
          },
        },
        {
          '@type': 'textEntity',
          'offset': 3,
          'length': 3,
          'type': {
            '@type': 'textEntityTypeTextUrl',
            'url': 'https://two.example',
          },
        },
      ]);

      // Simulate a keyboard edit so the controller normalizes all ranges.
      controller.value = const TextEditingValue(
        text: 'oneTwo!',
        selection: TextSelection.collapsed(offset: 7),
      );

      final (_, entities) = controller.toFormatted();
      expect(entities, hasLength(2));
      expect(entities[0]['offset'], 0);
      expect(entities[0]['length'], 3);
      expect(entities[0]['type'], {
        '@type': 'textEntityTypeTextUrl',
        'url': 'https://one.example',
      });
      expect(entities[1]['offset'], 3);
      expect(entities[1]['length'], 3);
      expect(entities[1]['type'], {
        '@type': 'textEntityTypeTextUrl',
        'url': 'https://two.example',
      });
    });

    test('rehydrates custom emoji while preserving enclosing formats', () {
      final controller = EmojiTextEditingController();
      addTearDown(controller.dispose);
      const source = 'a 🙂 b';

      controller.setFormattedText(source, [
        {
          '@type': 'textEntity',
          'offset': 2,
          'length': 2,
          'type': {
            '@type': 'textEntityTypeCustomEmoji',
            'custom_emoji_id': '123',
          },
        },
        {
          '@type': 'textEntity',
          'offset': 0,
          'length': source.length,
          'type': {'@type': 'textEntityTypeBold'},
        },
      ]);

      final (text, entities) = controller.toFormatted();
      expect(text, source);
      expect(
        entities,
        contains(
          allOf([
            containsPair('offset', 2),
            containsPair('length', 2),
            containsPair('type', {
              '@type': 'textEntityTypeCustomEmoji',
              'custom_emoji_id': '123',
            }),
          ]),
        ),
      );
      expect(
        entities,
        contains(
          allOf([
            containsPair('offset', 0),
            containsPair('length', source.length),
            containsPair('type', {'@type': 'textEntityTypeBold'}),
          ]),
        ),
      );
    });
  });
}
