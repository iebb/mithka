import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';

class AccountSessionBackup {
  const AccountSessionBackup({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.sizeBytes,
    required this.sessionString,
    this.phone,
    this.userId,
  });

  final String id;
  final String name;
  final String? phone;
  final int? userId;
  final DateTime createdAt;
  final int sizeBytes;
  final String sessionString;

  String get displayName => name.trim().isEmpty ? id : name;
}

class AccountBackupService {
  AccountBackupService._();
  static final AccountBackupService shared = AccountBackupService._();

  static const _channel = MethodChannel('mithka/account_backup');
  static const _format = 'mithka.tdlib.session_string.v1';
  static const _enabledKey = 'mithka.accountBackup.enabled';
  final Set<int> _inFlightAutoBackups = {};

  Future<bool> get isSupported async {
    if (!Platform.isIOS) return false;
    return await _channel.invokeMethod<bool>('isSupported') ?? false;
  }

  Future<bool> get isEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    if (!value) {
      await deleteAll();
    }
  }

  Future<void> backupActiveAccountIfEnabled() async {
    if (!await isEnabled) return;
    if (!await isSupported) return;

    final slot = TdClient.shared.activeSlot;
    if (!_inFlightAutoBackups.add(slot)) return;
    try {
      await backupActiveAccount();
    } catch (error) {
      stderr.writeln('☁️ [Mithka] account backup skipped: $error');
    } finally {
      _inFlightAutoBackups.remove(slot);
    }
  }

  Future<List<AccountSessionBackup>> listBackups() async {
    if (!await isSupported) return const [];
    final rawItems = await _channel.invokeListMethod<Object?>('getAllSessions');
    final backupsById = <String, AccountSessionBackup>{};
    for (final raw in rawItems ?? const []) {
      final data = raw is Uint8List ? raw : null;
      if (data == null) continue;
      final backup = _decode(data);
      if (backup == null) continue;
      final existing = backupsById[backup.id];
      if (existing == null || backup.createdAt.isAfter(existing.createdAt)) {
        backupsById[backup.id] = backup;
      }
    }
    final backups = backupsById.values.toList();
    backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return backups;
  }

  Future<List<AccountSessionBackup>> listRestorableBackups() async {
    final backups = await listBackups();
    if (backups.isEmpty) return const [];
    final loggedInIds = await _loggedInUserIds();
    if (loggedInIds.isEmpty) return backups;
    return backups.where((backup) {
      final userId = backup.userId ?? int.tryParse(backup.id);
      return userId == null || !loggedInIds.contains(userId);
    }).toList();
  }

  Future<Set<int>> _loggedInUserIds() async {
    final ids = <int>{};
    for (final slot in TdClient.shared.configuredSlots) {
      final cid = TdClient.shared.clientId(slot);
      if (cid == null) continue;
      try {
        final me = await TdClient.shared
            .queryTo({'@type': 'getMe'}, cid)
            .timeout(const Duration(seconds: 2));
        final userId = me.int64('id');
        if (userId != null) ids.add(userId);
      } catch (_) {}
    }
    return ids;
  }

  Future<AccountSessionBackup> backupActiveAccount() async {
    if (!await isSupported) {
      throw UnsupportedError('Account session backup is only available on iOS');
    }
    final exported = await _exportActiveAccountSession();
    await _channel.invokeMethod<void>('saveSession', {
      'id': exported.backup.id,
      'data': _encode(exported.backup, slot: exported.slot),
    });
    return exported.backup;
  }

  Future<AccountSessionBackup> exportActiveSession() async {
    if (!await isSupported) {
      throw UnsupportedError('Account session export is only available on iOS');
    }
    return (await _exportActiveAccountSession()).backup;
  }

  Future<_ExportedAccountSession> _exportActiveAccountSession() async {
    final slot = TdClient.shared.activeSlot;
    final me = await TdClient.shared.query({'@type': 'getMe'});
    final userId = me.int64('id');
    if (userId == null) {
      throw StateError('TDLib getMe did not return a user id');
    }
    final name = TDParse.userName(me);
    final phone = TDParse.formatPhone(me.str('phone_number'));
    final sessionString = await TdClient.shared.exportSessionStringForSlot(
      slot,
      userId: userId,
    );
    if (sessionString.trim().isEmpty) {
      throw StateError('TDLib session string is empty');
    }
    TdClient.shared.validateSessionString(
      sessionString,
      expectedUserId: userId,
    );

    final id = userId.toString();
    final createdAt = DateTime.now().toUtc();
    return _ExportedAccountSession(
      slot: slot,
      backup: AccountSessionBackup(
        id: id,
        name: name,
        phone: phone,
        userId: userId,
        createdAt: createdAt,
        sizeBytes: utf8.encode(sessionString).length,
        sessionString: sessionString,
      ),
    );
  }

  Future<int> restore(AccountSessionBackup backup) async {
    final slot = await TdClient.shared.restoreSessionSlot(backup.sessionString);
    return slot;
  }

  Future<int> restoreSessionString(String sessionString) async {
    TdClient.shared.validateSessionString(sessionString);
    return TdClient.shared.restoreSessionSlot(sessionString);
  }

  Future<TdFreshSessionResult> createFreshSessionFromSlot(int sourceSlot) {
    return TdClient.shared.createFreshSessionFromSlot(sourceSlot);
  }

  Future<void> delete(AccountSessionBackup backup) async {
    await deleteAccountId(backup.id);
  }

  Future<void> deleteAccountId(String id) async {
    if (!await isSupported) return;
    await _channel.invokeMethod<void>('deleteSession', {'id': id});
  }

  Future<void> deleteAll() async {
    if (!await isSupported) return;
    await _channel.invokeMethod<void>('deleteAllSessions');
  }

  Uint8List _encode(AccountSessionBackup backup, {required int slot}) {
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'format': _format,
          'id': backup.id,
          'accountId': backup.id,
          'slot': slot,
          'userId': backup.userId,
          'name': backup.name,
          'phone': backup.phone,
          'createdAt': backup.createdAt.toIso8601String(),
          'sessionString': backup.sessionString,
        }),
      ),
    );
  }

  AccountSessionBackup? _decode(Uint8List data) {
    try {
      final decoded = jsonDecode(utf8.decode(data));
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['format'] != _format) return null;
      final sessionString = decoded['sessionString'];
      if (sessionString is! String || sessionString.trim().isEmpty) {
        return null;
      }
      final createdAtText = decoded['createdAt'];
      final createdAt = createdAtText is String
          ? DateTime.tryParse(createdAtText)
          : null;
      final id = decoded['accountId']?.toString() ?? decoded['id']?.toString();
      if (id == null || id.isEmpty) return null;
      final userIdValue = decoded['userId'];
      return AccountSessionBackup(
        id: id,
        name: decoded['name']?.toString() ?? id,
        phone: decoded['phone']?.toString(),
        userId: userIdValue is int ? userIdValue : int.tryParse('$userIdValue'),
        createdAt: createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        sizeBytes: utf8.encode(sessionString).length,
        sessionString: sessionString,
      );
    } catch (_) {
      return null;
    }
  }
}

class _ExportedAccountSession {
  const _ExportedAccountSession({required this.slot, required this.backup});

  final int slot;
  final AccountSessionBackup backup;
}
