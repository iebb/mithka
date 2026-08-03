import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/outgoing_attachment.dart';
import 'package:mithka/platform/desktop_clipboard_images.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'materializes ordered channel images and honors the album limit',
    () async {
      const clipboardChannel = MethodChannel('mithka/clipboard');
      const pathProviderChannel = MethodChannel(
        'plugins.flutter.io/path_provider',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final directory = Directory.systemTemp.createTempSync(
        'mithka-clipboard-test-',
      );
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
        'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      messenger.setMockMethodCallHandler(clipboardChannel, (call) async {
        expect(call.method, 'readImages');
        return <Map<String, Object>>[
          {'mimeType': 'image/png', 'data': png},
          {'mimeType': 'image/jpeg', 'data': png},
        ];
      });
      messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
        if (call.method == 'getTemporaryDirectory') return directory.path;
        return null;
      });
      addTearDown(() async {
        messenger.setMockMethodCallHandler(clipboardChannel, null);
        messenger.setMockMethodCallHandler(pathProviderChannel, null);
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });

      final result = await DesktopClipboardImageService.readAttachments(1);

      expect(result.availableImageCount, 2);
      expect(result.failedImageCount, 0);
      expect(result.attachments, hasLength(1));
      expect(result.attachments.single.kind, OutgoingAttachmentKind.photo);
      expect(result.attachments.single.path, endsWith('.png'));
      expect(File(result.attachments.single.path).readAsBytesSync(), png);
    },
  );
}
