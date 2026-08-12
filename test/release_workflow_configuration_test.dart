import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Linux release installs the hotkey manager native dependency', () {
    final workflow = File('.github/workflows/release.yml').readAsStringSync();

    final linuxDependencies = RegExp(
      r"- name: Install Linux build dependencies[\s\S]*?"
      r"- name: Cache desktop tdjson",
    ).firstMatch(workflow);

    expect(linuxDependencies, isNotNull);
    expect(linuxDependencies!.group(0), contains('libkeybinder-3.0-dev'));
  });

  test('release workflows use the checked-in TDJSON manifest installers', () {
    for (final path in const [
      '.github/workflows/release.yml',
      '.github/workflows/google-play.yml',
    ]) {
      final workflow = File(path).readAsStringSync();

      expect(workflow, contains("hashFiles('scripts/tdjson-manifest.json')"));
      expect(workflow, contains('scripts/build-tdjson-android.sh'));
      expect(workflow, isNot(contains('TDJSON_RELEASE_TAG')));
      expect(workflow, isNot(contains('TDJSON_UPSTREAM_SHA')));
      expect(workflow, isNot(contains('TDJSON_ANDROID_ARM64_V8A_SHA256')));
      expect(workflow, isNot(contains('Resolve tdjson release')));
      expect(workflow, isNot(contains('/releases/download/')));
      expect(workflow, isNot(contains('restore-keys:')));
    }

    final desktopWorkflow = File(
      '.github/workflows/release.yml',
    ).readAsStringSync();
    expect(desktopWorkflow, contains('scripts/build-tdjson-desktop.sh'));
    expect(desktopWorkflow, isNot(contains('NATIVE_HELPER_ROOT')));
    expect(desktopWorkflow, isNot(contains('.tdlib-helper')));
    expect(desktopWorkflow, isNot(contains('.tdlib-build')));
    expect(desktopWorkflow, isNot(contains('vcpkg.exe')));
    expect(desktopWorkflow, isNot(contains('brew install cmake ninja')));
  });
}
