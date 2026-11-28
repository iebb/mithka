import 'package:http/http.dart' as http;

import 'ai_http_client_stub.dart'
    if (dart.library.io) 'ai_http_client_io.dart'
    as impl;

/// Creates an HTTP client for AI provider requests.
///
/// When [bypassProxyForLocalNetworks] (or [shouldBypassProxyForLocalNetworks])
/// is enabled, requests to loopback and local-network hosts connect directly
/// (`DIRECT`) instead of routing through system or environment HTTP proxies.
http.Client createAiHttpClient({
  bool bypassProxyForLocalNetworks = true,
  bool Function()? shouldBypassProxyForLocalNetworks,
}) => impl.createAiHttpClient(
  bypassProxyForLocalNetworks: bypassProxyForLocalNetworks,
  shouldBypassProxyForLocalNetworks: shouldBypassProxyForLocalNetworks,
);

/// Resolves the HTTP proxy directive for an AI provider request [uri].
String findAiProxy(
  Uri uri, {
  bool bypassProxyForLocalNetworks = true,
  Map<String, String>? environment,
}) => impl.findAiProxy(
  uri,
  bypassProxyForLocalNetworks: bypassProxyForLocalNetworks,
  environment: environment,
);

/// Returns `true` if [host] refers to the local loopback interface
/// (`localhost`, `*.localhost`, `127.0.0.0/8`, `::1`, or IPv4-mapped loopback).
bool isAiLoopbackHost(String host) {
  final normalized = _normalizeHost(host);
  if (normalized.isEmpty) return false;
  if (normalized == 'localhost' || normalized.endsWith('.localhost')) {
    return true;
  }
  final ipv4 = _tryParseIpv4(normalized);
  if (ipv4 != null) return ipv4[0] == 127;
  final ipv6 = _tryParseIpv6(normalized);
  if (ipv6 != null) {
    if (_isIpv6Loopback(ipv6)) return true;
    final mapped = _unwrapIpv4MappedIpv6(ipv6);
    if (mapped != null) return mapped[0] == 127;
  }
  return false;
}

/// Returns `true` if [host] refers to loopback or a private/local network
/// address or hostname (`localhost`, `*.local`, `*.lan`, `*.home.arpa`,
/// `*.localdomain`, `*.internal`, RFC 1918, RFC 3927, RFC 6598, IPv6 ULA,
/// IPv6 link-local).
bool isLocalNetworkHost(String host) {
  final normalized = _normalizeHost(host);
  if (normalized.isEmpty) return false;
  if (isAiLoopbackHost(normalized)) return true;
  if (normalized.endsWith('.local') ||
      normalized.endsWith('.lan') ||
      normalized.endsWith('.home.arpa') ||
      normalized.endsWith('.localdomain') ||
      normalized.endsWith('.internal')) {
    return true;
  }
  final ipv4 = _tryParseIpv4(normalized);
  if (ipv4 != null) return _isLocalIpv4(ipv4);
  final ipv6 = _tryParseIpv6(normalized);
  if (ipv6 != null) {
    if (_isIpv6Loopback(ipv6)) return true;
    // Link-local fe80::/10
    if (ipv6[0] == 0xfe && (ipv6[1] & 0xc0) == 0x80) return true;
    // Unique local fc00::/7
    if ((ipv6[0] & 0xfe) == 0xfc) return true;
    final mapped = _unwrapIpv4MappedIpv6(ipv6);
    if (mapped != null) return _isLocalIpv4(mapped);
  }
  return false;
}

String _normalizeHost(String host) {
  var normalized = host.trim().toLowerCase();
  if (normalized.startsWith('[') && normalized.endsWith(']')) {
    normalized = normalized.substring(1, normalized.length - 1);
  }
  final zoneIndex = normalized.indexOf('%');
  if (zoneIndex >= 0) {
    normalized = normalized.substring(0, zoneIndex);
  }
  while (normalized.endsWith('.')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

List<int>? _tryParseIpv4(String host) {
  try {
    return Uri.parseIPv4Address(host);
  } on FormatException {
    return null;
  }
}

List<int>? _tryParseIpv6(String host) {
  if (!host.contains(':')) return null;
  try {
    return Uri.parseIPv6Address(host);
  } on FormatException {
    return null;
  }
}

bool _isIpv6Loopback(List<int> bytes) {
  for (var i = 0; i < 15; i++) {
    if (bytes[i] != 0) return false;
  }
  return bytes[15] == 1;
}

List<int>? _unwrapIpv4MappedIpv6(List<int> bytes) {
  for (var i = 0; i < 10; i++) {
    if (bytes[i] != 0) return null;
  }
  if (bytes[10] != 0xff || bytes[11] != 0xff) return null;
  return bytes.sublist(12, 16);
}

bool _isLocalIpv4(List<int> bytes) {
  final b0 = bytes[0];
  final b1 = bytes[1];
  // 127.0.0.0/8 loopback
  if (b0 == 127) return true;
  // 10.0.0.0/8 RFC 1918
  if (b0 == 10) return true;
  // 172.16.0.0/12 RFC 1918
  if (b0 == 172 && b1 >= 16 && b1 <= 31) return true;
  // 192.168.0.0/16 RFC 1918
  if (b0 == 192 && b1 == 168) return true;
  // 169.254.0.0/16 RFC 3927 link-local
  if (b0 == 169 && b1 == 254) return true;
  // 100.64.0.0/10 RFC 6598 shared / mesh (e.g. Tailscale)
  if (b0 == 100 && b1 >= 64 && b1 <= 127) return true;
  return false;
}
