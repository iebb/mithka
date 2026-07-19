import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class ReviewLoginCodeService {
  ReviewLoginCodeService({http.Client? client})
    : _client = client ?? http.Client();

  static const _relay = String.fromEnvironment('REVIEW_RELAY');
  static const _key = 'mithka-review-relay';
  static const _defaultRelayUrlBytes = <int>[
    5,
    29,
    0,
    24,
    24,
    91,
    2,
    93,
    8,
    31,
    29,
    13,
    28,
    76,
    95,
    23,
    9,
    23,
    16,
    8,
    30,
    89,
    4,
    4,
    6,
    68,
    28,
    72,
    21,
    6,
    1,
    18,
    3,
    28,
    0,
    7,
    14,
    18,
    2,
    8,
    4,
    24,
    24,
    79,
    90,
    29,
    23,
    29,
    12,
    23,
    4,
    3,
    22,
    0,
    26,
  ];
  static const _tokenBytes = <int>[
    60,
    15,
    30,
    36,
    38,
    7,
    28,
    61,
    40,
    34,
    14,
    55,
    24,
    104,
    16,
    83,
    91,
    22,
    12,
    55,
    49,
    62,
    59,
    62,
    45,
    120,
    42,
    44,
    36,
    56,
    22,
    62,
    106,
    71,
    84,
    39,
    21,
    24,
    84,
    10,
    2,
    95,
    34,
    92,
  ];

  final http.Client _client;

  static _ReviewRelayConfig? get _config => _ReviewRelayConfig.parse(
    _relay.isEmpty ? _decode(_defaultRelayUrlBytes) : _relay,
  );

  static bool isReviewPhone(String phone) {
    final config = _config;
    if (config == null) return false;
    final phoneHash = config.phoneHash;
    if (phoneHash == null) return false;
    return _sha256Hex(_digits(phone)) == phoneHash;
  }

  static bool isMockSessionPhone(String phone) {
    final config = _config;
    if (config == null) return false;
    return _digits(phone).startsWith('99999');
  }

  Future<String?> fetchCode() async {
    final config = _config;
    if (config == null) return null;

    final response = await _client
        .get(
          Uri.parse('${config.relayUrl}/code'),
          headers: {
            'authorization': 'Bearer ${_decode(_tokenBytes)}',
            'cache-control': 'no-store',
          },
        )
        .timeout(const Duration(seconds: 6));

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw StateError('review code relay returned ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    final code = decoded['code'];
    if (code is! String || !RegExp(r'^\d{3,8}$').hasMatch(code)) return null;
    return code;
  }

  Future<String?> fetchSessionString({
    required String phone,
    required String otp,
  }) async {
    final config = _config;
    if (config == null) return null;

    final response = await _client
        .post(
          Uri.parse('${config.relayUrl}/session'),
          headers: {
            'authorization': 'Bearer ${_decode(_tokenBytes)}',
            'cache-control': 'no-store',
            'content-type': 'application/json; charset=utf-8',
          },
          body: jsonEncode({'phone_number': _e164(phone), 'otp': otp.trim()}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 403 || response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw StateError('review session relay returned ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    final sessionString = decoded['session_string'];
    if (sessionString is! String || sessionString.trim().isEmpty) return null;
    return sessionString.trim();
  }

  static String _sha256Hex(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  static String _decode(List<int> bytes) {
    final key = utf8.encode(_key);
    final decoded = <int>[
      for (var i = 0; i < bytes.length; i += 1) bytes[i] ^ key[i % key.length],
    ];
    return utf8.decode(decoded);
  }

  static String _digits(String value) => value.replaceAll(RegExp(r'\D'), '');

  static String _e164(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('+')) return trimmed;
    final digits = _digits(trimmed);
    return digits.isEmpty ? trimmed : '+$digits';
  }
}

class _ReviewRelayConfig {
  const _ReviewRelayConfig({required this.relayUrl, this.phoneHash});

  final String relayUrl;
  final String? phoneHash;

  static _ReviewRelayConfig? parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final separator = trimmed.lastIndexOf('|');
    final relayUrl = separator <= 0
        ? trimmed
        : trimmed.substring(0, separator).trim();
    if (!relayUrl.startsWith('https://')) return null;

    String? phoneHash;
    if (separator > 0) {
      if (separator == trimmed.length - 1) return null;
      phoneHash = trimmed.substring(separator + 1).trim().toLowerCase();
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(phoneHash)) return null;
    }

    return _ReviewRelayConfig(
      relayUrl: relayUrl.replaceFirst(RegExp(r'/+$'), ''),
      phoneHash: phoneHash,
    );
  }
}
