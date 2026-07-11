import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/outgoing_attachment.dart';

OutgoingAttachment attachment(
  String path,
  OutgoingAttachmentKind kind, {
  String caption = '',
}) => OutgoingAttachment(path: path, kind: kind, caption: caption);

void main() {
  test('groups compatible attachments without reordering', () {
    final batches = groupOutgoingAttachments([
      attachment('1.jpg', OutgoingAttachmentKind.photo),
      attachment('2.mp4', OutgoingAttachmentKind.video),
      attachment('3.gif', OutgoingAttachmentKind.animation),
      attachment('4.pdf', OutgoingAttachmentKind.document),
      attachment('5.zip', OutgoingAttachmentKind.document),
      attachment('6.mp3', OutgoingAttachmentKind.audio),
      attachment('7.flac', OutgoingAttachmentKind.audio),
      attachment('8.jpg', OutgoingAttachmentKind.photo),
    ]);

    expect(batches.map((batch) => batch.attachments.map((item) => item.path)), [
      ['1.jpg', '2.mp4'],
      ['3.gif'],
      ['4.pdf', '5.zip'],
      ['6.mp3', '7.flac'],
      ['8.jpg'],
    ]);
    expect(batches.map((batch) => batch.isAlbum), [
      true,
      false,
      true,
      true,
      false,
    ]);
  });

  test('splits albums at TDLib ten-item limit', () {
    final batches = groupOutgoingAttachments([
      for (var i = 0; i < 11; i++)
        attachment('$i.jpg', OutgoingAttachmentKind.photo),
    ]);

    expect(batches.map((batch) => batch.attachments.length), [10, 1]);
    expect(batches.map((batch) => batch.isAlbum), [true, false]);
  });

  test('builds album and standalone requests with one primary caption', () {
    final requests = buildAttachmentSendRequests(
      chatId: 42,
      caption: 'Album caption',
      captionEntities: const [
        {
          '@type': 'textEntity',
          'offset': 0,
          'length': 5,
          'type': {'@type': 'textEntityTypeBold'},
        },
      ],
      replyTo: const {'@type': 'inputMessageReplyToMessage', 'message_id': 9},
      attachments: [
        attachment('1.jpg', OutgoingAttachmentKind.photo),
        attachment('2.mp4', OutgoingAttachmentKind.video),
        attachment('3.pdf', OutgoingAttachmentKind.document),
      ],
    );

    expect(requests, hasLength(2));
    expect(requests.first['@type'], 'sendMessageAlbum');
    expect(requests.first['reply_to'], isNotNull);
    final album = requests.first['input_message_contents'] as List;
    expect(album, hasLength(2));
    expect((album.first as Map)['caption'], isNotNull);
    expect((album.last as Map)['caption'], isNull);
    expect(requests.last['@type'], 'sendMessage');
    expect(requests.last['reply_to'], isNull);
  });

  test('preserves an attachment caption when no primary caption exists', () {
    final requests = buildAttachmentSendRequests(
      chatId: 1,
      attachments: [
        attachment(
          'document.pdf',
          OutgoingAttachmentKind.document,
          caption: 'Document caption',
        ),
      ],
    );

    final content = requests.single['input_message_content'] as Map;
    expect((content['caption'] as Map)['text'], 'Document caption');
  });

  test('applies album caption to first attachment after reordering', () {
    final requests = buildAttachmentSendRequests(
      chatId: 1,
      caption: 'Reordered album caption',
      attachments: [
        attachment('third.jpg', OutgoingAttachmentKind.photo),
        attachment('first.jpg', OutgoingAttachmentKind.photo),
        attachment('second.mp4', OutgoingAttachmentKind.video),
      ],
    );

    final album = requests.single['input_message_contents'] as List;
    expect(((album.first as Map)['photo'] as Map)['photo'], {
      '@type': 'inputFileLocal',
      'path': 'third.jpg',
    });
    expect(
      ((album.first as Map)['caption'] as Map)['text'],
      'Reordered album caption',
    );
    expect((album[1] as Map)['caption'], isNull);
    expect((album[2] as Map)['caption'], isNull);
  });
}
