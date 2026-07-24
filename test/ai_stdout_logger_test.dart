import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/telegram_ai_service.dart';
import 'package:mithka/settings/ai_stdout_logger.dart';
import 'package:mithka/settings/apple_pcc_api.dart';

void main() {
  test('writes complete correlated JSON lines and redacts credentials', () {
    final lines = <String>[];
    const configuredSecret = 'configured-secret-value';
    final logger = AiStdoutLogger(
      sink: lines.add,
      secrets: const [configuredSecret],
    );
    final correlationId = logger.newCorrelationId('test provider');
    final credentialFields = <String, String>{
      'Authorization': 'Bearer auth-value',
      'x-api-key': 'header-key-value',
      'api_key': 'body-key-value',
      'access_token': 'access-value',
      'refresh_token': 'refresh-value',
      'id_token': 'id-value',
      'client_secret': 'client-value',
      'password': 'password-value',
      'cookie': 'cookie-value',
      'set-cookie': 'set-cookie-value',
    };

    logger.request(
      correlationId: correlationId,
      provider: 'test',
      operation: 'complete',
      payload: {
        'prompt': 'Full prompt\nwith $configuredSecret embedded',
        configuredSecret: 'secret used as a map key',
        'credentials': credentialFields,
      },
    );
    logger.response(
      correlationId: correlationId,
      provider: 'test',
      operation: 'complete',
      result: {
        'text': 'Full result with event-secret-value',
        'nested': [1, true, null],
      },
      secrets: const ['event-secret-value'],
    );
    logger.error(
      correlationId: correlationId,
      provider: 'test',
      operation: 'complete',
      error: StateError('failed with $configuredSecret'),
      payload: {'prompt': 'Full prompt'},
      stackTrace: StackTrace.fromString('trace containing $configuredSecret'),
    );

    expect(lines, hasLength(3));
    expect(lines, everyElement(isNot(contains('\n'))));
    expect(lines.join(), isNot(contains(configuredSecret)));
    expect(lines.join(), isNot(contains('event-secret-value')));
    for (final value in credentialFields.values) {
      expect(lines.join(), isNot(contains(value)));
    }

    final events = _decode(lines);
    expect(events.map((event) => event['event']), [
      'ai.request',
      'ai.response',
      'ai.error',
    ]);
    expect(events.map((event) => event['correlation_id']).toSet(), {
      correlationId,
    });
    expect(
      (events.first['payload'] as Map)['prompt'],
      'Full prompt\nwith [REDACTED] embedded',
    );
    expect(
      (events.first['payload'] as Map)['[REDACTED]'],
      'secret used as a map key',
    );
    final redactedCredentials =
        (events.first['payload'] as Map)['credentials'] as Map;
    expect(redactedCredentials.values, everyElement('[REDACTED]'));
    expect((events[1]['result'] as Map)['text'], 'Full result with [REDACTED]');
    expect(
      ((events[2]['error'] as Map)['message'] as String),
      isNot(contains(configuredSecret)),
    );
  });

  test('Telegram AI logs the full TDLib request and response', () async {
    final lines = <String>[];
    final logger = AiStdoutLogger(sink: lines.add);
    final service = TelegramAiService(
      aiLogger: logger,
      queryOverride: (request) async => {
        '@type': 'formattedText',
        'text': 'Full Telegram result',
        'entities': <Map<String, dynamic>>[],
      },
    );
    addTearDown(service.dispose);

    final result = await service.fix(
      const TelegramAiFormattedText(text: 'Full Telegram prompt'),
    );

    expect(result.text, 'Full Telegram result');
    final events = _decode(lines);
    expect(events.map((event) => event['event']), [
      'ai.request',
      'ai.response',
    ]);
    expect(events.first['provider'], 'telegram_cocoon');
    expect(events.first['operation'], 'fixTextWithAi');
    expect(
      (((events.first['payload'] as Map)['text'] as Map)['text']),
      'Full Telegram prompt',
    );
    expect((events.last['result'] as Map)['text'], 'Full Telegram result');
    expect(events.first['correlation_id'], events.last['correlation_id']);
  });

  test(
    'Telegram AI logs provider errors with the request correlation',
    () async {
      final lines = <String>[];
      final logger = AiStdoutLogger(sink: lines.add);
      final service = TelegramAiService(
        aiLogger: logger,
        queryOverride: (_) async => throw StateError('TDLib AI failed'),
      );
      addTearDown(service.dispose);

      await expectLater(
        service.fix(const TelegramAiFormattedText(text: 'Keep this prompt')),
        throwsStateError,
      );

      final events = _decode(lines);
      expect(events.map((event) => event['event']), ['ai.request', 'ai.error']);
      expect(events.first['correlation_id'], events.last['correlation_id']);
      expect(
        (((events.last['payload'] as Map)['text'] as Map)['text']),
        'Keep this prompt',
      );
      expect(
        ((events.last['error'] as Map)['message'] as String),
        contains('TDLib AI failed'),
      );
    },
  );

  test('Apple AI logs full native summarize payloads and results', () async {
    final lines = <String>[];
    final logger = AiStdoutLogger(sink: lines.add);
    final api = ApplePccApi(
      aiLogger: logger,
      invokeMethod: (method, arguments) async {
        expect(method, 'summarize');
        return {
          'text': 'Full Apple result',
          'provider': 'apple_pcc',
          'responseTokenCount': 17,
        };
      },
    );

    final result = await api.summarize(
      prompt: 'Full Apple prompt',
      instructions: 'Full Apple instructions',
    );

    expect(result.text, 'Full Apple result');
    final events = _decode(lines);
    expect(events.map((event) => event['event']), [
      'ai.request',
      'ai.response',
    ]);
    expect(events.first['provider'], 'private_cloud_compute');
    expect(events.first['operation'], 'summarize');
    expect((events.first['payload'] as Map)['prompt'], 'Full Apple prompt');
    expect(
      (events.first['payload'] as Map)['instructions'],
      'Full Apple instructions',
    );
    expect((events.last['result'] as Map)['text'], 'Full Apple result');
    expect(events.first['correlation_id'], events.last['correlation_id']);
  });

  test('Apple AI logs native errors with the request correlation', () async {
    final lines = <String>[];
    final logger = AiStdoutLogger(sink: lines.add);
    final api = ApplePccApi(
      aiLogger: logger,
      invokeMethod: (_, _) async => throw PlatformException(
        code: 'generation_failed',
        message: 'Native AI failed',
      ),
    );

    await expectLater(
      api.summarize(prompt: 'Preserved Apple prompt'),
      throwsA(isA<PlatformException>()),
    );

    final events = _decode(lines);
    expect(events.map((event) => event['event']), ['ai.request', 'ai.error']);
    expect(events.first['correlation_id'], events.last['correlation_id']);
    expect((events.last['payload'] as Map)['prompt'], 'Preserved Apple prompt');
    expect(
      ((events.last['error'] as Map)['message'] as String),
      contains('Native AI failed'),
    );
  });
}

List<Map<String, dynamic>> _decode(List<String> lines) => [
  for (final line in lines) Map<String, dynamic>.from(jsonDecode(line) as Map),
];
