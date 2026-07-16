import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  test('service plates remain readable over any wallpaper', () {
    for (final colors in [
      AppColors.light,
      AppColors.dark,
      AppColors.light.copyWith(bubbleIncoming: const Color(0xFFF3B4BD)),
      AppColors.dark.copyWith(bubbleIncoming: const Color(0xFF101820)),
    ]) {
      final plate = servicePlateBackground(colors);
      final foreground = servicePlateForeground(plate);

      expect(plate.a, 1);
      expect(_contrastRatio(plate, foreground), greaterThanOrEqualTo(4.5));
    }
  });
}

double _contrastRatio(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  final lighter = math.max(a, b);
  final darker = math.min(a, b);
  return (lighter + 0.05) / (darker + 0.05);
}
