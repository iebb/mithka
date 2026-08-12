//
//  td_video_stream_server.dart
//
//  TDLib-backed loopback HTTP range streaming for partially downloaded
//  Telegram videos.
//

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';

typedef TdVideoStreamQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

const _videoStreamExtensions = <String, String>{
  'video/mp4': 'mp4',
  'video/quicktime': 'mov',
  'video/webm': 'webm',
  'video/x-matroska': 'mkv',
  'video/mpeg': 'mpeg',
  'video/x-msvideo': 'avi',
  'video/3gpp': '3gp',
  'video/3gpp2': '3g2',
};

const _videoStreamMimeTypesByExtension = <String, String>{
  'mp4': 'video/mp4',
  'm4v': 'video/mp4',
  'mov': 'video/quicktime',
  'webm': 'video/webm',
  'mkv': 'video/x-matroska',
  'mpeg': 'video/mpeg',
  'mpg': 'video/mpeg',
  'avi': 'video/x-msvideo',
  '3gp': 'video/3gpp',
  '3g2': 'video/3gpp2',
};

String? _safeFileExtension(String? fileName) {
  final name = fileName?.trim().toLowerCase() ?? '';
  final separator = name.lastIndexOf('.');
  if (separator < 0 || separator + 1 >= name.length) return null;
  final extension = name.substring(separator + 1);
  return RegExp(r'^[a-z0-9]{1,8}$').hasMatch(extension) ? extension : null;
}

String _videoStreamMimeType(String? fileName, String? value) {
  final mimeType = value?.split(';').first.trim().toLowerCase();
  if (mimeType != null && mimeType.startsWith('video/')) return mimeType;
  final extension = _safeFileExtension(fileName);
  return _videoStreamMimeTypesByExtension[extension] ?? 'video/mp4';
}

String _videoStreamExtension(String? fileName, String mimeType) {
  final mapped = _videoStreamExtensions[mimeType];
  if (mapped != null) return mapped;
  return _safeFileExtension(fileName) ?? 'mp4';
}

TdVideoStreamQuery tdVideoStreamQueryForAccount(int? accountSlot) {
  if (accountSlot == null) return TdClient.shared.query;
  return (request) => TdClient.shared.queryForSlot(request, accountSlot);
}

/// A loopback range server for partially downloaded TDLib videos.
///
/// The class is public only so its HTTP behavior can be exercised without a
/// native media player in tests. App code should treat it as an implementation
/// detail of the Telegram video playback adapter.
class TdVideoStreamServer {
  TdVideoStreamServer(
    this.fileId, {
    TdVideoStreamQuery? query,
    String? fileName,
    String? mimeType,
    int maxResponseBytes = _defaultMaxResponseBytes,
    this.rangeWaitTimeout = const Duration(seconds: 45),
    this.rangePollInterval = const Duration(milliseconds: 100),
  }) : assert(maxResponseBytes > 0),
       _query = query ?? TdClient.shared.query,
       _maxResponseBytes = maxResponseBytes,
       _mimeType = _videoStreamMimeType(fileName, mimeType),
       _extension = _videoStreamExtension(
         fileName,
         _videoStreamMimeType(fileName, mimeType),
       );

  final int fileId;
  final TdVideoStreamQuery _query;
  final int _maxResponseBytes;
  final String _mimeType;
  final String _extension;
  final Duration rangeWaitTimeout;
  final Duration rangePollInterval;
  HttpServer? _server;
  String? _path;
  int _total = 0;
  int _downloadOffset = 0;
  int _downloadedPrefixSize = 0;
  bool _downloadComplete = false;
  bool _closed = false;
  bool _backgroundDownloadRequested = false;
  int _playbackPreparationCount = 0;
  Future<bool>? _pendingPreparation;
  int? _continuousDownloadOffset;
  Future<void> _downloadQueue = Future<void>.value();
  final Map<(int, int), Future<Map<String, dynamic>?>> _rangeDownloads = {};

  static const _chunkSize = 2 * 1024 * 1024;
  static const _defaultMaxResponseBytes = 2 * 1024 * 1024;
  static const _metadataTailSize = 4 * 1024 * 1024;

