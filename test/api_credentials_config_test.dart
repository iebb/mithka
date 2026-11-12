import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/api_credentials_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ApiCredentialsConfig', () {
    test('migrates API id saved as an integer without a type error', () async {
      SharedPreferences.setMockInitialValues({
        'mithka.api_credentials.enabled': true,
        'mithka.api_credentials.api_id': 12345,
        'mithka.api_credentials.api_hash': 'hash',
      });
      final prefs = await SharedPreferences.getInstance();

      expect(ApiCredentialsConfig.fromPrefs(prefs).apiId, 12345);
    });

    test('saves normalized credentials and user-agent values', () async {
      SharedPreferences.setMockInitialValues({});

      await ApiCredentialsConfig.save(
        const ApiCredentialsConfig(
          configured: true,
          enabled: true,
          apiId: 12345,
          apiHash: ' hash ',
          deviceModel: ' Pixel 10 ',
          systemVersion: ' Android 17 ',
          applicationVersion: ' Mithka 0.8 ',
        ),
      );

      final config = await ApiCredentialsConfig.load();
      expect(config.apiHash, 'hash');
      expect(config.deviceModel, 'Pixel 10');
      expect(config.systemVersion, 'Android 17');
      expect(config.applicationVersion, 'Mithka 0.8');
    });
  });
}
