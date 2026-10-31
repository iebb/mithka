//
//  app_proxy_service_test.dart
//
//  Tunnel ownership for encrypted proxies, run against fake tunnels: TDLib
//  sees a loopback SOCKS5 row, accounts share one tunnel per profile and
//  never stop each other's, a failed apply keeps the previous route, the
//  browser follows only the foreground account, and a reclaimed listener is
//  restarted on recovery.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/browser_proxy_notice.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/app_proxy_service.dart';
import 'package:mithka/settings/leaf_proxy_profile.dart';
import 'package:mithka/settings/proxy_config.dart';
import 'package:mithka/settings/proxy_status.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

const _uuid = '0f8b3c2a-5d1e-4f6a-9b7c-1a2b3c4d5e6f';

LeafProxyProfile _profile({int id = 1, int port = 443}) => LeafProxyProfile(
  id: id,
  protocol: 'vless',
  server: 'vless.example',
  port: port,
  uuid: _uuid,
  tls: true,
);

final class _FakeTunnel implements ProxyTunnel {
  _FakeTunnel(this.socksPort, this.httpPort);
  @override
  final int socksPort;
  @override
  final int httpPort;
  bool stopped = false;
  bool alive = true;
  @override
  bool get isRunning => alive && !stopped;
  @override
  Future<void> stop() async => stopped = true;
}

final class _Rig {
  _Rig() {
    service = AppProxyService(
      start: (profile) async {
        starts.add(profile.id);
        final tunnel = _FakeTunnel(
          20000 + tunnels.length * 2,
          20001 + tunnels.length * 2,
        );
        tunnels.add(tunnel);
        return tunnel;
      },
      configureBrowser: (port) async {
        browserPorts.add(port);
        return browserSupported;
      },
      supportsBrowser: () async => browserSupported,
      readAppPort: () => appPort,
      writeAppPort: (port) => appPort = port,
      probe: (port) async => !deadPorts.contains(port),
    );
  }

  late final AppProxyService service;
  final starts = <int>[];
  final tunnels = <_FakeTunnel>[];
  final browserPorts = <int?>[];
  final deadPorts = <int>{};
  bool browserSupported = true;
  int? appPort;

  /// What each client's TDLib was last told.
  final native = <int, ProxyConfig>{};
  int foreground = 1;

  Future<void> apply(int clientId, ProxyConfig config, {Object? fail}) =>
      service.apply(
        config: config,
        clientId: clientId,
        applyNative: (value) async {
          if (fail != null) throw fail;
          native[clientId] = value;
        },
        isForeground: () => foreground == clientId,
      );
}

