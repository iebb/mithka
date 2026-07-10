// Unit tests for the ported pure logic (date formatting, JSON helpers, parsing).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mithka/chat/emoji_catalog.dart';
import 'package:mithka/chat/emoji_text_controller.dart';
import 'package:mithka/chat/media_album_layout.dart';
import 'package:mithka/chat/rich_text_composer_view.dart';
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/keyword_blocker.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/json_helpers.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/date_text.dart';
import 'package:mithka/theme/emoji_font_catalog.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
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

    test('labels use locale-independent numeric format', () {
      Intl.defaultLocale = 'zh_Hans';
      final now = DateTime.now();
      String two(int value) => value.toString().padLeft(2, '0');
      String expectedDate(DateTime value) => value.year == now.year
          ? '${two(value.month)}/${two(value.day)}'
          : '${value.year}/${two(value.month)}/${two(value.day)}';

      final today = DateTime(now.year, now.month, now.day, 9, 5);
      final yesterday = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 1)).add(const Duration(minutes: 38));
      final previousYear = DateTime(now.year - 1, 6, 4, 7, 8);

      expect(DateText.listLabel(today.millisecondsSinceEpoch ~/ 1000), '09:05');
      expect(
        DateText.listLabel(yesterday.millisecondsSinceEpoch ~/ 1000),
        expectedDate(yesterday),
      );
      expect(
        DateText.separatorLabel(yesterday.millisecondsSinceEpoch ~/ 1000),
        '${expectedDate(yesterday)} 00:38',
      );
      expect(
        DateText.quoteLabel(yesterday.millisecondsSinceEpoch ~/ 1000),
        '${expectedDate(yesterday)} 00:38',
      );
      expect(
        DateText.quoteLabel(previousYear.millisecondsSinceEpoch ~/ 1000),
        '${expectedDate(previousYear)} 07:08',
      );
    });
  });

  group('EmojiCatalog', () {
    test('category labels resolve through localization', () {
      for (final category in EmojiCatalog.categories) {
        final localized = AppStrings.t(category.name);
        expect(localized, isNot(category.name));
        expect(localized, isNot(contains('emojiCategory')));
      }
    });
  });

  group('EmojiTextEditingController', () {
    test('inserts preformatted table without corrupting existing entities', () {
      final controller = EmojiTextEditingController();
      addTearDown(controller.dispose);

      controller.text = 'hello world';
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      controller.toggleFormat('textEntityTypeBold');
      controller.selection = const TextSelection.collapsed(offset: 5);
      controller.insertFormattedText(
        '\n| A | B |\n|---|---|\n|   |   |\n',
        type: 'textEntityTypePre',
      );

      final (text, entities) = controller.toFormatted();
      expect(text, startsWith('hello\n| A | B |'));
      expect(entities.map((e) => e['type']['@type']), [
        'textEntityTypeBold',
        'textEntityTypePre',
      ]);
      expect(entities[0]['offset'], 0);
      expect(entities[0]['length'], 5);
      expect(entities[1]['offset'], 5);
    });
  });

  group('RichTextComposerView', () {
    testWidgets('renders toolbar with semantics enabled', (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: RichTextComposerView(initialText: '', allowMedia: false),
        ),
      );
      await tester.pump();

      expect(find.byType(RichTextComposerView), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
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

  group('ChatMessage album visual media', () {
    test(
      'includes photos and videos, excludes thumbnail-only placeholders',
      () {
        ChatMessage message(String type) => ChatMessage(
          id: 1,
          isOutgoing: false,
          text: '',
          date: 1,
          contentType: type,
          image: TdFileRef(id: 10),
        );

        expect(message('messagePhoto').isAlbumVisualMedia, isTrue);
        expect(message('messageVideo').isAlbumVisualMedia, isTrue);
        expect(message('messageSticker').isAlbumVisualMedia, isFalse);
        expect(message('messageAnimation').isAlbumVisualMedia, isFalse);
      },
    );

    test('photo messages keep a downloadable thumbnail before full image', () {
      final message = TDParse.message({
        '@type': 'message',
        'id': 42,
        'date': 1,
        'is_outgoing': false,
        'content': {
          '@type': 'messagePhoto',
          'photo': {
            '@type': 'photo',
            'sizes': [
              {
                '@type': 'photoSize',
                'type': 'm',
                'width': 320,
                'height': 180,
                'photo': {'@type': 'file', 'id': 10},
              },
              {
                '@type': 'photoSize',
                'type': 'y',
                'width': 1920,
                'height': 1080,
                'photo': {'@type': 'file', 'id': 20},
              },
            ],
          },
        },
      });

      expect(message, isNotNull);
      expect(message!.image?.id, 20);
      expect(message.image?.thumbnail?.id, 10);
      expect(message.imageWidth, 1920);
      expect(message.imageHeight, 1080);
    });
  });

  group('ChatMessage replies', () {
    ChatMessage message({
      bool hasThread = false,
      int replyCount = 0,
      int? lastReplyId,
    }) => ChatMessage(
      id: 1,
      isOutgoing: false,
      text: 'message',
      date: 1,
      hasCommentThread: hasThread,
      commentCount: replyCount,
      lastCommentMessageId: lastReplyId,
    );

    test('thread metadata without replies does not expose Replies', () {
      expect(message(hasThread: true).hasActualReplies, isFalse);
      expect(
        message(hasThread: true, lastReplyId: 0).hasActualReplies,
        isFalse,
      );
    });

    test('reply count or a real last reply exposes Replies', () {
      expect(message(replyCount: 1).hasActualReplies, isTrue);
      expect(message(lastReplyId: 42).hasActualReplies, isTrue);
    });
  });

  group('MediaAlbumLayout', () {
    test('uses proportional non-overlapping rows for mixed albums', () {
      final layout = buildTelegramMediaAlbumLayout(
        items: const [
          MediaAlbumItem(width: 1600, height: 900),
          MediaAlbumItem(width: 900, height: 1600),
          MediaAlbumItem(width: 1200, height: 1200),
          MediaAlbumItem(width: 1024, height: 768),
          MediaAlbumItem(width: 768, height: 1024),
        ],
        maxWidth: 330,
      );

      expect(layout.tiles, hasLength(5));
      expect(layout.width, 330);
      expect(layout.height, greaterThan(0));
      for (final tile in layout.tiles) {
        expect(tile.left, greaterThanOrEqualTo(0));
        expect(tile.top, greaterThanOrEqualTo(0));
        expect(tile.right, lessThanOrEqualTo(layout.width + 0.01));
        expect(tile.bottom, lessThanOrEqualTo(layout.height + 0.01));
        expect(tile.width, greaterThan(0));
        expect(tile.height, greaterThan(0));
      }

      for (var i = 0; i < layout.tiles.length; i++) {
        for (var j = i + 1; j < layout.tiles.length; j++) {
          expect(layout.tiles[i].overlaps(layout.tiles[j]), isFalse);
        }
      }
    });
  });

  group('ThemeController chat folders', () {
    test('migrates the former folder visibility toggle', () async {
      SharedPreferences.setMockInitialValues({'showChatFolderFilter': false});
      var prefs = await SharedPreferences.getInstance();
      expect(
        ThemeController(prefs).chatFolderDisplayMode,
        ChatFolderDisplayMode.hidden,
      );

      SharedPreferences.setMockInitialValues({'showChatFolderFilter': true});
      prefs = await SharedPreferences.getInstance();
      expect(
        ThemeController(prefs).chatFolderDisplayMode,
        ChatFolderDisplayMode.menu,
      );
    });

    test('prefers and persists the explicit display mode', () async {
      SharedPreferences.setMockInitialValues({
        'showChatFolderFilter': false,
        'chatFolderDisplayMode': 'tabs',
      });
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);

      expect(theme.chatFolderDisplayMode, ChatFolderDisplayMode.tabs);
      theme.chatFolderDisplayMode = ChatFolderDisplayMode.menu;
      expect(prefs.getString('chatFolderDisplayMode'), 'menu');
    });
  });

  group('ThemeController fonts', () {
    test('applies explicit fallback chain in order', () async {
      SharedPreferences.setMockInitialValues({
        'fontFallbackChain': ['Futura', 'PingFang SC', 'Futura'],
      });
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);

      expect(theme.fontFallbackChain, ['Futura', 'PingFang SC']);
      final style = theme.applyAppTextStyle(const TextStyle());
      expect(style.fontFamily, 'Futura');
      expect(style.fontFamilyFallback, contains('PingFang SC'));
    });

    test('honors system bold text by increasing app text weights', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);

      final regular = theme.applyAppTextStyle(
        const TextStyle(),
        boldText: true,
      );
      final medium = theme.applyAppTextStyle(
        const TextStyle(fontWeight: FontWeight.w500),
        boldText: true,
      );

      expect(regular.fontWeight, FontWeight.w600);
      expect(medium.fontWeight, FontWeight.w700);
    });
  });

  group('TDParse.messageText', () {
    test('photo with no caption uses localized placeholder', () {
      final content = <String, dynamic>{'@type': 'messagePhoto'};
      expect(
        TDParse.messageText(content),
        AppStrings.t(AppStringKeys.composerImagePreview),
      );
    });

    test('plain text passes through', () {
      final content = <String, dynamic>{
        '@type': 'messageText',
        'text': {'@type': 'formattedText', 'text': 'hello'},
      };
      expect(TDParse.messageText(content), 'hello');
    });

    test('dice keeps emoji preview and parsed value', () {
      final message = TDParse.message({
        'id': 10,
        'date': 1,
        'content': {'@type': 'messageDice', 'emoji': '🎲', 'value': 6},
      });
      expect(message, isNotNull);
      expect(message!.text, '🎲');
      expect(message.diceEmoji, '🎲');
      expect(message.diceValue, 6);
      expect(message.isDice, isTrue);
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

    test('supports Bot API rich text class names', () {
      Map<String, dynamic> plain(String text) => {
        '@type': 'RichTextPlain',
        'text': text,
      };
      Map<String, dynamic> wrap(String type, String text) => {
        '@type': type,
        'text': plain(text),
      };

      final rich = <String, dynamic>{
        '@type': 'RichText',
        'texts': [
          wrap('RichTextBold', 'bold'),
          plain(' '),
          wrap('RichTextItalic', 'italic'),
          plain(' '),
          wrap('RichTextUnderline', 'underline'),
          plain(' '),
          wrap('RichTextStrikethrough', 'strike'),
          plain(' '),
          wrap('RichTextSpoiler', 'spoiler'),
          plain(' '),
          wrap('RichTextDateTime', 'tomorrow'),
          plain(' '),
          {
            '@type': 'RichTextTextMention',
            'text': plain('Alice'),
            'user_id': 42,
          },
          plain(' '),
          wrap('RichTextSubscript', 'sub'),
          plain(' '),
          wrap('RichTextSuperscript', 'super'),
          plain(' '),
          wrap('RichTextMarked', 'marked'),
          plain(' '),
          wrap('RichTextCode', 'code'),
          plain(' '),
          {
            '@type': 'RichTextCustomEmoji',
            'text': '🙂',
            'custom_emoji_id': '123456',
          },
          plain(' '),
          {'@type': 'RichTextMathematicalExpression', 'expression': r'x^2'},
          plain(' '),
          {
            '@type': 'RichTextUrl',
            'text': plain('site'),
            'url': 'https://example.com',
          },
          plain(' '),
          {'@type': 'RichTextEmailAddress', 'email_address': 'a@example.com'},
          plain(' '),
          {'@type': 'RichTextPhoneNumber', 'phone_number': '+123456789'},
          plain(' '),
          {
            '@type': 'RichTextBankCardNumber',
            'bank_card_number': '4242 4242 4242 4242',
          },
          plain(' '),
          {'@type': 'RichTextMention', 'username': 'telegram'},
          plain(' '),
          {'@type': 'RichTextHashtag', 'hashtag': 'topic'},
          plain(' '),
          {'@type': 'RichTextCashtag', 'cashtag': 'USD'},
          plain(' '),
          {'@type': 'RichTextBotCommand', 'command': 'start'},
          plain(' '),
          {'@type': 'RichTextAnchor', 'name': 'chapter-1'},
          {
            '@type': 'RichTextAnchorLink',
            'text': plain('chapter'),
            'name': 'chapter-1',
          },
          plain(' '),
          {'@type': 'RichTextReference', 'name': 'note-1'},
          plain(' '),
          {
            '@type': 'RichTextReferenceLink',
            'text': plain('note'),
            'name': 'note-1',
          },
        ],
      };

      expect(
        TDParse.richTextText(rich),
        contains(
          'bold italic underline strike spoiler tomorrow Alice sub super marked '
          'code 🙂 x^2 site a@example.com +123456789 '
          '4242 4242 4242 4242 @telegram #topic \$USD /start chapter note-1 note',
        ),
      );
      final entities = TDParse.richTextEntities(rich);
      expect(entities.map((e) => e.type), [
        'textEntityTypeBold',
        'textEntityTypeItalic',
        'textEntityTypeUnderline',
        'textEntityTypeStrikethrough',
        'textEntityTypeSpoiler',
        'textEntityTypeDateTime',
        'textEntityTypeMentionName',
        'textEntityTypeSubscript',
        'textEntityTypeSuperscript',
        'textEntityTypeMarked',
        'textEntityTypeCode',
        'textEntityTypeCustomEmoji',
        'textEntityTypeMathematicalExpression',
        'textEntityTypeTextUrl',
        'textEntityTypeEmailAddress',
        'textEntityTypePhoneNumber',
        'textEntityTypeBankCardNumber',
        'textEntityTypeTextUrl',
        'textEntityTypeHashtag',
        'textEntityTypeCashtag',
        'textEntityTypeBotCommand',
        'textEntityTypeTextUrl',
        'textEntityTypeTextUrl',
      ]);
      expect(
        entities
            .firstWhere((e) => e.type == 'textEntityTypeMentionName')
            .userId,
        42,
      );
      expect(
        entities
            .firstWhere((e) => e.type == 'textEntityTypeCustomEmoji')
            .customEmojiId,
        123456,
      );
      expect(entities.where((e) => e.url == '#chapter-1'), hasLength(1));
      expect(entities.where((e) => e.url == '#note-1'), hasLength(1));
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
              {
                '@type': 'pageBlockMathematicalExpression',
                'expression': r'x^2',
              },
              {
                '@type': 'pageBlockTable',
                'caption': {
                  '@type': 'pageBlockCaption',
                  'text': {'@type': 'richTextPlain', 'text': 'Metrics'},
                },
                'cells': [
                  [
                    {
                      '@type': 'richBlockTableCell',
                      'is_header': true,
                      'text': {'@type': 'richTextPlain', 'text': 'Name'},
                    },
                    {
                      '@type': 'richBlockTableCell',
                      'is_header': true,
                      'text': {'@type': 'richTextPlain', 'text': 'Value'},
                    },
                  ],
                  [
                    {
                      '@type': 'richBlockTableCell',
                      'text': {'@type': 'richTextPlain', 'text': 'Speed'},
                    },
                    {
                      '@type': 'richBlockTableCell',
                      'text': {
                        '@type': 'richTextBold',
                        'text': {'@type': 'richTextPlain', 'text': '42'},
                      },
                    },
                  ],
                ],
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
      expect(message.richBlocks, hasLength(2));
      expect(message.richBlocks.first.mathExpression, r'x^2');
      final table = message.richBlocks.last;
      expect(table.caption, 'Metrics');
      expect(table.tableRows, hasLength(2));
      expect(table.tableRows.first.first.text, 'Name');
      expect(table.tableRows.first.first.isHeader, isTrue);
      expect(table.tableRows[1][1].text, '42');
      expect(table.tableRows[1][1].entities.single.type, 'textEntityTypeBold');
    });

    test('extracts markdown pipe tables into rich table blocks', () {
      final message = TDParse.message({
        '@type': 'message',
        'id': 101,
        'date': 1,
        'is_outgoing': true,
        'content': {
          '@type': 'messageText',
          'text': {
            '@type': 'formattedText',
            'text':
                'Before\n\n| Name | Value |\n| ---- | ----- |\n| Speed | 42 |\n\nAfter',
          },
        },
      });

      expect(message, isNotNull);
      expect(message!.text, 'Before\n\nAfter');
      expect(message.richBlocks, hasLength(1));
      final table = message.richBlocks.single;
      expect(table.tableRows, hasLength(2));
      expect(table.tableRows.first.first.text, 'Name');
      expect(table.tableRows.first.first.isHeader, isTrue);
      expect(table.tableRows[1][1].text, '42');
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

  group('EmojiFontChoice', () {
    test('uses platform fallback until a runtime font is loaded', () {
      expect(EmojiFontChoice.system.fontFamilies, isNotEmpty);
      const choice = EmojiFontChoice(
        key: 'twemoji',
        label: 'Twemoji',
        fontFamily: 'MithkaEmoji_twemoji',
      );
      expect(choice.fontFamilies.first, 'MithkaEmoji_twemoji');
    });

    test('parses release manifest entries and chooses a downloadable format', () {
      final entry = EmojiFontManifestEntry.fromJson({
        'key': 'twemoji',
        'label': 'Twemoji',
        'license': 'CC-BY-4.0',
        'kind': 'color',
        'coverage_pct': 99,
        'emoji_version': '15.0',
        'updated': '2026-06-16',
        'formats': {
          'sbix':
              'https://github.com/iebb/emojifonts/releases/download/latest/twemoji.ttf',
        },
      });

      expect(entry.key, 'twemoji');
      expect(entry.runtimeFamily, 'MithkaEmoji_twemoji');
      expect(entry.format, 'sbix');
      expect(entry.emojiVersion, '15.0');
      expect(entry.extension, 'ttf');
    });
  });

  group('TranslationController', () {
    test('defaults off and persists target/provider preferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = TranslationController(prefs);

      expect(controller.enabled, isFalse);
      expect(controller.provider, TranslationProvider.tdlib);
      expect(controller.targetLanguageCode, 'zh-Hans');
      expect(
        controller.lingvaEndpoint,
        TranslationController.defaultLingvaEndpoint,
      );
      expect(controller.libreTranslateEndpoint, isEmpty);
      expect(controller.libreTranslateApiKey, isEmpty);

      controller.enabled = true;
      controller.provider = TranslationProvider.lingva;
      controller.targetLanguageCode = 'ja';
      controller.lingvaEndpoint = 'https://lingva.example.com/';
      controller.libreTranslateEndpoint = ' https://libre.example.com// ';
      controller.libreTranslateApiKey = ' secret-key ';

      final reloaded = TranslationController(prefs);
      expect(reloaded.enabled, isTrue);
      expect(reloaded.provider, TranslationProvider.lingva);
      expect(reloaded.targetLanguageCode, 'ja');
      expect(reloaded.lingvaEndpoint, 'https://lingva.example.com');
      expect(reloaded.libreTranslateEndpoint, 'https://libre.example.com');
      expect(reloaded.libreTranslateApiKey, 'secret-key');
    });

    test(
      'loads stored provider and falls back to Telegram for unavailable values',
      () async {
        SharedPreferences.setMockInitialValues({
          'translation.provider': 'tdlib',
        });
        final prefs = await SharedPreferences.getInstance();
        final controller = TranslationController(prefs);

        expect(controller.provider, TranslationProvider.tdlib);
        controller.provider = TranslationProvider.myMemory;
        expect(controller.provider, TranslationProvider.myMemory);

        SharedPreferences.setMockInitialValues({
          'translation.provider': 'not_a_provider',
        });
        final fallbackPrefs = await SharedPreferences.getInstance();
        final fallback = TranslationController(fallbackPrefs);
        expect(fallback.provider, TranslationProvider.tdlib);

        SharedPreferences.setMockInitialValues({
          'translation.provider': 'native_on_device',
        });
        final nativePrefs = await SharedPreferences.getInstance();
        final nativeFallback = TranslationController(nativePrefs);
        expect(nativeFallback.provider, TranslationProvider.tdlib);
      },
    );
  });

  group('AppLocaleController', () {
    tearDown(() {
      Intl.defaultLocale = null;
    });

    test('AppStrings follows script and regional locale tags', () {
      Intl.defaultLocale = 'zh_Hans';
      expect(AppStrings.t(AppStringKeys.apiCredentialsTitle), '视频与下载加速');

      Intl.defaultLocale = 'zh-Hant';
      expect(
        AppLocalizations.localeKeyFor(
          AppLocalizations.resolve(
            AppLocalizations.localeFromTag(Intl.getCurrentLocale())!,
          ),
        ),
        'zhHant',
      );

      Intl.defaultLocale = 'zh_HK';
      expect(
        AppLocalizations.localeKeyFor(
          AppLocalizations.resolve(
            AppLocalizations.localeFromTag(Intl.getCurrentLocale())!,
          ),
        ),
        'zhHant',
      );

      Intl.defaultLocale = 'en_US';
      expect(
        AppLocalizations.localeKeyFor(
          AppLocalizations.resolve(
            AppLocalizations.localeFromTag(Intl.getCurrentLocale())!,
          ),
        ),
        'en',
      );
    });

    test('non-Chinese locales do not surface Chinese fallback strings', () {
      final source = File('lib/l10n/app_localizations.dart').readAsStringSync();
      final keys = RegExp(
        r"static const [A-Za-z0-9_]+ = '([^']+)';",
      ).allMatches(source).map((match) => match.group(1)!).toSet();
      final zhValues = <String, String>{};
      final zhBlock = File('lib/l10n/messages/zh_hans.dart').readAsStringSync();
      for (final match in RegExp(
        r''' '([^']+)':\s*"((?:\\.|[^"])*)" '''.trim(),
        dotAll: true,
      ).allMatches(zhBlock)) {
        zhValues[match.group(1)!] = match.group(2)!;
      }
      final intentionalHan = RegExp(r'^(appLocale|country|markdown|theme)');
      final han = RegExp(r'[\u3400-\u9fff]');
      final failures = <String>[];
      for (final localeKey in ['en', 'ko', 'fr', 'es', 'de']) {
        for (final key in keys) {
          if (intentionalHan.hasMatch(key)) continue;
          final value = AppStrings.tForLocale(localeKey, key);
          if (han.hasMatch(value)) failures.add('$localeKey.$key=$value');
        }
      }
      final jaSameAsChinese = <String>[];
      for (final key in keys) {
        if (intentionalHan.hasMatch(key)) continue;
        final value = AppStrings.tForLocale('ja', key);
        final zhValue = zhValues[key];
        if (zhValue != null && value == zhValue && han.hasMatch(value)) {
          jaSameAsChinese.add('ja.$key=$value');
        }
      }
      if (jaSameAsChinese.length > 80) {
        failures.add(
          'ja appears to be using Chinese fallback for '
          '${jaSameAsChinese.length} keys: ${jaSameAsChinese.take(5).join(', ')}',
        );
      }
      expect(failures, isEmpty);
    });

    test('country names resolve from the split country map', () {
      expect(AppStrings.tForLocale('en', AppStringKeys.countryJP), 'Japan');
      expect(AppStrings.tForLocale('ja', AppStringKeys.countryJP), '日本');
      expect(AppStrings.tForLocale('ko', AppStringKeys.countryKR), '대한민국');
      expect(AppStrings.tForLocale('zhHant', AppStringKeys.countryTW), '中國台灣');
    });

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

    testWidgets('rebuilds localized text when language changes', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = AppLocaleController(prefs)
        ..locale = const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hans',
        );

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: Consumer<AppLocaleController>(
            builder: (context, locale, _) {
              return MaterialApp(
                locale: locale.locale,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                ],
                home: Builder(
                  builder: (context) => Text(
                    AppStringKeys.tabMessages.l10n(context),
                    textDirection: ui.TextDirection.ltr,
                  ),
                ),
              );
            },
          ),
        ),
      );
      expect(find.text('消息'), findsOneWidget);

      controller.locale = const Locale('en');
      await tester.pumpAndSettle();
      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('消息'), findsNothing);
    });
  });
}
