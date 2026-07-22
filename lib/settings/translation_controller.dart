//
//  translation_controller.dart
//
//  Persisted message translation preferences.
//

import 'package:flutter/foundation.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_translation_prompt.dart';

class TranslationLanguage {
  const TranslationLanguage(this.code, this.label);

  final String code;
  final String label;
}

enum TranslationProvider {
  tdlib('tdlib', AppStringKeys.translationTelegram),
  iosSystem('ios_system', AppStringKeys.translationSystem),
  androidMlKit('android_mlkit', AppStringKeys.translationMlKitLocal),
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
      _translateChats = _prefs.getBool(_translateChatsKey) ?? true,
      _aiTranslationEnabled = _prefs.getBool(_aiTranslationEnabledKey) ?? false,
      _aiTranslationPrompt = normalizeAiTranslationPrompt(
        _prefs.getString(aiTranslationPromptPreferenceKey),
      ),
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
      _libreTranslateApiKey = _prefs.getString(_libreTranslateApiKeyKey) ?? '',
      _ignoredLanguageCodes = {...?_prefs.getStringList(_ignoredLanguagesKey)},
      _autoTranslateChatIds = {...?_prefs.getStringList(_autoChatsKey)},
      _dismissedAutoTranslateChatIds = {
        ...?_prefs.getStringList(_dismissedAutoChatsKey),
      };

  static const _enabledKey = 'translation.enabled';
  static const _translateChatsKey = 'translation.translateChats';
  static const _aiTranslationEnabledKey = 'translation.ai.enabled';
  static const aiTranslationPromptPreferenceKey = 'translation.ai.prompt.v1';
  static const _providerKey = 'translation.provider';
  static const _targetLanguageKey = 'translation.targetLanguage';
  static const _lingvaEndpointKey = 'translation.lingvaEndpoint';
  static const _libreTranslateEndpointKey =
      'translation.libreTranslateEndpoint';
  static const _libreTranslateApiKeyKey = 'translation.libreTranslateApiKey';
  static const _ignoredLanguagesKey = 'translation.ignoredLanguages';
  static const _autoChatsKey = 'translation.autoChats';
  static const _dismissedAutoChatsKey = 'translation.dismissedAutoChats';

  static const defaultLingvaEndpoint = 'https://lingva.ml';

  static const targetLanguages = <TranslationLanguage>[
    TranslationLanguage('zh-Hans', AppStringKeys.appLocaleSimplifiedChinese),
    TranslationLanguage('zh-Hant', AppStringKeys.appLocaleTraditionalChinese),
    TranslationLanguage('en', AppStringKeys.appLocaleEnglish),
    TranslationLanguage('ja', AppStringKeys.appLocaleJapanese),
    TranslationLanguage('ko', AppStringKeys.appLocaleKorean),
    TranslationLanguage('fr', AppStringKeys.appLocaleFrench),
    TranslationLanguage('de', AppStringKeys.appLocaleGerman),
    TranslationLanguage('es', AppStringKeys.appLocaleSpanish),
    TranslationLanguage('ru', AppStringKeys.appLocaleRussian),
    TranslationLanguage('ar', AppStringKeys.appLocaleArabic),
    TranslationLanguage('pt', AppStringKeys.appLocalePortuguese),
    TranslationLanguage('it', AppStringKeys.appLocaleItalian),
    TranslationLanguage('tr', AppStringKeys.appLocaleTurkish),
    TranslationLanguage('vi', AppStringKeys.appLocaleVietnamese),
    TranslationLanguage('th', AppStringKeys.appLocaleThai),
    TranslationLanguage('id', AppStringKeys.appLocaleIndonesian),
    TranslationLanguage('ms', AppStringKeys.appLocaleMalay),
    TranslationLanguage('hi', AppStringKeys.appLocaleHindi),
    TranslationLanguage('uk', AppStringKeys.appLocaleUkrainian),
  ];

  final SharedPreferences _prefs;
  bool _enabled;
  bool _translateChats;
  bool _aiTranslationEnabled;
  String _aiTranslationPrompt;
  TranslationProvider _provider;
  String _targetLanguageCode;
  String _lingvaEndpoint;
  String _libreTranslateEndpoint;
  String _libreTranslateApiKey;
  final Set<String> _ignoredLanguageCodes;
  final Set<String> _autoTranslateChatIds;
  final Set<String> _dismissedAutoTranslateChatIds;

