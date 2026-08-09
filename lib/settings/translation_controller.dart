//
//  translation_controller.dart
//
//  Persisted message translation preferences.
//

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/message_translation_cache.dart';
import 'ai_settings_controller.dart';
import 'ai_translation_prompt.dart';

class TranslationLanguage {
  const TranslationLanguage(this.code, this.label);

  final String code;
  final String label;
}

enum TranslationDisplayStyle {
  translatedOnly(
    'translated_only',
    AppStringKeys.translationDisplayTranslatedOnly,
  ),
  both('both', AppStringKeys.translationDisplayBoth),
  quote('quote', AppStringKeys.translationDisplayQuote);

  const TranslationDisplayStyle(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static TranslationDisplayStyle fromStorage(String? value) => values
      .firstWhere((style) => style.storageValue == value, orElse: () => quote);
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

abstract final class TranslationOptionIds {
  static const _providerPrefix = 'provider:';
  static const _aiPrefix = 'ai:';

  static String provider(TranslationProvider value) =>
      '$_providerPrefix${value.storageValue}';

  static String ai(String candidateId) => '$_aiPrefix$candidateId';

  static bool isAi(String value) => value.startsWith(_aiPrefix);
  static bool isProvider(String value) => value.startsWith(_providerPrefix);

  static String? aiCandidateId(String value) =>
      isAi(value) ? value.substring(_aiPrefix.length) : null;

  static TranslationProvider? translationProvider(String value) {
    if (!isProvider(value)) return null;
    final storage = value.substring(_providerPrefix.length);
    for (final provider in TranslationProvider.selectableProviders) {
      if (provider.storageValue == storage) return provider;
    }
    return null;
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
      _displayStyle = TranslationDisplayStyle.fromStorage(
        _prefs.getString(_displayStyleKey),
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
      } {
    _restoreTranslationOptions();
    _restoreTelegramCooldown();
    messageCache = MessageTranslationCache(_prefs);
    messageCache.pruneExpired();
  }

  static const _enabledKey = 'translation.enabled';
  static const _translateChatsKey = 'translation.translateChats';
  static const _aiTranslationEnabledKey = 'translation.ai.enabled';
  static const aiTranslationPromptPreferenceKey = 'translation.ai.prompt.v1';
  static const _providerKey = 'translation.provider';
  static const _targetLanguageKey = 'translation.targetLanguage';
  static const _displayStyleKey = 'translation.displayStyle';
  static const _lingvaEndpointKey = 'translation.lingvaEndpoint';
  static const _libreTranslateEndpointKey =
      'translation.libreTranslateEndpoint';
  static const _libreTranslateApiKeyKey = 'translation.libreTranslateApiKey';
  static const _ignoredLanguagesKey = 'translation.ignoredLanguages';
  static const _autoChatsKey = 'translation.autoChats';
  static const _dismissedAutoChatsKey = 'translation.dismissedAutoChats';
  static const _optionOrderKey = 'translation.options.order.v1';
  static const _enabledOptionsKey = 'translation.options.enabled.v1';
  static const _telegramUnavailableUntilKey =
      'translation.telegramUnavailableUntil.v1';

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
  late final MessageTranslationCache messageCache;
  bool _enabled;
  bool _translateChats;
  bool _aiTranslationEnabled;
  String _aiTranslationPrompt;
  TranslationProvider _provider;
  String _targetLanguageCode;
  TranslationDisplayStyle _displayStyle;
  String _lingvaEndpoint;
  String _libreTranslateEndpoint;
  String _libreTranslateApiKey;
  final Set<String> _ignoredLanguageCodes;
  final Set<String> _autoTranslateChatIds;
  final Set<String> _dismissedAutoTranslateChatIds;
  late List<String> _translationOptionOrder;
  late Set<String> _enabledTranslationOptionIds;
  DateTime? _telegramTranslationUnavailableUntil;
  Timer? _telegramCooldownTimer;

  bool get enabled => _enabled;
  bool get translateChats => _translateChats;
  bool get aiTranslationEnabled => _aiTranslationEnabled;
  String get aiTranslationPrompt => _aiTranslationPrompt;
  bool get hasCustomAiTranslationPrompt =>
      _aiTranslationPrompt != defaultAiTranslationPrompt.trim();
  TranslationProvider get provider => _provider;
  String get providerLabel => _provider.label;
  String get targetLanguageCode => _targetLanguageCode;
  TranslationDisplayStyle get displayStyle => _displayStyle;
  String get displayStyleLabel => _displayStyle.label;
  String get lingvaEndpoint => _lingvaEndpoint;
  String get libreTranslateEndpoint => _libreTranslateEndpoint;
  String get libreTranslateApiKey => _libreTranslateApiKey;
  Set<String> get ignoredLanguageCodes =>
      Set.unmodifiable(_ignoredLanguageCodes);
  List<String> get translationOptionOrder =>
      List.unmodifiable(_translationOptionOrder);
  Set<String> get enabledTranslationOptionIds =>
      Set.unmodifiable(_enabledTranslationOptionIds);
  DateTime? get telegramTranslationUnavailableUntil =>
      _telegramTranslationUnavailableUntil;

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
    final candidateId =
        _prefs.getString(
          AiSettingsController.translationModelCandidatePreferenceKey,
        ) ??
        AiSettingsController.applePccModelCandidateId;
    _setTranslationOptionEnabled(
      TranslationOptionIds.ai(candidateId),
      value,
      notify: false,
    );
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
    _enabledTranslationOptionIds.removeWhere(TranslationOptionIds.isProvider);
    _setTranslationOptionEnabled(
      TranslationOptionIds.provider(value),
      true,
      notify: false,
    );
    notifyListeners();
  }

  List<String> orderedTranslationOptions(Iterable<String> availableIds) {
    final available = availableIds.toSet();
    return [
      for (final id in _translationOptionOrder)
        if (available.remove(id)) id,
      ...available,
    ];
  }

  List<String> orderedEnabledTranslationOptions(
    Iterable<String> availableIds,
  ) => orderedTranslationOptions(
    availableIds,
  ).where(_enabledTranslationOptionIds.contains).toList(growable: false);

  bool isTranslationOptionEnabled(String id) =>
      _enabledTranslationOptionIds.contains(id);

  void setTranslationOptionEnabled(String id, bool enabled) =>
      _setTranslationOptionEnabled(id, enabled, notify: true);

  void _setTranslationOptionEnabled(
    String id,
    bool enabled, {
    required bool notify,
  }) {
    if (!TranslationOptionIds.isAi(id) &&
        TranslationOptionIds.translationProvider(id) == null) {
      return;
    }
    if (!_translationOptionOrder.contains(id)) {
      _translationOptionOrder.add(id);
      _prefs.setStringList(_optionOrderKey, _translationOptionOrder);
    }
    final changed = enabled
        ? _enabledTranslationOptionIds.add(id)
        : _enabledTranslationOptionIds.remove(id);
    if (!changed) return;
    _prefs.setStringList(
      _enabledOptionsKey,
      _enabledTranslationOptionIds.toList(growable: false),
    );
    _aiTranslationEnabled = _enabledTranslationOptionIds.any(
      TranslationOptionIds.isAi,
    );
    _prefs.setBool(_aiTranslationEnabledKey, _aiTranslationEnabled);
    final provider = TranslationOptionIds.translationProvider(id);
    if (enabled && provider != null) {
      _provider = provider;
      _prefs.setString(_providerKey, provider.storageValue);
    }
    if (notify) notifyListeners();
  }

  void reorderTranslationOptions(
    List<String> visibleOrder,
    int oldIndex,
    int newIndex,
  ) {
    if (oldIndex < 0 || oldIndex >= visibleOrder.length) return;
    if (newIndex < 0 || newIndex >= visibleOrder.length) return;
    final reordered = [...visibleOrder];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    final visible = visibleOrder.toSet();
    _translationOptionOrder = [
      ...reordered,
      for (final id in _translationOptionOrder)
        if (!visible.contains(id)) id,
    ];
    _prefs.setStringList(_optionOrderKey, _translationOptionOrder);
    notifyListeners();
  }

  bool isTelegramTranslationAvailable({DateTime? now}) {
    final until = _telegramTranslationUnavailableUntil;
    return until == null || !(now ?? DateTime.now()).isBefore(until);
  }

  void markTelegramTranslationUnavailable({
    DateTime? now,
    Duration duration = const Duration(minutes: 10),
  }) {
    final until = (now ?? DateTime.now()).add(duration);
    _telegramTranslationUnavailableUntil = until;
    _prefs.setInt(_telegramUnavailableUntilKey, until.millisecondsSinceEpoch);
    _scheduleTelegramCooldownExpiry();
    notifyListeners();
  }

  set targetLanguageCode(String value) {
    value = _normalizeTargetLanguage(value);
    if (_targetLanguageCode == value) return;
    _targetLanguageCode = value;
    _prefs.setString(_targetLanguageKey, value);
    notifyListeners();
  }

  set displayStyle(TranslationDisplayStyle value) {
    if (_displayStyle == value) return;
    _displayStyle = value;
    _prefs.setString(_displayStyleKey, value.storageValue);
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

  void _restoreTranslationOptions() {
    final selectedProvider = TranslationOptionIds.provider(_provider);
    final selectedAi = TranslationOptionIds.ai(
      _prefs.getString(
            AiSettingsController.translationModelCandidatePreferenceKey,
          ) ??
          AiSettingsController.applePccModelCandidateId,
    );
    final storedOrder = _prefs.getStringList(_optionOrderKey);
    final storedEnabled = _prefs.getStringList(_enabledOptionsKey);
    _translationOptionOrder = storedOrder == null
        ? [if (_aiTranslationEnabled) selectedAi, selectedProvider]
        : [...storedOrder];
    _enabledTranslationOptionIds = storedEnabled == null
        ? {if (_aiTranslationEnabled) selectedAi, selectedProvider}
        : {...storedEnabled};
    for (final id in _enabledTranslationOptionIds) {
      if (!_translationOptionOrder.contains(id)) {
        _translationOptionOrder.add(id);
      }
    }
    if (storedOrder == null) {
      _prefs.setStringList(_optionOrderKey, _translationOptionOrder);
    }
    if (storedEnabled == null) {
      _prefs.setStringList(
        _enabledOptionsKey,
        _enabledTranslationOptionIds.toList(growable: false),
      );
    }
  }

  void _restoreTelegramCooldown() {
    final milliseconds = _prefs.getInt(_telegramUnavailableUntilKey);
    if (milliseconds == null) return;
    final until = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    if (!DateTime.now().isBefore(until)) {
      _prefs.remove(_telegramUnavailableUntilKey);
      return;
    }
    _telegramTranslationUnavailableUntil = until;
    _scheduleTelegramCooldownExpiry();
  }

  void _scheduleTelegramCooldownExpiry() {
    _telegramCooldownTimer?.cancel();
    final until = _telegramTranslationUnavailableUntil;
    if (until == null) return;
    final delay = until.difference(DateTime.now());
    if (delay <= Duration.zero) {
      _clearTelegramCooldown();
      return;
    }
    _telegramCooldownTimer = Timer(delay, _clearTelegramCooldown);
  }

  void _clearTelegramCooldown() {
    _telegramCooldownTimer?.cancel();
    _telegramCooldownTimer = null;
    if (_telegramTranslationUnavailableUntil == null) return;
    _telegramTranslationUnavailableUntil = null;
    _prefs.remove(_telegramUnavailableUntilKey);
    notifyListeners();
  }

  @override
  void dispose() {
    _telegramCooldownTimer?.cancel();
    super.dispose();
  }
}
