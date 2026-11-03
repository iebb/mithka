import 'dart:convert';

import 'package:flutter/foundation.dart';
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
    this.path = '',
  });

  final bool configured;
  final bool enabled;
  final String type;
  final String server;
  final int port;
  final String username;
  final String password;
  final String secret;
  final String path;

  static const _enabledKey = 'mithka.proxy.enabled';
  static const _typeKey = 'mithka.proxy.type';
  static const _serverKey = 'mithka.proxy.server';
  static const _portKey = 'mithka.proxy.port';
  static const _pathKey = 'mithka.proxy.path';
  static const _usernameKey = 'mithka.proxy.username';
  static const _passwordKey = 'mithka.proxy.password';
  static const _secretKey = 'mithka.proxy.secret';
  static const _securePasswordKey = 'mithka.proxy.password.v2';
  static const _secureSecretKey = 'mithka.proxy.secret.v2';
  static const _secureStorage = FlutterSecureStorage();

  /// Test seams: widget tests run without the platform secure-storage channel,
  /// while still exercising the real saved-config path.
  @visibleForTesting
  static ProxySecureRead? debugSecureRead;
  @visibleForTesting
  static ProxySecureWrite? debugSecureWrite;

  bool get isUsable =>
      enabled &&
      server.trim().isNotEmpty &&
      port > 0 &&
      port <= 65535 &&
      (type != 'web' || isValidWebProxy(server, port, path, secret));

  static bool isValidWebProxy(
    String server,
    int port,
    String path,
    String secret,
  ) {
    final host = server.toLowerCase();
    final labels = host.split('.');
    return port == 443 &&
        host.length <= 253 &&
        labels.length >= 2 &&
        labels.every(
          (label) =>
              label.isNotEmpty &&
              label.length <= 63 &&
              RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(label),
        ) &&
        !RegExp(r'^(?:[0-9]+|0x[0-9a-f]*)$').hasMatch(labels.last) &&
        path.length <= 128 &&
        (path.isEmpty ||
            RegExp(
              r'^[A-Za-z0-9][A-Za-z0-9_-]*(?:/[A-Za-z0-9][A-Za-z0-9_-]*)*$',
            ).hasMatch(path)) &&
        RegExp(r'^(?:dd)?[0-9a-f]{32}$').hasMatch(secret.toLowerCase());
  }

  String get label => switch (type) {
    'http' => 'HTTP',
    'mtproto' => 'MTProto',
    'web' => 'Web',
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
    'web' => {'@type': 'proxyTypeWeb', 'path': path, 'secret': secret},
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

  static bool get supportsWebProxy =>
      !kIsWeb &&
      const [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ].contains(defaultTargetPlatform);

  static bool isSupportedTdProxy(Map<String, dynamic> proxy) =>
      switch (tdProxyDetails(proxy).obj('type')?.type) {
        'proxyTypeSocks5' || 'proxyTypeHttp' || 'proxyTypeMtproto' => true,
        'proxyTypeWeb' => supportsWebProxy,
        _ => false,
      };

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
      'web' =>
        tdType?.type == 'proxyTypeWeb' &&
            (tdType?.str('secret') ?? '') == secret &&
            (tdType?.str('path') ?? '') == path,
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
      'proxyTypeWeb' => 'web',
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
      path: type?.str('path') ?? '',
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
        'webproxy' => 'web',
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
        'webproxy' => 'web',
        _ => null,
      };
    }
    if (kind == null) return null;

    final params = uri.queryParameters;
    if (kind == 'web') {
      var address = (params['server'] ?? '').trim();
      if (address.toLowerCase().startsWith('https://')) {
        address = address.substring(8);
      }
      final slash = address.indexOf('/');
      var host = (slash < 0 ? address : address.substring(0, slash))
          .toLowerCase();
      if (host.endsWith('.')) host = host.substring(0, host.length - 1);
      final path = slash < 0 ? '' : address.substring(slash + 1);
      final secret = _webLinkSecret(params['secret'] ?? '', path.isNotEmpty);
      if (secret == null || !isValidWebProxy(host, 443, path, secret)) {
        return null;
      }
      return ProxyConfig(
        configured: true,
        enabled: true,
        type: 'web',
        server: host,
        port: 443,
        path: path,
        secret: secret,
      );
    }
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

  static String? _webLinkSecret(String value, bool hasPath) {
    final hexSecret = value.toLowerCase();
    final valid = RegExp(r'^(?:dd)?[0-9a-f]{32}$');
    String hex(List<int> bytes) =>
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    List<int>? bytes;
    try {
      bytes = base64Url.decode(base64Url.normalize(value));
      final canonical = base64Url.encode(bytes).replaceAll('=', '');
      if (canonical == value && bytes.length >= 17 && bytes.first == 0x70) {
        final marked = hex(bytes.sublist(1));
        if (valid.hasMatch(marked)) return marked;
      }
    } on FormatException {
      // Hex secrets are also accepted when there is no relay path.
    }
    if (hasPath) return null;
    if (valid.hasMatch(hexSecret)) return hexSecret;
    final decoded = bytes == null ? '' : hex(bytes);
    return valid.hasMatch(decoded) ? decoded : null;
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
    return ProxyConfig(
      configured: prefs.containsKey(_enabledKey),
      enabled: prefs.getBool(_enabledKey) ?? false,
      type: prefs.getString(_typeKey) ?? 'socks5',
      server: prefs.getString(_serverKey) ?? '',
      port: prefs.getInt(_portKey) ?? 0,
      username: prefs.getString(_usernameKey) ?? '',
      password: password,
      secret: secret,
      path: prefs.getString(_pathKey) ?? '',
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
    await prefs.setString(_pathKey, config.path);
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
