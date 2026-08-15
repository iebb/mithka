import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/td_video_stream_server.dart';

void main() {
  test('detached windows receive sanitized live byte progress', () async {
    final fixture = await _VideoServerFixture.create(
      bytes: List<int>.generate(64, (index) => index),
      totalBytes: 4 * 1024 * 1024,
      maxResponseBytes: 16,
      reportedReadableBytes: 2 * 1024 * 1024,
    );
    try {
      final progressUri = tdVideoStreamProgressUri(fixture.uri);
      expect(progressUri.path, '${fixture.uri.path}.progress.json');

      final response = await fixture.getUri(progressUri);
      final payload = jsonDecode(utf8.decode(await _readBody(response)));

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.contentType?.mimeType, 'application/json');
      expect(
        response.headers.value(HttpHeaders.cacheControlHeader),
        'no-store',
      );
      expect(payload, containsPair('prefix_downloaded', 2 * 1024 * 1024));
      expect(payload, containsPair('downloaded', 2 * 1024 * 1024));
      expect(payload, containsPair('total', 4 * 1024 * 1024));
      expect(payload, containsPair('is_completed', false));
      expect(payload, isNot(contains('path')));
      expect(payload, isNot(contains('account')));
    } finally {
      await fixture.close();
    }
  });

  test(
    'a large request without Range returns one bounded exact body',
    () async {
      final fixture = await _VideoServerFixture.create(
        bytes: List<int>.generate(64, (index) => index),
        totalBytes: 1000000,
        maxResponseBytes: 16,
      );
      try {
        final response = await fixture.get();
        final body = await _readBody(response);

        expect(response.statusCode, HttpStatus.partialContent);
        expect(response.contentLength, 16);
        expect(
          response.headers.value(HttpHeaders.contentRangeHeader),
          'bytes 0-15/1000000',
        );
        expect(body, List<int>.generate(16, (index) => index));
      } finally {
        await fixture.close();
      }
    },
  );

  test('positive exact size wins over a larger expected size', () async {
    final fixture = await _VideoServerFixture.create(
      bytes: List<int>.generate(64, (index) => index),
      totalBytes: 64,
      expectedBytes: 1000000,
      maxResponseBytes: 16,
    );
    try {
      final response = await fixture.get(range: 'bytes=48-63');

      expect(response.statusCode, HttpStatus.partialContent);
      expect(response.contentLength, 16);
      expect(
        response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 48-63/64',
      );
      expect(await _readBody(response), fixture.bytes.sublist(48, 64));
    } finally {
      await fixture.close();
    }
  });

  test('an incomplete file stays on its loopback range source', () async {
    final fixture = await _VideoServerFixture.create(
      bytes: List<int>.generate(64, (index) => index),
      totalBytes: 1000000,
      maxResponseBytes: 16,
    );
    try {
      expect(fixture.uri.scheme, 'http');
      expect(fixture.uri.host, InternetAddress.loopbackIPv4.address);
      expect(fixture.uri.path, '/video/42.mp4');

      fixture.server.startBackgroundDownload();
      final response = await fixture.get(range: 'bytes=16-31');

      expect(response.statusCode, HttpStatus.partialContent);
      expect(
        response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 16-31/1000000',
      );
      expect(await _readBody(response), fixture.bytes.sublist(16, 32));
    } finally {
      await fixture.close();
    }
  });

  test('the loopback source preserves the video container metadata', () async {
    final fixture = await _VideoServerFixture.create(
      bytes: List<int>.generate(64, (index) => index),
      totalBytes: 64,
      maxResponseBytes: 64,
      fileName: 'sample.webm',
      mimeType: 'video/webm',
    );
    try {
      expect(fixture.uri.path, '/video/42.webm');
      final response = await fixture.get();
      expect(response.headers.contentType?.mimeType, 'video/webm');
      await _readBody(response);
    } finally {
      await fixture.close();
    }
  });

  test(
    'prepareForPlayback waits for bounded head and tail bootstrap ranges',
    () async {
      final fixture = await _PlaybackBootstrapFixture.create();
      var preparationCompleted = false;
      try {
        final preparation = fixture.server.prepareForPlayback().whenComplete(
          () => preparationCompleted = true,
        );

        await _waitFor(() => fixture.backend.boundedRequests.isNotEmpty);
        expect(
          fixture.backend.boundedRequests.first,
          containsPair('offset', 0),
        );
        expect(
          fixture.backend.boundedRequests.first,
          containsPair('limit', 2 * 1024 * 1024),
        );
        expect(
          fixture.backend.boundedRequests.first,
          containsPair('synchronous', true),
        );
        expect(preparationCompleted, isFalse);
        expect(
          fixture.backend.unlimitedRequests,
          0,
          reason: 'bootstrap must contain only bounded TDLib requests',
        );

        fixture.backend.completeBounded(0);
        await _waitFor(() => fixture.backend.boundedRequests.length == 2);
        expect(
          fixture.backend.boundedRequests[1],
          containsPair(
            'offset',
            _PlaybackBootstrapFixture.totalBytes - 4 * 1024 * 1024,
          ),
        );
        expect(
          fixture.backend.boundedRequests[1],
          containsPair('limit', 4 * 1024 * 1024),
        );
        expect(
          fixture.backend.boundedRequests[1],
          containsPair('synchronous', true),
        );
        expect(preparationCompleted, isFalse);
        expect(fixture.backend.unlimitedRequests, 0);

        fixture.backend.completeBounded(1);
        await preparation;
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(preparationCompleted, isTrue);
        expect(fixture.backend.boundedRequests, hasLength(2));
        expect(
          fixture.backend.unlimitedRequests,
          0,
          reason: 'preparation alone must not start a background download',
        );
      } finally {
        await fixture.close();
      }
    },
  );

  test(
    'background download requested during preparation waits for bounded work',
    () async {
      final fixture = await _PlaybackBootstrapFixture.create();
      try {
        final preparation = fixture.server.prepareForPlayback();
        await _waitFor(() => fixture.backend.boundedRequests.isNotEmpty);

        fixture.server.startBackgroundDownload();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(
          fixture.backend.unlimitedRequests,
          0,
          reason: 'the head bootstrap range is still pending',
        );

        fixture.backend.completeBounded(0);
        await _waitFor(() => fixture.backend.boundedRequests.length == 2);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(
          fixture.backend.unlimitedRequests,
          0,
          reason: 'the tail bootstrap range is still pending',
        );

        fixture.backend.completeBounded(1);
        await preparation;
        await _waitFor(() => fixture.backend.unlimitedRequests == 1);

        expect(fixture.backend.boundedRequests, hasLength(2));
        expect(fixture.backend.unlimitedRequests, 1);
      } finally {
        await fixture.close();
      }
    },
  );

  test('identical concurrent ranges share one bounded TDLib request', () async {
    late _ControlledRangeBackend backend;
    final fixture = await _VideoServerFixture.create(
      bytes: List<int>.generate(64, (index) => index),
      totalBytes: 1000000,
      reportedReadableBytes: 0,
      maxResponseBytes: 16,
      queryBuilder: (file) {
        backend = _ControlledRangeBackend(file: file, totalBytes: 1000000);
        return backend.query;
      },
    );
    try {
      final first = fixture.get(range: 'bytes=16-31');
      final second = fixture.get(range: 'bytes=16-31');

      await _waitFor(() => backend.prefixOffsets.length >= 2);
      await _waitFor(() => backend.boundedRequests.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(backend.boundedRequests, hasLength(1));
      expect(backend.boundedRequests.single['offset'], 16);
      expect(backend.boundedRequests.single['limit'], 16);

      backend.completeBounded(0);
      final responses = await Future.wait([first, second]);
      expect(
        responses.map((response) => response.statusCode),
        everyElement(HttpStatus.partialContent),
      );
      expect(await _readBody(responses[0]), fixture.bytes.sublist(16, 32));
      expect(await _readBody(responses[1]), fixture.bytes.sublist(16, 32));
    } finally {
      await fixture.close();
    }
  });

  test(
    'a bounded range burst restarts background download after draining',
    () async {
      late _ControlledRangeBackend backend;
      final fixture = await _VideoServerFixture.create(
        bytes: List<int>.generate(64, (index) => index),
        totalBytes: 1000000,
        reportedReadableBytes: 0,
        maxResponseBytes: 16,
        queryBuilder: (file) {
          backend = _ControlledRangeBackend(file: file, totalBytes: 1000000);
          return backend.query;
        },
      );
      try {
        final first = fixture.get(range: 'bytes=0-15');
        final second = fixture.get(range: 'bytes=16-31');

        await _waitFor(
          () =>
              backend.prefixOffsets.contains(0) &&
              backend.prefixOffsets.contains(16),
        );
        await _waitFor(() => backend.boundedRequests.isNotEmpty);
        fixture.server.startBackgroundDownload();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(backend.unlimitedRequests, 0);

        backend.completeBounded(0);
        await _waitFor(() => backend.boundedRequests.length == 2);
        expect(
          backend.unlimitedRequests,
          0,
          reason: 'queued bounded work must drain before restarting background',
        );

        backend.completeBounded(1);
        await _waitFor(() => backend.unlimitedRequests == 1);
        final responses = await Future.wait([first, second]);
        expect(
          responses.map((response) => response.statusCode),
          everyElement(HttpStatus.partialContent),
        );
        expect(await _readBody(responses[0]), fixture.bytes.sublist(0, 16));
        expect(await _readBody(responses[1]), fixture.bytes.sublist(16, 32));
        expect(backend.unlimitedRequests, 1);
      } finally {
        await fixture.close();
      }
    },
  );

  test('closing during a bounded range prevents background restart', () async {
    late _ControlledRangeBackend backend;
    final fixture = await _VideoServerFixture.create(
      bytes: List<int>.generate(64, (index) => index),
      totalBytes: 1000000,
      reportedReadableBytes: 0,
      maxResponseBytes: 16,
      queryBuilder: (file) {
        backend = _ControlledRangeBackend(file: file, totalBytes: 1000000);
        return backend.query;
      },
    );
    try {
      final response = fixture
          .get(range: 'bytes=16-31')
          .then<HttpClientResponse?>((value) => value, onError: (_) => null);
      await _waitFor(() => backend.boundedRequests.isNotEmpty);
      expect(backend.unlimitedRequests, 0);

      final close = fixture.server.close();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      backend.completeBounded(0);
      await close;
      await response.timeout(const Duration(seconds: 1), onTimeout: () => null);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        backend.unlimitedRequests,
        0,
        reason: 'a closed server must not restart background downloading',
      );
    } finally {
      await fixture.close();
    }
  });

  test(
    'closing during the initial query prevents a listener from starting',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mithka-video-start-race-test-',
      );
      final file = File('${directory.path}/video.mp4');
      await file.writeAsBytes(List<int>.generate(64, (index) => index));
      final backend = _DelayedStartBackend(file: file, totalBytes: 64);
      final server = TdVideoStreamServer(42, query: backend.query);
      try {
        final start = server.start();
        await backend.initialQueryStarted.future.timeout(
          const Duration(seconds: 1),
        );

        await server.close();
        backend.releaseInitialQuery();

        expect(await start, isNull);
        expect(backend.downloadRequests, 0);
        expect(await server.start(), isNull);
        expect(backend.getFileRequests, 1);
      } finally {
        backend.releaseInitialQuery();
        await server.close();
        if (await directory.exists()) await directory.delete(recursive: true);
      }
    },
  );

  test('an unavailable first range fails before successful headers', () async {
    final fixture = await _VideoServerFixture.create(
      bytes: const [],
      totalBytes: 1000000,
      reportedReadableBytes: 0,
      maxResponseBytes: 16,
    );
    try {
      final response = await fixture.get(range: 'bytes=0-15');
      final body = await _readBody(response);

      expect(response.statusCode, HttpStatus.serviceUnavailable);
      expect(response.contentLength, 0);
      expect(response.headers.value(HttpHeaders.retryAfterHeader), '1');
      expect(body, isEmpty);
    } finally {
      await fixture.close();
    }
  });

  test('a truncated local range becomes an empty retryable response', () async {
    final fixture = await _VideoServerFixture.create(
      bytes: const [1, 2, 3, 4],
      totalBytes: 1000000,
      reportedReadableBytes: 16,
      maxResponseBytes: 16,
    );
    try {
      final response = await fixture.get(range: 'bytes=0-15');
      final body = await _readBody(response);

      expect(response.statusCode, HttpStatus.serviceUnavailable);
      expect(response.contentLength, 0);
      expect(body, isEmpty);
    } finally {
      await fixture.close();
    }
  });

  test('a cancelled response does not poison a later range request', () async {
    final fixture = await _VideoServerFixture.create(
      bytes: List<int>.generate(256 * 1024, (index) => index % 251),
      totalBytes: 1000000,
      maxResponseBytes: 256 * 1024,
    );
    final cancelledClient = HttpClient();
    try {
      final request = await cancelledClient.getUrl(fixture.uri);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-262143');
      final response = await request.close();
      final firstChunk = Completer<void>();
      late StreamSubscription<List<int>> subscription;
      subscription = response.listen((_) {
        if (!firstChunk.isCompleted) firstChunk.complete();
      });
      await firstChunk.future.timeout(const Duration(seconds: 2));
      await subscription.cancel();
      cancelledClient.close(force: true);

      final followUp = await fixture.get(range: 'bytes=16-31');
      expect(followUp.statusCode, HttpStatus.partialContent);
      expect(await _readBody(followUp), fixture.bytes.sublist(16, 32));
    } finally {
      cancelledClient.close(force: true);
      await fixture.close();
    }
  });

  test('a held server answers only once its preparation settles', () async {
    final fixture = await _VideoServerFixture.create(
      bytes: List<int>.generate(64, (index) => index),
      totalBytes: 64,
      maxResponseBytes: 16,
    );
    final preparation = Completer<bool>();
    try {
      fixture.server.holdRequestsUntilPrepared(preparation.future);

      var answered = false;
      final response = fixture.get(range: 'bytes=0-15')
        ..then((_) => answered = true).ignore();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(
        answered,
        isFalse,
        reason: 'the window opens first, so early probes must wait',
      );

      preparation.complete(true);
      final resolved = await response.timeout(const Duration(seconds: 2));
      expect(resolved.statusCode, HttpStatus.partialContent);
      expect(await _readBody(resolved), fixture.bytes.sublist(0, 16));
    } finally {
      if (!preparation.isCompleted) preparation.complete(false);
      await fixture.close();
    }
  });

  test('a failed preparation still serves the range it can read', () async {
    final fixture = await _VideoServerFixture.create(
      bytes: List<int>.generate(64, (index) => index),
      totalBytes: 64,
      maxResponseBytes: 16,
    );
    try {
      fixture.server.holdRequestsUntilPrepared(Future<bool>.value(false));

      final response = await fixture.get(range: 'bytes=0-15');
      expect(response.statusCode, HttpStatus.partialContent);
      expect(await _readBody(response), fixture.bytes.sublist(0, 16));
    } finally {
      await fixture.close();
    }
  });
}