  bool get enabled => _enabled;
  bool get translateChats => _translateChats;
  bool get aiTranslationEnabled => _aiTranslationEnabled;
  String get aiTranslationPrompt => _aiTranslationPrompt;
  bool get hasCustomAiTranslationPrompt =>
      _aiTranslationPrompt != defaultAiTranslationPrompt.trim();
  TranslationProvider get provider => _provider;
  String get providerLabel => _provider.label;
  String get targetLanguageCode => _targetLanguageCode;
  String get lingvaEndpoint => _lingvaEndpoint;
  String get libreTranslateEndpoint => _libreTranslateEndpoint;
  String get libreTranslateApiKey => _libreTranslateApiKey;
  Set<String> get ignoredLanguageCodes =>
      Set.unmodifiable(_ignoredLanguageCodes);

  String get targetLanguageLabel => labelForTarget(_targetLanguageCode);

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    _prefs.setBool(_enabledKey, value);
    notifyListeners();
  }

  set translateChats(bool value) {
    if (_translateChats == value) return;
    _translateChats = value;
    _prefs.setBool(_translateChatsKey, value);
    notifyListeners();
  }

  set aiTranslationEnabled(bool value) {
    if (_aiTranslationEnabled == value) return;
    _aiTranslationEnabled = value;
    _prefs.setBool(_aiTranslationEnabledKey, value);
    notifyListeners();
  }

  void setAiTranslationPrompt(String value) {
    final normalized = normalizeAiTranslationPrompt(value);
    if (_aiTranslationPrompt == normalized) return;
    _aiTranslationPrompt = normalized;
    if (normalized == defaultAiTranslationPrompt.trim()) {
      _prefs.remove(aiTranslationPromptPreferenceKey);
    } else {
      _prefs.setString(aiTranslationPromptPreferenceKey, normalized);
    }
    notifyListeners();
  }

  void resetAiTranslationPrompt() =>
      setAiTranslationPrompt(defaultAiTranslationPrompt);

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

  bool autoTranslateEnabledFor(int chatId) =>
      _autoTranslateChatIds.contains('$chatId');

  void setAutoTranslateEnabledFor(int chatId, bool value) {
    final id = '$chatId';
    final changed = value
        ? _autoTranslateChatIds.add(id)
        : _autoTranslateChatIds.remove(id);
    if (!changed) return;
    if (value) {
      _dismissedAutoTranslateChatIds.remove(id);
      _persistStringSet(_dismissedAutoChatsKey, _dismissedAutoTranslateChatIds);
    }
    _persistStringSet(_autoChatsKey, _autoTranslateChatIds);
    notifyListeners();
  }

  bool autoTranslateSuggestionDismissedFor(int chatId) =>
      _dismissedAutoTranslateChatIds.contains('$chatId');

  void dismissAutoTranslateSuggestionFor(int chatId) {
    final id = '$chatId';
    final activeChanged = _autoTranslateChatIds.remove(id);
    final dismissedChanged = _dismissedAutoTranslateChatIds.add(id);
    if (!activeChanged && !dismissedChanged) return;
    if (activeChanged) {
      _persistStringSet(_autoChatsKey, _autoTranslateChatIds);
    }
    _persistStringSet(_dismissedAutoChatsKey, _dismissedAutoTranslateChatIds);
    notifyListeners();
  }

  void setIgnoredLanguage(String code, bool ignored) {
    final normalized = normalizeLanguageCode(code);
    if (normalized == null) return;
    final changed = ignored
        ? _ignoredLanguageCodes.add(normalized)
        : _ignoredLanguageCodes.remove(normalized);
    if (!changed) return;
    _persistStringSet(_ignoredLanguagesKey, _ignoredLanguageCodes);
    notifyListeners();
  }

  bool shouldTranslateLanguage(String? sourceLanguageCode) {
    final source = normalizeLanguageCode(sourceLanguageCode);
    if (source == null || source == 'und') return true;
    final target = normalizeLanguageCode(_targetLanguageCode);
    if (source == target) return false;
    return !_ignoredLanguageCodes.contains(source);
  }

  void _persistStringSet(String key, Set<String> values) {
    final sorted = values.toList()..sort();
    _prefs.setStringList(key, sorted);
  }

  static String labelForTarget(String code) => targetLanguages
      .firstWhere(
        (l) => l.code == _normalizeTargetLanguage(code),
        orElse: () => const TranslationLanguage(
          'zh-Hans',
          AppStringKeys.appLocaleSimplifiedChinese,
        ),
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
