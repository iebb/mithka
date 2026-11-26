import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS requests only capabilities implemented by the release app', () {
    for (final path in [
      'macos/Runner/DebugProfile.entitlements',
      'macos/Runner/Release.entitlements',
    ]) {
      final entitlements = File(path).readAsStringSync();
      expect(entitlements, contains('com.apple.security.device.audio-input'));
      // Video streams through a loopback HTTP server; the sandbox refuses
      // bind() on 127.0.0.1 without this, so videos fail to load.
      expect(entitlements, contains('com.apple.security.network.server'));
      expect(entitlements, isNot(contains('com.apple.security.device.camera')));
      expect(
        entitlements,
        isNot(contains('com.apple.security.personal-information.location')),
      );
    }

    final info = File('macos/Runner/Info.plist').readAsStringSync();
    expect(info, contains('NSMicrophoneUsageDescription'));
    expect(info, isNot(contains('NSCameraUsageDescription')));
    expect(info, isNot(contains('NSLocationWhenInUseUsageDescription')));

    // The Liquid Glass Icon Composer icon, not the flat AppIcon fallback.
    final project = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final iconNames = RegExp(
      r'ASSETCATALOG_COMPILER_APPICON_NAME = (\w+);',
    ).allMatches(project).map((match) => match.group(1)).toSet();
    expect(iconNames, {'Pengram'});
  });
}
