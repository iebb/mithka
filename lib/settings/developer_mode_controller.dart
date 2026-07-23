//
//  developer_mode_controller.dart
//
//  Hidden diagnostics toggles for local device debugging. The entry point is
//  unlocked by tapping the About version label repeatedly.
//

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeveloperModeController extends ChangeNotifier {
  DeveloperModeController(this._prefs)
    : _unlocked = _prefs.getBool(_unlockedKey) ?? false;

  static const _unlockedKey = 'developer_mode.unlocked';

  final SharedPreferences _prefs;
  bool _unlocked;

  bool get unlocked => _unlocked;

  Future<void> unlock() async {
    if (_unlocked) return;
    _unlocked = true;
    await _prefs.setBool(_unlockedKey, true);
    notifyListeners();
  }
}
