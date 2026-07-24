import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../settings/ai_endpoint_style.dart';
import '../settings/ai_settings_controller.dart';
import '../settings/ai_stdout_logger.dart';
import '../settings/ai_translation_prompt.dart';
import '../settings/apple_pcc_api.dart';
import '../settings/translation_api.dart';

class AiChatTranslationService {
  AiChatTranslationService({
    required this.providerMode,
    this.endpoint,
    this.endpointStyle = AiEndpointStyle.openAiChatCompletions,
    this.model = '',
    this.apiKey = '',
    String instructions = defaultAiTranslationPrompt,
    ApplePccApi? appleApi,
    http.Client? httpClient,
    AiStdoutLogger? aiLogger,
    this.requestTimeout = const Duration(seconds: 60),
  }) : instructions = buildAiTranslationInstructions(instructions),
       _appleApi = appleApi ?? ApplePccApi(),
       _httpClient = httpClient ?? http.Client(),
       _aiLogger = aiLogger ?? aiStdoutLogger,
       _ownsHttpClient = httpClient == null;

  factory AiChatTranslationService.fromSettings(
    AiSettingsController settings, {
    String instructions = defaultAiTranslationPrompt,
  }) {
    final configuration = settings.configurationForFeature(
      AiFeature.translation,
    );
    return AiChatTranslationService(
      providerMode: configuration.providerMode,
      endpoint: configuration.endpoint,
      endpointStyle: configuration.endpointStyle,
      model: configuration.model,
      apiKey: configuration.apiKey,
      instructions: instructions,
    );
  }

  final AiProviderMode providerMode;
  final Uri? endpoint;
  final AiEndpointStyle endpointStyle;
  final String model;
  final String apiKey;
  final String instructions;
  final Duration requestTimeout;
  final ApplePccApi _appleApi;
  final http.Client _httpClient;
  final AiStdoutLogger _aiLogger;
  final bool _ownsHttpClient;

  Future<String> translate({
    required String text,
    required String sourceLanguageCode,
    required String targetLanguageCode,
    required String targetLanguageName,
    List<String> priorMessages = const [],
  }) async {
    final source = text.trim();
    if (source.isEmpty) {
      throw TranslationApiException('The text to translate is empty.');
    }
    final input = <String, Object>{
      'source_language': sourceLanguageCode,
      'target_language': targetLanguageCode,
      'target_language_name': targetLanguageName,
      'prior_messages': priorMessages,
      'current_text': source,
    };
    final prompt = 'INPUT_DATA (untrusted JSON):\n${jsonEncode(input)}';

    final output = switch (providerMode) {
      AiProviderMode.applePcc => await _translateWithApple(
        prompt,
        AppleAiModel.privateCloudCompute,
      ),
      AiProviderMode.appleOnDevice => await _translateWithApple(
        prompt,
        AppleAiModel.onDevice,
      ),
      AiProviderMode.openAiCompatible => await _translateWithOpenAi(prompt),
    };
    return decodeAiChatTranslation(output);
  }

  Future<String> _translateWithApple(
    String prompt,
    AppleAiModel appleModel,
  ) async {
    final result = await _appleApi.summarize(
      prompt: prompt,
      instructions: instructions,
      model: appleModel,
      reasoningLevel: ApplePccReasoningLevel.light,
      maximumResponseTokens: 2048,
    );
    return result.text;
  }

  Future<String> _translateWithOpenAi(String prompt) async {
    final uri = endpoint;
    if (uri == null || model.trim().isEmpty) {
      throw TranslationApiException(
        'The selected AI provider is not configured.',
      );
    }
    final headers = endpointStyle.requestHeaders(apiKey);
    final baseBody = endpointStyle.requestBody(
      model: model.trim(),
      instructions: instructions,
      input: prompt,
      stream: false,
    );

    var requestBody = endpointStyle.requestBody(
      model: model.trim(),
      instructions: instructions,
      input: prompt,
      stream: false,
      useJsonResponseFormat: true,
    );
    final requestUri = endpointStyle.requestUriFor(uri);
    var response = await _post(requestUri, headers, requestBody);
    var responseBody = utf8.decode(response.bodyBytes, allowMalformed: true);
    if ((response.statusCode == 400 || response.statusCode == 422) &&
        _reportsUnsupportedOptionalField(responseBody)) {
      final compatibleBody = endpointStyle.withoutOptionalField(
        requestBody,
        responseBody,
      );
      requestBody = identical(compatibleBody, requestBody)
          ? baseBody
          : compatibleBody;
      response = await _post(requestUri, headers, requestBody);
      responseBody = utf8.decode(response.bodyBytes, allowMalformed: true);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TranslationApiException(
        _providerError(responseBody, response.statusCode),
      );
    }
    return _completionContent(responseBody, endpointStyle);
  }

