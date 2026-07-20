import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/apple_pcc_unread_summary_provider.dart';
import 'package:mithka/chat/unread_chat_summary_service.dart';
import 'package:mithka/settings/apple_pcc_api.dart';

Map<String, dynamic> _summaryJson() => {
  'overview': '同じ言語の要約',
  'overview_evidence_ids': ['m1'],
  'highlights': [
    {
      'text': '同じ言語の要約',
      'evidence_ids': ['m1'],
    },
  ],
  'needs_reply': <Map<String, dynamic>>[],
  'decisions': <Map<String, dynamic>>[],
  'actions': <Map<String, dynamic>>[],
  'questions': <Map<String, dynamic>>[],
  'uncertainties': <Map<String, dynamic>>[],
};

UnreadChatSummaryProviderRequest _request({
  UnreadChatSummaryStage stage = UnreadChatSummaryStage.chunk,
}) => UnreadChatSummaryProviderRequest(
  stage: stage,
  trustedInstructions: unreadChatSummaryTrustedInstructions,
  payload: {
    'stage': 'summarize_chunk',
    'output_language': 'zh-Hans',
    'messages': [
      {'evidence_id': 'm1', 'text': 'こんにちは'},
    ],
  },
  allowedEvidenceIds: const {'m1'},
);

void main() {
  test(
    'adapts the trusted request to ApplePccApi and parses fenced JSON',
    () async {
      late Map<String, Object?> captured;
      final api = ApplePccApi(
        invokeMethod: (method, arguments) async {
          expect(method, 'summarize');
          captured = Map<String, Object?>.from(arguments! as Map);
          return {
            'text': '```json\n${jsonEncode(_summaryJson())}\n```',
            'provider': 'apple_pcc',
          };
        },
      );
      final provider = ApplePccUnreadSummaryProvider(
        api: api,
        reasoningLevel: ApplePccReasoningLevel.deep,
        maximumResponseTokens: 700,
      );

      final result = await provider.complete(_request());

      expect(captured['reasoningLevel'], 'deep');
      expect(captured['maximumResponseTokens'], 700);
      expect(
        captured['instructions'],
        contains('UI language identified by INPUT_DATA.output_language'),
      );
      expect(captured['prompt'], contains('"output_language":"zh-Hans"'));
      expect(result['overview'], '同じ言語の要約');
    },
  );

  test('rejects a non-JSON PCC completion', () async {
    final provider = ApplePccUnreadSummaryProvider(
      api: ApplePccApi(
        invokeMethod: (_, _) async => {
          'text': 'not structured JSON',
          'provider': 'apple_pcc',
        },
      ),
    );

    expect(
      provider.complete(_request()),
      throwsA(isA<UnreadChatSummaryProviderException>()),
    );
  });

  test(
    'uses smaller chunk output and larger final merge output limits',
    () async {
      final capturedLimits = <Object?>[];
      final provider = ApplePccUnreadSummaryProvider(
        api: ApplePccApi(
          invokeMethod: (_, arguments) async {
            capturedLimits.add((arguments! as Map)['maximumResponseTokens']);
            return {
              'text': jsonEncode(_summaryJson()),
              'provider': 'apple_pcc',
            };
          },
        ),
        chunkMaximumResponseTokens: 700,
        mergeMaximumResponseTokens: 1300,
      );

      await provider.complete(_request());
      await provider.complete(_request(stage: UnreadChatSummaryStage.merge));

      expect(capturedLimits, [700, 1300]);
    },
  );

  test('retries transient PCC service failures', () async {
    var attempts = 0;
    final provider = ApplePccUnreadSummaryProvider(
      api: ApplePccApi(
        invokeMethod: (_, _) async {
          attempts++;
          if (attempts == 1) {
            throw PlatformException(
              code: 'pcc_service_unavailable',
              message: 'Try again',
            );
          }
          return {'text': jsonEncode(_summaryJson()), 'provider': 'apple_pcc'};
        },
      ),
      transientRetryDelays: const [Duration.zero],
    );

    final result = await provider.complete(_request());

    expect(attempts, 2);
    expect(result['overview'], '同じ言語の要約');
  });

  test('does not retry a PCC quota failure', () async {
    var attempts = 0;
    final provider = ApplePccUnreadSummaryProvider(
      api: ApplePccApi(
        invokeMethod: (_, _) async {
          attempts++;
          throw PlatformException(
            code: 'pcc_quota_reached',
            message: 'Quota reached',
          );
        },
      ),
      transientRetryDelays: const [Duration.zero, Duration.zero],
    );

    await expectLater(
      provider.complete(_request()),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'pcc_quota_reached',
        ),
      ),
    );
    expect(attempts, 1);
  });

  test('does not duplicate a timed-out native PCC request', () async {
    var attempts = 0;
    final provider = ApplePccUnreadSummaryProvider(
      api: ApplePccApi(
        invokeMethod: (_, _) async {
          attempts++;
          throw PlatformException(code: 'pcc_timeout', message: 'Timed out');
        },
      ),
      transientRetryDelays: const [Duration.zero, Duration.zero],
    );

    await expectLater(
      provider.complete(_request()),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'pcc_timeout',
        ),
      ),
    );
    expect(attempts, 1);
  });
}
