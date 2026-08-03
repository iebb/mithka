import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS hosts sanitize embedded MDK before final app signing', () {
    final script = File('tool/sanitize_mdk_macos.sh').readAsStringSync();
    final rootProject = File(
      '../../macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final exampleProject = File(
      '../mithka_video_player/example/macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    expect(script, contains('set -euo pipefail'));
    expect(script, contains(r'mdk_binary="$mdk_framework/Versions/A/mdk"'));
    expect(script, contains('install_name_tool'));
    expect(script, contains('-delete_rpath'));
    expect(script, contains('/opt/homebrew/lib'));
    expect(script, contains('/usr/local/lib'));
    expect(script, isNot(contains('grep -Fq')));
    expect(script, contains(r'load_commands="$(/usr/bin/otool -l'));
    expect(script, contains('EXPANDED_CODE_SIGN_IDENTITY'));
    expect(script, contains("-type f -name '*.dylib' -print0"));
    expect(script, contains(r'codesign --verify --strict "$nested_dylib"'));
    expect(script, contains('codesign --verify --deep --strict'));
    expect(
      script.indexOf(r'--sign "$signing_identity"'),
      lessThan(script.lastIndexOf(r'--sign "$signing_identity"')),
    );
    expect(
      script.indexOf(r'"$nested_dylib"'),
      lessThan(script.indexOf(r'"$mdk_framework"')),
    );

    expect(rootProject, contains('Sanitize embedded MDK'));
    expect(rootProject, contains('/bin/bash'));
    expect(
      rootProject,
      contains(
        r'$SRCROOT/../packages/mithka_video_player_fvp/tool/'
        'sanitize_mdk_macos.sh',
      ),
    );
    expect(
      rootProject.indexOf('Embed macOS TDLib */,'),
      lessThan(rootProject.indexOf('Sanitize embedded MDK */,')),
    );

    expect(exampleProject, contains('Sanitize embedded MDK'));
    expect(exampleProject, contains('/bin/bash'));
    expect(
      exampleProject,
      contains(
        r'$SRCROOT/../../../mithka_video_player_fvp/tool/'
        'sanitize_mdk_macos.sh',
      ),
    );
    expect(
      exampleProject.indexOf('3399D490228B24CF009A79C7 /* ShellScript */,'),
      lessThan(exampleProject.indexOf('Sanitize embedded MDK */,')),
    );
  });
}
