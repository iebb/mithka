import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final isMsvc in [true, false]) {
    test('legacy WinRT guard is target-scoped (MSVC: $isMsvc)', () async {
      final probe = await Directory.systemTemp.createTemp(
        'mithka-winrt-compat-',
      );
      addTearDown(() => probe.delete(recursive: true));
      final module = File(
        'windows/winrt_coroutine_compat.cmake',
      ).absolute.path.replaceAll('\\', '/');
      await File('${probe.path}/CMakeLists.txt').writeAsString('''
cmake_minimum_required(VERSION 3.14)
project(compat_probe LANGUAGES CXX)
set(MSVC ${isMsvc ? 'TRUE' : 'FALSE'})
file(WRITE "\${CMAKE_BINARY_DIR}/probe.cc" "int compatibility_probe = 0;")
add_library(local_auth_windows_plugin STATIC "\${CMAKE_BINARY_DIR}/probe.cc")
add_library(permission_handler_windows_plugin STATIC "\${CMAKE_BINARY_DIR}/probe.cc")
add_library(unrelated_plugin STATIC "\${CMAKE_BINARY_DIR}/probe.cc")
include("$module")
mithka_apply_legacy_winrt_coroutine_compat()
foreach(target IN ITEMS local_auth_windows_plugin permission_handler_windows_plugin unrelated_plugin)
  get_target_property(definitions \${target} COMPILE_DEFINITIONS)
  list(FIND definitions "_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS" guard_index)
  if(${isMsvc ? 'TRUE' : 'FALSE'} AND NOT target STREQUAL "unrelated_plugin")
    if(guard_index LESS 0)
      message(FATAL_ERROR "Affected target has no compatibility guard")
    endif()
  elseif(NOT guard_index LESS 0)
    message(FATAL_ERROR "Guard leaked outside the affected MSVC targets")
  endif()
endforeach()
''');
      final result = await Process.run('cmake', [
        '-S',
        probe.path,
        '-B',
        '${probe.path}/build',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    });
  }

  test('missing optional plugin targets are safe', () async {
    final probe = await Directory.systemTemp.createTemp('mithka-winrt-empty-');
    addTearDown(() => probe.delete(recursive: true));
    final module = File(
      'windows/winrt_coroutine_compat.cmake',
    ).absolute.path.replaceAll('\\', '/');
    await File('${probe.path}/CMakeLists.txt').writeAsString('''
cmake_minimum_required(VERSION 3.14)
project(compat_probe LANGUAGES NONE)
set(MSVC TRUE)
include("$module")
mithka_apply_legacy_winrt_coroutine_compat()
''');
    final result = await Process.run('cmake', [
      '-S',
      probe.path,
      '-B',
      '${probe.path}/build',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('production hook follows generated plugin targets', () {
    final cmake = File('windows/CMakeLists.txt').readAsStringSync();
    final plugins = cmake.indexOf('include(flutter/generated_plugins.cmake)');
    final guard = cmake.indexOf('mithka_apply_legacy_winrt_coroutine_compat()');
    expect(plugins, greaterThanOrEqualTo(0));
    expect(guard, greaterThan(plugins));
  });

  test('recovery is dispatch-only and pins validated release provenance', () {
    final workflow = File(
      '.github/workflows/windows-arm64-recovery.yml',
    ).readAsStringSync();
    expect(workflow, contains('workflow_dispatch:'));
    expect(workflow, isNot(contains('  push:')));
    expect(workflow, contains('contents: read'));
    expect(workflow, contains('actions: read'));
    expect(workflow, isNot(contains('contents: write')));
    expect(workflow, contains(r'ref: ${{ inputs.release_sha }}'));
    expect(workflow, contains('git rev-parse origin/release'));
    expect(workflow, contains(r'$originalRun.head_sha -ne $releaseSha'));
    expect(
      workflow,
      contains(r"$originalRun.path -ne '.github/workflows/release.yml'"),
    );
    expect(workflow, contains('Original release needs a passed quality gate'));
    expect(workflow, contains('Original build stamp is ambiguous'));
    expect(
      workflow,
      contains(
        'scripts/build-tdjson-desktop.sh windows native-libs/tdjson.dll arm64',
      ),
    );
    expect(workflow, isNot(contains('gh release')));
    expect(workflow, isNot(contains('git push')));
    expect(workflow, isNot(contains('sendMessage')));
  });
}
