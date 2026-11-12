import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mithka/chat/ai_chat_translation_service.dart';
import 'package:mithka/settings/ai_settings_controller.dart';
import 'package:mithka/settings/ai_stdout_logger.dart';
import 'package:mithka/settings/translation_api.dart';

void main() {
  test(
    'OpenAI-compatible translation sends context as untrusted JSON',
    () async {
      late http.Request captured;
      final logLines = <String>[];
      final client = MockClient((request) async {
        captured = request;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({'translation': 'Bis später 👋'}),
                  },
                },
              ],
            }),
          ),
          200,
        );
      });
      final service = AiChatTranslationService(
        providerMode: AiProviderMode.openAiCompatible,
        endpoint: Uri.parse('https://example.test/v1/chat/completions'),
        model: 'translator-model',
        apiKey: 'secret',
        httpClient: client,
        aiLogger: AiStdoutLogger(
          sink: logLines.add,
          contentPolicy: AiLogContentPolicy.fullContent,
        ),
      );

      final result = await service.translate(
        text: 'See you later 👋',
        sourceLanguageCode: 'en',
        targetLanguageCode: 'de',
        targetLanguageName: 'German',
        priorMessages: const ['The meeting is finished.'],
      );

      expect(result, 'Bis später 👋');
      expect(captured.headers['authorization'], 'Bearer secret');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['stream'], isFalse);
      expect(body['response_format'], {'type': 'json_object'});
      final messages = body['messages'] as List<dynamic>;
      expect(messages.first['content'], contains('Do not answer'));
      expect(messages.last['content'], contains('"prior_messages"'));
      expect(messages.last['content'], contains('See you later'));
      final logEvents = logLines
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList();
      expect(logEvents.map((event) => event['event']), [
        'ai.request',
        'ai.response',
      ]);
      expect(
        ((logEvents.first['payload'] as Map)['body'] as Map)['messages'],
        isNotEmpty,
      );
      expect((logEvents.last['result'] as Map)['body'], contains('Bis später'));
      expect(logLines.join(), isNot(contains('secret')));
    },
  );

  test('custom provider retries without unsupported response_format', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body.containsKey('response_format')) {
        return http.Response(
          jsonEncode({
            'error': {'message': 'unsupported response_format'},
          }),
          400,
        );
      }
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': '```json\n{"translation":"Bonjour"}\n```'},
            },
          ],
        }),
        200,
      );
    });
    final service = AiChatTranslationService(
      providerMode: AiProviderMode.openAiCompatible,
      endpoint: Uri.parse('https://example.test/v1/chat/completions'),
      model: 'compatible-model',
      httpClient: client,
    );

    final result = await service.translate(
      text: 'Hello',
      sourceLanguageCode: 'en',
      targetLanguageCode: 'fr',
      targetLanguageName: 'French',
    );

    expect(result, 'Bonjour');
    expect(requests, 2);
  });

  test('translation decoder rejects prose instead of showing model output', () {
    expect(
      () => decodeAiChatTranslation('Sure, here is your translation: Hello'),
      throwsA(isA<TranslationApiException>()),
    );
  });
}
