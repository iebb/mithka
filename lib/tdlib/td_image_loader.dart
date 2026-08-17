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

class TdFileByteRange {
  const TdFileByteRange({required this.start, required this.end});

  /// Inclusive start byte.
  final int start;

  /// Exclusive end byte.
  final int end;
}

class TdFileProgress {
  const TdFileProgress({
    required this.fileId,
    required this.downloaded,
    required this.prefixDownloaded,
    required this.total,
    required this.isActive,
    required this.isCompleted,
    this.downloadedRanges,
  });

  final int fileId;
  final int downloaded;
  final int prefixDownloaded;
  final int total;
  final bool isActive;
  final bool isCompleted;

  /// Known byte intervals, when the producer can report sparse downloads.
  /// `null` means only aggregate TDLib counters are available.
  final List<TdFileByteRange>? downloadedRanges;

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
  final Map<String, List<TdFileByteRange>> _downloadedRanges = {};
  bool _started = false;
  static const _cacheCapacity = 4096;
  static const _playbackInitialPrefix = 2 * 1024 * 1024;
  static const _priorityChunkSize = 512 * 1024;
  static const _priorityParallelism = 4;

  String _key(int slot, int fileId) => '$slot:$fileId';

  /// Records a resolved path, dropping the oldest entries past [_cacheCapacity].
  ///
  /// This map lives on a process-lifetime singleton and used to grow by one
  /// entry for every media item ever scrolled past. Eviction costs nothing: a
  /// miss re-issues downloadFile, exactly what [forget] already relies on.
  void _remember(String key, String path) {
    _cache[key] = path;
    if (_cache.length > _cacheCapacity) _cache.remove(_cache.keys.first);
  }

  /// Resolves a file reference without downloading it again when the source
  /// file used for an outgoing message is still available locally.
  Future<String?> pathFor(TdFileRef ref, {int? accountSlot}) async {
    final slot = accountSlot ?? _client.activeSlot;
    final localPath = ref.localPath;
    if (localPath != null && localPath.isNotEmpty) {
      final source = File(localPath);
      if (await source.exists()) {
        _remember(_key(slot, ref.id), localPath);
        return localPath;
      }
    }
    return path(ref.id, accountSlot: slot);
  }

  /// The already-resolved path for [ref], or null when nothing is cached.
  ///
  /// [pathFor] is async even on a pure cache hit, so a reader that awaits it
  /// always paints one placeholder frame first. This lets a widget skip that
  /// frame. It deliberately ignores `ref.localPath` — [pathFor] gates that
  /// behind an `exists()` check, and a source file picked for an outgoing
  /// message can be gone.
  String? cachedPath(TdFileRef ref, {int? accountSlot}) {
    final slot = accountSlot ?? _client.activeSlot;
    return _cache[_key(slot, ref.id)];
  }

  void _startIfNeeded() {
    if (_started) return;
    _started = true;
    _client
        .subscribeAll()
        .where((update) => update.type == 'updateFile')
        .listen((update) {
          final file = update.obj('file');
          final clientId = update.integer('@client_id');
          final accountSlot = clientId == null
              ? _client.activeSlot
              : _client.slotForClient(clientId);
          if (file != null && accountSlot != null) {
            _ingest(file, accountSlot: accountSlot);
          }
        });
  }

  /// Records file progress/completion and wakes any waiters.
  void _ingest(Map<String, dynamic> file, {required int accountSlot}) {
    final id = file.integer('id');
    final local = file.obj('local');
    if (id == null || local == null) {
      return;
    }
    final k = _key(accountSlot, id);
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
    final downloadOffset = local.integer('download_offset') ?? 0;
    final downloaded = completed
        ? total
        : math.max(downloadedSize, downloadedPrefix);
    // Lifecycle is map-owned: closed on completion below and via onCancel
    // when the last listener detaches.
    // ignore: close_sinks
    final controller = _progressControllers[k];
    if (controller != null) {
      if (completed && total > 0) {
        _downloadedRanges[k] = <TdFileByteRange>[
          TdFileByteRange(start: 0, end: total),
        ];
      } else if (downloadedPrefix > 0 && total > 0) {
        _rememberDownloadedRange(
          k,
          start: downloadOffset,
          end: downloadOffset + downloadedPrefix,
          total: total,
        );
      }
    }
    final progress = TdFileProgress(
      fileId: id,
      downloaded: downloaded,
      prefixDownloaded: completed ? total : downloadedPrefix,
      total: total,
      isActive: local.boolean('is_downloading_active') == true,
      isCompleted: completed,
      downloadedRanges: List<TdFileByteRange>.unmodifiable(
        _downloadedRanges[k] ?? const <TdFileByteRange>[],
      ),
    );
    if (controller != null && !controller.isClosed) {
      controller.add(progress);
    }

    if (!completed) return;
    if (path == null || path.isEmpty) return;

    // The completed event above is the stream's last; dispose the controller
    // so per-file controllers don't accumulate over a session. A re-download
    // gets a fresh controller from the next progress() call.
    final finished = _progressControllers.remove(k);
    _downloadedRanges.remove(k);
    unawaited(finished?.close());

    _remember(k, path);
    final pending = _waiters.remove(k) ?? [];
    for (final c in pending) {
      if (!c.isCompleted) c.complete(path);
    }
  }

