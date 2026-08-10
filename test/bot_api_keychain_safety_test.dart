import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('startup never accesses the legacy macOS login Keychain', () {
    final registry = File(
      'lib/bot_api/bot_api_account.dart',
    ).readAsStringSync();
    final tdClient = File('lib/tdlib/td_client.dart').readAsStringSync();

    expect(registry, isNot(contains('usesDataProtectionKeychain: false')));
    expect(registry, isNot(contains('flutter_secure_storage_service')));
    expect(registry, isNot(contains('authenticationUIBehavior')));
    expect(tdClient, isNot(contains('migrateLegacyMacOsKeychain')));
  });
}
