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

      final config = ApiCredentialsConfig.fromPrefs(prefs);
      expect(config.apiId, 12345);
      expect(config.hasCustomUserAgent, isFalse);
      expect(config.resolvedDeviceModel('Android'), 'Android');
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

    test('loads and resolves custom TDLib user-agent fields', () async {
      SharedPreferences.setMockInitialValues({
        'mithka.api_credentials.enabled': false,
        'mithka.api_credentials.device_model': 'Pixel 10',
        'mithka.api_credentials.system_version': 'Android 17',
        'mithka.api_credentials.application_version': 'Mithka 0.8',
      });
      final prefs = await SharedPreferences.getInstance();

      final config = ApiCredentialsConfig.fromPrefs(prefs);
      expect(config.isUsable, isFalse);
      expect(config.hasCustomUserAgent, isTrue);
      expect(config.resolvedDeviceModel('Android'), 'Pixel 10');
      expect(config.resolvedSystemVersion('Android'), 'Android 17');
      expect(config.resolvedApplicationVersion('1.0'), 'Mithka 0.8');
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