  Stream<TdFileProgress> progress(int fileId, {int? accountSlot}) {
    _startIfNeeded();

    final slot = accountSlot ?? _client.activeSlot;
    final k = _key(slot, fileId);
    final controller = _progressControllers.putIfAbsent(k, () {
      late final StreamController<TdFileProgress> created;
      created = StreamController<TdFileProgress>.broadcast(
        // Last listener gone → drop the controller so abandoned downloads
        // (screen closed mid-transfer) don't leak an entry per file.
        onCancel: () {
          if (identical(_progressControllers[k], created)) {
            _progressControllers.remove(k);
            _downloadedRanges.remove(k);
          }
          created.close();
        },
      );
      return created;
    });
    scheduleMicrotask(() async {
      try {
        final file = await _client.queryForSlot({
          '@type': 'getFile',
          'file_id': fileId,
        }, slot);
        _ingest(file, accountSlot: slot);
      } catch (_) {}
    });
    return controller.stream;
  }

  void _rememberDownloadedRange(
    String key, {
    required int start,
    required int end,
    required int total,
  }) {
    final boundedStart = start.clamp(0, total);
    final boundedEnd = end.clamp(boundedStart, total);
    if (boundedEnd <= boundedStart) return;
    final ranges = <TdFileByteRange>[
      ...?_downloadedRanges[key],
      TdFileByteRange(start: boundedStart, end: boundedEnd),
    ]..sort((a, b) => a.start.compareTo(b.start));
    final merged = <TdFileByteRange>[];
    for (final range in ranges) {
      if (merged.isEmpty || range.start > merged.last.end) {
        merged.add(range);
        continue;
      }
      final previous = merged.removeLast();
      merged.add(
        TdFileByteRange(
          start: previous.start,
          end: math.max(previous.end, range.end),
        ),
      );
    }
    _downloadedRanges[key] = merged;
  }

