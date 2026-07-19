import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/apple_pcc_api.dart';

void main() {
  test('capabilities parses the native camelCase response', () async {
    final reset = DateTime(2026, 7, 21).millisecondsSinceEpoch;
    final api = ApplePccApi(
      invokeMethod: (method, arguments) async {
        expect(method, 'getCapabilities');
        expect(arguments, isNull);
        return {
          'sdkAvailable': true,
          'available': true,
          'reason': '',
          'contextSize': 32768,
          'quotaLimitReached': false,
          'quotaApproachingLimit': true,
          'quotaResetDateMillis': reset,
        };
      },
    );

    final capabilities = await api.capabilities();

    expect(capabilities.sdkAvailable, isTrue);
    expect(capabilities.available, isTrue);
    expect(capabilities.reason, isEmpty);
    expect(capabilities.contextSize, 32768);
    expect(capabilities.quotaLimitReached, isFalse);
    expect(capabilities.quotaApproachingLimit, isTrue);
    expect(capabilities.quotaResetDate?.millisecondsSinceEpoch, reset);
  });

  test(
    'capability probe converts platform failures to unavailable state',
    () async {
      final api = ApplePccApi(
        invokeMethod: (_, _) async => throw PlatformException(
          code: 'requires_xcode_27',
          message: 'Unavailable in this SDK',
        ),
      );

      final capabilities = await api.capabilities();

      expect(capabilities.available, isFalse);
      expect(capabilities.reason, 'requires_xcode_27');
    },
  );

  test(
    'capability probe handles missing plugin and malformed response',
    () async {
      final missing = ApplePccApi(
        invokeMethod: (_, _) async => throw MissingPluginException(),
      );
      final malformed = ApplePccApi(invokeMethod: (_, _) async => {'value': 1});

      expect((await missing.capabilities()).reason, 'missing_plugin');
      expect((await malformed.capabilities()).reason, 'invalid_response');
    },
  );

  test('capability probe times out as unavailable', () async {
    final api = ApplePccApi(
      timeout: Duration.zero,
      invokeMethod: (_, _) => Completer<Object?>().future,
    );

    final capabilities = await api.capabilities();

    expect(capabilities.available, isFalse);
    expect(capabilities.reason, 'timeout');
  });

  test('summarize sends the native contract and parses its result', () async {
    final api = ApplePccApi(
      invokeMethod: (method, arguments) async {
        expect(method, 'summarize');
        expect(arguments, {
          'prompt': 'Summarize these messages',
          'instructions': 'Reply in the same language',
          'reasoningLevel': 'deep',
          'maximumResponseTokens': 500,
        });
        return {'text': 'Summary text', 'provider': 'apple_pcc'};
      },
    );

    final result = await api.summarize(
      prompt: ' Summarize these messages ',
      instructions: ' Reply in the same language ',
      reasoningLevel: ApplePccReasoningLevel.deep,
      maximumResponseTokens: 500,
    );

    expect(result.text, 'Summary text');
    expect(result.provider, 'apple_pcc');
  });

  test('summarize rejects empty input and malformed responses', () async {
    final api = ApplePccApi(invokeMethod: (_, _) async => {'provider': 'x'});

    expect(() => api.summarize(prompt: '   '), throwsA(isA<ArgumentError>()));
    expect(
      () => api.summarize(prompt: 'valid'),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'pcc_invalid_response',
        ),
      ),
    );
  });
}
