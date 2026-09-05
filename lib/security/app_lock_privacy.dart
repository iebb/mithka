import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// App-switcher privacy protection for a configured local app lock.
///
/// iOS covers the window before UIKit captures its background snapshot.
/// Android temporarily applies `FLAG_SECURE` while the activity is away so the
/// task preview cannot expose the unlocked conversation underneath the gate.
class AppLockPrivacyPlatform {
  const AppLockPrivacyPlatform._();

  static const _channel = MethodChannel('mithka/app_lock_privacy');

  static Future<void> setPrivacyShieldVisible(bool visible) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      return;
    }
    await _channel.invokeMethod<void>('setPrivacyShieldVisible', {
      'visible': visible,
    });
  }
}
