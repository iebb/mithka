import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../settings/ai_settings_controller.dart';
import '../settings/ai_translation_prompt.dart';
import '../settings/apple_pcc_api.dart';
import '../settings/translation_api.dart';

class AiChatTranslationService {
  AiChatTranslationService({
    required this.providerMode,
    this.endpoint,
    this.model = '',
    this.apiKey = '',
    String instructions = defaultAiTranslationPrompt,
    ApplePccApi? appleApi,
    http.Client? httpClient,
    this.requestTimeout = const Duration(seconds: 60),
  }) : instructions = buildAiTranslationInstructions(instructions),
       _appleApi = appleApi ?? ApplePccApi(),
       _httpClient = httpClient ?? http.Client(),
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
      model: configuration.model,
      apiKey: configuration.apiKey,
      instructions: instructions,
    );
  }

  final AiProviderMode providerMode;
  final Uri? endpoint;
  final String model;
  final String apiKey;
  final String instructions;
  final Duration requestTimeout;
  final ApplePccApi _appleApi;
  final http.Client _httpClient;
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
    final headers = <String, String>{
      'content-type': 'application/json',
      if (apiKey.trim().isNotEmpty) 'authorization': 'Bearer ${apiKey.trim()}',
    };
    final baseBody = <String, Object>{
      'model': model.trim(),
      'messages': [
        {'role': 'system', 'content': instructions},
        {'role': 'user', 'content': prompt},
      ],
      'stream': false,
    };

    var response = await _post(uri, headers, {
      ...baseBody,
      'response_format': {'type': 'json_object'},
    });
    var responseBody = utf8.decode(response.bodyBytes, allowMalformed: true);
    if ((response.statusCode == 400 || response.statusCode == 422) &&
        _reportsUnsupportedResponseFormat(responseBody)) {
      response = await _post(uri, headers, baseBody);
      responseBody = utf8.decode(response.bodyBytes, allowMalformed: true);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TranslationApiException(
        _providerError(responseBody, response.statusCode),
      );
    }
    return _completionContent(responseBody);
  }

  Future<http.Response> _post(
    Uri uri,
    Map<String, String> headers,
    Map<String, Object> body,
  ) => _httpClient
      .post(uri, headers: headers, body: jsonEncode(body))
      .timeout(requestTimeout);

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

String _completionContent(String body) {
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
  final choices = decoded['choices'];
  if (choices is! List || choices.isEmpty || choices.first is! Map) {
    throw TranslationApiException('The AI provider returned no translation.');
  }
  final message = (choices.first as Map)['message'];
  if (message is! Map) {
    throw TranslationApiException('The AI provider returned no translation.');
  }
  final content = message['content'];
  if (content is String && content.trim().isNotEmpty) return content;
  if (content is List) {
    final text = content
        .whereType<Map>()
        .map((part) => part['text'])
        .whereType<String>()
        .join();
    if (text.trim().isNotEmpty) return text;
  }
  throw TranslationApiException('The AI provider returned no translation.');
}

bool _reportsUnsupportedResponseFormat(String body) {
  final lower = body.toLowerCase();
  return lower.contains('response_format') &&
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
