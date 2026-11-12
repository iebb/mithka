import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/proxy_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const webSecret = '00112233445566778899aabbccddeeff';
  final markedSecret = base64Url
      .encode([0x70, ...List.generate(16, (index) => index * 0x11)])
      .replaceAll('=', '');

  test('rejects unsafe web addresses, paths and fake TLS secrets', () {
    for (final address in [
      '127.0.0.1',
      '127.1',
      'proxy.0x01',
      'localhost',
      'relay.example:443',
      'user@relay.example',
      'relay.example/../private',
      'relay.example/relay/',
      'relay.example/relay//nested',
      'relay.example/_relay',
      'relay.example/${'x' * 129}',
    ]) {
      expect(
        ProxyConfig.fromTelegramUrl(
          'tg://webproxy?server=${Uri.encodeQueryComponent(address)}&secret=$markedSecret',
        ),
        isNull,
        reason: address,
      );
    }
    for (final secret in ['', 'ee${webSecret}6578616d706c65', 'invalid']) {
      expect(
        ProxyConfig.fromTelegramUrl(
          'tg://webproxy?server=relay.example&secret=$secret',
        ),
        isNull,
      );
    }
    expect(
      ProxyConfig.fromTelegramUrl(
        'tg://webproxy?server=relay.example/path&secret=$webSecret',
      ),
      isNull,
      reason: 'paths require Telegram marker encoding',
    );
    expect(
      ProxyConfig.isValidWebProxy('relay.example', 443, 'relay/v2', webSecret),
      isTrue,
    );
    expect(
      ProxyConfig.isValidWebProxy('relay.example', 443, '../escape', webSecret),
      isFalse,
    );
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
