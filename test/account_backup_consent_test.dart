import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_backup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('backup decision requires pending or previously stored consent', () {
    expect(
      AccountBackupService.shouldBackUpAccount(
        pendingConsent: false,
        storedConsent: true,
      ),
      isFalse,
    );
    expect(
      AccountBackupService.shouldBackUpAccount(
        pendingConsent: null,
        storedConsent: false,
      ),
      isFalse,
    );
    expect(
      AccountBackupService.shouldBackUpAccount(
        pendingConsent: true,
        storedConsent: false,
      ),
      isTrue,
    );
    expect(
      AccountBackupService.shouldBackUpAccount(
        pendingConsent: null,
        storedConsent: true,
      ),
      isTrue,
    );
  });

  test(
    'migration deletes legacy auto-backups and preserves explicit consent',
    () async {
      SharedPreferences.setMockInitialValues({});
      const channel = MethodChannel('mithka/account_backup.migration_test');
      final deletedIds = <String>[];
      final records = <Uint8List>[
        _backupRecord(format: 'mithka.tdlib.session_string.v1', id: '1001'),
        _backupRecord(
          format: 'mithka.tdlib.session_string.v2.explicit_consent',
          id: '2002',
        ),
      ];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'isSupported':
                return true;
              case 'getAllSessions':
                return records;
              case 'deleteSession':
                deletedIds.add(
                  (call.arguments as Map<Object?, Object?>)['id']! as String,
                );
                return null;
              case 'deleteAllSessions':
                fail('recognized explicit records must never be deleted');
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final service = AccountBackupService(
        channel: channel,
        platformEligible: true,
      );
      final backups = await service.listBackups();

      expect(deletedIds, ['1001']);
      expect(backups.map((backup) => backup.id), ['2002']);
      expect(await service.hasConsentForAccountId('1001'), isFalse);
      expect(await service.hasConsentForAccountId('2002'), isTrue);
      expect(await service.consentedAccountCount(), 1);
    },
  );

  test('local and synced backups stay separate', () async {
    SharedPreferences.setMockInitialValues({
      'mithka.accountBackup.explicitConsentMigration.v1': true,
      'mithka.accountBackup.consent.4004': true,
    });
    const channel = MethodChannel('mithka/account_backup.local_test');
    final deletedStorages = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final arguments = call.arguments as Map<Object?, Object?>?;
          switch (call.method) {
            case 'isSupported':
            case 'isLocalStorageSupported':
              return true;
            case 'getAllSessions':
              final storage = arguments?['storage'] as String? ?? 'synced';
              return <Uint8List>[
                _backupRecord(
                  format: 'mithka.tdlib.session_string.v2.explicit_consent',
                  id: '4004',
                  createdAt: storage == 'local'
                      ? '2026-07-24T02:00:00.000Z'
                      : '2026-07-24T01:00:00.000Z',
                ),
              ];
            case 'deleteSession':
              deletedStorages.add(arguments?['storage']! as String);
              return null;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final service = AccountBackupService(
      channel: channel,
      platformEligible: true,
    );
    final backups = await service.listBackups();

    expect(backups, hasLength(2));
    expect(backups.first.storage, AccountSessionBackupStorage.local);
    expect(backups.last.storage, AccountSessionBackupStorage.synced);

    await service.delete(backups.first);
    expect(deletedStorages, ['local']);
    expect(await service.hasConsentForAccountId('4004'), isTrue);
  });

  test(
    'a mobile host without the native channel reports unsupported, not a throw',
    () async {
      // The submitted HarmonyOS host registers only generated plugins and has
      // no `mithka/account_backup` handler: every call throws
      // MissingPluginException. Eligibility is the mobile branch, so this is
      // the exact production state on ohos.
      SharedPreferences.setMockInitialValues({
        'mithka.accountBackup.explicitConsentMigration.v1': true,
      });
      const channel = MethodChannel('mithka/account_backup.missing_test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw MissingPluginException();
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final service = AccountBackupService(
        channel: channel,
        platformEligible: true,
      );

      expect(await service.isSupported, isFalse);
      expect(await service.isLocalStorageSupported, isFalse);
      // Every dependent surface reads the same clean answer.
      expect(await service.listBackups(), isEmpty);
      await service.backupActiveAccountIfEnabled();
      await expectLater(service.backupActiveAccount(), throwsUnsupportedError);
      await service.deleteAccountId('1234');
    },
  );

  test(
    'a channel error answering the probe also reports unsupported',
    () async {
      // A handler that exists but cannot serve the capability (e.g. the
      // system keychain unavailable) must not surface as a crash either.
      SharedPreferences.setMockInitialValues({
        'mithka.accountBackup.explicitConsentMigration.v1': true,
      });
      const channel = MethodChannel('mithka/account_backup.error_test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'keychain_unavailable');
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final service = AccountBackupService(
        channel: channel,
        platformEligible: true,
      );

      expect(await service.isSupported, isFalse);
      expect(await service.listBackups(), isEmpty);
    },
  );
}

Uint8List _backupRecord({
  required String format,
  required String id,
  String createdAt = '2026-07-18T00:00:00.000Z',
}) => Uint8List.fromList(
  utf8.encode(
    jsonEncode({
      'format': format,
      'id': id,
      'accountId': id,
      'userId': int.parse(id),
      'name': 'Account $id',
      'createdAt': createdAt,
      'sessionString': 'session-$id',
    }),
  ),
);
