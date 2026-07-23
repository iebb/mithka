import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/telegram_ai_service.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  test('AI composition request matches pinned TDLib schema', () {
    expect(
      buildComposeTextWithAiRequest(
        text: const TelegramAiFormattedText(text: 'Hello'),
        translateToLanguageCode: 'ja',
        styleName: 'formal',
        addEmojis: true,
      ),
      {
        '@type': 'composeTextWithAi',
        'text': {
          '@type': 'formattedText',
          'text': 'Hello',
          'entities': <Map<String, dynamic>>[],
        },
        'translate_to_language_code': 'ja',
        'style_name': 'formal',
        'add_emojis': true,
      },
    );
  });

  test(
    'AI reply request matches rich schema and keeps newest bounded context',
    () {
      expect(
        buildComposeRichMessageWithAiRequest(
          transcript: '0123456789',
          customPrompt: 'Write a concise reply.',
          translateToLanguageCode: 'ja',
          addEmojis: true,
          maxTranscriptCharacters: 5,
        ),
        {
          '@type': 'composeRichMessageWithAi',
          'message': {
            '@type': 'inputRichMessage',
            'source': {
              '@type': 'richMessageSourceBlocks',
              'blocks': [
                {
                  '@type': 'inputPageBlockParagraph',
                  'text': {'@type': 'richTextPlain', 'text': '56789'},
                },
              ],
            },
            'is_rtl': false,
            'detect_automatic_blocks': false,
          },
          'translate_to_language_code': 'ja',
          'style_name': '',
          'custom_prompt': 'Write a concise reply.',
          'add_emojis': true,
        },
      );
    },
  );

  test(
    'reply capability requires TDLib 1.8.66 and Telegram composition',
    () async {
      final oldService = TelegramAiService(
        queryOverride: (request) async =>
            _capabilityOption(request['name'] as String, version: '1.8.65'),
      );
      addTearDown(oldService.dispose);
      final oldCapabilities = await oldService.capabilities();
      expect(oldCapabilities.compositionSupported, isTrue);
      expect(oldCapabilities.richCompositionSupported, isFalse);
      expect(oldCapabilities.replySupported, isFalse);
      await expectLater(
        oldService.createReply(
          transcript: 'A: Hello',
          prompt: 'Reply politely.',
        ),
        throwsA(isA<UnsupportedError>()),
      );

      final currentService = TelegramAiService(
        queryOverride: (request) async => _capabilityOption(
          request['name'] as String,
          version: '1.8.66-1b08c83bc078',
        ),
      );
      addTearDown(currentService.dispose);
      final currentCapabilities = await currentService.capabilities();
      expect(currentCapabilities.richCompositionSupported, isTrue);
      expect(currentCapabilities.replySupported, isTrue);
    },
  );

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
      throwsA(isA<TelegramAiPremiumRequired>()),
    );
  });

  test(
    'custom styles update locally without adding a new style twice',
    () async {
      final requests = <Map<String, dynamic>>[];
      final service = TelegramAiService(
        queryOverride: (request) async {
          requests.add(Map<String, dynamic>.of(request));
          return switch (request['@type']) {
            'createTextCompositionStyle' => _styleJson(
              name: 'formal',
              title: request['title'] as String,
              prompt: request['prompt'] as String,
              isCreator: true,
            ),
            'editTextCompositionStyle' => _styleJson(
              name: request['name'] as String,
              title: request['title'] as String,
              prompt: request['prompt'] as String,
              isCreator: true,
            ),
            'addTextCompositionStyle' ||
            'deleteTextCompositionStyle' ||
            'removeTextCompositionStyle' => {'@type': 'ok'},
            _ => throw StateError('Unexpected request: $request'),
          };
        },
      );
      addTearDown(service.dispose);

      final created = await service.createStyle(
        title: 'Formal',
        prompt: 'Rewrite formally.',
      );
      expect(created.name, 'formal');
      expect(service.styles.single.title, 'Formal');
      expect(requests.map((request) => request['@type']), [
        'createTextCompositionStyle',
      ]);

      await service.editStyle(
        name: created.name,
        title: 'Very Formal',
        prompt: 'Rewrite very formally.',
      );
      expect(service.styles.single.title, 'Very Formal');

      const shared = TelegramAiStyle(
        name: 'friendly',
        title: 'Friendly',
        customEmojiId: 0,
        isCustom: true,
        isCreator: false,
        installCount: 8,
        prompt: 'Rewrite warmly.',
        creatorUserId: 42,
      );
      await service.addStyle(shared.name, style: shared);
      expect(service.styles.map((style) => style.name), ['friendly', 'formal']);

      await service.removeStyle(shared.name);
      await service.deleteStyle(created.name);
      expect(service.styles, isEmpty);
    },
  );

  test('AI summary request includes chat, message, translation and tone', () {
    expect(
      buildSummarizeMessageRequest(
        chatId: -1001,
        messageId: 77,
        translateToLanguageCode: 'en',
        tone: 'formal',
      ),
      {
        '@type': 'summarizeMessage',
        'chat_id': -1001,
        'message_id': 77,
        'translate_to_language_code': 'en',
        'tone': 'formal',
      },
    );
  });

  test('message parser preserves the server AI summary capability hint', () {
    final message = TDParse.message({
      '@type': 'message',
      'id': 7,
      'chat_id': 9,
      'date': 1,
      'is_outgoing': false,
      'summary_language_code': 'en',
      'sender_id': {'@type': 'messageSenderUser', 'user_id': 3},
      'content': {
        '@type': 'messageText',
        'text': {
          '@type': 'formattedText',
          'text': 'A long channel post',
          'entities': <Map<String, dynamic>>[],
        },
      },
    });
    expect(message, isNotNull);
    expect(message!.summaryLanguageCode, 'en');
  });

  test('video-note parser preserves Telegram speech recognition state', () {
    final message = TDParse.message({
      '@type': 'message',
      'id': 8,
      'chat_id': 9,
      'date': 1,
      'is_outgoing': false,
      'sender_id': {'@type': 'messageSenderUser', 'user_id': 3},
      'content': {
        '@type': 'messageVideoNote',
        'video_note': {
          '@type': 'videoNote',
          'duration': 12,
          'length': 240,
          'video': {'@type': 'file', 'id': 42},
          'speech_recognition_result': {
            '@type': 'speechRecognitionResultText',
            'text': 'Recognized video message',
          },
        },
      },
    });
    expect(message, isNotNull);
    expect(message!.videoNoteTranscription, 'Recognized video message');
    expect(message.videoNoteTranscriptionPending, isFalse);
  });
}

Map<String, dynamic> _styleJson({
  required String name,
  required String title,
  required String prompt,
  required bool isCreator,
}) => {
  '@type': 'textCompositionStyle',
  'name': name,
  'custom_emoji_id': 0,
  'title': title,
  'is_custom': true,
  'is_creator': isCreator,
  'install_count': 1,
  'prompt': prompt,
  'creator_user_id': isCreator ? 1 : 0,
};

Map<String, dynamic> _capabilityOption(
  String name, {
  required String version,
}) => switch (name) {
  'version' => {'@type': 'optionValueString', 'value': version},
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
