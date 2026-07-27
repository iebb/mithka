import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/rich_text_format.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  test('a single pipe is not parsed as a markdown table', () {
    final message = TDParse.message({
      'id': 1,
      'date': 1,
      'content': {
        '@type': 'messageText',
        'text': {'@type': 'formattedText', 'text': '|'},
      },
    });

    expect(message, isNotNull);
    expect(message!.text, '|');
    expect(message.richBlocks, isEmpty);
  });

  test('explicit TDLib markdown double underscores produce italic', () {
    final formatted = parseTelegramMarkdown('__italic__');
    expect(formatted.text, 'italic');
    expect(formatted.entities.single['type'], {
      '@type': 'textEntityTypeItalic',
    });

    final message = TDParse.message({
      'id': 2,
      'date': 1,
      'content': {
        '@type': 'messageText',
        'text': {'@type': 'formattedText', 'text': '__italic__'},
      },
    });
    expect(message, isNotNull);
    expect(message!.text, '__italic__');
    expect(message.textEntities, isEmpty);
  });

  test('authored Markdown uses TDLib as the parsing authority', () async {
    Map<String, dynamic>? request;
    final formatted = await parseTelegramMarkdownWithTdLib(
      '__hello__',
      query: (value) async {
        request = value;
        return {
          '@type': 'formattedText',
          'text': 'hello',
          'entities': [
            {
              '@type': 'textEntity',
              'offset': 0,
              'length': 5,
              'type': {'@type': 'textEntityTypeItalic'},
            },
          ],
        };
      },
    );

    expect(request?['@type'], 'parseMarkdown');
    expect((request?['text'] as Map<String, dynamic>)['text'], '__hello__');
    expect(formatted.text, 'hello');
    expect(formatted.entities.single['type'], {
      '@type': 'textEntityTypeItalic',
    });
  });

  test('text entity round-trip preserves current TDLib type payloads', () {
    final entities = TDParse.textEntities({
      '@type': 'formattedText',
      'text': '01:23 tomorrow',
      'entities': [
        {
          '@type': 'textEntity',
          'offset': 0,
          'length': 5,
          'type': {
            '@type': 'textEntityTypeMediaTimestamp',
            'media_timestamp': 83,
          },
        },
        {
          '@type': 'textEntity',
          'offset': 6,
          'length': 8,
          'type': {
            '@type': 'textEntityTypeDateTime',
            'unix_time': 1647531900,
            'formatting_type': {'@type': 'dateTimeFormattingTypeRelative'},
          },
        },
      ],
    });

    expect(entities, hasLength(2));
    expect(entities[0].toTdJson()['type'], {
      '@type': 'textEntityTypeMediaTimestamp',
      'media_timestamp': 83,
    });
    expect(entities[1].toTdJson()['type'], {
      '@type': 'textEntityTypeDateTime',
      'unix_time': 1647531900,
      'formatting_type': {'@type': 'dateTimeFormattingTypeRelative'},
    });
  });
}
