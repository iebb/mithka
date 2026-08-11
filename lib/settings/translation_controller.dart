//
//  translation_controller.dart
//
//  Persisted message translation preferences.
//

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

typedef TranslationSecureRead = Future<String?> Function(String key);
typedef TranslationSecureWrite =
    Future<void> Function(String key, String? value);

/// Metadata for one user-configured Cloud Translation Basic provider.
///
/// API keys are deliberately absent and live in platform secure storage under
/// a separate key for every provider ID.
class GoogleCloudTranslationProvider {
  const GoogleCloudTranslationProvider({
    required this.id,
    required this.name,
    required this.hasApiKey,
  });

  final String id;
  final String name;
  final bool hasApiKey;

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'has_api_key': hasApiKey,
  };

  static GoogleCloudTranslationProvider? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    final hasApiKey = value['has_api_key'];
    if (id is! String ||
        !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id) ||
        name is! String ||
        name.trim().isEmpty ||
        hasApiKey is! bool) {
      return null;
    }
    return GoogleCloudTranslationProvider(
      id: id,
      name: name.trim(),
      hasApiKey: hasApiKey,
    );
  }
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
  googleTranslate('google_translate', 'Google Translate'),
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
    googleTranslate,
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
  static const _googleCloudPrefix = 'google_cloud:';

  static const telegramTranslation = 'provider:tdlib';
  static const telegramCocoon = 'ai:builtin:telegram_cocoon';
  static const googleTranslate = 'provider:google_translate';
  static const iosSystemTranslation = 'provider:ios_system';
  static const androidMlKitTranslation = 'provider:android_mlkit';
  static const appleOnDeviceModel = 'ai:builtin:apple_on_device';
  static const googleCloudDefaultPriorityBase = 501;
  static const aiDefaultPriorityBase = 900;

  static const defaultPriorities = <String, int>{
    telegramTranslation: 100,
    telegramCocoon: 200,
    googleTranslate: 500,
    iosSystemTranslation: 800,
    androidMlKitTranslation: 800,
    appleOnDeviceModel: 1000,
  };

  static String provider(TranslationProvider value) =>
      '$_providerPrefix${value.storageValue}';

  static String ai(String candidateId) => '$_aiPrefix$candidateId';

  static String googleCloud(String providerId) =>
      '$_googleCloudPrefix$providerId';

  static bool isAi(String value) => value.startsWith(_aiPrefix);
  static bool isProvider(String value) => value.startsWith(_providerPrefix);
  static bool isGoogleCloud(String value) =>
      value.startsWith(_googleCloudPrefix);

  static int? defaultPriority(String value) => defaultPriorities[value];

  static String? aiCandidateId(String value) =>
      isAi(value) ? value.substring(_aiPrefix.length) : null;

  static String? googleCloudProviderId(String value) =>
      isGoogleCloud(value) ? value.substring(_googleCloudPrefix.length) : null;

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
  TranslationController(
    this._prefs, {
    TranslationSecureRead? secureRead,
    TranslationSecureWrite? secureWrite,
  }) : _secureRead = secureRead ?? _defaultSecureRead,
       _secureWrite = secureWrite ?? _defaultSecureWrite,
       _googleCloudProviders = _restoreGoogleCloudProviders(
         _prefs.getString(_googleCloudProvidersKey),
       ),
       _enabled = _prefs.getBool(_enabledKey) ?? false,
       _translateChats = _prefs.getBool(_translateChatsKey) ?? true,
       _aiTranslationEnabled =
           _prefs.getBool(_aiTranslationEnabledKey) ?? false,
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
       _ignoredLanguageCodes = _restoreIgnoredLanguageCodes(
         _prefs.getStringList(_ignoredLanguagesKey),
       ),
       _autoTranslateChatIds = {...?_prefs.getStringList(_autoChatsKey)},
       _dismissedAutoTranslateChatIds = {
         ...?_prefs.getStringList(_dismissedAutoChatsKey),
       } {
    _restoreTranslationOptions();
    _restoreTelegramCooldown();
    final storedIgnored =
        _prefs.getStringList(_ignoredLanguagesKey)?.toSet() ?? const <String>{};
    if (!setEquals(storedIgnored, _ignoredLanguageCodes)) {
      _persistStringSet(_ignoredLanguagesKey, _ignoredLanguageCodes);
    }
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
  static const _optionPrioritiesKey = 'translation.options.priorities.v1';
  static const _enabledOptionsKey = 'translation.options.enabled.v1';
  static const _telegramUnavailableUntilKey =
      'translation.telegramUnavailableUntil.v1';
  static const _googleCloudProvidersKey =
      'translation.googleCloud.providers.v1';

  static const _secureStorage = FlutterSecureStorage();
  static const _googleCloudApiKeyPrefix =
      'mithka.translation.google_cloud.provider.';
  static const _googleCloudApiKeySuffix = '.api_key.v1';

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
  final TranslationSecureRead _secureRead;
  final TranslationSecureWrite _secureWrite;
  late final MessageTranslationCache messageCache;
  List<GoogleCloudTranslationProvider> _googleCloudProviders;
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
  late Map<String, double> _translationOptionPriorityOverrides;
  List<String>? _legacyTranslationOptionOrder;
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
  List<GoogleCloudTranslationProvider> get googleCloudProviders =>
      List.unmodifiable(_googleCloudProviders);
  Set<String> get ignoredLanguageCodes =>
      Set.unmodifiable(_ignoredLanguageCodes);
  List<String> get translationOptionOrder =>
      List.unmodifiable(_translationOptionOrder);
  Map<String, double> get translationOptionPriorityOverrides =>
      Map.unmodifiable(_translationOptionPriorityOverrides);
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
    final available = availableIds.toSet().toList(growable: false);
    _migrateLegacyTranslationOptionOrder(available);
    final stableOrder = <String, int>{
      for (var index = 0; index < _translationOptionOrder.length; index++)
        _translationOptionOrder[index]: index,
    };
    final catalogOrder = <String, int>{
      for (var index = 0; index < available.length; index++)
        available[index]: index,
    };
    final ordered = [...available]
      ..sort((left, right) {
        final priorityComparison = _translationOptionPriority(
          left,
          available,
        ).compareTo(_translationOptionPriority(right, available));
        if (priorityComparison != 0) return priorityComparison;
        return (stableOrder[left] ?? catalogOrder[left]!).compareTo(
          stableOrder[right] ?? catalogOrder[right]!,
        );
      });
    final availableSet = available.toSet();
    _translationOptionOrder = [
      ...ordered,
      for (final id in _translationOptionOrder)
        if (!availableSet.contains(id)) id,
    ];
    return ordered;
  }

  double translationOptionPriority(String id, Iterable<String> availableIds) {
    final available = availableIds.toSet().toList(growable: false);
    _migrateLegacyTranslationOptionOrder(available);
    return _translationOptionPriority(id, available);
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
    final googleCloudProviderId = TranslationOptionIds.googleCloudProviderId(
      id,
    );
    if (!TranslationOptionIds.isAi(id) &&
        googleCloudProviderId == null &&
        TranslationOptionIds.translationProvider(id) == null) {
      return;
    }
    if (googleCloudProviderId != null &&
        googleCloudProviderById(googleCloudProviderId) == null) {
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

  GoogleCloudTranslationProvider? googleCloudProviderById(String? id) {
    if (id == null) return null;
    for (final provider in _googleCloudProviders) {
      if (provider.id == id) return provider;
    }
    return null;
  }

  Future<String> googleCloudApiKeyForProvider(String providerId) async {
    final provider = googleCloudProviderById(providerId);
    if (provider == null || !provider.hasApiKey) return '';
    try {
      return (await _secureRead(
            _googleCloudApiKeyStorageKey(providerId),
          ))?.trim() ??
          '';
    } catch (_) {
      return '';
    }
  }

  Future<GoogleCloudTranslationProvider> saveGoogleCloudProvider({
    String? id,
    required String name,
    required String apiKey,
  }) async {
    final normalizedKey = apiKey.trim();
    if (normalizedKey.isEmpty) {
      throw const FormatException('A Google Cloud API key is required.');
    }
    final existing = googleCloudProviderById(id);
    final providerId = existing?.id ?? _newGoogleCloudProviderId();
    final normalizedName = name.trim();
    final provider = GoogleCloudTranslationProvider(
      id: providerId,
      name: normalizedName.isEmpty
          ? 'Google Cloud Translation'
          : normalizedName,
      hasApiKey: true,
    );
    await _secureWrite(_googleCloudApiKeyStorageKey(providerId), normalizedKey);
    final providers = _googleCloudProviders.toList();
    final index = providers.indexWhere((value) => value.id == providerId);
    if (index < 0) {
      providers.add(provider);
    } else {
      providers[index] = provider;
    }
    _googleCloudProviders = List.unmodifiable(providers);
    final optionId = TranslationOptionIds.googleCloud(providerId);
    if (!_translationOptionOrder.contains(optionId)) {
      _translationOptionOrder.add(optionId);
      _persistTranslationOptionPriorities();
    }
    await _persistGoogleCloudProviders();
    notifyListeners();
    return provider;
  }

  Future<void> deleteGoogleCloudProvider(String providerId) async {
    if (googleCloudProviderById(providerId) == null) return;
    await _secureWrite(_googleCloudApiKeyStorageKey(providerId), null);
    _googleCloudProviders = List.unmodifiable(
      _googleCloudProviders.where((provider) => provider.id != providerId),
    );
    final optionId = TranslationOptionIds.googleCloud(providerId);
    _translationOptionOrder.remove(optionId);
    _translationOptionPriorityOverrides.remove(optionId);
    _enabledTranslationOptionIds.remove(optionId);
    await _prefs.setStringList(
      _enabledOptionsKey,
      _enabledTranslationOptionIds.toList(growable: false),
    );
    _persistTranslationOptionPriorities();
    await _persistGoogleCloudProviders();
    notifyListeners();
  }

  void reorderTranslationOptions(
    List<String> visibleOrder,
    int oldIndex,
    int newIndex,
  ) {
    if (oldIndex < 0 || oldIndex >= visibleOrder.length) return;
    if (newIndex < 0 || newIndex >= visibleOrder.length) return;
    if (oldIndex == newIndex) return;
    _migrateLegacyTranslationOptionOrder(visibleOrder);
    final priorities = <String, double>{
      for (final id in visibleOrder)
        id: _translationOptionPriority(id, visibleOrder),
    };
    final reordered = [...visibleOrder];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    final before = newIndex == 0 ? null : priorities[reordered[newIndex - 1]];
    final after = newIndex == reordered.length - 1
        ? null
        : priorities[reordered[newIndex + 1]];
    final double priority;
    if (before != null && after != null && before < after) {
      priority = (before + after) / 2;
    } else if (before == null && after != null) {
      priority = after > 0 ? after / 2 : after - 100;
    } else if (before != null && after == null) {
      priority = before + 100;
    } else if (before != null && after != null) {
      for (var index = 0; index < reordered.length; index++) {
        _translationOptionPriorityOverrides[reordered[index]] =
            (index + 1) * 100.0;
      }
      priority = _translationOptionPriorityOverrides[moved]!;
    } else {
      priority = priorities[moved] ?? 100;
    }
    _translationOptionPriorityOverrides[moved] = priority;
    final visible = visibleOrder.toSet();
    _translationOptionOrder = [
      ...reordered,
      for (final id in _translationOptionOrder)
        if (!visible.contains(id)) id,
    ];
    _persistTranslationOptionPriorities();
    notifyListeners();
  }

  void resetTranslationOptionPriorities() {
    _translationOptionPriorityOverrides.clear();
    _legacyTranslationOptionOrder = null;
    _translationOptionOrder = [...TranslationOptionIds.defaultPriorities.keys];
    _persistTranslationOptionPriorities();
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
    final lower = code.toLowerCase().replaceAll('_', '-');
    if (lower == 'zh' || lower.startsWith('zh-')) {
      final parts = lower.split('-').skip(1).toSet();
      if (parts.contains('hans') ||
          parts.contains('cn') ||
          parts.contains('sg')) {
        return 'zh-Hans';
      }
      if (parts.contains('hant') ||
          parts.contains('tw') ||
          parts.contains('hk') ||
          parts.contains('mo')) {
        return 'zh-Hant';
      }
      return 'zh';
    }
    return lower.split('-').first;
  }

  static Set<String> _restoreIgnoredLanguageCodes(List<String>? stored) {
    final result = <String>{};
    for (final code in stored ?? const <String>[]) {
      final normalized = normalizeLanguageCode(code);
      if (normalized == null) continue;
      if (normalized == 'zh') {
        // Older builds collapsed both Chinese scripts into one `zh` value.
        // Preserve that broad preference while allowing either script to be
        // toggled independently from now on.
        result
          ..add('zh-Hans')
          ..add('zh-Hant');
      } else {
        result.add(normalized);
      }
    }
    return result;
  }

  static String normalizeEndpoint(String value) =>
      value.trim().replaceFirst(RegExp(r'/+$'), '');

  double _translationOptionPriority(String id, List<String> availableIds) {
    final overridden = _translationOptionPriorityOverrides[id];
    if (overridden != null) return overridden;
    final fixed = TranslationOptionIds.defaultPriority(id);
    if (fixed != null) return fixed.toDouble();
    if (TranslationOptionIds.isGoogleCloud(id)) {
      final defaultGoogleCloudIds = [
        for (final optionId in availableIds)
          if (TranslationOptionIds.isGoogleCloud(optionId)) optionId,
      ];
      final index = defaultGoogleCloudIds.indexOf(id);
      return (TranslationOptionIds.googleCloudDefaultPriorityBase +
              (index < 0 ? defaultGoogleCloudIds.length : index))
          .toDouble();
    }
    if (TranslationOptionIds.isAi(id)) {
      final defaultAiIds = [
        for (final optionId in availableIds)
          if (TranslationOptionIds.isAi(optionId) &&
              TranslationOptionIds.defaultPriority(optionId) == null)
            optionId,
      ];
      final index = defaultAiIds.indexOf(id);
      return (TranslationOptionIds.aiDefaultPriorityBase +
              (index < 0 ? defaultAiIds.length : index))
          .toDouble();
    }
    final index = availableIds.indexOf(id);
    return (2000 + (index < 0 ? availableIds.length : index)).toDouble();
  }

  void _migrateLegacyTranslationOptionOrder(List<String> availableIds) {
    final legacyOrder = _legacyTranslationOptionOrder;
    if (legacyOrder == null) return;
    final combined = <String>[
      ...legacyOrder,
      for (final id in availableIds)
        if (!legacyOrder.contains(id)) id,
    ];
    _translationOptionPriorityOverrides = {
      for (var index = 0; index < combined.length; index++)
        combined[index]: (index + 1) * 100.0,
    };
    _translationOptionOrder = combined;
    _legacyTranslationOptionOrder = null;
    _persistTranslationOptionPriorities();
  }

  void _persistTranslationOptionPriorities() {
    _prefs.setString(
      _optionPrioritiesKey,
      jsonEncode(_translationOptionPriorityOverrides),
    );
    _prefs.setStringList(_optionOrderKey, _translationOptionOrder);
  }

  static Map<String, double>? _restoreTranslationOptionPriorities(String? raw) {
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final priorities = <String, double>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (entry.key is! String || value is! num) continue;
        final priority = value.toDouble();
        if (priority.isFinite) priorities[entry.key as String] = priority;
      }
      return priorities;
    } on FormatException {
      return null;
    }
  }

  static List<GoogleCloudTranslationProvider> _restoreGoogleCloudProviders(
    String? raw,
  ) {
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final providers = <GoogleCloudTranslationProvider>[];
      final ids = <String>{};
      for (final value in decoded) {
        final provider = GoogleCloudTranslationProvider.fromJson(value);
        if (provider != null && ids.add(provider.id)) providers.add(provider);
      }
      return List.unmodifiable(providers);
    } on FormatException {
      return const [];
    }
  }

  Future<void> _persistGoogleCloudProviders() => _prefs.setString(
    _googleCloudProvidersKey,
    jsonEncode(
      _googleCloudProviders.map((provider) => provider.toJson()).toList(),
    ),
  );

  String _newGoogleCloudProviderId() {
    final base = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    var id = 'google_$base';
    var suffix = 2;
    while (googleCloudProviderById(id) != null) {
      id = 'google_${base}_${suffix++}';
    }
    return id;
  }

  static String _googleCloudApiKeyStorageKey(String providerId) =>
      '$_googleCloudApiKeyPrefix$providerId$_googleCloudApiKeySuffix';

  static Future<String?> _defaultSecureRead(String key) =>
      _secureStorage.read(key: key);

  static Future<void> _defaultSecureWrite(String key, String? value) =>
      value == null
      ? _secureStorage.delete(key: key)
      : _secureStorage.write(key: key, value: value);

  void _restoreTranslationOptions() {
    final selectedProvider = TranslationOptionIds.provider(_provider);
    final selectedAi = TranslationOptionIds.ai(
      _prefs.getString(
            AiSettingsController.translationModelCandidatePreferenceKey,
          ) ??
          AiSettingsController.applePccModelCandidateId,
    );
    final storedOrder = _prefs.getStringList(_optionOrderKey);
    final storedPriorities = _restoreTranslationOptionPriorities(
      _prefs.getString(_optionPrioritiesKey),
    );
    final storedEnabled = _prefs.getStringList(_enabledOptionsKey);
    final defaultOrder = <String>[
      ...TranslationOptionIds.defaultPriorities.keys,
      if (_aiTranslationEnabled &&
          !TranslationOptionIds.defaultPriorities.containsKey(selectedAi))
        selectedAi,
      if (!TranslationOptionIds.defaultPriorities.containsKey(selectedProvider))
        selectedProvider,
    ];
    final legacyDefaultOrder = <String>[
      if (_aiTranslationEnabled) selectedAi,
      selectedProvider,
    ];
    final legacyOrderIsCustomized =
        storedPriorities == null &&
        storedOrder != null &&
        !listEquals(storedOrder, legacyDefaultOrder) &&
        !listEquals(storedOrder, defaultOrder);
    _translationOptionPriorityOverrides = storedPriorities ?? {};
    _legacyTranslationOptionOrder = legacyOrderIsCustomized
        ? [...storedOrder]
        : null;
    _translationOptionOrder = legacyOrderIsCustomized
        ? [...storedOrder]
        : defaultOrder;
    _enabledTranslationOptionIds = storedEnabled == null
        ? {if (_aiTranslationEnabled) selectedAi, selectedProvider}
        : {...storedEnabled};
    for (final id in _enabledTranslationOptionIds) {
      if (!_translationOptionOrder.contains(id)) {
        _translationOptionOrder.add(id);
      }
    }
    if (storedOrder == null || storedPriorities == null) {
      if (!legacyOrderIsCustomized) {
        _persistTranslationOptionPriorities();
      }
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
