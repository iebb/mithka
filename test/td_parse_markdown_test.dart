import 'package:flutter_test/flutter_test.dart';
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
}
