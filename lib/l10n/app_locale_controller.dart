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
      label: '简体中文',
    ),
    AppLocaleOption(
      locale: Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      label: '繁體中文',
    ),
    AppLocaleOption(locale: Locale('ja'), label: '日本語'),
    AppLocaleOption(locale: Locale('ko'), label: '한국어'),
    AppLocaleOption(locale: Locale('en'), label: 'English'),
    AppLocaleOption(locale: Locale('fr'), label: 'Français'),
    AppLocaleOption(locale: Locale('es'), label: 'Español'),
    AppLocaleOption(locale: Locale('de'), label: 'Deutsch'),
  ];

  final SharedPreferences _prefs;
  Locale? _locale;

  Locale? get locale => _locale;
  bool get followsSystem => _locale == null;

  String selectedLabel(BuildContext context) {
    if (_locale == null) return '跟随系统'.l10n(context);
    return labelFor(_locale!);
  }

  set locale(Locale? value) {
    final normalized = value == null ? null : AppLocalizations.resolve(value);
    if (_sameLocale(_locale, normalized)) return;
    _locale = normalized;
    if (normalized == null) {
      _prefs.remove(_localeKey);
    } else {
      _prefs.setString(_localeKey, normalized.toLanguageTag());
    }
    notifyListeners();
  }

  static String labelFor(Locale locale) {
    final normalized = AppLocalizations.resolve(locale);
    return options
        .firstWhere(
          (option) => _sameLocale(option.locale, normalized),
          orElse: () => options.first,
        )
        .label;
  }

  static Locale? _localeFromTag(String? tag) {
    if (tag == null || tag.isEmpty || tag == 'system') return null;
    final normalized = tag.replaceAll('_', '-');
    if (normalized == 'zh-Hant') {
      return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
    }
    if (normalized == 'zh-Hans' || normalized == 'zh') {
      return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
    }
    final language = normalized.split('-').first;
    final locale = Locale(language);
    if (!AppLocalizations.isSupportedLocale(locale)) return null;
    return AppLocalizations.resolve(locale);
  }

  static bool _sameLocale(Locale? a, Locale? b) =>
      a?.languageCode == b?.languageCode &&
      a?.scriptCode == b?.scriptCode &&
      a?.countryCode == b?.countryCode;
}
