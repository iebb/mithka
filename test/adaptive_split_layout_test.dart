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

  test(
    'desktop keeps split-selection navigation below the tablet threshold',
    () {
      const size = Size(700, 500);
      expect(
        usesAdaptiveSplitLayout(
          size,
          platform: TargetPlatform.macOS,
          isWeb: false,
        ),
        isFalse,
      );
      expect(
        usesSplitSelectionLayout(
          size,
          platform: TargetPlatform.macOS,
          isWeb: false,
        ),
        isTrue,
      );
    },
  );

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

  test('native desktop always uses its dedicated shell', () {
    expect(
      usesDesktopShellLayout(
        const Size(640, 480),
        platform: TargetPlatform.macOS,
        isWeb: false,
      ),
      isTrue,
    );
    expect(
      usesDesktopShellLayout(
        const Size(1200, 800),
        platform: TargetPlatform.iOS,
        isWeb: false,
      ),
      isFalse,
    );
  });

  test(
    'desktop rail survives when the list and conversation cannot both fit',
    () {
      final geometry = resolveDesktopShellGeometry(
        totalWidth: 780,
        requestedSidebarWidth: 420,
        infoPaneRequested: true,
      );

      expect(geometry.showListPane, isFalse);
      expect(geometry.showInfoPane, isFalse);
      expect(geometry.sidebarWidth, 0);
      expect(geometry.conversationWidth, 780 - desktopNavigationRailWidth);
      expect(desktopDetailNeedsBackButton(geometry), isTrue);
    },
  );

  test(
    '820px desktop constrains the list to preserve a 440px conversation',
    () {
      final geometry = resolveDesktopShellGeometry(
        totalWidth: 820,
        requestedSidebarWidth: 420,
        infoPaneRequested: true,
      );

      expect(geometry.showListPane, isTrue);
      expect(geometry.showInfoPane, isFalse);
      expect(geometry.sidebarWidth, 322);
      expect(geometry.conversationWidth, desktopConversationMinWidth);
      expect(desktopDetailNeedsBackButton(geometry), isFalse);
    },
  );

  test(
    '1100px desktop shows info only for the actual constrained list width',
    () {
      final defaultGeometry = resolveDesktopShellGeometry(
        totalWidth: 1100,
        requestedSidebarWidth: defaultSplitSidebarWidth(
          1100 - desktopNavigationRailWidth,
        ),
        infoPaneRequested: true,
      );
      final wideListGeometry = resolveDesktopShellGeometry(
        totalWidth: 1100,
        requestedSidebarWidth: 420,
        infoPaneRequested: true,
      );

      expect(defaultGeometry.showInfoPane, isTrue);
      expect(
        defaultGeometry.conversationWidth,
        greaterThanOrEqualTo(desktopConversationMinWidth),
      );
      expect(wideListGeometry.sidebarWidth, 420);
      expect(wideListGeometry.showInfoPane, isFalse);
      expect(
        wideListGeometry.conversationWidth,
        greaterThanOrEqualTo(desktopConversationMinWidth),
      );
    },
  );

  test('context pane hides before a 420px list as the window narrows', () {
    final full = resolveDesktopShellGeometry(
      totalWidth: 1280,
      requestedSidebarWidth: 420,
      infoPaneRequested: true,
    );
    final narrowed = resolveDesktopShellGeometry(
      totalWidth: 1100,
      requestedSidebarWidth: 420,
      infoPaneRequested: true,
    );

    expect(full.showListPane, isTrue);
    expect(full.showInfoPane, isTrue);
    expect(full.sidebarWidth, 420);
    expect(full.conversationWidth, 577);
    expect(narrowed.showListPane, isTrue);
    expect(narrowed.showInfoPane, isFalse);
    expect(narrowed.sidebarWidth, 420);
  });

  test('desktop info fit uses the actual sidebar width', () {
    expect(
      canShowDesktopInfoPane(totalWidth: 1142, sidebarWidth: 420),
      isFalse,
    );
    expect(canShowDesktopInfoPane(totalWidth: 1143, sidebarWidth: 420), isTrue);
  });
}
