import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/update/release_feed.dart';
import 'package:mithka/update/update_checker.dart';

void main() {
  const isGooglePlayBuild = bool.fromEnvironment('GOOGLE_PLAY_BUILD');

  test('compile-time distribution flag controls automatic updates', () {
    expect(UpdateChecker.automaticChecksEnabled(), equals(!isGooglePlayBuild));
  });

  test('automatic updates are disabled for Google Play builds', () {
    expect(
      UpdateChecker.automaticChecksEnabled(isGooglePlayBuild: true),
      isFalse,
    );
  });

  test('a manual check follows the same distribution rule', () {
    expect(
      UpdateChecker.automaticChecksEnabled(isGooglePlayBuild: true),
      isFalse,
      reason: 'About must not offer GitHub packages to a Play install',
    );
    final hostHasPackage = UpdateChecker.platformSelfDistributes(
      isAndroid: Platform.isAndroid,
      packageSuffix: desktopPackageSuffix(),
    );
    expect(
      UpdateChecker.supportsManualCheck,
      equals(!isGooglePlayBuild && hostHasPackage),
    );
  });

  group('which platforms Mithka distributes itself on', () {
    test('Android is offered the APK for its ABI', () {
      expect(UpdateChecker.platformSelfDistributes(isAndroid: true), isTrue);
    });

    test('each published desktop architecture is offered its package', () {
      for (final abi in [
        Abi.linuxX64,
        Abi.linuxArm64,
        Abi.windowsX64,
        Abi.windowsArm64,
      ]) {
        expect(
          UpdateChecker.platformSelfDistributes(
            packageSuffix: desktopPackageSuffix(abi),
          ),
          isTrue,
          reason: '$abi ships a package on GitHub Releases',
        );
      }
    });

    test('macOS has no GitHub package to offer', () {
      expect(
        UpdateChecker.platformSelfDistributes(
          packageSuffix: desktopPackageSuffix(Abi.macosArm64),
        ),
        isFalse,
      );
    });
  });
}
