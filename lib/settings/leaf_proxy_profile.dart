import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// An app-owned encrypted proxy. Credentials are serialized only to secure
/// storage; the generated Leaf configuration never contains routing or TUN.
class LeafProxyProfile {
  const LeafProxyProfile({
    required this.id,
    required this.protocol,
    required this.server,
    required this.port,
    this.name = '',
    this.password = '',
    this.uuid = '',
    this.cipher = 'chacha20-ietf-poly1305',
    this.security = 'aes-128-gcm',
    this.tls = false,
    this.serverName = '',
    this.webSocket = false,
    this.webSocketPath = '/',
    this.webSocketHost = '',
    this.vision = false,
  });

  final int id;
  final String protocol;
  final String server;
  final int port;
  final String name;
  final String password;
  final String uuid;

  /// Shadowsocks AEAD method.
  final String cipher;

  /// VMess body cipher.
  final String security;
  final bool tls;
  final String serverName;
  final bool webSocket;
  final String webSocketPath;
  final String webSocketHost;
  final bool vision;

  static const protocols = ['ss', 'trojan', 'vless', 'vmess'];

  /// What the bundled ring backend implements.
  static const ciphers = [
    'chacha20-ietf-poly1305',
    'aes-128-gcm',
    'aes-256-gcm',
  ];
  static const vmessSecurities = ['aes-128-gcm', 'chacha20-poly1305'];

  static int newId() => 1 + Random.secure().nextInt(0x7ffffffe);

  String get protocolLabel => switch (protocol) {
    'ss' => 'Shadowsocks',
    'trojan' => 'Trojan',
    'vless' => vision ? 'VLESS Vision' : 'VLESS',
    'vmess' => 'VMess',
    _ => protocol,
  };

  /// Protocol plus transport, for a row's second line.
  String get transportLabel => [
    protocolLabel,
    if (webSocket) 'WebSocket',
    if (tls && protocol != 'trojan') 'TLS',
  ].join(' · ');

  String get label => name.isEmpty ? protocolLabel : name;

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static final _label = RegExp(
    r'^[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?$',
  );
  static final _path = RegExp(r"^/[A-Za-z0-9\-._~!$&'()*+,;=:@/%?]*$");

  /// A DNS name, an IPv4 address or an unbracketed IPv6 address.
  static bool isHost(String value) {
    if (value.isEmpty || value.length > 253) return false;
    if (InternetAddress.tryParse(value) != null) return true;
    final name = value.endsWith('.')
        ? value.substring(0, value.length - 1)
        : value;
    return name.isNotEmpty && name.split('.').every(_label.hasMatch);
  }

  /// `host` or `host:port`, IPv6 in brackets: a valid HTTP Host header.
  static bool isHostHeader(String value) {
    final match = RegExp(
      r'^(\[[0-9A-Fa-f:.]+\]|[^:\[\]]+)(:(\d{1,5}))?$',
    ).firstMatch(value);
    if (match == null) return false;
    final host = match.group(1)!;
    final port = match.group(3);
    if (port != null && (int.parse(port) < 1 || int.parse(port) > 65535)) {
      return false;
    }
    return host.startsWith('[')
        ? InternetAddress.tryParse(host.substring(1, host.length - 1))?.type ==
              InternetAddressType.IPv6
        : isHost(host);
  }

