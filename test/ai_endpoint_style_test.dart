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
