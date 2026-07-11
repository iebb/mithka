//
//  screen_wakelock.dart
//
//  Keeps the screen awake during video playback by toggling the platform's
//  idle-timer / keep-screen-on flag through a lightweight method channel.
//  On Android this sets FLAG_KEEP_SCREEN_ON on the activity window; on iOS it
//  disables UIApplication.idleTimerDisabled.  Calls are silently ignored on
//  platforms without a registered handler (e.g. desktop), so the caller never
//  needs to guard.
//

import 'package:flutter/services.dart';

class ScreenWakelock {
  ScreenWakelock._();

  static const _channel = MethodChannel('mithka/screen_wakelock');

  /// Prevent the screen from dimming or sleeping.
  static Future<void> enable() async {
    try {
      await _channel.invokeMethod<void>('enable');
    } on MissingPluginException {
      // Platform has no handler — nothing to do.
    } catch (_) {
      // Best-effort; never let wakelock failures crash playback.
    }
  }

  /// Restore the system's normal idle-timer behaviour.
  static Future<void> disable() async {
    try {
      await _channel.invokeMethod<void>('disable');
    } on MissingPluginException {
      // Platform has no handler — nothing to do.
    } catch (_) {
      // Best-effort.
    }
  }
}
