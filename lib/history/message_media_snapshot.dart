//
//  message_media_snapshot.dart
//
//  Media snapshotting for the kept-message mirror (Telegram API Terms §1.4
//  feature, compiled only with [allowTelegramTosViolations]). When a mirrored
//  message carries a media file that is already fully on disk in TDLib's file
//  storage, the snapshotter copies it into the mirror's own attachment
//  directory so the kept copy survives TDLib's cache eviction and message
//  deletion. The copy is verbatim; photos are NOT decrypted through the
//  Telegram cloud (that would need a live file id, which a deleted message no
//  longer has).
//
//  The copy rules follow the reference kept-message clients: only files
//  already fully present in local TDLib storage are copied, never fetched.
//

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../config/build_flags.dart';
import '../tdlib/json_helpers.dart';

/// Keeps on-disk copies of media files referenced by mirrored messages.
class MessageMediaSnapshotter {
  MessageMediaSnapshotter._();

  static final MessageMediaSnapshotter shared = MessageMediaSnapshotter._();

  @visibleForTesting
  factory MessageMediaSnapshotter.forTesting() => MessageMediaSnapshotter._();

  /// Directory holding the copies. Resolved lazily from app support behind
  /// the same compile-time gate; tests inject one.
  Directory? dir;

  /// App-support subdirectory the production snapshotter copies into.
  static const dirName = 'message-history-media';

  bool _dirResolved = false;

  /// Holds every copy just before the post-copy validation, so tests can
  /// land an invalidation mid-copy deterministically.
  @visibleForTesting
  Future<void> Function()? beforeValidateForTesting;

  /// Test seam over [attachmentBytesBudget]: when set, the budget gate
  /// compares against this value instead of the default ceiling.
  @visibleForTesting
  int? budgetOverrideForTesting;

  /// Resolves the production directory once (from app support, so it follows
  /// the OS convention the mirror file already uses); an injected [dir] wins
  /// and never triggers the platform lookup. Failure keeps the snapshotter
  /// inert — nothing is fetched or copied without a directory.
  Future<void> ensureDirResolved() async {
    if (!allowTelegramTosViolations) return;
    if (_dirResolved) return;
    _dirResolved = true;
    if (dir != null) return;
    try {
      final support = await getApplicationSupportDirectory();
      dir = Directory('${support.path}/$dirName');
    } catch (_) {
      // Leave dir null: snapshot() then returns null for every file.
    }
  }

  int _generation = 0;
  final Map<String, int> _scopeEpochs = {};

  int get attachmentBytesBudget => 512 * 1024 * 1024;

  /// Bytes already committed under [dir]; 0 when no directory is set.
  int get usedBytes {
    final directory = dir;
    if (directory == null) return 0;
    var total = 0;
    for (final entity in directory.listSync(followLinks: false)) {
      if (entity is File) total += entity.lengthSync();
    }
    return total;
  }

  /// Global reset (clear-all): cancels every queued copy by generation.
  void invalidateAll() {
    _generation++;
  }

  /// Scoped reset (one account removed / one chat cleared): drops only that
  /// scope's queued copies; other scopes keep copying.
  void invalidateScope(int accountUserId, int chatId) {
    final key = '$accountUserId:$chatId';
    _scopeEpochs[key] = (_scopeEpochs[key] ?? 0) + 1;
  }

  /// Copies the file behind [file] into the mirror directory when it is
  /// already fully downloaded ([File.local] with a non-empty path and
  /// is_active_completed), and returns the copy's path. Returns null when the
  /// source is not fully local — nothing is fetched from the network here.
  Future<String?> snapshot(
    Map<String, dynamic>? file, {
    required int accountUserId,
    required int chatId,
    required int messageId,
  }) async {
    if (!allowTelegramTosViolations) return null;
    if (file == null) return null;
    final local = file.obj('local');
    if (local == null) return null;
    // TDLib marks a fully-downloaded local file with is_downloading_completed;
    // is_active_completed additionally means no other download is running for
    // it. Either bit alone is not a whole file on disk, so require the pair
    // but accept files TDLib reports complete without an active download
    // context (is_active_completed missing → treat as not running).
    final downloadingActive = local.boolean('is_active_downloading') ?? false;
    final downloaded = local.boolean('is_downloading_completed') ?? false;
    if (downloadingActive && !downloaded) return null;
    if (!downloaded) return null;
    final sourcePath = local.str('path');
    if (sourcePath == null || sourcePath.isEmpty) return null;
    final source = File(sourcePath);
    final generation = _generation;
    final scopeKey = '$accountUserId:$chatId';
    // Register the scope so deleteAccount can invalidate an in-flight copy
    // even before any per-chat invalidation ever touched it.
    final scopeEpoch = _scopeEpochs.putIfAbsent(scopeKey, () => 0);
    try {
      await ensureDirResolved();
      final directory = dir;
      if (directory == null) return null;
      if (!await source.exists()) return null;
      await directory.create(recursive: true);
      final name = _snapshotFileName(accountUserId, chatId, messageId, source);
      final target = File('${directory.path}/$name');
      if (!await target.exists()) {
        // Budget gate: a NEW copy must fit beside the bytes already committed.
        // Re-copying an existing target only replaces bytes the directory
        // already counts, so it stays exempt. Without the gate the mirror's
        // attachment dir grows without bound until the disk fills.
        final incoming = await source.length();
        final budget = budgetOverrideForTesting ?? attachmentBytesBudget;
        if (usedBytes + incoming > budget) return null;
        await source.copy(target.path);
      }
      final beforeValidate = beforeValidateForTesting;
      if (beforeValidate != null) await beforeValidate();
      // Re-check after the await: an invalidation that landed mid-copy must
      // not leave this scope's file behind for the store to reference.
      if (_generation != generation ||
          (_scopeEpochs[scopeKey] ?? 0) != scopeEpoch) {
        if (await target.exists()) {
          try {
            await target.delete();
          } catch (_) {}
        }
        return null;
      }
      return target.path;
    } catch (_) {
      return null;
    }
  }

