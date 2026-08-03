import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iOS app-switcher privacy protection for a configured local app lock.
///
/// Android's screenshot/task-switcher switch is intentionally not part of
/// this pass. On iOS, UIKit still allows the app to cover its background
/// snapshot while the app is leaving the foreground.
class AppLockPrivacyPlatform {
  const AppLockPrivacyPlatform._();

  static const _channel = MethodChannel('mithka/app_lock_privacy');

  static Future<void> setPrivacyShieldVisible(bool visible) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    await _channel.invokeMethod<void>('setPrivacyShieldVisible', {
      'visible': visible,
    });
  }
}