  void validate() {
    if (id <= 0 || !protocols.contains(protocol)) {
      throw const FormatException('Unsupported proxy type');
    }
    if (!isHost(server) || port < 1 || port > 65535) {
      throw const FormatException('Invalid proxy server or port');
    }
    if ((protocol == 'ss' || protocol == 'trojan') &&
        (password.isEmpty || password.contains(RegExp(r'[\x00-\x1f]')))) {
      throw const FormatException('A proxy password is required');
    }
    if (protocol == 'ss' && !ciphers.contains(cipher)) {
      throw const FormatException('Unsupported Shadowsocks cipher');
    }
    if ((protocol == 'vless' || protocol == 'vmess') && !_uuid.hasMatch(uuid)) {
      throw const FormatException('A valid UUID is required');
    }
    if (protocol == 'vmess' && !vmessSecurities.contains(security)) {
      throw const FormatException('Unsupported VMess security');
    }
    if (protocol == 'ss' && (tls || webSocket)) {
      throw const FormatException('Shadowsocks runs over TCP only');
    }
    if (protocol == 'trojan' && !tls) {
      throw const FormatException('Trojan requires TLS');
    }
    if (vision && (protocol != 'vless' || !tls || webSocket)) {
      throw const FormatException('Vision requires VLESS over TCP and TLS');
    }
    if (serverName.isNotEmpty && !isHost(serverName)) {
      throw const FormatException('Invalid TLS server name');
    }
    if (webSocket &&
        (webSocketPath.length > 512 || !_path.hasMatch(webSocketPath))) {
      throw const FormatException('Invalid WebSocket path');
    }
    if (webSocketHost.isNotEmpty && !isHostHeader(webSocketHost)) {
      throw const FormatException('Invalid WebSocket host');
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'protocol': protocol,
    'server': server,
    'port': port,
    'name': name,
    'password': password,
    'uuid': uuid,
    'cipher': cipher,
    'security': security,
    'tls': tls,
    'serverName': serverName,
    'webSocket': webSocket,
    'webSocketPath': webSocketPath,
    'webSocketHost': webSocketHost,
    'vision': vision,
  };

  /// The same endpoint and credentials, whatever the id or display name.
  bool sameSettings(LeafProxyProfile other) {
    final mine = toJson()
      ..remove('id')
      ..remove('name');
    final theirs = other.toJson()
      ..remove('id')
      ..remove('name');
    return jsonEncode(mine) == jsonEncode(theirs);
  }

  factory LeafProxyProfile.fromJson(Map<String, dynamic> json) {
    final profile = LeafProxyProfile(
      id: json['id'] as int,
      protocol: json['protocol'] as String,
      server: json['server'] as String,
      port: json['port'] as int,
      name: json['name'] as String? ?? '',
      password: json['password'] as String? ?? '',
      uuid: json['uuid'] as String? ?? '',
      cipher: json['cipher'] as String? ?? 'chacha20-ietf-poly1305',
      security: json['security'] as String? ?? 'aes-128-gcm',
      tls: json['tls'] as bool? ?? false,
      serverName: json['serverName'] as String? ?? '',
      webSocket: json['webSocket'] as bool? ?? false,
      webSocketPath: json['webSocketPath'] as String? ?? '/',
      webSocketHost: json['webSocketHost'] as String? ?? '',
      vision: json['vision'] as bool? ?? false,
    );
    profile.validate();
    return profile;
  }

  String get _bracketedServer =>
      InternetAddress.tryParse(server)?.type == InternetAddressType.IPv6
      ? '[$server]'
      : server;

  /// TLS, WebSocket, then the proxy handshake, from wire to application.
  /// Certificates are always verified; there is no insecure option.
  Map<String, dynamic> get leafConfig {
    validate();
    final actors = <String>[];
    final outbounds = <Map<String, dynamic>>[];
    if (tls) {
      actors.add('tls');
      outbounds.add({
        'tag': 'tls',
        'protocol': 'tls',
        'settings': {
          'serverName': serverName.isEmpty ? server : serverName,
          // WebSocket needs HTTP/1.1; the raw TLS protocols ignore ALPN.
          'alpn': ['http/1.1'],
          'insecure': false,
        },
      });
    }
    if (webSocket) {
      actors.add('ws');
      outbounds.add({
        'tag': 'ws',
        'protocol': 'ws',
        'settings': {
          'path': webSocketPath,
          // Always explicit: Leaf would otherwise build the URL from a bare
          // IPv6 address.
          'headers': {
            'Host': webSocketHost.isNotEmpty
                ? webSocketHost
                : serverName.isNotEmpty
                ? serverName
                : _bracketedServer,
          },
        },
      });
    }
    actors.add('protocol');
    outbounds.add({
      'tag': 'protocol',
      'protocol': protocol == 'ss' ? 'shadowsocks' : protocol,
      'settings': {
        'address': server,
        'port': port,
        if (protocol == 'ss') ...{'method': cipher, 'password': password},
        if (protocol == 'trojan') 'password': password,
        if (protocol == 'vless' || protocol == 'vmess') 'uuid': uuid,
        if (protocol == 'vmess') 'security': security,
        if (protocol == 'vless') 'flow': vision ? 'xtls-rprx-vision' : '',
      },
    });
    return {
      'outbounds': [
        {
          'tag': 'proxy',
          'protocol': 'chain',
          'settings': {'actors': actors},
        },
        ...outbounds,
      ],
    };
  }

  /// SIP002 and legacy `ss://`, `trojan://`, `vless://`, and VMess v2 base64
  /// JSON. Anything this engine cannot honour exactly (REALITY, other
  /// transports, plugins, insecure TLS, legacy VMess) is rejected, never
  /// silently changed.
  static LeafProxyProfile? fromUrl(String value) {
    try {
      final text = value.trim();
      final colon = text.indexOf('://');
      if (colon <= 0) return null;
      final protocol = text.substring(0, colon).toLowerCase();
      if (!protocols.contains(protocol)) return null;
      final rest = text.substring(colon + 3);
      final profile = switch (protocol) {
        'vmess' => _fromVmess(rest),
        'ss' => _fromShadowsocks(rest),
        _ => _fromUriStyle(protocol, Uri.parse('$protocol://$rest')),
      };
      profile?.validate();
      return profile;
    } catch (_) {
      return null;
    }
  }

  static String _fragmentName(String text) {
    final hash = text.indexOf('#');
    if (hash < 0) return '';
    try {
      return Uri.decodeComponent(text.substring(hash + 1)).trim();
    } catch (_) {
      return text.substring(hash + 1).trim();
    }
  }

  static String _decode64(String value) {
    final cleaned = value.trim().replaceAll('-', '+').replaceAll('_', '/');
    return utf8.decode(base64.decode(base64.normalize(cleaned)));
  }

  static LeafProxyProfile? _fromVmess(String rest) {
    final json =
        jsonDecode(_decode64(rest.split('#').first)) as Map<String, dynamic>;
    String field(String key) => json[key]?.toString().trim() ?? '';
    final net = field('net').isEmpty ? 'tcp' : field('net');
    final aid = int.tryParse(field('aid').isEmpty ? '0' : field('aid'));
    final headerType = field('type');
    final security = switch (field('scy').toLowerCase()) {
      '' || 'auto' || 'aes-128-gcm' => 'aes-128-gcm',
      'chacha20-poly1305' || 'chacha20-ietf-poly1305' => 'chacha20-poly1305',
      _ => null,
    };
    if (!['tcp', 'ws'].contains(net) ||
        aid != 0 ||
        !['', 'none'].contains(headerType) ||
        !['', 'none', 'tls'].contains(field('tls')) ||
        security == null) {
      return null;
    }
    return LeafProxyProfile(
      id: newId(),
      protocol: 'vmess',
      server: field('add'),
      port: int.parse(field('port')),
      uuid: field('id'),
      name: field('ps'),
      security: security,
      tls: field('tls') == 'tls',
      serverName: field('sni'),
      webSocket: net == 'ws',
      webSocketPath: field('path').isEmpty ? '/' : field('path'),
      webSocketHost: field('host'),
    );
  }

  static LeafProxyProfile? _fromShadowsocks(String rest) {
    final name = _fragmentName(rest);
    final body = rest.split('#').first;
    final at = body.lastIndexOf('@');
    final String method;
    final String password;
    final Uri endpoint;
    if (at < 0) {
      // Legacy: base64(method:password@host:port).
      final decoded = _decode64(body);
      final split = decoded.lastIndexOf('@');
      final credentials = decoded.substring(0, split);
      endpoint = Uri.parse('ss://${decoded.substring(split + 1)}');
      final colon = credentials.indexOf(':');
      method = credentials.substring(0, colon);
      password = credentials.substring(colon + 1);
    } else {
      endpoint = Uri.parse('ss://${body.substring(at + 1)}');
      if (endpoint.queryParameters['plugin']?.isNotEmpty ?? false) return null;
      var userInfo = Uri.decodeComponent(body.substring(0, at));
      if (!userInfo.contains(':')) userInfo = _decode64(userInfo);
      final colon = userInfo.indexOf(':');
      method = userInfo.substring(0, colon);
      password = userInfo.substring(colon + 1);
    }
    final cipher = method.toLowerCase() == 'chacha20-poly1305'
        ? 'chacha20-ietf-poly1305'
        : method.toLowerCase();
    return LeafProxyProfile(
      id: newId(),
      protocol: 'ss',
      server: endpoint.host,
      port: endpoint.port,
      name: name,
      cipher: cipher,
      password: password,
    );
  }

  static LeafProxyProfile? _fromUriStyle(String protocol, Uri uri) {
    final q = uri.queryParameters;
    final transport = (q['type'] ?? 'tcp').toLowerCase();
    final security = (q['security'] ?? (protocol == 'trojan' ? 'tls' : 'none'))
        .toLowerCase();
    final flow = q['flow'] ?? '';
    final insecure = ['1', 'true'];
    if (!['tcp', 'ws'].contains(transport) ||
        !['none', 'tls', ''].contains(security) ||
        !['', 'none'].contains(q['headerType'] ?? '') ||
        !['', 'xtls-rprx-vision'].contains(flow) ||
        (protocol == 'vless' &&
            !['', 'none'].contains(q['encryption'] ?? '')) ||
        insecure.contains(q['allowInsecure']) ||
        insecure.contains(q['insecure'])) {
      return null;
    }
    final credential = Uri.decodeComponent(uri.userInfo);
    return LeafProxyProfile(
      id: newId(),
      protocol: protocol,
      server: uri.host,
      port: uri.port,
      name: uri.hasFragment ? _fragmentName('#${uri.fragment}') : '',
      password: protocol == 'trojan' ? credential : '',
      uuid: protocol == 'vless' ? credential : '',
      tls: security == 'tls',
      serverName: q['sni'] ?? q['peer'] ?? '',
      webSocket: transport == 'ws',
      webSocketPath: q['path']?.isNotEmpty == true ? q['path']! : '/',
      webSocketHost: q['host'] ?? '',
      vision: flow == 'xtls-rprx-vision',
    );
  }
}
