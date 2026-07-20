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
          'onDeviceSdkAvailable': true,
          'onDeviceAvailable': true,
          'onDeviceReason': 'available',
          'onDeviceContextSize': 4096,
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
    expect(capabilities.onDeviceSdkAvailable, isTrue);
    expect(capabilities.onDeviceAvailable, isTrue);
    expect(capabilities.onDeviceReason, 'available');
    expect(capabilities.onDeviceContextSize, 4096);
    expect(capabilities.contextSizeFor(AppleAiModel.onDevice), 4096);
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
        expect(arguments, isA<Map<String, Object>>());
        final values = Map<String, Object>.from(arguments! as Map);
        expect(values.remove('requestId'), isA<String>());
        expect(values, {
          'prompt': 'Summarize these messages',
          'instructions': 'Reply in the same language',
          'modelMode': 'private_cloud_compute',
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

  test(
    'summarize selects the on-device model in the native contract',
    () async {
      final api = ApplePccApi(
        invokeMethod: (method, arguments) async {
          expect(method, 'summarize');
          expect((arguments! as Map)['modelMode'], 'on_device');
          return {
            'text': '本机总结',
            'provider': 'apple_on_device',
            'contextSize': 4096,
            'inputTokenCount': 512,
            'responseTokenCount': 40,
          };
        },
      );

      final result = await api.summarize(
        prompt: '总结',
        model: AppleAiModel.onDevice,
      );

      expect(result.provider, 'apple_on_device');
      expect(result.contextSize, 4096);
      expect(result.inputTokenCount, 512);
      expect(result.responseTokenCount, 40);
    },
  );

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

  test('summarize cancels the native request after a timeout', () async {
    final methods = <String>[];
    final api = ApplePccApi(
      summaryTimeout: Duration.zero,
      invokeMethod: (method, _) {
        methods.add(method);
        if (method == 'summarize') return Completer<Object?>().future;
        return Future<Object?>.value();
      },
    );

    await expectLater(
      api.summarize(prompt: 'valid'),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'pcc_timeout',
        ),
      ),
    );
    expect(methods, ['summarize', 'cancelSummary']);
  });
}
