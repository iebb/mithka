import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'apple_pcc_api.dart';
import 'openai_compatible_models_api.dart';

enum AiProviderMode {
  applePcc('apple_pcc'),
  appleOnDevice('apple_on_device'),
  openAiCompatible('open_ai_compatible');

  const AiProviderMode(this.storageValue);

  final String storageValue;

  static AiProviderMode fromStorage(String? value) => switch (value) {
    'apple_on_device' || 'appleOnDevice' => appleOnDevice,
    'open_ai_compatible' || 'openAiCompatible' => openAiCompatible,
    _ => applePcc,
  };
}

class AiServerProfile {
  const AiServerProfile({
    required this.id,
    required this.name,
    required this.endpoint,
    required this.model,
    this.contextWindowTokens = defaultContextWindowTokens,
    this.contextWindowDetected = false,
    this.availableModels = const [],
  });

  static const defaultContextWindowTokens = 131072;
  static const minimumContextWindowTokens = 4096;
  static const maximumContextWindowTokens = 16777216;

  final String id;
  final String name;
  final String endpoint;
  final String model;
  final int contextWindowTokens;
  final bool contextWindowDetected;
  final List<OpenAiCompatibleModelInfo> availableModels;

  Uri get chatCompletionsUri => Uri.parse(endpoint);

  AiServerProfile copyWith({
    String? name,
    String? endpoint,
    String? model,
    int? contextWindowTokens,
    bool? contextWindowDetected,
    List<OpenAiCompatibleModelInfo>? availableModels,
  }) => AiServerProfile(
    id: id,
    name: name ?? this.name,
    endpoint: endpoint ?? this.endpoint,
    model: model ?? this.model,
    contextWindowTokens: contextWindowTokens ?? this.contextWindowTokens,
    contextWindowDetected: contextWindowDetected ?? this.contextWindowDetected,
    availableModels: availableModels ?? this.availableModels,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'endpoint': endpoint,
    'model': model,
    'context_window_tokens': contextWindowTokens,
    'context_window_detected': contextWindowDetected,
    'available_models': availableModels
        .map((model) => model.toJson())
        .toList(growable: false),
  };

  static AiServerProfile? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final endpoint = value['endpoint'];
    if (id is! String ||
        id.trim().isEmpty ||
        endpoint is! String ||
        !AiSettingsController.isValidOpenAiCompatibleEndpoint(endpoint)) {
      return null;
    }
    final uri = AiSettingsController.validateOpenAiCompatibleEndpoint(endpoint);
    final rawName = value['name'];
    final rawModel = value['model'];
    final rawContext = value['context_window_tokens'];
    final parsedContext = switch (rawContext) {
      int() => rawContext,
      num() => rawContext.toInt(),
      String() => int.tryParse(rawContext),
      _ => null,
    };
    final availableModels = <OpenAiCompatibleModelInfo>[];
    final rawModels = value['available_models'];
    if (rawModels is List) {
      for (final raw in rawModels) {
        final parsed = OpenAiCompatibleModelInfo.fromJson(raw);
        if (parsed != null) availableModels.add(parsed);
      }
    }
    return AiServerProfile(
      id: id.trim(),
      name: rawName is String && rawName.trim().isNotEmpty
          ? rawName.trim()
          : uri.host,
      endpoint: uri.toString(),
      model: rawModel is String ? rawModel.trim() : '',
      contextWindowTokens:
          parsedContext != null &&
              parsedContext >= minimumContextWindowTokens &&
              parsedContext <= maximumContextWindowTokens
          ? parsedContext
          : defaultContextWindowTokens,
      contextWindowDetected: value['context_window_detected'] == true,
      availableModels: List.unmodifiable(availableModels),
    );
  }
}

typedef AiSecureRead = Future<String?> Function(String key);
typedef AiSecureWrite = Future<void> Function(String key, String? value);

/// Global settings for unread-chat summarization.
///
/// Provider metadata lives in [SharedPreferences]. Every endpoint has its own
/// API key entry in platform secure storage; keys are never serialized with the
/// provider profiles.
class AiSettingsController extends ChangeNotifier {
  AiSettingsController(
    this._preferences, {
    ApplePccApi? pccApi,
    OpenAiCompatibleModelsApi? modelsApi,
    AiSecureRead? secureRead,
    AiSecureWrite? secureWrite,
  }) : _pccApi = pccApi ?? ApplePccApi(),
       _modelsApi = modelsApi ?? OpenAiCompatibleModelsApi(),
       _ownsModelsApi = modelsApi == null,
       _secureRead = secureRead ?? _defaultSecureRead,
       _secureWrite = secureWrite ?? _defaultSecureWrite;

