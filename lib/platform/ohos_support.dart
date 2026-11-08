//
//  ohos_support.dart
//
//  HarmonyOS (ohos) platform gating helpers.
//

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound_platform_interface/flutter_sound_recorder_platform_interface.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

import 'ohos_media_bridge.dart';

/// Whether [operatingSystem] names HarmonyOS.
///
/// Pure so tests can pin the mapping on any host.
bool isOhosFor(String operatingSystem) => operatingSystem == 'ohos';

/// Whether the app runs on HarmonyOS (HarmonyOS NEXT).
///
/// Detected through `dart:io`'s operating-system string instead of
/// `TargetPlatform.ohos` because the stock Flutter SDK that CI compiles with
/// has no such enum value — that literal only builds against the OpenHarmony
/// flutter fork. The fork reports `Platform.operatingSystem == 'ohos'` at
/// runtime, which stock-compiled code can still observe.
bool get isOhos => !kIsWeb && isOhosFor(Platform.operatingSystem);

/// Selects Dart plugin implementations the OHOS fork cannot register itself.
///
/// file_picker declares a `dartPluginClass` only for its stock platforms, so
/// on HarmonyOS `FilePicker.platform` would stay uninitialized. Its
/// method-channel implementation speaks exactly the channel, method names and
/// arguments that the file_picker_ohos native plugin serves.
///
/// image_picker, permission_handler's microphone and flutter_sound's recorder
/// have no OHOS native side at all; they are answered by the app's own bridge
/// (see ohos_media_bridge.dart).
void registerOhosDartPluginFallbacks({bool? onOhos}) {
  if (!(onOhos ?? isOhos)) return;
  FilePickerIO.registerWith();
  ImagePickerPlatform.instance = OhosImagePicker();
  PermissionHandlerPlatform.instance = OhosPermissionHandler(
    fallback: PermissionHandlerPlatform.instance,
  );
  FlutterSoundRecorderPlatform.instance = OhosFlutterSoundRecorder();
}

/// Whether [operatingSystem] names a phone/tablet system.
bool isMobileOperatingSystemFor(String operatingSystem) =>
    operatingSystem == 'android' ||
    operatingSystem == 'ios' ||
    isOhosFor(operatingSystem);

/// Whether the app runs on a phone/tablet platform: Android, iOS, or
/// HarmonyOS.
///
/// The mobile-vs-desktop boundary in one place, so HarmonyOS joins the mobile
/// branch without every call site learning about it. Reads `dart:io` (not
/// `TargetPlatform.ohos`) for the same stock-SDK reason as [isOhos]; on the
/// ohos fork `defaultTargetPlatform` is an enum value stock code cannot name.
///
/// An explicit `debugDefaultTargetPlatformOverride` of Android or iOS also
/// counts: widget tests simulate those platforms through that override while
/// `dart:io` keeps reporting the desktop host, and the mobile branch must
/// follow the simulation. The override is null outside tests, so real devices
/// and profiles are decided by the operating system alone.
bool get isMobilePlatform {
  if (kIsWeb) return false;
  if (isMobileOperatingSystemFor(Platform.operatingSystem)) return true;
  final override = debugDefaultTargetPlatformOverride;
  return override == TargetPlatform.android || override == TargetPlatform.iOS;
}
