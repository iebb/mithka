import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/ai_endpoint_style.dart';

void main() {
  test('derives request and model endpoints for every API style', () {
    expect(
      AiEndpointStyle.openAiChatCompletions
          .requestUriFor(Uri.parse('https://ai.example/custom'))
          .path,
      '/custom/v1/chat/completions',
    );
    expect(
      AiEndpointStyle.openAiResponses
          .modelsUriFor(Uri.parse('https://ai.example/custom/v1/responses'))
          .path,
      '/custom/v1/models',
    );
    expect(
      AiEndpointStyle.anthropicMessages
          .requestUriFor(Uri.parse('https://ai.example/v1'))
          .path,
      '/v1/messages',
    );
    expect(
      AiEndpointStyle.ollamaChat
          .modelsUriFor(Uri.parse('http://localhost:11434/api/chat'))
          .path,
      '/api/tags',
    );
  });

  test('builds OpenAI Responses requests and parses output text', () {
    final body = AiEndpointStyle.openAiResponses.requestBody(
      model: 'gpt-test',
      instructions: 'Return JSON.',
      input: 'Hello',
      stream: true,
      reasoningEffort: 'low',
      useJsonResponseFormat: true,
    );

    expect(body['instructions'], 'Return JSON.');
    expect(body['input'], 'Hello');
    expect(body['store'], isFalse);
    expect(body['reasoning'], {'effort': 'low'});
    expect(body['text'], {
      'format': {'type': 'json_object'},
    });
    expect(
      AiEndpointStyle.openAiResponses.responseText({
        'output': [
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': '{"ok":true}'},
            ],
          },
        ],
      }),
      '{"ok":true}',
    );
    expect(
      AiEndpointStyle.openAiResponses.streamDelta({
        'type': 'response.output_text.delta',
        'delta': 'Hello',
      }),
      'Hello',
    );
  });

  test('Responses reasoning output never becomes visible response text', () {
    expect(
      AiEndpointStyle.openAiResponses.responseText({
        'output': [
          {
            'type': 'reasoning',
            'content': [
              {
                'type': 'reasoning_text',
                'text': 'Private analysis about the reply target.',
              },
            ],
          },
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': '{"reply":"Visible reply"}'},
            ],
          },
        ],
      }),
      '{"reply":"Visible reply"}',
    );
  });

  test('uses native authentication and bodies for Anthropic and Ollama', () {
    final anthropicHeaders = AiEndpointStyle.anthropicMessages.requestHeaders(
      ' secret ',
    );
    expect(anthropicHeaders['x-api-key'], 'secret');
    expect(anthropicHeaders['anthropic-version'], '2023-06-01');
    expect(anthropicHeaders, isNot(contains('authorization')));
    final anthropicBody = AiEndpointStyle.anthropicMessages.requestBody(
      model: 'claude-test',
      instructions: 'Be brief.',
      input: 'Hello',
      stream: false,
    );
    expect(anthropicBody['system'], 'Be brief.');
    expect(anthropicBody['max_tokens'], 4096);
    expect(
      AiEndpointStyle.anthropicMessages.responseText({
        'content': [
          {'type': 'text', 'text': 'Hello'},
        ],
      }),
      'Hello',
    );

    final ollamaBody = AiEndpointStyle.ollamaChat.requestBody(
      model: 'local-test',
      instructions: 'Return JSON.',
      input: 'Hello',
      stream: true,
      useJsonResponseFormat: true,
    );
    expect(ollamaBody['format'], 'json');
    expect(
      AiEndpointStyle.ollamaChat.streamDelta({
        'message': {'content': 'Hi'},
      }),
      'Hi',
    );
  });

  test('maps an explicit output token cap to every endpoint dialect', () {
    for (final style in AiEndpointStyle.values) {
      final body = style.requestBody(
        model: 'reply-model',
        instructions: 'Reply briefly.',
        input: 'Hello',
        stream: true,
        maximumOutputTokens: 700,
      );
      final configuredLimit = switch (style) {
        AiEndpointStyle.openAiChatCompletions => body['max_tokens'],
        AiEndpointStyle.openAiResponses => body['max_output_tokens'],
        AiEndpointStyle.anthropicMessages => body['max_tokens'],
        AiEndpointStyle.ollamaChat => (body['options'] as Map)['num_predict'],
      };
      expect(configuredLimit, 700, reason: style.storageValue);
    }
  });

  test('maps a strict JSON schema to every endpoint dialect', () {
    const schema = <String, Object?>{
      'type': 'object',
      'properties': {
        'reply': {'type': 'string'},
      },
      'required': ['reply'],
      'additionalProperties': false,
    };

    final chat = AiEndpointStyle.openAiChatCompletions.requestBody(
      model: 'chat-model',
      instructions: 'Reply.',
      input: 'Hello',
      stream: true,
      jsonResponseSchema: schema,
      jsonResponseName: 'ai_reply',
    );
    expect(chat['response_format'], {
      'type': 'json_schema',
      'json_schema': {'name': 'ai_reply', 'strict': true, 'schema': schema},
    });

    final responses = AiEndpointStyle.openAiResponses.requestBody(
      model: 'responses-model',
      instructions: 'Reply.',
      input: 'Hello',
      stream: true,
      jsonResponseSchema: schema,
      jsonResponseName: 'ai_reply',
    );
    expect(responses['text'], {
      'format': {
        'type': 'json_schema',
        'name': 'ai_reply',
        'strict': true,
        'schema': schema,
      },
    });

    final anthropic = AiEndpointStyle.anthropicMessages.requestBody(
      model: 'claude-model',
      instructions: 'Reply.',
      input: 'Hello',
      stream: true,
      jsonResponseSchema: schema,
    );
    expect(anthropic['output_config'], {
      'format': {'type': 'json_schema', 'schema': schema},
    });

    final ollama = AiEndpointStyle.ollamaChat.requestBody(
      model: 'ollama-model',
      instructions: 'Reply.',
      input: 'Hello',
      stream: true,
      jsonResponseSchema: schema,
    );
    expect(ollama['format'], schema);
  });

  test('strict JSON schema fallbacks retain a structured boundary', () {
    const schema = <String, Object?>{'type': 'object'};
    final chat = AiEndpointStyle.openAiChatCompletions.requestBody(
      model: 'chat-model',
      instructions: 'Reply.',
      input: 'Hello',
      stream: true,
      jsonResponseSchema: schema,
    );
    final chatJson = AiEndpointStyle.openAiChatCompletions.withoutOptionalField(
      chat,
      'Unsupported response_format json_schema',
    );
    expect(chatJson['response_format'], {'type': 'json_object'});
    expect(
      AiEndpointStyle.openAiChatCompletions.withoutOptionalField(
        chatJson,
        'Unsupported response_format',
      ),
      isNot(contains('response_format')),
    );

    final ollama = AiEndpointStyle.ollamaChat.requestBody(
      model: 'ollama-model',
      instructions: 'Reply.',
      input: 'Hello',
      stream: true,
      jsonResponseSchema: schema,
    );
    final ollamaJson = AiEndpointStyle.ollamaChat.withoutOptionalField(
      ollama,
      'format schema unsupported',
    );
    expect(ollamaJson['format'], 'json');
  });

  test(
    'opaque upstream errors peel compatibility fields without disabling stream',
    () {
      const schema = <String, Object?>{'type': 'object'};
      final original = AiEndpointStyle.openAiChatCompletions.withFunctionTools(
        AiEndpointStyle.openAiChatCompletions.requestBody(
          model: 'deepseek-test',
          instructions: 'Reply.',
          input: 'Hello',
          stream: true,
          disableThinking: true,
          jsonResponseSchema: schema,
        ),
        [_chatContextTool],
      );
      const opaqueError =
          'Error from provider (Console): Upstream request failed';

      final jsonObject = AiEndpointStyle.openAiChatCompletions
          .withoutOptionalField(original, opaqueError);
      expect(jsonObject['response_format'], {'type': 'json_object'});
      expect(jsonObject['tools'], isNotNull);
      expect(jsonObject['thinking'], isNotNull);
      expect(jsonObject['stream'], isTrue);

      final withoutTools = AiEndpointStyle.openAiChatCompletions
          .withoutOptionalField(jsonObject, opaqueError);
      expect(withoutTools, isNot(contains('tools')));
      expect(withoutTools['thinking'], isNotNull);
      expect(withoutTools['stream'], isTrue);

      final withoutThinking = AiEndpointStyle.openAiChatCompletions
          .withoutOptionalField(withoutTools, opaqueError);
      expect(withoutThinking, isNot(contains('thinking')));
      expect(withoutThinking['stream'], isTrue);

      final promptOnly = AiEndpointStyle.openAiChatCompletions
          .withoutOptionalField(withoutThinking, opaqueError);
      expect(promptOnly, isNot(contains('response_format')));
      expect(promptOnly['stream'], isTrue);
    },
  );

  test('opaque fallbacks eventually reach prompt-only JSON for every API', () {
    const schema = <String, Object?>{'type': 'object'};
    const opaqueError = 'Upstream request failed';

    Map<String, Object?> peel(
      AiEndpointStyle style,
      Map<String, Object?> body,
    ) {
      var current = body;
      for (var attempt = 0; attempt < 8; attempt++) {
        final next = style.withoutOptionalField(current, opaqueError);
        if (identical(next, current)) return current;
        current = next;
      }
      fail('Opaque fallback did not converge for ${style.storageValue}');
    }

    for (final style in AiEndpointStyle.values) {
      var body = style.requestBody(
        model: 'test-model',
        instructions: 'Return JSON.',
        input: 'Hello',
        stream: true,
        reasoningEffort: 'low',
        disableThinking: true,
        jsonResponseSchema: schema,
      );
      body = style.withFunctionTools(body, [_chatContextTool]);
      final compatible = peel(style, body);

      expect(compatible, isNot(contains('tools')), reason: style.storageValue);
      switch (style) {
        case AiEndpointStyle.openAiChatCompletions:
          expect(
            compatible,
            isNot(contains('response_format')),
            reason: style.storageValue,
          );
          expect(compatible, isNot(contains('thinking')));
          expect(compatible, isNot(contains('reasoning_effort')));
          expect(compatible['stream'], isTrue);
        case AiEndpointStyle.openAiResponses:
          expect(
            compatible,
            isNot(contains('text')),
            reason: style.storageValue,
          );
          expect(compatible, isNot(contains('reasoning')));
          expect(compatible['stream'], isTrue);
        case AiEndpointStyle.anthropicMessages:
          expect(compatible, isNot(contains('output_config')));
          expect(compatible['stream'], isFalse);
        case AiEndpointStyle.ollamaChat:
          expect(compatible, isNot(contains('format')));
          expect(compatible['stream'], isTrue);
      }
    }
  });

  test('stream deltas preserve whitespace-only chunks', () {
    expect(
      AiEndpointStyle.openAiResponses.streamDelta({
        'type': 'response.output_text.delta',
        'delta': ' ',
      }),
      ' ',
    );
    expect(
      AiEndpointStyle.anthropicMessages.streamDelta({
        'type': 'content_block_delta',
        'delta': {'type': 'text_delta', 'text': '\n'},
      }),
      '\n',
    );
    expect(
      AiEndpointStyle.ollamaChat.streamDelta({
        'message': {'content': ' '},
      }),
      ' ',
    );
  });

  test('Anthropic thinking stays internal while text remains visible', () {
    final stream = AiEndpointStreamAccumulator(
      AiEndpointStyle.anthropicMessages,
    );
    stream.add({
      'type': 'message_start',
      'message': {'role': 'assistant', 'content': <Object?>[]},
    });
    stream.add({
      'type': 'content_block_start',
      'index': 0,
      'content_block': {'type': 'thinking', 'thinking': ''},
    });
    expect(
      stream.add({
        'type': 'content_block_delta',
        'index': 0,
        'delta': {'type': 'thinking_delta', 'thinking': 'Private analysis.'},
      }),
      isEmpty,
    );
    expect(
      stream.add({
        'type': 'content_block_delta',
        'index': 0,
        'delta': {'type': 'signature_delta', 'signature': 'signed'},
      }),
      isEmpty,
    );
    stream.add({
      'type': 'content_block_start',
      'index': 1,
      'content_block': {'type': 'text', 'text': ''},
    });
    expect(
      stream.add({
        'type': 'content_block_delta',
        'index': 1,
        'delta': {'type': 'text_delta', 'text': '{"reply":"Visible reply"}'},
      }),
      '{"reply":"Visible reply"}',
    );
    stream.add({
      'type': 'message_delta',
      'delta': {'stop_reason': 'end_turn'},
    });
    stream.add({'type': 'message_stop'});

    final content = stream.envelope['content']! as List<Object?>;
    expect(content.first, {
      'type': 'thinking',
      'thinking': 'Private analysis.',
      'signature': 'signed',
    });
    expect(stream.text, '{"reply":"Visible reply"}');
    expect(
      AiEndpointStyle.anthropicMessages.responseText(stream.envelope),
      '{"reply":"Visible reply"}',
    );
  });

  test('Ollama thinking stays internal while text remains visible', () {
    final stream = AiEndpointStreamAccumulator(AiEndpointStyle.ollamaChat);
    expect(
      stream.add({
        'message': {
          'role': 'assistant',
          'thinking': 'Private analysis.',
          'content': '',
        },
        'done': false,
      }),
      isEmpty,
    );
    expect(
      stream.add({
        'message': {
          'role': 'assistant',
          'content': '{"reply":"Visible reply"}',
        },
        'done': true,
      }),
      '{"reply":"Visible reply"}',
    );

    final message = stream.envelope['message']! as Map<String, Object?>;
    expect(message['thinking'], 'Private analysis.');
    expect(message['content'], '{"reply":"Visible reply"}');
    expect(
      AiEndpointStyle.ollamaChat.responseText(stream.envelope),
      '{"reply":"Visible reply"}',
    );
  });

  test('serializes function tools for every endpoint dialect', () {
    final base = <String, Object?>{'model': 'reply-model'};

    final chat = AiEndpointStyle.openAiChatCompletions.withFunctionTools(base, [
      _chatContextTool,
    ]);
    expect(chat['tools'], [
      {
        'type': 'function',
        'function': {
          'name': 'get_chat_context',
          'description': 'Read earlier messages from the current chat.',
          'parameters': _chatContextParameters,
          'strict': true,
        },
      },
    ]);
    expect(chat['tool_choice'], 'auto');

    final responses = AiEndpointStyle.openAiResponses.withFunctionTools(base, [
      _chatContextTool,
    ]);
    expect(responses['tools'], [
      {
        'type': 'function',
        'name': 'get_chat_context',
        'description': 'Read earlier messages from the current chat.',
        'parameters': _chatContextParameters,
        'strict': true,
      },
    ]);
    expect(responses['tool_choice'], 'auto');

    final anthropic = AiEndpointStyle.anthropicMessages.withFunctionTools(
      base,
      [_chatContextTool],
    );
    expect(anthropic['tools'], [
      {
        'name': 'get_chat_context',
        'description': 'Read earlier messages from the current chat.',
        'input_schema': _chatContextParameters,
        'strict': true,
      },
    ]);
    expect(anthropic['tool_choice'], {'type': 'auto'});

    final ollama = AiEndpointStyle.ollamaChat.withFunctionTools(base, [
      _chatContextTool,
    ]);
    expect(ollama['tools'], [
      {
        'type': 'function',
        'function': {
          'name': 'get_chat_context',
          'description': 'Read earlier messages from the current chat.',
          'parameters': _chatContextParameters,
        },
      },
    ]);
    expect(ollama, isNot(contains('tool_choice')));
    expect(base, {'model': 'reply-model'});
  });

  test('parses and continues an OpenAI Responses function call', () {
    const style = AiEndpointStyle.openAiResponses;
    final original = style.withFunctionTools(
      style.requestBody(
        model: 'gpt-test',
        instructions: 'Draft a reply.',
        input: 'Initial chat excerpt',
        stream: false,
      ),
      [_chatContextTool],
    );
    final response = <String, Object?>{
      'output': [
        {'type': 'reasoning', 'id': 'reasoning-1', 'summary': <Object?>[]},
        {
          'type': 'function_call',
          'id': 'function-1',
          'call_id': 'call-responses-1',
          'name': 'get_chat_context',
          'arguments': '{"query":"release date","limit":12}',
        },
      ],
    };

    final calls = style.functionToolCalls(response);

    expect(calls, hasLength(1));
    expect(calls.single.id, 'call-responses-1');
    expect(calls.single.name, 'get_chat_context');
    expect(calls.single.arguments, {'query': 'release date', 'limit': 12});

    final continued = style.toolContinuationBody(
      previousBody: original,
      response: response,
      results: [
        AiFunctionToolResult(
          call: calls.single,
          output: '{"messages":["July 30"]}',
        ),
      ],
    );
    expect(continued['input'], [
      {'role': 'user', 'content': 'Initial chat excerpt'},
      {'type': 'reasoning', 'id': 'reasoning-1', 'summary': <Object?>[]},
      {
        'type': 'function_call',
        'id': 'function-1',
        'call_id': 'call-responses-1',
        'name': 'get_chat_context',
        'arguments': '{"query":"release date","limit":12}',
      },
      {
        'type': 'function_call_output',
        'call_id': 'call-responses-1',
        'output': '{"messages":["July 30"]}',
      },
    ]);
    expect(continued['tools'], original['tools']);
    expect(continued['tool_choice'], 'auto');
    expect(original['input'], 'Initial chat excerpt');
  });

  test('parses and continues an OpenAI Chat Completions function call', () {
    const style = AiEndpointStyle.openAiChatCompletions;
    final original = style.withFunctionTools(
      style.requestBody(
        model: 'chat-test',
        instructions: 'Draft a reply.',
        input: 'Initial chat excerpt',
        stream: false,
      ),
      [_chatContextTool],
    );
    final assistant = <String, Object?>{
      'role': 'assistant',
      'content': null,
      'tool_calls': [
        {
          'id': 'call-chat-1',
          'type': 'function',
          'function': {
            'name': 'get_chat_context',
            'arguments': '{"before_cursor":"42","limit":8}',
          },
        },
      ],
    };
    final response = <String, Object?>{
      'choices': [
        {'index': 0, 'message': assistant, 'finish_reason': 'tool_calls'},
      ],
    };

    final calls = style.functionToolCalls(response);

    expect(calls, hasLength(1));
    expect(calls.single.id, 'call-chat-1');
    expect(calls.single.name, 'get_chat_context');
    expect(calls.single.arguments, {'before_cursor': '42', 'limit': 8});

    final continued = style.toolContinuationBody(
      previousBody: original,
      response: response,
      results: [
        AiFunctionToolResult(call: calls.single, output: 'Earlier messages'),
      ],
    );
    expect(continued['messages'], [
      {'role': 'system', 'content': 'Draft a reply.'},
      {'role': 'user', 'content': 'Initial chat excerpt'},
      assistant,
      {
        'role': 'tool',
        'tool_call_id': 'call-chat-1',
        'content': 'Earlier messages',
      },
    ]);
    expect(continued['tools'], original['tools']);
    expect(original['messages'], hasLength(2));
  });

  test('parses and continues an Anthropic Messages tool use', () {
    const style = AiEndpointStyle.anthropicMessages;
    final original = style.withFunctionTools(
      style.requestBody(
        model: 'claude-test',
        instructions: 'Draft a reply.',
        input: 'Initial chat excerpt',
        stream: false,
      ),
      [_chatContextTool],
    );
    final content = <Object?>[
      {'type': 'text', 'text': 'I will check earlier context.'},
      {
        'type': 'tool_use',
        'id': 'toolu-anthropic-1',
        'name': 'get_chat_context',
        'input': {'query': 'meeting time', 'limit': 6},
      },
    ];
    final response = <String, Object?>{
      'content': content,
      'stop_reason': 'tool_use',
    };

    final calls = style.functionToolCalls(response);

    expect(calls, hasLength(1));
    expect(calls.single.id, 'toolu-anthropic-1');
    expect(calls.single.name, 'get_chat_context');
    expect(calls.single.arguments, {'query': 'meeting time', 'limit': 6});

    final continued = style.toolContinuationBody(
      previousBody: original,
      response: response,
      results: [
        AiFunctionToolResult(call: calls.single, output: 'Meeting is at 15:00'),
      ],
    );
    expect(continued['messages'], [
      {'role': 'user', 'content': 'Initial chat excerpt'},
      {'role': 'assistant', 'content': content},
      {
        'role': 'user',
        'content': [
          {
            'type': 'tool_result',
            'tool_use_id': 'toolu-anthropic-1',
            'content': 'Meeting is at 15:00',
          },
        ],
      },
    ]);
    expect(continued['tools'], original['tools']);
    expect(continued['tool_choice'], {'type': 'auto'});
    expect(original['messages'], hasLength(1));
  });

  test('parses and continues an Ollama function call without a call ID', () {
    const style = AiEndpointStyle.ollamaChat;
    final original = style.withFunctionTools(
      style.requestBody(
        model: 'qwen-test',
        instructions: 'Draft a reply.',
        input: 'Initial chat excerpt',
        stream: false,
      ),
      [_chatContextTool],
    );
    final assistant = <String, Object?>{
      'role': 'assistant',
      'content': '',
      'tool_calls': [
        {
          'type': 'function',
          'function': {
            'index': 0,
            'name': 'get_chat_context',
            'arguments': {'query': 'address', 'limit': 4},
          },
        },
      ],
    };
    final response = <String, Object?>{'message': assistant, 'done': true};

    final calls = style.functionToolCalls(response);

    expect(calls, hasLength(1));
    expect(calls.single.id, 'ollama_chat-0-get_chat_context');
    expect(calls.single.name, 'get_chat_context');
    expect(calls.single.arguments, {'query': 'address', 'limit': 4});

    final continued = style.toolContinuationBody(
      previousBody: original,
      response: response,
      results: [
        AiFunctionToolResult(call: calls.single, output: '1 Telegram Way'),
      ],
    );
    expect(continued['messages'], [
      {'role': 'system', 'content': 'Draft a reply.'},
      {'role': 'user', 'content': 'Initial chat excerpt'},
      assistant,
      {
        'role': 'tool',
        'tool_name': 'get_chat_context',
        'content': '1 Telegram Way',
      },
    ]);
    expect(continued['tools'], original['tools']);
    expect(original['messages'], hasLength(2));
  });

  test('accumulates streamed Chat Completion text and fragmented tools', () {
    const style = AiEndpointStyle.openAiChatCompletions;
    final stream = AiEndpointStreamAccumulator(style);
    expect(stream.isComplete, isFalse);

    expect(
      stream.add({
        'choices': [
          {
            'delta': {
              'role': 'assistant',
              'reasoning_content': 'Private planning.',
            },
          },
        ],
      }),
      isEmpty,
    );
    expect(
      stream.add({
        'choices': [
          {
            'delta': {'content': 'I can '},
          },
        ],
      }),
      'I can ',
    );
    expect(
      stream.add({
        'choices': [
          {
            'delta': {'content': 'check.'},
          },
        ],
      }),
      'check.',
    );
    stream.add({
      'choices': [
        {
          'delta': {
            'tool_calls': [
              {
                'index': 0,
                'id': 'call-chat-stream',
                'type': 'function',
                'function': {
                  'name': 'get_chat_context',
                  'arguments': '{"query":"meeting',
                },
              },
            ],
          },
        },
      ],
    });
    stream.add({
      'choices': [
        {
          'delta': {
            'tool_calls': [
              {
                'index': 0,
                'function': {'arguments': ' time"}'},
              },
            ],
          },
          'finish_reason': 'tool_calls',
        },
      ],
    });

    expect(stream.text, 'I can check.');
    expect(style.responseText(stream.envelope), 'I can check.');
    final message =
        ((stream.envelope['choices'] as List).single as Map)['message'] as Map;
    expect(message['reasoning_content'], 'Private planning.');
    expect(stream.hasToolCalls, isTrue);
    final calls = style.functionToolCalls(stream.envelope);
    expect(calls, hasLength(1));
    expect(calls.single.id, 'call-chat-stream');
    expect(calls.single.name, 'get_chat_context');
    expect(calls.single.arguments, {'query': 'meeting time'});
    expect(
      (stream.envelope['choices'] as List).single['finish_reason'],
      'tool_calls',
    );
    expect(stream.isComplete, isTrue);
  });

  test('preserves a streamed Chat refusal without exposing it as text', () {
    const style = AiEndpointStyle.openAiChatCompletions;
    final stream = AiEndpointStreamAccumulator(style);

    stream.add({
      'choices': [
        {
          'delta': {'refusal': 'I cannot help with that.'},
          'finish_reason': 'stop',
        },
      ],
    });

    expect(stream.text, isEmpty);
    expect(style.responseText(stream.envelope), isNull);
    expect(style.refusalText(stream.envelope), 'I cannot help with that.');
    expect(stream.isComplete, isTrue);
  });

  test(
    'accumulates Responses tools and prefers the completed response envelope',
    () {
      const style = AiEndpointStyle.openAiResponses;
      final stream = AiEndpointStreamAccumulator(style);
      stream.add({
        'type': 'response.output_item.done',
        'output_index': 0,
        'item': {
          'type': 'reasoning',
          'id': 'reasoning-stream',
          'summary': <Object?>[],
        },
      });
      stream.add({
        'type': 'response.output_item.added',
        'output_index': 1,
        'item': {
          'type': 'function_call',
          'id': 'function-stream',
          'call_id': 'call-responses-stream',
          'name': 'get_chat_context',
          'arguments': '',
        },
      });
      stream.add({
        'type': 'response.function_call_arguments.delta',
        'output_index': 1,
        'item_id': 'function-stream',
        'delta': '{"query":"release',
      });
      stream.add({
        'type': 'response.function_call_arguments.delta',
        'output_index': 1,
        'item_id': 'function-stream',
        'delta': ' date"}',
      });
      expect(
        stream.add({
          'type': 'response.output_text.delta',
          'delta': 'July 30 works.',
        }),
        'July 30 works.',
      );

      expect(stream.hasToolCalls, isTrue);
      expect(style.functionToolCalls(stream.envelope).single.arguments, {
        'query': 'release date',
      });
      expect((stream.envelope['output'] as List).first, {
        'type': 'reasoning',
        'id': 'reasoning-stream',
        'summary': <Object?>[],
      });

      final completed = <String, Object?>{
        'id': 'response-stream',
        'output': [
          {
            'type': 'reasoning',
            'id': 'reasoning-authoritative',
            'summary': <Object?>[],
          },
          {
            'type': 'function_call',
            'id': 'function-stream',
            'call_id': 'call-responses-stream',
            'name': 'get_chat_context',
            'arguments': '{"query":"release date"}',
          },
          {
            'type': 'message',
            'role': 'assistant',
            'content': [
              {'type': 'output_text', 'text': 'July 30 works.'},
            ],
          },
        ],
      };
      expect(
        stream.add({'type': 'response.completed', 'response': completed}),
        isEmpty,
      );

      expect(stream.envelope, completed);
      expect(stream.isComplete, isTrue);
      expect(
        (stream.envelope['output'] as List).first,
        containsPair('id', 'reasoning-authoritative'),
      );
      expect(style.responseText(stream.envelope), 'July 30 works.');
    },
  );

  test('treats an incomplete Responses event as terminal', () {
    const style = AiEndpointStyle.openAiResponses;
    final stream = AiEndpointStreamAccumulator(style);

    stream.add({
      'type': 'response.output_item.done',
      'output_index': 0,
      'item': {
        'type': 'reasoning',
        'id': 'reasoning-only',
        'summary': <Object?>[],
      },
    });
    stream.add({
      'type': 'response.incomplete',
      'response': {
        'id': 'response-incomplete',
        'status': 'incomplete',
        'incomplete_details': {'reason': 'max_tokens'},
        'output': <Object?>[],
      },
    });

    expect(stream.isComplete, isTrue);
    expect(style.outputLimitReached(stream.envelope), isTrue);
    expect((stream.envelope['output'] as List).single, {
      'type': 'reasoning',
      'id': 'reasoning-only',
      'summary': <Object?>[],
    });
  });

  test('preserves Responses text when a terminal envelope omits output', () {
    const style = AiEndpointStyle.openAiResponses;
    final stream = AiEndpointStreamAccumulator(style);

    stream.add({
      'type': 'response.output_text.delta',
      'delta': 'Visible streamed reply.',
    });
    stream.add({
      'type': 'response.completed',
      'response': {
        'id': 'response-completed',
        'status': 'completed',
        'output': <Object?>[],
      },
    });

    expect(stream.isComplete, isTrue);
    expect(style.responseText(stream.envelope), 'Visible streamed reply.');
  });

  test('assembles indexed Anthropic text and fragmented tool input', () {
    const style = AiEndpointStyle.anthropicMessages;
    final stream = AiEndpointStreamAccumulator(style);
    stream.add({
      'type': 'message_start',
      'message': {
        'id': 'message-anthropic-stream',
        'role': 'assistant',
        'content': <Object?>[],
      },
    });
    stream.add({
      'type': 'content_block_start',
      'index': 0,
      'content_block': {'type': 'text', 'text': ''},
    });
    expect(
      stream.add({
        'type': 'content_block_delta',
        'index': 0,
        'delta': {'type': 'text_delta', 'text': 'I will check.'},
      }),
      'I will check.',
    );
    stream.add({
      'type': 'content_block_start',
      'index': 1,
      'content_block': {
        'type': 'tool_use',
        'id': 'toolu-anthropic-stream',
        'name': 'get_chat_context',
        'input': <String, Object?>{},
      },
    });
    stream.add({
      'type': 'content_block_delta',
      'index': 1,
      'delta': {
        'type': 'input_json_delta',
        'partial_json': '{"query":"meeting',
      },
    });
    stream.add({
      'type': 'content_block_delta',
      'index': 1,
      'delta': {'type': 'input_json_delta', 'partial_json': ' time"}'},
    });
    stream.add({'type': 'content_block_stop', 'index': 1});
    stream.add({
      'type': 'message_delta',
      'delta': {'stop_reason': 'tool_use'},
    });
    expect(stream.isComplete, isFalse);
    stream.add({'type': 'message_stop'});

    expect(stream.text, 'I will check.');
    expect(style.responseText(stream.envelope), 'I will check.');
    expect(stream.envelope['stop_reason'], 'tool_use');
    final content = stream.envelope['content'] as List;
    expect(content.map((block) => block['type']), ['text', 'tool_use']);
    final calls = style.functionToolCalls(stream.envelope);
    expect(calls, hasLength(1));
    expect(calls.single.id, 'toolu-anthropic-stream');
    expect(calls.single.arguments, {'query': 'meeting time'});
    expect(stream.isComplete, isTrue);
  });

  test('accumulates Ollama text and fragmented tool arguments', () {
    const style = AiEndpointStyle.ollamaChat;
    final stream = AiEndpointStreamAccumulator(style);

    expect(
      stream.add({
        'model': 'qwen-test',
        'message': {'role': 'assistant', 'content': 'Let me '},
        'done': false,
      }),
      'Let me ',
    );
    expect(
      stream.add({
        'model': 'qwen-test',
        'message': {'role': 'assistant', 'content': 'check.'},
        'done': false,
      }),
      'check.',
    );
    stream.add({
      'model': 'qwen-test',
      'message': {
        'role': 'assistant',
        'content': '',
        'tool_calls': [
          {
            'function': {
              'index': 0,
              'name': 'get_chat_',
              'arguments': '{"query":"addr',
            },
          },
        ],
      },
      'done': false,
    });
    stream.add({
      'model': 'qwen-test',
      'message': {
        'role': 'assistant',
        'content': '',
        'tool_calls': [
          {
            'function': {'index': 0, 'name': 'context', 'arguments': 'ess"}'},
          },
        ],
      },
      'done': true,
    });

    expect(stream.text, 'Let me check.');
    expect(style.responseText(stream.envelope), 'Let me check.');
    expect(stream.envelope['done'], isTrue);
    expect(stream.isComplete, isTrue);
    final calls = style.functionToolCalls(stream.envelope);
    expect(calls, hasLength(1));
    expect(calls.single.name, 'get_chat_context');
    expect(calls.single.arguments, {'query': 'address'});
  });

  test('compatibility fallback strips unsupported tool fields', () {
    for (final (index, style) in AiEndpointStyle.values.indexed) {
      final body = style.withFunctionTools(
        <String, Object?>{
          'model': 'test-model',
          'stream': false,
          'parallel_tool_calls': true,
        },
        [_chatContextTool],
      );
      final error = index.isEven
          ? '400 Unsupported tools parameter'
          : '422 Function calling is not supported by this model';

      final compatible = style.withoutOptionalField(body, error);

      expect(compatible, isNot(same(body)), reason: style.storageValue);
      expect(compatible, isNot(contains('tools')), reason: style.storageValue);
      expect(
        compatible,
        isNot(contains('tool_choice')),
        reason: style.storageValue,
      );
      expect(
        compatible,
        isNot(contains('parallel_tool_calls')),
        reason: style.storageValue,
      );
      expect(compatible['model'], 'test-model', reason: style.storageValue);
      expect(body, contains('tools'), reason: style.storageValue);
    }
  });

  test(
    'compatibility fallback keeps tools when only strict is unsupported',
    () {
      for (final style in AiEndpointStyle.values.where(
        (style) => style != AiEndpointStyle.ollamaChat,
      )) {
        final body = style.withFunctionTools(
          <String, Object?>{'model': 'test-model'},
          [_chatContextTool],
        );

        final compatible = style.withoutOptionalField(
          body,
          'Unknown field tools[0].strict',
        );

        expect(compatible, isNot(same(body)), reason: style.storageValue);
        expect(compatible, contains('tools'), reason: style.storageValue);
        expect(jsonEncode(compatible['tools']), isNot(contains('"strict"')));
        expect(jsonEncode(body['tools']), contains('"strict"'));
      }
    },
  );

  test('compatibility fallback keeps tools without tool choice', () {
    final body = AiEndpointStyle.openAiResponses.withFunctionTools(
      <String, Object?>{'model': 'test-model'},
      [_chatContextTool],
    );

    final compatible = AiEndpointStyle.openAiResponses.withoutOptionalField(
      body,
      'Unknown parameter: tool_choice',
    );

    expect(compatible, contains('tools'));
    expect(compatible, isNot(contains('tool_choice')));
    expect(body['tool_choice'], 'auto');
  });

  test('detects output budget exhaustion for every endpoint dialect', () {
    expect(
      AiEndpointStyle.openAiChatCompletions.outputLimitReached({
        'choices': [
          {'finish_reason': 'length'},
        ],
      }),
      isTrue,
    );
    expect(
      AiEndpointStyle.openAiResponses.outputLimitReached({
        'status': 'incomplete',
        'incomplete_details': {'reason': 'max_tokens'},
      }),
      isTrue,
    );
    expect(
      AiEndpointStyle.anthropicMessages.outputLimitReached({
        'stop_reason': 'max_tokens',
      }),
      isTrue,
    );
    expect(
      AiEndpointStyle.ollamaChat.outputLimitReached({'done_reason': 'length'}),
      isTrue,
    );
  });
}

const _chatContextParameters = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{
    'query': <String, Object?>{'type': 'string'},
    'before_cursor': <String, Object?>{'type': 'string'},
    'limit': <String, Object?>{'type': 'integer', 'minimum': 1, 'maximum': 24},
  },
  'required': <String>[],
  'additionalProperties': false,
};

const _chatContextTool = AiFunctionToolDefinition(
  name: 'get_chat_context',
  description: 'Read earlier messages from the current chat.',
  parameters: _chatContextParameters,
);