  static const enabledPreferenceKey = 'ai.unread_summary.enabled';
  static const providerPreferenceKey = 'ai.provider_mode';
  static const endpointPreferenceKey = 'ai.custom_server.endpoint';
  static const modelPreferenceKey = 'ai.custom_server.model';
  static const apiKeyStorageKey = 'mithka.ai.api_key.v1';
  static const serverProfilesPreferenceKey = 'ai.custom_server.profiles.v1';
  static const activeServerProfileIdPreferenceKey =
      'ai.custom_server.active_profile_id';
  static const openAiChatCompletionsPath = '/v1/chat/completions';

  static const _secureStorage = FlutterSecureStorage();
  static const _profileApiKeyPrefix = 'mithka.ai.provider.';
  static const _profileApiKeySuffix = '.api_key.v1';

  final SharedPreferences _preferences;
  final ApplePccApi _pccApi;
  final OpenAiCompatibleModelsApi _modelsApi;
  final bool _ownsModelsApi;
  final AiSecureRead _secureRead;
  final AiSecureWrite _secureWrite;

  Future<void>? _initialization;
  bool _initialized = false;
  bool _enabled = false;
  AiProviderMode _provider = AiProviderMode.applePcc;
  List<AiServerProfile> _serverProfiles = const [];
  String? _activeServerProfileId;
  final Map<String, String> _profileApiKeys = {};
  ApplePccCapabilities? _pccCapabilities;

