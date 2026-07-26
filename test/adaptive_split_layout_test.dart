import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/adaptive_split_layout.dart';

void main() {
  test('desktop keeps the iPad split UI in a short wide window', () {
    for (final platform in const [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      expect(
        usesAdaptiveSplitLayout(
          const Size(800, 500),
          platform: platform,
          isWeb: false,
        ),
        isTrue,
      );
    }
  });

  test('desktop falls back only when two usable panes cannot fit', () {
    expect(
      usesAdaptiveSplitLayout(
        const Size(700, 500),
        platform: TargetPlatform.macOS,
        isWeb: false,
      ),
      isFalse,
    );
  });

  test('tablet split remains limited to sufficiently large landscape UI', () {
    expect(
      usesAdaptiveSplitLayout(
        const Size(1024, 768),
        platform: TargetPlatform.iOS,
        isWeb: false,
      ),
      isTrue,
    );
    expect(
      usesAdaptiveSplitLayout(
        const Size(768, 1024),
        platform: TargetPlatform.iOS,
        isWeb: false,
      ),
      isFalse,
    );
  });

  test('dragged sidebar width preserves both pane minimums', () {
    expect(
      constrainSplitSidebarWidth(requestedWidth: 100, totalWidth: 1200),
      splitSidebarMinWidth,
    );
    expect(
      constrainSplitSidebarWidth(requestedWidth: 1000, totalWidth: 1200),
      1200 - splitDetailMinWidth,
    );
  });
}
