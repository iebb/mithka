import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _expectedMembers = <String, Set<String>>{
  'tdjson-android-arm64-v8a.zip': {'arm64-v8a/libtdjson.so'},
  'tdjson-android-armeabi-v7a.zip': {'armeabi-v7a/libtdjson.so'},
  'tdjson-android-x86_64.zip': {'x86_64/libtdjson.so'},
  'tdjson-ios.xcframework.zip': {
    'tdjson.xcframework/Info.plist',
    'tdjson.xcframework/ios-arm64/tdjson.framework/Headers/tdjson.h',
    'tdjson.xcframework/ios-arm64/tdjson.framework/Info.plist',
    'tdjson.xcframework/ios-arm64/tdjson.framework/Modules/module.modulemap',
    'tdjson.xcframework/ios-arm64/tdjson.framework/tdjson',
    'tdjson.xcframework/ios-arm64-simulator/tdjson.framework/Headers/tdjson.h',
    'tdjson.xcframework/ios-arm64-simulator/tdjson.framework/Info.plist',
    'tdjson.xcframework/ios-arm64-simulator/tdjson.framework/Modules/module.modulemap',
    'tdjson.xcframework/ios-arm64-simulator/tdjson.framework/tdjson',
  },
  'tdjson-linux-x64.zip': {'libtdjson.so'},
  'tdjson-macos-universal.zip': {'libtdjson.dylib'},
  'tdjson-windows-x64.zip': {'tdjson.dll'},
};

const _linuxAsset = 'tdjson-linux-x64.zip';
const _linuxMember = 'libtdjson.so';
const _iosAsset = 'tdjson-ios.xcframework.zip';

