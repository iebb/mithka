import 'package:flutter_test/flutter_test.dart';

import 'package:mithka/platform/android_share_intent.dart';

void main() {
  test('normalizes a native share payload', () {
    final payload = AndroidShareIntentPayload.fromMap({
      'id': 'share-1',
      'text': '  hello from another app  ',
      'mimeType': 'text/plain',
      'uris': ['content://one', '', 42, 'content://two'],
    });

    expect(payload.id, 'share-1');
    expect(payload.text, '  hello from another app  ');
    expect(payload.mimeType, 'text/plain');
    expect(payload.uris, ['content://one', 'content://two']);
    expect(payload.hasContent, isTrue);
  });
}
