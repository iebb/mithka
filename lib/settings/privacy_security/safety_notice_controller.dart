import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool shouldShowSafetyNotice({
  required bool restricted,
  required bool disabled,
  required bool acknowledged,
}) => restricted && !disabled && !acknowledged;

/// Local preference for the Telegram Terms-of-Service safety notice overlay.
class SafetyNoticeController extends ChangeNotifier {
  SafetyNoticeController(this._prefs)
    : _disabled = _prefs.getBool(_disabledKey) ?? false;

  static const _disabledKey = 'safety_notice.disabled';

  final SharedPreferences _prefs;
  bool _disabled;

  /// The opt-out defaults to false, preserving the notice for existing users.
  bool get disabled => _disabled;

  set disabled(bool value) {
    if (_disabled == value) return;
    _disabled = value;
    unawaited(_prefs.setBool(_disabledKey, value));
    notifyListeners();
  }
}
