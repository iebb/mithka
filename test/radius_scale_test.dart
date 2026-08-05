//
//  radius_scale_test.dart
//
//  Corner radii had drifted across every value from 1 to 28, so the same kind
//  of element was a different shape depending on which screen you opened. The
//  scale in AppRadius is the fix; this keeps it from drifting back.
//

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/theme/app_theme.dart';

/// Literal radii that are allowed to stay literal.
///
/// Below the smallest step is hairline detail — a 2px inner mark reads as
/// square either way. At or above [AppRadius.pill] the shape is fully rounded,
/// and half-of-a-known-size is real geometry: a 42px box with a 21px radius is
/// a circle, and snapping it to a step would quietly make it an oval-ish
/// rounded square.
bool isAllowedLiteral(double radius) =>
    radius < AppRadius.sm || radius >= AppRadius.pill;

final _radiusCall = RegExp(
  r'BorderRadius\.circular\(\s*([0-9]+(?:\.[0-9]+)?)\s*\)',
);
final _nearbyDimension = RegExp(
  r'\b(?:width|height|size|radius|diameter)\s*:\s*([0-9]+(?:\.[0-9]+)?)',
);

/// True when the radius is half an adjacent dimension, i.e. a circle or
/// stadium rather than a rounded rectangle that wants a step.
bool _isGeometry(String source, int offset, double radius) {
  final start = offset - 260 < 0 ? 0 : offset - 260;
  final end = offset + 260 > source.length ? source.length : offset + 260;
  return _nearbyDimension
      .allMatches(source.substring(start, end))
      .any((m) => (double.parse(m.group(1)!) / 2 - radius).abs() < 0.51);
}

void main() {
  test('the scale is ordered and has no duplicate steps', () {
    const steps = [
      AppRadius.sm,
      AppRadius.md,
      AppRadius.control,
      AppRadius.card,
      AppRadius.lg,
      AppRadius.xl,
      AppRadius.xxl,
    ];
    expect(steps.toSet(), hasLength(steps.length), reason: 'duplicate step');
    for (var i = 1; i < steps.length; i++) {
      expect(steps[i], greaterThan(steps[i - 1]), reason: 'step $i');
    }
    expect(AppRadius.pill, greaterThan(steps.last));
  });

  test('no rounded surface uses an off-scale literal radius', () {
    final steps = <double>{
      AppRadius.sm,
      AppRadius.md,
      AppRadius.control,
      AppRadius.card,
      AppRadius.lg,
      AppRadius.xl,
      AppRadius.xxl,
    };
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('theme/app_theme.dart')) continue;
      final source = entity.readAsStringSync();
      for (final match in _radiusCall.allMatches(source)) {
        final radius = double.parse(match.group(1)!);
        if (isAllowedLiteral(radius)) continue;
        if (steps.contains(radius)) continue; // on-scale, just not tokenised
        if (_isGeometry(source, match.start, radius)) continue;
        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        offenders.add('${entity.path}:$line uses $radius');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Pick a step from AppRadius instead of a literal. If the shape is a '
          'circle or stadium, use AppRadius.pill so it stays right when the '
          'size changes.\n${offenders.join('\n')}',
    );
  });
}
