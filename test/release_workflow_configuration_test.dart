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

  test('Windows releases publish installers beside portable archives', () {
    final workflow = File('.github/workflows/release.yml').readAsStringSync();
    final installer = File('windows/installer/mithka.iss').readAsStringSync();
    final builder = File(
      'scripts/build-windows-installer.ps1',
    ).readAsStringSync();

    expect(workflow, contains('scripts\\build-windows-installer.ps1'));
    expect(workflow, contains('*-windows-x64-setup.exe'));
    expect(workflow, contains('*-windows-arm64-setup.exe'));
    expect(workflow, contains("'*-windows-x64.zip'"));
    expect(workflow, contains("'*-windows-arm64.zip'"));

    expect(installer, contains(r'PrivilegesRequired=lowest'));
    expect(
      installer,
      contains(r'DefaultDirName={localappdata}\Programs\Mithka'),
    );
    expect(
      installer,
      contains(r'UninstallFilesDir={localappdata}\Programs\Mithka Uninstall'),
      reason: 'the in-app directory swap must not erase the uninstaller',
    );
    expect(installer, contains(r'Type: filesandordirs; Name: "{app}"'));
    expect(installer, contains(r'ArchitecturesAllowed=arm64'));
    expect(
      installer,
      contains(r'ArchitecturesAllowed=x64compatible and not arm64'),
    );
    expect(
      builder,
      contains("'mithka.exe', 'flutter_windows.dll', 'tdjson.dll'"),
    );
    expect(builder, contains('0xAA64'));
    expect(builder, contains('0x8664'));
  });
}
