import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mithka_proxy/mithka_proxy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tdlib/json_helpers.dart';
import 'leaf_proxy_profile.dart';

typedef ProxySecureRead = Future<String?> Function(String key);
typedef ProxySecureWrite = Future<void> Function(String key, String? value);

class ProxyConfig {
  const ProxyConfig({
    required this.configured,
    required this.enabled,
    required this.type,
    required this.server,
    required this.port,
    this.username = '',
    this.password = '',
    this.secret = '',
    this.leaf,
  });

  final bool configured;
  final bool enabled;
  final String type;
  final String server;
  final int port;
  final String username;
  final String password;
  final String secret;
  final LeafProxyProfile? leaf;

  factory ProxyConfig.encrypted(LeafProxyProfile profile) => ProxyConfig(
    configured: true,
    enabled: true,
    type: profile.protocol,
    server: profile.server,
    port: profile.port,
    leaf: profile,
  );

  static const _enabledKey = 'mithka.proxy.enabled';
  static const _typeKey = 'mithka.proxy.type';
  static const _serverKey = 'mithka.proxy.server';
  static const _portKey = 'mithka.proxy.port';
  static const _usernameKey = 'mithka.proxy.username';
  static const _passwordKey = 'mithka.proxy.password';
  static const _secretKey = 'mithka.proxy.secret';
  static const _securePasswordKey = 'mithka.proxy.password.v2';
  static const _secureSecretKey = 'mithka.proxy.secret.v2';
  static const _secureLeafKey = 'mithka.proxy.leaf.v1';
  static const _secureCatalogKey = 'mithka.proxy.leaf.catalog.v1';

  /// Not a secret: whether [_secureCatalogKey] holds anything, so a proxy list
  /// read never touches the keychain for someone with no encrypted proxy.
  static const _catalogPresentKey = 'mithka.proxy.leaf.catalog.present';
  static const _secureStorage = FlutterSecureStorage();

  /// Test seams: widget tests run without the platform secure-storage channel,
  /// while still exercising the real saved-config path.
  @visibleForTesting
  static ProxySecureRead? debugSecureRead;
  @visibleForTesting
  static ProxySecureWrite? debugSecureWrite;
  @visibleForTesting
  static bool? debugEncryptedProxiesSupported;

  /// Shadowsocks, Trojan, VLESS and VMess need the bundled Leaf engine, which
  /// is built for Android, iOS and macOS only.
  static bool get encryptedProxiesSupported =>
      debugEncryptedProxiesSupported ?? LeafEngine.isSupported;

  bool get isUsable => enabled && server.trim().isNotEmpty && port > 0;

  String get label =>
      leaf?.protocolLabel ??
      switch (type) {
        'http' => 'HTTP',
        'mtproto' => 'MTProto',
        _ => 'SOCKS5',
      };

  Map<String, dynamic> get tdType => switch (type) {
    'http' => {
      '@type': 'proxyTypeHttp',
      'username': username,
      'password': password,
      'http_only': false,
    },
    'mtproto' => {'@type': 'proxyTypeMtproto', 'secret': secret},
    _ => {
      '@type': 'proxyTypeSocks5',
      'username': username,
      'password': password,
    },
  };

  Map<String, dynamic> get tdProxy {
    if (leaf != null) {
      throw StateError('Encrypted proxies must be resolved through Leaf first');
    }
    return {
      '@type': 'proxy',
      'server': server.trim(),
      'port': port,
      'type': tdType,
    };
  }

  Map<String, dynamic> get addProxyRequest => {
    '@type': 'addProxy',
    'proxy': tdProxy,
    'enable': true,
  };

  static Map<String, dynamic> tdProxyDetails(Map<String, dynamic> proxy) {
    return proxy.obj('proxy') ?? proxy;
  }

