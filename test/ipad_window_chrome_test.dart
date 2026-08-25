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