  bool get initialized => _initialized;
  bool get enabled => _enabled;
  AiProviderMode get provider => _provider;
  List<AiServerProfile> get serverProfiles => _serverProfiles;
  String? get activeServerProfileId => _activeServerProfileId;
  AiServerProfile? get activeServerProfile {
    final id = _activeServerProfileId;
    if (id == null) return null;
    for (final profile in _serverProfiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  String get endpoint => activeServerProfile?.endpoint ?? '';
  String get model => activeServerProfile?.model ?? '';
  String get apiKey => _profileApiKeys[_activeServerProfileId] ?? '';
  String apiKeyForServerProfile(String profileId) =>
      _profileApiKeys[profileId] ?? '';
  bool get hasApiKey => apiKey.isNotEmpty;
  ApplePccCapabilities? get pccCapabilities => _pccCapabilities;

  bool get isConfiguredForCurrentProvider => switch (_provider) {
    AiProviderMode.applePcc =>
      _pccCapabilities?.available == true &&
          _pccCapabilities?.quotaLimitReached != true,
    AiProviderMode.appleOnDevice => _pccCapabilities?.onDeviceAvailable == true,
    AiProviderMode.openAiCompatible =>
      model.isNotEmpty && isValidOpenAiCompatibleEndpoint(endpoint),
  };

  Uri? get openAiChatCompletionsUri {
    if (_provider != AiProviderMode.openAiCompatible || endpoint.isEmpty) {
      return null;
    }
    try {
      return validateOpenAiCompatibleEndpoint(endpoint);
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
    _serverProfiles = _readStoredProfiles();
    _activeServerProfileId = _preferences.getString(
      activeServerProfileIdPreferenceKey,
    );

    var migratedLegacyProfile = false;
    if (_serverProfiles.isEmpty) {
      final storedEndpoint =
          _preferences.getString(endpointPreferenceKey)?.trim() ?? '';
      final normalizedEndpoint = _normalizeStoredEndpoint(storedEndpoint);
      if (normalizedEndpoint.isNotEmpty) {
        final uri = Uri.parse(normalizedEndpoint);
        final profile = AiServerProfile(
          id: 'legacy',
          name: uri.host,
          endpoint: normalizedEndpoint,
          model: _preferences.getString(modelPreferenceKey)?.trim() ?? '',
        );
        _serverProfiles = [profile];
        _activeServerProfileId = profile.id;
        migratedLegacyProfile = true;
      }
    }
    if (_serverProfiles.isNotEmpty &&
        !_serverProfiles.any((p) => p.id == _activeServerProfileId)) {
      _activeServerProfileId = _serverProfiles.first.id;
    }

    final keyResults = await Future.wait(
      _serverProfiles.map((profile) async {
        final value = await _readSecureValueSafely(_profileKey(profile.id));
        return MapEntry(profile.id, value);
      }),
    );
    for (final entry in keyResults) {
      if (entry.value.isNotEmpty) _profileApiKeys[entry.key] = entry.value;
    }
    if (_serverProfiles.any((profile) => profile.id == 'legacy') &&
        !_profileApiKeys.containsKey('legacy')) {
      final legacyKey = await _readSecureValueSafely(apiKeyStorageKey);
      if (legacyKey.isNotEmpty) {
        _profileApiKeys['legacy'] = legacyKey;
        try {
          await _secureWrite(_profileKey('legacy'), legacyKey);
          await _secureWrite(apiKeyStorageKey, null);
        } catch (_) {
          // Keep using the legacy key in memory. A later initialization will
          // retry the secure-storage migration without losing credentials.
        }
      }
    }

    final capabilities = await _pccApi.capabilities();
    _pccCapabilities = capabilities;
    if (migratedLegacyProfile) await _persistProfiles();
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

  Future<List<OpenAiCompatibleModelInfo>> discoverModels({
    required String endpoint,
    required String apiKey,
    String? preferredModel,
  }) async {
    final uri = validateOpenAiCompatibleEndpoint(endpoint);
    final models = await _modelsApi.listModels(
      chatCompletionsUri: uri,
      apiKey: apiKey,
    );
    if (models.isEmpty) return models;
    final normalizedPreferred = preferredModel?.trim() ?? '';
    final targetIndex = normalizedPreferred.isEmpty
        ? 0
        : models.indexWhere((model) => model.id == normalizedPreferred);
    if (targetIndex < 0) return models;
    if (models[targetIndex].contextWindowTokens != null) return models;

    try {
      final detail = await _modelsApi.retrieveModel(
        chatCompletionsUri: uri,
        modelId: models[targetIndex].id,
        apiKey: apiKey,
      );
      if (detail?.contextWindowTokens == null) return models;
      final enriched = models.toList();
      enriched[targetIndex] = OpenAiCompatibleModelInfo(
        id: models[targetIndex].id,
        contextWindowTokens: detail!.contextWindowTokens,
      );
      return List.unmodifiable(enriched);
    } on OpenAiCompatibleModelsException {
      // Model-list discovery still succeeded. Detail lookup is optional and
      // must not hide usable model IDs on providers that do not implement it.
      return models;
    }
  }

  Future<OpenAiCompatibleModelInfo?> discoverModelDetails({
    required String endpoint,
    required String apiKey,
    required String model,
  }) => _modelsApi.retrieveModel(
    chatCompletionsUri: validateOpenAiCompatibleEndpoint(endpoint),
    modelId: model,
    apiKey: apiKey,
  );

  Future<List<OpenAiCompatibleModelInfo>> refreshModelsForProfile(
    String profileId,
  ) async {
    final profile = _profileById(profileId);
    if (profile == null) {
      throw const FormatException('The selected AI provider no longer exists.');
    }
    final models = await discoverModels(
      endpoint: profile.endpoint,
      apiKey: _profileApiKeys[profileId] ?? '',
      preferredModel: profile.model,
    );
    final selectedModel = models.where((item) => item.id == profile.model);
    final discoveredContext = selectedModel.isEmpty
        ? null
        : selectedModel.first.contextWindowTokens;
    await _replaceProfile(
      profile.copyWith(
        availableModels: List.unmodifiable(models),
        contextWindowTokens: discoveredContext ?? profile.contextWindowTokens,
        contextWindowDetected: discoveredContext != null,
      ),
    );
    return models;
  }

  Future<AiServerProfile> saveServerProfile({
    String? id,
    required String name,
    required String endpoint,
    required String model,
    required String apiKey,
    required int contextWindowTokens,
    bool contextWindowDetected = false,
    List<OpenAiCompatibleModelInfo>? availableModels,
  }) async {
    final uri = validateOpenAiCompatibleEndpoint(endpoint);
    final normalizedModel = model.trim();
    if (normalizedModel.isEmpty) {
      throw const FormatException('A model is required.');
    }
    if (contextWindowTokens < AiServerProfile.minimumContextWindowTokens ||
        contextWindowTokens > AiServerProfile.maximumContextWindowTokens) {
      throw const FormatException(
        'The context window is outside the supported range.',
      );
    }
    final normalizedId = id?.trim();
    final profileId = normalizedId != null && normalizedId.isNotEmpty
        ? normalizedId
        : _newProfileId();
    final existing = _profileById(profileId);
    final profile = AiServerProfile(
      id: profileId,
      name: name.trim().isEmpty ? uri.host : name.trim(),
      endpoint: uri.toString(),
      model: normalizedModel,
      contextWindowTokens: contextWindowTokens,
      contextWindowDetected: contextWindowDetected,
      availableModels: List.unmodifiable(
        availableModels ?? existing?.availableModels ?? const [],
      ),
    );
    final normalizedKey = apiKey.trim();
    await _secureWrite(
      _profileKey(profileId),
      normalizedKey.isEmpty ? null : normalizedKey,
    );
    if (normalizedKey.isEmpty) {
      _profileApiKeys.remove(profileId);
    } else {
      _profileApiKeys[profileId] = normalizedKey;
    }
    await _replaceProfile(profile, makeActive: true);
    return profile;
  }

  Future<void> selectServerProfile(String profileId) async {
    if (_profileById(profileId) == null) return;
    if (_activeServerProfileId == profileId) return;
    _activeServerProfileId = profileId;
    await _preferences.setString(activeServerProfileIdPreferenceKey, profileId);
    notifyListeners();
  }

  Future<void> deleteServerProfile(String profileId) async {
    if (_profileById(profileId) == null) return;
    await _secureWrite(_profileKey(profileId), null);
    _profileApiKeys.remove(profileId);
    _serverProfiles = List.unmodifiable(
      _serverProfiles.where((profile) => profile.id != profileId),
    );
    if (_activeServerProfileId == profileId) {
      _activeServerProfileId = _serverProfiles.firstOrNull?.id;
    }
    await _persistProfiles();
    notifyListeners();
  }

  // Compatibility helpers for callers that still edit the active server one
  // field at a time. New UI should commit an entire provider atomically.
  Future<void> setEndpoint(String value) async {
    final endpoint = validateOpenAiCompatibleEndpoint(value).toString();
    final active = activeServerProfile;
    if (active == null) {
      final uri = Uri.parse(endpoint);
      final profile = AiServerProfile(
        id: _newProfileId(),
        name: uri.host,
        endpoint: endpoint,
        model: '',
      );
      await _replaceProfile(profile, makeActive: true);
      return;
    }
    await _replaceProfile(active.copyWith(endpoint: endpoint));
  }

  Future<void> setModel(String value) async {
    final active = activeServerProfile;
    if (active == null) return;
    await _replaceProfile(active.copyWith(model: value.trim()));
  }

  Future<void> setApiKey(String value) async {
    final id = _activeServerProfileId;
    if (id == null) return;
    final normalized = value.trim();
    await _secureWrite(_profileKey(id), normalized.isEmpty ? null : normalized);
    if (normalized.isEmpty) {
      _profileApiKeys.remove(id);
    } else {
      _profileApiKeys[id] = normalized;
    }
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
    if (!uri.path.endsWith(openAiChatCompletionsPath)) {
      throw const FormatException(
        'The server endpoint path must end in /v1/chat/completions.',
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

  @override
  void dispose() {
    if (_ownsModelsApi) _modelsApi.close();
    super.dispose();
  }

  List<AiServerProfile> _readStoredProfiles() {
    final encoded = _preferences.getString(serverProfilesPreferenceKey);
    if (encoded == null || encoded.isEmpty) return const [];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return const [];
      final profiles = <AiServerProfile>[];
      final ids = <String>{};
      for (final value in decoded) {
        final profile = AiServerProfile.fromJson(value);
        if (profile != null && ids.add(profile.id)) profiles.add(profile);
      }
      return List.unmodifiable(profiles);
    } on FormatException {
      return const [];
    }
  }

  Future<void> _replaceProfile(
    AiServerProfile profile, {
    bool makeActive = false,
  }) async {
    final profiles = _serverProfiles.toList();
    final index = profiles.indexWhere((item) => item.id == profile.id);
    if (index < 0) {
      profiles.add(profile);
    } else {
      profiles[index] = profile;
    }
    _serverProfiles = List.unmodifiable(profiles);
    if (makeActive || _activeServerProfileId == null) {
      _activeServerProfileId = profile.id;
    }
    await _persistProfiles();
    notifyListeners();
  }

  Future<void> _persistProfiles() async {
    await _preferences.setString(
      serverProfilesPreferenceKey,
      jsonEncode(_serverProfiles.map((profile) => profile.toJson()).toList()),
    );
    final activeId = _activeServerProfileId;
    if (activeId == null) {
      await _preferences.remove(activeServerProfileIdPreferenceKey);
    } else {
      await _preferences.setString(
        activeServerProfileIdPreferenceKey,
        activeId,
      );
    }
  }

  AiServerProfile? _profileById(String id) {
    for (final profile in _serverProfiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  static String _profileKey(String profileId) =>
      '$_profileApiKeyPrefix$profileId$_profileApiKeySuffix';

  static String _newProfileId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

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

  Future<String> _readSecureValueSafely(String key) async {
    try {
      return (await _secureRead(key))?.trim() ?? '';
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

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
