import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/ai_stdout_logger.dart';

void main() {
  test('metadata-only logging never writes request, result, or error text', () {
    final lines = <String>[];
    final logger = AiStdoutLogger(sink: lines.add);
    const prompt = 'private prompt that must not reach stdout';
    const result = 'private result that must not reach stdout';
    const failure = 'private failure that must not reach stdout';

    logger.request(
      correlationId: 'metadata-1',
      provider: 'test',
      operation: 'complete',
      payload: const {
        'prompt': prompt,
        'messages': [prompt],
      },
    );
    logger.response(
      correlationId: 'metadata-1',
      provider: 'test',
      operation: 'complete',
      result: const {'text': result},
    );
    logger.error(
      correlationId: 'metadata-1',
      provider: 'test',
      operation: 'complete',
      error: StateError(failure),
      payload: const {'prompt': prompt},
      stackTrace: StackTrace.fromString('trace with $failure'),
    );

    final output = lines.join('\n');
    expect(output, isNot(contains(prompt)));
    expect(output, isNot(contains(result)));
    expect(output, isNot(contains(failure)));
    final events = _decode(lines);
    expect(events, hasLength(3));
    expect(events[0], isNot(contains('payload')));
    expect(events[0]['payload_metadata'], {'type': 'map', 'entry_count': 2});
    expect(events[1], isNot(contains('result')));
    expect(events[1]['result_metadata'], {'type': 'map', 'entry_count': 1});
    expect(events[2], isNot(contains('payload')));
    expect((events[2]['error'] as Map), {'type': 'StateError'});
  });

  test('explicit developer logging writes content and redacts credentials', () {
    final lines = <String>[];
    const configuredSecret = 'configured-secret-value';
    final logger = AiStdoutLogger(
      sink: lines.add,
      secrets: const [configuredSecret],
      contentPolicy: AiLogContentPolicy.fullContent,
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
}

List<Map<String, dynamic>> _decode(List<String> lines) => [
  for (final line in lines) Map<String, dynamic>.from(jsonDecode(line) as Map),
];
