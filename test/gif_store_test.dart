import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/gif_item.dart';
import 'package:mithka/chat/gif_store.dart';

void main() {
  test('inline GIF results retain the query identity required for sending', () {
    final page = parseInlineGifSearchPage({
      '@type': 'inlineQueryResults',
      'inline_query_id': '9007199254740991',
      'next_offset': 'next-page',
      'results': [
        {
          '@type': 'inlineQueryResultAnimation',
          'id': 'gif-result-7',
          'animation': {
            '@type': 'animation',
            'duration': 3,
            'width': 480,
            'height': 270,
            'mime_type': 'video/mp4',
            'animation': {
              '@type': 'file',
              'id': 77,
              'remote': {'@type': 'remoteFile', 'id': 'inline-animation'},
            },
          },
        },
      ],
    });

    expect(page.nextOffset, 'next-page');
    expect(page.items, hasLength(1));
    final gif = page.items.single;
    expect(gif.inlineQueryId, 9007199254740991);
    expect(gif.inlineResultId, 'gif-result-7');
    expect(gifSendRequest(chatId: 42, gif: gif), {
      '@type': 'sendInlineQueryResultMessage',
      'chat_id': 42,
      'query_id': 9007199254740991,
      'result_id': 'gif-result-7',
      'hide_via_bot': true,
    });
  });
}