  /// Deletes one snapshot file (ignoring errors), for single-entry removal.
  void deleteFile(String? path) {
    if (!allowTelegramTosViolations) return;
    if (path == null || path.isEmpty) return;
    final file = File(path);
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  /// Reads a snapshot's bytes for export; null when the file is missing,
  /// unreadable, or lives outside the snapshot directory (a stale path).
  Future<List<int>?> readSnapshotBytes(String path) async {
    if (!allowTelegramTosViolations) return null;
    try {
      final directory = dir;
      if (directory == null) return null;
      if (!path.startsWith('${directory.path}/')) return null;
      final file = File(path);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// Writes export bytes back as the snapshot of the entry keyed
  /// `<account>:<chat>:<message>`; returns the new path, null on failure.
  /// The written file is renamed to THIS caller's account prefix, so an
  /// import under a different account id still lets deleteScope and
  /// deleteAccount reclaim the file.
  Future<String?> writeSnapshotBytes(
    String entryKey,
    List<int> bytes, {
    int? accountUserIdOverride,
  }) async {
    if (!allowTelegramTosViolations) return null;
    try {
      final parts = entryKey.split(':');
      if (parts.length != 3) return null;
      final accountUserId = accountUserIdOverride ?? int.tryParse(parts[0]);
      final chatId = int.tryParse(parts[1]);
      final messageId = int.tryParse(parts[2]);
      if (accountUserId == null || chatId == null || messageId == null) {
        return null;
      }
      await ensureDirResolved();
      final directory = dir;
      if (directory == null) return null;
      await directory.create(recursive: true);
      final name = _snapshotFileName(
        accountUserId,
        chatId,
        messageId,
        File('x.bin'),
      );
      final target = File('${directory.path}/$name');
      await target.writeAsBytes(bytes, flush: true);
      return target.path;
    } catch (_) {
      return null;
    }
  }

  /// Removes every snapshot of one (account, chat) scope.
  void deleteScope(int accountUserId, int chatId) {
    if (!allowTelegramTosViolations) return;
    invalidateScope(accountUserId, chatId);
    _deleteWhere(
      (name) => name.startsWith(
        '${accountUserId}_$chatId'
        '_',
      ),
    );
  }

  /// Removes every snapshot of one account. Scope-stamps every (account,
  /// chat) scope the account owned so in-flight copies for it are
  /// invalidated — a copy finishing after the removal is deleted instead of
  /// surviving on disk for an account whose entries are gone, exactly like
  /// deleteScope does per chat.
  void deleteAccount(int accountUserId) {
    if (!allowTelegramTosViolations) return;
    for (final scope in _scopeEpochs.keys.toList(growable: false)) {
      if (scope.startsWith('$accountUserId:')) {
        _scopeEpochs[scope] = (_scopeEpochs[scope] ?? 0) + 1;
      }
    }
    _deleteWhere((name) => name.startsWith('${accountUserId}_'));
  }

  /// Removes every snapshot file (clear-all). Also sweeps files written by
  /// older builds whose names no longer parse.
  void deleteAll() {
    if (!allowTelegramTosViolations) return;
    invalidateAll();
    final directory = dir;
    if (directory == null) return;
    if (!directory.existsSync()) return;
    for (final entity in directory.listSync(followLinks: false)) {
      if (entity is File) {
        try {
          entity.deleteSync();
        } catch (_) {}
      }
    }
  }

  void _deleteWhere(bool Function(String name) where) {
    final directory = dir;
    if (directory == null) return;
    if (!directory.existsSync()) return;
    for (final entity in directory.listSync(followLinks: false)) {
      if (entity is File && where(_fileBaseName(entity.path))) {
        try {
          entity.deleteSync();
        } catch (_) {}
      }
    }
  }

  static String _fileBaseName(String path) {
    final slash = path.lastIndexOf(Platform.pathSeparator);
    return slash < 0 ? path : path.substring(slash + 1);
  }

  /// `<account>_<chat>_<message>_<suffix>.<ext>`; the account/chat/message
  /// prefix is what scope deletions match on.
  static String _snapshotFileName(
    int accountUserId,
    int chatId,
    int messageId,
    File source,
  ) {
    final extension = source.path.contains('.')
        ? source.path.substring(source.path.lastIndexOf('.') + 1)
        : 'bin';
    final safeExtension = RegExp(r'^[A-Za-z0-9]{1,8}$').hasMatch(extension)
        ? extension
        : 'bin';
    return '${accountUserId}_$chatId'
        '_$messageId'
        '_m.$safeExtension';
  }
}
