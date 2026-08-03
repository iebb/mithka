import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Linux release installs the hotkey manager native dependency', () {
    final workflow = File('.github/workflows/release.yml').readAsStringSync();

    final linuxDependencies = RegExp(
      r"- name: Install Linux build dependencies[\s\S]*?"
      r"- name: Install macOS build dependencies",
    ).firstMatch(workflow);

    expect(linuxDependencies, isNotNull);
    expect(linuxDependencies!.group(0), contains('libkeybinder-3.0-dev'));
  });

  test('Android releases pin and hash-verify the exact TDLib binaries', () {
    const expectedHashes = <String>[
      'cc7f46072ed11631dbd3c09d8c0fb7c9b352ad07a64a80e3c088153aa65111b1',
      '472371dfe8aea93ccb6b20bc32d35f3d0b1f1c97b1f9d98a4279703dbba2a042',
      'd5615f73aad657ba9a40beca47fbc80504f87bddcf17d3d3471389b8de977b21',
    ];
    for (final path in const [
      '.github/workflows/release.yml',
      '.github/workflows/google-play.yml',
    ]) {
      final workflow = File(path).readAsStringSync();

      for (final hash in expectedHashes) {
        expect(workflow, contains(hash), reason: '$path must pin $hash');
      }
      expect(workflow, contains('key: jnilibs-v2-'));
      expect(
        workflow,
        isNot(
          matches(
            RegExp(
              r'path: android/app/src/main/jniLibs[^\n]*\n'
              r'\s+key: jnilibs-v2-[^\n]*\n\s+restore-keys:',
            ),
          ),
        ),
      );
      expect(
        workflow,
        contains(
          r'''printf '%s  %s\n' "$expected" "$library" | sha256sum --check --strict''',
        ),
      );
      expect(workflow, isNot(contains('restore-keys:')));
    }
  });
}
