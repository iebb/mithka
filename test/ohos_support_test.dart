import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/platform/ohos_support.dart';

void main() {
  group('isOhosFor', () {
    test('matches only the HarmonyOS operating-system string', () {
      expect(isOhosFor('ohos'), isTrue);
      expect(isOhosFor('android'), isFalse);
      expect(isOhosFor('ios'), isFalse);
      expect(isOhosFor('macos'), isFalse);
      expect(isOhosFor(''), isFalse);
    });
  });

  group('isMobileOperatingSystemFor', () {
    test('treats HarmonyOS as a mobile platform beside Android and iOS', () {
      expect(isMobileOperatingSystemFor('ohos'), isTrue);
      expect(isMobileOperatingSystemFor('android'), isTrue);
      expect(isMobileOperatingSystemFor('ios'), isTrue);
      expect(isMobileOperatingSystemFor('macos'), isFalse);
      expect(isMobileOperatingSystemFor('windows'), isFalse);
      expect(isMobileOperatingSystemFor('linux'), isFalse);
    });
  });

  group('runtime getters', () {
    // Platform.operatingSystem cannot be mocked in a VM test, so the getters
    // are pinned against the host instead: every CI host is a desktop OS,
    // where both helpers must report their desktop branch.
    test('a desktop host reports not-ohos; mobile matches the host OS', () {
      expect(isOhos, isFalse);
      expect(
        isMobilePlatform,
        isMobileOperatingSystemFor(Platform.operatingSystem),
      );
    });
  });

  test('HarmonyOS selects the method-channel file picker', () {
    // file_picker registers no Dart implementation for ohos; without this
    // fallback FilePicker.platform is an uninitialized late field there.
    registerOhosDartPluginFallbacks(onOhos: true);
    expect(FilePicker.platform, isA<FilePickerIO>());
  });

  test('HarmonyOS composer offers the camera entry', () {
    // Capture goes through the system camera there, so the strip must show it
    // even though defaultTargetPlatform is neither Android nor iOS.
    expect(composerShowsCameraIcon(null, true), isTrue);
    expect(composerShowsCameraIcon(TargetPlatform.macOS, true), isFalse);
    expect(composerShowsCameraIcon(TargetPlatform.macOS, false), isFalse);
    expect(composerShowsCameraIcon(TargetPlatform.iOS, false), isTrue);
  });
}
