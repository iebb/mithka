import 'dart:convert';

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

UnreadChatSummaryProviderRequest _request() => UnreadChatSummaryProviderRequest(
  stage: UnreadChatSummaryStage.chunk,
  trustedInstructions: unreadChatSummaryTrustedInstructions,
  payload: {
    'stage': 'summarize_chunk',
    'output_language': 'same_as_chat',
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
        contains('same language or languages used by the chat messages'),
      );
      expect(captured['prompt'], contains('"output_language":"same_as_chat"'));
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
}
