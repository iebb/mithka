enum AiEndpointStyle {
  openAiChatCompletions(
    storageValue: 'open_ai_chat_completions',
    endpointSuffix: '/v1/chat/completions',
    exampleEndpoint: 'https://example.com/v1/chat/completions',
  ),
  openAiResponses(
    storageValue: 'open_ai_responses',
    endpointSuffix: '/v1/responses',
    exampleEndpoint: 'https://api.openai.com/v1/responses',
  ),
  anthropicMessages(
    storageValue: 'anthropic_messages',
    endpointSuffix: '/v1/messages',
    exampleEndpoint: 'https://api.anthropic.com/v1/messages',
  ),
  ollamaChat(
    storageValue: 'ollama_chat',
    endpointSuffix: '/api/chat',
    exampleEndpoint: 'http://localhost:11434/api/chat',
  );

  const AiEndpointStyle({
    required this.storageValue,
    required this.endpointSuffix,
    required this.exampleEndpoint,
  });

  final String storageValue;
  final String endpointSuffix;
  final String exampleEndpoint;

  static AiEndpointStyle fromStorage(String? value) => switch (value) {
    'open_ai_responses' || 'openAiResponses' => openAiResponses,
    'anthropic_messages' || 'anthropicMessages' => anthropicMessages,
    'ollama_chat' || 'ollamaChat' => ollamaChat,
    _ => openAiChatCompletions,
  };

  static AiEndpointStyle? inferFromEndpoint(String value) {
    final path = Uri.tryParse(value.trim())?.path;
    if (path == null) return null;
    for (final style in values) {
      if (path.endsWith(style.endpointSuffix)) return style;
    }
    return null;
  }

  Uri requestUriFor(Uri configuredUri) {
    var path = configuredUri.path;
    while (path.endsWith('/') && path.length > 1) {
      path = path.substring(0, path.length - 1);
    }
    if (path.endsWith(endpointSuffix)) {
      return configuredUri.replace(path: path);
    }

    final versionPrefix = switch (this) {
      AiEndpointStyle.ollamaChat => '/api',
      _ => '/v1',
    };
    final endpointTail = endpointSuffix.substring(versionPrefix.length);
    final suffix = path.endsWith(versionPrefix) ? endpointTail : endpointSuffix;
    return configuredUri.replace(path: path == '/' ? suffix : '$path$suffix');
  }

  Uri modelsUriFor(Uri requestUri) {
    final normalizedRequestUri = requestUriFor(requestUri);
    final path = normalizedRequestUri.path;
    final prefix = path.substring(0, path.length - endpointSuffix.length);
    final modelsSuffix = switch (this) {
      AiEndpointStyle.ollamaChat => '/api/tags',
      _ => '/v1/models',
    };
    return normalizedRequestUri.replace(path: '$prefix$modelsSuffix');
  }

  Uri? modelUriFor(Uri requestUri, String modelId) {
    if (this == AiEndpointStyle.ollamaChat) return null;
    final modelsUri = modelsUriFor(requestUri);
    return modelsUri.replace(
      pathSegments: [...modelsUri.pathSegments, modelId.trim()],
    );
  }

  Map<String, String> requestHeaders(String? apiKey) {
    final key = apiKey?.trim();
    final headers = <String, String>{
      'accept': 'application/json',
      'content-type': 'application/json',
      if (this == AiEndpointStyle.anthropicMessages)
        'anthropic-version': '2023-06-01',
    };
    if (key != null && key.isNotEmpty) {
      if (this == AiEndpointStyle.anthropicMessages) {
        headers['x-api-key'] = key;
      } else {
        headers['authorization'] = 'Bearer $key';
      }
    }
    return headers;
  }

  Map<String, Object?> requestBody({
    required String model,
    required String instructions,
    required String input,
    required bool stream,
    String? reasoningEffort,
    bool useJsonResponseFormat = false,
  }) {
    final normalizedReasoningEffort = reasoningEffort?.trim();
    return switch (this) {
      AiEndpointStyle.openAiChatCompletions => <String, Object?>{
        'model': model,
        'messages': [
          if (instructions.trim().isNotEmpty)
            {'role': 'system', 'content': instructions},
          {'role': 'user', 'content': input},
        ],
        'stream': stream,
        if (normalizedReasoningEffort?.isNotEmpty == true)
          'reasoning_effort': normalizedReasoningEffort,
        if (useJsonResponseFormat) 'response_format': {'type': 'json_object'},
      },
      AiEndpointStyle.openAiResponses => <String, Object?>{
        'model': model,
        if (instructions.trim().isNotEmpty) 'instructions': instructions,
        'input': input,
        'stream': stream,
        'store': false,
        if (normalizedReasoningEffort?.isNotEmpty == true)
          'reasoning': {'effort': normalizedReasoningEffort},
        if (useJsonResponseFormat)
          'text': {
            'format': {'type': 'json_object'},
          },
      },
      AiEndpointStyle.anthropicMessages => <String, Object?>{
        'model': model,
        if (instructions.trim().isNotEmpty) 'system': instructions,
        'messages': [
          {'role': 'user', 'content': input},
        ],
        'max_tokens': 4096,
        'stream': stream,
      },
      AiEndpointStyle.ollamaChat => <String, Object?>{
        'model': model,
        'messages': [
          if (instructions.trim().isNotEmpty)
            {'role': 'system', 'content': instructions},
          {'role': 'user', 'content': input},
        ],
        'stream': stream,
        if (useJsonResponseFormat) 'format': 'json',
      },
    };
  }

  Map<String, Object?> withoutOptionalField(
    Map<String, Object?> body,
    String errorMessage,
  ) {
    final compatible = Map<String, Object?>.of(body);
    final message = errorMessage.toLowerCase();
    var changed = false;
    switch (this) {
      case AiEndpointStyle.openAiChatCompletions:
        if (message.contains('reasoning_effort') ||
            message.contains('reasoning effort')) {
          changed = compatible.remove('reasoning_effort') != null || changed;
        }
        if (message.contains('response_format') ||
            message.contains('response format')) {
          changed = compatible.remove('response_format') != null || changed;
        }
        break;
      case AiEndpointStyle.openAiResponses:
        if (message.contains('reasoning')) {
          changed = compatible.remove('reasoning') != null || changed;
        }
        if (message.contains('text') || message.contains('format')) {
          changed = compatible.remove('text') != null || changed;
        }
        if (message.contains('store')) {
          changed = compatible.remove('store') != null || changed;
        }
        break;
      case AiEndpointStyle.anthropicMessages:
        break;
      case AiEndpointStyle.ollamaChat:
        if (message.contains('format')) {
          changed = compatible.remove('format') != null || changed;
        }
        break;
    }
    if (message.contains('stream') && compatible['stream'] == true) {
      compatible['stream'] = false;
      changed = true;
    }
    return changed ? compatible : body;
  }

  String? responseText(Map<dynamic, dynamic> envelope) => switch (this) {
    AiEndpointStyle.openAiChatCompletions => _chatCompletionText(envelope),
    AiEndpointStyle.openAiResponses => _responsesText(envelope),
    AiEndpointStyle.anthropicMessages => _contentPartsText(envelope['content']),
    AiEndpointStyle.ollamaChat =>
      _messageText(envelope['message']) ??
          _nonEmptyString(envelope['response']),
  };

  String streamDelta(Map<dynamic, dynamic> event) => switch (this) {
    AiEndpointStyle.openAiChatCompletions => _chatCompletionDelta(event),
    AiEndpointStyle.openAiResponses =>
      event['type'] == 'response.output_text.delta'
          ? _nonEmptyString(event['delta']) ?? ''
          : '',
    AiEndpointStyle.anthropicMessages =>
      event['type'] == 'content_block_delta' && event['delta'] is Map
          ? _nonEmptyString((event['delta'] as Map)['text']) ?? ''
          : '',
    AiEndpointStyle.ollamaChat =>
      _messageText(event['message']) ??
          _nonEmptyString(event['response']) ??
          '',
  };

  String? refusalText(Map<dynamic, dynamic> envelope) {
    if (this == AiEndpointStyle.openAiResponses) {
      final output = envelope['output'];
      if (output is List) {
        for (final item in output.whereType<Map>()) {
          final content = item['content'];
          if (content is! List) continue;
          for (final part in content.whereType<Map>()) {
            final refusal = _nonEmptyString(part['refusal']);
            if (refusal != null) return refusal;
          }
        }
      }
    }
    if (this == AiEndpointStyle.openAiChatCompletions) {
      final choices = envelope['choices'];
      if (choices is List && choices.isNotEmpty && choices.first is Map) {
        final message = (choices.first as Map)['message'];
        if (message is Map) return _nonEmptyString(message['refusal']);
      }
    }
    return null;
  }

  String? errorMessage(Map<dynamic, dynamic> envelope) {
    final error = envelope['error'];
    if (error is String) return _nonEmptyString(error);
    if (error is Map) return _nonEmptyString(error['message']);
    final response = envelope['response'];
    if (response is Map) {
      final responseError = response['error'];
      if (responseError is String) return _nonEmptyString(responseError);
      if (responseError is Map) {
        return _nonEmptyString(responseError['message']);
      }
    }
    return _nonEmptyString(envelope['message']);
  }
}

