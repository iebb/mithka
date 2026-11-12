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
  });
}
