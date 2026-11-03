import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import 'download_storage.dart';

/// An independent, complete copy. Neither its payload nor its metadata lives
/// in TDLib's cache. Paths are reconstructed from validated local filenames.
class RetainedDownload {
  const RetainedDownload({
    required this.id,
    required this.title,
    required this.fileName,
    required this.size,
    required this.savedAt,
    required this.path,
    required this.isVideo,
  });

  final String id;
  final String title;
  final String fileName;
  final int size;
  final DateTime savedAt;
  final String path;
  final bool isVideo;
}

/// User-selected retained downloads, not an automatic download/cache policy.
/// One directory per Telegram user avoids leaking copies when a slot is reused
/// for a different account. An account switch never redirects an in-flight save.
class RetainedDownloadStore {
  RetainedDownloadStore(this.directory);

  final Directory directory;
  static final _entryId = RegExp(r'^[a-f0-9]{64}$');

  static Future<RetainedDownloadStore> forAccount(int accountSlot) async {
    final me = await TdClient.shared.queryForSlot({
      '@type': 'getMe',
    }, accountSlot);
    final userId = me.int64('id');
    if (userId == null || userId <= 0) {
      throw StateError('The download owner is unavailable');
    }
    return _forOwner(userId);
  }

  static Future<RetainedDownloadStore> _forOwner(int userId) async {
    final root = await DownloadStorage.retainedRoot();
    final owner = sha256.convert(utf8.encode('telegram-user:$userId'));
    return RetainedDownloadStore(
      Directory('$root/retained-downloads-v1/$owner'),
    );
  }

  static Future<RetainedDownload> keepFile({
    required int accountSlot,
    required int fileId,
    required String title,
    required bool isVideo,
  }) async {
    final lease = TdClient.shared.retainAccountSlot(accountSlot);
    if (lease == null) throw StateError('The download owner is unavailable');
    try {
      final me = await lease.query({'@type': 'getMe'});
      final userId = me.int64('id');
      if (userId == null || userId <= 0) {
        throw StateError('The download owner is unavailable');
      }
      final store = await _forOwner(userId);
      final file = await lease.query({'@type': 'getFile', 'file_id': fileId});
      return await store.keep(file: file, title: title, isVideo: isVideo);
    } finally {
      await lease.release();
    }
  }

  /// Copies into a hidden staging directory, then publishes the directory in
  /// one rename. An interrupted/failed copy is never listed as retained.
  Future<RetainedDownload> keep({
    required Map<String, dynamic> file,
    required String title,
    required bool isVideo,
  }) async {
    final local = file.obj('local');
    final sourcePath = local?.str('path') ?? '';
    if (local?.boolean('is_downloading_completed') != true ||
        sourcePath.isEmpty) {
      throw StateError('Only complete downloads can be retained');
    }
    final source = File(sourcePath);
    final before = await source.stat();
    final declaredSize = file.int64('size') ?? 0;
    if (before.type != FileSystemEntityType.file ||
        (declaredSize > 0 && before.size != declaredSize)) {
      throw StateError('The complete download is no longer available');
    }
    await directory.create(recursive: true);
    // unique_id survives TDLib restarts; numeric file IDs can be reused after
    // signing in again. Without a stable remote identity, keep a fresh copy.
    final uniqueId = file.obj('remote')?.str('unique_id') ?? '';
    final pending = await directory.createTemp('.pending-');
    final id = sha256
        .convert(utf8.encode(uniqueId.isEmpty ? pending.path : uniqueId))
        .toString();
    final destination = Directory('${directory.path}/$id');
    try {
      final existing = await _read(id);
      if (existing != null) return existing;
      // Do not replace a prior copy whose metadata cannot be read.
      if (await FileSystemEntity.type(destination.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw StateError('A retained copy needs attention');
      }
      final fileName = _safeFileName(title, isVideo: isVideo);
      final copy = await source.copy('${pending.path}/$fileName');
      final handle = await copy.open(mode: FileMode.append);
      try {
        await handle.flush();
      } finally {
        await handle.close();
      }
      final after = await source.stat();
      if (await copy.length() != before.size ||
          after.size != before.size ||
          after.modified != before.modified) {
        throw StateError('The source changed while retaining the download');
      }
      final savedAt = DateTime.now().toUtc();
      await File('${pending.path}/entry.json').writeAsString(
        jsonEncode({
          'version': 1,
          'title': title.trim().isEmpty
              ? fileName
              : String.fromCharCodes(title.runes.take(1000)),
          'file_name': fileName,
          'size': before.size,
          'saved_at': savedAt.toIso8601String(),
          'is_video': isVideo,
        }),
        flush: true,
      );
      try {
        await pending.rename(destination.path);
      } on FileSystemException {
        // Two UI surfaces may retain the same file concurrently. Keep the
        // first complete copy, never overwrite it with the second operation.
        final concurrent = await _read(id);
        if (concurrent != null) return concurrent;
        rethrow;
      }
      final retained = await _read(id);
      if (retained == null) {
        throw StateError('Retained copy verification failed');
      }
      return retained;
    } finally {
      if (await pending.exists()) await pending.delete(recursive: true);
    }
  }

  Future<List<RetainedDownload>> list() async {
    if (!await directory.exists()) return [];
    final entries = <RetainedDownload>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final id = entity.uri.pathSegments.where((part) => part.isNotEmpty).last;
      if (!_entryId.hasMatch(id)) continue;
      final entry = await _read(id);
      if (entry != null) entries.add(entry);
    }
    entries.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return entries;
  }

