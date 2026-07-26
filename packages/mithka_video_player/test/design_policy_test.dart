import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('core package does not depend on the optional FVP backend', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      pubspec,
      isNot(matches(RegExp(r'^\s*fvp\s*:', multiLine: true))),
      reason: 'FVP must remain in the optional mithka_video_player_fvp adapter',
    );

    final coreSources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in coreSources) {
      expect(
        file.readAsStringSync(),
        isNot(contains('package:fvp/')),
        reason: '${file.path} imports the optional FVP backend',
      );
    }
  });

  test('package and example UI do not depend on Material or Cupertino', () {
    final roots = [Directory('lib'), Directory('example/lib')];
    final dartFiles = roots
        .expand(
          (root) => root
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart')),
        )
        .toList();

    expect(dartFiles, isNotEmpty);
    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(contains('package:flutter/material.dart')),
        reason: '${file.path} imports Material',
      );
      expect(
        source,
        isNot(contains('package:flutter/cupertino.dart')),
        reason: '${file.path} imports Cupertino',
      );
      expect(
        source,
        isNot(matches(RegExp(r'\b(?:Icons|CupertinoIcons)\.'))),
        reason: '${file.path} uses a built-in icon set',
      );
    }
  });
}