Future<List<int>> _readBody(HttpClientResponse response) =>
    response.fold(<int>[], (body, chunk) => body..addAll(chunk));

Future<void> _waitFor(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not reached within 2 seconds');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

final class _VideoServerFixture {
  _VideoServerFixture._({
    required this.directory,
    required this.bytes,
    required this.server,
    required this.uri,
  });

  final Directory directory;
  final List<int> bytes;
  final TdVideoStreamServer server;
  final Uri uri;
  final List<HttpClient> _clients = [];

  static Future<_VideoServerFixture> create({
    required List<int> bytes,
    required int totalBytes,
    required int maxResponseBytes,
    int? expectedBytes,
    int? reportedReadableBytes,
    String? fileName,
    String? mimeType,
    TdVideoStreamQuery Function(File file)? queryBuilder,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'mithka-video-stream-test-',
    );
    final file = File('${directory.path}/video.mp4');
    await file.writeAsBytes(bytes, flush: true);
    final backend = _FakeTdVideoBackend(
      file: file,
      totalBytes: totalBytes,
      expectedBytes: expectedBytes ?? totalBytes,
      reportedReadableBytes: reportedReadableBytes ?? bytes.length,
    );
    final server = TdVideoStreamServer(
      42,
      query: queryBuilder?.call(file) ?? backend.query,
      fileName: fileName,
      mimeType: mimeType,
      maxResponseBytes: maxResponseBytes,
      rangeWaitTimeout: const Duration(milliseconds: 20),
      rangePollInterval: const Duration(milliseconds: 1),
    );
    final uri = await server.start();
    if (uri == null) {
      await directory.delete(recursive: true);
      throw StateError('The video stream server did not start');
    }
    return _VideoServerFixture._(
      directory: directory,
      bytes: bytes,
      server: server,
      uri: uri,
    );
  }

  Future<HttpClientResponse> get({String? range}) async {
    return getUri(uri, range: range);
  }

  Future<HttpClientResponse> getUri(Uri target, {String? range}) async {
    final client = HttpClient();
    _clients.add(client);
    try {
      final request = await client.getUrl(target);
      if (range != null) {
        request.headers.set(HttpHeaders.rangeHeader, range);
      }
      return request.close();
    } catch (_) {
      client.close(force: true);
      _clients.remove(client);
      rethrow;
    }
  }

  Future<void> close() async {
    for (final client in _clients) {
      client.close(force: true);
    }
    _clients.clear();
    await server.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

final class _FakeTdVideoBackend {
  const _FakeTdVideoBackend({
    required this.file,
    required this.totalBytes,
    required this.expectedBytes,
    required this.reportedReadableBytes,
  });

  final File file;
  final int totalBytes;
  final int expectedBytes;
  final int reportedReadableBytes;

  Future<Map<String, dynamic>> query(Map<String, dynamic> request) async {
    switch (request['@type']) {
      case 'getFile':
      case 'downloadFile':
        return _fileInfo();
      case 'getFileDownloadedPrefixSize':
        final offset = request['offset'] as int? ?? 0;
        return {
          '@type': 'fileDownloadedPrefixSize',
          'size': (reportedReadableBytes - offset).clamp(0, totalBytes),
        };
      default:
        throw UnsupportedError('Unexpected TDLib query ${request['@type']}');
    }
  }

  Map<String, dynamic> _fileInfo() => {
    '@type': 'file',
    'id': 42,
    'size': totalBytes,
    'expected_size': expectedBytes,
    'local': {
      '@type': 'localFile',
      'path': file.path,
      'download_offset': 0,
      'downloaded_prefix_size': reportedReadableBytes,
      'is_downloading_completed': false,
    },
  };
}

final class _ControlledRangeBackend {
  _ControlledRangeBackend({required this.file, required this.totalBytes});

  final File file;
  final int totalBytes;
  final prefixOffsets = <int>[];
  final boundedRequests = <Map<String, dynamic>>[];
  final _boundedGates = <Completer<void>>[];
  var readableBytes = 0;
  var unlimitedRequests = 0;

  Future<Map<String, dynamic>> query(Map<String, dynamic> request) async {
    switch (request['@type']) {
      case 'getFile':
        return _fileInfo();
      case 'getFileDownloadedPrefixSize':
        final offset = request['offset'] as int? ?? 0;
        prefixOffsets.add(offset);
        return {
          '@type': 'fileDownloadedPrefixSize',
          'size': (readableBytes - offset).clamp(0, totalBytes),
        };
      case 'downloadFile':
        final limit = request['limit'] as int? ?? 0;
        if (limit == 0) {
          unlimitedRequests++;
          return _fileInfo();
        }
        final copy = Map<String, dynamic>.from(request);
        final gate = Completer<void>();
        boundedRequests.add(copy);
        _boundedGates.add(gate);
        await gate.future;
        final offset = copy['offset'] as int? ?? 0;
        final readableEnd = offset + limit;
        if (readableEnd > readableBytes) readableBytes = readableEnd;
        return _fileInfo();
      default:
        throw UnsupportedError('Unexpected TDLib query ${request['@type']}');
    }
  }

  void completeBounded(int index) {
    final gate = _boundedGates[index];
    if (!gate.isCompleted) gate.complete();
  }

  Map<String, dynamic> _fileInfo() => {
    '@type': 'file',
    'id': 42,
    'size': totalBytes,
    'expected_size': totalBytes,
    'local': {
      '@type': 'localFile',
      'path': file.path,
      'download_offset': 0,
      'downloaded_prefix_size': readableBytes,
      'is_downloading_completed': false,
    },
  };
}

final class _PlaybackBootstrapFixture {
  _PlaybackBootstrapFixture._({
    required this.directory,
    required this.server,
    required this.backend,
  });

  static const totalBytes = 10 * 1024 * 1024;

  final Directory directory;
  final TdVideoStreamServer server;
  final _PlaybackBootstrapBackend backend;

  static Future<_PlaybackBootstrapFixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'mithka-video-bootstrap-test-',
    );
    final file = File('${directory.path}/video.mp4');
    final handle = await file.open(mode: FileMode.write);
    await handle.truncate(totalBytes);
    await handle.close();
    final backend = _PlaybackBootstrapBackend(
      file: file,
      totalBytes: totalBytes,
    );
    final server = TdVideoStreamServer(
      42,
      query: backend.query,
      rangeWaitTimeout: const Duration(seconds: 1),
      rangePollInterval: const Duration(milliseconds: 1),
    );
    final uri = await server.start();
    if (uri == null) {
      await directory.delete(recursive: true);
      throw StateError('The video stream server did not start');
    }
    return _PlaybackBootstrapFixture._(
      directory: directory,
      server: server,
      backend: backend,
    );
  }

  Future<void> close() async {
    backend.completeAllBounded();
    await server.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

final class _PlaybackBootstrapBackend {
  _PlaybackBootstrapBackend({required this.file, required this.totalBytes});

  final File file;
  final int totalBytes;
  final boundedRequests = <Map<String, dynamic>>[];
  final _boundedGates = <Completer<void>>[];
  final _readableRanges = <(int, int)>[];
  var unlimitedRequests = 0;

  Future<Map<String, dynamic>> query(Map<String, dynamic> request) async {
    switch (request['@type']) {
      case 'getFile':
        return _fileInfo();
      case 'getFileDownloadedPrefixSize':
        final offset = request['offset'] as int? ?? 0;
        return {
          '@type': 'fileDownloadedPrefixSize',
          'size': _readablePrefixFrom(offset),
        };
      case 'downloadFile':
        final limit = request['limit'] as int? ?? 0;
        if (limit == 0) {
          unlimitedRequests++;
          return _fileInfo();
        }
        final copy = Map<String, dynamic>.from(request);
        final gate = Completer<void>();
        boundedRequests.add(copy);
        _boundedGates.add(gate);
        await gate.future;
        final offset = copy['offset'] as int? ?? 0;
        _readableRanges.add((offset, offset + limit));
        return _fileInfo();
      default:
        throw UnsupportedError('Unexpected TDLib query ${request['@type']}');
    }
  }

  void completeBounded(int index) {
    final gate = _boundedGates[index];
    if (!gate.isCompleted) gate.complete();
  }

  void completeAllBounded() {
    for (final gate in _boundedGates) {
      if (!gate.isCompleted) gate.complete();
    }
  }

  int _readablePrefixFrom(int offset) {
    for (final (start, end) in _readableRanges) {
      if (start <= offset && offset < end) return end - offset;
    }
    return 0;
  }

  int get _downloadedHeadBytes => _readablePrefixFrom(0);

  Map<String, dynamic> _fileInfo() => {
    '@type': 'file',
    'id': 42,
    'size': totalBytes,
    'expected_size': totalBytes,
    'local': {
      '@type': 'localFile',
      'path': file.path,
      'download_offset': 0,
      'downloaded_prefix_size': _downloadedHeadBytes,
      'is_downloading_completed': false,
    },
  };
}

final class _DelayedStartBackend {
  _DelayedStartBackend({required this.file, required this.totalBytes});

  final File file;
  final int totalBytes;
  final initialQueryStarted = Completer<void>();
  final _initialQueryRelease = Completer<void>();
  var getFileRequests = 0;
  var downloadRequests = 0;

  Future<Map<String, dynamic>> query(Map<String, dynamic> request) async {
    switch (request['@type']) {
      case 'getFile':
        getFileRequests++;
        if (!initialQueryStarted.isCompleted) initialQueryStarted.complete();
        await _initialQueryRelease.future;
        return _fileInfo();
      case 'downloadFile':
        downloadRequests++;
        return _fileInfo();
      default:
        throw UnsupportedError('Unexpected TDLib query ${request['@type']}');
    }
  }

  void releaseInitialQuery() {
    if (!_initialQueryRelease.isCompleted) _initialQueryRelease.complete();
  }

  Map<String, dynamic> _fileInfo() => {
    '@type': 'file',
    'id': 42,
    'size': totalBytes,
    'expected_size': totalBytes,
    'local': {
      '@type': 'localFile',
      'path': file.path,
      'download_offset': 0,
      'downloaded_prefix_size': totalBytes,
      'is_downloading_completed': false,
    },
  };
}
