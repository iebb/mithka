import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_image_loader.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const accountSlot = 7;
  late StreamController<Map<String, dynamic>> updates;
  late _DownloadBackend backend;

  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast(sync: true);
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: accountSlot,
        query: (request) => backend.query(request),
        send: (request) async => backend.send(request),
        updates: updates.stream,
      ),
    );
  });

  setUp(() => backend = _DownloadBackend());

  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  test(
    'a priority range completes without replacing its own download',
    () async {
      const offset = 1024 * 1024;
      const length = 6 * 1024 * 1024;
      final result = await TdFileCenter.shared.downloadPriorityRange(
        920001,
        accountSlot: accountSlot,
        offset: offset,
        length: length,
      );

      expect(result, isNotNull);
      expect(backend.replacedDownloads, 0);
      expect(backend.requests, hasLength(1));
      expect(result!['local'], containsPair('download_offset', offset));
      expect(result['local'], containsPair('downloaded_prefix_size', length));
      expect(result['local'], containsPair('is_downloading_completed', false));
    },
  );

  test('different files can still download concurrently', () async {
    final results = await Future.wait([
      for (final fileId in [920002, 920003])
        TdFileCenter.shared.downloadPriorityRange(
          fileId,
          accountSlot: accountSlot,
          offset: 0,
          length: 2 * 1024 * 1024,
        ),
    ]);

    expect(results, everyElement(isNotNull));
    expect(backend.replacedDownloads, 0);
    expect(backend.requests, hasLength(2));
  });

  testWidgets('range waits honor a timeout longer than the query default', (
    tester,
  ) async {
    backend.completionDelay = const Duration(seconds: 35);
    var finished = false;
    final download = TdFileCenter.shared
        .downloadPriorityRange(
          920004,
          accountSlot: accountSlot,
          offset: 0,
          length: 2 * 1024 * 1024,
        )
        .whenComplete(() => finished = true);

    await tester.pump(const Duration(seconds: 31));
    expect(finished, isFalse);
    await tester.pump(const Duration(seconds: 4));
    expect(await download, isNotNull);
  });

  test('whole-file progress and completion arrive after startup', () async {
    const fileId = 920005;
    backend.totalSize = 0;
    final result = await TdFileCenter.shared.downloadPriorityFile(
      fileId,
      accountSlot: accountSlot,
    );

    expect(result!['local'], containsPair('is_downloading_active', true));
    expect(result['local'], containsPair('is_downloading_completed', false));
    expect(backend.requests.single, {
      '@type': 'downloadFile',
      'file_id': fileId,
      'priority': 32,
      'offset': 0,
      'limit': 0,
      'synchronous': false,
    });

    final completion = TdFileCenter.shared
        .progress(fileId, accountSlot: accountSlot)
        .firstWhere((progress) => progress.isCompleted);
    // Let the initial getFile probe finish before the later completion update.
    await Future<void>.delayed(Duration.zero);
    backend.totalSize = 16 * 1024 * 1024;
    updates.add({
      '@type': 'updateFile',
      'file': backend.file(fileId, completed: true),
    });

    final progress = await completion;
    expect(progress.downloaded, backend.totalSize);
    expect(progress.fraction, 1);
    expect(
      TdFileCenter.shared.cachedPath(
        TdFileRef(id: fileId),
        accountSlot: accountSlot,
      ),
      '/tmp/mithka-priority-$fileId',
    );
  });

  test('canceling a range does not restart it in a Dart worker', () async {
    final download = TdFileCenter.shared.downloadPriorityRange(
      920006,
      accountSlot: accountSlot,
      offset: 0,
      length: 6 * 1024 * 1024,
    );
    TdFileCenter.shared.cancelDownload(920006, accountSlot: accountSlot);

    expect(await download, isNull);
    await Future<void>.delayed(Duration.zero);
    expect(backend.requests, hasLength(1));
    expect(backend.canceledFiles, contains(920006));
  });

  test(
    'canceling a whole file leaves no queued chunks to restart it',
    () async {
      await TdFileCenter.shared.downloadPriorityFile(
        920007,
        accountSlot: accountSlot,
      );
      TdFileCenter.shared.cancelDownload(920007, accountSlot: accountSlot);
      await Future<void>.delayed(Duration.zero);

      expect(backend.requests, hasLength(1));
      expect(backend.canceledFiles, contains(920007));
    },
  );

  test(
    'a rejected download is not reissued as an unlimited fallback',
    () async {
      backend.rejectDownloads = true;
      final result = await TdFileCenter.shared.downloadPriorityFile(
        920008,
        accountSlot: accountSlot,
      );

      expect(result, isNull);
      expect(backend.requests, hasLength(1));
    },
  );

  test(
    'a missing source account never falls back to the active account',
    () async {
      final result = await TdFileCenter.shared.downloadPriorityFile(
        920009,
        accountSlot: accountSlot + 1,
      );

      expect(result, isNull);
      expect(backend.requests, isEmpty);
    },
  );

  test('invalid ranges never start a transfer', () async {
    for (final (fileId, offset, length) in [
      (0, 0, 1024),
      (-1, 0, 1024),
      (920010, -1, 1024),
      (920010, 0, 0),
      (920010, 0, -1),
    ]) {
      expect(
        await TdFileCenter.shared.downloadPriorityRange(
          fileId,
          accountSlot: accountSlot,
          offset: offset,
          length: length,
        ),
        isNull,
      );
    }
    expect(backend.requests, isEmpty);
  });
}

