//
//  app_proxy_service.dart
//
//  Encrypted proxies (Shadowsocks, Trojan, VLESS, VMess) run in an in-process
//  Leaf engine that listens on loopback only. TDLib reaches it as a managed
//  SOCKS5 row, Dart HTTP and the app's WebViews as an HTTP proxy. Nothing here
//  touches device routing: there is no VPN, TUN or system proxy.
//
//  WebViews that cannot be proxied per app (iOS 15-16, macOS 12-13, Android
//  WebView without PROXY_OVERRIDE) load directly and say so; that is the only
//  direct fallback. Desktop windows run their own Flutter engines in the same
//  process, so they read the primary engine's route instead of setting one.
//

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:mithka_proxy/mithka_proxy.dart';

import '../tdlib/json_helpers.dart';
import 'leaf_proxy_profile.dart';
import 'proxy_config.dart';

typedef ProxyQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic>);

abstract interface class ProxyTunnel {
  int get socksPort;
  int get httpPort;
  bool get isRunning;
  Future<void> stop();
}

final class _NativeTunnel implements ProxyTunnel {
  _NativeTunnel(this.engine);
  final LeafEngine engine;
  @override
  int get socksPort => engine.socksPort;
  @override
  int get httpPort => engine.httpPort;
  @override
  bool get isRunning => engine.isRunning;
  @override
  Future<void> stop() => engine.stop();
}

class _TunnelEntry {
  _TunnelEntry(this.key, this.profile, this.tunnel);
  final String key;
  final LeafProxyProfile profile;
  final Future<ProxyTunnel> tunnel;
  int users = 0;
}

class _ClientRoute {
  _ClientRoute(this.entry, this.config, this.applyNative, this.isForeground);
  final _TunnelEntry entry;
  final ProxyConfig config;
  final Future<void> Function(ProxyConfig) applyNative;
  final bool Function() isForeground;
}

enum BrowserProxyRoute { direct, proxied, directFallback }

/// Owns tunnel lifetimes independently of the active account. All mutations of
/// one client's route are ordered; another account cannot stop its tunnel.
class AppProxyService {
  AppProxyService({
    Future<ProxyTunnel> Function(LeafProxyProfile)? start,
    Future<bool> Function(int?)? configureBrowser,
    Future<bool> Function()? supportsBrowser,
    int? Function()? readAppPort,
    void Function(int?)? writeAppPort,
    Future<bool> Function(int port)? probe,
  }) : _start = start ?? _startNative,
       _configureBrowser = configureBrowser ?? LeafWebViewProxy.configure,
       _supportsBrowser = supportsBrowser ?? LeafWebViewProxy.isSupported,
       _readAppPort = readAppPort ?? (() => LeafEngine.appHttpPort),
       _writeAppPort =
           writeAppPort ?? ((port) => LeafEngine.appHttpPort = port),
       _probe = probe ?? _probeLoopback;

  static final shared = AppProxyService();

  /// The SOCKS5 username marking TDLib rows this service manages:
  /// `mithka-leaf:<profile id>`. The view hides them behind their profile.
  static const managedPrefix = 'mithka-leaf:';

  static Future<ProxyTunnel> _startNative(LeafProxyProfile profile) async =>
      _NativeTunnel(await LeafEngine.start(jsonEncode(profile.leafConfig)));

  static Future<bool> _probeLoopback(int port) async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(seconds: 1),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  final Future<ProxyTunnel> Function(LeafProxyProfile) _start;
  final Future<bool> Function(int?) _configureBrowser;
  final Future<bool> Function() _supportsBrowser;
  final int? Function() _readAppPort;
  final void Function(int?) _writeAppPort;
  final Future<bool> Function(int port) _probe;
  final Map<String, _TunnelEntry> _entries = {};
  final Map<int, _ClientRoute> _clients = {};
  final Map<int, Future<void>> _operations = {};
  final Map<int, LeafProxyProfile> _knownProfiles = {};
  _TunnelEntry? _browserEntry;
  Future<void> _browserOperation = Future.value();
  BrowserProxyRoute _route = BrowserProxyRoute.direct;
  int? _appliedPort;
  bool _appliedSupported = true;
  int _foregroundApplies = 0;
  int _foregroundGeneration = 0;
  Completer<void>? _foregroundIdle;
  bool _secondary = false;
  bool _installed = false;
  AppLifecycleListener? _lifecycle;

