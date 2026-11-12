import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/desktop_image_preview_window.dart';
import 'package:mithka/chat/image_preview.dart';

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

  test('action-bearing previews stay in the main window', () {
    expect(imagePreviewCanUseIndependentWindow(), isTrue);
    expect(
      imagePreviewCanUseIndependentWindow(
        primaryActionLabel: 'Set as profile photo',
      ),
      isFalse,
    );
    expect(imagePreviewCanUseIndependentWindow(onMore: (_) async {}), isFalse);
  });
}
