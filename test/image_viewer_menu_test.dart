import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/full_image_viewer.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  File writeImage() {
    final directory = Directory.systemTemp.createTempSync(
      'mithka-image-viewer-menu-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final image = File('${directory.path}/photo.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
          'AAAAC0lEQVR42uNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
    return image;
  }

  testWidgets(
    'the more button opens the built-in menu without an onMore callback',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final image = writeImage();

      await tester.pumpWidget(
        MaterialApp(
          home: FullImageViewer(
            items: [TdFileRef(id: 1, localPath: image.path)],
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('image-viewer-more')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('image-viewer-actions-menu')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('image-viewer-more')));
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.byKey(const ValueKey('image-viewer-actions-menu')),
        findsOneWidget,
      );
      // Copy follows DesktopClipboardImageService.canWriteImage, which reads
      // dart:io Platform — visible exactly on the host platforms that
      // implement the channel (macOS/iOS/Android), hidden elsewhere.
      expect(
        find.byKey(const ValueKey('image-viewer-action-copy')),
        Platform.isMacOS || Platform.isIOS || Platform.isAndroid
            ? findsOneWidget
            : findsNothing,
      );
      expect(
        find.byKey(const ValueKey('image-viewer-action-save')),
        findsOneWidget,
      );
      // No message anchors were supplied: View in Chat and Reply stay hidden.
      expect(
        find.byKey(const ValueKey('image-viewer-action-view-in-chat')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('image-viewer-action-reply')),
        findsNothing,
      );

      debugDefaultTargetPlatformOverride = null;
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('message anchors reveal View in Chat and Reply', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final image = writeImage();
    final viewed = <int>[];
    final replied = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: FullImageViewer(
          items: [TdFileRef(id: 1, localPath: image.path)],
          messageActions: ImageViewerMessageActions(
            messageIds: const [77],
            onViewInChat: (id) async => viewed.add(id),
            onReply: (id) async => replied.add(id),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('image-viewer-more')));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(const ValueKey('image-viewer-action-view-in-chat')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('image-viewer-action-reply')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('image-viewer-action-view-in-chat')),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(viewed, [77]);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('tapping outside the menu dismisses it', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final image = writeImage();

    await tester.pumpWidget(
      MaterialApp(
        home: FullImageViewer(items: [TdFileRef(id: 1, localPath: image.path)]),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('image-viewer-more')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.byKey(const ValueKey('image-viewer-actions-menu')),
      findsOneWidget,
    );

    await tester.tapAt(const Offset(40, 500));
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.byKey(const ValueKey('image-viewer-actions-menu')),
      findsNothing,
    );

    debugDefaultTargetPlatformOverride = null;
  });
}
