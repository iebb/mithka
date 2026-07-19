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
    this.requestTimeout = const Duration(seconds: 90),
    this.useJsonResponseFormat = false,
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  final Uri serverBaseUri;
  final String model;
  final String? apiKey;
  final Duration requestTimeout;
  final bool useJsonResponseFormat;
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
      'stream': false,
      if (useJsonResponseFormat) 'response_format': {'type': 'json_object'},
    };

    final http.Response response;
    try {
      response = await _httpClient
          .post(chatCompletionsUri, headers: headers, body: jsonEncode(body))
          .timeout(requestTimeout);
    } on TimeoutException catch (error) {
      throw UnreadChatSummaryProviderException(
        'The summary request timed out: $error',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw UnreadChatSummaryProviderException(
        _errorMessage(response.body),
        statusCode: response.statusCode,
      );
    }

    final Map<String, dynamic> envelope;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('response is not an object');
      }
      envelope = Map<String, dynamic>.from(decoded);
    } on FormatException catch (error) {
      throw UnreadChatSummaryProviderException(
        'The server returned invalid JSON: $error',
        statusCode: response.statusCode,
      );
    }

    return decodeUnreadChatSummaryJson(
      _messageContent(envelope),
      statusCode: response.statusCode,
    );
  }

  void close() {
    if (_ownsHttpClient) _httpClient.close();
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
