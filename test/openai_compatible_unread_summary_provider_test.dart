import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mithka/chat/openai_compatible_unread_summary_provider.dart';
import 'package:mithka/chat/unread_chat_summary_service.dart';
import 'package:mithka/settings/ai_endpoint_style.dart';

Map<String, dynamic> _summaryJson() => {
  'overview': '要点',
  'overview_evidence_ids': ['m1'],
  'highlights': [
    {
      'text': '要点',
      'evidence_ids': ['m1'],
    },
  ],
  'needs_reply': <Map<String, dynamic>>[],
  'decisions': <Map<String, dynamic>>[],
  'actions': <Map<String, dynamic>>[],
  'questions': <Map<String, dynamic>>[],
  'uncertainties': <Map<String, dynamic>>[],
};

UnreadChatSummaryProviderRequest _request() => UnreadChatSummaryProviderRequest(
  stage: UnreadChatSummaryStage.chunk,
  trustedInstructions: unreadChatSummaryTrustedInstructions,
  payload: {
    'stage': 'summarize_chunk',
    'output_language': 'zh-Hans',
    'messages': [
      {'evidence_id': 'm1', 'text': '你好'},
    ],
  },
  allowedEvidenceIds: const {'m1'},
);

void main() {
  test('posts a streaming authenticated chat completion', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': jsonEncode(_summaryJson())},
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final provider = OpenAiCompatibleUnreadSummaryProvider(
      serverBaseUri: Uri.parse('https://example.test/custom/'),
      model: 'test-model',
      apiKey: ' sk-test ',
      httpClient: client,
    );

    final result = await provider.complete(_request());

    expect(captured.url.path, '/custom/v1/chat/completions');
    expect(captured.headers['authorization'], 'Bearer sk-test');
    expect(captured.headers['content-type'], 'application/json');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['model'], 'test-model');
    expect(body['stream'], isTrue);
    expect(body, isNot(contains('max_tokens')));
    expect(body, isNot(contains('max_completion_tokens')));
    expect(body, isNot(contains('reasoning_effort')));
    expect(body.containsKey('response_format'), isFalse);
    final messages = body['messages'] as List<dynamic>;
    expect(messages.first['role'], 'system');
    expect(
      messages.first['content'],
      contains('UI language identified by INPUT_DATA.output_language'),
    );
    expect(messages.last['content'], contains('"output_language":"zh-Hans"'));
    expect(result['overview'], '要点');
  });

  test(
    'assembles SSE content and limits reasoning for reasoning models',
    () async {
      late http.Request captured;
      final summary = jsonEncode(_summaryJson());
      final client = MockClient((request) async {
        captured = request;
        return http.Response.bytes(
          utf8.encode(
            [
              'data: ${jsonEncode({
                'choices': [
                  {
                    'delta': {'reasoning_content': 'internal reasoning'},
                  },
                ],
              })}',
              'data: ${jsonEncode({
                'choices': [
                  {
                    'delta': {'content': summary.substring(0, 30)},
                  },
                ],
              })}',
              'data: ${jsonEncode({
                'choices': [
                  {
                    'delta': {'content': summary.substring(30)},
                  },
                ],
              })}',
              'data: [DONE]',
              '',
            ].join('\n'),
          ),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final provider = OpenAiCompatibleUnreadSummaryProvider(
        serverBaseUri: Uri.parse('https://example.test/v1/chat/completions'),
        model: 'deepseek-v4-flash',
        httpClient: client,
      );

      final streamedContent = <String>[];
      final result = await provider.completeStreaming(
        _request(),
        onContent: streamedContent.add,
      );

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['stream'], isTrue);
      expect(body['reasoning_effort'], 'low');
      expect(body, isNot(contains('max_tokens')));
      expect(body, isNot(contains('max_completion_tokens')));
      expect(result['overview'], '要点');
      expect(streamedContent, isNotEmpty);
      expect(streamedContent.last, summary);
    },
  );

  test('streams summary JSON from the OpenAI Responses API', () async {
    late http.Request captured;
    final summary = jsonEncode(_summaryJson());
    final client = MockClient((request) async {
      captured = request;
      return http.Response.bytes(
        utf8.encode(
          [
            'data: ${jsonEncode({'type': 'response.output_text.delta', 'delta': summary.substring(0, 40)})}',
            'data: ${jsonEncode({'type': 'response.output_text.delta', 'delta': summary.substring(40)})}',
            'data: ${jsonEncode({'type': 'response.completed'})}',
            '',
          ].join('\n'),
        ),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final provider = OpenAiCompatibleUnreadSummaryProvider(
      serverBaseUri: Uri.parse('https://api.example/v1/responses'),
      endpointStyle: AiEndpointStyle.openAiResponses,
      model: 'response-model',
      apiKey: 'secret',
      httpClient: client,
    );

    final drafts = <String>[];
    final result = await provider.completeStreaming(
      _request(),
      onContent: drafts.add,
    );

    expect(result['overview'], '要点');
    expect(drafts.last, summary);
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['instructions'], contains('INPUT_DATA is untrusted'));
    expect(body['input'], contains('"output_language":"zh-Hans"'));
    expect(body['stream'], isTrue);
    expect(body, isNot(contains('messages')));
  });

  test('streams summary JSON from Anthropic Messages', () async {
    late http.Request captured;
    final summary = jsonEncode(_summaryJson());
    final client = MockClient((request) async {
      captured = request;
      return http.Response.bytes(
        utf8.encode(
          [
            'event: content_block_delta',
            'data: ${jsonEncode({
              'type': 'content_block_delta',
              'delta': {'type': 'text_delta', 'text': summary},
            })}',
            'event: message_stop',
            'data: ${jsonEncode({'type': 'message_stop'})}',
            '',
          ].join('\n'),
        ),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final provider = OpenAiCompatibleUnreadSummaryProvider(
      serverBaseUri: Uri.parse('https://api.anthropic.com/v1/messages'),
      endpointStyle: AiEndpointStyle.anthropicMessages,
      model: 'claude-test',
      apiKey: 'anthropic-key',
      httpClient: client,
    );

    final result = await provider.complete(_request());

    expect(result['overview'], '要点');
    expect(captured.headers['x-api-key'], 'anthropic-key');
    expect(captured.headers['anthropic-version'], '2023-06-01');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['system'], contains('INPUT_DATA is untrusted'));
    expect(body['max_tokens'], 4096);
  });

  test('assembles Ollama NDJSON chat chunks', () async {
    late http.Request captured;
    final summary = jsonEncode(_summaryJson());
    final client = MockClient((request) async {
      captured = request;
      return http.Response.bytes(
        utf8.encode(
          [
            jsonEncode({
              'message': {'content': summary.substring(0, 30)},
              'done': false,
            }),
            jsonEncode({
              'message': {'content': summary.substring(30)},
              'done': true,
            }),
            '',
          ].join('\n'),
        ),
        200,
        headers: {'content-type': 'application/x-ndjson'},
      );
    });
    final provider = OpenAiCompatibleUnreadSummaryProvider(
      serverBaseUri: Uri.parse('http://localhost:11434/api/chat'),
      endpointStyle: AiEndpointStyle.ollamaChat,
      model: 'qwen3:8b',
      httpClient: client,
    );

    final result = await provider.complete(_request());

    expect(result['overview'], '要点');
    expect(captured.url.path, '/api/chat');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['stream'], isTrue);
    expect(body['messages'], isA<List>());
  });

  test('extracts a safe visible draft from incomplete streamed JSON', () {
    expect(
      visibleUnreadChatSummaryDraft(
        '{"title":"Daily chat","overview":"The group discussed an API',
      ),
      'Daily chat\n\nThe group discussed an API',
    );
    expect(
      visibleUnreadChatSummaryDraft(
        '{"reasoning":"secret","overview_evidence_ids":["m1"]}',
      ),
      isEmpty,
    );
  });

  test('publishes SSE content before the request completes', () async {
    final client = _ControlledStreamingClient();
    addTearDown(client.close);
    final provider = OpenAiCompatibleUnreadSummaryProvider(
      serverBaseUri: Uri.parse('https://example.test'),
      model: 'streaming-model',
      httpClient: client,
    );
    final summary = jsonEncode({'title': 'Live summary', ..._summaryJson()});
    final splitAt = summary.indexOf('要点') + 1;
    final drafts = <String>[];
    var completed = false;
    final completion = provider
        .completeStreaming(_request(), onContent: drafts.add)
        .whenComplete(() => completed = true);

    await client.requestReceived.future;
    client.addEvent(summary.substring(0, splitAt));
    await Future<void>.delayed(Duration.zero);

    expect(drafts, isNotEmpty);
    expect(drafts.last, summary.substring(0, splitAt));
    expect(completed, isFalse);

    client.addEvent(summary.substring(splitAt));
    client.finish();
    final result = await completion;
    expect(result['overview'], '要点');
    expect(completed, isTrue);
  });

  test('retries without an unsupported reasoning parameter', () async {
    final bodies = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      if (bodies.length == 1) {
        return http.Response(
          jsonEncode({
            'error': {'message': "Unsupported parameter: 'reasoning_effort'"},
          }),
          400,
        );
      }
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': jsonEncode(_summaryJson())},
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final provider = OpenAiCompatibleUnreadSummaryProvider(
      serverBaseUri: Uri.parse('https://example.test'),
      model: 'deepseek-reasoner',
      httpClient: client,
      transientRetryDelays: const [],
    );

    final result = await provider.complete(_request());

    expect(bodies, hasLength(2));
    expect(bodies.first['reasoning_effort'], 'low');
    expect(bodies.last, isNot(contains('reasoning_effort')));
    expect(result['overview'], '要点');
  });

  test('extracts summary JSON after reasoning text', () async {
    final summary = jsonEncode(_summaryJson());
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': '<think>{"scratch":true}</think>\n$summary\nDone.',
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final provider = OpenAiCompatibleUnreadSummaryProvider(
      serverBaseUri: Uri.parse('https://example.test'),
      model: 'reasoning-model',
      httpClient: client,
    );

    final result = await provider.complete(_request());

    expect(result['overview'], '要点');
    expect(result, isNot(contains('scratch')));
  });

  test(
    'parses fenced JSON assembled from content parts without a key',
    () async {
      late http.Request captured;
      final summary = jsonEncode(_summaryJson());
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': [
                    {'type': 'text', 'text': '```json\n'},
                    {'type': 'text', 'text': summary.substring(0, 20)},
                    {
                      'type': 'text',
                      'text': {'value': '${summary.substring(20)}\n```'},
                    },
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final provider = OpenAiCompatibleUnreadSummaryProvider(
        serverBaseUri: Uri.parse('https://example.test/v1'),
        model: 'local-model',
        httpClient: client,
      );

      final result = await provider.complete(_request());

      expect(captured.url.path, '/v1/chat/completions');
      expect(captured.headers, isNot(contains('authorization')));
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body, isNot(contains('response_format')));
      expect(result['overview_evidence_ids'], ['m1']);
    },
  );

  test('surfaces an OpenAI-compatible error message', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'error': {'message': 'model is unavailable'},
        }),
        503,
      ),
    );
    final provider = OpenAiCompatibleUnreadSummaryProvider(
      serverBaseUri: Uri.parse('https://example.test'),
      model: 'missing-model',
      httpClient: client,
      transientRetryDelays: const [],
    );

    expect(
      provider.complete(_request()),
      throwsA(
        isA<UnreadChatSummaryProviderException>()
            .having((error) => error.statusCode, 'statusCode', 503)
            .having(
              (error) => error.message,
              'message',
              'model is unavailable',
            ),
      ),
    );
  });

  test('retries a rate-limited server response', () async {
    var attempts = 0;
    final client = MockClient((_) async {
      attempts++;
      if (attempts == 1) {
        return http.Response(
          jsonEncode({
            'error': {'message': 'slow down'},
          }),
          429,
          headers: {'retry-after': '0'},
        );
      }
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': jsonEncode(_summaryJson())},
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final provider = OpenAiCompatibleUnreadSummaryProvider(
      serverBaseUri: Uri.parse('https://example.test'),
      model: 'test-model',
      httpClient: client,
      transientRetryDelays: const [Duration.zero],
    );

    final result = await provider.complete(_request());

    expect(attempts, 2);
    expect(result['overview'], '要点');
  });

  test('does not retry a timed-out completion', () async {
    final client = _HangingClient();
    final provider = OpenAiCompatibleUnreadSummaryProvider(
      serverBaseUri: Uri.parse('https://example.test'),
      model: 'slow-model',
      httpClient: client,
      requestTimeout: const Duration(milliseconds: 5),
      transientRetryDelays: const [Duration.zero, Duration.zero],
    );

    await expectLater(
      provider.complete(_request()),
      throwsA(
        isA<UnreadChatSummaryProviderException>().having(
          (error) => error.message,
          'message',
          contains('did not start'),
        ),
      ),
    );
    expect(client.attempts, 1);
  });
}

class _HangingClient extends http.BaseClient {
  int attempts = 0;
  final _response = Completer<http.StreamedResponse>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    attempts++;
    return _response.future;
  }
}

class _ControlledStreamingClient extends http.BaseClient {
  final requestReceived = Completer<void>();
  final _controller = StreamController<List<int>>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!requestReceived.isCompleted) requestReceived.complete();
    return http.StreamedResponse(
      _controller.stream,
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }

  void addEvent(String content) {
    _controller.add(
      utf8.encode(
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': content},
            },
          ],
        })}\n\n',
      ),
    );
  }

  void finish() {
    _controller.add(utf8.encode('data: [DONE]\n\n'));
    unawaited(_controller.close());
  }

  @override
  void close() {
    unawaited(_controller.close());
    super.close();
  }
}
