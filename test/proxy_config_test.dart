import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/proxy_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('migrates legacy proxy secrets only after secure read-back', () async {
    SharedPreferences.setMockInitialValues({
      'mithka.proxy.enabled': true,
      'mithka.proxy.type': 'mtproto',
      'mithka.proxy.server': 'proxy.example',
      'mithka.proxy.port': 443,
      'mithka.proxy.password': 'legacy-password',
      'mithka.proxy.secret': 'legacy-secret',
    });
    final preferences = await SharedPreferences.getInstance();
    final secureValues = <String, String>{};

    final config = await ProxyConfig.load(
      preferences: preferences,
      secureRead: (key) async => secureValues[key],
      secureWrite: (key, value) async {
        if (value == null) {
          secureValues.remove(key);
        } else {
          secureValues[key] = value;
        }
      },
    );

    expect(config.password, 'legacy-password');
    expect(config.secret, 'legacy-secret');
    expect(secureValues['mithka.proxy.password.v2'], 'legacy-password');
    expect(secureValues['mithka.proxy.secret.v2'], 'legacy-secret');
    expect(preferences.containsKey('mithka.proxy.password'), isFalse);
    expect(preferences.containsKey('mithka.proxy.secret'), isFalse);
  });

  test(
    'retains plaintext migration source when secure storage fails',
    () async {
      SharedPreferences.setMockInitialValues({
        'mithka.proxy.enabled': true,
        'mithka.proxy.password': 'legacy-password',
        'mithka.proxy.secret': 'legacy-secret',
      });
      final preferences = await SharedPreferences.getInstance();

      final config = await ProxyConfig.load(
        preferences: preferences,
        secureRead: (_) async => null,
        secureWrite: (_, _) async => throw StateError('unavailable'),
      );

      expect(config.password, 'legacy-password');
      expect(config.secret, 'legacy-secret');
      expect(preferences.getString('mithka.proxy.password'), 'legacy-password');
      expect(preferences.getString('mithka.proxy.secret'), 'legacy-secret');
    },
  );

  test('retains migration source until secure storage reads it back', () async {
    SharedPreferences.setMockInitialValues({
      'mithka.proxy.enabled': true,
      'mithka.proxy.password': 'legacy-password',
      'mithka.proxy.secret': 'legacy-secret',
    });
    final preferences = await SharedPreferences.getInstance();

    final config = await ProxyConfig.load(
      preferences: preferences,
      secureRead: (_) async => null,
      secureWrite: (_, _) async {},
    );

    expect(config.password, 'legacy-password');
    expect(config.secret, 'legacy-secret');
    expect(preferences.getString('mithka.proxy.password'), 'legacy-password');
    expect(preferences.getString('mithka.proxy.secret'), 'legacy-secret');
  });

  test('saves password and MTProto secret only in secure storage', () async {
    final preferences = await SharedPreferences.getInstance();
    final secureValues = <String, String>{};
    const config = ProxyConfig(
      configured: true,
      enabled: true,
      type: 'mtproto',
      server: 'proxy.example',
      port: 443,
      username: 'proxy-user',
      password: 'secure-password',
      secret: 'secure-secret',
    );

    await ProxyConfig.save(
      config,
      preferences: preferences,
      secureRead: (key) async => secureValues[key],
      secureWrite: (key, value) async {
        if (value == null) {
          secureValues.remove(key);
        } else {
          secureValues[key] = value;
        }
      },
    );

    expect(secureValues['mithka.proxy.password.v2'], 'secure-password');
    expect(secureValues['mithka.proxy.secret.v2'], 'secure-secret');
    expect(preferences.getString('mithka.proxy.username'), 'proxy-user');
    expect(preferences.containsKey('mithka.proxy.password'), isFalse);
    expect(preferences.containsKey('mithka.proxy.secret'), isFalse);
  });
}
