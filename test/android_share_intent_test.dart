import 'package:flutter_test/flutter_test.dart';

import 'package:mithka/chat/outgoing_attachment.dart';
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

  test('classifies shared files for the existing send pipeline', () {
    expect(
      const AndroidSharedFile(
        path: '/cache/photo.jpg',
        fileName: 'photo.jpg',
        mimeType: 'image/jpeg',
      ).attachmentKind,
      OutgoingAttachmentKind.photo,
    );
    expect(
      const AndroidSharedFile(
        path: '/cache/clip.mp4',
        fileName: 'clip.mp4',
        mimeType: 'video/mp4',
      ).attachmentKind,
      OutgoingAttachmentKind.video,
    );
    expect(
      const AndroidSharedFile(
        path: '/cache/song.m4a',
        fileName: 'song.m4a',
        mimeType: 'audio/mp4',
      ).attachmentKind,
      OutgoingAttachmentKind.audio,
    );
    expect(
      const AndroidSharedFile(
        path: '/cache/archive.zip',
        fileName: 'archive.zip',
        mimeType: 'application/zip',
      ).attachmentKind,
      OutgoingAttachmentKind.document,
    );
  });

  test('payload without text or files is ignored by content check', () {
    final payload = AndroidShareIntentPayload.fromMap({
      'id': 'empty',
      'text': '   ',
      'uris': <String>[],
    });
    expect(payload.hasContent, isFalse);
  });
}
