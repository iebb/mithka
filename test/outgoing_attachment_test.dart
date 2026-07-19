import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:mithka/chat/outgoing_attachment.dart';
import 'package:mithka/tdlib/td_image_loader.dart';
import 'package:mithka/tdlib/td_models.dart';

OutgoingAttachment attachment(
  String path,
  OutgoingAttachmentKind kind, {
  String caption = '',
  int? width,
  int? height,
}) => OutgoingAttachment(
  path: path,
  kind: kind,
  caption: caption,
  width: width,
  height: height,
);

void main() {
  test('gallery media can always be converted to document attachments', () {
    for (final media in [
      (isVideo: false, isAnimation: false),
      (isVideo: true, isAnimation: false),
      (isVideo: false, isAnimation: true),
    ]) {
      expect(
        galleryAttachmentKind(
          sendAsFile: true,
          isVideo: media.isVideo,
          isAnimation: media.isAnimation,
        ),
        OutgoingAttachmentKind.document,
      );
    }

    expect(
      galleryAttachmentKind(
        sendAsFile: false,
        isVideo: true,
        isAnimation: false,
      ),
      OutgoingAttachmentKind.video,
    );
    expect(
      galleryAttachmentKind(
        sendAsFile: false,
        isVideo: false,
        isAnimation: true,
      ),
      OutgoingAttachmentKind.animation,
    );

    final document = attachmentInputMessageContent(
      attachment(
        '/tmp/IMG_1234.HEIC',
        galleryAttachmentKind(
          sendAsFile: true,
          isVideo: false,
          isAnimation: false,
        ),
      ),
    );
    expect(document['@type'], 'inputMessageDocument');
    expect(
      ((document['document'] as Map)['document'] as Map)['path'],
      '/tmp/IMG_1234.HEIC',
    );

    final originalDocument = attachmentInputMessageContent(
      const OutgoingAttachment(
        path: '/tmp/prepared.jpg',
        originalPath: '/tmp/IMG_5678.HEIC',
        kind: OutgoingAttachmentKind.document,
      ),
    );
    expect(
      ((originalDocument['document'] as Map)['document'] as Map)['path'],
      '/tmp/IMG_5678.HEIC',
    );
  });

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

  test('includes image dimensions in the outgoing photo payload', () {
    final content = attachmentInputMessageContent(
      attachment(
        'wide.jpg',
        OutgoingAttachmentKind.photo,
        width: 1600,
        height: 900,
      ),
    );

    expect(content['width'], 1600);
    expect(content['height'], 900);
    expect((content['photo'] as Map)['width'], 1600);
    expect((content['photo'] as Map)['height'], 900);
  });

  test('reads the encoded photo dimensions before sending', () async {
    final directory = await Directory.systemTemp.createTemp(
      'mithka-dimensions-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/wide.png');
    await file.writeAsBytes(
      image_lib.encodePng(image_lib.Image(width: 4, height: 2)),
    );

    final resolved = await resolveAttachmentDimensions(
      attachment(file.path, OutgoingAttachmentKind.photo),
    );

    expect(resolved.width, 4);
    expect(resolved.height, 2);
  });

  test('parses the local source path from an outgoing TDLib file', () {
    final message = TDParse.message({
      '@type': 'message',
      'id': -10,
      'chat_id': 42,
      'is_outgoing': true,
      'date': 1,
      'content': {
        '@type': 'messagePhoto',
        'caption': {'@type': 'formattedText', 'text': '', 'entities': []},
        'photo': {
          '@type': 'photo',
          'sizes': [
            {
              '@type': 'photoSize',
              'width': 1200,
              'height': 900,
              'photo': {
                '@type': 'file',
                'id': 7,
                'local': {
                  '@type': 'localFile',
                  'path': '/tmp/outgoing-photo.jpg',
                  'is_downloading_completed': true,
                },
              },
            },
          ],
        },
      },
    });

    expect(message?.image?.localPath, '/tmp/outgoing-photo.jpg');
  });

  test('server-confirmed media inherits the pending local source path', () {
    final pending = ChatMessage(
      id: -10,
      isOutgoing: true,
      text: '',
      date: 1,
      contentType: 'messageVideo',
      image: TdFileRef(id: 1, localPath: '/tmp/thumb.jpg'),
      imageWidth: 1600,
      imageHeight: 900,
      video: TdFileRef(id: 2, localPath: '/tmp/video.mp4'),
      document: MessageDocument(
        fileName: 'file.pdf',
        size: 10,
        ext: 'PDF',
        file: TdFileRef(id: 3, localPath: '/tmp/file.pdf'),
      ),
    );
    final sent = ChatMessage(
      id: 100,
      isOutgoing: true,
      text: '',
      date: 2,
      contentType: 'messageVideo',
      image: TdFileRef(id: 11),
      video: TdFileRef(id: 12),
      document: MessageDocument(
        fileName: 'file.pdf',
        size: 10,
        ext: 'PDF',
        file: TdFileRef(id: 13),
      ),
    );

    sent.inheritLocalMediaFrom(pending);

    expect(sent.image?.id, 11);
    expect(sent.image?.localPath, '/tmp/thumb.jpg');
    expect(sent.imageWidth, 1600);
    expect(sent.imageHeight, 900);
    expect(sent.video?.id, 12);
    expect(sent.video?.localPath, '/tmp/video.mp4');
    expect(sent.document?.file?.id, 13);
    expect(sent.document?.file?.localPath, '/tmp/file.pdf');
  });

  test(
    'resolves an outgoing source file without asking TDLib to download',
    () async {
      final directory = await Directory.systemTemp.createTemp('mithka-media-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/photo.jpg');
      await file.writeAsBytes([1, 2, 3]);

      final path = await TdFileCenter.shared.pathFor(
        TdFileRef(id: 999, localPath: file.path),
      );

      expect(path, file.path);
    },
  );
}
