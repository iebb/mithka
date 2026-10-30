// Behavioral tests for the OHOS hap payload verifier and the autofill
// shim decisions — the offline halves of the release workflow's new gates.
//
// The dynsym gate is exercised against the committed aarch64 stub ELFs in
// test/fixtures: libtdjson_stub.so defines the four modern entry points the
// Dart client binds (plus legacy aliases), while
// libtdjson_stub_legacy_only.so exports only the legacy td_json_client_*
// set and must fail the gate. A digest mismatch is also proven to fail.
// The loader gate therefore runs on real ELF structure, not a substring.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = {
    'release_tag': 'tdjson-ohos-test',
    'assets': {
      'tdjson-ohos-arm64.zip': {
        'release_tag': 'tdjson-ohos-test-v2',
        'members': {'arm64-v8a/libtdjson.so': <String, Object?>{}},
      },
    },
  };
  // Filled per test with the real library bytes.
  Map<String, Object?> member(String sha, int size) => {
    'sha256': sha,
    'size': size,
  };

  Directory? scratch;
  late File elf;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('hap_verify_test');
    elf = File(
      'test/fixtures/libtdjson_stub.so',
    ).copySync('${scratch!.path}/libtdjson.so');
  });

  tearDown(() => scratch?.deleteSync(recursive: true));

  ProcessResult runVerifier(
    File hap,
    Map<String, Object?> manifestJson, {
    File? installedOverride,
  }) {
    final manifestFile = File('${scratch!.path}/manifest.json');
    manifestFile.writeAsStringSync(jsonEncode(manifestJson));
    return Process.runSync('python3', [
      'scripts/verify_ohos_hap_payload.py',
      hap.path,
      '--manifest',
      manifestFile.path,
      '--installed',
      (installedOverride ?? elf).path,
    ]);
  }

  File buildHap({File? elfOverride}) {
    // A minimal zip with the required entries; the payload is a real ELF.
    final hapPath = '${scratch!.path}/entry.hap';
    final hap = File(hapPath);
    final payload = elfOverride ?? elf;
    const script = '''
import sys, zipfile
hap, elf = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(hap, 'w') as z:
    z.writestr('pack.info', 'pack')
    z.writestr('ets/modules.abc', 'abc')
    z.write(elf, 'libs/arm64-v8a/libtdjson.so')
''';
    final helper = File('${scratch!.path}/mkzip.py')..writeAsStringSync(script);
    final r = Process.runSync('python3', [helper.path, hap.path, payload.path]);
    expect(r.exitCode, 0, reason: r.stderr.toString());
    return hap;
  }

  test('a hap carrying the real pinned arm64 ELF verifies', () {
    final hap = buildHap();
    final bytes = elf.readAsBytesSync();
    final ok = manifest;
    (ok['assets']! as Map<String, Object?>)['tdjson-ohos-arm64.zip']
        as Map<String, Object?>;
    final asset =
        (ok['assets']! as Map<String, Object?>)['tdjson-ohos-arm64.zip']!
            as Map<String, Object?>;
    final digest = Process.runSync('python3', [
      '-c',
      'import hashlib,sys;'
          "print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())",
      elf.path,
    ]).stdout.toString().trim();
    asset['members'] = {'arm64-v8a/libtdjson.so': member(digest, bytes.length)};
    final r = runVerifier(hap, ok);
    expect(r.exitCode, 0, reason: r.stderr.toString());
    expect(r.stdout.toString(), contains('dynsym defines'));
    expect(r.stdout.toString(), contains('4 modern tdjson'));
  });

  test('a legacy-only tdjson stub fails the loader gate', () {
    // The Dart client binds td_create_client_id/td_send/td_receive/
    // td_execute; a library exporting only the legacy td_json_client_*
    // aliases is not loadable by this client and must fail the gate.
    final legacyElf = File('test/fixtures/libtdjson_stub_legacy_only.so');
    final hap = buildHap(elfOverride: legacyElf);
    final bytes = legacyElf.readAsBytesSync();
    final ok = manifest;
    final asset =
        (ok['assets']! as Map<String, Object?>)['tdjson-ohos-arm64.zip']!
            as Map<String, Object?>;
    final digest = Process.runSync('python3', [
      '-c',
      'import hashlib,sys;'
          "print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())",
      legacyElf.path,
    ]).stdout.toString().trim();
    asset['members'] = {'arm64-v8a/libtdjson.so': member(digest, bytes.length)};
    final r = runVerifier(hap, ok, installedOverride: legacyElf);
    expect(r.exitCode, isNot(0));
    expect(
      r.stderr.toString(),
      contains('does not define the td_create_client_id entry point'),
    );
  });

  test('a digest mismatch fails the gate', () {
    final hap = buildHap();
    final bytes = elf.readAsBytesSync();
    final bad = manifest;
    final asset =
        (bad['assets']! as Map<String, Object?>)['tdjson-ohos-arm64.zip']!
            as Map<String, Object?>;
    asset['members'] = {
      'arm64-v8a/libtdjson.so': member('0' * 64, bytes.length),
    };
    final r = runVerifier(hap, bad);
    expect(r.exitCode, isNot(0));
    expect(r.stderr.toString(), contains('pinned manifest digest'));
  });
}
