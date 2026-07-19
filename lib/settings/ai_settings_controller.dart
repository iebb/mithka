import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'apple_pcc_api.dart';

enum AiProviderMode {
  applePcc('apple_pcc'),
  openAiCompatible('open_ai_compatible');

  const AiProviderMode(this.storageValue);

  final String storageValue;

  static AiProviderMode fromStorage(String? value) => switch (value) {
    'open_ai_compatible' || 'openAiCompatible' => openAiCompatible,
    _ => applePcc,
  };
}

typedef AiSecureRead = Future<String?> Function(String key);
typedef AiSecureWrite = Future<void> Function(String key, String? value);

/// Global settings for unread-chat summarization.
///
/// Ordinary preferences live in [SharedPreferences]. The user-supplied API key
/// is kept only in memory and platform secure storage.
class AiSettingsController extends ChangeNotifier {
  AiSettingsController(
    this._preferences, {
    ApplePccApi? pccApi,
    AiSecureRead? secureRead,
    AiSecureWrite? secureWrite,
  }) : _pccApi = pccApi ?? ApplePccApi(),
       _secureRead = secureRead ?? _defaultSecureRead,
       _secureWrite = secureWrite ?? _defaultSecureWrite;

  static const enabledPreferenceKey = 'ai.unread_summary.enabled';
  static const providerPreferenceKey = 'ai.provider_mode';
  static const endpointPreferenceKey = 'ai.custom_server.endpoint';
  static const modelPreferenceKey = 'ai.custom_server.model';
  static const apiKeyStorageKey = 'mithka.ai.api_key.v1';
  static const openAiChatCompletionsPath = '/v1/chat/completions';

  static const _secureStorage = FlutterSecureStorage();

  final SharedPreferences _preferences;
  final ApplePccApi _pccApi;
  final AiSecureRead _secureRead;
  final AiSecureWrite _secureWrite;

  Future<void>? _initialization;
  bool _initialized = false;
  bool _enabled = false;
  AiProviderMode _provider = AiProviderMode.applePcc;
  String _endpoint = '';
  String _model = '';
  String _apiKey = '';
  ApplePccCapabilities? _pccCapabilities;

  bool get initialized => _initialized;
  bool get enabled => _enabled;
  AiProviderMode get provider => _provider;
  String get endpoint => _endpoint;
  String get model => _model;
  String get apiKey => _apiKey;
  bool get hasApiKey => _apiKey.isNotEmpty;
  ApplePccCapabilities? get pccCapabilities => _pccCapabilities;

  bool get isConfiguredForCurrentProvider => switch (_provider) {
    AiProviderMode.applePcc =>
      _pccCapabilities?.available == true &&
          _pccCapabilities?.quotaLimitReached != true,
    AiProviderMode.openAiCompatible =>
      _model.isNotEmpty && isValidOpenAiCompatibleEndpoint(_endpoint),
  };

  Uri? get openAiChatCompletionsUri {
    if (_provider != AiProviderMode.openAiCompatible || _endpoint.isEmpty) {
      return null;
    }
    try {
      return validateOpenAiCompatibleEndpoint(_endpoint);
    } on FormatException {
      return null;
    }
  }

  Future<void> initialize() async {
    if (_initialized) return;
    final pending = _initialization;
    if (pending != null) return pending;

    final operation = _initialize();
    _initialization = operation;
    try {
      await operation;
    } finally {
      _initialization = null;
    }
  }

  Future<void> _initialize() async {
    _enabled = _preferences.getBool(enabledPreferenceKey) ?? false;
    _provider = AiProviderMode.fromStorage(
      _preferences.getString(providerPreferenceKey),
    );
    final storedEndpoint =
        _preferences.getString(endpointPreferenceKey)?.trim() ?? '';
    _endpoint = _normalizeStoredEndpoint(storedEndpoint);
    _model = _preferences.getString(modelPreferenceKey)?.trim() ?? '';

    final results = await Future.wait<Object?>([
      _readApiKeySafely(),
      _pccApi.capabilities(),
    ]);
    _apiKey = results[0] as String;
    _pccCapabilities = results[1] as ApplePccCapabilities;
    _initialized = true;
    notifyListeners();
  }

