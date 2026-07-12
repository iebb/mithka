import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/api_credentials_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ApiCredentialsConfig', () {
    test('loads API id saved as a string', () async {
      SharedPreferences.setMockInitialValues({
        'mithka.api_credentials.enabled': true,
        'mithka.api_credentials.api_id': '12345',
        'mithka.api_credentials.api_hash': 'hash',
      });
      final prefs = await SharedPreferences.getInstance();

      expect(ApiCredentialsConfig.fromPrefs(prefs).apiId, 12345);
    });

    test('migrates API id saved as an integer without a type error', () async {
      SharedPreferences.setMockInitialValues({
        'mithka.api_credentials.enabled': true,
        'mithka.api_credentials.api_id': 12345,
        'mithka.api_credentials.api_hash': 'hash',
      });
      final prefs = await SharedPreferences.getInstance();

      expect(ApiCredentialsConfig.fromPrefs(prefs).apiId, 12345);
    });
  });
}
