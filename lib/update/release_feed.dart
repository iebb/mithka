//
//  release_feed.dart
//
//  The project's GitHub Releases feed, shared by the Android APK prompt and the
//  desktop one-click updater. The repo is public, so the API needs no auth.
//  Every caller treats a failed request as "nothing to offer" rather than an
//  error, because the checks run unasked on launch.
//

import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

/// GitHub rejects requests without a User-Agent.
const releaseFeedUserAgent = 'mithka-update-checker';

const _owner = 'TiaraBasori';
const _repo = 'MithkaX';

/// Where a user is sent when an in-place update is not something this install
/// can do for them.
const releasesPageUrl = 'https://github.com/$_owner/$_repo/releases';

/// One downloadable file attached to a release.
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
    required this.sha256,
  });

  final String name;
  final String url;

  /// Bytes GitHub reports for the asset, or 0 when it is unknown.
  final int size;

  /// Lowercase hex SHA-256 GitHub publishes for the asset, or null on releases
  /// that predate the digest field. The desktop updater refuses to install a
  /// package it cannot verify, so this is what makes a release installable.
  final String? sha256;
}

class ReleaseInfo {
  const ReleaseInfo({required this.version, required this.assets});

  /// Semver without the leading `v`, taken from the release tag.
  final String version;
  final List<ReleaseAsset> assets;

  /// The single asset whose name ends with [suffix], or null when this release
  /// does not carry a package for the caller's platform.
  ReleaseAsset? assetEndingWith(String suffix) {
    for (final asset in assets) {
      if (asset.name.endsWith(suffix)) return asset;
    }
    return null;
  }
}

/// The tail of the desktop package this build can install over itself.
///
/// Null where an in-place update does not apply: macOS ships through its own
/// signed channel, and no other desktop architecture is published.
String? desktopPackageSuffix([Abi? abi, bool? appImage]) =>
    switch (abi ?? Abi.current()) {
      Abi.linuxX64 =>
        (appImage ?? (Platform.environment['APPIMAGE'] ?? '').isNotEmpty)
            ? 'linux-x64.AppImage'
            : 'linux-x64.tar.gz',
      Abi.linuxArm64 =>
        (appImage ?? (Platform.environment['APPIMAGE'] ?? '').isNotEmpty)
            ? 'linux-arm64.AppImage'
            : 'linux-arm64.tar.gz',
      Abi.windowsX64 => 'windows-x64.zip',
      Abi.windowsArm64 => 'windows-arm64.zip',
      _ => null,
    };

/// The newest release, or null when the request fails or is malformed.
///
/// MithkaX ships every build as a pre-release, so the feed walks the release
/// list and takes the first (newest) tag instead of `releases/latest`, which
/// only answers stable releases and would never see one here.
Future<ReleaseInfo?> fetchLatestRelease({
  String owner = _owner,
  String repo = _repo,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.getUrl(
      Uri.parse(
        'https://api.github.com/repos/$owner/$repo/releases?per_page=10',
      ),
    );
    request.headers.set(HttpHeaders.userAgentHeader, releaseFeedUserAgent);
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/vnd.github+json',
    );
    final response = await request.close().timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final body = await response.transform(utf8.decoder).join();
    return parseReleaseList(body);
  } finally {
    client.close(force: true);
  }
}

/// Reads the release list and returns the first (newest) entry, or null when
/// the list is empty or malformed.
ReleaseInfo? parseReleaseList(String body) {
  final json = jsonDecode(body);
  if (json is! List || json.isEmpty) return null;
  ReleaseInfo? best;
  for (final entry in json.whereType<Map>()) {
    final tag = entry['tag_name'] as String?;
    if (tag == null) continue;
    final info = _parseOneRelease(entry, tag);
    if (info == null) continue;
    best ??= info;
  }
  return best;
}

/// Reads one release document, or null when the tag is missing.
ReleaseInfo? parseReleaseInfo(String body) {
  final json = jsonDecode(body);
  if (json is! Map<String, dynamic>) return null;
  final tag = json['tag_name'] as String?;
  if (tag == null) return null;
  return _parseOneRelease(json, tag);
}

ReleaseInfo? _parseOneRelease(Map json, String tag) {
  final assets = ((json['assets'] as List?) ?? const [])
      .whereType<Map>()
      .map(
        (asset) => ReleaseAsset(
          name: (asset['name'] as String?) ?? '',
          url: (asset['browser_download_url'] as String?) ?? '',
          size: (asset['size'] as num?)?.toInt() ?? 0,
          sha256: _hexDigest(asset['digest'] as String?),
        ),
      )
      .where((asset) => asset.url.isNotEmpty)
      .toList();
  return ReleaseInfo(
    version: tag.replaceFirst(RegExp(r'^v'), ''),
    assets: assets,
  );
}

/// GitHub reports digests as `sha256:<hex>`; anything else is treated as absent
/// so a caller that requires verification fails closed.
String? _hexDigest(String? digest) {
  const prefix = 'sha256:';
  if (digest == null || !digest.startsWith(prefix)) return null;
  final hex = digest.substring(prefix.length).toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hex)) return null;
  return hex;
}

/// >0 if a>b, <0 if a<b, 0 if equal — compares the X.Y.Z triple.
int compareReleaseVersions(String a, String b) {
  final pa = _triple(a);
  final pb = _triple(b);
  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i] - pb[i];
  }
  return 0;
}

List<int> _triple(String version) {
  // Strip any "+build" / pre-release suffix, then parse up to 3 numbers.
  final core = version.split(RegExp(r'[+\-]')).first;
  final numbers = core
      .split('.')
      .map((part) => int.tryParse(part.trim()) ?? 0)
      .toList();
  while (numbers.length < 3) {
    numbers.add(0);
  }
  return numbers.sublist(0, 3);
}
