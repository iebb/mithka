//
//  td_image_loader.dart
//
//  Resolves TDLib file ids to on-disk paths by driving downloadFile and
//  listening for updateFile. Used by PhotoAvatar / TDImage to show real profile
//  photos and thumbnails. The Flutter port of the Swift `TDFileCenter`.
//

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'json_helpers.dart';
import 'td_client.dart';
import 'td_models.dart';

class TdFileProgress {
  const TdFileProgress({
    required this.fileId,
    required this.downloaded,
    required this.prefixDownloaded,
    required this.total,
    required this.isActive,
    required this.isCompleted,
  });

  final int fileId;
  final int downloaded;
  final int prefixDownloaded;
  final int total;
  final bool isActive;
  final bool isCompleted;

  double? get fraction {
    if (isCompleted) return 1;
    if (total <= 0 || downloaded <= 0) return null;
    return (downloaded / total).clamp(0.0, 1.0);
  }

  double? get prefixFraction {
    if (isCompleted) return 1;
    if (total <= 0 || prefixDownloaded <= 0) return null;
    return (prefixDownloaded / total).clamp(0.0, 1.0);
  }
}

class TdFileCenter {
  TdFileCenter._();
  static final TdFileCenter shared = TdFileCenter._();

  final TdClient _client = TdClient.shared;

  // Keyed by "slot:fileId" — TDLib file ids are PER-ACCOUNT, so the same id
  // means different files in different accounts.
  final Map<String, String> _cache = {};
  final Map<String, List<Completer<String?>>> _waiters = {};
  final Map<String, List<Completer<String?>>> _playbackWaiters = {};
  final Map<String, StreamController<TdFileProgress>> _progressControllers = {};
  bool _started = false;
  static const _playbackInitialPrefix = 2 * 1024 * 1024;
  static const _priorityChunkSize = 512 * 1024;
  static const _priorityParallelism = 4;

  String _key(int slot, int fileId) => '$slot:$fileId';

  /// Resolves a file reference without downloading it again when the source
  /// file used for an outgoing message is still available locally.
  Future<String?> pathFor(TdFileRef ref) async {
    final localPath = ref.localPath;
    if (localPath != null && localPath.isNotEmpty) {
      final source = File(localPath);
      if (await source.exists()) {
        _cache[_key(_client.activeSlot, ref.id)] = localPath;
        return localPath;
      }
    }
    return path(ref.id);
  }

  void _startIfNeeded() {
    if (_started) return;
    _started = true;
    _client.subscribe().listen((update) {
      if (update.type != 'updateFile') return;
      final file = update.obj('file');
      if (file != null) _ingest(file);
    });
  }

  /// Records file progress/completion and wakes any waiters.
  void _ingest(Map<String, dynamic> file) {
    final id = file.integer('id');
    final local = file.obj('local');
    if (id == null || local == null) {
      return;
    }
    final slot = _client.activeSlot;
    final k = _key(slot, id);
    final path = local.str('path');

    if (path != null && path.isNotEmpty) {
      final playbackPending = _playbackWaiters.remove(k) ?? [];
      for (final c in playbackPending) {
        if (!c.isCompleted) c.complete(path);
      }
    }

    final completed = local.boolean('is_downloading_completed') == true;
    final expectedSize = file.integer('expected_size') ?? 0;
    final fileSize = file.integer('size') ?? 0;
    final total = expectedSize > 0 ? expectedSize : fileSize;
    final downloadedSize = local.integer('downloaded_size') ?? 0;
    final downloadedPrefix = local.integer('downloaded_prefix_size') ?? 0;
    final downloaded = completed
        ? total
        : math.max(downloadedSize, downloadedPrefix);
    final progress = TdFileProgress(
      fileId: id,
      downloaded: downloaded,
      prefixDownloaded: completed ? total : downloadedPrefix,
      total: total,
      isActive: local.boolean('is_downloading_active') == true,
      isCompleted: completed,
    );
    // Lifecycle is map-owned: closed on completion below and via onCancel
    // when the last listener detaches.
    // ignore: close_sinks
    final controller = _progressControllers[k];
    if (controller != null && !controller.isClosed) {
      controller.add(progress);
    }

    if (!completed) return;
    if (path == null || path.isEmpty) return;

    // The completed event above is the stream's last; dispose the controller
    // so per-file controllers don't accumulate over a session. A re-download
    // gets a fresh controller from the next progress() call.
    final finished = _progressControllers.remove(k);
    unawaited(finished?.close());

    _cache[k] = path;
    final pending = _waiters.remove(k) ?? [];
    for (final c in pending) {
      if (!c.isCompleted) c.complete(path);
    }
  }

