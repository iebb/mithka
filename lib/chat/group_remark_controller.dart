//
//  group_remark_controller.dart
//
//  Stores a private, on-device display name for a group. Remarks are scoped
//  to the stable Telegram user id as well as the chat id, so switching or
//  reusing TDLib account slots cannot expose one account's remarks to another.
//

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GroupRemarkController extends ChangeNotifier {
  GroupRemarkController(this._preferences, {int? initialAccountUserId})
    : _activeAccountUserId = initialAccountUserId;

  static const _preferencePrefix = 'mithka.groupRemark.v1.user';

  final SharedPreferences _preferences;
  int? _activeAccountUserId;

  int? get activeAccountUserId => _activeAccountUserId;
  bool get canPersist => _activeAccountUserId != null;

  void setActiveAccountUserId(int? userId) {
    if (_activeAccountUserId == userId) return;
    _activeAccountUserId = userId;
    notifyListeners();
  }

  String? remarkFor(int chatId) {
    final userId = _activeAccountUserId;
    if (userId == null) return null;
    return _normalized(_preferences.getString(_key(userId, chatId)));
  }

  String displayTitleFor(int chatId, String serverTitle) =>
      remarkFor(chatId) ?? serverTitle;

  Future<void> setRemark(int chatId, String value) async {
    final userId = _activeAccountUserId;
    if (userId == null) return;

    final key = _key(userId, chatId);
    final previous = _normalized(_preferences.getString(key));
    final next = _normalized(value);
    if (previous == next) return;

    if (next == null) {
      await _preferences.remove(key);
    } else {
      await _preferences.setString(key, next);
    }
    notifyListeners();
  }

  static String? _normalized(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static String _key(int userId, int chatId) =>
      '$_preferencePrefix.$userId.chat.$chatId';
}
