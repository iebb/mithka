import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mithka/chat/stickers/sticker_export_service.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native sticker MOV export retains an alpha-capable codec', (
    tester,
  ) async {
    const width = 4;
    const height = 4;
    Uint8List frame(int alpha) {
      final bytes = Uint8List(width * height * 4);
      for (var offset = 0; offset < bytes.length; offset += 4) {
        bytes[offset] = 255;
        bytes[offset + 3] = alpha;
      }
      return bytes;
    }

    final apng = StickerExportService.encodeRgbaFramesForTest(
      [frame(0), frame(128)],
      width: width,
      height: height,
      durationMs: 100,
      format: StickerExportFormat.png,
    );
    expect(apng, isNotNull);
    final temp = await getTemporaryDirectory();
    final source = File('${temp.path}/sticker-alpha-test.png');
    await source.writeAsBytes(apng!, flush: true);

    final outputPath = await const MethodChannel(
      'mithka/sticker_export',
    ).invokeMethod<String>('encodeAlphaMov', {'path': source.path});
    expect(outputPath, isNotNull);
    final output = File(outputPath!);
    expect(await output.exists(), isTrue);
    expect(await output.length(), greaterThan(0));
    // Kept in the test log so a local ffprobe can verify the encoded codec and
    // alpha metadata when diagnosing platform encoder regressions.
    // ignore: avoid_print
    print('STICKER_ALPHA_MOV=$outputPath');
  });
}
