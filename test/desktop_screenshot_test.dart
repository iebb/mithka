import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/platform/desktop_screenshot.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'mithka-screenshot-test-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'macOS requests access before opening the native region picker',
    () async {
      var accessAllowed = false;
      var permissionRequests = 0;
      var captureCalls = 0;
      final service = DesktopScreenshotService(
        platform: DesktopScreenshotPlatform.macOS,
        permissionCheck: () async => accessAllowed,
        permissionRequest: () async {
          permissionRequests++;
          accessAllowed = true;
        },
        regionCapture: (path) async {
          captureCalls++;
          await File(path).writeAsBytes(const [1, 2, 3], flush: true);
          return true;
        },
        temporaryDirectoryProvider: () async => temporaryDirectory,
        clock: () => DateTime.fromMicrosecondsSinceEpoch(1234),
      );

      final path = await service.capture();

      expect(permissionRequests, 1);
      expect(captureCalls, 1);
      expect(path, endsWith('mithka-screenshot-1234.png'));
      expect(await File(path!).length(), 3);
    },
  );

  test('macOS denial does not open the native picker', () async {
    var permissionRequests = 0;
    var captureCalls = 0;
    final service = DesktopScreenshotService(
      platform: DesktopScreenshotPlatform.macOS,
      permissionCheck: () async => false,
      permissionRequest: () async => permissionRequests++,
      regionCapture: (_) async {
        captureCalls++;
        return true;
      },
      temporaryDirectoryProvider: () async => temporaryDirectory,
    );

    expect(await service.capture(), isNull);
    expect(permissionRequests, 1);
    expect(captureCalls, 0);
  });

  test('Windows capture skips macOS permission preflight', () async {
    var permissionChecks = 0;
    final service = DesktopScreenshotService(
      platform: DesktopScreenshotPlatform.windows,
      permissionCheck: () async {
        permissionChecks++;
        return false;
      },
      permissionRequest: () async => fail('must not request macOS access'),
      regionCapture: (path) async {
        await File(path).writeAsBytes(const [4, 5, 6], flush: true);
        return true;
      },
      temporaryDirectoryProvider: () async => temporaryDirectory,
    );

    final path = await service.capture();

    expect(permissionChecks, 0);
    expect(path, isNotNull);
    expect(await File(path!).exists(), isTrue);
  });

  test('cancelled or empty captures are not returned as attachments', () async {
    final cancelled = DesktopScreenshotService(
      platform: DesktopScreenshotPlatform.linux,
      regionCapture: (_) async => false,
      temporaryDirectoryProvider: () async => temporaryDirectory,
    );
    final empty = DesktopScreenshotService(
      platform: DesktopScreenshotPlatform.linux,
      regionCapture: (path) async {
        await File(path).create();
        return true;
      },
      temporaryDirectoryProvider: () async => temporaryDirectory,
    );

    expect(await cancelled.capture(), isNull);
    expect(await empty.capture(), isNull);
    expect(temporaryDirectory.listSync(), isEmpty);
  });
}
