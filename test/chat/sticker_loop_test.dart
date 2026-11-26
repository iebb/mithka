//
//  Mithka sticker loop: AnimatedStickerView drives a `.tgs` with its own
//  long-lived controller, so one authored loop takes its authored time
//  regardless of parent rebuilds or the platform's reduced-motion flag.
//

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:mithka/chat/stickers/animated_sticker_view.dart';
import 'package:mithka/tdlib/td_models.dart';

String _tgsJson() => jsonEncode({
  'v': '5.5.2',
  'fr': 60,
  'ip': 0,
  'op': 180,
  'w': 512,
  'h': 512,
  'nm': 'sticker',
  'ddd': 0,
  'assets': [],
  'layers': [
    {
      'ddd': 0,
      'ind': 1,
      'ty': 1,
      'nm': 'solid',
      'sr': 1,
      'sc': '#000000',
      'sw': 512,
      'sh': 512,
      'ao': 0,
      'ks': {
        'o': {
          'a': 1,
          'k': [
            {
              't': 0,
              's': [100],
            },
            {
              't': 180,
              's': [0],
            },
          ],
        },
        'r': {'a': 0, 'k': 0},
        'p': {
          'a': 0,
          'k': [0, 0, 0],
        },
        'a': {
          'a': 0,
          'k': [0, 0, 0],
        },
        's': {
          'a': 0,
          'k': [100, 100, 100],
        },
      },
      'ip': 0,
      'op': 180,
      'st': 0,
      'bm': 0,
    },
  ],
});

void main() {
  testWidgets('a tgs plays one loop in its authored three seconds', (
    tester,
  ) async {
    final compressed = const GZipEncoder().encode(utf8.encode(_tgsJson()));
    final file = File(
      '${Directory.systemTemp.path}/mithka_sticker_${DateTime.now().microsecondsSinceEpoch}.tgs',
    );
    file.writeAsBytesSync(compressed);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 200,
            height: 200,
            child: AnimatedStickerView(
              file: TdFileRef(id: 7, localPath: file.path),
            ),
          ),
        ),
      ),
    );
    // The fake clock never resolves real file I/O or the worker-isolate parses.
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (find.byType(Lottie).evaluate().isNotEmpty) break;
    }

    final lottie = tester.widget<Lottie>(find.byType(Lottie));
    expect(
      lottie.composition!.duration,
      const Duration(seconds: 3),
      reason: 'a 180-frame, 60 fps tgs is a three-second loop',
    );
    final controller = lottie.controller! as AnimationController;
    expect(controller.animationBehavior, AnimationBehavior.preserve);

    final start = controller.value;
    await tester.pump(const Duration(milliseconds: 1500));
    expect(
      (controller.value - start) % 1.0,
      closeTo(0.5, 0.1),
      reason: 'half the loop after half its duration',
    );
  });
}
