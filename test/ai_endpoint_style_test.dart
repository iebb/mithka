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
}
