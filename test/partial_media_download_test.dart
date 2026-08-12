import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_image_loader.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<Map<String, dynamic>> updates;
  late Map<int, Future<Map<String, dynamic>> Function(Map<String, dynamic>)>
  handlers;
  late List<Map<String, dynamic>> sentRequests;
  late Directory temporaryDirectory;
  late File completedImage;

  setUpAll(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'mithka-partial-media-test-',
    );
    completedImage = File('${temporaryDirectory.path}/complete.png');
    await completedImage.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
        'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    handlers = {};
    updates = StreamController<Map<String, dynamic>>.broadcast(sync: true);
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) {
          final fileId = request['file_id'];
          final handler = fileId is int ? handlers[fileId] : null;
          if (handler == null) {
            throw StateError('No file handler for $request');
          }
          return handler(request);
        },
        send: (request) async => sentRequests.add(request),
        updates: updates.stream,
      ),
    );
  });

  setUp(() => sentRequests = []);

  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('parsed partial TDLib paths are not treated as complete sources', () {
    final partial = TDParse.fileRef(
      _file(
        id: 910001,
        downloaded: 24,
        active: true,
        completed: false,
        path: '/tmp/partial-image.jpg',
      ),
    );
    final completed = TDParse.fileRef(
      _file(
        id: 910002,
        downloaded: 100,
        active: false,
        completed: true,
        path: '/tmp/complete-image.jpg',
      ),
    );

    expect(partial?.localPath, isNull);
    expect(completed?.localPath, '/tmp/complete-image.jpg');
    expect(
      TdFileRef(id: 910003, localPath: '/tmp/outgoing-source.jpg').localPath,
      '/tmp/outgoing-source.jpg',
      reason: 'explicit outgoing sources remain immediately usable',
    );
  });

  testWidgets('partial media cannot remain on a stale progress state', (
    tester,
  ) async {
    {
      const fileId = 910006;
      handlers[fileId] = (request) async => _file(
        id: fileId,
        downloaded: 24,
        active: true,
        completed: false,
        path: '${temporaryDirectory.path}/partial.png',
      );

      await _pumpImage(tester, fileId);
      expect(find.text('24%'), findsOneWidget);

      await tester.pump(const Duration(seconds: 16));
      expect(
        sentRequests.where(
          (request) =>
              request['@type'] == 'downloadFile' &&
              request['file_id'] == fileId &&
              request['priority'] == 32,
        ),
        hasLength(1),
      );

      // A failed automatic resume must not leave the old percentage spinning
      // until the much longer path timeout. It becomes an explicit retry
      // affordance after one bounded grace interval.
      await tester.pump(const Duration(seconds: 16));
      expect(sentRequests, hasLength(1));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('24%'), findsNothing);
      expect(
        find.byKey(const ValueKey('td-image-download-retry')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('td-image-download-retry')));
      await tester.pump();
      expect(sentRequests, hasLength(2));

      updates.add({
        '@type': 'updateFile',
        'file': _file(
          id: fileId,
          downloaded: 25,
          active: true,
          completed: false,
          path: '${temporaryDirectory.path}/partial.png',
        ),
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 16));
      expect(sentRequests, hasLength(3));

      updates.add({
        '@type': 'updateFile',
        'file': _file(
          id: fileId,
          downloaded: 100,
          active: false,
          completed: true,
          path: completedImage.path,
        ),
      });
      await tester.pump();
      await tester.pump();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    sentRequests.clear();

    {
      const fileId = 910011;
      handlers[fileId] = (request) async => _file(
        id: fileId,
        downloaded: 24,
        active: true,
        completed: false,
        path: '${temporaryDirectory.path}/partial.png',
      );

      await _pumpImage(tester, fileId);
      expect(find.text('24%'), findsOneWidget);

      updates.add({
        '@type': 'updateFile',
        'file': _file(
          id: fileId,
          downloaded: 24,
          active: false,
          completed: false,
          path: '${temporaryDirectory.path}/partial.png',
        ),
      });
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('24%'), findsNothing);
      expect(
        find.byKey(const ValueKey('td-image-download-retry')),
        findsNothing,
      );

      // Complete the underlying path waiter so the test leaves no long timer.
      updates.add({
        '@type': 'updateFile',
        'file': _file(
          id: fileId,
          downloaded: 100,
          active: false,
          completed: true,
          path: completedImage.path,
        ),
      });
      await tester.pump();
      await tester.pump();
      await tester.pump();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    sentRequests.clear();

    {
      const fileId = 910021;
      final strandedDownloadResponse = Completer<Map<String, dynamic>>();
      handlers[fileId] = (request) {
        if (request['@type'] == 'downloadFile') {
          return strandedDownloadResponse.future;
        }
        return Future.value(
          _file(
            id: fileId,
            downloaded: 24,
            active: true,
            completed: false,
            path: '${temporaryDirectory.path}/partial.png',
          ),
        );
      };

      await _pumpImage(tester, fileId);
      expect(find.text('24%'), findsOneWidget);

      // This proves the timeout is installed independently of the stranded
      // immediate downloadFile response.
      await tester.pump(const Duration(seconds: 181));
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('24%'), findsNothing);
      expect(
        find.byKey(const ValueKey('td-image-download-retry')),
        findsOneWidget,
      );
      expect(strandedDownloadResponse.isCompleted, isFalse);
      expect(sentRequests, hasLength(1));
      expect(sentRequests.single, {
        '@type': 'downloadFile',
        'file_id': fileId,
        'priority': 32,
        'offset': 0,
        'limit': 0,
        'synchronous': false,
      });

      // Completion may still arrive after the bound; it must replace the
      // placeholder from TdFileCenter's completed-path cache.
      updates.add({
        '@type': 'updateFile',
        'file': _file(
          id: fileId,
          downloaded: 100,
          active: false,
          completed: true,
          path: completedImage.path,
        ),
      });
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        TdFileCenter.shared.cachedPath(TdFileRef(id: fileId)),
        completedImage.path,
      );
      final providers = tester
          .widgetList<Image>(find.byType(Image))
          .map((image) => image.image)
          .toList();
      expect(
        providers.any(_isFileImageProvider),
        isTrue,
        reason:
            'providers: ${providers.map((provider) => provider.runtimeType)}',
      );
      expect(tester.takeException(), isNull);
    }
  });
}

bool _isFileImageProvider(ImageProvider provider) =>
    provider is FileImage ||
    (provider is ResizeImage && provider.imageProvider is FileImage);

Future<void> _pumpImage(WidgetTester tester, int fileId) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox.square(
          dimension: 160,
          child: TDImage(
            photo: TdFileRef(
              id: fileId,
              miniThumb: base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
                'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
              ),
            ),
            cornerRadius: 0,
            cacheWidth: 160,
            cacheHeight: 160,
            showProgress: true,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

Map<String, dynamic> _file({
  required int id,
  required int downloaded,
  required bool active,
  required bool completed,
  required String path,
}) => {
  '@type': 'file',
  'id': id,
  'size': 100,
  'expected_size': 100,
  'local': {
    '@type': 'localFile',
    'path': path,
    'downloaded_size': downloaded,
    'downloaded_prefix_size': downloaded,
    'is_downloading_active': active,
    'is_downloading_completed': completed,
  },
};