  /// Called only after explicit confirmation; this does not touch the source
  /// message or TDLib cache. Never accepts a path supplied by the UI/metadata.
  Future<void> remove(String id) async {
    if (!_entryId.hasMatch(id)) throw ArgumentError.value(id, 'id');
    final entry = await _read(id);
    if (entry == null) throw StateError('Retained copy is unavailable');
    await File(entry.path).delete();
    await File('${directory.path}/$id/entry.json').delete();
    await Directory('${directory.path}/$id').delete();
  }

  Future<RetainedDownload?> _read(String id) async {
    if (!_entryId.hasMatch(id)) return null;
    final folder = '${directory.path}/$id';
    if (await FileSystemEntity.type(folder, followLinks: false) !=
        FileSystemEntityType.directory) {
      return null;
    }
    try {
      final metadataPath = '$folder/entry.json';
      if (await FileSystemEntity.type(metadataPath, followLinks: false) !=
          FileSystemEntityType.file) {
        return null;
      }
      final metadata = File(metadataPath);
      if (await metadata.length() > 65536) return null;
      final raw = jsonDecode(await metadata.readAsString());
      if (raw is! Map<String, dynamic> || raw['version'] != 1) return null;
      final name = raw.str('file_name');
      final size = raw.int64('size');
      final savedAt = DateTime.tryParse(raw.str('saved_at') ?? '');
      if (name == null ||
          !_validFileName(name) ||
          size == null ||
          size < 0 ||
          savedAt == null) {
        return null;
      }
      final path = '$folder/$name';
      if (await FileSystemEntity.type(path, followLinks: false) !=
              FileSystemEntityType.file ||
          await File(path).length() != size) {
        return null;
      }
      return RetainedDownload(
        id: id,
        title: raw.str('title') ?? name,
        fileName: name,
        size: size,
        savedAt: savedAt,
        path: path,
        isVideo: raw.boolean('is_video') ?? false,
      );
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  static bool _validFileName(String name) =>
      name.isNotEmpty &&
      name != '.' &&
      name != '..' &&
      name != 'entry.json' &&
      !name.contains(RegExp(r'[/\\\x00-\x1f]'));

  static String _safeFileName(String title, {required bool isVideo}) {
    var name = title.replaceAll(RegExp(r'[/\\<>:"|?*\x00-\x1f]'), '_').trim();
    if (!_validFileName(name)) name = isVideo ? 'video.mp4' : 'download.bin';
    name = name.replaceFirst(RegExp(r'[. ]+$'), '');
    if (name.isEmpty) name = isVideo ? 'video.mp4' : 'download.bin';
    if (RegExp(
      r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\.|$)',
      caseSensitive: false,
    ).hasMatch(name)) {
      name = 'download_$name';
    }
    final dot = name.lastIndexOf('.');
    final extension = dot > 0 ? name.substring(dot) : '';
    final suffix = extension.length <= 16 ? extension : '';
    // Bound UTF-8 bytes as well as code points for cross-platform filenames.
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final buffer = StringBuffer();
    var bytes = 0;
    for (final rune in stem.runes) {
      final character = String.fromCharCode(rune);
      bytes += utf8.encode(character).length;
      if (bytes > 160) break;
      buffer.write(character);
    }
    return '$buffer$suffix';
  }
}
