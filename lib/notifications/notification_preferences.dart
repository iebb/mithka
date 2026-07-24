import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum NotificationAccountMode { all, current, selected }

class NotificationPreferences extends ChangeNotifier {
  NotificationPreferences._();

  static final NotificationPreferences shared = NotificationPreferences._();

  static const _allAccountsKey = 'mithka.notifications.allAccounts.v1';
  static const _accountModeKey = 'mithka.notifications.accountMode.v2';
  static const _selectedAccountIdsKey =
      'mithka.notifications.selectedAccountIds.v2';
  static const _inAppSoundsKey = 'mithka.notifications.inAppSounds.v1';
  static const _inAppVibrateKey = 'mithka.notifications.inAppVibrate.v1';
  static const _inAppPreviewKey = 'mithka.notifications.inAppPreview.v1';
  static const _namesOnLockScreenKey =
      'mithka.notifications.namesOnLockScreen.v1';

  SharedPreferences? _preferences;
  NotificationAccountMode _accountMode = NotificationAccountMode.all;
  Set<int> _selectedAccountIds = {};
  bool _inAppSounds = true;
  bool _inAppVibrate = false;
  bool _inAppPreview = true;
  bool _namesOnLockScreen = true;

  NotificationAccountMode get accountMode => _accountMode;
  Set<int> get selectedAccountIds => Set.unmodifiable(_selectedAccountIds);
  bool get allAccounts => _accountMode == NotificationAccountMode.all;
  bool get inAppSounds => _inAppSounds;
  bool get inAppVibrate => _inAppVibrate;
  bool get inAppPreview => _inAppPreview;
  bool get namesOnLockScreen => _namesOnLockScreen;

  void initialize(SharedPreferences preferences) {
    _preferences = preferences;
    final storedMode = preferences.getString(_accountModeKey);
    _accountMode = NotificationAccountMode.values.firstWhere(
      (mode) => mode.name == storedMode,
      orElse: () => (preferences.getBool(_allAccountsKey) ?? true)
          ? NotificationAccountMode.all
          : NotificationAccountMode.current,
    );
    _selectedAccountIds =
        (preferences.getStringList(_selectedAccountIdsKey) ?? const <String>[])
            .map(int.tryParse)
            .whereType<int>()
            .toSet();
    if (_accountMode == NotificationAccountMode.selected &&
        _selectedAccountIds.isEmpty) {
      _accountMode = NotificationAccountMode.current;
    }
    _inAppSounds = preferences.getBool(_inAppSoundsKey) ?? true;
    _inAppVibrate = preferences.getBool(_inAppVibrateKey) ?? false;
    _inAppPreview = preferences.getBool(_inAppPreviewKey) ?? true;
    _namesOnLockScreen = preferences.getBool(_namesOnLockScreenKey) ?? true;
  }

  Future<void> setAllAccounts(bool value) => setAccountMode(
    value ? NotificationAccountMode.all : NotificationAccountMode.current,
  );

  Future<void> setAccountMode(
    NotificationAccountMode value, {
    Iterable<int> defaultSelectedAccountIds = const [],
  }) async {
    if (value == NotificationAccountMode.selected &&
        _selectedAccountIds.isEmpty) {
      _selectedAccountIds = defaultSelectedAccountIds.toSet();
      await _persistSelectedAccountIds();
    }
    if (_accountMode == value) return;
    _accountMode = value;
    notifyListeners();
    await _preferences?.setString(_accountModeKey, value.name);
    await _preferences?.setBool(
      _allAccountsKey,
      value == NotificationAccountMode.all,
    );
  }

  Future<void> setSelectedAccountIds(Iterable<int> values) async {
    final normalized = values.toSet();
    if (setEquals(normalized, _selectedAccountIds)) return;
    _selectedAccountIds = normalized;
    notifyListeners();
    await _persistSelectedAccountIds();
  }

  Future<void> removeAccount(int userId) async {
    if (!_selectedAccountIds.contains(userId)) return;
    final remaining = _selectedAccountIds.toSet()..remove(userId);
    _selectedAccountIds = remaining;
    if (_accountMode == NotificationAccountMode.selected && remaining.isEmpty) {
      _accountMode = NotificationAccountMode.current;
      await _preferences?.setString(
        _accountModeKey,
        NotificationAccountMode.current.name,
      );
    }
    notifyListeners();
    await _persistSelectedAccountIds();
  }

  bool receivesNotificationsFrom({
    required int userId,
    required bool isActiveAccount,
  }) => switch (_accountMode) {
    NotificationAccountMode.all => true,
    NotificationAccountMode.current => isActiveAccount,
    NotificationAccountMode.selected => _selectedAccountIds.contains(userId),
  };

  Future<void> _persistSelectedAccountIds() async {
    final values = _selectedAccountIds.map((id) => '$id').toList()..sort();
    await _preferences?.setStringList(_selectedAccountIdsKey, values);
  }

  Future<void> setInAppSounds(bool value) => _set(
    value: value,
    current: _inAppSounds,
    apply: () => _inAppSounds = value,
    key: _inAppSoundsKey,
  );

  Future<void> setInAppVibrate(bool value) => _set(
    value: value,
    current: _inAppVibrate,
    apply: () => _inAppVibrate = value,
    key: _inAppVibrateKey,
  );

  Future<void> setInAppPreview(bool value) => _set(
    value: value,
    current: _inAppPreview,
    apply: () => _inAppPreview = value,
    key: _inAppPreviewKey,
  );

  Future<void> setNamesOnLockScreen(bool value) => _set(
    value: value,
    current: _namesOnLockScreen,
    apply: () => _namesOnLockScreen = value,
    key: _namesOnLockScreenKey,
  );

  Future<void> _set({
    required bool value,
    required bool current,
    required VoidCallback apply,
    required String key,
  }) async {
    if (value == current) return;
    apply();
    notifyListeners();
    await _preferences?.setBool(key, value);
  }
}
