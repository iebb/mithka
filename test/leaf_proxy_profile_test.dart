//
//  leaf_proxy_profile_test.dart
//
//  Encrypted proxy profiles: what a share link may become, what validation
//  refuses, and the exact Leaf outbound chain a profile produces. Anything the
//  engine cannot honour must be rejected, never silently weakened.
//

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/leaf_proxy_profile.dart';

const _uuid = '0f8b3c2a-5d1e-4f6a-9b7c-1a2b3c4d5e6f';

LeafProxyProfile _profile({
  String protocol = 'vless',
  String server = 'proxy.example',
  int port = 443,
  String password = '',
  String uuid = _uuid,
  String cipher = 'chacha20-ietf-poly1305',
  String security = 'aes-128-gcm',
  bool tls = true,
  String serverName = '',
  bool webSocket = false,
  String webSocketPath = '/',
  String webSocketHost = '',
  bool vision = false,
}) => LeafProxyProfile(
  id: 7,
  protocol: protocol,
  server: server,
  port: port,
  password: password,
  uuid: uuid,
  cipher: cipher,
  security: security,
  tls: tls,
  serverName: serverName,
  webSocket: webSocket,
  webSocketPath: webSocketPath,
  webSocketHost: webSocketHost,
  vision: vision,
);

String _b64(String value) => base64.encode(utf8.encode(value));

