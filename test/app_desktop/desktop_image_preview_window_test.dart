import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/desktop_image_preview_window.dart';
import 'package:mithka/chat/media/image_preview.dart';
import 'package:mithka/media/media_metadata.dart';
import 'package:mithka/media/media_metadata_dialog.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  testWidgets(
    'macOS preview Copy Image sends image bytes instead of the local path',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'mithka-image-preview-copy-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
        'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      final image = File('${directory.path}/one-pixel.png')
        ..writeAsBytesSync(bytes);
      expect(image.existsSync(), isTrue);
      const channel = MethodChannel('mithka/clipboard');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var copies = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'writeImage');
        expect(call.arguments, bytes);
        copies++;
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      await tester.pumpWidget(
        DesktopImagePreviewWindowApp(
          arguments: DesktopImagePreviewWindowArguments(
            title: 'Image preview',
            localeTag: 'en',
            dark: true,
            items: [DesktopImagePreviewItemArguments(path: image.path)],
          ),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('desktop-image-preview-more')),
      );
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.text('Copy image'));
        for (var attempt = 0; attempt < 20 && copies == 0; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();

      expect(
        find.byKey(const ValueKey('desktop-image-preview-more-menu')),
        findsNothing,
      );
      expect(copies, 1);
      expect(find.text('Copied'), findsOneWidget);
    },
    skip: !Platform.isMacOS,
  );

  test('desktop image arguments contain presentation-only local data', () {
    final arguments = DesktopImagePreviewWindowArguments(
      title: 'Image preview',
      localeTag: 'en',
      dark: true,
      startIndex: 1,
      items: [
        const DesktopImagePreviewItemArguments(
          path: '/private/tmp/mithka/first.jpg',
        ),
        DesktopImagePreviewItemArguments(
          path: '/private/tmp/mithka/photo.jpg',
          miniThumb: Uint8List.fromList([1, 2, 3, 4]),
        ),
      ],
    );

    final encoded = arguments.encode();
    final decoded = DesktopImagePreviewWindowArguments.tryParseLaunchArguments([
      '14',
      encoded,
    ]);

    expect(decoded?.startIndex, 1);
    expect(decoded?.title, 'Image preview');
    expect(decoded?.localeTag, 'en');
    expect(decoded?.dark, isTrue);
    expect(decoded?.items, hasLength(2));
    expect(decoded?.items.first.path, '/private/tmp/mithka/first.jpg');
    expect(decoded?.items[1].path, '/private/tmp/mithka/photo.jpg');
    expect(decoded?.items[1].miniThumb, [1, 2, 3, 4]);
    expect(encoded, isNot(contains('fileId')));
    expect(encoded, isNot(contains('chatId')));
    expect(encoded, isNot(contains('account')));
  });

  test(
    'desktop image paths accept local absolutes and reject remote sources',
    () {
      expect(normalizeDesktopImagePath('/tmp/photo.png'), '/tmp/photo.png');
      expect(
        normalizeDesktopImagePath(r'C:\Users\Mithka\photo.png'),
        r'C:\Users\Mithka\photo.png',
      );
      expect(normalizeDesktopImagePath('photo.png'), isNull);
      expect(
        normalizeDesktopImagePath('https://example.com/photo.png'),
        isNull,
      );
      expect(normalizeDesktopImagePath('file:///tmp/photo.png'), isNull);
      expect(normalizeDesktopImagePath(r'\\server\share\photo.png'), isNull);
    },
  );

  test('long galleries open the window on the tapped image', () {
    // Past the 64-image limit the tapped photo used to be dropped and the
    // window opened on photo 64 instead.
    for (final (length, start) in [
      (200, 150),
      (200, 0),
      (200, 199),
      (65, 64),
      (10, 7),
      (1, 0),
    ]) {
      final slice = desktopImagePreviewWindowSlice(length, start);
      expect(slice.count, length < 64 ? length : 64);
      expect(slice.first, greaterThanOrEqualTo(0));
      expect(slice.first + slice.count, lessThanOrEqualTo(length));
      expect(slice.first + slice.initialIndex, start);
    }
  });

  test('only previews with custom actions stay in the main window', () {
    // Chat photos carry View in chat, Reply and media info, which the native
    // window's menu offers, so they open there too.
    expect(imagePreviewCanUseIndependentWindow(), isTrue);
    expect(
      imagePreviewCanUseIndependentWindow(
        primaryActionLabel: 'Set as profile photo',
      ),
      isFalse,
    );
    expect(imagePreviewCanUseIndependentWindow(onMore: (_) async {}), isFalse);
  });

  testWidgets(
    'desktop preview window binds AppColors to the active dark or light mode',
    (tester) async {
      for (final (dark, expectedBackground) in [
        (true, AppColors.dark.background),
        (false, AppColors.light.background),
      ]) {
        await tester.pumpWidget(
          DesktopImagePreviewWindowApp(
            arguments: DesktopImagePreviewWindowArguments(
              title: 'Image preview',
              localeTag: 'en',
              dark: dark,
              items: const [DesktopImagePreviewItemArguments()],
            ),
          ),
        );
        await tester.pump();
        final moreContext = tester.element(
          find.byKey(const ValueKey('desktop-image-preview-more')),
        );
        expect(moreContext.colors.background, expectedBackground);
      }
    },
  );

  test('desktop image arguments carry media facts and an action session', () {
    const arguments = DesktopImagePreviewWindowArguments(
      title: 'Image preview',
      localeTag: 'en',
      dark: false,
      canReply: true,
      actionSession: 'image-3-abc',
      originWindowId: 0,
      items: [
        DesktopImagePreviewItemArguments(
          path: '/private/tmp/mithka/photo.jpg',
          hasMessage: true,
          metadata: MediaMetadata(
            kind: MediaMetadataKind.photo,
            width: 1280,
            height: 960,
            sizeBytes: 204800,
            localPath: 'relative/photo.jpg',
          ),
        ),
        DesktopImagePreviewItemArguments(),
      ],
    );

    final encoded = arguments.encode();
    final decoded = DesktopImagePreviewWindowArguments.tryParse(encoded)!;

    expect(decoded.canReply, isTrue);
    expect(decoded.actionSession, 'image-3-abc');
    expect(decoded.originWindowId, 0);
    expect(decoded.hasMessageActions, isTrue);
    final first = decoded.items.first;
    expect(first.hasMessage, isTrue);
    expect(first.metadata?.kind, MediaMetadataKind.photo);
    expect(first.metadata?.width, 1280);
    expect(first.metadata?.height, 960);
    expect(first.metadata?.sizeBytes, 204800);
    // Only absolute local paths cross the window boundary.
    expect(first.metadata?.localPath, isNull);
    expect(first.withPath('/tmp/edited.png').hasMessage, isTrue);
    expect(first.withPath('/tmp/edited.png').metadata?.width, 1280);
    expect(decoded.items[1].hasMessage, isFalse);
    expect(decoded.items[1].metadata, isNull);
    // Message ids stay in the opening window.
    expect(encoded, isNot(contains('messageId')));

    final withoutSession = DesktopImagePreviewWindowArguments.tryParse(
      const DesktopImagePreviewWindowArguments(
        title: 'Image preview',
        localeTag: 'en',
        dark: false,
        actionSession: '../not an id',
        originWindowId: 0,
        items: [DesktopImagePreviewItemArguments(hasMessage: true)],
      ).encode(),
    )!;
    expect(withoutSession.hasMessageActions, isFalse);
  });

  test('preview action requests accept only a known action and index', () {
    final request = DesktopImagePreviewActionRequest.tryParse(
      const DesktopImagePreviewActionRequest(
        session: 'image-1-x',
        action: DesktopImagePreviewAction.reply,
        index: 3,
      ).toJson(),
    );
    expect(request?.session, 'image-1-x');
    expect(request?.action, DesktopImagePreviewAction.reply);
    expect(request?.index, 3);

    for (final source in [
      null,
      {'session': 'image-1-x', 'action': 'delete', 'index': 0},
      {'session': 'image 1', 'action': 'reply', 'index': 0},
      {'session': 'image-1-x', 'action': 'reply', 'index': -1},
      {'session': 'image-1-x', 'action': 'reply', 'index': 64},
      {'session': 'image-1-x', 'action': 'reply', 'index': '1'},
    ]) {
      expect(DesktopImagePreviewActionRequest.tryParse(source), isNull);
    }
  });

  testWidgets('preview More menu offers message actions and media info', (
    tester,
  ) async {
    await tester.pumpWidget(
      const DesktopImagePreviewWindowApp(
        arguments: DesktopImagePreviewWindowArguments(
          title: 'Image preview',
          localeTag: 'en',
          dark: true,
          canReply: true,
          actionSession: 'image-1-x',
          originWindowId: 0,
          items: [
            DesktopImagePreviewItemArguments(
              hasMessage: true,
              metadata: MediaMetadata(
                kind: MediaMetadataKind.photo,
                width: 800,
                height: 600,
              ),
            ),
            DesktopImagePreviewItemArguments(),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('desktop-image-preview-more')));
    await tester.pump();

    expect(find.text('View in chat'), findsOneWidget);
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Media info'), findsOneWidget);

    await tester.tap(find.text('Media info'));
    // The placeholder spinner keeps animating, so the page never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MediaMetadataDialog), findsOneWidget);
    expect(
      find.byKey(const ValueKey('desktop-image-preview-more-menu')),
      findsNothing,
    );
  });

  testWidgets('preview More menu hides message entries without a message', (
    tester,
  ) async {
    await tester.pumpWidget(
      const DesktopImagePreviewWindowApp(
        arguments: DesktopImagePreviewWindowArguments(
          title: 'Image preview',
          localeTag: 'en',
          dark: false,
          items: [DesktopImagePreviewItemArguments(hasMessage: true)],
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('desktop-image-preview-more')));
    await tester.pump();

    expect(find.text('View in chat'), findsNothing);
    expect(find.text('Reply'), findsNothing);
    expect(find.text('Media info'), findsNothing);
    expect(find.text('Close'), findsOneWidget);
  });
}
