import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mithka/platform/air_feedback.dart';
import 'package:mithka/settings/feedback_report_dispatch.dart';

const _info = AirFeedbackDeviceInfo(
  appVersion: '1.12.8',
  appBuild: '412',
  deviceModel: 'iPhone17,2',
  osVersion: 'iOS 26.1',
  locale: 'en_US',
);

AirFeedbackClient _client(
  MockClientHandler handler, {
  Duration timeout = const Duration(seconds: 10),
}) => AirFeedbackClient(
  httpClient: MockClient(handler),
  endpoint: Uri.parse('https://apps.example/v1/ingest/feedback'),
  appKey: 'ak_test_key',
  deviceInfo: () async => _info,
  timeout: timeout,
);

void main() {
  group('AirFeedbackClient', () {
    test('posts the AppFeedback.swift JSON shape with the app key', () async {
      late http.Request sent;
      final client = _client((request) async {
        sent = request;
        return http.Response(
          jsonEncode({'id': '1b9eba2d-7cf0-4e6c-bd2c-0c8e15220c30'}),
          201,
        );
      });

      final id = await client.send('Hello there');

      expect(id, '1b9eba2d-7cf0-4e6c-bd2c-0c8e15220c30');
      expect(sent.method, 'POST');
      expect(sent.url.toString(), 'https://apps.example/v1/ingest/feedback');
      expect(sent.headers['Authorization'], 'Bearer ak_test_key');
      expect(sent.headers['Content-Type'], startsWith('application/json'));
      expect(sent.headers.keys, isNot(contains('X-Attest-Key-Id')));
      expect(jsonDecode(sent.body), {
        'message': 'Hello there',
        'appVersion': '1.12.8',
        'appBuild': '412',
        'deviceModel': 'iPhone17,2',
        'osVersion': 'iOS 26.1',
        'locale': 'en_US',
        'images': <Object>[],
      });
    });

    test('ships the production endpoint and public ingest key', () {
      final client = AirFeedbackClient();
      expect(
        client.endpoint.toString(),
        'https://apps.air.build/v1/ingest/feedback',
      );
      expect(client.appKey, startsWith('ak_production_'));
    });

    test('keeps the message within the ingest limit', () {
      final long = '${'a' * 3999}😀${'b' * 10}';
      final body = AirFeedbackClient.requestBody(long, _info);
      final message = body['message']! as String;
      expect(message.length, 3999);
      expect(message, 'a' * 3999);
      expect(AirFeedbackClient.requestBody('short', _info)['message'], 'short');
    });

    test('accepts a success without an id', () async {
      final client = _client((_) async => http.Response('', 202));
      expect(await client.send('Hi'), isNull);
    });

    test('reports the server reason on refusal', () async {
      final client = _client(
        (_) async => http.Response(jsonEncode({'reason': 'Too long.'}), 413),
      );
      await expectLater(
        client.send('Hi'),
        throwsA(
          isA<AirFeedbackException>()
              .having((e) => e.message, 'message', 'Too long.')
              .having((e) => e.statusCode, 'statusCode', 413),
        ),
      );
    });

    test('gives up after its timeout', () async {
      final never = Completer<http.Response>();
      final client = _client(
        (_) => never.future,
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(client.send('Hi'), throwsA(isA<TimeoutException>()));
    });
  });

  group('sendFeedbackReport', () {
    test('both succeed: shows the Sentry id', () async {
      final outcome = await sendFeedbackReport(
        sentry: () async => '0123456789abcdef0123456789abcdef',
        airFeedback: () async => 'ffffffff-0000',
      );
      expect(outcome.sent, isTrue);
      expect(outcome.displayId, '01234567');
    });

    test('only Sentry succeeds: sent', () async {
      final outcome = await sendFeedbackReport(
        sentry: () async => '0123456789abcdef0123456789abcdef',
        airFeedback: () async => throw const AirFeedbackException('down'),
      );
      expect(outcome.sent, isTrue);
      expect(outcome.airFeedbackSent, isFalse);
      expect(outcome.displayId, '01234567');
    });

    test('only AirFeedback succeeds: sent with its id', () async {
      final outcome = await sendFeedbackReport(
        sentry: () async => null,
        airFeedback: () async => '1b9eba2d-7cf0-4e6c-bd2c-0c8e15220c30',
      );
      expect(outcome.sent, isTrue);
      expect(outcome.displayId, '1b9eba2d');
    });

    test('Sentry throws, AirFeedback succeeds without id: sent', () async {
      final outcome = await sendFeedbackReport(
        sentry: () async => throw StateError('no sentry'),
        airFeedback: () async => null,
      );
      expect(outcome.sent, isTrue);
      expect(outcome.displayId, isNull);
    });

    test('both fail: not sent', () async {
      final outcome = await sendFeedbackReport(
        sentry: () async => null,
        airFeedback: () async => throw const AirFeedbackException('down'),
      );
      expect(outcome.sent, isFalse);
    });

    test('a hanging AirFeedback does not hold the form', () async {
      final watch = Stopwatch()..start();
      final outcome = await sendFeedbackReport(
        sentry: () async => '0123456789abcdef0123456789abcdef',
        airFeedback: () => Completer<String?>().future,
        airFeedbackTimeout: const Duration(milliseconds: 50),
      );
      expect(outcome.sent, isTrue);
      expect(outcome.airFeedbackSent, isFalse);
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('both are started before either finishes', () async {
      final sentryGate = Completer<String?>();
      var airStarted = false;
      final pending = sendFeedbackReport(
        sentry: () => sentryGate.future,
        airFeedback: () async {
          airStarted = true;
          return 'air';
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(airStarted, isTrue);
      sentryGate.complete(null);
      expect((await pending).displayId, 'air');
    });
  });
}
