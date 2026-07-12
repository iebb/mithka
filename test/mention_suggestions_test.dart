import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/emoji_text_controller.dart';

void main() {
  group('mention query detection', () {
    test('finds an active mention at the cursor', () {
      final query = activeMentionQuery(
        'hello @nat',
        const TextSelection.collapsed(offset: 10),
      );

      expect(query, isNotNull);
      expect(query!.start, 6);
      expect(query.end, 10);
      expect(query.query, 'nat');
    });

    test('opens the menu immediately after at-sign', () {
      final query = activeMentionQuery(
        '@',
        const TextSelection.collapsed(offset: 1),
      );

      expect(query?.query, isEmpty);
    });

    test('does not treat email addresses or selections as mention queries', () {
      expect(
        activeMentionQuery(
          'mail@example.com',
          const TextSelection.collapsed(offset: 16),
        ),
        isNull,
      );
      expect(
        activeMentionQuery(
          '@natu',
          const TextSelection(baseOffset: 1, extentOffset: 5),
        ),
        isNull,
      );
    });
  });

  test('selected member is inserted as an ID-backed mention', () {
    final controller = EmojiTextEditingController();
    addTearDown(controller.dispose);
    controller.value = const TextEditingValue(
      text: 'hello @na later',
      selection: TextSelection.collapsed(offset: 9),
    );

    controller.insertTextMention(
      start: 6,
      end: 9,
      label: 'Natu Profile',
      userId: 123456,
    );

    final (text, entities) = controller.toFormatted();
    expect(text, 'hello @Natu Profile later');
    expect(controller.selection.extentOffset, 20);
    expect(entities, hasLength(1));
    expect(entities.single['offset'], 6);
    expect(entities.single['length'], '@Natu Profile'.length);
    expect(entities.single['type'], {
      '@type': 'textEntityTypeMentionName',
      'user_id': 123456,
    });
  });
}
