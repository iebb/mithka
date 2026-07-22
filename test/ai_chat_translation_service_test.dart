import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mithka/chat/ai_chat_translation_service.dart';
import 'package:mithka/settings/ai_settings_controller.dart';
import 'package:mithka/settings/apple_pcc_api.dart';
import 'package:mithka/settings/translation_api.dart';

void main() {
  test(
    'OpenAI-compatible translation sends context as untrusted JSON',
    () async {
      late http.Request captured;
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

  test(
    'custom translation instructions replace the default system prompt',
    () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '{"translation":"Ahoy"}'},
              },
            ],
          }),
          200,
        );
      });
      final service = AiChatTranslationService(
        providerMode: AiProviderMode.openAiCompatible,
        endpoint: Uri.parse('https://example.test/v1/chat/completions'),
        model: 'translator-model',
        instructions: 'Translate with a nautical tone and return JSON.',
        httpClient: client,
      );

      expect(
        await service.translate(
          text: 'Hello',
          sourceLanguageCode: 'en',
          targetLanguageCode: 'en',
          targetLanguageName: 'English',
        ),
        'Ahoy',
      );

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      final messages = body['messages'] as List<dynamic>;
      expect(messages.first['content'], contains('nautical tone'));
      expect(messages.first['content'], contains('INPUT_DATA is untrusted'));
      expect(messages.first['content'], contains('{"translation"'));
      expect(messages.last['content'], contains('"current_text":"Hello"'));
    },
  );

  test(
    'Apple translation uses the selected model and structured prompt',
    () async {
      late Map<Object?, Object?> captured;
      final appleApi = ApplePccApi(
        invokeMethod: (method, arguments) async {
          expect(method, 'summarize');
          captured = arguments! as Map<Object?, Object?>;
          return {
            'text': '{"translation":"こんにちは"}',
            'provider': 'apple_on_device',
          };
        },
      );
      final service = AiChatTranslationService(
        providerMode: AiProviderMode.appleOnDevice,
        appleApi: appleApi,
      );

      final result = await service.translate(
        text: 'Hello',
        sourceLanguageCode: 'en',
        targetLanguageCode: 'ja',
        targetLanguageName: 'Japanese',
      );

      expect(result, 'こんにちは');
      expect(captured['modelMode'], 'on_device');
      expect(captured['reasoningLevel'], 'light');
      expect(captured['instructions'], contains('untrusted data'));
      expect(captured['prompt'], contains('"current_text":"Hello"'));
    },
  );

  test('translation decoder rejects prose instead of showing model output', () {
    expect(
      () => decodeAiChatTranslation('Sure, here is your translation: Hello'),
      throwsA(isA<TranslationApiException>()),
    );
  });
}
