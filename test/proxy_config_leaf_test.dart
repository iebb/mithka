//
//  proxy_config_leaf_test.dart
//
//  Saved encrypted proxies: credentials live only in secure storage, an
//  unreadable or unsupported one fails closed instead of turning direct, and
//  the catalog behind the proxy list is upserted and pruned in place.
//

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/leaf_proxy_profile.dart';
import 'package:mithka/settings/proxy_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uuid = '0f8b3c2a-5d1e-4f6a-9b7c-1a2b3c4d5e6f';

LeafProxyProfile _vless({int id = 11, int port = 443, String name = ''}) =>
    LeafProxyProfile(
      id: id,
      protocol: 'vless',
      server: 'vless.example',
      port: port,
      name: name,
      uuid: _uuid,
      tls: true,
      vision: true,
    );

void main() {
  final secure = <String, String>{};

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secure.clear();
    ProxyConfig.debugEncryptedProxiesSupported = true;
    ProxyConfig.debugSecureRead = (key) async => secure[key];
    ProxyConfig.debugSecureWrite = (key, value) async {
      if (value == null) {
        secure.remove(key);
      } else {
        secure[key] = value;
      }
    };
  });

  tearDown(() {
    ProxyConfig.debugEncryptedProxiesSupported = null;
    ProxyConfig.debugSecureRead = null;
    ProxyConfig.debugSecureWrite = null;
  });

  test(
    'saves an encrypted proxy to secure storage and loads it back',
    () async {
      final profile = _vless();
      await ProxyConfig.save(ProxyConfig.encrypted(profile));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('mithka.proxy.type'), 'vless');
      // Nothing that identifies the account on the proxy reaches preferences.
      for (final key in prefs.getKeys()) {
        expect('${prefs.get(key)}', isNot(contains(_uuid)), reason: key);
      }
      expect(secure['mithka.proxy.leaf.v1'], contains(_uuid));

      final loaded = await ProxyConfig.load();
      expect(loaded.configured, isTrue);
      expect(loaded.isUsable, isTrue);
      expect(loaded.leaf!.toJson(), profile.toJson());
      expect(loaded.label, 'VLESS Vision');
      expect(() => loaded.tdProxy, throwsStateError);

      final catalog = await ProxyConfig.loadLeafProfiles();
      expect(catalog.map((p) => p.id), [profile.id]);
    },
  );

  test('fails closed when the saved profile cannot be read', () async {
    await ProxyConfig.save(ProxyConfig.encrypted(_vless()));
    secure.remove('mithka.proxy.leaf.v1');

    final loaded = await ProxyConfig.load();
    // Unconfigured leaves every TDLib account on its current route; it is
    // never a request to connect directly.
    expect(loaded.configured, isFalse);
    expect(loaded.enabled, isFalse);
  });

  test('fails closed where the engine is not built', () async {
    await ProxyConfig.save(ProxyConfig.encrypted(_vless()));
    ProxyConfig.debugEncryptedProxiesSupported = false;

    expect((await ProxyConfig.load()).configured, isFalse);
    expect(await ProxyConfig.loadLeafProfiles(), isEmpty);
    expect(
      ProxyConfig.fromTelegramUrl('vless://$_uuid@vless.example:443'),
      isNull,
    );
  });

  test('upserts the catalog in place and never re-adds on disable', () async {
    await ProxyConfig.save(ProxyConfig.encrypted(_vless(id: 1)));
    await ProxyConfig.save(ProxyConfig.encrypted(_vless(id: 2, port: 8443)));
    await ProxyConfig.save(
      ProxyConfig.encrypted(_vless(id: 1, name: 'Renamed')),
    );
    var catalog = await ProxyConfig.loadLeafProfiles();
    expect(catalog.map((p) => p.id), [1, 2]);
    expect(catalog.first.name, 'Renamed');

    await ProxyConfig.removeLeafProfile(1);
    await ProxyConfig.disable();
    catalog = await ProxyConfig.loadLeafProfiles();
    expect(catalog.map((p) => p.id), [2]);

    await ProxyConfig.removeLeafProfile(2);
    expect(await ProxyConfig.loadLeafProfiles(), isEmpty);
    expect(secure.containsKey('mithka.proxy.leaf.catalog.v1'), isFalse);
  });

  test(
    'never reads secure storage for a list without encrypted proxies',
    () async {
      var reads = 0;
      ProxyConfig.debugSecureRead = (key) async {
        reads++;
        return secure[key];
      };
      expect(await ProxyConfig.loadLeafProfiles(), isEmpty);
      expect(reads, 0);
    },
  );

  test('skips catalog entries that no longer validate', () async {
    await ProxyConfig.save(ProxyConfig.encrypted(_vless(id: 1)));
    final stored = jsonDecode(secure['mithka.proxy.leaf.catalog.v1']!) as List;
    secure['mithka.proxy.leaf.catalog.v1'] = jsonEncode([
      {...stored.single as Map<String, dynamic>, 'id': 2, 'tls': false},
      ...stored,
    ]);
    final catalog = await ProxyConfig.loadLeafProfiles();
    expect(catalog.map((p) => p.id), [1]);
  });

  test('a link already saved keeps the saved identity', () async {
    final saved = _vless(id: 5, name: 'Mine');
    await ProxyConfig.save(ProxyConfig.encrypted(saved));
    final parsed = ProxyConfig.fromTelegramUrl(
      'vless://$_uuid@vless.example:443?security=tls&flow=xtls-rprx-vision',
    )!;
    expect(parsed.leaf!.id, isNot(5));
    final resolved = await ProxyConfig.withSavedIdentity(parsed);
    expect(resolved.leaf!.id, 5);
    expect(resolved.leaf!.name, 'Mine');

    final other = ProxyConfig.fromTelegramUrl(
      'vless://$_uuid@vless.example:8443?security=tls',
    )!;
    expect(
      (await ProxyConfig.withSavedIdentity(other)).leaf!.id,
      other.leaf!.id,
    );
  });

  test('restores a stored encrypted row from the proxy list', () {
    final profile = _vless();
    final config = ProxyConfig.fromTdProxy({
      '@type': 'addedProxy',
      'id': -profile.id,
      'proxy': {
        '@type': 'proxy',
        'server': profile.server,
        'port': profile.port,
        'type': {'@type': 'mithkaLeafProxy'},
        'mithka_leaf': profile.toJson(),
      },
    });
    expect(config.leaf!.toJson(), profile.toJson());
  });
}
