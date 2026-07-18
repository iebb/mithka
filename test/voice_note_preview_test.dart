import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/voice_note_preview_view.dart';
import 'package:mithka/chat/voice_note_trimmer.dart';

void main() {
  test('Telegram waveform encoder packs five-bit samples', () {
    final encoded = encodeTelegramWaveform([-60, -30, 0]);
    final bytes = base64Decode(encoded);
    expect(bytes.length, 2);
    expect(bytes[0] & 0x1f, 0);
    expect((bytes[0] >> 5) | ((bytes[1] & 0x03) << 3), 16);
    expect((bytes[1] >> 2) & 0x1f, 31);
  });

  test('waveform encoder caps long recordings at one hundred samples', () {
    final encoded = encodeTelegramWaveform(List.filled(500, -12));
    expect(base64Decode(encoded).length, 63);
  });

  test('voice note trimmer rewrites an Ogg Opus page range', () async {
    final head = Uint8List(19)
      ..setRange(0, 8, ascii.encode('OpusHead'))
      ..[8] = 1
      ..[9] = 1;
    ByteData.sublistView(head).setUint16(10, 312, Endian.little);
    final pages = <Uint8List>[
      _oggPage(head, granule: 0, sequence: 0, headerType: 0x02),
      _oggPage(
        Uint8List.fromList([...ascii.encode('OpusTags'), 0, 0, 0, 0]),
        granule: 0,
        sequence: 1,
      ),
      _oggPage(
        Uint8List.fromList([0xf8, 0xff, 0xfe]),
        granule: 1272,
        sequence: 2,
      ),
      _oggPage(
        Uint8List.fromList([0xf8, 0xff, 0xfe]),
        granule: 2232,
        sequence: 3,
      ),
      _oggPage(
        Uint8List.fromList([0xf8, 0xff, 0xfe]),
        granule: 3192,
        sequence: 4,
        headerType: 0x04,
      ),
    ];
    final directory = await Directory.systemTemp.createTemp('voice-trim-test-');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.ogg');
    await source.writeAsBytes(pages.expand((page) => page).toList());

    final result = await VoiceNoteTrimmer.trim(
      inputPath: source.path,
      startSeconds: 0.02,
      endSeconds: 0.055,
    );
    final output = await File(result.path).readAsBytes();
    addTearDown(() => File(result.path).parent.delete(recursive: true));
    expect(output, isNotEmpty);
    expect(ascii.decode(output.sublist(0, 4)), 'OggS');
    expect(result.durationSeconds, 1);
  });
}

Uint8List _oggPage(
  Uint8List body, {
  required int granule,
  required int sequence,
  int headerType = 0,
}) {
  final page = Uint8List(28 + body.length)
    ..setRange(0, 4, ascii.encode('OggS'))
    ..[4] = 0
    ..[5] = headerType
    ..[26] = 1
    ..[27] = body.length
    ..setRange(28, 28 + body.length, body);
  ByteData.sublistView(page)
    ..setUint64(6, granule, Endian.little)
    ..setUint32(14, 0x12345678, Endian.little)
    ..setUint32(18, sequence, Endian.little);
  return VoiceNoteTrimmer.rewritePage(
    page,
    granule: granule,
    sequence: sequence,
    headerType: headerType,
  );
}