String? _chatCompletionText(Map<dynamic, dynamic> envelope) {
  final choices = envelope['choices'];
  if (choices is! List || choices.isEmpty || choices.first is! Map) return null;
  final choice = choices.first as Map;
  return _messageText(choice['message']) ?? _nonEmptyString(choice['text']);
}

String _chatCompletionDelta(Map<dynamic, dynamic> envelope) {
  final choices = envelope['choices'];
  if (choices is! List || choices.isEmpty || choices.first is! Map) return '';
  final choice = choices.first as Map;
  final delta = choice['delta'];
  if (delta is Map) {
    final content = delta['content'];
    if (content is String) return content;
  }
  return _messageText(choice['message']) ??
      _nonEmptyString(choice['text']) ??
      '';
}

String? _responsesText(Map<dynamic, dynamic> envelope) {
  final output = envelope['output'];
  if (output is! List) return null;
  final buffer = StringBuffer();
  for (final item in output.whereType<Map>()) {
    final text = _contentPartsText(item['content']);
    if (text != null) buffer.write(text);
  }
  return _nonEmptyString(buffer.toString());
}

String? _messageText(Object? message) {
  if (message is! Map) return null;
  final content = message['content'];
  return _nonEmptyString(content) ?? _contentPartsText(content);
}

String? _contentPartsText(Object? content) {
  if (content is! List) return null;
  final buffer = StringBuffer();
  for (final part in content) {
    if (part is String) {
      buffer.write(part);
      continue;
    }
    if (part is! Map) continue;
    final text = part['text'];
    if (text is String) {
      buffer.write(text);
    } else if (text is Map && text['value'] is String) {
      buffer.write(text['value'] as String);
    }
  }
  return _nonEmptyString(buffer.toString());
}

String? _nonEmptyString(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return value;
}
