import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class OpenAiCompatibleModelInfo {
  const OpenAiCompatibleModelInfo({required this.id, this.contextWindowTokens});

  final String id;
  final int? contextWindowTokens;

  Map<String, Object?> toJson() => {
    'id': id,
    if (contextWindowTokens != null)
      'context_window_tokens': contextWindowTokens,
  };

  static OpenAiCompatibleModelInfo? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    if (id is! String || id.trim().isEmpty) return null;
    return OpenAiCompatibleModelInfo(
      id: id.trim(),
      contextWindowTokens: _readContextWindow(value),
    );
  }

  static int? _readContextWindow(Map<dynamic, dynamic> value) {
    const keys = [
      'context_window_tokens',
      'contextWindowTokens',
      'context_window',
      'contextWindow',
      'context_length',
      'contextLength',
      'max_context_length',
      'maxContextLength',
      'max_model_len',
      'maxModelLen',
      'max_input_tokens',
      'maxInputTokens',
      'input_token_limit',
      'inputTokenLimit',
    ];
    for (final key in keys) {
      final parsed = _positiveInt(value[key]);
      if (parsed != null) return parsed;
    }
    for (final containerKey in const ['metadata', 'capabilities', 'limits']) {
      final container = value[containerKey];
      if (container is Map) {
        for (final key in keys) {
          final parsed = _positiveInt(container[key]);
          if (parsed != null) return parsed;
        }
      }
    }
    return null;
  }

  static int? _positiveInt(Object? value) {
    final parsed = switch (value) {
      int() => value,
      num() => value.toInt(),
      String() => int.tryParse(value.trim()),
      _ => null,
    };
    return parsed != null && parsed > 0 ? parsed : null;
  }
}

class OpenAiCompatibleModelsException implements Exception {
  const OpenAiCompatibleModelsException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class OpenAiCompatibleModelsApi {
  OpenAiCompatibleModelsApi({
    http.Client? httpClient,
    this.requestTimeout = const Duration(seconds: 20),
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Duration requestTimeout;

  static Uri modelsUriFor(Uri chatCompletionsUri) {
    var path = chatCompletionsUri.path;
    while (path.endsWith('/') && path.length > 1) {
      path = path.substring(0, path.length - 1);
    }
    if (!path.endsWith('/v1/chat/completions')) {
      throw const FormatException(
        'The server endpoint path must end in /v1/chat/completions.',
      );
    }
    final prefix = path.substring(
      0,
      path.length - '/v1/chat/completions'.length,
    );
    return chatCompletionsUri.replace(path: '$prefix/v1/models');
  }

  static Uri modelUriFor(Uri chatCompletionsUri, String modelId) {
    final modelsUri = modelsUriFor(chatCompletionsUri);
    return modelsUri.replace(
      pathSegments: [...modelsUri.pathSegments, modelId.trim()],
    );
  }

  Future<List<OpenAiCompatibleModelInfo>> listModels({
    required Uri chatCompletionsUri,
    String? apiKey,
  }) async {
    final key = apiKey?.trim();
    final response = await _httpClient
        .get(
          modelsUriFor(chatCompletionsUri),
          headers: {
            'accept': 'application/json',
            if (key != null && key.isNotEmpty) 'authorization': 'Bearer $key',
          },
        )
        .timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenAiCompatibleModelsException(
        _errorMessage(response.body),
        statusCode: response.statusCode,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (error) {
      throw OpenAiCompatibleModelsException(
        'The model list returned invalid JSON: $error',
      );
    }
    if (decoded is! Map || decoded['data'] is! List) {
      throw const OpenAiCompatibleModelsException(
        'The model list response has no data array.',
      );
    }
    final byId = <String, OpenAiCompatibleModelInfo>{};
    for (final raw in decoded['data'] as List) {
      final model = OpenAiCompatibleModelInfo.fromJson(raw);
      if (model != null) byId[model.id] = model;
    }
    final models = byId.values.toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    return models;
  }

  /// Fetches the standard per-model detail resource. Providers that do not
  /// implement it, or that return no context metadata, yield `null` or a model
  /// whose [OpenAiCompatibleModelInfo.contextWindowTokens] is null.
  Future<OpenAiCompatibleModelInfo?> retrieveModel({
    required Uri chatCompletionsUri,
    required String modelId,
    String? apiKey,
  }) async {
    final normalizedModelId = modelId.trim();
    if (normalizedModelId.isEmpty) return null;
    final key = apiKey?.trim();
    final response = await _httpClient
        .get(
          modelUriFor(chatCompletionsUri, normalizedModelId),
          headers: {
            'accept': 'application/json',
            if (key != null && key.isNotEmpty) 'authorization': 'Bearer $key',
          },
        )
        .timeout(requestTimeout);
    if (response.statusCode == 404 ||
        response.statusCode == 405 ||
        response.statusCode == 501) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenAiCompatibleModelsException(
        _errorMessage(response.body),
        statusCode: response.statusCode,
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (error) {
      throw OpenAiCompatibleModelsException(
        'The model details returned invalid JSON: $error',
      );
    }
    final model = OpenAiCompatibleModelInfo.fromJson(
      decoded is Map && decoded['data'] is Map ? decoded['data'] : decoded,
    );
    if (model == null) {
      throw const OpenAiCompatibleModelsException(
        'The model details response has no model ID.',
      );
    }
    return model;
  }

  void close() {
    if (_ownsHttpClient) _httpClient.close();
  }

  String _errorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) {
          return (error['message'] as String).trim();
        }
        if (decoded['message'] is String) {
          return (decoded['message'] as String).trim();
        }
      }
    } on FormatException {
      // Fall through to bounded plain text.
    }
    final compact = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compact.isEmpty) return 'The server rejected the model list request.';
    return compact.length <= 300 ? compact : '${compact.substring(0, 300)}…';
  }
}
