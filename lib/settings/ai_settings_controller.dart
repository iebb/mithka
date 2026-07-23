import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_endpoint_style.dart';
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

class AiServerProvider {
  const AiServerProvider({
    required this.id,
    required this.name,
    required this.endpoint,
    this.endpointStyle = AiEndpointStyle.openAiChatCompletions,
    this.availableModels = const [],
  });

  final String id;
  final String name;
  final String endpoint;
  final AiEndpointStyle endpointStyle;
  final List<OpenAiCompatibleModelInfo> availableModels;

  Uri get requestUri => Uri.parse(endpoint);
  Uri get chatCompletionsUri => requestUri;

  AiServerProvider copyWith({
    String? name,
    String? endpoint,
    AiEndpointStyle? endpointStyle,
    List<OpenAiCompatibleModelInfo>? availableModels,
  }) => AiServerProvider(
    id: id,
    name: name ?? this.name,
    endpoint: endpoint ?? this.endpoint,
    endpointStyle: endpointStyle ?? this.endpointStyle,
    availableModels: availableModels ?? this.availableModels,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'endpoint': endpoint,
    'endpoint_style': endpointStyle.storageValue,
    'available_models': availableModels
        .map((model) => model.toJson())
        .toList(growable: false),
  };

  static AiServerProvider? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final endpoint = value['endpoint'];
    final endpointStyle = value['endpoint_style'] is String
        ? AiEndpointStyle.fromStorage(value['endpoint_style'] as String)
        : AiEndpointStyle.inferFromEndpoint(
                endpoint is String ? endpoint : '',
              ) ??
              AiEndpointStyle.openAiChatCompletions;
    if (id is! String ||
        id.trim().isEmpty ||
        endpoint is! String ||
        !AiSettingsController.isValidOpenAiCompatibleEndpoint(
          endpoint,
          endpointStyle: endpointStyle,
        )) {
      return null;
    }
    final uri = AiSettingsController.validateOpenAiCompatibleEndpoint(
      endpoint,
      endpointStyle: endpointStyle,
    );
    final rawName = value['name'];
    final availableModels = <OpenAiCompatibleModelInfo>[];
    final rawModels = value['available_models'];
    if (rawModels is List) {
      for (final raw in rawModels) {
        final parsed = OpenAiCompatibleModelInfo.fromJson(raw);
        if (parsed != null) availableModels.add(parsed);
      }
    }
    return AiServerProvider(
      id: id.trim(),
      name: rawName is String && rawName.trim().isNotEmpty
          ? rawName.trim()
          : uri.host,
      endpoint: uri.toString(),
      endpointStyle: endpointStyle,
      availableModels: List.unmodifiable(availableModels),
    );
  }
}

class AiModelProfile {
  const AiModelProfile({
    required this.id,
    required this.providerId,
    required this.model,
    this.contextWindowTokens = defaultContextWindowTokens,
    this.contextWindowDetected = false,
  });

  static const defaultContextWindowTokens = 200000;
  static const minimumContextWindowTokens = 4096;
  static const maximumContextWindowTokens = 16777216;

  final String id;
  final String providerId;
  final String model;
  final int contextWindowTokens;
  final bool contextWindowDetected;

  AiModelProfile copyWith({
    String? providerId,
    String? model,
    int? contextWindowTokens,
    bool? contextWindowDetected,
  }) => AiModelProfile(
    id: id,
    providerId: providerId ?? this.providerId,
    model: model ?? this.model,
    contextWindowTokens: contextWindowTokens ?? this.contextWindowTokens,
    contextWindowDetected: contextWindowDetected ?? this.contextWindowDetected,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'provider_id': providerId,
    'model': model,
    'context_window_tokens': contextWindowTokens,
    'context_window_detected': contextWindowDetected,
  };

  static AiModelProfile? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final providerId = value['provider_id'];
    final model = value['model'];
    if (id is! String ||
        id.trim().isEmpty ||
        providerId is! String ||
        providerId.trim().isEmpty ||
        model is! String ||
        model.trim().isEmpty) {
      return null;
    }
    final rawContext = value['context_window_tokens'];
    final parsedContext = switch (rawContext) {
      int() => rawContext,
      num() => rawContext.toInt(),
      String() => int.tryParse(rawContext),
      _ => null,
    };
    return AiModelProfile(
      id: id.trim(),
      providerId: providerId.trim(),
      model: model.trim(),
      contextWindowTokens:
          parsedContext != null &&
              parsedContext >= minimumContextWindowTokens &&
              parsedContext <= maximumContextWindowTokens
          ? parsedContext
          : defaultContextWindowTokens,
      contextWindowDetected: value['context_window_detected'] == true,
    );
  }
}

enum AiFeature { translation, summary, reply }

enum AiModelCandidateKind { applePcc, appleOnDevice, server, telegramCocoon }

@immutable
class AiModelCandidate {
  const AiModelCandidate._({
    required this.id,
    required this.kind,
    this.profile,
    this.serverProvider,
  });