  bool matchesTdProxy(Map<String, dynamic> proxy) {
    final details = tdProxyDetails(proxy);
    if ((details.str('server') ?? '') != server.trim()) return false;
    if ((details.integer('port') ?? 0) != port) return false;
    final tdType = details.obj('type');
    return switch (type) {
      'http' =>
        tdType?.type == 'proxyTypeHttp' &&
            (tdType?.str('username') ?? '') == username &&
            (tdType?.str('password') ?? '') == password,
      'mtproto' =>
        tdType?.type == 'proxyTypeMtproto' &&
            (tdType?.str('secret') ?? '') == secret,
      _ =>
        tdType?.type == 'proxyTypeSocks5' &&
            (tdType?.str('username') ?? '') == username &&
            (tdType?.str('password') ?? '') == password,
    };
  }

  static ProxyConfig fromTdProxy(Map<String, dynamic> proxy) {
    final details = tdProxyDetails(proxy);
    final profile = details.obj('mithka_leaf');
    if (profile != null) {
      return ProxyConfig.encrypted(LeafProxyProfile.fromJson(profile));
    }
    final type = details.obj('type');
    final kind = switch (type?.type) {
      'proxyTypeHttp' => 'http',
      'proxyTypeMtproto' => 'mtproto',
      _ => 'socks5',
    };
    return ProxyConfig(
      configured: true,
      enabled: true,
      type: kind,
      server: details.str('server') ?? '',
      port: details.integer('port') ?? 0,
      username: type?.str('username') ?? '',
      password: type?.str('password') ?? '',
      secret: type?.str('secret') ?? '',
    );
  }

  static ProxyConfig? fromTelegramUrl(String raw) {
    if (encryptedProxiesSupported) {
      final encrypted = LeafProxyProfile.fromUrl(raw);
      if (encrypted != null) return ProxyConfig.encrypted(encrypted);
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(candidate);
    if (uri == null) return null;

    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    String? kind;
    if (scheme == 'tg' || scheme == 'mk' || scheme == 'mithka') {
      final tgTarget = host.isNotEmpty ? host : uri.path.toLowerCase();
      kind = switch (tgTarget) {
        'socks' => 'socks5',
        'proxy' => 'mtproto',
        _ => null,
      };
    } else {
      final isTelegramHost =
          host == 't.me' ||
          host == 'telegram.me' ||
          host == 'telegram.dog' ||
          host == 'www.t.me' ||
          host == 'www.telegram.me' ||
          host == 'www.telegram.dog';
      if (!isTelegramHost) return null;
      final segments = uri.pathSegments
          .where((segment) => segment.trim().isNotEmpty)
          .toList();
      final first = segments.isEmpty ? null : segments.first.toLowerCase();
      kind = switch (first) {
        'socks' => 'socks5',
        'proxy' => 'mtproto',
        _ => null,
      };
    }
    if (kind == null) return null;

    final params = uri.queryParameters;
    final server = (params['server'] ?? '').trim();
    final port = int.tryParse((params['port'] ?? '').trim()) ?? 0;
    if (server.isEmpty || port <= 0 || port > 65535) return null;

    final secret = (params['secret'] ?? '').trim();
    if (kind == 'mtproto' && secret.isEmpty) return null;
    final username = (params['user'] ?? params['username'] ?? '').trim();
    final password = (params['pass'] ?? params['password'] ?? '').trim();

    return ProxyConfig(
      configured: true,
      enabled: true,
      type: kind,
      server: server,
      port: port,
      username: username,
      password: password,
      secret: secret,
    );
  }

  static Future<ProxyConfig> load({
    SharedPreferences? preferences,
    ProxySecureRead? secureRead,
    ProxySecureWrite? secureWrite,
  }) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    final read = secureRead ?? debugSecureRead ?? _defaultSecureRead;
    final write = secureWrite ?? debugSecureWrite ?? _defaultSecureWrite;
    final password = await _loadSensitiveValue(
      preferences: prefs,
      legacyKey: _passwordKey,
      secureKey: _securePasswordKey,
      secureRead: read,
      secureWrite: write,
    );
    final secret = await _loadSensitiveValue(
      preferences: prefs,
      legacyKey: _secretKey,
      secureKey: _secureSecretKey,
      secureRead: read,
      secureWrite: write,
    );
    final kind = prefs.getString(_typeKey) ?? 'socks5';
    LeafProxyProfile? leaf;
    if (LeafProxyProfile.protocols.contains(kind)) {
      try {
        final stored = await read(_secureLeafKey);
        if (stored != null) {
          leaf = LeafProxyProfile.fromJson(
            jsonDecode(stored) as Map<String, dynamic>,
          );
        }
      } catch (_) {}
      // Fail closed: an encrypted proxy that cannot be read, or cannot run
      // here, is never turned into a direct connection. Unconfigured leaves
      // every TDLib account on the route it already has.
      if (leaf == null || !encryptedProxiesSupported) {
        return const ProxyConfig(
          configured: false,
          enabled: false,
          type: 'socks5',
          server: '',
          port: 0,
        );
      }
    }
    return ProxyConfig(
      configured: prefs.containsKey(_enabledKey),
      enabled: prefs.getBool(_enabledKey) ?? false,
      type: kind,
      server: prefs.getString(_serverKey) ?? '',
      port: prefs.getInt(_portKey) ?? 0,
      username: prefs.getString(_usernameKey) ?? '',
      password: password,
      secret: secret,
      leaf: leaf,
    );
  }

