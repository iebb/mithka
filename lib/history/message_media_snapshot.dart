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
//  Ported from AyuGram's AyuMessageUtils.saveDownloadedMedia /
//  processAttachment semantics (see exteraless's com.radolyn.ayugram).
//

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/build_flags.dart';
import '../tdlib/json_helpers.dart';

/// Keeps on-disk copies of media files referenced by mirrored messages.
class MessageMediaSnapshotter {
  MessageMediaSnapshotter._();

  static final MessageMediaSnapshotter shared = MessageMediaSnapshotter._();

  @visibleForTesting
  factory MessageMediaSnapshotter.forTesting() => MessageMediaSnapshotter._();

  /// Directory holding the copies. Resolved lazily; tests inject one.
  @visibleForTesting
  Directory? dir;

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
    final scopeEpoch = _scopeEpochs[scopeKey] ?? 0;
    try {
      if (!await source.exists()) return null;
      final directory = dir;
      if (directory == null) return null;
      await directory.create(recursive: true);
      final name = _snapshotFileName(accountUserId, chatId, messageId, source);
      final target = File('${directory.path}/$name');
      if (!await target.exists()) {
        await source.copy(target.path);
      }
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

  /// Removes every snapshot of one account.
  void deleteAccount(int accountUserId) {
    if (!allowTelegramTosViolations) return;
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