  /// Once per engine, from main: routes Dart HTTP. The primary engine also
  /// re-checks tunnels on resume, when iOS may have reclaimed the loopback
  /// listeners of a suspended app.
  void install() {
    if (_installed) return;
    _installed = true;
    HttpOverrides.global = _ProxyHttpOverrides(this, HttpOverrides.current);
    if (!_secondary) {
      _lifecycle = AppLifecycleListener(onResume: () => unawaited(recover()));
    }
  }

  /// A desktop window engine: it shares the primary engine's tunnels through
  /// TDLib and the process-wide port, and must never reconfigure WebKit.
  void markSecondaryEngine() => _secondary = true;

  static bool isManagedRow(Map<String, dynamic> row) =>
      managedUsername(row).startsWith(managedPrefix);

  static String managedUsername(Map<String, dynamic> row) =>
      ProxyConfig.tdProxyDetails(row).obj('type')?.str('username') ?? '';

  static int? managedProfileId(Map<String, dynamic> row) {
    final username = managedUsername(row);
    if (!username.startsWith(managedPrefix)) return null;
    return int.tryParse(username.substring(managedPrefix.length));
  }

  /// The profile behind a managed row, while this engine has it running.
  LeafProxyProfile? profileFor(Map<String, dynamic> row) {
    final id = managedProfileId(row);
    return id == null ? null : _knownProfiles[id];
  }

  Future<T> _ordered<T>(int clientId, Future<T> Function() operation) {
    final result = (_operations[clientId] ?? Future.value()).then(
      (_) => operation(),
    );
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _operations[clientId] = tail;
    return result.whenComplete(() {
      if (identical(_operations[clientId], tail)) _operations.remove(clientId);
    });
  }

  /// Browsers opened while a foreground route is being changed wait for it,
  /// so a page cannot load directly in the gap before the tunnel is up.
  Future<T> _holdingBrowser<T>(Future<T> Function() body) async {
    _foregroundApplies++;
    try {
      return await body();
    } finally {
      if (--_foregroundApplies == 0) {
        _foregroundIdle?.complete();
        _foregroundIdle = null;
      }
    }
  }

  _TunnelEntry _acquire(LeafProxyProfile profile) {
    final key = jsonEncode(profile.toJson());
    final entry = _entries.putIfAbsent(
      key,
      () => _TunnelEntry(key, profile, _start(profile)),
    );
    entry.users++;
    _knownProfiles[profile.id] = profile;
    return entry;
  }

  Future<void> _release(_TunnelEntry? entry) async {
    if (entry == null || --entry.users != 0) return;
    if (identical(_entries[entry.key], entry)) _entries.remove(entry.key);
    if (!_entries.values.any((e) => e.profile.id == entry.profile.id)) {
      _knownProfiles.remove(entry.profile.id);
    }
    try {
      await (await entry.tunnel).stop();
    } catch (_) {}
  }

  static ProxyConfig _local(LeafProxyProfile profile, ProxyTunnel tunnel) =>
      ProxyConfig(
        configured: true,
        enabled: true,
        type: 'socks5',
        server: '127.0.0.1',
        port: tunnel.socksPort,
        username: '$managedPrefix${profile.id}',
      );

  Future<void> apply({
    required ProxyConfig config,
    required int clientId,
    required Future<void> Function(ProxyConfig) applyNative,
    required bool Function() isForeground,
  }) {
    if (_secondary && config.isUsable && config.leaf != null) {
      // A tunnel started here would outlive this window's engine.
      return Future.error(
        UnsupportedError('Encrypted proxies are managed in the main window'),
      );
    }
    Future<void> body() => _ordered(clientId, () async {
      final profile = config.isUsable ? config.leaf : null;
      _TunnelEntry? next;
      try {
        if (profile != null) next = _acquire(profile);
        final native = next == null
            ? config
            : _local(profile!, await next.tunnel);
        await applyNative(native);
      } catch (_) {
        await _release(next);
        rethrow;
      }
      final previous = _clients.remove(clientId);
      if (next != null) {
        _clients[clientId] = _ClientRoute(
          next,
          config,
          applyNative,
          isForeground,
        );
      }
      if (isForeground()) await prepareBrowser(clientId);
      await _release(previous?.entry);
    });
    return isForeground() && !_secondary ? _holdingBrowser(body) : body();
  }

