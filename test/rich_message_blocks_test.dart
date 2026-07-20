import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/tdlib/td_models.dart';

Map<String, dynamic> _plain(String text) => {
  '@type': 'richTextPlain',
  'text': text,
};

Map<String, dynamic> _caption(String text) => {
  '@type': 'pageBlockCaption',
  'text': _plain(text),
};

Map<String, dynamic> _file(int id) => {
  '@type': 'file',
  'id': id,
  'local': {
    '@type': 'localFile',
    'path': '/tmp/$id.bin',
    'is_downloading_completed': true,
  },
};

Map<String, dynamic> _photo(int id) => {
  '@type': 'photo',
  'sizes': [
    {'@type': 'photoSize', 'width': 640, 'height': 480, 'photo': _file(id)},
  ],
};

Map<String, dynamic> _video(int id) => {
  '@type': 'video',
  'duration': 12,
  'width': 640,
  'height': 360,
  'video': _file(id),
};

Map<String, dynamic> _animation(int id) => {
  '@type': 'animation',
  'duration': 4,
  'width': 320,
  'height': 240,
  'animation': _file(id),
};

void main() {
  test('parses every TDLib rich message block kind without flattening it', () {
    final message = TDParse.message({
      '@type': 'message',
      'id': 500,
      'chat_id': 42,
      'date': 1,
      'is_outgoing': false,
      'content': {
        '@type': 'messageRichMessage',
        'message': {
          '@type': 'richMessage',
          'is_full': true,
          'blocks': [
            {'@type': 'pageBlockParagraph', 'text': _plain('Paragraph')},
            {
              '@type': 'pageBlockSectionHeading',
              'text': _plain('Heading'),
              'size': 2,
            },
            {
              '@type': 'pageBlockPreformatted',
              'text': _plain('code()'),
              'language': 'dart',
            },
            {'@type': 'pageBlockFooter', 'footer': _plain('Footer')},
            {'@type': 'pageBlockThinking', 'text': _plain('Thinking')},
            {'@type': 'pageBlockDivider'},
            {'@type': 'pageBlockMathematicalExpression', 'expression': r'x^2'},
            {'@type': 'pageBlockAnchor', 'name': 'chapter-1'},
            {
              '@type': 'pageBlockList',
              'items': [
                {
                  '@type': 'pageBlockListItem',
                  'label': '1.',
                  'blocks': [
                    {'@type': 'pageBlockParagraph', 'text': _plain('Item')},
                  ],
                  'has_checkbox': true,
                  'is_checked': true,
                  'value': 1,
                  'type': '1',
                },
              ],
            },
            {
              '@type': 'pageBlockBlockQuote',
              'blocks': [
                {'@type': 'pageBlockParagraph', 'text': _plain('Quote')},
              ],
              'credit': _plain('Credit'),
            },
            {
              '@type': 'pageBlockPullQuote',
              'text': _plain('Pull quote'),
              'credit': _plain('Credit'),
            },
            {
              '@type': 'pageBlockAnimation',
              'animation': _animation(11),
              'caption': _caption('Animation'),
              'has_spoiler': false,
            },
            {
              '@type': 'pageBlockAudio',
              'audio': {
                '@type': 'audio',
                'file_name': 'song.mp3',
                'duration': 30,
                'title': 'Song',
                'performer': 'Artist',
                'audio': _file(12),
              },
              'caption': _caption('Audio'),
            },
            {
              '@type': 'pageBlockPhoto',
              'photo': _photo(13),
              'caption': _caption('Photo'),
              'has_spoiler': true,
            },
            {
              '@type': 'pageBlockVideo',
              'video': _video(14),
              'caption': _caption('Video'),
              'has_spoiler': false,
            },
            {
              '@type': 'pageBlockVoiceNote',
              'voice_note': {
                '@type': 'voiceNote',
                'duration': 8,
                'voice': _file(15),
              },
              'caption': _caption('Voice'),
            },
            {
              '@type': 'pageBlockCollage',
              'blocks': [
                {
                  '@type': 'pageBlockPhoto',
                  'photo': _photo(16),
                  'has_spoiler': false,
                },
              ],
              'caption': _caption('Collage'),
            },
            {
              '@type': 'pageBlockSlideshow',
              'blocks': [
                {
                  '@type': 'pageBlockVideo',
                  'video': _video(17),
                  'has_spoiler': false,
                },
              ],
              'caption': _caption('Slideshow'),
            },
            {
              '@type': 'pageBlockTable',
              'caption': _plain('Table'),
              'cells': [
                [
                  {
                    '@type': 'pageBlockTableCell',
                    'text': _plain('Cell'),
                    'is_header': true,
                    'colspan': 1,
                    'rowspan': 1,
                    'align': {'@type': 'pageBlockHorizontalAlignmentLeft'},
                    'valign': {'@type': 'pageBlockVerticalAlignmentTop'},
                  },
                ],
              ],
              'is_bordered': true,
              'is_striped': false,
            },
            {
              '@type': 'pageBlockDetails',
              'header': _plain('Details'),
              'blocks': [
                {'@type': 'pageBlockParagraph', 'text': _plain('Inside')},
              ],
              'is_open': true,
            },
            {
              '@type': 'pageBlockMap',
              'location': {
                '@type': 'location',
                'latitude': 35.681236,
                'longitude': 139.767125,
              },
              'zoom': 17,
              'width': 640,
              'height': 360,
              'caption': _caption('Tokyo'),
            },
          ],
        },
      },
    });

    expect(message, isNotNull);
    expect(message!.text, isEmpty);
    expect(message.textEntities, isEmpty);
    expect(message.richBlocks.map((block) => block.kind), [
      ...RichMessageBlockKind.values,
    ]);
    expect(message.richBlocks[1].size, 2);
    expect(message.richBlocks[2].language, 'dart');
    expect(message.richBlocks[8].listItems.single.isChecked, isTrue);
    expect(message.richBlocks[11].video?.id, 11);
    expect(message.richBlocks[12].music?.file?.id, 12);
    expect(message.richBlocks[13].image?.id, 13);
    expect(message.richBlocks[13].hasSpoiler, isTrue);
    expect(message.richBlocks[14].video?.id, 14);
    expect(message.richBlocks[15].voice?.file?.id, 15);
    expect(message.richBlocks[16].children.single.image?.id, 16);
    expect(message.richBlocks[17].children.single.video?.id, 17);
    expect(message.richBlocks[18].tableRows.single.single.text, 'Cell');
    expect(message.richBlocks[19].children.single.text, 'Inside');
    expect(message.richBlocks[20].mapLocation?.latitude, 35.681236);
  });

  test('treats whitespace-only rich media captions as absent', () {
    final message = TDParse.message({
      '@type': 'message',
      'id': 501,
      'chat_id': 42,
      'date': 1,
      'is_outgoing': false,
      'content': {
        '@type': 'messageRichMessage',
        'message': {
          '@type': 'richMessage',
          'is_full': true,
          'blocks': [
            {
              '@type': 'pageBlockPhoto',
              'photo': _photo(21),
              'caption': _caption(' \n '),
            },
            {
              '@type': 'pageBlockVideo',
              'video': _video(22),
              'caption': _caption('\t'),
            },
            {
              '@type': 'pageBlockAnimation',
              'animation': _animation(23),
              'caption': _caption('  '),
            },
            {
              '@type': 'pageBlockAudio',
              'audio': {'@type': 'audio', 'duration': 30, 'audio': _file(24)},
              'caption': _caption('\n\t'),
            },
            {
              '@type': 'pageBlockVoiceNote',
              'voice_note': {
                '@type': 'voiceNote',
                'duration': 8,
                'voice': _file(25),
              },
              'caption': _caption(' \t '),
            },
          ],
        },
      },
    });

    expect(message, isNotNull);
    expect(message!.richBlocks, hasLength(5));
    for (final block in message.richBlocks) {
      expect(block.caption, isEmpty);
      expect(block.captionEntities, isEmpty);
    }
  });
}