  Stream<TdFileProgress> progress(int fileId) {
    _startIfNeeded();

    final slot = _client.activeSlot;
    final k = _key(slot, fileId);
    final controller = _progressControllers.putIfAbsent(k, () {
      late final StreamController<TdFileProgress> created;
      created = StreamController<TdFileProgress>.broadcast(
        // Last listener gone → drop the controller so abandoned downloads
        // (screen closed mid-transfer) don't leak an entry per file.
        onCancel: () {
          if (identical(_progressControllers[k], created)) {
            _progressControllers.remove(k);
          }
          created.close();
        },
      );
      return created;
    });
    scheduleMicrotask(() async {
      try {
        final file = await _client.query({
          '@type': 'getFile',
          'file_id': fileId,
        });
        _ingest(file);
      } catch (_) {}
    });
    return controller.stream;
  }

  /// Returns the local path as soon as TDLib exposes one, without waiting for
  /// the file to finish downloading. Useful for video playback, where the
  /// platform player can often begin reading the growing local file while TDLib
  /// continues filling it.
  Future<String?> playbackPath(int fileId) async {
    _startIfNeeded();

    final slot = _client.activeSlot;
    final k = _key(slot, fileId);
    final cached = _cache[k];
    if (cached != null) return cached;

    final pending = _playbackWaiters[k];
    if (pending != null && pending.isNotEmpty) {
      final completer = Completer<String?>();
      pending.add(completer);
      return completer.future.timeout(
        const Duration(seconds: 25),
        onTimeout: () {
          _playbackWaiters[k]?.remove(completer);
          return null;
        },
      );
    }

    final completer = Completer<String?>();
    _playbackWaiters[k] = [completer];

    try {
      final file = await _client.query({'@type': 'getFile', 'file_id': fileId});
      _ingest(file);
      final localPath = file.obj('local')?.str('path');
      if (localPath != null && localPath.isNotEmpty) {
        _playbackWaiters.remove(k);
        return localPath;
      }
    } catch (_) {}

    try {
      unawaited(
        downloadPriorityRange(
          fileId,
          offset: 0,
          length: _playbackInitialPrefix,
          priority: 30,
          timeout: const Duration(seconds: 25),
        ),
      );
    } catch (_) {}

    return completer.future.timeout(
      const Duration(seconds: 25),
      onTimeout: () {
        _playbackWaiters[k]?.remove(completer);
        return null;
      },
    );
  }

