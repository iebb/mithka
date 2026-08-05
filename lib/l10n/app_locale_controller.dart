import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_localizations.dart';

class AppLocaleOption {
  const AppLocaleOption({required this.locale, required this.label});

  final Locale locale;
  final String label;

  String get tag => locale.toLanguageTag();
}

class AppLocaleController extends ChangeNotifier {
  AppLocaleController(this._prefs)
    : _locale = _localeFromTag(_prefs.getString(_localeKey));

  static const _localeKey = 'app.locale';

  static const options = <AppLocaleOption>[
    AppLocaleOption(
      locale: Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      label: AppStringKeys.appLocaleSimplifiedChinese,
    ),
    AppLocaleOption(
      locale: Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      label: AppStringKeys.appLocaleTraditionalChinese,
    ),
    AppLocaleOption(
      locale: Locale('ja'),
      label: AppStringKeys.appLocaleJapanese,
    ),
    AppLocaleOption(locale: Locale('ko'), label: AppStringKeys.appLocaleKorean),
    AppLocaleOption(
      locale: Locale('en'),
      label: AppStringKeys.appLocaleEnglish,
    ),
    AppLocaleOption(locale: Locale('fr'), label: AppStringKeys.appLocaleFrench),
    AppLocaleOption(
      locale: Locale('es'),
      label: AppStringKeys.appLocaleSpanish,
    ),
    AppLocaleOption(locale: Locale('de'), label: AppStringKeys.appLocaleGerman),
  ];

  final SharedPreferences _prefs;
  Locale? _locale;

  Locale? get locale => _locale;
  bool get followsSystem => _locale == null;

  String selectedLabel(BuildContext context) {
    if (_locale == null) {
      return AppStringKeys.appLocaleFollowSystem.l10n(context);
    }
    return labelFor(_locale!);
  }

  set locale(Locale? value) {
    final normalized = value == null ? null : AppLocalizations.resolve(value);
    if (_sameLocale(_locale, normalized)) return;
    _locale = normalized;
    AppStrings.setLocale(normalized ?? ui.PlatformDispatcher.instance.locale);
    if (normalized == null) {
      _prefs.remove(_localeKey);
    } else {
      _prefs.setString(_localeKey, normalized.toLanguageTag());
    }
    notifyListeners();
  }

  static String labelFor(Locale locale) {
    final normalized = AppLocalizations.resolve(locale);
    final option = options.firstWhere(
      (option) => _sameLocale(option.locale, normalized),
      orElse: () => options.first,
    );
    return AppStrings.t(option.label);
  }

  static Locale? _localeFromTag(String? tag) {
    final locale = AppLocalizations.localeFromTag(tag);
    if (locale == null) return null;
    if (!AppLocalizations.isSupportedLocale(locale)) return null;
    return AppLocalizations.resolve(locale);
  }

  static bool _sameLocale(Locale? a, Locale? b) =>
      a?.languageCode == b?.languageCode &&
      a?.scriptCode == b?.scriptCode &&
      a?.countryCode == b?.countryCode;
}