  const AiModelCandidate.applePcc()
    : this._(
        id: AiSettingsController.applePccModelCandidateId,
        kind: AiModelCandidateKind.applePcc,
      );

  const AiModelCandidate.appleOnDevice()
    : this._(
        id: AiSettingsController.appleOnDeviceModelCandidateId,
        kind: AiModelCandidateKind.appleOnDevice,
      );

  const AiModelCandidate.telegramCocoon()
    : this._(
        id: AiSettingsController.telegramCocoonModelCandidateId,
        kind: AiModelCandidateKind.telegramCocoon,
      );

  factory AiModelCandidate.server({
    required AiModelProfile profile,
    required AiServerProvider provider,
  }) => AiModelCandidate._(
    id: AiSettingsController.serverModelCandidateId(profile.id),
    kind: AiModelCandidateKind.server,
    profile: profile,
    serverProvider: provider,
  );

  final String id;
  final AiModelCandidateKind kind;
  final AiModelProfile? profile;
  final AiServerProvider? serverProvider;

  AiProviderMode get providerMode => switch (kind) {
    AiModelCandidateKind.applePcc => AiProviderMode.applePcc,
    AiModelCandidateKind.appleOnDevice => AiProviderMode.appleOnDevice,
    AiModelCandidateKind.server => AiProviderMode.openAiCompatible,
    AiModelCandidateKind.telegramCocoon => throw UnsupportedError(
      'Telegram Cocoon is a reply-only specialized provider.',
    ),
  };

  String get model => profile?.model ?? '';
  int? get contextWindowTokens => profile?.contextWindowTokens;
}

@immutable
class AiFeatureModelConfiguration {
  const AiFeatureModelConfiguration({
    required this.candidate,
    required this.endpoint,
    required this.endpointStyle,
    required this.apiKey,
    required this.contextWindowTokens,
  });

  final AiModelCandidate candidate;
  final Uri? endpoint;
  final AiEndpointStyle endpointStyle;
  final String apiKey;
  final int? contextWindowTokens;

  AiProviderMode get providerMode => candidate.providerMode;
  String get model => candidate.model;
}

typedef AiSecureRead = Future<String?> Function(String key);
typedef AiSecureWrite = Future<void> Function(String key, String? value);

