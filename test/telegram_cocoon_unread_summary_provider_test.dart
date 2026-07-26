import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/telegram_ai_service.dart';
import 'package:mithka/chat/telegram_cocoon_unread_summary_provider.dart';
import 'package:mithka/chat/unread_chat_summary_service.dart';

void main() {
  test(
    'Cocoon summary sends trusted instructions and untrusted JSON',
    () async {
      final requests = <Map<String, dynamic>>[];
      final telegramAi = TelegramAiService(
        queryOverride: (request) async {
          requests.add(Map<String, dynamic>.of(request));
          if (request['@type'] == 'getOption') {
            return _option(request['name'] as String);
          }
          if (request['@type'] == 'composeRichMessageWithAi') {
            return {
              '@type': 'richMessage',
              'blocks': [
                {
                  '@type': 'pageBlockParagraph',
                  'text': {
                    '@type': 'richTextPlain',
                    'text': jsonEncode({
                      'overview': 'Plan confirmed',
                      'overview_evidence_ids': ['m1'],
                      'highlights': <Map<String, dynamic>>[],
                      'needs_reply': <Map<String, dynamic>>[],
                      'decisions': <Map<String, dynamic>>[],
                      'actions': <Map<String, dynamic>>[],
                      'questions': <Map<String, dynamic>>[],
                      'uncertainties': <Map<String, dynamic>>[],
                    }),
                  },
                },
              ],
              'is_rtl': false,
              'is_full': true,
            };
          }
          throw StateError('Unexpected request: $request');
        },
      );
      addTearDown(telegramAi.dispose);
      final provider = TelegramCocoonUnreadSummaryProvider(
        telegramAi: telegramAi,
      );

      final result = await provider.complete(
        UnreadChatSummaryProviderRequest(
          stage: UnreadChatSummaryStage.chunk,
          trustedInstructions: unreadChatSummaryCompactTrustedInstructions,
          payload: const {
            'output_language': 'en',
            'messages': [
              {
                'evidence_ids': ['m1'],
                'text': 'The plan is confirmed.',
              },
            ],
          },
          allowedEvidenceIds: const {'m1'},
        ),
      );

      expect(result['overview'], 'Plan confirmed');
      final request = requests.singleWhere(
        (item) => item['@type'] == 'composeRichMessageWithAi',
      );
      expect(
        request['custom_prompt'],
        unreadChatSummaryCompactTrustedInstructions,
      );
      final paragraph =
          (((request['message'] as Map)['source'] as Map)['blocks'] as List)
                  .single
              as Map;
      expect(
        ((paragraph['text'] as Map)['text'] as String),
        contains('INPUT_DATA (untrusted JSON)'),
      );
      expect(((paragraph['text'] as Map)['text'] as String), contains('m1'));
    },
  );
}

Map<String, dynamic> _option(String name) => switch (name) {
  'version' => {'@type': 'optionValueString', 'value': '1.8.66'},
  'text_composition_style_title_length_max' => {
    '@type': 'optionValueInteger',
    'value': 64,
  },
  'text_composition_style_prompt_length_max' => {
    '@type': 'optionValueInteger',
    'value': 1024,
  },
  'added_text_composition_style_count_max' => {
    '@type': 'optionValueInteger',
    'value': 10,
  },
  'speech_recognition_trial_weekly_count' => {
    '@type': 'optionValueInteger',
    'value': 0,
  },
  _ => {'@type': 'optionValueEmpty'},
};