  /// The foreground account changed to [clientId]. Browsers opened meanwhile
  /// wait until its route, including a saved proxy still [applying], is set.
  /// A later account switch supersedes an older restore still in flight.
  Future<void> followForeground(int clientId, [Future<void>? applying]) {
    if (_secondary) return Future.value();
    final generation = ++_foregroundGeneration;
    return _holdingBrowser(() async {
      try {
        await applying;
      } catch (_) {}
      if (generation != _foregroundGeneration) return;
      await prepareBrowser(clientId);
    });
  }

  /// Points WebViews and Dart HTTP at [clientId]'s tunnel. Call after the
  /// foreground account changes; each TDLib account keeps its own route.
  Future<BrowserProxyRoute> prepareBrowser(int clientId) {
    if (_secondary) return browserRoute();
    final completer = Completer<BrowserProxyRoute>();
    _browserOperation = _browserOperation.then((_) async {
      try {
        final next = _clients[clientId]?.entry;
        if (next != null) next.users++;
        final previous = _browserEntry;
        _browserEntry = next;
        int? port;
        try {
          port = next == null ? null : (await next.tunnel).httpPort;
        } catch (_) {}
        // Direct is how the platform starts, so an unchanged route sends
        // nothing; a refused one is retried on the next change.
        var supported = _appliedSupported;
        if (port != _appliedPort || !_appliedSupported) {
          try {
            _writeAppPort(port);
          } catch (_) {}
          supported = await _configureBrowserBounded(port);
          _appliedPort = port;
          _appliedSupported = supported;
        }
        await _release(previous);
        _route = next == null
            ? BrowserProxyRoute.direct
            : supported && port != null
            ? BrowserProxyRoute.proxied
            : BrowserProxyRoute.directFallback;
        completer.complete(_route);
      } catch (error, stack) {
        // Never break the chain: the next foreground change must still run.
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  /// The route a WebView about to load should report. Waits for a foreground
  /// change in flight; a secondary engine reads the primary engine's port.
  Future<BrowserProxyRoute> browserRoute() async {
    if (_secondary) {
      final port = _readAppPortOrNull();
      if (port == null) return BrowserProxyRoute.direct;
      return await _platformAnswer(_supportsBrowser)
          ? BrowserProxyRoute.proxied
          : BrowserProxyRoute.directFallback;
    }
    while (_foregroundApplies > 0) {
      await (_foregroundIdle ??= Completer<void>()).future;
    }
    await _browserOperation;
    return _route;
  }

  /// A platform side that never answers must not stall every later route
  /// change behind it; it reads as unsupported.
  Future<bool> _configureBrowserBounded(int? port) =>
      _platformAnswer(() => _configureBrowser(port));

  Future<bool> _platformAnswer(Future<bool> Function() operation) async {
    try {
      return await operation().timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
    } catch (_) {
      return false;
    }
  }

  int? _readAppPortOrNull() {
    try {
      return _readAppPort();
    } catch (_) {
      return null;
    }
  }

  /// Restarts every tunnel whose engine stopped or whose listener no longer
  /// accepts, and re-points the clients and browser that used it.
  Future<void> recover() async {
    if (_secondary) return;
    for (final entry in _entries.values.toList()) {
      final ProxyTunnel tunnel;
      try {
        tunnel = await entry.tunnel;
      } catch (_) {
        continue;
      }
      if (tunnel.isRunning && await _probe(tunnel.socksPort)) continue;
      if (identical(_entries[entry.key], entry)) _entries.remove(entry.key);
      final routes = {
        for (final client in _clients.entries)
          if (identical(client.value.entry, entry)) client.key: client.value,
      };
      await Future.wait([
        for (final MapEntry(key: clientId, value: route) in routes.entries)
          apply(
            config: route.config,
            clientId: clientId,
            applyNative: route.applyNative,
            isForeground: route.isForeground,
          ).catchError((Object _) {}),
      ]);
    }
  }

  Future<void> releaseClient(int clientId) => _ordered(clientId, () async {
    // The browser holds its own reference; it moves on the next foreground
    // change, so releasing a background account never repoints it.
    await _release(_clients.remove(clientId)?.entry);
  });

  @visibleForTesting
  Future<void> dispose() async {
    await Future.wait(_operations.values.toList());
    for (final id in _clients.keys.toList()) {
      await releaseClient(id);
    }
    await prepareBrowser(0);
    _lifecycle?.dispose();
  }

  /// Presents encrypted profiles alongside TDLib's native proxies. Negative
  /// ids belong only to this adapter; no synthetic type is ever sent to TDLib.
  Future<Map<String, dynamic>> viewQuery({
    required Map<String, dynamic> request,
    required ProxyQuery queryNative,
    required Future<void> Function(ProxyConfig) applyConfig,
  }) async {
    final kind = request.type;
    if (kind == 'getProxies') {
      final raw = await queryNative(request);
      List<LeafProxyProfile> profiles;
      try {
        profiles = await ProxyConfig.loadLeafProfiles();
      } catch (_) {
        profiles = const [];
      }
      final rows = raw.objects('proxies') ?? const <Map<String, dynamic>>[];
      bool enabled(LeafProxyProfile profile) => rows.any(
        (row) =>
            row.boolean('is_enabled') == true &&
            managedProfileId(row) == profile.id,
      );
      return {
        ...raw,
        'proxies': [
          for (final row in rows)
            if (!isManagedRow(row)) row,
          for (final profile in profiles)
            {
              '@type': 'addedProxy',
              'id': -profile.id,
              'is_enabled': enabled(profile),
              'proxy': {
                '@type': 'proxy',
                'server': profile.server,
                'port': profile.port,
                'type': {
                  '@type': 'mithkaLeafProxy',
                  'protocol': profile.protocolLabel,
                  'label': [
                    if (profile.name.isNotEmpty) profile.name,
                    profile.transportLabel,
                  ].join(' · '),
                },
                'mithka_leaf': profile.toJson(),
              },
            },
        ],
      };
    }
    final id = request.integer('proxy_id') ?? 0;
    if ((kind == 'enableProxy' || kind == 'removeProxy') && id < 0) {
      final profiles = await ProxyConfig.loadLeafProfiles();
      final profile = profiles.where((p) => p.id == -id).firstOrNull;
      if (profile == null) throw StateError('Proxy no longer exists');
      if (kind == 'enableProxy') {
        await applyConfig(ProxyConfig.encrypted(profile));
      } else {
        final raw = await queryNative({'@type': 'getProxies'});
        for (final row
            in raw.objects('proxies') ?? const <Map<String, dynamic>>[]) {
          if (managedProfileId(row) == profile.id) {
            await queryNative({
              '@type': 'removeProxy',
              'proxy_id': row.integer('id'),
            });
          }
        }
        await ProxyConfig.removeLeafProfile(profile.id);
      }
      return {'@type': 'ok'};
    }
    if (kind == 'testProxy') {
      final profileJson = request.obj('proxy')?.obj('mithka_leaf');
      if (profileJson != null) {
        // Probes through its own short-lived tunnel, or the running one when
        // the profile is already in use.
        final profile = LeafProxyProfile.fromJson(profileJson);
        final entry = _acquire(profile);
        try {
          return await queryNative({
            ...request,
            'proxy': _local(profile, await entry.tunnel).tdProxy,
          });
        } finally {
          await _release(entry);
        }
      }
    }
    return queryNative(request);
  }

  int? get _httpPortForDart => _readAppPortOrNull();
}

class _ProxyHttpOverrides extends HttpOverrides {
  _ProxyHttpOverrides(this.service, this.previous);
  final AppProxyService service;
  final HttpOverrides? previous;

  static bool _isLoopback(String host) {
    if (host == 'localhost') return true;
    final address = InternetAddress.tryParse(host);
    return address != null && address.isLoopback;
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client =
        previous?.createHttpClient(context) ?? super.createHttpClient(context);
    // HttpClient exposes no getter for an earlier resolver; the default one
    // connects directly.
    client.findProxy = (uri) {
      final port = service._httpPortForDart;
      if (port == null || _isLoopback(uri.host)) return 'DIRECT';
      return 'PROXY 127.0.0.1:$port';
    };
    return client;
  }
}