  Future<Uri?> start() async {
    if (_closed) return null;
    try {
      final file = await _query({'@type': 'getFile', 'file_id': fileId});
      _updateFileInfo(file);
    } catch (_) {}
    if (_closed) return null;

    if (_path == null || _path!.isEmpty || _total <= 0) {
      await _primePlaybackRange(0, _chunkSize);
    }
    if (_closed) return null;
    if (_total <= 0) {
      try {
        final file = await _query({'@type': 'getFile', 'file_id': fileId});
        _updateFileInfo(file);
      } catch (_) {}
    }
    if (_closed || _total <= 0) return null;
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: true,
    );
    if (_closed) {
      await server.close(force: true);
      return null;
    }
    _server = server;
    server.listen(_handleRequest);
    return Uri.parse(
      'http://127.0.0.1:${server.port}/video/$fileId.$_extension',
    );
  }

  Future<void> close() async {
    _closed = true;
    await _server?.close(force: true);
    _server = null;
  }

  /// Makes the MP4 header and trailing metadata readable before a native
  /// player probes the loopback URL. Many Telegram videos keep the `moov` atom
  /// at EOF; exposing the URL before both ranges exist makes a transient TDLib
  /// range miss look like an unsupported file to native media backends.
  Future<bool> prepareForPlayback() async {
    if (_closed || _total <= 0) return false;
    _playbackPreparationCount++;
    try {
      final headEnd = math.min(_total - 1, _chunkSize - 1);
      if (!await _ensureRange(0, headEnd)) return false;
      final tailStart = math.max(0, _total - _metadataTailSize);
      return await _ensureRange(tailStart, _total - 1);
    } finally {
      _playbackPreparationCount--;
      if (_playbackPreparationCount == 0 &&
          _backgroundDownloadRequested &&
          _rangeDownloads.isEmpty) {
        unawaited(_startContinuousDownload(0));
      }
    }
  }

  /// Serves nothing until [preparation] settles.
  ///
  /// A caller that hands the URL to a player before [prepareForPlayback] has
  /// finished — the desktop window opens right away so the user is not left
  /// waiting on an idle chat — uses this so the first probe waits for the
  /// bootstrap ranges instead of reading a transient range miss as an
  /// unsupported file.
  void holdRequestsUntilPrepared(Future<bool> preparation) {
    // A failed preparation must release the gate rather than fail the request:
    // the per-range download is still the authority on what can be served.
    final gate = preparation.then<bool>(
      (prepared) => prepared,
      onError: (_, _) => false,
    );
    _pendingPreparation = gate;
    unawaited(
      gate.whenComplete(() {
        if (identical(_pendingPreparation, gate)) _pendingPreparation = null;
      }),
    );
  }

  void startBackgroundDownload() {
    if (_closed || _downloadComplete) return;
    _backgroundDownloadRequested = true;
    if (_playbackPreparationCount == 0 && _rangeDownloads.isEmpty) {
      unawaited(_startContinuousDownload(0));
    }
  }

  /// Creates TDLib's partial file using a bounded request. Keeping the first
  /// request finite is important when transfer boost is enabled: an unlimited
  /// download can have many large parts in flight, and changing that same
  /// download to a playback range forces TDLib to cancel those parts before it
  /// can serve the player.
  Future<void> _primePlaybackRange(int offset, int length) async {
    if (_closed) return;
    try {
      final file = await _query({
        '@type': 'downloadFile',
        'file_id': fileId,
        'priority': 32,
        'offset': offset,
        'limit': length,
        'synchronous': false,
      });
      _updateFileInfo(file);
    } catch (_) {}
  }

  void _updateFileInfo(Map<String, dynamic> file) {
    final expected = file.integer('expected_size') ?? 0;
    final size = file.integer('size') ?? 0;
    if (size > 0 || expected > 0) {
      _total = size > 0 ? size : expected;
    }
    final path = file.obj('local')?.str('path');
    if (path != null && path.isNotEmpty) _path = path;
    final local = file.obj('local');
    _downloadOffset = local?.integer('download_offset') ?? _downloadOffset;
    final prefix = local?.integer('downloaded_prefix_size') ?? 0;
    _downloadedPrefixSize = prefix;
    _downloadComplete =
        local?.boolean('is_downloading_completed') == true && _total > 0;
    if (_downloadComplete) {
      _downloadOffset = 0;
      _downloadedPrefixSize = _total;
      _continuousDownloadOffset = null;
    }
  }

  Future<void> _startContinuousDownload(int offset) async {
    if (_closed ||
        _downloadComplete ||
        !_backgroundDownloadRequested ||
        _playbackPreparationCount > 0 ||
        _rangeDownloads.isNotEmpty ||
        _continuousDownloadOffset == offset) {
      return;
    }
    _continuousDownloadOffset = offset;
    try {
      final file = await _query({
        '@type': 'downloadFile',
        'file_id': fileId,
        'priority': 32,
        'offset': offset,
        'limit': 0,
        'synchronous': false,
      });
      _updateFileInfo(file);
    } catch (_) {
      if (_continuousDownloadOffset == offset) {
        _continuousDownloadOffset = null;
      }
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    var requestFinished = false;
    unawaited(
      request.response.done.then<void>(
        (_) => requestFinished = true,
        onError: (_, _) => requestFinished = true,
      ),
    );
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
      }

      request.response.headers
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..contentType = ContentType.parse(_mimeType);

      final preparation = _pendingPreparation;
      if (preparation != null) {
        await preparation;
        if (requestFinished || _closed) return;
      }

      if (_total <= 0) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      final range = rangeHeader == null ? null : _requestedRange(rangeHeader);
      if (rangeHeader != null && range == null) {
        request.response
          ..statusCode = HttpStatus.requestedRangeNotSatisfiable
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$_total');
        await request.response.close();
        return;
      }
      final (start, end) = range ?? (0, _total - 1);
      if (request.method == 'HEAD') {
        if (range == null) {
          _writeRangeHeaders(request.response, start, end, false);
        } else {
          final boundedEnd = _boundedEnd(start, end);
          _writeRangeHeaders(request.response, start, boundedEnd, true);
        }
        await request.response.close();
        return;
      }

      final boundedEnd = _boundedEnd(start, end);
      final partial = range != null || boundedEnd < _total - 1;
      final bytes = await _loadRange(
        start,
        boundedEnd,
        isCancelled: () => requestFinished,
      );
      if (requestFinished) return;
      if (bytes == null) {
        await _closeEmptyResponse(
          request.response,
          HttpStatus.serviceUnavailable,
          retryAfter: const Duration(seconds: 1),
        );
        return;
      }
      _writeRangeHeaders(request.response, start, boundedEnd, partial);
      request.response.add(bytes);
      await request.response.close();
    } catch (_) {
      // The player may cancel a range request after headers were sent. Do not
      // attempt to mutate that response again; just finish it if it is open.
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.contentLength = 0;
      } catch (_) {
        // Headers were already sent.
      }
      try {
        await request.response.close();
      } catch (_) {
        // The client already closed the response.
      }
    }
  }

  int _boundedEnd(int start, int requestedEnd) => math.min(
    requestedEnd,
    math.min(_total - 1, start + _maxResponseBytes - 1),
  );

  Future<void> _closeEmptyResponse(
    HttpResponse response,
    int statusCode, {
    Duration? retryAfter,
  }) async {
    response
      ..statusCode = statusCode
      ..contentLength = 0;
    if (retryAfter != null) {
      response.headers.set(
        HttpHeaders.retryAfterHeader,
        retryAfter.inSeconds.toString(),
      );
    }
    await response.close();
  }

  void _writeRangeHeaders(
    HttpResponse response,
    int start,
    int end,
    bool partial,
  ) {
    response
      ..statusCode = partial ? HttpStatus.partialContent : HttpStatus.ok
      ..contentLength = end - start + 1;
    if (partial) {
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$_total',
      );
    }
  }

  /// Loads the complete bounded response before committing its headers.
  /// AVFoundation validates `Content-Length` strictly, so an unavailable or
  /// truncated TDLib range must become an empty retryable response rather than
  /// a short successful body.
  Future<List<int>?> _loadRange(
    int start,
    int end, {
    required bool Function() isCancelled,
  }) async {
    if (isCancelled() ||
        !await _ensureRange(start, end, isCancelled: isCancelled) ||
        isCancelled() ||
        _path == null) {
      return null;
    }
    final bytes = await _readRange(start, end);
    if (isCancelled() || bytes.length != end - start + 1) return null;
    return bytes;
  }

  (int, int)? _requestedRange(String header) {
    if (!header.startsWith('bytes=')) return null;
    var start = 0;
    int? requestedEnd;
    final value = header.substring('bytes='.length).split(',').first.trim();
    final parts = value.split('-');
    if (parts.length != 2) return null;
    if (parts.first.isEmpty) {
      final suffixLength = int.tryParse(parts[1]) ?? 0;
      if (suffixLength <= 0) return null;
      start = math.max(0, _total - math.min(suffixLength, _maxResponseBytes));
      requestedEnd = _total - 1;
    } else {
      start = int.tryParse(parts.first) ?? -1;
      if (start < 0 || start >= _total) return null;
      if (parts[1].isNotEmpty) {
        requestedEnd = int.tryParse(parts[1]);
      }
    }
    final end = math.min(
      math.max(start, requestedEnd ?? (_total - 1)),
      _total - 1,
    );
    return (start, end);
  }

  Future<bool> _ensureRange(
    int start,
    int end, {
    bool Function()? isCancelled,
  }) async {
    if (_closed || isCancelled?.call() == true) return false;
    if (await _rangeIsReadable(start, end)) return true;

    final readableEnd = _downloadOffset + _downloadedPrefixSize - 1;
    final continuousOffset = _continuousDownloadOffset;
    final continuousDownloadCanReachRange =
        continuousOffset != null &&
        continuousOffset <= start &&
        start <= readableEnd + _chunkSize;
    if (continuousDownloadCanReachRange &&
        await _waitForReadableRange(start, end, isCancelled: isCancelled)) {
      return true;
    }

    if (isCancelled?.call() == true) return false;
    final length = end - start + 1;
    try {
      final file = await _downloadPlaybackRange(start, length);
      if (file != null) _updateFileInfo(file);
      if (_path == null || _path!.isEmpty) {
        await _primePlaybackRange(start, length);
      }
      return _waitForReadableRange(start, end, isCancelled: isCancelled);
    } catch (_) {
      return _waitForReadableRange(start, end, isCancelled: isCancelled);
    }
  }

  Future<Map<String, dynamic>?> _downloadPlaybackRange(int offset, int length) {
    if (_closed) return Future<Map<String, dynamic>?>.value();
    final key = (offset, length);
    final existing = _rangeDownloads[key];
    if (existing != null) return existing;

    final task = _downloadQueue.then((_) async {
      if (_closed) return null;
      _continuousDownloadOffset = null;
      try {
        return await _query({
          '@type': 'downloadFile',
          'file_id': fileId,
          'priority': 32,
          'offset': offset,
          'limit': length,
          'synchronous': true,
        }).timeout(const Duration(seconds: 45));
      } catch (_) {
        return null;
      }
    });
    _rangeDownloads[key] = task;
    _downloadQueue = task.then<void>((_) {}, onError: (_) {});
    unawaited(
      task.whenComplete(() {
        if (identical(_rangeDownloads[key], task)) {
          _rangeDownloads.remove(key);
        }
        if (!_closed &&
            _backgroundDownloadRequested &&
            _playbackPreparationCount == 0 &&
            _rangeDownloads.isEmpty &&
            !_downloadComplete) {
          unawaited(_startContinuousDownload(0));
        }
      }),
    );
    return task;
  }

  Future<bool> _waitForReadableRange(
    int start,
    int end, {
    bool Function()? isCancelled,
  }) async {
    final deadline = DateTime.now().add(rangeWaitTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_closed || isCancelled?.call() == true) return false;
      if (await _rangeIsReadable(start, end)) return true;
      await Future<void>.delayed(rangePollInterval);
    }
    return false;
  }

  Future<bool> _rangeIsReadable(int start, int end) async {
    if (_downloadComplete) return true;
    try {
      final prefix = await _query({
        '@type': 'getFileDownloadedPrefixSize',
        'file_id': fileId,
        'offset': start,
      });
      return (prefix.integer('size') ?? 0) >= end - start + 1;
    } catch (_) {
      return false;
    }
  }

  Future<List<int>> _readRange(int start, int end) async {
    final path = _path;
    if (path == null || path.isEmpty) return const [];
    final file = File(path);
    final available = await file.length();
    if (available <= start) return const [];
    final readableEnd = math.min(end, available - 1);
    final raf = await file.open();
    try {
      await raf.setPosition(start);
      return await raf.read(readableEnd - start + 1);
    } finally {
      await raf.close();
    }
  }
}
