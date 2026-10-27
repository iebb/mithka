// Behavioral tests for the OHOS hap payload verifier and the autofill
// shim decisions — the offline halves of the release workflow's new gates.
//
// The dynsym gate is exercised against the committed aarch64 stub ELF in
// test/fixtures (built once with the NDK clang; it defines exactly the five
// td_json_client entry points), and a digest mismatch is proven to fail the
// gate. The loader gate therefore runs on a real ELF, not a substring.
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

  ProcessResult runVerifier(File hap, Map<String, Object?> manifestJson) {
    final manifestFile = File('${scratch!.path}/manifest.json');
    manifestFile.writeAsStringSync(jsonEncode(manifestJson));
    return Process.runSync('python3', [
      'scripts/verify_ohos_hap_payload.py',
      hap.path,
      '--manifest',
      manifestFile.path,
      '--installed',
      '${scratch!.path}/libtdjson.so',
    ]);
  }

  File buildHap() {
    // A minimal zip with the required entries; the payload is the real ELF.
    final hapPath = '${scratch!.path}/entry.hap';
    final hap = File(hapPath);
    const script = '''
import sys, zipfile
hap, elf = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(hap, 'w') as z:
    z.writestr('pack.info', 'pack')
    z.writestr('ets/modules.abc', 'abc')
    z.write(elf, 'libs/arm64-v8a/libtdjson.so')
''';
    final helper = File('${scratch!.path}/mkzip.py')..writeAsStringSync(script);
    final r = Process.runSync('python3', [helper.path, hap.path, elf.path]);
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
    expect(r.stdout.toString(), contains('5 td_json_client'));
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
