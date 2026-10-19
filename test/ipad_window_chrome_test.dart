import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/ipad_window_chrome.dart';

void main() {
  // Values measured on an iPad Pro 13-inch simulator running iPadOS 27:
  // Display.size always keeps the panel's native portrait orientation.
  const displaySize = Size(2064, 2752);
  const floatingViewSize = Size(2256, 1480);
  const fullscreenViewSize = Size(2752, 2064);
  const iPadOS26 = 'Version 26.0 (Build 23A5260n)';
  // iPhone 15 Pro Max panel, and the canvas Display Zoom gives the app on it.
  const iPhonePanelSize = Size(1290, 2796);
  const iPhoneZoomedViewSize = Size(1179, 2556);
  // iPad Pro 13-inch panel rendered by Display Zoom (~0.80 uniform scale).
  const iPadZoomedViewSize = Size(1653, 2200);
  // A floating window dragged to exactly half the panel in both dimensions.
  const halfSizeWindow = Size(1032, 1376);

  test('reserves clearance for a floating window on iPadOS 26', () {
    expect(
      iPadWindowChromeInset(
        viewSize: floatingViewSize,
        displaySize: displaySize,
        paddingTop: 10,
        platform: TargetPlatform.iOS,
        isWeb: false,
        operatingSystemVersion: iPadOS26,
      ),
      iPadWindowControlsTopInset,
    );
  });

  test('reserves clearance for a full-width tiled window', () {
    expect(
      iPadWindowChromeInset(
        viewSize: const Size(2752, 2000),
        displaySize: displaySize,
        paddingTop: 10,
        platform: TargetPlatform.iOS,
        isWeb: false,
        operatingSystemVersion: iPadOS26,
      ),
      iPadWindowControlsTopInset,
    );
  });

  test('no clearance in landscape fullscreen despite the menu bar', () {
    expect(
      iPadWindowChromeInset(
        viewSize: fullscreenViewSize,
        displaySize: displaySize,
        paddingTop: 32,
        platform: TargetPlatform.iOS,
        isWeb: false,
        operatingSystemVersion: iPadOS26,
      ),
      0,
    );
  });

  test('no clearance in portrait fullscreen', () {
    expect(
      iPadWindowChromeInset(
        viewSize: displaySize,
        displaySize: displaySize,
        paddingTop: 32,
        platform: TargetPlatform.iOS,
        isWeb: false,
        operatingSystemVersion: iPadOS26,
      ),
      0,
    );
  });

  test('no clearance on a landscape iPhone without a status bar', () {
    expect(
      iPadWindowChromeInset(
        viewSize: const Size(2532, 1170),
        displaySize: const Size(1170, 2532),
        paddingTop: 0,
        platform: TargetPlatform.iOS,
        isWeb: false,
        operatingSystemVersion: iPadOS26,
      ),
      0,
    );
  });

  test('no clearance on an iPhone using Display Zoom', () {
    // Display Zoom renders the app on a canvas scaled by ~0.914 on both
    // sides, while the status bar keeps its full notched-device inset.
    expect(
      iPadWindowChromeInset(
        viewSize: iPhoneZoomedViewSize,
        displaySize: iPhonePanelSize,
        paddingTop: 59,
        platform: TargetPlatform.iOS,
        isWeb: false,
        operatingSystemVersion: iPadOS26,
      ),
      0,
    );
  });

  test('no clearance on a landscape iPhone using Display Zoom', () {
    expect(
      iPadWindowChromeInset(
        viewSize: const Size(2556, 1179),
        displaySize: iPhonePanelSize,
        paddingTop: 0,
        platform: TargetPlatform.iOS,
        isWeb: false,
        operatingSystemVersion: iPadOS26,
      ),
      0,
    );
  });

  test('no clearance on an iPhone at native scale', () {
    expect(
      iPadWindowChromeInset(
        viewSize: iPhonePanelSize,
        displaySize: iPhonePanelSize,
        paddingTop: 59,
        platform: TargetPlatform.iOS,
        isWeb: false,
        operatingSystemVersion: iPadOS26,
      ),
      0,
    );
  });

  test('no clearance on an iPad using Display Zoom', () {
    expect(
      iPadWindowChromeInset(
        viewSize: iPadZoomedViewSize,
        displaySize: displaySize,
        paddingTop: 32,
        platform: TargetPlatform.iOS,
        isWeb: false,
        operatingSystemVersion: iPadOS26,
      ),
      0,
    );
  });

  test('reserves clearance for a half-size window reporting window chrome', () {
    // Uniform by size alone, so the ~10pt window margin is what identifies it.
    expect(
      iPadWindowChromeInset(
        viewSize: halfSizeWindow,
        displaySize: displaySize,
        paddingTop: 10,
        platform: TargetPlatform.iOS,
        isWeb: false,
        operatingSystemVersion: iPadOS26,
      ),
      iPadWindowControlsTopInset,
    );
  });

  test('half-size window with a fullscreen status bar reads as fullscreen', () {
    // A real half-size window reports the ~10pt window chrome margin, never
    // the fullscreen menu-bar inset, so this pairing is not a live window.
    expect(
      iPadWindowChromeInset(
        viewSize: halfSizeWindow,
        displaySize: displaySize,
        paddingTop: 32,
        platform: TargetPlatform.iOS,
        isWeb: false,
        operatingSystemVersion: iPadOS26,
      ),
      0,
    );
  });

  test('reserves clearance for a window scaled unevenly', () {
    expect(
      iPadWindowChromeInset(
        viewSize: floatingViewSize,
        displaySize: displaySize,
        paddingTop: 32,
        platform: TargetPlatform.iOS,
        isWeb: false,
        operatingSystemVersion: iPadOS26,
      ),
      iPadWindowControlsTopInset,
    );
  });

  test('no clearance for a floating window before iPadOS 26', () {
    expect(
      iPadWindowChromeInset(
        viewSize: floatingViewSize,
        displaySize: displaySize,
        paddingTop: 10,
        platform: TargetPlatform.iOS,
        isWeb: false,
        operatingSystemVersion: 'Version 18.2 (Build 22C152)',
      ),
      0,
    );
  });

  test('no clearance on other platforms', () {
    for (final platform in const [
      TargetPlatform.macOS,
      TargetPlatform.android,
      TargetPlatform.linux,
      TargetPlatform.windows,
      TargetPlatform.fuchsia,
    ]) {
      expect(
        iPadWindowChromeInset(
          viewSize: floatingViewSize,
          displaySize: displaySize,
          paddingTop: 10,
          platform: platform,
          isWeb: false,
          operatingSystemVersion: iPadOS26,
        ),
        0,
      );
    }
  });

  test('no clearance on the web', () {
    expect(
      iPadWindowChromeInset(
        viewSize: floatingViewSize,
        displaySize: displaySize,
        paddingTop: 10,
        platform: TargetPlatform.iOS,
        isWeb: true,
        operatingSystemVersion: iPadOS26,
      ),
      0,
    );
  });

  test('unparseable version string falls back to no clearance', () {
    expect(
      iPadWindowChromeInset(
        viewSize: floatingViewSize,
        displaySize: displaySize,
        paddingTop: 10,
        platform: TargetPlatform.iOS,
        isWeb: false,
        operatingSystemVersion: 'iOS',
      ),
      0,
    );
  });

  test('size tolerance ignores sub-pixel rounding', () {
    expect(
      iPadWindowChromeInset(
        viewSize: const Size(2063, 2751),
        displaySize: displaySize,
        paddingTop: 32,
        platform: TargetPlatform.iOS,
        isWeb: false,
        operatingSystemVersion: iPadOS26,
      ),
      0,
    );
  });
}
