import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tdlib/json_helpers.dart';

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
  });

  final bool configured;
  final bool enabled;
  final String type;
  final String server;
  final int port;
  final String username;
  final String password;
  final String secret;

  static const _enabledKey = 'mithka.proxy.enabled';
  static const _typeKey = 'mithka.proxy.type';
  static const _serverKey = 'mithka.proxy.server';
  static const _portKey = 'mithka.proxy.port';
  static const _usernameKey = 'mithka.proxy.username';
  static const _passwordKey = 'mithka.proxy.password';
  static const _secretKey = 'mithka.proxy.secret';
  static const _securePasswordKey = 'mithka.proxy.password.v2';
  static const _secureSecretKey = 'mithka.proxy.secret.v2';
  static const _secureStorage = FlutterSecureStorage();

  bool get isUsable => enabled && server.trim().isNotEmpty && port > 0;

  String get label => switch (type) {
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

  Map<String, dynamic> get tdProxy => {
    '@type': 'proxy',
    'server': server.trim(),
    'port': port,
    'type': tdType,
  };

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
    final read = secureRead ?? _defaultSecureRead;
    final write = secureWrite ?? _defaultSecureWrite;
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
    return ProxyConfig(
      configured: prefs.containsKey(_enabledKey),
      enabled: prefs.getBool(_enabledKey) ?? false,
      type: prefs.getString(_typeKey) ?? 'socks5',
      server: prefs.getString(_serverKey) ?? '',
      port: prefs.getInt(_portKey) ?? 0,
      username: prefs.getString(_usernameKey) ?? '',
      password: password,
      secret: secret,
    );
  }

  static Future<void> save(
    ProxyConfig config, {
    SharedPreferences? preferences,
    ProxySecureRead? secureRead,
    ProxySecureWrite? secureWrite,
  }) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    final read = secureRead ?? _defaultSecureRead;
    final write = secureWrite ?? _defaultSecureWrite;
    final previousPassword = await read(_securePasswordKey);
    final previousSecret = await read(_secureSecretKey);
    try {
      await write(
        _securePasswordKey,
        config.password.isEmpty ? null : config.password,
      );
      await write(
        _secureSecretKey,
        config.secret.isEmpty ? null : config.secret,
      );
      final savedPassword = await read(_securePasswordKey);
      final savedSecret = await read(_secureSecretKey);
      if ((savedPassword ?? '') != config.password ||
          (savedSecret ?? '') != config.secret) {
        throw StateError('Proxy credentials could not be verified');
      }
    } catch (_) {
      try {
        await write(_securePasswordKey, previousPassword);
        await write(_secureSecretKey, previousSecret);
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
      ),
    );
  }
}
