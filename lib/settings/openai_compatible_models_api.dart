import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_endpoint_style.dart';

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

  static Uri modelsUriFor(
    Uri endpoint, {
    AiEndpointStyle endpointStyle = AiEndpointStyle.openAiChatCompletions,
  }) => endpointStyle.modelsUriFor(endpoint);

  static Uri? modelUriFor(
    Uri endpoint,
    String modelId, {
    AiEndpointStyle endpointStyle = AiEndpointStyle.openAiChatCompletions,
  }) => endpointStyle.modelUriFor(endpoint, modelId);

  Future<List<OpenAiCompatibleModelInfo>> listModels({
    required Uri chatCompletionsUri,
    String? apiKey,
    AiEndpointStyle endpointStyle = AiEndpointStyle.openAiChatCompletions,
  }) async {
    final response = await _httpClient
        .get(
          modelsUriFor(chatCompletionsUri, endpointStyle: endpointStyle),
          headers: endpointStyle.requestHeaders(apiKey),
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
    if (decoded is! Map) {
      throw const OpenAiCompatibleModelsException(
        'The model list response is not an object.',
      );
    }
    final rawModels = endpointStyle == AiEndpointStyle.ollamaChat
        ? decoded['models']
        : decoded['data'];
    if (rawModels is! List) {
      throw const OpenAiCompatibleModelsException(
        'The model list response has no model array.',
      );
    }
    final byId = <String, OpenAiCompatibleModelInfo>{};
    for (final raw in rawModels) {
      final model = endpointStyle == AiEndpointStyle.ollamaChat && raw is Map
          ? OpenAiCompatibleModelInfo.fromJson({
              'id': raw['model'] ?? raw['name'],
              ...raw,
            })
          : OpenAiCompatibleModelInfo.fromJson(raw);
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
    AiEndpointStyle endpointStyle = AiEndpointStyle.openAiChatCompletions,
  }) async {
    final normalizedModelId = modelId.trim();
    if (normalizedModelId.isEmpty) return null;
    final modelUri = modelUriFor(
      chatCompletionsUri,
      normalizedModelId,
      endpointStyle: endpointStyle,
    );
    if (modelUri == null) return null;
    final response = await _httpClient
        .get(modelUri, headers: endpointStyle.requestHeaders(apiKey))
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

  Future<String> testModel({
    required Uri chatCompletionsUri,
    required String model,
    required String prompt,
    String? apiKey,
    AiEndpointStyle endpointStyle = AiEndpointStyle.openAiChatCompletions,
  }) async {
    final normalizedModel = model.trim();
    final normalizedPrompt = prompt.trim();
    if (normalizedModel.isEmpty || normalizedPrompt.isEmpty) {
      throw const FormatException('A model and test prompt are required.');
    }
    final response = await _httpClient
        .post(
          endpointStyle.requestUriFor(chatCompletionsUri),
          headers: endpointStyle.requestHeaders(apiKey),
          body: jsonEncode(
            endpointStyle.requestBody(
              model: normalizedModel,
              instructions: '',
              input: normalizedPrompt,
              stream: false,
            ),
          ),
        )
        .timeout(requestTimeout);
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenAiCompatibleModelsException(
        _errorMessage(body),
        statusCode: response.statusCode,
      );
    }
    return _completionText(body, endpointStyle);
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

  String _completionText(String body, AiEndpointStyle endpointStyle) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (error) {
      throw OpenAiCompatibleModelsException(
        'The model test returned invalid JSON: $error',
      );
    }
    if (decoded is! Map) {
      throw const OpenAiCompatibleModelsException(
        'The model test response is not an object.',
      );
    }
    final content = endpointStyle.responseText(decoded);
    if (content != null && content.trim().isNotEmpty) return content.trim();
    final refusal = endpointStyle.refusalText(decoded);
    if (refusal != null) {
      throw OpenAiCompatibleModelsException(
        'The model refused the test prompt: ${refusal.trim()}',
      );
    }
    throw const OpenAiCompatibleModelsException(
      'The model test returned an empty response.',
    );
  }
}
