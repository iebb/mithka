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
    int? maximumOutputTokens,
  }) {
    final normalizedReasoningEffort = reasoningEffort?.trim();
    final normalizedMaximumOutputTokens =
        maximumOutputTokens != null && maximumOutputTokens > 0
        ? maximumOutputTokens
        : null;
    return switch (this) {
      AiEndpointStyle.openAiChatCompletions => <String, Object?>{
        'model': model,
        'messages': [
          if (instructions.trim().isNotEmpty)
            {'role': 'system', 'content': instructions},
          {'role': 'user', 'content': input},
        ],
        'stream': stream,
        'max_tokens': ?normalizedMaximumOutputTokens,
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
        'max_output_tokens': ?normalizedMaximumOutputTokens,
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
        'max_tokens': normalizedMaximumOutputTokens ?? 4096,
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
        if (normalizedMaximumOutputTokens != null)
          'options': {'num_predict': normalizedMaximumOutputTokens},
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
        if (message.contains('max_tokens') ||
            message.contains('max tokens') ||
            message.contains('max_completion_tokens')) {
          changed = compatible.remove('max_tokens') != null || changed;
        }
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
        if (message.contains('max_output_tokens') ||
            message.contains('max output tokens')) {
          changed = compatible.remove('max_output_tokens') != null || changed;
        }
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
        if (message.contains('num_predict') || message.contains('max tokens')) {
          changed = compatible.remove('options') != null || changed;
        }
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
          ? _streamString(event['delta'])
          : '',
    AiEndpointStyle.anthropicMessages =>
      event['type'] == 'content_block_delta' && event['delta'] is Map
          ? _streamString((event['delta'] as Map)['text'])
          : '',
    AiEndpointStyle.ollamaChat =>
      _messageDelta(event['message']) ?? _streamString(event['response']),
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

/// Accumulates one streamed assistant turn into the same provider-native
/// envelope accepted by [AiEndpointStyle.functionToolCalls] and
/// [AiEndpointStyle.toolContinuationBody].
///
/// [add] returns only the visible text contributed by that event, while [text]
/// contains the full visible response received so far.
class AiEndpointStreamAccumulator {
  AiEndpointStreamAccumulator(this.style);

  final AiEndpointStyle style;
  final StringBuffer _text = StringBuffer();

  String get text => _text.toString();

  bool get hasToolCalls => style.functionToolCalls(envelope).isNotEmpty;

  bool get isComplete => switch (style) {
    AiEndpointStyle.openAiChatCompletions =>
      _chatTransportDone || _chatFinishReason != null,
    AiEndpointStyle.openAiResponses => _completedResponsesEnvelope != null,
    AiEndpointStyle.anthropicMessages => _anthropicMessageStopped,
    AiEndpointStyle.ollamaChat => _ollamaEnvelope['done'] == true,
  };

  final Map<int, _StreamingToolCall> _chatToolCalls = {};
  String _chatRole = 'assistant';
  String? _chatFinishReason;
  bool _chatTransportDone = false;

  final Map<int, Map<String, Object?>> _responsesOutput = {};
  final Map<String, int> _responsesOutputIndexesById = {};
  Map<String, Object?>? _completedResponsesEnvelope;

  final Map<int, Map<String, Object?>> _anthropicContent = {};
  final Map<int, StringBuffer> _anthropicInputFragments = {};
  Map<String, Object?> _anthropicMessage = {};
  String? _anthropicStopReason;
  bool _anthropicMessageStopped = false;

  final Map<int, _StreamingToolCall> _ollamaToolCalls = {};
  Map<String, Object?> _ollamaEnvelope = {};
  String _ollamaRole = 'assistant';

  /// Adds a provider stream event and returns its newly visible text delta.
  String add(Map<dynamic, dynamic> event) {
    final delta = switch (style) {
      AiEndpointStyle.openAiChatCompletions => _addChatCompletion(event),
      AiEndpointStyle.openAiResponses => _addResponses(event),
      AiEndpointStyle.anthropicMessages => _addAnthropic(event),
      AiEndpointStyle.ollamaChat => _addOllama(event),
    };
    if (delta.isNotEmpty) _text.write(delta);
    return delta;
  }

  /// Records the Chat Completions `data: [DONE]` transport sentinel.
  /// Other protocols have typed completion events and deliberately ignore it.
  void markDataDone() {
    if (style == AiEndpointStyle.openAiChatCompletions) {
      _chatTransportDone = true;
    }
  }

  /// A completed provider-native response assembled from all events so far.
  Map<String, Object?> get envelope => switch (style) {
    AiEndpointStyle.openAiChatCompletions => _chatCompletionEnvelope,
    AiEndpointStyle.openAiResponses => _responsesEnvelope,
    AiEndpointStyle.anthropicMessages => _anthropicEnvelope,
    AiEndpointStyle.ollamaChat => _ollamaCompletedEnvelope,
  };

  String _addChatCompletion(Map<dynamic, dynamic> event) {
    final choices = event['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) return '';
    final choice = choices.first as Map;
    final finishReason = choice['finish_reason'];
    if (finishReason is String && finishReason.isNotEmpty) {
      _chatFinishReason = finishReason;
    }
    final delta = choice['delta'];
    if (delta is Map) {
      final role = delta['role'];
      if (role is String && role.isNotEmpty) _chatRole = role;
      _mergeStreamingToolCalls(
        _chatToolCalls,
        delta['tool_calls'],
        idKey: 'id',
      );
    }
    final message = choice['message'];
    if (message is Map) {
      final role = message['role'];
      if (role is String && role.isNotEmpty) _chatRole = role;
      _mergeStreamingToolCalls(
        _chatToolCalls,
        message['tool_calls'],
        idKey: 'id',
      );
    }
    return style.streamDelta(event);
  }

  Map<String, Object?> get _chatCompletionEnvelope {
    final message = <String, Object?>{
      'role': _chatRole,
      'content': text.isEmpty ? null : text,
      if (_chatToolCalls.isNotEmpty)
        'tool_calls': [
          for (final entry
              in _chatToolCalls.entries.toList()
                ..sort((left, right) => left.key.compareTo(right.key)))
            entry.value.chatJson,
        ],
    };
    return {
      'choices': [
        {
          'index': 0,
          'message': message,
          if (_chatFinishReason != null) 'finish_reason': _chatFinishReason,
        },
      ],
    };
  }

  String _addResponses(Map<dynamic, dynamic> event) {
    final type = event['type'];
    if (type == 'response.completed' && event['response'] is Map) {
      final completed = _jsonMap(event['response'] as Map);
      _completedResponsesEnvelope = completed;
      if (_text.isEmpty) return style.responseText(completed) ?? '';
      return '';
    }

    final outputIndex = _eventIndex(event, 'output_index');
    if ((type == 'response.output_item.added' ||
            type == 'response.output_item.done') &&
        event['item'] is Map) {
      final item = _jsonMap(event['item'] as Map);
      final index = outputIndex ?? _responsesOutput.length;
      _responsesOutput[index] = item;
      final id = item['id'];
      if (id is String && id.isNotEmpty) {
        _responsesOutputIndexesById[id] = index;
      }
    } else if (type == 'response.function_call_arguments.delta' ||
        type == 'response.function_call_arguments.done') {
      final index = _responsesIndexForEvent(event, outputIndex);
      final item = _responsesOutput.putIfAbsent(index, () {
        final id = event['item_id'];
        return <String, Object?>{
          'type': 'function_call',
          if (id is String && id.isNotEmpty) 'id': id,
          if (event['call_id'] is String) 'call_id': event['call_id'],
          if (event['name'] is String) 'name': event['name'],
          'arguments': '',
        };
      });
      final id = event['item_id'];
      if (id is String && id.isNotEmpty) {
        item['id'] ??= id;
        _responsesOutputIndexesById[id] = index;
      }
      if (event['call_id'] is String) item['call_id'] ??= event['call_id'];
      if (event['name'] is String) item['name'] ??= event['name'];
      final value = type == 'response.function_call_arguments.done'
          ? event['arguments']
          : event['delta'];
      if (value is String) {
        if (type == 'response.function_call_arguments.done') {
          item['arguments'] = value;
        } else {
          item['arguments'] = '${item['arguments'] ?? ''}$value';
        }
      } else if (value is Map) {
        item['arguments'] = _jsonMap(value);
      }
    }

    final delta = style.streamDelta(event);
    if (delta.isNotEmpty) return delta;
    if (type == 'response.output_text.done' &&
        _text.isEmpty &&
        event['text'] is String) {
      return event['text'] as String;
    }
    return '';
  }

  int _responsesIndexForEvent(Map<dynamic, dynamic> event, int? outputIndex) {
    if (outputIndex != null) return outputIndex;
    final itemId = event['item_id'];
    if (itemId is String) {
      final known = _responsesOutputIndexesById[itemId];
      if (known != null) return known;
    }
    return _responsesOutput.isEmpty
        ? 0
        : _responsesOutput.keys.reduce(
                (left, right) => left > right ? left : right,
              ) +
              1;
  }

  Map<String, Object?> get _responsesEnvelope {
    final completed = _completedResponsesEnvelope;
    if (completed != null) return _jsonMap(completed);
    final output = <Object?>[
      for (final entry
          in _responsesOutput.entries.toList()
            ..sort((left, right) => left.key.compareTo(right.key)))
        _jsonMap(entry.value),
    ];
    final messageIndex = output.indexWhere(
      (item) => item is Map && item['type'] == 'message',
    );
    if (text.isNotEmpty) {
      final content = <Object?>[
        {'type': 'output_text', 'text': text},
      ];
      if (messageIndex < 0) {
        output.add({
          'type': 'message',
          'role': 'assistant',
          'content': content,
        });
      } else {
        final message = _jsonMap(output[messageIndex] as Map);
        final existingContent = message['content'];
        if (existingContent is! List || existingContent.isEmpty) {
          message['content'] = content;
        }
        output[messageIndex] = message;
      }
    }
    return {'output': output};
  }

  String _addAnthropic(Map<dynamic, dynamic> event) {
    final type = event['type'];
    if (type == 'message_start' && event['message'] is Map) {
      _anthropicMessage = _jsonMap(event['message'] as Map);
      final content = _anthropicMessage.remove('content');
      if (content is List) {
        for (final (index, block) in content.indexed) {
          if (block is Map) _anthropicContent[index] = _jsonMap(block);
        }
      }
    }
    if (type == 'content_block_start' && event['content_block'] is Map) {
      final index = _eventIndex(event, 'index') ?? _anthropicContent.length;
      final block = _jsonMap(event['content_block'] as Map);
      _anthropicContent[index] = block;
      final initialText = block['type'] == 'text' ? block['text'] : null;
      return initialText is String ? initialText : '';
    }
    if (type == 'content_block_delta' && event['delta'] is Map) {
      final index = _eventIndex(event, 'index') ?? 0;
      final delta = event['delta'] as Map;
      if (delta['type'] == 'input_json_delta') {
        final fragment = delta['partial_json'];
        if (fragment is String) {
          _anthropicInputFragments
              .putIfAbsent(index, StringBuffer.new)
              .write(fragment);
        }
        return '';
      }
      final textDelta = style.streamDelta(event);
      if (textDelta.isNotEmpty) {
        final block = _anthropicContent.putIfAbsent(
          index,
          () => {'type': 'text', 'text': ''},
        );
        block['text'] = '${block['text'] ?? ''}$textDelta';
      }
      return textDelta;
    }
    if (type == 'content_block_stop') {
      final index = _eventIndex(event, 'index') ?? 0;
      _finalizeAnthropicInput(index);
    } else if (type == 'message_delta' && event['delta'] is Map) {
      final stopReason = (event['delta'] as Map)['stop_reason'];
      if (stopReason is String && stopReason.isNotEmpty) {
        _anthropicStopReason = stopReason;
      }
    } else if (type == 'message_stop') {
      _anthropicMessageStopped = true;
    }
    return '';
  }

  void _finalizeAnthropicInput(int index) {
    final fragments = _anthropicInputFragments[index];
    if (fragments == null) return;
    final block = _anthropicContent[index];
    if (block == null || block['type'] != 'tool_use') return;
    final encoded = fragments.toString();
    try {
      final decoded = jsonDecode(encoded);
      block['input'] = decoded is Map ? _jsonMap(decoded) : encoded;
    } on FormatException {
      block['input'] = encoded;
    }
  }

  Map<String, Object?> get _anthropicEnvelope {
    for (final index in _anthropicInputFragments.keys) {
      _finalizeAnthropicInput(index);
    }
    final content = <Object?>[
      for (final entry
          in _anthropicContent.entries.toList()
            ..sort((left, right) => left.key.compareTo(right.key)))
        _jsonMap(entry.value),
    ];
    if (content.isEmpty && text.isNotEmpty) {
      content.add({'type': 'text', 'text': text});
    }
    return {
      ..._anthropicMessage,
      'content': content,
      if (_anthropicStopReason != null) 'stop_reason': _anthropicStopReason,
    };
  }

  String _addOllama(Map<dynamic, dynamic> event) {
    final metadata = _jsonMap(event)..remove('message');
    _ollamaEnvelope = {..._ollamaEnvelope, ...metadata};
    final message = event['message'];
    if (message is Map) {
      final role = message['role'];
      if (role is String && role.isNotEmpty) _ollamaRole = role;
      _mergeStreamingToolCalls(
        _ollamaToolCalls,
        message['tool_calls'],
        idKey: 'id',
      );
    }
    return style.streamDelta(event);
  }

  Map<String, Object?> get _ollamaCompletedEnvelope => {
    ..._ollamaEnvelope,
    'message': {
      'role': _ollamaRole,
      'content': text,
      if (_ollamaToolCalls.isNotEmpty)
        'tool_calls': [
          for (final entry
              in _ollamaToolCalls.entries.toList()
                ..sort((left, right) => left.key.compareTo(right.key)))
            entry.value.ollamaJson,
        ],
    },
  };
}

class _StreamingToolCall {
  String id = '';
  String type = 'function';
  String name = '';
  final StringBuffer arguments = StringBuffer();
  Map<String, Object?>? objectArguments;

  void merge(Map<dynamic, dynamic> raw, {required String idKey}) {
    final rawId = raw[idKey];
    if (rawId is String && rawId.isNotEmpty) id = _mergeStable(id, rawId);
    final rawType = raw['type'];
    if (rawType is String && rawType.isNotEmpty) type = rawType;
    final function = raw['function'];
    if (function is! Map) return;
    final rawName = function['name'];
    if (rawName is String && rawName.isNotEmpty) {
      name = _mergeStable(name, rawName);
    }
    final rawArguments = function['arguments'];
    if (rawArguments is Map) {
      objectArguments = _jsonMap(rawArguments);
    } else if (rawArguments is String && rawArguments.isNotEmpty) {
      arguments.write(rawArguments);
    }
  }

  Object get encodedArguments => objectArguments ?? arguments.toString();

  Map<String, Object?> get chatJson => {
    if (id.isNotEmpty) 'id': id,
    'type': type,
    'function': {'name': name, 'arguments': encodedArguments},
  };

  Map<String, Object?> get ollamaJson => {
    if (id.isNotEmpty) 'id': id,
    'type': type,
    'function': {'name': name, 'arguments': encodedArguments},
  };
}

void _mergeStreamingToolCalls(
  Map<int, _StreamingToolCall> target,
  Object? rawCalls, {
  required String idKey,
}) {
  if (rawCalls is! List) return;
  for (final (position, rawCall) in rawCalls.indexed) {
    if (rawCall is! Map) continue;
    final function = rawCall['function'];
    final index =
        _intValue(rawCall['index']) ??
        (function is Map ? _intValue(function['index']) : null) ??
        position;
    target
        .putIfAbsent(index, _StreamingToolCall.new)
        .merge(rawCall, idKey: idKey);
  }
}

String _mergeStable(String current, String next) {
  if (current.isEmpty || next.startsWith(current)) return next;
  if (current == next || current.endsWith(next)) return current;
  return '$current$next';
}

int? _eventIndex(Map<dynamic, dynamic> event, String key) =>
    _intValue(event[key]);

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return value is String ? int.tryParse(value) : null;
}

Map<String, Object?> _jsonMap(Map<dynamic, dynamic> value) => {
  for (final entry in value.entries) '${entry.key}': _jsonValue(entry.value),
};

Object? _jsonValue(Object? value) => switch (value) {
  Map<dynamic, dynamic>() => _jsonMap(value),
  List<dynamic>() => value.map(_jsonValue).toList(),
  _ => value,
};

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

String? _messageDelta(Object? message) {
  if (message is! Map) return null;
  final content = message['content'];
  if (content is String) return content;
  return _contentPartsText(content);
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

String _streamString(Object? value) => value is String ? value : '';
