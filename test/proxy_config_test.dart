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

  test('imports Telegram web links, marked path secrets and implicit 443', () {
    for (final link in [
      'tg://webproxy?server=Relay.Example/relay/v2&secret=$markedSecret',
      'https://t.me/webproxy?server=https%3A%2F%2Frelay.example%2Frelay%2Fv2&secret=$markedSecret&port=80',
      'mithka://webproxy?server=relay.example/relay/v2&secret=$markedSecret',
    ]) {
      final config = ProxyConfig.fromTelegramUrl(link)!;
      expect(config.type, 'web');
      expect(config.server, 'relay.example');
      expect(config.port, 443);
      expect(config.path, 'relay/v2');
      expect(config.secret, webSecret);
      expect(config.isUsable, isTrue);
      expect(config.tdType, {
        '@type': 'proxyTypeWeb',
        'path': 'relay/v2',
        'secret': webSecret,
      });
      final added = {'proxy': config.tdProxy};
      expect(ProxyConfig.fromTdProxy(added).type, 'web');
      expect(ProxyConfig.fromTdProxy(added).path, 'relay/v2');
      expect(config.matchesTdProxy(added), isTrue);
      expect(
        config.matchesTdProxy({
          'proxy': {
            ...config.tdProxy,
            'type': {...config.tdType, 'path': 'other'},
          },
        }),
        isFalse,
      );
    }
    expect(
      ProxyConfig.fromTelegramUrl(
        'https://t.me/webproxy?server=relay.example&secret=dd$webSecret',
      )!.secret,
      'dd$webSecret',
    );
    for (final secret in [
      'DD${webSecret.toUpperCase()}',
      'cA${webSecret.substring(2)}',
      base64Url.encode(List.generate(16, (index) => index * 0x11)),
    ]) {
      expect(
        ProxyConfig.fromTelegramUrl(
          'tg://webproxy?server=relay.example&secret=${Uri.encodeQueryComponent(secret)}',
        ),
        isNotNull,
        reason: secret,
      );
    }
  });

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
  });

  test(
    'web path round-trips while its secret stays in secure storage',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final secrets = <String, String>{};
      Future<String?> read(String key) async => secrets[key];
      Future<void> write(String key, String? value) async {
        if (value == null) {
          secrets.remove(key);
        } else {
          secrets[key] = value;
        }
      }

      final config = ProxyConfig.fromTelegramUrl(
        'tg://webproxy?server=relay.example/relay&secret=$markedSecret',
      )!;
      await ProxyConfig.save(
        config,
        preferences: preferences,
        secureRead: read,
        secureWrite: write,
      );
      final loaded = await ProxyConfig.load(
        preferences: preferences,
        secureRead: read,
        secureWrite: write,
      );
      expect(loaded.path, 'relay');
      expect(loaded.secret, webSecret);
      expect(loaded.matchesTdProxy(config.tdProxy), isTrue);
      expect(
        preferences.getKeys().any((key) => preferences.get(key) == webSecret),
        isFalse,
      );
    },
  );

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
