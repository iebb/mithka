import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mithka/chat/openai_compatible_unread_summary_provider.dart';
import 'package:mithka/chat/unread_chat_summary_service.dart';

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
    'output_language': 'same_as_chat',
    'messages': [
      {'evidence_id': 'm1', 'text': '你好'},
    ],
  },
  allowedEvidenceIds: const {'m1'},
);

void main() {
  test('posts a nonstreaming authenticated chat completion', () async {
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
    expect(body['stream'], isFalse);
    expect(body.containsKey('response_format'), isFalse);
    final messages = body['messages'] as List<dynamic>;
    expect(messages.first['role'], 'system');
    expect(
      messages.first['content'],
      contains('same language or languages used by the chat messages'),
    );
    expect(
      messages.last['content'],
      contains('"output_language":"same_as_chat"'),
    );
    expect(result['overview'], '要点');
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
}