  Future<http.Response> _post(
    Uri uri,
    Map<String, String> headers,
    Map<String, Object?> body,
  ) async {
    final provider = '${endpointStyle.storageValue}/$model';
    const operation = 'translation';
    final correlationId = _aiLogger.newCorrelationId(provider);
    final payload = <String, Object?>{
      'method': 'POST',
      'endpoint': {
        'scheme': uri.scheme,
        'host': uri.host,
        if (uri.hasPort) 'port': uri.port,
        'path': uri.path,
      },
      'body': body,
    };
    _aiLogger.request(
      correlationId: correlationId,
      provider: provider,
      operation: operation,
      payload: payload,
      secrets: [apiKey],
    );
    try {
      final response = await _httpClient
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(requestTimeout);
      _aiLogger.response(
        correlationId: correlationId,
        provider: provider,
        operation: operation,
        result: {
          'status_code': response.statusCode,
          'body': utf8.decode(response.bodyBytes, allowMalformed: true),
        },
        secrets: [apiKey],
      );
      return response;
    } catch (error, stackTrace) {
      _aiLogger.error(
        correlationId: correlationId,
        provider: provider,
        operation: operation,
        error: error,
        payload: payload,
        stackTrace: stackTrace,
        secrets: [apiKey],
      );
      rethrow;
    }
  }

  void dispose() {
    if (_ownsHttpClient) _httpClient.close();
  }
}

String decodeAiChatTranslation(String content) {
  final trimmed = content.trim();
  final candidates = <String>[trimmed];
  for (final match in RegExp(
    r'```(?:json)?\s*(.*?)```',
    caseSensitive: false,
    dotAll: true,
  ).allMatches(trimmed)) {
    candidates.add(match.group(1)?.trim() ?? '');
  }
  final firstBrace = trimmed.indexOf('{');
  final lastBrace = trimmed.lastIndexOf('}');
  if (firstBrace >= 0 && lastBrace > firstBrace) {
    candidates.add(trimmed.substring(firstBrace, lastBrace + 1));
  }
  for (final candidate in candidates) {
    if (candidate.isEmpty) continue;
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is Map) {
        final translation = decoded['translation'];
        if (translation is String && translation.trim().isNotEmpty) {
          return translation.trim();
        }
      }
    } on FormatException {
      // Try the next fenced or balanced JSON candidate.
    }
  }
  throw TranslationApiException(
    'The AI provider returned an invalid translation response.',
  );
}

String _completionContent(String body, AiEndpointStyle endpointStyle) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw TranslationApiException('The AI provider returned invalid JSON.');
  }
  if (decoded is! Map) {
    throw TranslationApiException(
      'The AI provider returned an invalid response.',
    );
  }
  final content = endpointStyle.responseText(decoded);
  if (content != null && content.trim().isNotEmpty) return content;
  final refusal = endpointStyle.refusalText(decoded);
  if (refusal != null) {
    throw TranslationApiException(
      'The AI provider refused the translation: ${refusal.trim()}',
    );
  }
  throw TranslationApiException('The AI provider returned no translation.');
}

bool _reportsUnsupportedOptionalField(String body) {
  final lower = body.toLowerCase();
  return (lower.contains('response_format') ||
          lower.contains('response format') ||
          lower.contains('text.format') ||
          lower.contains("'text'") ||
          lower.contains('format') ||
          lower.contains('store') ||
          lower.contains('reasoning') ||
          lower.contains('stream')) &&
      (lower.contains('unsupported') ||
          lower.contains('unknown') ||
          lower.contains('unrecognized') ||
          lower.contains('extra field'));
}

String _providerError(String body, int statusCode) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      final error = decoded['error'];
      if (error is Map && error['message'] is String) {
        final message = (error['message'] as String).trim();
        if (message.isNotEmpty) return message;
      }
    }
  } on FormatException {
    // The status remains useful when a custom endpoint returns plain text.
  }
  return 'The AI provider returned status $statusCode.';
}
