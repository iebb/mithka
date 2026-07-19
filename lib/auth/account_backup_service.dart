import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pro/mithka_pro_service.dart';
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
  AccountBackupService({MethodChannel? channel, bool? platformEligible})
    : _channel = channel ?? const MethodChannel('mithka/account_backup'),
      _platformEligible =
          platformEligible ?? (Platform.isIOS || Platform.isAndroid);

  static final AccountBackupService shared = AccountBackupService();

  final MethodChannel _channel;
  final bool _platformEligible;
  static const _format = 'mithka.tdlib.session_string.v2.explicit_consent';
  static const _legacyFormat = 'mithka.tdlib.session_string.v1';
  static const _consentPrefix = 'mithka.accountBackup.consent.';
  static const _pendingConsentPrefix = 'mithka.accountBackup.pending.';
  static const _legacyEnabledKey = 'mithka.accountBackup.enabled';
  static const _consentMigrationKey =
      'mithka.accountBackup.explicitConsentMigration.v1';
  final Set<int> _inFlightAutoBackups = {};
  final Map<int, bool> _pendingConsentBySlot = {};
  Future<void>? _migrationFuture;

  static bool shouldBackUpAccount({
    required bool? pendingConsent,
    required bool storedConsent,
  }) => pendingConsent ?? storedConsent;

  static bool shouldSelectLoginBackupByDefault({
    required int accountCount,
    required bool isIOS,
    required bool isSupported,
  }) =>
      isIOS &&
      isSupported &&
      accountCount < MithkaProService.freeCloudSessionSyncLimit;

  Future<bool> get isSupported async {
    if (!_platformEligible) return false;
    return await _channel.invokeMethod<bool>('isSupported') ?? false;
  }

  Future<Set<String>> consentedAccountIds() async {
    await _ensureExplicitConsentMigration();
    final prefs = await SharedPreferences.getInstance();
    return prefs
        .getKeys()
        .where(
          (key) =>
              key.startsWith(_consentPrefix) && (prefs.getBool(key) ?? false),
        )
        .map((key) => key.substring(_consentPrefix.length))
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<Set<String>> protectedAccountIds() async {
    final ids = await consentedAccountIds();
    if (await isSupported) {
      ids.addAll((await listBackups()).map((backup) => backup.id));
    }
    return ids;
  }

  Future<int> consentedAccountCount() async =>
      (await protectedAccountIds()).length;

  Future<bool> hasConsentForAccountId(String id) async {
    await _ensureExplicitConsentMigration();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_consentPrefix$id') ?? false;
  }

  Future<bool> activeAccountHasConsent() async {
    final userId = await _activeUserId();
    return userId != null && await hasConsentForAccountId('$userId');
  }

  Future<bool> canAddBackupConsent({String? existingAccountId}) async {
    final protectedIds = await protectedAccountIds();
    final existing =
        existingAccountId != null && protectedIds.contains(existingAccountId);
    return MithkaProService.shared.canAddCloudSessionSync(
      protectedIds.length,
      alreadySynced: existing,
    );
  }

  Future<bool> canAddBackupConsentForActiveAccount() async {
    final userId = await _activeUserId();
    return canAddBackupConsent(
      existingAccountId: userId == null ? null : '$userId',
    );
  }

  Future<void> beginLoginConsent({
    required int slot,
    bool enabled = false,
  }) async {
    await _ensureExplicitConsentMigration();
    _pendingConsentBySlot[slot] = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_pendingConsentPrefix$slot', enabled);
  }

  Future<void> setPendingLoginConsent({
    required int slot,
    required bool enabled,
  }) async {
    await _ensureExplicitConsentMigration();
    _pendingConsentBySlot[slot] = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_pendingConsentPrefix$slot', enabled);
  }

  Future<bool> pendingLoginConsent({required int slot}) async {
    await _ensureExplicitConsentMigration();
    final inMemory = _pendingConsentBySlot[slot];
    if (inMemory != null) return inMemory;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_pendingConsentPrefix$slot') ?? false;
  }

  Future<void> clearPendingLoginConsent({required int slot}) async {
    _pendingConsentBySlot.remove(slot);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_pendingConsentPrefix$slot');
  }

  Future<void> setActiveAccountConsent(bool enabled) async {
    final userId = await _activeUserId();
    if (userId == null) {
      throw StateError('TDLib getMe did not return a user id');
    }
    await setAccountConsent('$userId', enabled);
    if (enabled) await backupActiveAccount();
  }

  Future<void> setAccountConsent(String accountId, bool enabled) async {
    await _ensureExplicitConsentMigration();
    final prefs = await SharedPreferences.getInstance();
    if (enabled) {
      if (!await canAddBackupConsent(existingAccountId: accountId)) {
        throw const AccountBackupLimitException();
      }
      await prefs.setBool('$_consentPrefix$accountId', true);
      return;
    }
    await prefs.remove('$_consentPrefix$accountId');
    await deleteAccountId(accountId, removeConsent: false);
  }

  Future<void> backupActiveAccountIfEnabled() async {
    await _ensureExplicitConsentMigration();
    if (!await isSupported) return;

    final slot = TdClient.shared.activeSlot;
    if (!_inFlightAutoBackups.add(slot)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingKey = '$_pendingConsentPrefix$slot';
      final hasPendingChoice =
          _pendingConsentBySlot.containsKey(slot) ||
          prefs.containsKey(pendingKey);
      bool? pendingConsent;
      if (hasPendingChoice) {
        pendingConsent =
            _pendingConsentBySlot.remove(slot) ??
            prefs.getBool(pendingKey) ??
            false;
        await prefs.remove(pendingKey);
        final userId = await _activeUserId();
        if (userId == null) return;
        final accountId = '$userId';
        if (!pendingConsent) {
          await setAccountConsent(accountId, false);
          return;
        }
        if (!await canAddBackupConsent(existingAccountId: accountId)) return;
        await prefs.setBool('$_consentPrefix$accountId', true);
      }

      final userId = await _activeUserId();
      final storedConsent =
          userId != null && (prefs.getBool('$_consentPrefix$userId') ?? false);
      if (userId == null ||
          !shouldBackUpAccount(
            pendingConsent: pendingConsent,
            storedConsent: storedConsent,
          )) {
        return;
      }
      await backupActiveAccount();
    } catch (error) {
      stderr.writeln('☁️ [Mithka] account backup skipped: $error');
    } finally {
      _inFlightAutoBackups.remove(slot);
    }
  }

  Future<List<AccountSessionBackup>> listBackups() async {
    await _ensureExplicitConsentMigration();
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
    if (backups.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      for (final backup in backups) {
        await prefs.setBool('$_consentPrefix${backup.id}', true);
      }
    }
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
      throw UnsupportedError(
        'Account session backup is not available on this device',
      );
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
      throw UnsupportedError(
        'Account session export is not available on this device',
      );
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

  Future<void> deleteAccountId(String id, {bool removeConsent = true}) async {
    if (removeConsent) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_consentPrefix$id');
    }
    if (!await isSupported) return;
    await _channel.invokeMethod<void>('deleteSession', {'id': id});
  }

  Future<void> deleteAll() async {
    await _ensureExplicitConsentMigration();
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where(
      (key) =>
          key.startsWith(_consentPrefix) ||
          key.startsWith(_pendingConsentPrefix),
    )) {
      await prefs.remove(key);
    }
    _pendingConsentBySlot.clear();
    if (!await isSupported) return;
    await _channel.invokeMethod<void>('deleteAllSessions');
  }

  Future<int?> _activeUserId() async {
    try {
      final me = await TdClient.shared.query({'@type': 'getMe'});
      return me.int64('id');
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureExplicitConsentMigration() async {
    final operation = _migrationFuture ??= _performExplicitConsentMigration();
    try {
      await operation;
    } catch (_) {
      if (identical(_migrationFuture, operation)) _migrationFuture = null;
      rethrow;
    }
  }

  Future<void> _performExplicitConsentMigration() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_consentMigrationKey) ?? false) return;

    // Older builds automatically wrote every authorized iOS account to the
    // Keychain. Those v1 records have no per-account permission, so remove
    // them once instead of silently converting the global default to consent.
    // Explicit-consent v2 records restored from another device are preserved.
    for (final key in prefs.getKeys().where(
      (key) =>
          key.startsWith(_consentPrefix) ||
          key.startsWith(_pendingConsentPrefix),
    )) {
      await prefs.remove(key);
    }
    _pendingConsentBySlot.clear();
    try {
      if (await isSupported) {
        final rawItems = await _channel.invokeListMethod<Object?>(
          'getAllSessions',
        );
        final explicitRecords = <String, Uint8List>{};
        final legacyIds = <String>{};
        var foundUnidentifiedLegacyRecord = false;
        for (final raw in rawItems ?? const []) {
          if (raw is! Uint8List) {
            foundUnidentifiedLegacyRecord = true;
            continue;
          }
          try {
            final decoded = jsonDecode(utf8.decode(raw));
            if (decoded is! Map<String, dynamic>) {
              foundUnidentifiedLegacyRecord = true;
              continue;
            }
            if (decoded['format'] == _format) {
              final id =
                  decoded['accountId']?.toString() ?? decoded['id']?.toString();
              if (id != null && id.isNotEmpty) {
                explicitRecords[id] = raw;
              } else {
                foundUnidentifiedLegacyRecord = true;
              }
              continue;
            }
            final id =
                decoded['accountId']?.toString() ?? decoded['id']?.toString();
            if (decoded['format'] == _legacyFormat &&
                id != null &&
                id.isNotEmpty) {
              legacyIds.add(id);
            } else {
              foundUnidentifiedLegacyRecord = true;
            }
          } catch (_) {
            foundUnidentifiedLegacyRecord = true;
          }
        }
        if (foundUnidentifiedLegacyRecord) {
          await _channel.invokeMethod<void>('deleteAllSessions');
          for (final entry in explicitRecords.entries) {
            await _channel.invokeMethod<void>('saveSession', {
              'id': entry.key,
              'data': entry.value,
            });
          }
        } else {
          for (final id in legacyIds.difference(explicitRecords.keys.toSet())) {
            await _channel.invokeMethod<void>('deleteSession', {'id': id});
          }
        }
        for (final id in explicitRecords.keys) {
          await prefs.setBool('$_consentPrefix$id', true);
        }
      }
    } on MissingPluginException {
      // Native support may not be present on desktop and unit-test hosts.
    }
    await prefs.remove(_legacyEnabledKey);
    await prefs.setBool(_consentMigrationKey, true);
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

class AccountBackupLimitException implements Exception {
  const AccountBackupLimitException();

  @override
  String toString() => 'Mithka Pro is required for more than four backups';
}

class _ExportedAccountSession {
  const _ExportedAccountSession({required this.slot, required this.backup});

  final int slot;
  final AccountSessionBackup backup;
}
