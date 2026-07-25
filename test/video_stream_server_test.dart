import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/video_player_view.dart';

void main() {
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
}

Future<List<int>> _readBody(HttpClientResponse response) =>
    response.fold(<int>[], (body, chunk) => body..addAll(chunk));

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
    int? reportedReadableBytes,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'mithka-video-stream-test-',
    );
    final file = File('${directory.path}/video.mp4');
    await file.writeAsBytes(bytes, flush: true);
    final backend = _FakeTdVideoBackend(
      file: file,
      totalBytes: totalBytes,
      reportedReadableBytes: reportedReadableBytes ?? bytes.length,
    );
    final server = TdVideoStreamServer(
      42,
      query: backend.query,
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
    final client = HttpClient();
    _clients.add(client);
    try {
      final request = await client.getUrl(uri);
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
    required this.reportedReadableBytes,
  });

  final File file;
  final int totalBytes;
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
    'expected_size': totalBytes,
    'local': {
      '@type': 'localFile',
      'path': file.path,
      'download_offset': 0,
      'downloaded_prefix_size': reportedReadableBytes,
      'is_downloading_completed': false,
    },
  };
}
