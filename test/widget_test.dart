// Unit tests for the ported pure logic (date formatting, JSON helpers, parsing).

import 'package:mithka/tdlib/json_helpers.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/settings/keyword_blocker.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/theme/date_text.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('DateText', () {
    test('bubbleLabel pads to HH:mm', () {
      final unix = DateTime(2024, 6, 4, 9, 5).millisecondsSinceEpoch ~/ 1000;
      expect(DateText.bubbleLabel(unix), '09:05');
    });

    test('empty for non-positive unix', () {
      expect(DateText.listLabel(0), '');
      expect(DateText.separatorLabel(0), '');
    });
  });

  group('JSON helpers', () {
    test('parses TDLib int64-as-string', () {
      final obj = <String, dynamic>{'order': '123456789012345', 'n': 7};
      expect(obj.int64('order'), 123456789012345);
      expect(obj.integer('n'), 7);
      expect(obj.str('missing'), isNull);
    });
  });

  group('TDParse.messageText', () {
    test('photo with no caption → [图片]', () {
      final content = <String, dynamic>{'@type': 'messagePhoto'};
      expect(TDParse.messageText(content), '[图片]');
    });

    test('plain text passes through', () {
      final content = <String, dynamic>{
        '@type': 'messageText',
        'text': {'@type': 'formattedText', 'text': 'hello'},
      };
      expect(TDParse.messageText(content), 'hello');
    });

    test('flattens Telegram core RichText markdown nodes', () {
      final rich = <String, dynamic>{
        '@type': 'textConcat',
        'texts': [
          {'@type': 'textPlain', 'text': 'Hello '},
          {
            '@type': 'textBold',
            'text': {'@type': 'textPlain', 'text': 'bold'},
          },
          {'@type': 'textPlain', 'text': ' '},
          {
            '@type': 'textUrl',
            'text': {'@type': 'textPlain', 'text': 'site'},
            'url': 'https://example.com',
          },
        ],
      };

      expect(TDParse.richTextText(rich), 'Hello bold site');
      final entities = TDParse.richTextEntities(rich);
      expect(entities.map((e) => e.type), [
        'textEntityTypeBold',
        'textEntityTypeTextUrl',
      ]);
      expect(entities[1].url, 'https://example.com');
    });

    test('parses TDLib messageRichMessage in chat messages', () {
      final message = TDParse.message({
        '@type': 'message',
        'id': 100,
        'date': 1,
        'is_outgoing': false,
        'content': {
          '@type': 'messageRichMessage',
          'message': {
            '@type': 'richMessage',
            'is_rtl': false,
            'is_full': true,
            'blocks': [
              {
                '@type': 'pageBlockParagraph',
                'text': {
                  '@type': 'richTexts',
                  'texts': [
                    {'@type': 'richTextPlain', 'text': 'Hello '},
                    {
                      '@type': 'richTextBold',
                      'text': {'@type': 'richTextPlain', 'text': 'bold'},
                    },
                    {'@type': 'richTextPlain', 'text': ' and '},
                    {
                      '@type': 'richTextUrl',
                      'text': {'@type': 'richTextPlain', 'text': 'link'},
                      'url': 'https://example.com',
                      'is_cached': false,
                    },
                  ],
                },
              },
              {
                '@type': 'pageBlockPreformatted',
                'language': 'dart',
                'text': {'@type': 'richTextPlain', 'text': 'final x = 1;'},
              },
            ],
          },
        },
      });

      expect(message, isNotNull);
      expect(message!.text, 'Hello bold and link\n\nfinal x = 1;');
      expect(message.textEntities.map((e) => e.type), [
        'textEntityTypeBold',
        'textEntityTypeTextUrl',
        'textEntityTypePreCode',
      ]);
      expect(message.textEntities[1].url, 'https://example.com');
      expect(message.textEntities[2].language, 'dart');
    });
  });

  group('TDParse.messageButtonRows', () {
    test('parses inline keyboard url and callback buttons', () {
      final rows = TDParse.messageButtonRows({
        '@type': 'replyMarkupInlineKeyboard',
        'rows': [
          [
            {
              '@type': 'inlineKeyboardButton',
              'text': 'Open',
              'type': {
                '@type': 'inlineKeyboardButtonTypeUrl',
                'url': 'https://example.com',
              },
            },
            {
              '@type': 'inlineKeyboardButton',
              'text': 'Tap',
              'type': {
                '@type': 'inlineKeyboardButtonTypeCallback',
                'data': 'abc',
              },
            },
          ],
        ],
      });

      expect(rows, hasLength(1));
      expect(rows.first, hasLength(2));
      expect(rows.first[0].text, 'Open');
      expect(rows.first[0].url, 'https://example.com');
      expect(rows.first[1].isCallback, isTrue);
      expect(rows.first[1].data, 'abc');
    });

    test('parses reply keyboard text buttons', () {
      final rows = TDParse.messageButtonRows({
        '@type': 'replyMarkupShowKeyboard',
        'rows': [
          [
            {
              '@type': 'keyboardButton',
              'text': 'OK',
              'type': {'@type': 'keyboardButtonTypeText'},
            },
          ],
        ],
      });

      expect(rows.single.single.text, 'OK');
      expect(rows.single.single.type, 'keyboardButtonTypeText');
      expect(rows.single.single.isReplyKeyboard, isTrue);
    });

    test('marks inline and reply keyboard Web App buttons', () {
      final inlineRows = TDParse.messageButtonRows({
        '@type': 'replyMarkupInlineKeyboard',
        'rows': [
          [
            {
              '@type': 'inlineKeyboardButton',
              'text': 'Mini App',
              'type': {
                '@type': 'inlineKeyboardButtonTypeWebApp',
                'url': 'https://example.com/app',
              },
            },
          ],
        ],
      });
      final replyRows = TDParse.messageButtonRows({
        '@type': 'replyMarkupShowKeyboard',
        'rows': [
          [
            {
              '@type': 'keyboardButton',
              'text': 'Launch',
              'type': {
                '@type': 'keyboardButtonTypeWebApp',
                'url': 'https://example.com/reply-app',
              },
            },
          ],
        ],
      });

      expect(inlineRows.single.single.isWebApp, isTrue);
      expect(inlineRows.single.single.url, 'https://example.com/app');
      expect(replyRows.single.single.isWebApp, isTrue);
      expect(replyRows.single.single.isReplyKeyboard, isTrue);
      expect(replyRows.single.single.url, 'https://example.com/reply-app');
    });
  });

  group('TDParse.linkPreview', () {
    test('parses title, full description, and article photo', () {
      final preview = TDParse.linkPreview({
        '@type': 'linkPreview',
        'url': 'https://example.com/rich',
        'display_url': 'example.com/rich',
        'site_name': 'Example',
        'title': 'Rich Message Demo',
        'description': {
          '@type': 'formattedText',
          'text': 'Select a screen\n- Text Formatting\n- Code & Pre',
          'entities': [
            {
              '@type': 'textEntity',
              'offset': 18,
              'length': 15,
              'type': {'@type': 'textEntityTypeBold'},
            },
          ],
        },
        'type': {
          '@type': 'linkPreviewTypeArticle',
          'photo': {
            '@type': 'photo',
            'sizes': [
              {
                '@type': 'photoSize',
                'width': 320,
                'height': 180,
                'photo': {'@type': 'file', 'id': 42},
              },
            ],
          },
        },
        'show_large_media': true,
        'show_media_above_description': true,
        'show_above_text': false,
      });

      expect(preview, isNotNull);
      expect(preview!.title, 'Rich Message Demo');
      expect(preview.description, contains('Text Formatting'));
      expect(preview.descriptionEntities.single.type, 'textEntityTypeBold');
      expect(preview.image?.id, 42);
      expect(preview.imageWidth, 320);
      expect(preview.imageHeight, 180);
      expect(preview.showLargeMedia, isTrue);
    });
  });

  group('KeywordBlocker', () {
    test('matches plain keywords and regex rules', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final blocker = KeywordBlocker.shared;
      blocker.initialize(prefs);
      blocker.replaceAll(['free money', r're:\b\d{5}\b', r'/hello\s+world/i']);

      expect(blocker.matches('Claim FREE MONEY now'), isTrue);
      expect(blocker.matches('code 12345 please'), isTrue);
      expect(blocker.matches('HELLO     WORLD'), isTrue);
      expect(blocker.matches('normal message'), isFalse);
    });
  });

  group('AppFontChoice', () {
    test('applies primary font before CJK and system fallbacks', () {
      final style = AppFontChoice.futura.applyTextStyle(
        const TextStyle(fontSize: 16),
        cjkFallback: AppFontChoice.pingFangTw,
      );

      expect(style.fontFamily, 'Futura');
      expect(style.fontFamilyFallback, isNotNull);
      expect(style.fontFamilyFallback!.first, 'PingFang TC');
      expect(style.fontFamilyFallback!, contains('Helvetica Neue'));
    });

    test('preset fonts ignore stale custom font families', () {
      final style = AppFontChoice.futura.applyTextStyle(
        const TextStyle(fontSize: 16),
        cjkFallback: AppFontChoice.pingFangTw,
        customPrimaryFamily: 'My Latin',
        customCjkFamily: 'My CJK',
      );

      expect(style.fontFamily, 'Futura');
      expect(style.fontFamilyFallback, isNotNull);
      expect(style.fontFamilyFallback!.first, 'PingFang TC');
      expect(style.fontFamilyFallback!.length, greaterThan(1));
    });

    test('custom font choices use explicit custom font families', () {
      final style = AppFontChoice.custom.applyTextStyle(
        const TextStyle(fontSize: 16),
        cjkFallback: AppFontChoice.customCjk,
        customPrimaryFamily: 'My Latin',
        customCjkFamily: 'My CJK',
      );

      expect(style.fontFamily, 'My Latin');
      expect(style.fontFamilyFallback, isNotNull);
      expect(style.fontFamilyFallback!.first, 'My CJK');
      expect(style.fontFamilyFallback!.length, greaterThan(1));
    });

    test('monospace font choices render code with selected family', () {
      final style = AppMonospaceFontChoice.custom.applyTextStyle(
        const TextStyle(fontSize: 13),
        customFamily: 'My Mono',
      );

      expect(style.fontFamily, 'My Mono');
      expect(style.fontFamilyFallback, contains('My Mono'));
      expect(style.fontFamilyFallback!.length, greaterThan(1));
    });
  });

  group('TranslationController', () {
    test('defaults off and persists target/no-translate preferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = TranslationController(prefs);

      expect(controller.enabled, isFalse);
      expect(controller.autoTranslate, isFalse);
      expect(controller.provider, TranslationProvider.nativeOnDevice);
      expect(controller.targetLanguageCode, 'zh-Hans');
      expect(controller.noTranslateLanguageCodes, isEmpty);
      expect(
        controller.lingvaEndpoint,
        TranslationController.defaultLingvaEndpoint,
      );
      expect(controller.libreTranslateEndpoint, isEmpty);

      controller.enabled = true;
      controller.autoTranslate = true;
      controller.provider = TranslationProvider.nativeOnDevice;
      controller.targetLanguageCode = 'ja';
      controller.setNoTranslateLanguage('en', true);
      controller.lingvaEndpoint = 'https://lingva.example.com/';
      controller.libreTranslateEndpoint = ' https://libre.example.com// ';

      final reloaded = TranslationController(prefs);
      expect(reloaded.enabled, isTrue);
      expect(reloaded.autoTranslate, isTrue);
      expect(reloaded.provider, TranslationProvider.nativeOnDevice);
      expect(reloaded.targetLanguageCode, 'ja');
      expect(reloaded.noTranslateLanguageCodes, contains('en'));
      expect(reloaded.lingvaEndpoint, 'https://lingva.example.com');
      expect(reloaded.libreTranslateEndpoint, 'https://libre.example.com');
    });

    test(
      'forces native provider regardless of stale stored provider',
      () async {
        SharedPreferences.setMockInitialValues({
          'translation.provider': 'tdlib',
        });
        final prefs = await SharedPreferences.getInstance();
        final controller = TranslationController(prefs);

        expect(controller.provider, TranslationProvider.nativeOnDevice);
        controller.provider = TranslationProvider.lingva;
        expect(controller.provider, TranslationProvider.nativeOnDevice);
      },
    );
  });

  group('AppLocaleController', () {
    test('defaults to system and persists explicit locale choices', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = AppLocaleController(prefs);

      expect(controller.followsSystem, isTrue);
      expect(controller.locale, isNull);

      controller.locale = const Locale('ja');
      expect(controller.followsSystem, isFalse);
      expect(controller.locale, const Locale('ja'));

      final reloaded = AppLocaleController(prefs);
      expect(reloaded.locale, const Locale('ja'));

      reloaded.locale = null;
      expect(reloaded.followsSystem, isTrue);

      final systemAgain = AppLocaleController(prefs);
      expect(systemAgain.locale, isNull);
    });
  });
}
