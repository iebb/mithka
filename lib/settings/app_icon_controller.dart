import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../pro/mithka_pro_service.dart';

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
    darkAsset: 'assets/app_icons/white_dark.png',
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
  ),
  pilot(
    key: 'pilot',
    labelKey: AppStringKeys.appIconPilot,
    asset: 'assets/app_icons/pilot.png',
    darkAsset: 'assets/app_icons/pilot_dark.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  headphones(
    key: 'headphones',
    labelKey: AppStringKeys.appIconHeadphones,
    asset: 'assets/app_icons/headphones.png',
    darkAsset: 'assets/app_icons/headphones_dark.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  winter(
    key: 'winter',
    labelKey: AppStringKeys.appIconWinter,
    asset: 'assets/app_icons/winter.png',
    darkAsset: 'assets/app_icons/winter_dark.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  astronaut(
    key: 'astronaut',
    labelKey: AppStringKeys.appIconAstronaut,
    asset: 'assets/app_icons/astronaut.png',
    darkAsset: 'assets/app_icons/astronaut_dark.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  crown(
    key: 'crown',
    labelKey: AppStringKeys.appIconCrown,
    asset: 'assets/app_icons/crown.png',
    darkAsset: 'assets/app_icons/crown_dark.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  party(
    key: 'party',
    labelKey: AppStringKeys.appIconParty,
    asset: 'assets/app_icons/party.png',
    darkAsset: 'assets/app_icons/party_dark.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  sleepy(
    key: 'sleepy',
    labelKey: AppStringKeys.appIconSleepy,
    asset: 'assets/app_icons/sleepy.png',
    darkAsset: 'assets/app_icons/sleepy_dark.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  heart(
    key: 'heart',
    labelKey: AppStringKeys.appIconHeart,
    asset: 'assets/app_icons/heart.png',
    darkAsset: 'assets/app_icons/heart_dark.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  coffee(
    key: 'coffee',
    labelKey: AppStringKeys.appIconCoffee,
    asset: 'assets/app_icons/coffee.png',
    darkAsset: 'assets/app_icons/coffee_dark.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  detective(
    key: 'detective',
    labelKey: AppStringKeys.appIconDetective,
    asset: 'assets/app_icons/detective.png',
    darkAsset: 'assets/app_icons/detective_dark.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  gamer(
    key: 'gamer',
    labelKey: AppStringKeys.appIconGamer,
    asset: 'assets/app_icons/gamer.png',
    darkAsset: 'assets/app_icons/gamer_dark.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  fishing(
    key: 'fishing',
    labelKey: AppStringKeys.appIconFishing,
    asset: 'assets/app_icons/fishing.png',
    darkAsset: 'assets/app_icons/fishing_dark.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  );

  const AppIconVariant({
    required this.key,
    required this.labelKey,
    required this.asset,
    required this.colors,
    this.requiresSupporter = false,
    this.darkAsset,
  });

  final String key;
  final String labelKey;
  final String asset;
  final List<Color> colors;
  final bool requiresSupporter;
  final String? darkAsset;

  String previewAsset(Brightness brightness) =>
      brightness == Brightness.dark ? darkAsset ?? asset : asset;

  static List<AppIconVariant> forPlatform(TargetPlatform platform) => values
      .where(
        (variant) =>
            !variant.requiresSupporter ||
            supporterIconsAvailableForPlatform(platform),
      )
      .toList(growable: false);

  static AppIconVariant fromKey(String? key) => values.firstWhere(
    (variant) => variant.key == key,
    orElse: () => AppIconVariant.defaultIcon,
  );
}

bool appIconPickerAvailableForPlatform(
  TargetPlatform platform, {
  bool isWeb = kIsWeb,
}) =>
    !isWeb &&
    switch (platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS => true,
      TargetPlatform.fuchsia ||
      TargetPlatform.linux ||
      TargetPlatform.windows => false,
    };

class AppIconController extends ChangeNotifier {
  AppIconController(
    this._prefs, {
    MithkaProService? proService,
    TargetPlatform? platform,
  }) : _pro = proService ?? MithkaProService.shared,
       _platform = platform ?? defaultTargetPlatform {
    _pro.addListener(_entitlementChanged);
  }

  static const _channel = MethodChannel('mithka/app_icon');
  static const _selectedKey = 'selected_app_icon';

  final SharedPreferences _prefs;
  final MithkaProService _pro;
  final TargetPlatform _platform;
  bool _disposed = false;

  bool get supporterAvailable => supporterIconsAvailableForPlatform(_platform);
  bool get activeSupporter => _pro.isPro;
  MithkaProService get proService => _pro;
  List<AppIconVariant> get availableVariants =>
      AppIconVariant.forPlatform(_platform);
  bool isLocked(AppIconVariant icon) =>
      icon.requiresSupporter && icon != _variant && !activeSupporter;

  void _entitlementChanged() {
    if (!_disposed) notifyListeners();
  }

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
    if (!_supported || _loading || _disposed) return false;
    if (next.requiresSupporter && !supporterAvailable) return false;
    // Retain an already-applied paid icon after expiry; never reset native state.
    if (next == _variant && !next.requiresSupporter) return true;
    _loading = true;
    notifyListeners();
    try {
      if (next.requiresSupporter) {
        final verified = await _pro.refreshEntitlement();
        if (!verified || !_pro.isPro) return false;
      }
      if (_disposed) return false;
      if (next == _variant) return true;
      await _channel.invokeMethod<void>('setIcon', {'name': next.key});
      _variant = next;
      return await _prefs.setString(_selectedKey, next.key);
    } catch (_) {
      // A rejected native change does not persist or optimistically select it.
      return false;
    } finally {
      _loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pro.removeListener(_entitlementChanged);
    super.dispose();
  }
}
