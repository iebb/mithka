import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mithka/settings/openai_compatible_models_api.dart';

void main() {
  test(
    'derives /v1/models, authenticates, and parses model metadata',
    () async {
      late http.Request captured;
      final api = OpenAiCompatibleModelsApi(
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'z-model'},
                {'id': 'a-model', 'context_length': 32768},
                {
                  'id': 'nested-model',
                  'limits': {'context_window': '131072'},
                },
                {'id': 'camel-model', 'contextWindowTokens': 200000},
                {'id': 'a-model', 'context_length': 65536},
              ],
            }),
            200,
          );
        }),
      );

      final models = await api.listModels(
        chatCompletionsUri: Uri.parse(
          'https://ai.example/custom/v1/chat/completions',
        ),
        apiKey: ' secret ',
      );

      expect(captured.url.toString(), 'https://ai.example/custom/v1/models');
      expect(captured.headers['authorization'], 'Bearer secret');
      expect(models.map((model) => model.id), [
        'a-model',
        'camel-model',
        'nested-model',
        'z-model',
      ]);
      expect(models.first.contextWindowTokens, 65536);
      expect(models[1].contextWindowTokens, 200000);
      expect(models[2].contextWindowTokens, 131072);
      expect(models.last.contextWindowTokens, isNull);
    },
  );

  test('allows keyless model discovery', () async {
    late http.Request captured;
    final api = OpenAiCompatibleModelsApi(
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'data': []}), 200);
      }),
    );

    expect(
      await api.listModels(
        chatCompletionsUri: Uri.parse(
          'http://127.0.0.1:11434/v1/chat/completions',
        ),
      ),
      isEmpty,
    );
    expect(captured.headers, isNot(contains('authorization')));
  });

  test('retrieves context metadata from a per-model detail resource', () async {
    late http.Request captured;
    final api = OpenAiCompatibleModelsApi(
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'id': 'vendor/model',
            'capabilities': {'maxInputTokens': 262144},
          }),
          200,
        );
      }),
    );

    final model = await api.retrieveModel(
      chatCompletionsUri: Uri.parse(
        'https://ai.example/custom/v1/chat/completions',
      ),
      modelId: 'vendor/model',
      apiKey: 'secret',
    );

    expect(captured.url.pathSegments.last, 'vendor/model');
    expect(captured.headers['authorization'], 'Bearer secret');
    expect(model?.id, 'vendor/model');
    expect(model?.contextWindowTokens, 262144);
  });

  test('treats an unsupported per-model detail endpoint as optional', () async {
    final api = OpenAiCompatibleModelsApi(
      httpClient: MockClient((_) async => http.Response('', 404)),
    );

    expect(
      await api.retrieveModel(
        chatCompletionsUri: Uri.parse('https://ai.example/v1/chat/completions'),
        modelId: 'model',
      ),
      isNull,
    );
  });

  test('surfaces server model-list errors', () async {
    final api = OpenAiCompatibleModelsApi(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'message': 'invalid key'},
          }),
          401,
        ),
      ),
    );

    await expectLater(
      api.listModels(
        chatCompletionsUri: Uri.parse('https://ai.example/v1/chat/completions'),
      ),
      throwsA(
        isA<OpenAiCompatibleModelsException>()
            .having((error) => error.statusCode, 'status', 401)
            .having((error) => error.message, 'message', 'invalid key'),
      ),
    );
  });
}
