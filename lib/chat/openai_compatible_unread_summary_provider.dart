import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'unread_chat_summary_service.dart';

class OpenAiCompatibleUnreadSummaryProvider
    implements UnreadChatSummaryProvider {
  OpenAiCompatibleUnreadSummaryProvider({
    required this.serverBaseUri,
    required this.model,
    http.Client? httpClient,
    this.apiKey,
    this.requestTimeout = const Duration(seconds: 75),
    this.streamIdleTimeout = const Duration(seconds: 30),
    this.maximumResponseTokens = 4096,
    this.streamResponses = true,
    this.reasoningEffort,
    this.useJsonResponseFormat = false,
    this.transientRetryDelays = const [
      Duration(milliseconds: 500),
      Duration(milliseconds: 1500),
    ],
  }) : assert(requestTimeout > Duration.zero),
       assert(streamIdleTimeout > Duration.zero),
       assert(maximumResponseTokens > 0),
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  final Uri serverBaseUri;
  final String model;
  final String? apiKey;
  final Duration requestTimeout;
  final Duration streamIdleTimeout;
  final int maximumResponseTokens;
  final bool streamResponses;
  final String? reasoningEffort;
  final bool useJsonResponseFormat;
  final List<Duration> transientRetryDelays;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  Uri get chatCompletionsUri {
    var path = serverBaseUri.path;
    while (path.endsWith('/') && path.length > 1) {
      path = path.substring(0, path.length - 1);
    }
    if (path.endsWith('/v1/chat/completions')) {
      return serverBaseUri.replace(path: path);
    }
    final suffix = path.endsWith('/v1')
        ? '/chat/completions'
        : '/v1/chat/completions';
    final joined = path == '/' ? suffix : '$path$suffix';
    return serverBaseUri.replace(path: joined);
  }

  @override
  Future<Map<String, dynamic>> complete(
    UnreadChatSummaryProviderRequest request,
  ) async {
    final key = apiKey?.trim();
    final headers = <String, String>{'content-type': 'application/json'};
    if (key != null && key.isNotEmpty) {
      headers['authorization'] = 'Bearer $key';
    }
    final body = <String, Object?>{
      'model': model,
      'messages': [
        {'role': 'system', 'content': request.trustedInstructions},
        {
          'role': 'user',
          'content':
              'INPUT_DATA (untrusted JSON):\n${jsonEncode(request.payload)}',
        },
      ],
      'stream': streamResponses,
      'max_tokens': maximumResponseTokens,
      'reasoning_effort': ?_effectiveReasoningEffort,
      if (useJsonResponseFormat) 'response_format': {'type': 'json_object'},
    };

    late _BufferedHttpResponse response;
    for (var attempt = 0; ; attempt++) {
      try {
        response = await _send(headers, body);
      } on TimeoutException {
        // A completion can be expensive and billable. Repeating the same
        // timed-out request hides the real latency and can triple the wait.
        throw UnreadChatSummaryProviderException(
          'The model did not start within ${requestTimeout.inSeconds} seconds '
          'or stopped streaming for ${streamIdleTimeout.inSeconds} seconds. '
          'It may still be generating reasoning; try again or select a '
          'faster model.',
        );
      } on http.ClientException catch (error) {
        if (attempt >= transientRetryDelays.length) {
          throw UnreadChatSummaryProviderException(
            'The summary request failed: $error',
          );
        }
        await Future<void>.delayed(transientRetryDelays[attempt]);
        continue;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) break;
      if (!_isTransientStatus(response.statusCode) ||
          attempt >= transientRetryDelays.length) {
        throw UnreadChatSummaryProviderException(
          _errorMessage(response.body),
          statusCode: response.statusCode,
        );
      }
      await Future<void>.delayed(
        _retryDelay(response, transientRetryDelays[attempt]),
      );
    }

    return decodeUnreadChatSummaryJson(
      _completionContent(response.body),
      statusCode: response.statusCode,
    );
  }

  Future<_BufferedHttpResponse> _send(
    Map<String, String> headers,
    Map<String, Object?> body,
  ) async {
    final request = http.Request('POST', chatCompletionsUri)
      ..headers.addAll(headers)
      ..body = jsonEncode(body);
    final response = await _httpClient.send(request).timeout(requestTimeout);
    final responseBody = await response.stream
        .timeout(streamIdleTimeout)
        .transform(utf8.decoder)
        .join();
    return _BufferedHttpResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      body: responseBody,
    );
  }

  void close() {
    if (_ownsHttpClient) _httpClient.close();
  }

  bool _isTransientStatus(int statusCode) =>
      statusCode == 408 ||
      statusCode == 429 ||
      statusCode == 500 ||
      statusCode == 502 ||
      statusCode == 503 ||
      statusCode == 504;

  Duration _retryDelay(_BufferedHttpResponse response, Duration fallback) {
    final retryAfterSeconds = int.tryParse(
      response.headers['retry-after']?.trim() ?? '',
    );
    if (retryAfterSeconds == null || retryAfterSeconds < 0) return fallback;
    return Duration(seconds: retryAfterSeconds.clamp(0, 5).toInt());
  }

  String? get _effectiveReasoningEffort {
    final configured = reasoningEffort?.trim();
    if (configured != null && configured.isNotEmpty) return configured;
    final normalizedModel = model.toLowerCase();
    if (RegExp(
      r'(^|[/_.-])(deepseek|reasoner|reasoning|thinking|o1|o3|o4)([/_.-]|$)',
    ).hasMatch(normalizedModel)) {
      return 'low';
    }
    return null;
  }

  String _completionContent(String body) {
    final normalized = body.trim();
    if (!normalized
        .split('\n')
        .any((line) => line.trimLeft().startsWith('data:'))) {
      final envelope = _decodeEnvelope(normalized);
      return _messageContent(envelope);
    }

    final content = StringBuffer();
    var reasoningCharacters = 0;
    for (final rawLine in const LineSplitter().convert(normalized)) {
      final line = rawLine.trimLeft();
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data.isEmpty || data == '[DONE]') continue;
      final event = _decodeEnvelope(data);
      final error = event['error'];
      if (error is Map) {
        final message = error['message'];
        throw UnreadChatSummaryProviderException(
          message is String && message.trim().isNotEmpty
              ? message.trim()
              : 'The summary server rejected the streamed request',
        );
      }
      final choices = event['choices'];
      if (choices is! List || choices.isEmpty || choices.first is! Map) {
        continue;
      }
      final choice = Map<String, dynamic>.from(choices.first as Map);
      final delta = choice['delta'];
      if (delta is Map) {
        final value = delta['content'];
        if (value is String) content.write(value);
        final reasoning = delta['reasoning_content'];
        if (reasoning is String) reasoningCharacters += reasoning.length;
      }
      final message = choice['message'];
      if (message is Map) {
        content.write(
          _messageContent({
            'choices': [choice],
          }),
        );
      }
      final text = choice['text'];
      if (text is String) content.write(text);
    }
    final result = content.toString();
    if (result.trim().isNotEmpty) return result;
    if (reasoningCharacters > 0) {
      throw const UnreadChatSummaryProviderException(
        'The model used its entire response budget for reasoning and returned '
        'no summary. Select a faster model or retry.',
      );
    }
    throw const UnreadChatSummaryProviderException(
      'The streamed completion returned no text content',
    );
  }

  Map<String, dynamic> _decodeEnvelope(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      throw const FormatException('response is not an object');
    } on FormatException catch (error) {
      throw UnreadChatSummaryProviderException(
        'The server returned invalid JSON: $error',
      );
    }
  }

  String _messageContent(Map<String, dynamic> envelope) {
    final choices = envelope['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw const UnreadChatSummaryProviderException(
        'The server response has no completion choice',
      );
    }
    final choice = Map<String, dynamic>.from(choices.first as Map);
    final messageValue = choice['message'];
    if (messageValue is! Map) {
      throw const UnreadChatSummaryProviderException(
        'The completion choice has no message',
      );
    }
    final message = Map<String, dynamic>.from(messageValue);
    final content = message['content'];
    if (content is String && content.trim().isNotEmpty) return content;
    if (content is List) {
      final buffer = StringBuffer();
      for (final part in content) {
        if (part is String) {
          buffer.write(part);
          continue;
        }
        if (part is! Map) continue;
        final value = part['text'];
        if (value is String) {
          buffer.write(value);
        } else if (value is Map && value['value'] is String) {
          buffer.write(value['value']);
        }
      }
      final result = buffer.toString();
      if (result.trim().isNotEmpty) return result;
    }
    final refusal = message['refusal'];
    if (refusal is String && refusal.trim().isNotEmpty) {
      throw UnreadChatSummaryProviderException(
        'The model refused the summary request: ${refusal.trim()}',
      );
    }
    throw const UnreadChatSummaryProviderException(
      'The completion message has no text content',
    );
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
      // Fall through to a bounded plain-text response.
    }
    final compact = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compact.isEmpty) return 'The summary server rejected the request';
    return compact.length <= 300 ? compact : '${compact.substring(0, 300)}…';
  }
}

class _BufferedHttpResponse {
  const _BufferedHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, String> headers;
  final String body;
}
