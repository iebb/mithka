//
//  update_checker.dart
//
//  Android-only in-app update check against the project's GitHub Releases. On
//  launch it asks the latest release for its tag (semver) and assets, compares
//  the tag to the installed version, and — if newer AND there's an APK asset for
//  this device's ABI — offers to download it in the browser. Repo is public, so
//  the releases API needs no auth. Fails silently (offline / rate-limited).
//

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../components/confirm_dialog.dart';

class UpdateChecker {
  UpdateChecker._();

  static const _channel = MethodChannel('mithka/app_info');
  static const _owner = 'iebb';
  static const _repo = 'mithka';
  static bool _checkedThisLaunch = false;

  /// Checks once per launch (Android only) and prompts if a newer same-ABI APK
  /// exists. Safe to call from any screen's first frame; no-op otherwise.
  static Future<void> maybePrompt(BuildContext context) async {
    if (!Platform.isAndroid || _checkedThisLaunch) return;
    _checkedThisLaunch = true;
    try {
      final info = await _channel.invokeMethod<Map<dynamic, dynamic>>('info');
      final current = (info?['version'] as String?) ?? '';
      final abis = ((info?['abis'] as List?) ?? const [])
          .whereType<String>()
          .toList();
      if (current.isEmpty || abis.isEmpty) return;

      final release = await _fetchLatest();
      if (release == null) return;
      final remote = release.version;
      if (_compareSemver(remote, current) <= 0) return; // not newer

      // Pick the asset for this device's preferred ABI (first match wins).
      String? url;
      for (final abi in abis) {
        for (final a in release.assets) {
          if (a.name.endsWith('.apk') && a.name.contains(abi)) {
            url = a.url;
            break;
          }
        }
        if (url != null) break;
      }
      if (url == null) return; // no APK for this architecture

      if (!context.mounted) return;
      final ok = await confirmDialog(
        context,
        title: AppStrings.t(AppStringKeys.updateNewVersionFound),
        message: AppStrings.t(AppStringKeys.updateVersionPrompt, {
          'value1': current,
          'value2': remote,
        }),
        confirmText: AppStrings.t(AppStringKeys.updateAction),
        cancelText: AppStrings.t(AppStringKeys.updateLater),
      );
      if (ok && context.mounted) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // Offline, rate-limited, or no release yet — silently skip.
    }
  }

  static Future<_Release?> _fetchLatest() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(
        Uri.parse(
          'https://api.github.com/repos/$_owner/$_repo/releases/latest',
        ),
      );
      // GitHub rejects requests without a User-Agent.
      req.headers.set(HttpHeaders.userAgentHeader, 'mithka-update-checker');
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final resp = await req.close().timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tag = json['tag_name'] as String?;
      if (tag == null) return null;
      final assets = ((json['assets'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (a) => _Asset(
              (a['name'] as String?) ?? '',
              (a['browser_download_url'] as String?) ?? '',
            ),
          )
          .where((a) => a.url.isNotEmpty)
          .toList();
      return _Release(tag.replaceFirst(RegExp(r'^v'), ''), assets);
    } finally {
      client.close(force: true);
    }
  }

  /// >0 if a>b, <0 if a<b, 0 if equal — compares the X.Y.Z triple.
  static int _compareSemver(String a, String b) {
    final pa = _triple(a);
    final pb = _triple(b);
    for (var i = 0; i < 3; i++) {
      if (pa[i] != pb[i]) return pa[i] - pb[i];
    }
    return 0;
  }

  static List<int> _triple(String v) {
    // Strip any "+build" / pre-release suffix, then parse up to 3 numbers.
    final core = v.split(RegExp(r'[+\-]')).first;
    final nums = core
        .split('.')
        .map((s) => int.tryParse(s.trim()) ?? 0)
        .toList();
    while (nums.length < 3) {
      nums.add(0);
    }
    return nums.sublist(0, 3);
  }
}

class _Release {
  _Release(this.version, this.assets);
  final String version; // semver without leading "v"
  final List<_Asset> assets;
}

class _Asset {
  _Asset(this.name, this.url);
  final String name;
  final String url;
}