  static Future<void> save(
    ProxyConfig config, {
    SharedPreferences? preferences,
    ProxySecureRead? secureRead,
    ProxySecureWrite? secureWrite,
  }) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    final read = secureRead ?? debugSecureRead ?? _defaultSecureRead;
    final write = secureWrite ?? debugSecureWrite ?? _defaultSecureWrite;
    final previousPassword = await read(_securePasswordKey);
    final previousSecret = await read(_secureSecretKey);
    final previousLeaf = await read(_secureLeafKey);
    final serializedLeaf = config.leaf == null
        ? null
        : jsonEncode(config.leaf!.toJson());
    try {
      await write(
        _securePasswordKey,
        config.password.isEmpty ? null : config.password,
      );
      await write(
        _secureSecretKey,
        config.secret.isEmpty ? null : config.secret,
      );
      await write(_secureLeafKey, serializedLeaf);
      final savedPassword = await read(_securePasswordKey);
      final savedSecret = await read(_secureSecretKey);
      if ((savedPassword ?? '') != config.password ||
          (savedSecret ?? '') != config.secret ||
          await read(_secureLeafKey) != serializedLeaf) {
        throw StateError('Proxy credentials could not be verified');
      }
      // Only an enabled encrypted proxy joins the list. Disabling keeps the
      // saved route but must not restore a profile the user just removed.
      final leaf = config.leaf;
      if (config.enabled && leaf != null) {
        final catalog = await loadLeafProfiles(
          preferences: prefs,
          secureRead: read,
        );
        await write(
          _secureCatalogKey,
          jsonEncode([
            for (final profile in catalog)
              (profile.id == leaf.id ? leaf : profile).toJson(),
            if (!catalog.any((profile) => profile.id == leaf.id)) leaf.toJson(),
          ]),
        );
        await prefs.setBool(_catalogPresentKey, true);
      }
    } catch (_) {
      try {
        await write(_securePasswordKey, previousPassword);
        await write(_secureSecretKey, previousSecret);
        await write(_secureLeafKey, previousLeaf);
      } catch (_) {
        // Preserve the original secure-storage failure for the caller.
      }
      rethrow;
    }
    await prefs.setBool(_enabledKey, config.enabled);
    await prefs.setString(_typeKey, config.type);
    await prefs.setString(_serverKey, config.server.trim());
    await prefs.setInt(_portKey, config.port);
    await prefs.setString(_usernameKey, config.username);
    await prefs.remove(_passwordKey);
    await prefs.remove(_secretKey);
  }

  /// The saved encrypted proxies. A secure-storage failure throws; entries
  /// that no longer validate are skipped rather than hiding the rest.
  static Future<List<LeafProxyProfile>> loadLeafProfiles({
    SharedPreferences? preferences,
    ProxySecureRead? secureRead,
  }) async {
    if (!encryptedProxiesSupported) return const [];
    final prefs = preferences ?? await SharedPreferences.getInstance();
    if (!(prefs.getBool(_catalogPresentKey) ?? false)) return const [];
    final read = secureRead ?? debugSecureRead ?? _defaultSecureRead;
    final stored = await read(_secureCatalogKey);
    if (stored == null) return const [];
    Object? decoded;
    try {
      decoded = jsonDecode(stored);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];
    final profiles = <LeafProxyProfile>[];
    for (final entry in decoded) {
      try {
        profiles.add(LeafProxyProfile.fromJson(entry as Map<String, dynamic>));
      } catch (_) {}
    }
    return profiles;
  }

  static Future<void> removeLeafProfile(
    int id, {
    SharedPreferences? preferences,
    ProxySecureRead? secureRead,
    ProxySecureWrite? secureWrite,
  }) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    final profiles = await loadLeafProfiles(
      preferences: prefs,
      secureRead: secureRead,
    );
    final write = secureWrite ?? debugSecureWrite ?? _defaultSecureWrite;
    final remaining = [
      for (final profile in profiles)
        if (profile.id != id) profile.toJson(),
    ];
    await write(
      _secureCatalogKey,
      remaining.isEmpty ? null : jsonEncode(remaining),
    );
    await prefs.setBool(_catalogPresentKey, remaining.isNotEmpty);
  }

  /// Reuses the saved profile with the same settings, so adding one link
  /// twice selects the existing proxy instead of listing a duplicate.
  static Future<ProxyConfig> withSavedIdentity(ProxyConfig config) async {
    final leaf = config.leaf;
    if (leaf == null) return config;
    try {
      final saved = await loadLeafProfiles();
      final match = saved.where(leaf.sameSettings).firstOrNull;
      if (match != null) return ProxyConfig.encrypted(match);
    } catch (_) {}
    return config;
  }

  static Future<String> _loadSensitiveValue({
    required SharedPreferences preferences,
    required String legacyKey,
    required String secureKey,
    required ProxySecureRead secureRead,
    required ProxySecureWrite secureWrite,
  }) async {
    final legacyValue = preferences.getString(legacyKey) ?? '';
    try {
      final secureValue = await secureRead(secureKey);
      if (secureValue != null) {
        await preferences.remove(legacyKey);
        return secureValue;
      }
      if (legacyValue.isEmpty) {
        await preferences.remove(legacyKey);
        return '';
      }
      await secureWrite(secureKey, legacyValue);
      final verified = await secureRead(secureKey);
      if (verified == legacyValue) {
        await preferences.remove(legacyKey);
      }
      return legacyValue;
    } catch (_) {
      // Migration is deliberately fail-safe: retain and use the legacy value
      // until secure storage accepts and confirms it on a later load.
      return legacyValue;
    }
  }

  static Future<String?> _defaultSecureRead(String key) =>
      _secureStorage.read(key: key);

  static Future<void> _defaultSecureWrite(String key, String? value) =>
      value == null
      ? _secureStorage.delete(key: key)
      : _secureStorage.write(key: key, value: value);

  static Future<void> disable() async {
    final current = await load();
    await save(
      ProxyConfig(
        configured: true,
        enabled: false,
        type: current.type,
        server: current.server,
        port: current.port,
        username: current.username,
        password: current.password,
        secret: current.secret,
        leaf: current.leaf,
      ),
    );
  }
}
