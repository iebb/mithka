//
//  theme_controller.dart
//
//  Drives the app-wide appearance (跟随系统 / 浅色 / 深色), bottom tab-bar style,
//  text scale, and chat appearance preferences. Values are persisted in
//  SharedPreferences and applied through providers at the app root.
//

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

enum AppearanceMode {
  system('跟随系统', Icons.contrast),
  light('浅色', Icons.light_mode),
  dark('深色', Icons.dark_mode);

  const AppearanceMode(this.label, this.icon);
  final String label;
  final IconData icon;

  ThemeMode get themeMode => switch (this) {
    AppearanceMode.system => ThemeMode.system,
    AppearanceMode.light => ThemeMode.light,
    AppearanceMode.dark => ThemeMode.dark,
  };
}

/// Classic flat bar (default) or the system tab bar.
enum TabBarStyle {
  classic('经典', Icons.view_week),
  system('系统', Icons.auto_awesome);

  const TabBarStyle(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum UnreadBadgeMode {
  messages('未读消息数', Icons.mark_chat_unread),
  chats('未读会话数', Icons.forum);

  const UnreadBadgeMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

class ThemeController extends ChangeNotifier {
  ThemeController(this._prefs) {
    _mode = AppearanceMode.values.firstWhere(
      (m) => m.name == _prefs.getString(_modeKey),
      orElse: () => AppearanceMode.system,
    );
    _tabBarStyle = TabBarStyle.values.firstWhere(
      (s) => s.name == _prefs.getString(_tabKey),
      orElse: () => TabBarStyle.classic, // flat bar by default
    );
    _brandColor = Color(
      _prefs.getInt(_brandKey) ?? (0xFF000000 | AppTheme.defaultBrand),
    );
    _fontScale = _prefs.getDouble(_fontKey) ?? 1.0;
    _circularGroupAvatars = _prefs.getBool(_groupAvatarCircleKey) ?? true;
    _showChatFolderFilter = _prefs.getBool(_chatFolderFilterKey) ?? false;
    _showMemberTags = _prefs.getBool(_memberTagsKey) ?? false;
    _showPremiumNameColors = _prefs.getBool(_premiumNameColorsKey) ?? true;
    _showPremiumEmojiStatus = _prefs.getBool(_premiumEmojiStatusKey) ?? true;
    _groupImageMessages = _prefs.getBool(_groupImageMessagesKey) ?? false;
    _unreadBadgeMode = UnreadBadgeMode.values.firstWhere(
      (m) => m.name == _prefs.getString(_unreadBadgeModeKey),
      orElse: () => UnreadBadgeMode.messages,
    );
    AppTheme.applyBrand(_brandColor); // before the first MaterialApp build
  }

  static const _modeKey = 'appearanceMode';
  static const _tabKey = 'tabBarStyle';
  static const _brandKey = 'brandColor';
  static const _fontKey = 'fontScale';
  static const _groupAvatarCircleKey = 'circularGroupAvatars';
  static const _chatFolderFilterKey = 'showChatFolderFilter';
  static const _memberTagsKey = 'showMemberTags';
  static const _premiumNameColorsKey = 'showPremiumNameColors';
  static const _premiumEmojiStatusKey = 'showPremiumEmojiStatus';
  static const _groupImageMessagesKey = 'groupImageMessages';
  static const _unreadBadgeModeKey = 'unreadBadgeMode';

  /// Selectable text-scale steps for the 字体大小 control (小 / 标准 / 大 / 超大).
  /// Capped at 1.3 so fixed-height chrome doesn't overflow badly.
  static const List<double> fontScaleSteps = [0.85, 1.0, 1.15, 1.3];

  final SharedPreferences _prefs;
  late AppearanceMode _mode;
  late TabBarStyle _tabBarStyle;
  late Color _brandColor;
  late double _fontScale;
  late bool _circularGroupAvatars;
  bool _showChatFolderFilter = false;
  bool _showMemberTags = false;
  bool _showPremiumNameColors = true;
  bool _showPremiumEmojiStatus = true;
  bool _groupImageMessages = false;
  late UnreadBadgeMode _unreadBadgeMode;

  AppearanceMode get mode => _mode;
  TabBarStyle get tabBarStyle => _tabBarStyle;
  ThemeMode get themeMode => _mode.themeMode;
  Color get brandColor => _brandColor;
  bool get circularGroupAvatars => _circularGroupAvatars;
  bool get showChatFolderFilter => _showChatFolderFilter;
  bool get showMemberTags => _showMemberTags;
  bool get showPremiumNameColors => _showPremiumNameColors;
  bool get showPremiumEmojiStatus => _showPremiumEmojiStatus;
  bool get groupImageMessages => _groupImageMessages;
  UnreadBadgeMode get unreadBadgeMode => _unreadBadgeMode;

  /// App-wide text scale factor, applied at the root via MediaQuery.textScaler.
  double get fontScale => _fontScale;

  set mode(AppearanceMode value) {
    _mode = value;
    _prefs.setString(_modeKey, value.name);
    notifyListeners();
  }

  set tabBarStyle(TabBarStyle value) {
    _tabBarStyle = value;
    _prefs.setString(_tabKey, value.name);
    notifyListeners();
  }

  /// The app's accent / brand color. Persisted and applied app-wide.
  set brandColor(Color value) {
    _brandColor = value;
    _prefs.setInt(_brandKey, value.toARGB32());
    AppTheme.applyBrand(value);
    notifyListeners();
  }

  set fontScale(double value) {
    _fontScale = value;
    _prefs.setDouble(_fontKey, value);
    notifyListeners();
  }

  set circularGroupAvatars(bool value) {
    _circularGroupAvatars = value;
    _prefs.setBool(_groupAvatarCircleKey, value);
    notifyListeners();
  }

  set showChatFolderFilter(bool value) {
    _showChatFolderFilter = value;
    _prefs.setBool(_chatFolderFilterKey, value);
    notifyListeners();
  }

  set showMemberTags(bool value) {
    _showMemberTags = value;
    _prefs.setBool(_memberTagsKey, value);
    notifyListeners();
  }

  set showPremiumNameColors(bool value) {
    _showPremiumNameColors = value;
    _prefs.setBool(_premiumNameColorsKey, value);
    notifyListeners();
  }

  set showPremiumEmojiStatus(bool value) {
    _showPremiumEmojiStatus = value;
    _prefs.setBool(_premiumEmojiStatusKey, value);
    notifyListeners();
  }

  set groupImageMessages(bool value) {
    _groupImageMessages = value;
    _prefs.setBool(_groupImageMessagesKey, value);
    notifyListeners();
  }

  set unreadBadgeMode(UnreadBadgeMode value) {
    _unreadBadgeMode = value;
    _prefs.setString(_unreadBadgeModeKey, value.name);
    notifyListeners();
  }
}