  Future<void> refreshPccCapabilities() async {
    final capabilities = await _pccApi.capabilities();
    _pccCapabilities = capabilities;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    await _preferences.setBool(enabledPreferenceKey, value);
    _enabled = value;
    notifyListeners();
  }

  Future<void> setProvider(AiProviderMode value) async {
    if (_provider == value) return;
    await _preferences.setString(providerPreferenceKey, value.storageValue);
    _provider = value;
    notifyListeners();
  }

  Future<void> setEndpoint(String value) async {
    final trimmed = value.trim();
    final normalized = trimmed.isEmpty
        ? ''
        : validateOpenAiCompatibleEndpoint(trimmed).toString();
    if (_endpoint == normalized) return;
    await _preferences.setString(endpointPreferenceKey, normalized);
    _endpoint = normalized;
    notifyListeners();
  }

  Future<void> setModel(String value) async {
    final normalized = value.trim();
    if (_model == normalized) return;
    await _preferences.setString(modelPreferenceKey, normalized);
    _model = normalized;
    notifyListeners();
  }

  Future<void> setApiKey(String value) async {
    final normalized = value.trim();
    if (_apiKey == normalized) return;
    await _secureWrite(
      apiKeyStorageKey,
      normalized.isEmpty ? null : normalized,
    );
    _apiKey = normalized;
    notifyListeners();
  }

  static bool isValidOpenAiCompatibleEndpoint(String value) {
    try {
      validateOpenAiCompatibleEndpoint(value);
      return true;
    } on FormatException {
      return false;
    }
  }

  static Uri validateOpenAiCompatibleEndpoint(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('The server endpoint is required.');
    }

    final Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } on FormatException {
      throw const FormatException('The server endpoint is not a valid URL.');
    }
    if (!uri.hasAuthority || uri.host.isEmpty) {
      throw const FormatException('The server endpoint must include a host.');
    }
    if (uri.userInfo.isNotEmpty) {
      throw const FormatException(
        'Credentials must not be embedded in the server endpoint.',
      );
    }
    if (uri.hasQuery || uri.hasFragment) {
      throw const FormatException(
        'The server endpoint must not include a query or fragment.',
      );
    }
    if (uri.path != openAiChatCompletionsPath) {
      throw const FormatException(
        'The server endpoint path must be exactly /v1/chat/completions.',
      );
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'http') {
      throw const FormatException('The server endpoint must use HTTPS.');
    }
    if (scheme == 'http' && !_isLoopbackHost(uri.host)) {
      throw const FormatException(
        'HTTP is permitted only for a loopback server.',
      );
    }
    try {
      if (uri.hasPort && (uri.port <= 0 || uri.port > 65535)) {
        throw const FormatException('The server endpoint port is invalid.');
      }
    } on FormatException {
      throw const FormatException('The server endpoint port is invalid.');
    }
    return uri;
  }

  static String _normalizeStoredEndpoint(String value) {
    if (value.isEmpty) return '';
    try {
      return validateOpenAiCompatibleEndpoint(value).toString();
    } on FormatException {
      return '';
    }
  }

  static bool _isLoopbackHost(String host) {
    final normalized = host.toLowerCase();
    if (normalized == 'localhost' || normalized.endsWith('.localhost')) {
      return true;
    }
    return InternetAddress.tryParse(normalized)?.isLoopback ?? false;
  }

  Future<String> _readApiKeySafely() async {
    try {
      return (await _secureRead(apiKeyStorageKey))?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<String?> _defaultSecureRead(String key) =>
      _secureStorage.read(key: key);

  static Future<void> _defaultSecureWrite(String key, String? value) =>
      value == null
      ? _secureStorage.delete(key: key)
      : _secureStorage.write(key: key, value: value);
}
