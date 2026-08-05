//
//  popup_menu_density_test.dart
//
//  The anchored menus hanging off the desktop title bar were built at touch
//  size — 50pt rows, 16pt text, a 220pt card — which reads as oversized next
//  to the chrome it drops from. These pin the two densities, and pin the
//  anchoring maths to the width the menu actually renders.
//

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  const pointer = TargetPlatform.macOS;
  const touch = TargetPlatform.iOS;

  test('a pointer gets the denser menu', () {
    expect(
      AppMetric.popupMenuRowHeight(pointer),
      lessThan(AppMetric.popupMenuRowHeight(touch)),
    );
    expect(
      AppMetric.popupMenuWidth(pointer),
      lessThan(AppMetric.popupMenuWidth(touch)),
    );
    expect(
      AppMetric.popupMenuTextSize(pointer),
      lessThan(AppMetric.popupMenuTextSize(touch)),
    );
    expect(
      AppMetric.popupMenuIconSlot(pointer),
      lessThan(AppMetric.popupMenuIconSlot(touch)),
    );
    expect(
      AppMetric.popupMenuInset(pointer),
      lessThan(AppMetric.popupMenuInset(touch)),
    );
  });

  test('touch keeps the fingertip sizes', () {
    expect(AppMetric.popupMenuRowHeight(touch), AppMetric.menuRowHeight);
    expect(AppMetric.popupMenuWidth(touch), AppMetric.menuWidth);
    expect(AppMetric.popupMenuIconSlot(touch), AppMetric.menuIconSlot);
    expect(AppMetric.popupMenuTextSize(touch), AppTextSize.bodyLarge);
  });

  test('a pointer row still clears a comfortable minimum', () {
    expect(
      AppMetric.popupMenuRowHeight(pointer),
      greaterThanOrEqualTo(28),
      reason: 'dense is not the same as cramped',
    );
  });

  test('the icon fits its slot', () {
    for (final platform in [pointer, touch]) {
      // Both menus draw the glyph at slot - 3.
      expect(
        AppMetric.popupMenuIconSlot(platform) - 3,
        lessThan(AppMetric.popupMenuIconSlot(platform)),
      );
      expect(
        AppMetric.popupMenuIconSlot(platform) - 3,
        lessThan(AppMetric.popupMenuRowHeight(platform)),
        reason: 'a glyph taller than its row would clip',
      );
    }
  });

  test('every metric answers the ambient platform', () {
    debugDefaultTargetPlatformOverride = pointer;
    final dense = AppMetric.popupMenuWidth();
    debugDefaultTargetPlatformOverride = touch;
    final roomy = AppMetric.popupMenuWidth();
    debugDefaultTargetPlatformOverride = null;

    expect(
      dense,
      lessThan(roomy),
      reason:
          'the call sites pass no platform, so the default has to resolve '
          'it — the anchoring maths depends on matching the rendered width',
    );
  });
}
