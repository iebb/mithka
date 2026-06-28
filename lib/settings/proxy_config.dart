import 'package:shared_preferences/shared_preferences.dart';

import '../tdlib/json_helpers.dart';

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

  Map<String, dynamic> get addProxyRequest => {
    '@type': 'addProxy',
    'server': server.trim(),
    'port': port,
    'enable': true,
    'type': tdType,
  };

  bool matchesTdProxy(Map<String, dynamic> proxy) {
    if ((proxy.str('server') ?? '') != server.trim()) return false;
    if ((proxy.integer('port') ?? 0) != port) return false;
    final tdType = proxy.obj('type');
    return switch (type) {
      'http' => tdType?.type == 'proxyTypeHttp',
      'mtproto' => tdType?.type == 'proxyTypeMtproto',
      _ => tdType?.type == 'proxyTypeSocks5',
    };
  }

  static ProxyConfig fromTdProxy(Map<String, dynamic> proxy) {
    final type = proxy.obj('type');
    final kind = switch (type?.type) {
      'proxyTypeHttp' => 'http',
      'proxyTypeMtproto' => 'mtproto',
      _ => 'socks5',
    };
    return ProxyConfig(
      configured: true,
      enabled: true,
      type: kind,
      server: proxy.str('server') ?? '',
      port: proxy.integer('port') ?? 0,
      username: type?.str('username') ?? '',
      password: type?.str('password') ?? '',
      secret: type?.str('secret') ?? '',
    );
  }

  static Future<ProxyConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ProxyConfig(
      configured: prefs.containsKey(_enabledKey),
      enabled: prefs.getBool(_enabledKey) ?? false,
      type: prefs.getString(_typeKey) ?? 'socks5',
      server: prefs.getString(_serverKey) ?? '',
      port: prefs.getInt(_portKey) ?? 0,
      username: prefs.getString(_usernameKey) ?? '',
      password: prefs.getString(_passwordKey) ?? '',
      secret: prefs.getString(_secretKey) ?? '',
    );
  }

  static Future<void> save(ProxyConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, config.enabled);
    await prefs.setString(_typeKey, config.type);
    await prefs.setString(_serverKey, config.server.trim());
    await prefs.setInt(_portKey, config.port);
    await prefs.setString(_usernameKey, config.username);
    await prefs.setString(_passwordKey, config.password);
    await prefs.setString(_secretKey, config.secret);
  }

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
