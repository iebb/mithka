import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/full_image_viewer.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  testWidgets('the page counter hugs its text instead of spanning the bar', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'mithka-image-viewer-counter-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final image = File('${directory.path}/photo.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
          'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: FullImageViewer(
          items: [
            TdFileRef(id: 1, localPath: image.path),
            TdFileRef(id: 2, localPath: image.path),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('1 / 2'), findsOneWidget);
    final counter = tester.getSize(
      find.byKey(const ValueKey('image-viewer-counter')),
    );
    final label = tester.getSize(find.text('1 / 2'));
    // A Container given an alignment grows to its constraints, which turned
    // this pill into a bar across the whole window.
    expect(counter.height, 32);
    expect(counter.width, closeTo(label.width + 24, 1));
    expect(
      counter.width,
      lessThan(tester.view.physicalSize.width / tester.view.devicePixelRatio),
    );
  });

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

  testWidgets('mini thumbnails are zoomable before the full image arrives', (
    tester,
  ) async {
    final thumb = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
      'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: FullImageViewer(
          items: [TdFileRef(id: 2, miniThumb: Uint8List.fromList(thumb))],
        ),
      ),
    );
    await tester.pump();

    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.transformationController, isNotNull);
    expect(
      viewer.transformationController!.value.getMaxScaleOnAxis(),
      closeTo(1, 0.001),
    );

    final target = find.byType(InteractiveViewer);
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(target);
    await tester.pump();
    expect(
      viewer.transformationController!.value.getMaxScaleOnAxis(),
      closeTo(2, 0.001),
    );

    // The test client has no TDLib file transport, so let the bounded path
    // waiter expire before disposing the viewer.
    await tester.pump(const Duration(minutes: 3, seconds: 1));
  });

  testWidgets(
    'downloadable thumbnails stay zoomable while the original loads',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'mithka-image-viewer-thumbnail-test-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final thumbnail = File('${directory.path}/thumbnail.png')
        ..writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
            'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: FullImageViewer(
            items: [
              TdFileRef(
                id: 3,
                thumbnail: TdFileRef(id: 4, localPath: thumbnail.path),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();

      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(viewer.trackpadScrollCausesScale, isTrue);

      await tester.pump(const Duration(minutes: 3, seconds: 1));
    },
  );

  testWidgets('pinch gestures zoom the image instead of paging the gallery', (
    tester,
  ) async {
    final thumb = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
      'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: FullImageViewer(
          items: [
            TdFileRef(id: 3, miniThumb: Uint8List.fromList(thumb)),
            TdFileRef(id: 4, miniThumb: Uint8List.fromList(thumb)),
          ],
        ),
      ),
    );
    await tester.pump();

    final target = find.byType(InteractiveViewer);
    final viewer = tester.widget<InteractiveViewer>(target);
    final center = tester.getCenter(target);
    final leftFinger = await tester.startGesture(
      center + const Offset(-28, 0),
      pointer: 1,
    );
    final rightFinger = await tester.startGesture(
      center + const Offset(28, 0),
      pointer: 2,
    );
    await tester.pump();
    await leftFinger.moveTo(center + const Offset(-80, 0));
    await rightFinger.moveTo(center + const Offset(80, 0));
    await tester.pump();
    await leftFinger.up();
    await rightFinger.up();
    await tester.pump();

    expect(
      viewer.transformationController!.value.getMaxScaleOnAxis(),
      greaterThan(1.01),
    );
    await tester.pump(const Duration(minutes: 3, seconds: 1));
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