void main() {
  group('validate', () {
    test('accepts each supported protocol in its valid shape', () {
      for (final profile in [
        _profile(protocol: 'ss', password: 'pw', tls: false, uuid: ''),
        _profile(protocol: 'trojan', password: 'pw', uuid: ''),
        _profile(vision: true),
        _profile(tls: false),
        _profile(
          protocol: 'vmess',
          webSocket: true,
          security: 'chacha20-poly1305',
        ),
      ]) {
        expect(profile.validate, returnsNormally, reason: profile.protocol);
      }
    });

    test('rejects combinations the engine cannot run', () {
      final invalid = {
        'ss over TLS': _profile(protocol: 'ss', password: 'pw'),
        'ss without password': _profile(protocol: 'ss', tls: false),
        'ss stream cipher': _profile(
          protocol: 'ss',
          password: 'pw',
          tls: false,
          cipher: 'rc4-md5',
        ),
        'trojan without TLS': _profile(
          protocol: 'trojan',
          password: 'pw',
          tls: false,
        ),
        'vision without TLS': _profile(tls: false, vision: true),
        'vision over WebSocket': _profile(vision: true, webSocket: true),
        'vision on VMess': _profile(protocol: 'vmess', vision: true),
        'vmess legacy cipher': _profile(protocol: 'vmess', security: 'none'),
        'malformed UUID': _profile(uuid: 'not-a-uuid'),
        'unknown protocol': _profile(protocol: 'hysteria2'),
        'port zero': _profile(port: 0),
        'port too large': _profile(port: 65536),
        'host with a scheme': _profile(server: 'https://proxy.example'),
        'host with a space': _profile(server: 'proxy example'),
        'bracketed IPv6 server': _profile(server: '[2001:db8::1]'),
        'invalid SNI': _profile(serverName: 'bad_sni!'),
        'path without slash': _profile(webSocket: true, webSocketPath: 'ws'),
        'path with a space': _profile(webSocket: true, webSocketPath: '/a b'),
        'path too long': _profile(
          webSocket: true,
          webSocketPath: '/${'a' * 512}',
        ),
        'host header with a path': _profile(
          webSocket: true,
          webSocketHost: 'cdn.example/x',
        ),
        'unbracketed IPv6 host header': _profile(
          webSocket: true,
          webSocketHost: '2001:db8::1',
        ),
      };
      for (final MapEntry(key: reason, value: profile) in invalid.entries) {
        expect(profile.validate, throwsFormatException, reason: reason);
      }
    });

    test('accepts IPv6 servers and bracketed IPv6 host headers', () {
      expect(
        _profile(
          server: '2001:db8::1',
          webSocket: true,
          webSocketHost: '[2001:db8::1]:8443',
        ).validate,
        returnsNormally,
      );
    });
  });

  group('leafConfig', () {
    test('layers TLS, WebSocket and the protocol, wire first', () {
      final config = _profile(
        protocol: 'vmess',
        serverName: 'sni.example',
        webSocket: true,
        webSocketPath: '/ray?ed=2048',
      ).leafConfig;
      final outbounds = (config['outbounds'] as List)
          .cast<Map<String, dynamic>>();
      expect(config.keys, ['outbounds']);
      expect(outbounds.first, {
        'tag': 'proxy',
        'protocol': 'chain',
        'settings': {
          'actors': ['tls', 'ws', 'protocol'],
        },
      });
      expect(outbounds[1]['settings'], {
        'serverName': 'sni.example',
        'alpn': ['http/1.1'],
        'insecure': false,
      });
      expect(outbounds[2]['settings'], {
        'path': '/ray?ed=2048',
        'headers': {'Host': 'sni.example'},
      });
      expect(outbounds[3], {
        'tag': 'protocol',
        'protocol': 'vmess',
        'settings': {
          'address': 'proxy.example',
          'port': 443,
          'uuid': _uuid,
          'security': 'aes-128-gcm',
        },
      });
    });

    test('always sends an explicit WebSocket Host, bracketing IPv6', () {
      final config = _profile(
        server: '2001:db8::1',
        tls: false,
        webSocket: true,
      ).leafConfig;
      final ws = (config['outbounds'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((outbound) => outbound['tag'] == 'ws');
      expect(ws['settings']['headers'], {'Host': '[2001:db8::1]'});
    });

    test('maps Shadowsocks and VLESS Vision settings exactly', () {
      final ss =
          (_profile(
                    protocol: 'ss',
                    password: 'pw',
                    tls: false,
                    cipher: 'aes-256-gcm',
                  ).leafConfig['outbounds']
                  as List)
              .last;
      expect(ss['protocol'], 'shadowsocks');
      expect(ss['settings'], {
        'address': 'proxy.example',
        'port': 443,
        'method': 'aes-256-gcm',
        'password': 'pw',
      });

      final vless =
          (_profile(vision: true).leafConfig['outbounds'] as List).last;
      expect(vless['settings']['flow'], 'xtls-rprx-vision');
      final tls = (_profile(vision: true).leafConfig['outbounds'] as List)[1];
      // Without an explicit SNI the server name is verified.
      expect(tls['settings']['serverName'], 'proxy.example');
    });

    test('refuses to build a configuration for an invalid profile', () {
      expect(
        () => _profile(tls: false, vision: true).leafConfig,
        throwsFormatException,
      );
    });
  });

  group('fromUrl', () {
    test('parses SIP002 Shadowsocks links in both userinfo forms', () {
      final encoded = LeafProxyProfile.fromUrl(
        'ss://${_b64('aes-128-gcm:p@ss:word')}@203.0.113.5:8388#Home%20SS',
      )!;
      expect(encoded.protocol, 'ss');
      expect(encoded.cipher, 'aes-128-gcm');
      expect(encoded.password, 'p@ss:word');
      expect(encoded.server, '203.0.113.5');
      expect(encoded.port, 8388);
      expect(encoded.name, 'Home SS');

      final plain = LeafProxyProfile.fromUrl(
        'ss://chacha20-poly1305:secret%2Fvalue@ss.example:443',
      )!;
      expect(plain.cipher, 'chacha20-ietf-poly1305');
      expect(plain.password, 'secret/value');
    });

    test('parses legacy whole-body base64 Shadowsocks links', () {
      final profile = LeafProxyProfile.fromUrl(
        'ss://${_b64('aes-256-gcm:pw@[2001:db8::2]:8443')}#Legacy',
      )!;
      expect(profile.server, '2001:db8::2');
      expect(profile.port, 8443);
      expect(profile.cipher, 'aes-256-gcm');
      expect(profile.name, 'Legacy');
    });

    test('parses Trojan with its default TLS and a WebSocket transport', () {
      final profile = LeafProxyProfile.fromUrl(
        'trojan://pa%40ss@trojan.example:443?sni=front.example&type=ws'
        '&path=%2Fws&host=cdn.example#T',
      )!;
      expect(profile.password, 'pa@ss');
      expect(profile.tls, isTrue);
      expect(profile.serverName, 'front.example');
      expect(profile.webSocket, isTrue);
      expect(profile.webSocketPath, '/ws');
      expect(profile.webSocketHost, 'cdn.example');
    });

    test('parses VLESS Vision and plain VLESS', () {
      final vision = LeafProxyProfile.fromUrl(
        'vless://$_uuid@vless.example:443?security=tls&flow=xtls-rprx-vision'
        '&encryption=none&type=tcp&sni=sni.example',
      )!;
      expect(vision.vision, isTrue);
      expect(vision.tls, isTrue);
      expect(vision.protocolLabel, 'VLESS Vision');

      final plain = LeafProxyProfile.fromUrl('vless://$_uuid@1.2.3.4:80')!;
      expect(plain.tls, isFalse);
      expect(plain.vision, isFalse);
    });

    test('parses VMess v2 base64 JSON', () {
      final link =
          'vmess://${_b64(jsonEncode({'v': '2', 'ps': 'VM', 'add': 'vmess.example', 'port': '8443', 'id': _uuid, 'aid': '0', 'scy': 'auto', 'net': 'ws', 'type': 'none', 'host': 'cdn.example', 'path': '/v', 'tls': 'tls', 'sni': 'sni.example'}))}';
      final profile = LeafProxyProfile.fromUrl(link)!;
      expect(profile.port, 8443);
      expect(profile.security, 'aes-128-gcm');
      expect(profile.webSocket, isTrue);
      expect(profile.webSocketHost, 'cdn.example');
      expect(profile.tls, isTrue);
      expect(profile.name, 'VM');
    });

    test('rejects what the engine cannot honour exactly', () {
      final rejected = [
        'vless://$_uuid@h.example:443?security=reality&pbk=x&sid=y',
        'vless://$_uuid@h.example:443?security=tls&type=grpc',
        'vless://$_uuid@h.example:443?security=tls&encryption=aes',
        'vless://$_uuid@h.example:443?security=tls&flow=xtls-rprx-direct',
        'vless://$_uuid@h.example:443?security=tls&type=tcp&headerType=http',
        'trojan://pw@h.example:443?allowInsecure=1',
        'trojan://pw@h.example:443?security=none',
        'ss://${_b64('aes-128-gcm:pw')}@h.example:8388?plugin=obfs-local',
        'ss://${_b64('rc4-md5:pw')}@h.example:8388',
        'vmess://${_b64(jsonEncode({'add': 'h.example', 'port': '1', 'id': _uuid, 'aid': '64'}))}',
        'vmess://${_b64(jsonEncode({'add': 'h.example', 'port': '1', 'id': _uuid, 'net': 'kcp'}))}',
        'vmess://not-base64!',
        'hysteria2://pw@h.example:443',
        'https://t.me/proxy?server=a&port=1&secret=b',
        '',
      ];
      for (final link in rejected) {
        expect(LeafProxyProfile.fromUrl(link), isNull, reason: link);
      }
    });
  });

  test('serializes losslessly and validates on read', () {
    final profile = _profile(
      protocol: 'trojan',
      password: 'pw',
      webSocket: true,
      webSocketPath: '/t',
    );
    final restored = LeafProxyProfile.fromJson(
      jsonDecode(jsonEncode(profile.toJson())) as Map<String, dynamic>,
    );
    expect(restored.toJson(), profile.toJson());
    expect(
      () => LeafProxyProfile.fromJson({...profile.toJson(), 'tls': false}),
      throwsFormatException,
    );
  });

  test('sameSettings ignores only the id and display name', () {
    final a = _profile();
    final b = LeafProxyProfile.fromJson({
      ...a.toJson(),
      'id': 99,
      'name': 'Renamed',
    });
    expect(a.sameSettings(b), isTrue);
    expect(a.sameSettings(_profile(port: 8443)), isFalse);
  });
}
