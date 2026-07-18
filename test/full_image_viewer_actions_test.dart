import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/full_image_viewer.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  testWidgets('owned image preview exposes primary and more actions', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'mithka-image-viewer-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final image = File('${directory.path}/photo.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
          'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
    int? primaryIndex;
    int? moreIndex;

    await tester.pumpWidget(
      MaterialApp(
        home: FullImageViewer(
          items: [TdFileRef(id: 1, localPath: image.path)],
          primaryActionLabel: 'Set as profile photo',
          onPrimaryAction: (index) async => primaryIndex = index,
          onMore: (index) async => moreIndex = index,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('Set as profile photo'), findsOneWidget);
    expect(find.byKey(const ValueKey('image-viewer-more')), findsOneWidget);

    await tester.tap(find.text('Set as profile photo'));
    await tester.pump();
    expect(primaryIndex, 0);

    await tester.tap(find.byKey(const ValueKey('image-viewer-more')));
    await tester.pump();
    expect(moreIndex, 0);
  });

  test('viewer source avoids stock Material and Cupertino controls', () {
    final source = File('lib/chat/full_image_viewer.dart').readAsStringSync();
    expect(source, isNot(contains('package:flutter/material.dart')));
    expect(source, isNot(contains('package:flutter/cupertino.dart')));
    expect(source, isNot(contains('Scaffold(')));
    expect(source, isNot(contains('CircularProgressIndicator(')));
    expect(source.replaceAll('HeroAppIcons.', ''), isNot(contains('Icons.')));
  });
}
