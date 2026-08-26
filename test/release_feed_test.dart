import 'dart:convert';
import 'dart:ffi' show Abi;

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/update/release_feed.dart';

/// A well-formed digest, spelled out because a default value has to be const.
const _digest =
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

String _releaseJson(
  List<Map<String, Object?>> assets, {
  String tag = 'v1.3.0',
}) => jsonEncode({'tag_name': tag, 'assets': assets});

Map<String, Object?> _asset(
  String name, {
  int size = 1024,
  Object? digest = _digest,
}) => {
  'name': name,
  'browser_download_url': 'https://example.invalid/$name',
  'size': size,
  'digest': digest,
};

void main() {
  group('parsing', () {
    test('reads the tag without its leading v', () {
      expect(parseReleaseInfo(_releaseJson(const []))!.version, '1.3.0');
    });

    test('keeps the name, url, size, and digest of each asset', () {
      final release = parseReleaseInfo(
        _releaseJson([_asset('mithka-1.3.0-linux-x64.tar.gz', size: 47)]),
      )!;
      final asset = release.assets.single;
      expect(asset.name, 'mithka-1.3.0-linux-x64.tar.gz');
      expect(asset.url, endsWith('mithka-1.3.0-linux-x64.tar.gz'));
      expect(asset.size, 47);
      expect(asset.sha256, 'a' * 64);
    });

    test('normalizes an uppercase digest', () {
      final release = parseReleaseInfo(
        _releaseJson([_asset('a.zip', digest: 'sha256:${'AB' * 32}')]),
      )!;
      expect(release.assets.single.sha256, 'ab' * 32);
    });

    for (final digest in <Object?>[
      null,
      'md5:${'a' * 32}',
      'sha256:not-hex',
      'sha256:${'a' * 63}',
    ]) {
      test('treats $digest as no digest at all', () {
        final release = parseReleaseInfo(
          _releaseJson([_asset('a.zip', digest: digest)]),
        )!;
        expect(
          release.assets.single.sha256,
          isNull,
          reason: 'an unverifiable asset must never be installed',
        );
      });
    }

    test('drops an asset with no download url', () {
      final release = parseReleaseInfo(
        _releaseJson([
          {'name': 'a.zip', 'browser_download_url': '', 'size': 1},
        ]),
      )!;
      expect(release.assets, isEmpty);
    });

    test('a document without a tag is not a release', () {
      expect(parseReleaseInfo('{"assets": []}'), isNull);
      expect(parseReleaseInfo('[]'), isNull);
    });
  });

  group('asset selection', () {
    final release = parseReleaseInfo(
      _releaseJson([
        _asset('mithka-1.3.0-arm64-v8a.apk'),
        _asset('mithka-1.3.0-linux-arm64.tar.gz'),
        _asset('mithka-1.3.0-linux-x64.tar.gz'),
        _asset('mithka-1.3.0-macos-universal.zip'),
        _asset('mithka-1.3.0-windows-arm64.zip'),
        _asset('mithka-1.3.0-windows-x64.zip'),
      ]),
    )!;

    test('x64 and arm64 names do not match each other', () {
      // "linux-x64.tar.gz" must not be satisfied by the arm64 package, and the
      // reverse must hold too, or a machine gets the wrong architecture.
      expect(
        release.assetEndingWith('linux-x64.tar.gz')!.name,
        'mithka-1.3.0-linux-x64.tar.gz',
      );
      expect(
        release.assetEndingWith('linux-arm64.tar.gz')!.name,
        'mithka-1.3.0-linux-arm64.tar.gz',
      );
      expect(
        release.assetEndingWith('windows-arm64.zip')!.name,
        'mithka-1.3.0-windows-arm64.zip',
      );
      expect(
        release.assetEndingWith('windows-x64.zip')!.name,
        'mithka-1.3.0-windows-x64.zip',
      );
    });

    test('an architecture with no package returns nothing', () {
      expect(release.assetEndingWith('linux-riscv64.tar.gz'), isNull);
    });
  });

  group('package suffix', () {
    test('every published desktop architecture maps to its package', () {
      expect(desktopPackageSuffix(Abi.linuxX64), 'linux-x64.tar.gz');
      expect(desktopPackageSuffix(Abi.linuxArm64), 'linux-arm64.tar.gz');
      expect(desktopPackageSuffix(Abi.windowsX64), 'windows-x64.zip');
      expect(desktopPackageSuffix(Abi.windowsArm64), 'windows-arm64.zip');
    });

    test('macOS and mobile update through their own channels', () {
      for (final abi in [
        Abi.macosArm64,
        Abi.macosX64,
        Abi.androidArm64,
        Abi.iosArm64,
        Abi.linuxRiscv64,
      ]) {
        expect(desktopPackageSuffix(abi), isNull, reason: '$abi');
      }
    });
  });

  group('version comparison', () {
    test('orders the X.Y.Z triple', () {
      expect(compareReleaseVersions('1.3.0', '1.2.9'), greaterThan(0));
      expect(compareReleaseVersions('1.2.9', '1.3.0'), lessThan(0));
      expect(compareReleaseVersions('1.3.0', '1.3.0'), 0);
      expect(compareReleaseVersions('1.10.0', '1.9.0'), greaterThan(0));
    });

    test('ignores a build or pre-release suffix', () {
      expect(compareReleaseVersions('1.3.0', '1.3.0+285'), 0);
      expect(compareReleaseVersions('1.3.0', '1.3.0-nightly.20260825'), 0);
    });

    test('treats a missing component as zero', () {
      expect(compareReleaseVersions('1.3', '1.3.0'), 0);
      expect(compareReleaseVersions('2', '1.9.9'), greaterThan(0));
    });
  });
}
