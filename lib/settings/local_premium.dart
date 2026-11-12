//
//  local_premium.dart
//
//  Local "fake Premium" for THIS account only (Telegram API Terms §1.4
//  self-build feature, behind the compile-time gate — enabled builds opt
//  in explicitly, official-style builds compile every path out). It never
//  talks to Telegram: the flag only short-circuits the client-side
//  "am I premium" checks so locally-rendered limits and premium UI unlock.
//  Server-side enforcement (upload limits, premium-only actions) still
//  applies — nothing here can bypass what the server rejects.
//
//  The write path sets getOption/setOption 'x_empty_local_premium' — a
//  device-local TDLib option mirror carries no server meaning; TDLib
//  ignores unknown option names, which is exactly what we want: the value
//  lives in this file's prefs, not in any server-visible state.
//

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/build_flags.dart';

/// Whether the active account's premium-only client surfaces act unlocked.
class LocalPremium extends ChangeNotifier {
  LocalPremium._();

  static final LocalPremium shared = LocalPremium._();

  static bool get isAvailable => allowTelegramTosViolations;

  static const _enabledKey = 'local_premium.enabled';

  bool _enabled = false;
  SharedPreferences? _prefs;

  bool get enabled => _enabled && isAvailable;

  void initialize(SharedPreferences prefs) {
    if (!isAvailable) return;
    _prefs = prefs;
    _enabled = prefs.getBool(_enabledKey) ?? false;
    notifyListeners();
  }

  void setEnabled(bool value) {
    if (!isAvailable || _enabled == value) return;
    _enabled = value;
    _prefs?.setBool(_enabledKey, value);
    notifyListeners();
  }

  /// The premium answer for OUR OWN account. The overlay only ever ADDS
  /// premium: when the switch is off the real server value passes through
  /// untouched — a non-opted build never downgrades a genuine Premium
  /// account, it simply has no overlay at all.
  bool premiumForMe(bool serverValue) => enabled || serverValue;
}
