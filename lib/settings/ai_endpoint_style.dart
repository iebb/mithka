import 'dart:convert';

class AiFunctionToolDefinition {
  const AiFunctionToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
  });

  final String name;
  final String description;
  final Map<String, Object?> parameters;
}

class AiFunctionToolCall {
  const AiFunctionToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final Map<String, Object?> arguments;
}

class AiFunctionToolResult {
  const AiFunctionToolResult({
    required this.call,
    required this.output,
    this.isError = false,
  });

  final AiFunctionToolCall call;
  final String output;
  final bool isError;
}

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

  Map<String, Object?> withFunctionTools(
    Map<String, Object?> body,
    List<AiFunctionToolDefinition> tools,
  ) {
    if (tools.isEmpty) return body;
    final next = Map<String, Object?>.of(body);
    switch (this) {
      case AiEndpointStyle.openAiChatCompletions:
        next['tools'] = [
          for (final tool in tools)
            {
              'type': 'function',
              'function': {
                'name': tool.name,
                'description': tool.description,
                'parameters': tool.parameters,
                'strict': true,
              },
            },
        ];
        next['tool_choice'] = 'auto';
        break;
      case AiEndpointStyle.openAiResponses:
        next['tools'] = [
          for (final tool in tools)
            {
              'type': 'function',
              'name': tool.name,
              'description': tool.description,
              'parameters': tool.parameters,
              'strict': true,
            },
        ];
        next['tool_choice'] = 'auto';
        break;
      case AiEndpointStyle.anthropicMessages:
        next['tools'] = [
          for (final tool in tools)
            {
              'name': tool.name,
              'description': tool.description,
              'input_schema': tool.parameters,
              'strict': true,
            },
        ];
        next['tool_choice'] = {'type': 'auto'};
        break;
      case AiEndpointStyle.ollamaChat:
        next['tools'] = [
          for (final tool in tools)
            {
              'type': 'function',
              'function': {
                'name': tool.name,
                'description': tool.description,
                'parameters': tool.parameters,
              },
            },
        ];
        break;
    }
    return next;
  }

  List<AiFunctionToolCall> functionToolCalls(Map<dynamic, dynamic> envelope) {
    final rawCalls = switch (this) {
      AiEndpointStyle.openAiChatCompletions => _chatCompletionToolCalls(
        envelope,
      ),
      AiEndpointStyle.openAiResponses => _responsesToolCalls(envelope),
      AiEndpointStyle.anthropicMessages => _anthropicToolCalls(envelope),
      AiEndpointStyle.ollamaChat => _ollamaToolCalls(envelope),
    };
    final calls = <AiFunctionToolCall>[];
    for (var index = 0; index < rawCalls.length; index++) {
      final call = _parseToolCall(this, rawCalls[index], index);
      if (call != null) calls.add(call);
    }
    return calls;
  }

  Map<String, Object?> toolContinuationBody({
    required Map<String, Object?> previousBody,
    required Map<dynamic, dynamic> response,
    required List<AiFunctionToolResult> results,
  }) {
    final next = Map<String, Object?>.of(previousBody);
    switch (this) {
      case AiEndpointStyle.openAiChatCompletions:
        final messages = _objectList(previousBody['messages']);
        final choices = response['choices'];
        if (choices is List && choices.isNotEmpty && choices.first is Map) {
          final assistant = (choices.first as Map)['message'];
          if (assistant is Map) messages.add(_stringKeyedMap(assistant));
        }
        for (final result in results) {
          messages.add({
            'role': 'tool',
            'tool_call_id': result.call.id,
            'content': result.output,
          });
        }
        next['messages'] = messages;
        break;
      case AiEndpointStyle.openAiResponses:
        final input = previousBody['input'];
        final inputs = input is List
            ? List<Object?>.of(input)
            : <Object?>[
                {'role': 'user', 'content': input?.toString() ?? ''},
              ];
        final output = response['output'];
        if (output is List) inputs.addAll(output);
        for (final result in results) {
          inputs.add({
            'type': 'function_call_output',
            'call_id': result.call.id,
            'output': result.output,
          });
        }
        next['input'] = inputs;
        break;
      case AiEndpointStyle.anthropicMessages:
        final messages = _objectList(previousBody['messages']);
        final content = response['content'];
        if (content is List) {
          messages.add({'role': 'assistant', 'content': content});
        }
        messages.add({
          'role': 'user',
          'content': [
            for (final result in results)
              {
                'type': 'tool_result',
                'tool_use_id': result.call.id,
                'content': result.output,
                if (result.isError) 'is_error': true,
              },
          ],
        });
        next['messages'] = messages;
        break;
      case AiEndpointStyle.ollamaChat:
        final messages = _objectList(previousBody['messages']);
        final assistant = response['message'];
        if (assistant is Map) messages.add(_stringKeyedMap(assistant));
        for (final result in results) {
          messages.add({
            'role': 'tool',
            'tool_name': result.call.name,
            'content': result.output,
          });
        }
        next['messages'] = messages;
        break;
    }
    return next;
  }

  Map<String, Object?> withoutOptionalField(
    Map<String, Object?> body,
    String errorMessage,
  ) {
    final compatible = Map<String, Object?>.of(body);
    final message = errorMessage.toLowerCase();
    var changed = false;
    if (message.contains('strict') && compatible['tools'] is List) {
      var removedStrict = false;
      final tools = <Object?>[
        for (final rawTool in compatible['tools']! as List)
          if (rawTool is Map)
            () {
              final tool = _stringKeyedMap(rawTool);
              if (tool.containsKey('strict')) {
                tool.remove('strict');
                removedStrict = true;
              }
              final rawFunction = tool['function'];
              if (rawFunction is Map) {
                final function = _stringKeyedMap(rawFunction);
                if (function.containsKey('strict')) {
                  function.remove('strict');
                  removedStrict = true;
                }
                tool['function'] = function;
              }
              return tool;
            }()
          else
            rawTool,
      ];
      if (removedStrict) {
        compatible['tools'] = tools;
        changed = true;
      }
    } else if ((message.contains('tool_choice') ||
            message.contains('tool choice')) &&
        compatible.containsKey('tool_choice')) {
      compatible.remove('tool_choice');
      changed = true;
    } else if (message.contains('parallel_tool_calls') &&
        compatible.containsKey('parallel_tool_calls')) {
      compatible.remove('parallel_tool_calls');
      changed = true;
    } else if ((message.contains('tool') || message.contains('function')) &&
        compatible.containsKey('tools')) {
      changed = compatible.remove('tools') != null || changed;
      changed = compatible.remove('tool_choice') != null || changed;
      changed = compatible.remove('parallel_tool_calls') != null || changed;
    }
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

List<Map<dynamic, dynamic>> _chatCompletionToolCalls(
  Map<dynamic, dynamic> envelope,
) {
  final choices = envelope['choices'];
  if (choices is! List || choices.isEmpty || choices.first is! Map) {
    return const [];
  }
  final message = (choices.first as Map)['message'];
  if (message is! Map || message['tool_calls'] is! List) return const [];
  return (message['tool_calls'] as List).whereType<Map>().toList();
}

List<Map<dynamic, dynamic>> _responsesToolCalls(
  Map<dynamic, dynamic> envelope,
) {
  final output = envelope['output'];
  if (output is! List) return const [];
  return output
      .whereType<Map>()
      .where((item) => item['type'] == 'function_call')
      .toList();
}

List<Map<dynamic, dynamic>> _anthropicToolCalls(
  Map<dynamic, dynamic> envelope,
) {
  final content = envelope['content'];
  if (content is! List) return const [];
  return content
      .whereType<Map>()
      .where((item) => item['type'] == 'tool_use')
      .toList();
}

List<Map<dynamic, dynamic>> _ollamaToolCalls(Map<dynamic, dynamic> envelope) {
  final message = envelope['message'];
  if (message is! Map || message['tool_calls'] is! List) return const [];
  return (message['tool_calls'] as List).whereType<Map>().toList();
}

AiFunctionToolCall? _parseToolCall(
  AiEndpointStyle style,
  Map<dynamic, dynamic> raw,
  int index,
) {
  final Object? rawName;
  final Object? rawArguments;
  final Object? rawId;
  switch (style) {
    case AiEndpointStyle.openAiChatCompletions:
      final function = raw['function'];
      if (function is! Map) return null;
      rawName = function['name'];
      rawArguments = function['arguments'];
      rawId = raw['id'];
      break;
    case AiEndpointStyle.openAiResponses:
      rawName = raw['name'];
      rawArguments = raw['arguments'];
      rawId = raw['call_id'];
      break;
    case AiEndpointStyle.anthropicMessages:
      rawName = raw['name'];
      rawArguments = raw['input'];
      rawId = raw['id'];
      break;
    case AiEndpointStyle.ollamaChat:
      final function = raw['function'];
      if (function is! Map) return null;
      rawName = function['name'];
      rawArguments = function['arguments'];
      rawId = raw['id'];
      break;
  }
  final name = rawName is String ? rawName.trim() : '';
  if (name.isEmpty) return null;
  final arguments = _toolArguments(rawArguments);
  final id = rawId is String && rawId.trim().isNotEmpty
      ? rawId.trim()
      : '${style.storageValue}-$index-$name';
  return AiFunctionToolCall(id: id, name: name, arguments: arguments);
}

Map<String, Object?> _toolArguments(Object? value) {
  if (value is Map) return _stringKeyedMap(value);
  if (value is! String || value.trim().isEmpty) return const {};
  try {
    final decoded = jsonDecode(value);
    return decoded is Map ? _stringKeyedMap(decoded) : const {};
  } on FormatException {
    return const {};
  }
}

List<Object?> _objectList(Object? value) =>
    value is List ? List<Object?>.of(value) : <Object?>[];

Map<String, Object?> _stringKeyedMap(Map<dynamic, dynamic> value) => {
  for (final entry in value.entries) '${entry.key}': entry.value,
};

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
