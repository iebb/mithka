import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_backup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'login backup consent accepts its computed default and explicit changes',
    () async {
      SharedPreferences.setMockInitialValues({
        'mithka.accountBackup.explicitConsentMigration.v1': true,
      });
      const slot = 8042;

      await AccountBackupService.shared.beginLoginConsent(
        slot: slot,
        enabled: true,
      );
      expect(
        await AccountBackupService.shared.pendingLoginConsent(slot: slot),
        isTrue,
      );

      await AccountBackupService.shared.setPendingLoginConsent(
        slot: slot,
        enabled: false,
      );
      expect(
        await AccountBackupService.shared.pendingLoginConsent(slot: slot),
        isFalse,
      );
    },
  );

  test('login backup defaults on only below four accounts', () {
    for (var accountCount = 0; accountCount < 4; accountCount += 1) {
      expect(
        AccountBackupService.shouldSelectLoginBackupByDefault(
          accountCount: accountCount,
          isIOS: true,
          isSupported: true,
        ),
        isTrue,
      );
    }
    expect(
      AccountBackupService.shouldSelectLoginBackupByDefault(
        accountCount: 4,
        isIOS: true,
        isSupported: true,
      ),
      isFalse,
    );
    expect(
      AccountBackupService.shouldSelectLoginBackupByDefault(
        accountCount: 8,
        isIOS: true,
        isSupported: true,
      ),
      isFalse,
    );
    expect(
      AccountBackupService.shouldSelectLoginBackupByDefault(
        accountCount: 3,
        isIOS: false,
        isSupported: true,
      ),
      isFalse,
    );
    expect(
      AccountBackupService.shouldSelectLoginBackupByDefault(
        accountCount: 3,
        isIOS: true,
        isSupported: false,
      ),
      isFalse,
    );
  });

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

  test(
    'migration cleans unknown data then re-saves explicit v2 records',
    () async {
      SharedPreferences.setMockInitialValues({});
      const channel = MethodChannel('mithka/account_backup.unknown_test');
      final explicit = _backupRecord(
        format: 'mithka.tdlib.session_string.v2.explicit_consent',
        id: '3003',
      );
      var deleteAllCalls = 0;
      final savedIds = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'isSupported':
                return true;
              case 'getAllSessions':
                return <Uint8List>[
                  Uint8List.fromList([0, 1, 2]),
                  explicit,
                ];
              case 'deleteAllSessions':
                deleteAllCalls += 1;
                return null;
              case 'saveSession':
                savedIds.add(
                  (call.arguments as Map<Object?, Object?>)['id']! as String,
                );
                return null;
              case 'deleteSession':
                fail('unidentified data requires a complete cleanup');
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
      await service.listBackups();

      expect(deleteAllCalls, 1);
      expect(savedIds, ['3003']);
      expect(await service.hasConsentForAccountId('3003'), isTrue);
    },
  );
}

Uint8List _backupRecord({required String format, required String id}) =>
    Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': format,
          'id': id,
          'accountId': id,
          'userId': int.parse(id),
          'name': 'Account $id',
          'createdAt': '2026-07-18T00:00:00.000Z',
          'sessionString': 'session-$id',
        }),
      ),
    );
