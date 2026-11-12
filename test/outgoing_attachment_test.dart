import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
  test('splits albums at TDLib ten-item limit', () {
    final batches = groupOutgoingAttachments([
      for (var i = 0; i < 11; i++)
        attachment('$i.jpg', OutgoingAttachmentKind.photo),
    ]);

    expect(batches.map((batch) => batch.attachments.length), [10, 1]);
    expect(batches.map((batch) => batch.isAlbum), [true, false]);
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