/// Global provider and model settings shared by AI features.
///
/// Provider and model metadata live in separate [SharedPreferences] records.
/// Every provider has its own API key entry in platform secure storage; keys
/// are never serialized with either record.
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
  // Combined provider/model records used before providers and models were
  // separated. Kept only as a migration source.
  static const apiKeyStorageKey = 'mithka.ai.api_key.v1';
  static const serverProfilesPreferenceKey = 'ai.custom_server.profiles.v1';
  static const activeServerProfileIdPreferenceKey =
      'ai.custom_server.active_profile_id';
  static const serverProvidersPreferenceKey = 'ai.custom_server.providers.v2';
  static const modelProfilesPreferenceKey = 'ai.custom_server.models.v1';
  static const activeServerProviderIdPreferenceKey =
      'ai.custom_server.active_provider_id.v2';
  static const activeModelProfileIdPreferenceKey =
      'ai.custom_server.active_model_id.v1';
  static const translationModelCandidatePreferenceKey =
      'ai.feature.translation.model_candidate.v1';
  static const summaryModelCandidatePreferenceKey =
      'ai.feature.summary.model_candidate.v1';
  static const replyModelCandidatePreferenceKey =
      'ai.feature.reply.model_candidate.v1';
  static const applePccModelCandidateId = 'builtin:apple_pcc';
  static const appleOnDeviceModelCandidateId = 'builtin:apple_on_device';
  static const telegramCocoonModelCandidateId = 'builtin:telegram_cocoon';
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
  List<AiServerProvider> _serverProviders = const [];
  List<AiModelProfile> _modelProfiles = const [];
  String? _activeServerProviderId;
  String? _activeModelProfileId;
  String _translationModelCandidateId = applePccModelCandidateId;
  String _summaryModelCandidateId = applePccModelCandidateId;
  String _replyModelCandidateId = telegramCocoonModelCandidateId;
  final Map<String, String> _profileApiKeys = {};
  ApplePccCapabilities? _pccCapabilities;

  bool get initialized => _initialized;
  bool get enabled => _enabled;
  AiProviderMode get provider => _provider;
  List<AiServerProvider> get serverProviders => _serverProviders;
  List<AiModelProfile> get modelProfiles => _modelProfiles;
  String? get activeServerProviderId => _activeServerProviderId;
  String? get activeModelProfileId => _activeModelProfileId;
  AiServerProvider? get activeServerProvider {
    final id = _activeServerProviderId;
    if (id == null) return null;
    for (final provider in _serverProviders) {
      if (provider.id == id) return provider;
    }
    return null;
  }

  AiModelProfile? get activeModelProfile {
    final id = _activeModelProfileId;
    if (id == null) return null;
    for (final profile in _modelProfiles) {
      if (profile.id == id && profile.providerId == _activeServerProviderId) {
        return profile;
      }
    }
    return null;
  }

  List<AiModelProfile> modelsForProvider(String providerId) =>
      List.unmodifiable(
        _modelProfiles.where((profile) => profile.providerId == providerId),
      );

  List<AiModelCandidate> get modelCandidates => List.unmodifiable([
    const AiModelCandidate.applePcc(),
    const AiModelCandidate.appleOnDevice(),
    for (final profile in _modelProfiles)
      if (_providerById(profile.providerId) case final provider?)
        AiModelCandidate.server(profile: profile, provider: provider),
  ]);

  List<AiModelCandidate> modelCandidatesForFeature(AiFeature feature) =>
      switch (feature) {
        AiFeature.translation || AiFeature.summary => modelCandidates,
        AiFeature.reply => List.unmodifiable([
          const AiModelCandidate.telegramCocoon(),
          ...modelCandidates,
        ]),
      };

  String get translationModelCandidateId => _translationModelCandidateId;
  String get summaryModelCandidateId => _summaryModelCandidateId;
  String get replyModelCandidateId => _replyModelCandidateId;
  AiModelCandidate get translationModelCandidate =>
      modelCandidateById(_translationModelCandidateId) ??
      const AiModelCandidate.applePcc();
  AiModelCandidate get summaryModelCandidate =>
      modelCandidateById(_summaryModelCandidateId) ??
      const AiModelCandidate.applePcc();
  AiModelCandidate get replyModelCandidate =>
      modelCandidateByIdForFeature(AiFeature.reply, _replyModelCandidateId) ??
      const AiModelCandidate.telegramCocoon();

  String modelCandidateIdForFeature(AiFeature feature) => switch (feature) {
    AiFeature.translation => _translationModelCandidateId,
    AiFeature.summary => _summaryModelCandidateId,
    AiFeature.reply => _replyModelCandidateId,
  };

  AiModelCandidate modelCandidateForFeature(AiFeature feature) =>
      switch (feature) {
        AiFeature.translation => translationModelCandidate,
        AiFeature.summary => summaryModelCandidate,
        AiFeature.reply => replyModelCandidate,
      };

  AiModelCandidate? modelCandidateById(String? id) {
    if (id == null) return null;
    for (final candidate in modelCandidates) {
      if (candidate.id == id) return candidate;
    }
    return null;
  }

  AiModelCandidate? modelCandidateByIdForFeature(
    AiFeature feature,
    String? id,
  ) {
    if (id == null) return null;
    for (final candidate in modelCandidatesForFeature(feature)) {
      if (candidate.id == id) return candidate;
    }
    return null;
  }

  AiFeatureModelConfiguration configurationForFeature(AiFeature feature) {
    final candidate = modelCandidateForFeature(feature);
    final provider = candidate.serverProvider;
    Uri? endpoint;
    if (provider != null) {
      try {
        endpoint = validateOpenAiCompatibleEndpoint(
          provider.endpoint,
          endpointStyle: provider.endpointStyle,
        );
      } on FormatException {
        endpoint = null;
      }
    }
    return AiFeatureModelConfiguration(
      candidate: candidate,
      endpoint: endpoint,
      endpointStyle:
          provider?.endpointStyle ?? AiEndpointStyle.openAiChatCompletions,
      apiKey: provider == null ? '' : apiKeyForServerProvider(provider.id),
      contextWindowTokens: switch (candidate.kind) {
        AiModelCandidateKind.applePcc => _pccCapabilities?.contextSize,
        AiModelCandidateKind.appleOnDevice =>
          _pccCapabilities?.onDeviceContextSize,
        AiModelCandidateKind.server => candidate.contextWindowTokens,
        AiModelCandidateKind.telegramCocoon => null,
      },
    );
  }

  bool isConfiguredForFeature(AiFeature feature) {
    final configuration = configurationForFeature(feature);
    return switch (configuration.candidate.kind) {
      AiModelCandidateKind.applePcc =>
        _pccCapabilities?.available == true &&
            _pccCapabilities?.quotaLimitReached != true,
      AiModelCandidateKind.appleOnDevice =>
        _pccCapabilities?.onDeviceAvailable == true,
      AiModelCandidateKind.server =>
        configuration.model.isNotEmpty && configuration.endpoint != null,
      AiModelCandidateKind.telegramCocoon => true,
    };
  }

  // Compatibility aliases for callers that only need provider identity.
  List<AiServerProvider> get serverProfiles => serverProviders;
  String? get activeServerProfileId => activeServerProviderId;
  AiServerProvider? get activeServerProfile => activeServerProvider;

  String get endpoint => activeServerProvider?.endpoint ?? '';
  String get model => activeModelProfile?.model ?? '';
  String get apiKey => _profileApiKeys[_activeServerProviderId] ?? '';
  String apiKeyForServerProvider(String providerId) =>
      _profileApiKeys[providerId] ?? '';
  String apiKeyForServerProfile(String profileId) =>
      apiKeyForServerProvider(profileId);
  bool get hasApiKey => apiKey.isNotEmpty;
  ApplePccCapabilities? get pccCapabilities => _pccCapabilities;

  bool get isConfiguredForCurrentProvider => switch (_provider) {
    AiProviderMode.applePcc =>
      _pccCapabilities?.available == true &&
          _pccCapabilities?.quotaLimitReached != true,
    AiProviderMode.appleOnDevice => _pccCapabilities?.onDeviceAvailable == true,
    AiProviderMode.openAiCompatible =>
      model.isNotEmpty &&
          isValidOpenAiCompatibleEndpoint(
            endpoint,
            endpointStyle: activeServerProvider?.endpointStyle,
          ),
  };

  Uri? get openAiChatCompletionsUri {
    if (_provider != AiProviderMode.openAiCompatible || endpoint.isEmpty) {
      return null;
    }
    try {
      return validateOpenAiCompatibleEndpoint(
        endpoint,
        endpointStyle: activeServerProvider?.endpointStyle,
      );
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
    _serverProviders = _readStoredProviders();
    _modelProfiles = _readStoredModels();
    _activeServerProviderId = _preferences.getString(
      activeServerProviderIdPreferenceKey,
    );
    _activeModelProfileId = _preferences.getString(
      activeModelProfileIdPreferenceKey,
    );

    var migratedLegacyConfiguration = false;
    if (_serverProviders.isEmpty) {
      final migrated = _readLegacyProfiles();
      if (migrated.providers.isNotEmpty) {
        _serverProviders = migrated.providers;
        _modelProfiles = migrated.models;
        final legacyActiveId = _preferences.getString(
          activeServerProfileIdPreferenceKey,
        );
        _activeServerProviderId =
            migrated.providers.any((provider) => provider.id == legacyActiveId)
            ? legacyActiveId
            : migrated.providers.first.id;
        _activeModelProfileId = _modelProfiles
            .where((model) => model.providerId == _activeServerProviderId)
            .firstOrNull
            ?.id;
        migratedLegacyConfiguration = true;
      }
    }
    if (_serverProviders.isEmpty) {
      final storedEndpoint =
          _preferences.getString(endpointPreferenceKey)?.trim() ?? '';
      final normalizedEndpoint = _normalizeStoredEndpoint(storedEndpoint);
      if (normalizedEndpoint.isNotEmpty) {
        final uri = Uri.parse(normalizedEndpoint);
        final provider = AiServerProvider(
          id: 'legacy',
          name: uri.host,
          endpoint: normalizedEndpoint,
          endpointStyle:
              AiEndpointStyle.inferFromEndpoint(normalizedEndpoint) ??
              AiEndpointStyle.openAiChatCompletions,
        );
        _serverProviders = [provider];
        _activeServerProviderId = provider.id;
        final legacyModel = _preferences.getString(modelPreferenceKey)?.trim();
        if (legacyModel != null && legacyModel.isNotEmpty) {
          final model = AiModelProfile(
            id: _legacyModelId(provider.id),
            providerId: provider.id,
            model: legacyModel,
          );
          _modelProfiles = [model];
          _activeModelProfileId = model.id;
        }
        migratedLegacyConfiguration = true;
      }
    }
    if (_serverProviders.isNotEmpty &&
        !_serverProviders.any((p) => p.id == _activeServerProviderId)) {
      _activeServerProviderId = _serverProviders.first.id;
    }
    _removeOrphanedModels();
    _ensureActiveModelMatchesProvider();
    final legacyCandidateId = _legacyFeatureModelCandidateId();
    final storedTranslationCandidate = _preferences.getString(
      translationModelCandidatePreferenceKey,
    );
    final storedSummaryCandidate = _preferences.getString(
      summaryModelCandidatePreferenceKey,
    );
    final storedReplyCandidate = _preferences.getString(
      replyModelCandidatePreferenceKey,
    );
    _translationModelCandidateId =
        modelCandidateById(storedTranslationCandidate)?.id ?? legacyCandidateId;
    _summaryModelCandidateId =
        modelCandidateById(storedSummaryCandidate)?.id ?? legacyCandidateId;
    _replyModelCandidateId =
        modelCandidateByIdForFeature(
          AiFeature.reply,
          storedReplyCandidate,
        )?.id ??
        telegramCocoonModelCandidateId;
    final migratedFeatureSelections =
        storedTranslationCandidate == null ||
        storedSummaryCandidate == null ||
        storedReplyCandidate == null ||
        storedTranslationCandidate != _translationModelCandidateId ||
        storedSummaryCandidate != _summaryModelCandidateId ||
        storedReplyCandidate != _replyModelCandidateId;

    final keyResults = await Future.wait(
      _serverProviders.map((provider) async {
        final value = await _readSecureValueSafely(_profileKey(provider.id));
        return MapEntry(provider.id, value);
      }),
    );
    for (final entry in keyResults) {
      if (entry.value.isNotEmpty) _profileApiKeys[entry.key] = entry.value;
    }
    if (_serverProviders.any((provider) => provider.id == 'legacy') &&
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
    if (migratedLegacyConfiguration || migratedFeatureSelections) {
      await _persistConfiguration();
    }
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

  Future<void> setFeatureModelCandidate(
    AiFeature feature,
    String candidateId,
  ) async {
    if (modelCandidateByIdForFeature(feature, candidateId) == null) return;
    final current = modelCandidateIdForFeature(feature);
    if (current == candidateId) return;
    switch (feature) {
      case AiFeature.translation:
        _translationModelCandidateId = candidateId;
      case AiFeature.summary:
        _summaryModelCandidateId = candidateId;
      case AiFeature.reply:
        _replyModelCandidateId = candidateId;
    }
    await _persistFeatureModelSelections();
    notifyListeners();
  }

  Future<List<OpenAiCompatibleModelInfo>> discoverModels({
    required String endpoint,
    required String apiKey,
    String? preferredModel,
    AiEndpointStyle? endpointStyle,
  }) async {
    final resolvedStyle =
        endpointStyle ??
        AiEndpointStyle.inferFromEndpoint(endpoint) ??
        AiEndpointStyle.openAiChatCompletions;
    final uri = validateOpenAiCompatibleEndpoint(
      endpoint,
      endpointStyle: resolvedStyle,
    );
    final models = await _modelsApi.listModels(
      chatCompletionsUri: uri,
      apiKey: apiKey,
      endpointStyle: resolvedStyle,
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
        endpointStyle: resolvedStyle,
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
    AiEndpointStyle? endpointStyle,
  }) {
    final resolvedStyle =
        endpointStyle ??
        AiEndpointStyle.inferFromEndpoint(endpoint) ??
        AiEndpointStyle.openAiChatCompletions;
    return _modelsApi.retrieveModel(
      chatCompletionsUri: validateOpenAiCompatibleEndpoint(
        endpoint,
        endpointStyle: resolvedStyle,
      ),
      modelId: model,
      apiKey: apiKey,
      endpointStyle: resolvedStyle,
    );
  }

  Future<String> testServerModel({
    required String providerId,
    required String model,
    required String prompt,
  }) {
    final provider = _providerById(providerId);
    if (provider == null) {
      throw const FormatException('The selected AI provider no longer exists.');
    }
    return _modelsApi.testModel(
      chatCompletionsUri: provider.chatCompletionsUri,
      model: model,
      prompt: prompt,
      apiKey: _profileApiKeys[providerId],
      endpointStyle: provider.endpointStyle,
    );
  }

  Future<List<OpenAiCompatibleModelInfo>> refreshModelsForProvider(
    String providerId,
  ) async {
    final provider = _providerById(providerId);
    if (provider == null) {
      throw const FormatException('The selected AI provider no longer exists.');
    }
    final selectedModel = _modelProfiles
        .where(
          (model) =>
              model.providerId == providerId &&
              model.id == _activeModelProfileId,
        )
        .firstOrNull;
    final models = await discoverModels(
      endpoint: provider.endpoint,
      apiKey: _profileApiKeys[providerId] ?? '',
      preferredModel: selectedModel?.model,
      endpointStyle: provider.endpointStyle,
    );
    final selectedResult = models.where(
      (item) => item.id == selectedModel?.model,
    );
    final discoveredContext = selectedResult.isEmpty
        ? null
        : selectedResult.first.contextWindowTokens;
    await _replaceProvider(
      provider.copyWith(availableModels: List.unmodifiable(models)),
      notify: false,
    );
    if (selectedModel != null && discoveredContext != null) {
      await _replaceModel(
        selectedModel.copyWith(
          contextWindowTokens: discoveredContext,
          contextWindowDetected: true,
        ),
        notify: false,
      );
    }
    notifyListeners();
    return models;
  }

  Future<List<OpenAiCompatibleModelInfo>> refreshModelsForProfile(
    String profileId,
  ) => refreshModelsForProvider(profileId);

  Future<AiServerProvider> saveServerProvider({
    String? id,
    required String name,
    required String endpoint,
    required String apiKey,
    AiEndpointStyle? endpointStyle,
    List<OpenAiCompatibleModelInfo>? availableModels,
  }) async {
    final normalizedId = id?.trim();
    final providerId = normalizedId != null && normalizedId.isNotEmpty
        ? normalizedId
        : _newId('provider');
    final existing = _providerById(providerId);
    final resolvedStyle =
        endpointStyle ??
        AiEndpointStyle.inferFromEndpoint(endpoint) ??
        existing?.endpointStyle ??
        AiEndpointStyle.openAiChatCompletions;
    final uri = validateOpenAiCompatibleEndpoint(
      endpoint,
      endpointStyle: resolvedStyle,
    );
    final provider = AiServerProvider(
      id: providerId,
      name: name.trim().isEmpty ? uri.host : name.trim(),
      endpoint: uri.toString(),
      endpointStyle: resolvedStyle,
      availableModels: List.unmodifiable(
        availableModels ?? existing?.availableModels ?? const [],
      ),
    );
    final normalizedKey = apiKey.trim();
    await _secureWrite(
      _profileKey(providerId),
      normalizedKey.isEmpty ? null : normalizedKey,
    );
    if (normalizedKey.isEmpty) {
      _profileApiKeys.remove(providerId);
    } else {
      _profileApiKeys[providerId] = normalizedKey;
    }
    await _replaceProvider(provider, makeActive: true);
    return provider;
  }

  Future<AiModelProfile> saveModelProfile({
    String? id,
    required String providerId,
    required String model,
    required int contextWindowTokens,
    bool contextWindowDetected = false,
  }) async {
    if (_providerById(providerId) == null) {
      throw const FormatException('An AI provider is required.');
    }
    final normalizedModel = model.trim();
    if (normalizedModel.isEmpty) {
      throw const FormatException('A model is required.');
    }
    if (contextWindowTokens < AiModelProfile.minimumContextWindowTokens ||
        contextWindowTokens > AiModelProfile.maximumContextWindowTokens) {
      throw const FormatException(
        'The context window is outside the supported range.',
      );
    }
    final normalizedId = id?.trim();
    final existing = normalizedId == null || normalizedId.isEmpty
        ? _modelProfiles
              .where(
                (profile) =>
                    profile.providerId == providerId &&
                    profile.model == normalizedModel,
              )
              .firstOrNull
        : _modelById(normalizedId);
    final profile = AiModelProfile(
      id: existing?.id ?? _newId('model'),
      providerId: providerId,
      model: normalizedModel,
      contextWindowTokens: contextWindowTokens,
      contextWindowDetected: contextWindowDetected,
    );
    await _replaceModel(profile, makeActive: true);
    return profile;
  }

  Future<void> selectServerProvider(String providerId) async {
    if (_providerById(providerId) == null) return;
    if (_activeServerProviderId == providerId && activeModelProfile != null) {
      return;
    }
    _activeServerProviderId = providerId;
    _ensureActiveModelMatchesProvider();
    await _persistConfiguration();
    notifyListeners();
  }

  Future<void> selectModelProfile(String modelProfileId) async {
    final profile = _modelById(modelProfileId);
    if (profile == null || _providerById(profile.providerId) == null) return;
    if (_activeModelProfileId == profile.id &&
        _activeServerProviderId == profile.providerId) {
      return;
    }
    _activeServerProviderId = profile.providerId;
    _activeModelProfileId = profile.id;
    await _persistConfiguration();
    notifyListeners();
  }

  Future<void> deleteServerProvider(String providerId) async {
    if (_providerById(providerId) == null) return;
    await _secureWrite(_profileKey(providerId), null);
    _profileApiKeys.remove(providerId);
    _serverProviders = List.unmodifiable(
      _serverProviders.where((provider) => provider.id != providerId),
    );
    _modelProfiles = List.unmodifiable(
      _modelProfiles.where((model) => model.providerId != providerId),
    );
    if (_activeServerProviderId == providerId) {
      _activeServerProviderId = _serverProviders.firstOrNull?.id;
    }
    _ensureActiveModelMatchesProvider();
    _repairFeatureModelSelections();
    await _persistConfiguration();
    notifyListeners();
  }

  Future<void> deleteModelProfile(String modelProfileId) async {
    if (_modelById(modelProfileId) == null) return;
    _modelProfiles = List.unmodifiable(
      _modelProfiles.where((model) => model.id != modelProfileId),
    );
    if (_activeModelProfileId == modelProfileId) {
      _activeModelProfileId = null;
      _ensureActiveModelMatchesProvider();
    }
    _repairFeatureModelSelections();
    await _persistConfiguration();
    notifyListeners();
  }

  Future<void> selectServerProfile(String profileId) =>
      selectServerProvider(profileId);

  Future<void> deleteServerProfile(String profileId) =>
      deleteServerProvider(profileId);

  /// Compatibility bridge for older callers that still submit one combined
  /// provider/model form. New UI saves these records independently.
  Future<AiServerProvider> saveServerProfile({
    String? id,
    required String name,
    required String endpoint,
    required String model,
    required String apiKey,
    AiEndpointStyle? endpointStyle,
    required int contextWindowTokens,
    bool contextWindowDetected = false,
    List<OpenAiCompatibleModelInfo>? availableModels,
  }) async {
    final provider = await saveServerProvider(
      id: id,
      name: name,
      endpoint: endpoint,
      apiKey: apiKey,
      endpointStyle: endpointStyle,
      availableModels: availableModels,
    );
    await saveModelProfile(
      providerId: provider.id,
      model: model,
      contextWindowTokens: contextWindowTokens,
      contextWindowDetected: contextWindowDetected,
    );
    return provider;
  }

  // Compatibility helpers for callers that still edit the active server one
  // field at a time. New UI should commit an entire provider atomically.
  Future<void> setEndpoint(String value) async {
    final active = activeServerProvider;
    final endpointStyle =
        AiEndpointStyle.inferFromEndpoint(value) ??
        active?.endpointStyle ??
        AiEndpointStyle.openAiChatCompletions;
    final endpoint = validateOpenAiCompatibleEndpoint(
      value,
      endpointStyle: endpointStyle,
    ).toString();
    if (active == null) {
      final uri = Uri.parse(endpoint);
      final provider = AiServerProvider(
        id: _newId('provider'),
        name: uri.host,
        endpoint: endpoint,
        endpointStyle: endpointStyle,
      );
      await _replaceProvider(provider, makeActive: true);
      return;
    }
    await _replaceProvider(
      active.copyWith(endpoint: endpoint, endpointStyle: endpointStyle),
    );
  }

  Future<void> setModel(String value) async {
    final providerId = _activeServerProviderId;
    if (providerId == null || value.trim().isEmpty) return;
    final active = activeModelProfile;
    await saveModelProfile(
      id: active?.id,
      providerId: providerId,
      model: value,
      contextWindowTokens:
          active?.contextWindowTokens ??
          AiModelProfile.defaultContextWindowTokens,
      contextWindowDetected: active?.contextWindowDetected ?? false,
    );
  }

  Future<void> setApiKey(String value) async {
    final id = _activeServerProviderId;
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

  static bool isValidOpenAiCompatibleEndpoint(
    String value, {
    AiEndpointStyle? endpointStyle,
  }) {
    try {
      validateOpenAiCompatibleEndpoint(value, endpointStyle: endpointStyle);
      return true;
    } on FormatException {
      return false;
    }
  }

  static Uri validateOpenAiCompatibleEndpoint(
    String value, {
    AiEndpointStyle? endpointStyle,
  }) {
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
    final resolvedStyle =
        endpointStyle ??
        AiEndpointStyle.inferFromEndpoint(trimmed) ??
        AiEndpointStyle.openAiChatCompletions;
    if (!uri.path.endsWith(resolvedStyle.endpointSuffix)) {
      throw FormatException(
        'The server endpoint path must end in '
        '${resolvedStyle.endpointSuffix}.',
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

  List<AiServerProvider> _readStoredProviders() {
    final encoded = _preferences.getString(serverProvidersPreferenceKey);
    if (encoded == null || encoded.isEmpty) return const [];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return const [];
      final providers = <AiServerProvider>[];
      final ids = <String>{};
      for (final value in decoded) {
        final provider = AiServerProvider.fromJson(value);
        if (provider != null && ids.add(provider.id)) providers.add(provider);
      }
      return List.unmodifiable(providers);
    } on FormatException {
      return const [];
    }
  }

  List<AiModelProfile> _readStoredModels() {
    final encoded = _preferences.getString(modelProfilesPreferenceKey);
    if (encoded == null || encoded.isEmpty) return const [];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return const [];
      final models = <AiModelProfile>[];
      final ids = <String>{};
      for (final value in decoded) {
        final model = AiModelProfile.fromJson(value);
        if (model != null && ids.add(model.id)) models.add(model);
      }
      return List.unmodifiable(models);
    } on FormatException {
      return const [];
    }
  }

  ({List<AiServerProvider> providers, List<AiModelProfile> models})
  _readLegacyProfiles() {
    final encoded = _preferences.getString(serverProfilesPreferenceKey);
    if (encoded == null || encoded.isEmpty) {
      return (providers: const [], models: const []);
    }
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) {
        return (providers: const [], models: const []);
      }
      final providers = <AiServerProvider>[];
      final models = <AiModelProfile>[];
      final ids = <String>{};
      for (final value in decoded) {
        final provider = AiServerProvider.fromJson(value);
        if (provider == null || !ids.add(provider.id)) continue;
        providers.add(provider);
        if (value is! Map) continue;
        final rawModel = value['model'];
        if (rawModel is! String || rawModel.trim().isEmpty) continue;
        final rawContext = value['context_window_tokens'];
        final parsedContext = switch (rawContext) {
          int() => rawContext,
          num() => rawContext.toInt(),
          String() => int.tryParse(rawContext),
          _ => null,
        };
        models.add(
          AiModelProfile(
            id: _legacyModelId(provider.id),
            providerId: provider.id,
            model: rawModel.trim(),
            contextWindowTokens:
                parsedContext != null &&
                    parsedContext >=
                        AiModelProfile.minimumContextWindowTokens &&
                    parsedContext <= AiModelProfile.maximumContextWindowTokens
                ? parsedContext
                : AiModelProfile.defaultContextWindowTokens,
            contextWindowDetected: value['context_window_detected'] == true,
          ),
        );
      }
      return (
        providers: List.unmodifiable(providers),
        models: List.unmodifiable(models),
      );
    } on FormatException {
      return (providers: const [], models: const []);
    }
  }

  Future<void> _replaceProvider(
    AiServerProvider provider, {
    bool makeActive = false,
    bool notify = true,
  }) async {
    final providers = _serverProviders.toList();
    final index = providers.indexWhere((item) => item.id == provider.id);
    if (index < 0) {
      providers.add(provider);
    } else {
      providers[index] = provider;
    }
    _serverProviders = List.unmodifiable(providers);
    if (makeActive || _activeServerProviderId == null) {
      _activeServerProviderId = provider.id;
      _ensureActiveModelMatchesProvider();
    }
    await _persistConfiguration();
    if (notify) notifyListeners();
  }

  Future<void> _replaceModel(
    AiModelProfile model, {
    bool makeActive = false,
    bool notify = true,
  }) async {
    final models = _modelProfiles.toList();
    final index = models.indexWhere((item) => item.id == model.id);
    if (index < 0) {
      models.add(model);
    } else {
      models[index] = model;
    }
    _modelProfiles = List.unmodifiable(models);
    if (makeActive || _activeModelProfileId == null) {
      _activeServerProviderId = model.providerId;
      _activeModelProfileId = model.id;
    }
    await _persistConfiguration();
    if (notify) notifyListeners();
  }

  Future<void> _persistConfiguration() async {
    // Models are written first so an interrupted legacy migration can safely
    // retry from the old combined provider records on the next launch.
    await _preferences.setString(
      modelProfilesPreferenceKey,
      jsonEncode(_modelProfiles.map((model) => model.toJson()).toList()),
    );
    await _preferences.setString(
      serverProvidersPreferenceKey,
      jsonEncode(
        _serverProviders.map((provider) => provider.toJson()).toList(),
      ),
    );
    final activeProviderId = _activeServerProviderId;
    if (activeProviderId == null) {
      await _preferences.remove(activeServerProviderIdPreferenceKey);
    } else {
      await _preferences.setString(
        activeServerProviderIdPreferenceKey,
        activeProviderId,
      );
    }
    final activeModelId = _activeModelProfileId;
    if (activeModelId == null) {
      await _preferences.remove(activeModelProfileIdPreferenceKey);
    } else {
      await _preferences.setString(
        activeModelProfileIdPreferenceKey,
        activeModelId,
      );
    }
    await _persistFeatureModelSelections();
  }

  Future<void> _persistFeatureModelSelections() async {
    await _preferences.setString(
      translationModelCandidatePreferenceKey,
      _translationModelCandidateId,
    );
    await _preferences.setString(
      summaryModelCandidatePreferenceKey,
      _summaryModelCandidateId,
    );
    await _preferences.setString(
      replyModelCandidatePreferenceKey,
      _replyModelCandidateId,
    );
  }

  void _removeOrphanedModels() {
    final providerIds = _serverProviders.map((provider) => provider.id).toSet();
    _modelProfiles = List.unmodifiable(
      _modelProfiles.where((model) => providerIds.contains(model.providerId)),
    );
  }

  void _ensureActiveModelMatchesProvider() {
    final providerId = _activeServerProviderId;
    if (providerId == null) {
      _activeModelProfileId = null;
      return;
    }
    final current = _modelById(_activeModelProfileId);
    if (current?.providerId == providerId) return;
    _activeModelProfileId = _modelProfiles
        .where((model) => model.providerId == providerId)
        .firstOrNull
        ?.id;
  }

  void _repairFeatureModelSelections() {
    if (modelCandidateById(_translationModelCandidateId) == null) {
      _translationModelCandidateId = applePccModelCandidateId;
    }
    if (modelCandidateById(_summaryModelCandidateId) == null) {
      _summaryModelCandidateId = applePccModelCandidateId;
    }
    if (modelCandidateByIdForFeature(AiFeature.reply, _replyModelCandidateId) ==
        null) {
      _replyModelCandidateId = telegramCocoonModelCandidateId;
    }
  }

  String _legacyFeatureModelCandidateId() {
    return switch (_provider) {
      AiProviderMode.applePcc => applePccModelCandidateId,
      AiProviderMode.appleOnDevice => appleOnDeviceModelCandidateId,
      AiProviderMode.openAiCompatible =>
        activeModelProfile == null
            ? applePccModelCandidateId
            : serverModelCandidateId(activeModelProfile!.id),
    };
  }

  AiServerProvider? _providerById(String? id) {
    if (id == null) return null;
    for (final provider in _serverProviders) {
      if (provider.id == id) return provider;
    }
    return null;
  }

  AiModelProfile? _modelById(String? id) {
    if (id == null) return null;
    for (final model in _modelProfiles) {
      if (model.id == id) return model;
    }
    return null;
  }

  static String _profileKey(String profileId) =>
      '$_profileApiKeyPrefix$profileId$_profileApiKeySuffix';

  static String _newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  static String serverModelCandidateId(String modelProfileId) =>
      'server:$modelProfileId';

  static String _legacyModelId(String providerId) => '${providerId}_model';

  static String _normalizeStoredEndpoint(String value) {
    if (value.isEmpty) return '';
    try {
      final style =
          AiEndpointStyle.inferFromEndpoint(value) ??
          AiEndpointStyle.openAiChatCompletions;
      return validateOpenAiCompatibleEndpoint(
        value,
        endpointStyle: style,
      ).toString();
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
