import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:mithka/chat/composer/outgoing_attachment.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Telegram photo limits', () {
    late Directory directory;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('mithka-limits-');
    });
    tearDown(() => directory.delete(recursive: true));

    Future<String> png(int width, int height) async {
      final image = image_lib.Image(
        width: width,
        height: height,
        numChannels: 4,
      )..clear(image_lib.ColorRgba8(200, 40, 40, 255));
      // A transparent corner must not turn black in the opaque JPEG.
      image_lib.fillRect(
        image,
        x1: 0,
        y1: 0,
        x2: 199,
        y2: 199,
        color: image_lib.ColorRgba8(0, 0, 0, 0),
        alphaBlend: false,
      );
      final file = File('${directory.path}/${width}x$height.png');
      await file.writeAsBytes(image_lib.encodePng(image, level: 1));
      return file.path;
    }

    test('an original past width + height 10000 is downscaled', () async {
      final path = await png(6400, 3700);
      final fitted = await fitPhotoToTelegramLimits(
        attachment(
          path,
          OutgoingAttachmentKind.photo,
          width: 6400,
          height: 3700,
        ),
      );

      expect(fitted.kind, OutgoingAttachmentKind.photo);
      expect(fitted.path, isNot(path));
      expect((fitted.width, fitted.height), (2560, 1480));
      final decoded = image_lib.decodeJpg(
        await File(fitted.path).readAsBytes(),
      )!;
      expect((decoded.width, decoded.height), (2560, 1480));
      final corner = decoded.getPixel(20, 20);
      expect([corner.r, corner.g, corner.b], everyElement(greaterThan(240)));
      expect(decoded.getPixel(1280, 740).g, lessThan(80));
      await File(fitted.path).parent.delete(recursive: true);
    });

    test('measuring an unmeasured oversized photo also fits it', () async {
      final path = await png(6400, 3700);
      final fitted = await resolveAttachmentDimensions(
        attachment(path, OutgoingAttachmentKind.photo),
      );

      expect((fitted.width, fitted.height), (2560, 1480));
      await File(fitted.path).parent.delete(recursive: true);
    });

    test('a photo within the limits is sent untouched', () async {
      final path = await png(1200, 800);
      final original = attachment(
        path,
        OutgoingAttachmentKind.photo,
        width: 1200,
        height: 800,
      );

      expect(await fitPhotoToTelegramLimits(original), same(original));
    });

    test('a panorama past a 20:1 ratio is sent as a file', () async {
      final fitted = await fitPhotoToTelegramLimits(
        attachment(
          '/missing/pano.jpg',
          OutgoingAttachmentKind.photo,
          width: 4200,
          height: 200,
        ),
      );

      expect(fitted.kind, OutgoingAttachmentKind.document);
      expect(fitted.path, '/missing/pano.jpg');
      expect(fitted.width, isNull);
    });

    test(
      'an oversized photo that cannot be decoded is sent as a file',
      () async {
        final file = File('${directory.path}/broken.heic')
          ..writeAsBytesSync(List.filled(64, 7));
        final fitted = await fitPhotoToTelegramLimits(
          attachment(
            file.path,
            OutgoingAttachmentKind.photo,
            width: 8064,
            height: 6048,
          ),
        );

        expect(fitted.kind, OutgoingAttachmentKind.document);
        expect(fitted.path, file.path);
      },
    );
  });

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