  /// Returns the local path as soon as TDLib exposes one, without waiting for
  /// the file to finish downloading. Useful for video playback, where the
  /// platform player can often begin reading the growing local file while TDLib
  /// continues filling it.
  Future<String?> playbackPath(int fileId, {int? accountSlot}) async {
    _startIfNeeded();

    final slot = accountSlot ?? _client.activeSlot;
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
      final file = await _client.queryForSlot({
        '@type': 'getFile',
        'file_id': fileId,
      }, slot);
      _ingest(file, accountSlot: slot);
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
          accountSlot: slot,
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

  Future<void> requestPlaybackPrefix(
    int fileId,
    int bytes, {
    int? accountSlot,
  }) async {
    _startIfNeeded();
    final slot = accountSlot ?? _client.activeSlot;
    try {
      await downloadPriorityRange(
        fileId,
        accountSlot: slot,
        offset: 0,
        length: bytes,
        priority: 30,
        timeout: const Duration(seconds: 25),
      );
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> downloadPriorityRange(
    int fileId, {
    int? accountSlot,
    required int offset,
    required int length,
    int priority = 32,
    int parallelism = _priorityParallelism,
    int chunkSize = _priorityChunkSize,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    _startIfNeeded();
    final slot = accountSlot ?? _client.activeSlot;
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
              .queryForSlot({
                '@type': 'downloadFile',
                'file_id': fileId,
                'priority': priority,
                'offset': chunk.key,
                'limit': chunk.value,
                'synchronous': true,
              }, slot)
              .timeout(timeout);
          _ingest(file, accountSlot: slot);
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
    int? accountSlot,
    required int total,
    int priority = 32,
    int parallelism = _priorityParallelism,
    int chunkSize = 2 * 1024 * 1024,
  }) async {
    _startIfNeeded();
    final slot = accountSlot ?? _client.activeSlot;
    if (fileId == 0) return null;
    if (total <= 0) {
      try {
        final response = await _client.queryForSlot({
          '@type': 'downloadFile',
          'file_id': fileId,
          'priority': priority,
          'offset': 0,
          'limit': 0,
          'synchronous': false,
        }, slot);
        _ingest(response, accountSlot: slot);
        return response;
      } catch (_) {}
      return null;
    }
    final rangeResult = await downloadPriorityRange(
      fileId,
      accountSlot: slot,
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
      final response = await _client.queryForSlot({
        '@type': 'downloadFile',
        'file_id': fileId,
        'priority': priority,
        'offset': 0,
        'limit': 0,
        'synchronous': false,
      }, slot);
      _ingest(response, accountSlot: slot);
      return response;
    } catch (_) {
      return null;
    }
  }

  void cancelDownload(int fileId, {int? accountSlot}) {
    _startIfNeeded();
    final slot = accountSlot ?? _client.activeSlot;
    final clientId = _client.clientId(slot);
    if (clientId == null) return;
    _client.sendTo({
      '@type': 'cancelDownloadFile',
      'file_id': fileId,
      'only_if_pending': false,
    }, clientId);
  }

  /// Renews a visible whole-file download without allocating a query waiter.
  ///
  /// TDLib emits updateFile for the resumed transfer. Fire-and-forget matters
  /// here: this is the bounded path waiter's one recovery attempt, and a lost
  /// response must not accumulate another permanently pending query.
  void resumeDownload(int fileId, {int? accountSlot}) {
    _startIfNeeded();
    final slot = accountSlot ?? _client.activeSlot;
    final clientId = _client.clientId(slot);
    if (clientId == null) return;
    _client.sendTo({
      '@type': 'downloadFile',
      'file_id': fileId,
      'priority': 32,
      'offset': 0,
      'limit': 0,
      'synchronous': false,
    }, clientId);
  }

  /// Drops the remembered local path for a file id.
  ///
  /// TDLib deletes cached files on its own (storage optimizer, "clear cache",
  /// media replaced by a message edit). A path handed out before that keeps
  /// resolving to a file that no longer exists, so a reader that finds one
  /// missing reports it here and the next [path] call downloads it again.
  void forget(int fileId, {int? accountSlot}) {
    final slot = accountSlot ?? _client.activeSlot;
    _cache.remove(_key(slot, fileId));
  }

  Future<void> _requestPathDownload(int fileId, int accountSlot) async {
    try {
      final response = await _client.queryForSlot({
        '@type': 'downloadFile',
        'file_id': fileId,
        'priority': 16,
        'offset': 0,
        'limit': 0,
        'synchronous': false,
      }, accountSlot);
      _ingest(response, accountSlot: accountSlot);
    } catch (_) {
      // The completion waiter remains bounded and updateFile can still finish
      // a request whose immediate response was lost.
    }
  }

  void _removePathWaiter(
    String key,
    Completer<String?> completer,
    List<Completer<String?>> waiters,
  ) {
    if (!identical(_waiters[key], waiters)) return;
    waiters.remove(completer);
    if (waiters.isEmpty) _waiters.remove(key);
  }

  /// Returns a local path for the file id, downloading if needed.
  Future<String?> path(int fileId, {int? accountSlot}) async {
    _startIfNeeded();

    final slot = accountSlot ?? _client.activeSlot;
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
          _removePathWaiter(k, completer, pending);
          return null;
        },
      );
    }

    final completer = Completer<String?>();
    final waiters = <Completer<String?>>[completer];
    _waiters[k] = waiters;

    // Do not await the request response before installing the bounded wait.
    // A lost TDLib response previously meant the first resolver never reached
    // its 180-second timeout (only later joined callers did). _ingest handles
    // both an immediate completed response and the eventual updateFile event.
    unawaited(_requestPathDownload(fileId, slot));

    // Otherwise wait for the completing updateFile.
    final existing = _cache[k];
    if (existing != null) return existing;
    // Don't wait forever if the download stalls/fails — callers (e.g. the file
    // opener) then surface "下载失败" instead of a stuck spinner.
    return completer.future.timeout(
      const Duration(seconds: 180),
      onTimeout: () {
        _removePathWaiter(k, completer, waiters);
        return null;
      },
    );
  }

  /// Downloads the complete file for an outgoing upload and returns its path.
  ///
  /// Unlike [path], this uses TDLib's synchronous download response so the
  /// result stays associated with the requested account even while background
  /// accounts are also emitting `updateFile` events.
  Future<String?> uploadPath(
    int fileId, {
    int? accountSlot,
    Duration timeout = const Duration(minutes: 10),
  }) async {
    _startIfNeeded();
    if (fileId <= 0) return null;
    final slot = accountSlot ?? _client.activeSlot;
    final k = _key(slot, fileId);
    final cached = _cache[k];
    if (cached != null && await File(cached).exists()) return cached;
    try {
      final response = await _client
          .queryForSlot({
            '@type': 'downloadFile',
            'file_id': fileId,
            'priority': 32,
            'offset': 0,
            'limit': 0,
            'synchronous': true,
          }, slot)
          .timeout(timeout);
      _ingest(response, accountSlot: slot);
      final local = response.obj('local');
      final path = local?.str('path');
      if (local?.boolean('is_downloading_completed') == true &&
          path != null &&
          path.isNotEmpty &&
          await File(path).exists()) {
        _remember(k, path);
        return path;
      }
    } catch (_) {}
    return null;
  }
}
