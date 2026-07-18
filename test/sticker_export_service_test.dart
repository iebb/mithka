import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:mithka/chat/sticker_export_service.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  ChatMessage message({TdFileRef? animatedSticker}) => ChatMessage(
    id: 41,
    isOutgoing: false,
    text: '',
    date: 1,
    animatedSticker: animatedSticker,
    image: animatedSticker == null ? TdFileRef(id: 7) : null,
  );

  test('offers PNG, GIF, and MOV when alpha MOV is supported', () {
    final formats = StickerExportService.availableFormats(
      message(),
      supportsMov: true,
    );
    expect(formats, [
      StickerExportFormat.png,
      StickerExportFormat.gif,
      StickerExportFormat.mov,
    ]);
  });

  test('labels animated PNG exports as APNG', () {
    final animated = message(animatedSticker: TdFileRef(id: 9));
    expect(StickerExportService.isAnimated(animated), isTrue);
    expect(
      StickerExportService.availableFormats(animated, supportsMov: true),
      contains(StickerExportFormat.lottie),
    );
    expect(StickerExportFormat.png.label(animated: true), 'APNG');
    expect(StickerExportFormat.png.label(animated: false), 'PNG');
    expect(StickerExportFormat.lottie.label(animated: true), 'Lottie JSON');
  });

  test('TGS export returns the original standard Lottie JSON', () {
    final source = utf8.encode(
      '{"v":"5.7.4","fr":60,"ip":0,"op":120,"w":512,"h":512,"layers":[]}',
    );
    final tgs = Uint8List.fromList(GZipEncoder().encode(source)!);
    final decoded = StickerExportService.decodeTgsLottie(tgs);
    expect(decoded, isNotNull);
    expect(jsonDecode(utf8.decode(decoded!))['w'], 512);
    expect(StickerExportService.decodeTgsLottie(Uint8List(4)), isNull);
  });

  test('APNG encoder keeps animation frames and full alpha', () {
    final bytes = StickerExportService.encodeRgbaFramesForTest(
      [
        Uint8List.fromList([255, 0, 0, 0]),
        Uint8List.fromList([0, 255, 0, 128]),
      ],
      width: 1,
      height: 1,
      durationMs: 50,
      format: StickerExportFormat.png,
    );

    expect(bytes, isNotNull);
    final decoded = image_lib.decodePng(bytes!);
    expect(decoded, isNotNull);
    expect(decoded!.numFrames, 2);
    expect(decoded.frames[0].getPixel(0, 0).a.toInt(), 0);
    expect(decoded.frames[1].getPixel(0, 0).a.toInt(), 128);
    expect(decoded.frames[0].frameDuration, 50);
  });

  test('GIF encoder produces an animated GIF', () {
    final bytes = StickerExportService.encodeRgbaFramesForTest(
      [
        Uint8List.fromList([255, 0, 0, 0]),
        Uint8List.fromList([0, 0, 255, 255]),
      ],
      width: 1,
      height: 1,
      durationMs: 60,
      format: StickerExportFormat.gif,
    );

    expect(bytes, isNotNull);
    expect(String.fromCharCodes(bytes!.take(6)), startsWith('GIF8'));
    expect(image_lib.decodeGif(bytes)?.numFrames, 2);
  });
}
