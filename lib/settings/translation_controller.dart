//
//  translation_controller.dart
//
//  Persisted message translation preferences.
//

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class TranslationLanguage {
  const TranslationLanguage(this.code, this.label);

  final String code;
  final String label;
}

enum TranslationProvider {
  tdlib('tdlib', 'Telegram 翻译'),
  iosSystem('ios_system', '系统翻译'),
  androidMlKit('android_mlkit', 'ML Kit（本地）'),
  myMemory('my_memory', 'MyMemory'),
  lingva('lingva', 'Lingva'),
  libreTranslate('libre_translate', 'LibreTranslate');

  const TranslationProvider(this.storageValue, this.label);

  final String storageValue;
  final String label;
  bool get isNative =>
      this == TranslationProvider.iosSystem ||
      this == TranslationProvider.androidMlKit;

  static const selectableProviders = <TranslationProvider>[
    tdlib,
    iosSystem,
    androidMlKit,
    myMemory,
    lingva,
    libreTranslate,
  ];

  static TranslationProvider fromStorage(String? value) {
    if (value == 'native_on_device') return tdlib;
    return selectableProviders.firstWhere(
      (provider) => provider.storageValue == value,
      orElse: () => tdlib,
    );
  }
}

class TranslationController extends ChangeNotifier {
  TranslationController(this._prefs)
    : _enabled = _prefs.getBool(_enabledKey) ?? false,
      _provider = TranslationProvider.fromStorage(
        _prefs.getString(_providerKey),
      ),
      _targetLanguageCode = _normalizeTargetLanguage(
        _prefs.getString(_targetLanguageKey),
      ),
      _lingvaEndpoint =
          _prefs.getString(_lingvaEndpointKey) ?? defaultLingvaEndpoint,
      _libreTranslateEndpoint =
          _prefs.getString(_libreTranslateEndpointKey) ?? '',
      _libreTranslateApiKey = _prefs.getString(_libreTranslateApiKeyKey) ?? '';

  static const _enabledKey = 'translation.enabled';
  static const _providerKey = 'translation.provider';
  static const _targetLanguageKey = 'translation.targetLanguage';
  static const _lingvaEndpointKey = 'translation.lingvaEndpoint';
  static const _libreTranslateEndpointKey =
      'translation.libreTranslateEndpoint';
  static const _libreTranslateApiKeyKey = 'translation.libreTranslateApiKey';

  static const defaultLingvaEndpoint = 'https://lingva.ml';

  static const targetLanguages = <TranslationLanguage>[
    TranslationLanguage('zh-Hans', '简体中文'),
    TranslationLanguage('zh-Hant', '繁體中文'),
    TranslationLanguage('en', 'English'),
    TranslationLanguage('ja', '日本語'),
    TranslationLanguage('ko', '한국어'),
    TranslationLanguage('fr', 'Français'),
    TranslationLanguage('de', 'Deutsch'),
    TranslationLanguage('es', 'Español'),
    TranslationLanguage('ru', 'Русский'),
    TranslationLanguage('ar', 'العربية'),
    TranslationLanguage('pt', 'Português'),
    TranslationLanguage('it', 'Italiano'),
    TranslationLanguage('tr', 'Türkçe'),
    TranslationLanguage('vi', 'Tiếng Việt'),
    TranslationLanguage('th', 'ไทย'),
    TranslationLanguage('id', 'Indonesia'),
    TranslationLanguage('ms', 'Melayu'),
    TranslationLanguage('hi', 'हिन्दी'),
    TranslationLanguage('uk', 'Українська'),
  ];

  final SharedPreferences _prefs;
  bool _enabled;
  TranslationProvider _provider;
  String _targetLanguageCode;
  String _lingvaEndpoint;
  String _libreTranslateEndpoint;
  String _libreTranslateApiKey;

  bool get enabled => _enabled;
  TranslationProvider get provider => _provider;
  String get providerLabel => _provider.label;
  String get targetLanguageCode => _targetLanguageCode;
  String get lingvaEndpoint => _lingvaEndpoint;
  String get libreTranslateEndpoint => _libreTranslateEndpoint;
  String get libreTranslateApiKey => _libreTranslateApiKey;

  String get targetLanguageLabel => labelForTarget(_targetLanguageCode);

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    _prefs.setBool(_enabledKey, value);
    notifyListeners();
  }

  set provider(TranslationProvider value) {
    if (_provider == value) return;
    _provider = value;
    _prefs.setString(_providerKey, value.storageValue);
    notifyListeners();
  }

  set targetLanguageCode(String value) {
    value = _normalizeTargetLanguage(value);
    if (_targetLanguageCode == value) return;
    _targetLanguageCode = value;
    _prefs.setString(_targetLanguageKey, value);
    notifyListeners();
  }

  set lingvaEndpoint(String value) {
    final normalized = normalizeEndpoint(value);
    if (_lingvaEndpoint == normalized) return;
    _lingvaEndpoint = normalized;
    _prefs.setString(_lingvaEndpointKey, normalized);
    notifyListeners();
  }

  set libreTranslateEndpoint(String value) {
    final normalized = normalizeEndpoint(value);
    if (_libreTranslateEndpoint == normalized) return;
    _libreTranslateEndpoint = normalized;
    _prefs.setString(_libreTranslateEndpointKey, normalized);
    notifyListeners();
  }

  set libreTranslateApiKey(String value) {
    final normalized = value.trim();
    if (_libreTranslateApiKey == normalized) return;
    _libreTranslateApiKey = normalized;
    _prefs.setString(_libreTranslateApiKeyKey, normalized);
    notifyListeners();
  }

  static String labelForTarget(String code) => targetLanguages
      .firstWhere(
        (l) => l.code == _normalizeTargetLanguage(code),
        orElse: () => const TranslationLanguage('zh-Hans', '简体中文'),
      )
      .label;

  static String _normalizeTargetLanguage(String? code) =>
      code == null || code.isEmpty || code == 'auto' ? 'zh-Hans' : code;

  static String? normalizeLanguageCode(String? code) {
    if (code == null || code.isEmpty) return null;
    final lower = code.toLowerCase();
    if (lower.startsWith('zh')) return 'zh';
    return lower.split('-').first;
  }

  static String normalizeEndpoint(String value) =>
      value.trim().replaceFirst(RegExp(r'/+$'), '');
}
