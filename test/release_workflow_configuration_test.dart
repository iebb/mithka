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
}
