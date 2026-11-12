import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/telegram_ai_service.dart';
import 'package:mithka/tdlib/td_client.dart';

void main() {
  test('AI reply preserves formatted entities returned by TDLib', () async {
    final requests = <Map<String, dynamic>>[];
    final service = TelegramAiService(
      queryOverride: (request) async {
        requests.add(Map<String, dynamic>.of(request));
        if (request['@type'] == 'getOption') {
          return _capabilityOption(
            request['name'] as String,
            version: '1.8.66',
          );
        }
        if (request['@type'] == 'composeRichMessageWithAi') {
          return {
            '@type': 'richMessage',
            'blocks': [
              {
                '@type': 'pageBlockParagraph',
                'text': {
                  '@type': 'richTexts',
                  'texts': [
                    {'@type': 'richTextPlain', 'text': 'Hello '},
                    {
                      '@type': 'richTextBold',
                      'text': {'@type': 'richTextPlain', 'text': 'world'},
                    },
                  ],
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
    addTearDown(service.dispose);

    final reply = await service.createReply(
      transcript: 'Taylor: Are you free tomorrow?',
      prompt: 'Reply positively and keep it short.',
    );

    expect(reply.text, 'Hello world');
    expect(reply.entities, [
      {
        '@type': 'textEntity',
        'offset': 6,
        'length': 5,
        'type': {'@type': 'textEntityTypeBold'},
      },
    ]);
    final request = requests.singleWhere(
      (request) => request['@type'] == 'composeRichMessageWithAi',
    );
    expect(request['style_name'], '');
    expect(request['custom_prompt'], 'Reply positively and keep it short.');
  });

  test(
    'AI reply falls back to creation when Cocoon rejects rich input',
    () async {
      final requests = <Map<String, dynamic>>[];
      final service = TelegramAiService(
        queryOverride: (request) async {
          requests.add(Map<String, dynamic>.of(request));
          if (request['@type'] == 'getOption') {
            return _capabilityOption(
              request['name'] as String,
              version: '1.8.66',
              promptMax: 480,
            );
          }
          if (request['@type'] == 'composeRichMessageWithAi') {
            throw TdError({
              '@type': 'error',
              'code': 400,
              'message': 'RICH_MESSAGE_UNSUPPORTED',
            });
          }
          if (request['@type'] == 'createRichMessageWithAi') {
            return {
              '@type': 'richMessage',
              'blocks': [
                {
                  '@type': 'pageBlockParagraph',
                  'text': {
                    '@type': 'richTextPlain',
                    'text': 'Yes, Sakura Hall works.',
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
      addTearDown(service.dispose);

      final first = await service.createReply(
        transcript: '[REPLY TARGET] [OTHER] Alex:\nDoes Sakura Hall work?',
        prompt: 'Write a concise direct reply.',
        translateToLanguageCode: 'en',
      );
      expect(first.text, 'Yes, Sakura Hall works.');

      final firstOperations = requests
          .map((request) => request['@type'])
          .where((type) => type != 'getOption')
          .toList(growable: false);
      expect(firstOperations, [
        'composeRichMessageWithAi',
        'createRichMessageWithAi',
      ]);
      final fallback = requests.last;
      expect(fallback['language_code'], 'en');
      expect(
        (fallback['prompt'] as String).runes.length,
        lessThanOrEqualTo(480),
      );
      expect(fallback['prompt'], contains('[REPLY TARGET]'));

      requests.clear();
      await service.createReply(
        transcript: '[REPLY TARGET] [OTHER] Blair:\nAre we set?',
        prompt: 'Write a concise direct reply.',
      );
      expect(requests.map((request) => request['@type']), [
        'createRichMessageWithAi',
      ]);
    },
  );

  test('AI reply maps Telegram premium throttling to typed error', () async {
    final service = TelegramAiService(
      queryOverride: (request) async {
        if (request['@type'] == 'getOption') {
          return _capabilityOption(
            request['name'] as String,
            version: '1.8.66',
          );
        }
        if (request['@type'] == 'composeRichMessageWithAi') {
          throw TdError({
            '@type': 'error',
            'code': 429,
            'message': 'AICOMPOSE_FLOOD_PREMIUM',
          });
        }
        throw StateError('Unexpected request: $request');
      },
    );
    addTearDown(service.dispose);

    expect(
      service.createReply(transcript: 'A: Hello', prompt: 'Reply politely.'),
      throwsA(isA<TelegramAiDailyLimitReached>()),
    );
  });
}

Map<String, dynamic> _capabilityOption(
  String name, {
  required String version,
  int promptMax = 1024,
}) => switch (name) {
  'version' => {'@type': 'optionValueString', 'value': version},
  'text_composition_style_title_length_max' => {
    '@type': 'optionValueInteger',
    'value': 64,
  },
  'text_composition_style_prompt_length_max' => {
    '@type': 'optionValueInteger',
    'value': promptMax,
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
