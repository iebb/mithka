import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter/widgets.dart' show RepaintBoundary, ValueKey, Widget;
import 'package:flutter_test/flutter_test.dart';

const captureGlassReview = bool.fromEnvironment('CAPTURE_GLASS_REVIEW');
const _imageKey = ValueKey('glass-review-image');

Widget glassReviewBoundary(Widget child) =>
    captureGlassReview ? RepaintBoundary(key: _imageKey, child: child) : child;

Future<void> loadGlassReviewIconFonts() async {
  if (!captureGlassReview) return;
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json'));
  for (final entry in manifest as List<dynamic>) {
    final family = entry['family'] as String;
    if (!family.startsWith('packages/heroicons_flutter/')) continue;
    final loader = FontLoader(family);
    for (final font in entry['fonts'] as List<dynamic>) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

Future<void> captureGlassReviewImage(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_imageKey),
  );
  expect(boundary.debugNeedsPaint, isFalse);
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(data, isNotNull);
      final bytes = data!;
      final directory = Directory('build/glass-review');
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png').writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
    } finally {
      image.dispose();
    }
  });
}