  Future<void> requestPlaybackPrefix(int fileId, int bytes) async {
    _startIfNeeded();
    try {
      await downloadPriorityRange(
        fileId,
        offset: 0,
        length: bytes,
        priority: 30,
        timeout: const Duration(seconds: 25),
      );
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> downloadPriorityRange(
    int fileId, {
    required int offset,
    required int length,
    int priority = 32,
    int parallelism = _priorityParallelism,
    int chunkSize = _priorityChunkSize,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    _startIfNeeded();
    if (fileId == 0 || length <= 0) return null;
    final chunks = <MapEntry<int, int>>[];
    var cursor = offset;
    final endExclusive = offset + length;
    while (cursor < endExclusive) {
      final nextLength = math.min(chunkSize, endExclusive - cursor);
      chunks.add(MapEntry(cursor, nextLength));
      cursor += nextLength;
    }
    if (chunks.isEmpty) return null;

    var nextIndex = 0;
    var completed = 0;
    Map<String, dynamic>? latest;

    Future<void> worker() async {
      while (true) {
        final index = nextIndex++;
        if (index >= chunks.length) return;
        final chunk = chunks[index];
        try {
          final file = await _client
              .query({
                '@type': 'downloadFile',
                'file_id': fileId,
                'priority': priority,
                'offset': chunk.key,
                'limit': chunk.value,
                'synchronous': true,
              })
              .timeout(timeout);
          _ingest(file);
          latest = file;
          completed++;
        } catch (_) {}
      }
    }

    final workerCount = math.min(parallelism, chunks.length);
    await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);
    return completed == chunks.length ? latest : null;
  }

  Future<Map<String, dynamic>?> downloadPriorityFile(
    int fileId, {
    required int total,
    int priority = 32,
    int parallelism = _priorityParallelism,
    int chunkSize = 2 * 1024 * 1024,
  }) async {
    _startIfNeeded();
    if (fileId == 0) return null;
    if (total <= 0) {
      try {
        final response = await _client.query({
          '@type': 'downloadFile',
          'file_id': fileId,
          'priority': priority,
          'offset': 0,
          'limit': 0,
          'synchronous': false,
        });
        _ingest(response);
        return response;
      } catch (_) {}
      return null;
    }
    final rangeResult = await downloadPriorityRange(
      fileId,
      offset: 0,
      length: total,
      priority: priority,
      parallelism: parallelism,
      chunkSize: chunkSize,
      timeout: const Duration(seconds: 90),
    );
    if (rangeResult != null) return rangeResult;

    // One or more chunks timed out or failed. Fall back to a standard
    // async download so TDLib keeps the file alive in the background and
    // continues emitting updateFile events. Without this, the progress bar
    // stalls at whatever fraction the chunked download reached, and the
    // file never completes.
    try {
      final response = await _client.query({
        '@type': 'downloadFile',
        'file_id': fileId,
        'priority': priority,
        'offset': 0,
        'limit': 0,
        'synchronous': false,
      });
      _ingest(response);
      return response;
    } catch (_) {
      return null;
    }
  }

  void cancelDownload(int fileId) {
    _startIfNeeded();
    _client.send({
      '@type': 'cancelDownloadFile',
      'file_id': fileId,
      'only_if_pending': false,
    });
  }

  /// Returns a local path for the file id, downloading if needed.
  Future<String?> path(int fileId) async {
    _startIfNeeded();

    final slot = _client.activeSlot;
    final k = _key(slot, fileId);
    final cached = _cache[k];
    if (cached != null) return cached;
    final pending = _waiters[k];
    if (pending != null && pending.isNotEmpty) {
      final completer = Completer<String?>();
      pending.add(completer);
      return completer.future.timeout(
        const Duration(seconds: 180),
        onTimeout: () {
          _waiters[k]?.remove(completer);
          return null;
        },
      );
    }

    final completer = Completer<String?>();
    _waiters[k] = [completer];

    // Kick the download. The immediate response reflects current state, so an
    // already-complete file resolves without waiting for an update.
    try {
      final response = await _client.query({
        '@type': 'downloadFile',
        'file_id': fileId,
        'priority': 16,
        'offset': 0,
        'limit': 0,
        'synchronous': false,
      });
      _ingest(response);
      final local = response.obj('local');
      if (local?.boolean('is_downloading_completed') == true) {
        final path = local?.str('path');
        if (path != null && path.isNotEmpty) {
          _cache[k] = path;
          final pending = _waiters.remove(k) ?? [];
          for (final c in pending) {
            if (!c.isCompleted) c.complete(path);
          }
          return path;
        }
      }
    } catch (_) {
      // fall through to wait for updateFile
    }

    // Otherwise wait for the completing updateFile.
    final existing = _cache[k];
    if (existing != null) return existing;
    // Don't wait forever if the download stalls/fails — callers (e.g. the file
    // opener) then surface "下载失败" instead of a stuck spinner.
    return completer.future.timeout(
      const Duration(seconds: 180),
      onTimeout: () {
        _waiters[k]?.remove(completer);
        return null;
      },
    );
  }
}