/// Mirrors TDLib's one current user-requested range per file. A different
/// offset/limit cancels the previous synchronous request, even when both
/// requests have the same priority.
class _DownloadBackend {
  final requests = <Map<String, dynamic>>[];
  final pending =
      <
        int,
        ({int offset, int limit, Completer<Map<String, dynamic>> response})
      >{};
  final canceledFiles = <int>{};
  int replacedDownloads = 0;
  int totalSize = 16 * 1024 * 1024;
  Duration completionDelay = Duration.zero;
  bool rejectDownloads = false;

  Map<String, dynamic> file(
    int fileId, {
    int offset = 0,
    int downloaded = 0,
    bool active = false,
    bool completed = false,
  }) => {
    '@type': 'file',
    'id': fileId,
    'size': totalSize,
    'local': {
      '@type': 'localFile',
      'path': '/tmp/mithka-priority-$fileId',
      'download_offset': offset,
      'downloaded_prefix_size': completed ? totalSize : downloaded,
      'downloaded_size': completed ? totalSize : downloaded,
      'is_downloading_active': active,
      'is_downloading_completed': completed,
    },
  };

  Future<Map<String, dynamic>> query(Map<String, dynamic> request) {
    requests.add(request);
    final fileId = request['file_id'] as int;
    if (request['@type'] == 'getFile') {
      return Future.value(file(fileId, active: true));
    }
    if (rejectDownloads) {
      return Future.value({
        '@type': 'error',
        'code': 400,
        'message': 'File not found',
      });
    }
    final offset = request['offset'] as int;
    final limit = request['limit'] as int;
    final previous = pending[fileId];
    if (previous != null &&
        !previous.response.isCompleted &&
        (previous.offset != offset || previous.limit != limit)) {
      replacedDownloads++;
      previous.response.complete({
        '@type': 'error',
        'code': 200,
        'message': 'Canceled by another downloadFile request',
      });
    }
    canceledFiles.remove(fileId);
    if (request['synchronous'] == false) {
      return Future.value(file(fileId, active: true));
    }
    final response = Completer<Map<String, dynamic>>();
    pending[fileId] = (offset: offset, limit: limit, response: response);
    unawaited(
      Future<void>.delayed(completionDelay, () {
        if (!response.isCompleted) {
          response.complete(file(fileId, offset: offset, downloaded: limit));
        }
      }),
    );
    return response.future;
  }

  void send(Map<String, dynamic> request) {
    if (request['@type'] != 'cancelDownloadFile') return;
    final fileId = request['file_id'] as int;
    canceledFiles.add(fileId);
    final response = pending[fileId]?.response;
    if (response != null && !response.isCompleted) {
      response.complete({
        '@type': 'error',
        'code': 400,
        'message': 'File download has failed or was canceled',
      });
    }
  }
}