void main() {
  late Directory temporaryDirectory;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'mithka_tdjson_installer_test.',
    );
  });

  tearDown(() {
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  test('installs a valid member and reuses the verified destination', () async {
    final fixture = _createFixture(temporaryDirectory);
    final destination = File.fromUri(
      temporaryDirectory.uri.resolve('installed/libtdjson.so'),
    );

    final firstResult = await _runInstaller(
      fixture,
      asset: _linuxAsset,
      destination: destination,
      member: _linuxMember,
    );

    expect(firstResult.exitCode, 0, reason: _processFailure(firstResult));
    expect(
      destination.readAsBytesSync(),
      fixture.payloads[_linuxAsset]![_linuxMember],
    );
    expect(firstResult.stdout, contains('Installed pinned tdjson'));

    fixture.archives[_linuxAsset]!.deleteSync();
    final secondResult = await _runInstaller(
      fixture,
      asset: _linuxAsset,
      destination: destination,
      member: _linuxMember,
    );

    expect(secondResult.exitCode, 0, reason: _processFailure(secondResult));
    expect(secondResult.stdout, contains('Verified pinned tdjson'));
    expect(
      destination.readAsBytesSync(),
      fixture.payloads[_linuxAsset]![_linuxMember],
    );
  });

  test(
    'a truncated archive preserves an existing member destination',
    () async {
      final fixture = _createFixture(temporaryDirectory);
      final destination = File.fromUri(
        temporaryDirectory.uri.resolve('installed/libtdjson.so'),
      )..createSync(recursive: true);
      const existingBytes = <int>[0x6f, 0x6c, 0x64];
      destination.writeAsBytesSync(existingBytes);

      final archive = fixture.archives[_linuxAsset]!;
      final completeArchive = archive.readAsBytesSync();
      archive.writeAsBytesSync(
        completeArchive.sublist(0, completeArchive.length ~/ 2),
        flush: true,
      );

      final result = await _runInstaller(
        fixture,
        asset: _linuxAsset,
        destination: destination,
        member: _linuxMember,
      );

      expect(result.exitCode, isNot(0), reason: _processFailure(result));
      expect(result.stderr, contains('size mismatch'));
      expect(destination.readAsBytesSync(), existingBytes);
    },
  );

  group('rejects archive members without replacing the destination', () {
    test('unsafe path', () async {
      final fixture = _createFixture(
        temporaryDirectory,
        extraMembers: {
          _linuxAsset: {
            '../escaped-libtdjson.so': utf8.encode('unsafe fixture member'),
          },
        },
      );
      final destination = File.fromUri(
        temporaryDirectory.uri.resolve('installed/libtdjson.so'),
      )..createSync(recursive: true);
      const existingBytes = <int>[0x73, 0x61, 0x66, 0x65];
      destination.writeAsBytesSync(existingBytes);

      final result = await _runInstaller(
        fixture,
        asset: _linuxAsset,
        destination: destination,
        member: _linuxMember,
      );

      expect(result.exitCode, isNot(0), reason: _processFailure(result));
      expect(result.stderr, contains('contains unsafe member'));
      expect(destination.readAsBytesSync(), existingBytes);
      expect(
        File.fromUri(
          temporaryDirectory.uri.resolve('escaped-libtdjson.so'),
        ).existsSync(),
        isFalse,
      );
    });

    test('unexpected file', () async {
      final fixture = _createFixture(
        temporaryDirectory,
        extraMembers: {
          _linuxAsset: {
            'unexpected-libtdjson.so': utf8.encode('unexpected fixture member'),
          },
        },
      );
      final destination = File.fromUri(
        temporaryDirectory.uri.resolve('installed/libtdjson.so'),
      )..createSync(recursive: true);
      const existingBytes = <int>[0x6b, 0x65, 0x65, 0x70];
      destination.writeAsBytesSync(existingBytes);

      final result = await _runInstaller(
        fixture,
        asset: _linuxAsset,
        destination: destination,
        member: _linuxMember,
      );

      expect(result.exitCode, isNot(0), reason: _processFailure(result));
      expect(result.stderr, contains('member mismatch'));
      expect(destination.readAsBytesSync(), existingBytes);
    });
  });

  test('tree validation failure preserves the existing destination', () async {
    final fixture = _createFixture(
      temporaryDirectory,
      memberPayloadOverrides: {
        _iosAsset: {
          'tdjson.xcframework/Info.plist': utf8.encode(
            'corrupted plist fixture',
          ),
        },
      },
    );
    final destination = Directory.fromUri(
      temporaryDirectory.uri.resolve('installed/tdjson.xcframework/'),
    )..createSync(recursive: true);
    final sentinel = File.fromUri(destination.uri.resolve('existing.txt'))
      ..writeAsStringSync('preserve this tree');

    final result = await _runInstaller(
      fixture,
      asset: _iosAsset,
      destination: destination,
    );

    expect(result.exitCode, isNot(0), reason: _processFailure(result));
    expect(
      result.stderr,
      anyOf(contains('size mismatch'), contains('SHA-256')),
    );
    expect(destination.existsSync(), isTrue);
    expect(sentinel.readAsStringSync(), 'preserve this tree');
    expect(destination.listSync(recursive: true).map((entry) => entry.path), [
      sentinel.path,
    ]);
  });

  test('recovers an interrupted tree swap before checking the cache', () async {
    final fixture = _createFixture(temporaryDirectory);
    final destination = Directory.fromUri(
      temporaryDirectory.uri.resolve('installed/tdjson.xcframework/'),
    );

    final installResult = await _runInstaller(
      fixture,
      asset: _iosAsset,
      destination: destination,
    );
    expect(installResult.exitCode, 0, reason: _processFailure(installResult));

    final backup = Directory.fromUri(
      destination.parent.uri.resolve(
        '.tdjson.xcframework.install-fixture-previous/',
      ),
    );
    destination.renameSync(backup.path);
    fixture.archives[_iosAsset]!.deleteSync();

    final recoveryResult = await _runInstaller(
      fixture,
      asset: _iosAsset,
      destination: destination,
    );

    expect(recoveryResult.exitCode, 0, reason: _processFailure(recoveryResult));
    expect(recoveryResult.stdout, contains('Verified pinned tdjson tree'));
    expect(destination.existsSync(), isTrue);
    expect(backup.existsSync(), isFalse);
  });
}

_Fixture _createFixture(
  Directory root, {
  Map<String, Map<String, List<int>>> memberPayloadOverrides = const {},
  Map<String, Map<String, List<int>>> extraMembers = const {},
}) {
  final archiveDirectory = Directory.fromUri(root.uri.resolve('archives/'))
    ..createSync(recursive: true);
  final manifestAssets = <String, Object?>{};
  final archives = <String, File>{};
  final payloads = <String, Map<String, List<int>>>{};

  for (final assetEntry in _expectedMembers.entries) {
    final canonicalPayloads = <String, List<int>>{
      for (final member in assetEntry.value)
        member: utf8.encode('fixture payload for ${assetEntry.key}:$member'),
    };
    final archivePayloads = <String, List<int>>{
      ...canonicalPayloads,
      ...?memberPayloadOverrides[assetEntry.key],
      ...?extraMembers[assetEntry.key],
    };
    final archive = Archive();
    for (final memberEntry in archivePayloads.entries) {
      archive.addFile(ArchiveFile.bytes(memberEntry.key, memberEntry.value));
    }
    final archiveBytes = ZipEncoder().encode(archive);
    final archiveFile = File.fromUri(
      archiveDirectory.uri.resolve(assetEntry.key),
    )..writeAsBytesSync(archiveBytes, flush: true);

    archives[assetEntry.key] = archiveFile;
    payloads[assetEntry.key] = canonicalPayloads;
    manifestAssets[assetEntry.key] = <String, Object?>{
      'sha256': sha256.convert(archiveBytes).toString(),
      'size': archiveBytes.length,
      'members': <String, Object?>{
        for (final memberEntry in canonicalPayloads.entries)
          memberEntry.key: <String, Object?>{
            'sha256': sha256.convert(memberEntry.value).toString(),
            'size': memberEntry.value.length,
          },
      },
    };
  }

  final manifest = File.fromUri(root.uri.resolve('manifest.json'))
    ..writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'schema_version': 2,
        'release_tag': 'test-v1',
        'tdlib_version': 'test',
        'upstream_repository': 'tdlib/td',
        'upstream_sha': '1111111111111111111111111111111111111111',
        'mithka_tdjson_sha': '2222222222222222222222222222222222222222',
        'patchset_sha256':
            '3333333333333333333333333333333333333333333333333333333333333333',
        'build_definition_sha256':
            '4444444444444444444444444444444444444444444444444444444444444444',
        'assets': manifestAssets,
      }),
    );

  return _Fixture(manifest: manifest, archives: archives, payloads: payloads);
}

Future<ProcessResult> _runInstaller(
  _Fixture fixture, {
  required String asset,
  required FileSystemEntity destination,
  String? member,
}) {
  return Process.run('python3', [
    'scripts/install-tdjson-artifact.py',
    asset,
    destination.path,
    if (member != null) ...['--member', member, '--mode', '0755'],
    '--manifest',
    fixture.manifest.path,
    '--archive',
    fixture.archives[asset]!.path,
  ], workingDirectory: Directory.current.path);
}

String _processFailure(ProcessResult result) =>
    'stdout:\n${result.stdout}\nstderr:\n${result.stderr}';

class _Fixture {
  const _Fixture({
    required this.manifest,
    required this.archives,
    required this.payloads,
  });

  final File manifest;
  final Map<String, File> archives;
  final Map<String, Map<String, List<int>>> payloads;
}
