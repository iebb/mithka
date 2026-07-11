import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/rich_message_source.dart';

void main() {
  test('serializes inline formatting as Telegram rich HTML', () {
    final html = formattedTextToRichHtml('bold and secret', [
      {
        'offset': 0,
        'length': 4,
        'type': {'@type': 'textEntityTypeBold'},
      },
      {
        'offset': 9,
        'length': 6,
        'type': {'@type': 'textEntityTypeSpoiler'},
      },
    ]);

    expect(html, '<p><b>bold</b> and <tg-spoiler>secret</tg-spoiler></p>');
  });

  test('serializes checklist lines as checked and unchecked items', () {
    final html = formattedTextToRichHtml('- [x] Done\n- [ ] Next', const []);

    expect(
      html,
      '<ul><li><input type="checkbox" checked>Done</li>'
      '<li><input type="checkbox">Next</li></ul>',
    );
  });

  test('escapes table and math source content', () {
    expect(escapeRichHtml(r'x < y & z'), r'x &lt; y &amp; z');
  });
}
