import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/desktop_image_preview_window.dart';
import 'package:mithka/chat/image_edit_view.dart';
import 'package:mithka/chat/image_preview.dart';

void main() {
  testWidgets('desktop preview builds a routed gallery shell with toolbar', (
    tester,
  ) async {
    await tester.pumpWidget(
      const DesktopImagePreviewWindowApp(
        arguments: DesktopImagePreviewWindowArguments(
          title: 'Image preview',
          localeTag: 'en',
          dark: true,
          items: [
            DesktopImagePreviewItemArguments(path: '/tmp/missing-photo.png'),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('desktop-image-preview-toolbar')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop preview toolbar keeps the requested owned-icon order', (
    tester,
  ) async {
    await tester.pumpWidget(
      const DesktopImagePreviewWindowApp(
        arguments: DesktopImagePreviewWindowArguments(
          title: 'Image preview',
          localeTag: 'en',
          dark: true,
          items: [
            DesktopImagePreviewItemArguments(path: '/tmp/missing-photo.png'),
          ],
        ),
      ),
    );
    await tester.pump();

    const orderedKeys = [
      'desktop-image-preview-rotate',
      'desktop-image-preview-edit',
      'desktop-image-preview-translate',
      'desktop-image-preview-ocr',
      'desktop-image-preview-share',
      'desktop-image-preview-save',
      'desktop-image-preview-more',
    ];
    final centers = <double>[];
    for (final key in orderedKeys) {
      final action = find.byKey(ValueKey(key));
      expect(action, findsOneWidget);
      centers.add(tester.getCenter(action).dx);
    }
    for (var index = 1; index < centers.length; index++) {
      expect(centers[index], greaterThan(centers[index - 1]));
    }

    for (final key in const [
      'desktop-image-preview-translate',
      'desktop-image-preview-ocr',
      'desktop-image-preview-share',
    ]) {
      final tooltip = tester.widget<Tooltip>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, isNotEmpty);
    }
  });

  testWidgets('desktop preview toolbar stays usable at minimum window width', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 320);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      const DesktopImagePreviewWindowApp(
        arguments: DesktopImagePreviewWindowArguments(
          title: 'Image preview',
          localeTag: 'en',
          dark: true,
          items: [
            DesktopImagePreviewItemArguments(path: '/tmp/missing-photo.png'),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('desktop-image-preview-toolbar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktop-image-preview-more')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop preview edit action opens the existing image editor', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'mithka-image-preview-edit-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final image = File('${directory.path}/one-pixel.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
          'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
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

    await tester.tap(find.byKey(const ValueKey('desktop-image-preview-edit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(ImageEditView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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

  test('malformed and unrelated child arguments are ignored', () {
    expect(DesktopImagePreviewWindowArguments.tryParse(''), isNull);
    expect(
      DesktopImagePreviewWindowArguments.tryParse('{"type":"mithka.chat"}'),
      isNull,
    );
    expect(
      DesktopImagePreviewWindowArguments.tryParse(
        '{"type":"mithka.image-preview","version":1}',
      ),
      isNull,
    );
    expect(DesktopImagePreviewWindowArguments.tryParse('not json'), isNull);
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

  test('desktop image window uses system chrome behind an IO boundary', () {
    final shell = File(
      'lib/app/desktop_image_preview_window.dart',
    ).readAsStringSync();
    final io = File(
      'lib/app/desktop_image_preview_window_io.dart',
    ).readAsStringSync();
    final stub = File(
      'lib/app/desktop_image_preview_window_stub.dart',
    ).readAsStringSync();
    final helper = File('lib/chat/image_preview.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(shell, isNot(contains('package:multi_window_manager/')));
    expect(stub, isNot(contains('multi_window_manager')));
    expect(io, contains('package:multi_window_manager/'));
    expect(io, contains('titleBarStyle: TitleBarStyle.normal'));
    expect(io, contains('title: arguments.title'));
    expect(io, contains('windowButtonVisibility: true'));
    expect(io, contains('Size(860, 640)'));
    expect(shell, isNot(contains('_WindowControl')));
    expect(shell, isNot(contains('desktopWindowDragArea')));
    expect(shell, contains('desktop-image-previous'));
    expect(shell, contains('desktop-image-next'));
    expect(shell, contains('DesktopImagePreviewPathUpdate'));
    expect(shell, contains('desktop-image-preview-toolbar'));
    expect(shell, contains('pageRouteBuilder:'));
    expect(helper, contains('if (opened) return'));
    expect(helper, contains('Navigator.of(context).push<void>'));
    expect(
      main,
      contains('DesktopImagePreviewWindowArguments.tryParseLaunchArguments'),
    );
    expect(main, contains('DesktopImagePreviewWindowApp('));
  });
}