void main() {
  L10nFixtures.load().install();

  test('TDLib gets a loopback SOCKS5 row naming the profile', () async {
    final rig = _Rig();
    await rig.apply(1, ProxyConfig.encrypted(_profile(id: 9)));

    final row = rig.native[1]!;
    expect(row.leaf, isNull);
    expect(row.type, 'socks5');
    expect(row.server, '127.0.0.1');
    expect(row.port, rig.tunnels.single.socksPort);
    expect(row.username, 'mithka-leaf:9');
    final tdRow = {'@type': 'addedProxy', 'id': 3, 'proxy': row.tdProxy};
    expect(AppProxyService.isManagedRow(tdRow), isTrue);
    expect(AppProxyService.managedProfileId(tdRow), 9);
    expect(rig.service.profileFor(tdRow)!.id, 9);
  });

  test('accounts share one tunnel and never stop each other\'s', () async {
    final rig = _Rig();
    final config = ProxyConfig.encrypted(_profile());
    await rig.apply(1, config);
    await rig.apply(2, config);
    expect(rig.starts, [1]);

    await rig.service.releaseClient(2);
    expect(rig.tunnels.single.stopped, isFalse);

    // Moving the foreground account to a direct route releases the browser's
    // reference too; only then does the tunnel stop.
    await rig.apply(
      1,
      const ProxyConfig(
        configured: true,
        enabled: false,
        type: 'socks5',
        server: '',
        port: 0,
      ),
    );
    expect(rig.tunnels.single.stopped, isTrue);
    expect(rig.appPort, isNull);
  });

  test('a failed apply keeps the previous route and tunnel', () async {
    final rig = _Rig();
    await rig.apply(1, ProxyConfig.encrypted(_profile()));
    await expectLater(
      rig.apply(
        1,
        ProxyConfig.encrypted(_profile(id: 2)),
        fail: StateError('td'),
      ),
      throwsStateError,
    );
    expect(rig.starts, [1, 2]);
    expect(rig.tunnels[0].stopped, isFalse);
    expect(rig.tunnels[1].stopped, isTrue);
    expect(rig.native[1]!.username, 'mithka-leaf:1');
    expect(rig.appPort, rig.tunnels[0].httpPort);
  });

  test('the browser follows only the foreground account', () async {
    final rig = _Rig();
    await rig.apply(2, ProxyConfig.encrypted(_profile(id: 2)));
    // Background: no WebView or Dart HTTP change at all.
    expect(rig.browserPorts, isEmpty);
    expect(await rig.service.browserRoute(), BrowserProxyRoute.direct);

    await rig.apply(1, ProxyConfig.encrypted(_profile()));
    expect(rig.browserPorts, [rig.tunnels[1].httpPort]);
    expect(rig.appPort, rig.tunnels[1].httpPort);
    expect(await rig.service.browserRoute(), BrowserProxyRoute.proxied);

    rig.foreground = 2;
    await rig.service.followForeground(2);
    expect(rig.appPort, rig.tunnels[0].httpPort);
    expect(await rig.service.browserRoute(), BrowserProxyRoute.proxied);
  });

  test('an unchanged direct route never calls the platform', () async {
    final rig = _Rig();
    await rig.apply(
      1,
      const ProxyConfig(
        configured: true,
        enabled: true,
        type: 'socks5',
        server: 'socks.example',
        port: 1080,
      ),
    );
    await rig.service.followForeground(1);
    expect(rig.native[1]!.server, 'socks.example');
    expect(rig.browserPorts, isEmpty);
    expect(rig.starts, isEmpty);
  });

  test('a late foreground restore cannot repoint the newer account', () async {
    final rig = _Rig();
    await rig.apply(1, ProxyConfig.encrypted(_profile()));
    await rig.apply(2, ProxyConfig.encrypted(_profile(id: 2)));
    final gate = Completer<void>();
    final oldRestore = rig.service.followForeground(1, gate.future);
    rig.foreground = 2;
    await rig.service.followForeground(2);
    final port = rig.tunnels[1].httpPort;
    expect(rig.appPort, port);
    gate.complete();
    await oldRestore;
    expect(rig.appPort, port);
    expect(await rig.service.browserRoute(), BrowserProxyRoute.proxied);
  });

  test(
    'a WebView that cannot be proxied reports the direct fallback',
    () async {
      final rig = _Rig()..browserSupported = false;
      await rig.apply(1, ProxyConfig.encrypted(_profile()));
      expect(
        await rig.service.browserRoute(),
        BrowserProxyRoute.directFallback,
      );
      // Dart HTTP is still routed through the tunnel.
      expect(rig.appPort, rig.tunnels.single.httpPort);
      expect(
        await awaitBrowserProxyRoute(service: rig.service),
        BrowserProxyNotice.unsupported,
      );
    },
  );

  test('a browser opened during a foreground change waits for it', () async {
    final rig = _Rig();
    final gate = Completer<void>();
    final applying = rig.service.apply(
      config: ProxyConfig.encrypted(_profile()),
      clientId: 1,
      applyNative: (_) => gate.future,
      isForeground: () => true,
    );
    var resolved = false;
    final route = rig.service.browserRoute().then((value) {
      resolved = true;
      return value;
    });
    await pumpEventQueue();
    expect(resolved, isFalse);
    gate.complete();
    await applying;
    expect(await route, BrowserProxyRoute.proxied);

    // A wait that runs out loads anyway and says so.
    final stuck = Completer<void>();
    unawaited(
      rig.service.apply(
        config: ProxyConfig.encrypted(_profile(id: 3)),
        clientId: 1,
        applyNative: (_) => stuck.future,
        isForeground: () => true,
      ),
    );
    expect(
      await awaitBrowserProxyRoute(
        service: rig.service,
        timeout: const Duration(milliseconds: 20),
      ),
      BrowserProxyNotice.notReady,
    );
    stuck.complete();
  });

  test('recover restarts a reclaimed tunnel and re-points its users', () async {
    final rig = _Rig();
    await rig.apply(1, ProxyConfig.encrypted(_profile()));
    await rig.apply(2, ProxyConfig.encrypted(_profile()));
    final first = rig.tunnels.single;

    await rig.service.recover();
    expect(rig.starts, [1]);

    rig.deadPorts.add(first.socksPort);
    await rig.service.recover();
    expect(rig.starts, [1, 1]);
    final second = rig.tunnels.last;
    expect(first.stopped, isTrue);
    expect(rig.native[1]!.port, second.socksPort);
    expect(rig.native[2]!.port, second.socksPort);
    expect(rig.appPort, second.httpPort);
  });

  test('a desktop window never starts a tunnel of its own', () async {
    final rig = _Rig()..appPort = 4321;
    rig.service.markSecondaryEngine();
    await expectLater(
      rig.apply(1, ProxyConfig.encrypted(_profile())),
      throwsUnsupportedError,
    );
    expect(rig.starts, isEmpty);
    expect(await rig.service.browserRoute(), BrowserProxyRoute.proxied);
    expect(rig.browserPorts, isEmpty);
  });

  group('proxy list adapter', () {
    final secure = <String, String>{};

    setUp(() async {
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
      await ProxyConfig.save(ProxyConfig.encrypted(_profile(id: 4)));
    });

    tearDown(() {
      ProxyConfig.debugEncryptedProxiesSupported = null;
      ProxyConfig.debugSecureRead = null;
      ProxyConfig.debugSecureWrite = null;
    });

    Map<String, dynamic> managedRow(int id, {bool enabled = false}) => {
      '@type': 'addedProxy',
      'id': id,
      'is_enabled': enabled,
      'proxy': {
        '@type': 'proxy',
        'server': '127.0.0.1',
        'port': 30000 + id,
        'type': {
          '@type': 'proxyTypeSocks5',
          'username': 'mithka-leaf:4',
          'password': '',
        },
      },
    };

    final socks = {
      '@type': 'addedProxy',
      'id': 1,
      'is_enabled': false,
      'proxy': {
        '@type': 'proxy',
        'server': 'socks.example',
        'port': 1080,
        'type': {'@type': 'proxyTypeSocks5', 'username': '', 'password': ''},
      },
    };

    test('lists profiles in place of their loopback rows', () async {
      final rig = _Rig();
      final result = await rig.service.viewQuery(
        request: {'@type': 'getProxies'},
        queryNative: (_) async => {
          '@type': 'proxies',
          'proxies': [socks, managedRow(2, enabled: true), managedRow(3)],
        },
        applyConfig: (_) async {},
      );
      final rows = (result['proxies'] as List).cast<Map<String, dynamic>>();
      expect(rows.map((row) => row['id']), [1, -4]);
      expect(rows.last['is_enabled'], isTrue);
      expect(rows.last['proxy']['server'], 'vless.example');
      expect(rows.last['proxy']['type']['label'], 'VLESS · TLS');

      // The status meter reads the same raw list.
      final readings = proxyReadingsFrom({
        'proxies': [socks, managedRow(2, enabled: true), managedRow(3)],
      })!;
      expect(readings, hasLength(2));
      expect(readings.last.isEnabled, isTrue);
    });

    test('enable, test and remove resolve the profile', () async {
      final rig = _Rig();
      final sent = <Map<String, dynamic>>[];
      final applied = <ProxyConfig>[];
      Future<Map<String, dynamic>> query(Map<String, dynamic> request) =>
          rig.service.viewQuery(
            request: request,
            queryNative: (value) async {
              sent.add(value);
              return value['@type'] == 'getProxies'
                  ? {
                      'proxies': [managedRow(2, enabled: true), socks],
                    }
                  : {'@type': 'ok'};
            },
            applyConfig: (config) async => applied.add(config),
          );

      await query({'@type': 'enableProxy', 'proxy_id': -4});
      expect(applied.single.leaf!.id, 4);
      expect(sent, isEmpty);

      final listed = await query({'@type': 'getProxies'});
      final row = (listed['proxies'] as List).cast<Map<String, dynamic>>().last;
      await query({
        '@type': 'testProxy',
        'proxy': row['proxy'],
        'dc_id': 2,
        'timeout': 5.0,
      });
      final probe = sent.last;
      expect(probe['proxy']['server'], '127.0.0.1');
      expect(probe['proxy']['port'], rig.tunnels.single.socksPort);
      expect(probe['proxy'].containsKey('mithka_leaf'), isFalse);
      expect(rig.tunnels.single.stopped, isTrue);

      sent.clear();
      await query({'@type': 'removeProxy', 'proxy_id': -4});
      expect(
        sent
            .where((r) => r['@type'] == 'removeProxy')
            .map((r) => r['proxy_id']),
        [2],
      );
      expect(await ProxyConfig.loadLeafProfiles(), isEmpty);
    });
  });

  testWidgets('the fallback strip names why a page is direct', (tester) async {
    Future<void> pump(BrowserProxyNotice notice) => tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppColors.light]),
        home: Scaffold(body: BrowserProxyNoticeBar(notice: notice)),
      ),
    );

    await pump(BrowserProxyNotice.none);
    expect(find.byType(Text), findsNothing);

    await pump(BrowserProxyNotice.unsupported);
    expect(
      find.text(AppStrings.t(AppStringKeys.proxyBrowserUnsupported)),
      findsOneWidget,
    );

    await pump(BrowserProxyNotice.notReady);
    expect(
      find.byKey(const ValueKey('browser-proxy-notice-notReady')),
      findsOneWidget,
    );
  });
}
