//
//  font_weight_test.dart
//
//  Mithka's own styles use 300, 400, 500 and 600 only. Anything heavier reads
//  as a different typeface at the sizes the app draws at, so this fails the
//  build rather than letting a w700 slip back in.
//
//  AppTextWeight.forSystemBoldText is exempt: it answers the platform's Bold
//  Text accessibility setting, where climbing past semibold is the point.
//

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/theme/app_theme.dart';

final _weight = RegExp(r'FontWeight\.(w\d00|bold|normal|values)\b');

/// Weights the codebase may name. `normal` is w400, which is allowed.
const _allowedNames = {'w300', 'w400', 'w500', 'w600', 'normal'};

/// The accessibility ladder is the one place heavier weights are correct.
const _exempt = 'lib/theme/app_theme.dart';

/// Generated and vendored trees this rule does not govern.
///
/// A desktop build materializes `.plugin_symlinks` under `ephemeral/`, pointing
/// at the pub cache — including other packages' example apps, whose styling is
/// not ours to hold to this range. Their presence depends on whether anyone has
/// built for Linux or Windows locally, so scanning them makes the test's result
/// depend on the machine it runs on.
const _generatedSegments = [
  '/ephemeral/',
  '/.plugin_symlinks/',
  '/build/',
  '/.dart_tool/',
];

Iterable<File> dartSources() sync* {
  for (final directory in [Directory('lib'), Directory('packages')]) {
    if (!directory.existsSync()) continue;
    // Symlinks lead out of the repository entirely; the rule covers checked-in
    // source, so the walk stays inside it.
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalizedPath = entity.path.replaceAll('\\', '/');
      if (normalizedPath.endsWith(_exempt)) continue;
      final path = '/$normalizedPath';
      if (_generatedSegments.any(path.contains)) continue;
      yield entity;
    }
  }
}

void main() {
  test('no source names a weight outside 300-600', () {
    final offenders = <String>[];
    for (final file in dartSources()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final match in _weight.allMatches(lines[i])) {
          final name = match.group(1)!;
          if (_allowedNames.contains(name)) continue;
          offenders.add('${file.path}:${i + 1}  FontWeight.$name');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'use FontWeight.w600 as the heaviest weight:\n'
          '${offenders.join('\n')}',
    );
  });

  test('the weight tokens stay inside the range', () {
    for (final weight in [
      AppTextWeight.regular,
      AppTextWeight.medium,
      AppTextWeight.semibold,
      AppTextWeight.bold,
    ]) {
      expect(AppTextWeight.allowed, contains(weight));
    }
  });

  group('the Bold Text accessibility ladder', () {
    test('leaves weights alone when the setting is off', () {
      for (final weight in AppTextWeight.allowed) {
        expect(
          AppTextWeight.forSystemBoldText(weight, boldText: false),
          weight,
        );
      }
    });

    test('makes every weight heavier, past semibold when asked', () {
      for (final weight in AppTextWeight.allowed) {
        final bolder = AppTextWeight.forSystemBoldText(weight, boldText: true);
        expect(
          bolder.value,
          greaterThan(weight.value),
          reason: 'the system setting has to visibly do something',
        );
      }
      // Deliberately outside the app's own range.
      expect(
        AppTextWeight.forSystemBoldText(FontWeight.w600, boldText: true),
        FontWeight.w800,
      );
    });
  });
}
