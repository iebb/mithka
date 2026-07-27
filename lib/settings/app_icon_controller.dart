import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';

enum AppIconVariant {
  defaultIcon(
    key: 'default',
    labelKey: AppStringKeys.appIconDefault,
    asset: 'assets/app_icons/default.png',
    colors: [Color(0xFFFF8F6E), Color(0xFF7C76F7)],
  ),
  white(
    key: 'white',
    labelKey: AppStringKeys.appIconWhite,
    asset: 'assets/app_icons/white.png',
    colors: [Color(0xFFFFFFFF), Color(0xFFEAF2FF)],
  ),
  blue(
    key: 'blue',
    labelKey: AppStringKeys.appIconBlueGradient,
    asset: 'assets/app_icons/blue.png',
    colors: [Color(0xFF1DB5FF), Color(0xFF224BFF)],
  ),
  purple(
    key: 'purple',
    labelKey: AppStringKeys.appIconPurpleGradient,
    asset: 'assets/app_icons/purple.png',
    colors: [Color(0xFFF76AFF), Color(0xFF4D31C9)],
  ),
  pixel(
    key: 'pixel',
    labelKey: AppStringKeys.appIconPixel,
    asset: 'assets/app_icons/pixel.png',
    colors: [Color(0xFF1A2034), Color(0xFF11B0D4)],
  ),
  aurora(
    key: 'aurora',
    labelKey: AppStringKeys.appIconAurora,
    asset: 'assets/app_icons/aurora.png',
    colors: [Color(0xFF071F42), Color(0xFF13B6C7)],
  ),
  prism(
    key: 'prism',
    labelKey: AppStringKeys.appIconPrism,
    asset: 'assets/app_icons/prism.png',
    colors: [Color(0xFF352873), Color(0xFFFF76CE)],
  ),
  signal(
    key: 'signal',
    labelKey: AppStringKeys.appIconSignal,
    asset: 'assets/app_icons/signal.png',
    colors: [Color(0xFFFF4F65), Color(0xFF7B183C)],
  );

  const AppIconVariant({
    required this.key,
    required this.labelKey,
    required this.asset,
    required this.colors,
  });

  final String key;
  final String labelKey;
  final String asset;
  final List<Color> colors;

  static AppIconVariant fromKey(String? key) => values.firstWhere(
    (variant) => variant.key == key,
    orElse: () => AppIconVariant.defaultIcon,
  );
}

class AppIconController extends ChangeNotifier {
  AppIconController(this._prefs);

  static const _channel = MethodChannel('mithka/app_icon');
  static const _selectedKey = 'selected_app_icon';

  final SharedPreferences _prefs;
  AppIconVariant _variant = AppIconVariant.defaultIcon;
  bool _supported = false;
  bool _loading = false;

  AppIconVariant get variant => _variant;
  bool get supported => _supported;
  bool get loading => _loading;

  Future<void> initialize() async {
    _variant = AppIconVariant.fromKey(_prefs.getString(_selectedKey));
    try {
      _supported = await _channel.invokeMethod<bool>('isSupported') ?? false;
      final current = await _channel.invokeMethod<String>('currentIcon');
      if (current != null && current.isNotEmpty) {
        _variant = AppIconVariant.fromKey(current);
        unawaited(_prefs.setString(_selectedKey, _variant.key));
      } else {
        unawaited(_prefs.setString(_selectedKey, _variant.key));
      }
    } catch (_) {
      _supported = false;
    }
    notifyListeners();
  }

  Future<bool> setVariant(AppIconVariant next) async {
    if (_loading || next == _variant) return true;
    final previous = _variant;
    _variant = next;
    _loading = true;
    notifyListeners();
    try {
      await _channel.invokeMethod<void>('setIcon', {'name': next.key});
      await _prefs.setString(_selectedKey, next.key);
      return true;
    } catch (_) {
      _variant = previous;
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
