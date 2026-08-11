import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph, SelectedContent;
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/custom_emoji.dart';
import 'package:mithka/chat/message_action_menu.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/chat/stretchable_message_bubble_background.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/document_file_icon.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/message_bubble_background.dart';
import 'package:mithka/theme/telegram_cloud_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Iterable<TextSpan> _textSpans(InlineSpan span) sync* {
  if (span is! TextSpan) return;
  yield span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* _textSpans(child);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ThemeController> pumpBubble(
    WidgetTester tester,
    ChatMessage message, {
    List<ChatMessage> groupedMedia = const <ChatMessage>[],
    bool isGroup = false,
    bool showCommentAttachment = false,
    bool channelHasLinkedDiscussion = false,
    bool themingEnabled = true,
    AppColors? colors,
    Color? outgoingBubbleColor,
    Color? outgoingBubbleTextColor,
    Color? incomingBubbleColor,
    Color? incomingBubbleTextColor,
    TelegramMessageColors? messageColors,
    TelegramCloudTheme? cloudTheme,
    MessageBubbleBackground? bubbleBackground,
    TranslationDisplayStyle translationDisplayStyle =
        TranslationDisplayStyle.quote,
    Set<int> showOriginalTranslationMessageIds = const <int>{},
    GlobalKey<SelectionAreaState>? mobileTextSelectionAreaKey,
    ValueChanged<SelectedContent?>? onMobileTextSelectionChanged,
    ValueChanged<ChatMessage>? onLongPress,
    ValueChanged<ChatMessage>? onOpenComments,
    void Function(ChatMessage, Rect?, MessageActionSource)? onActionMenu,
  }) async {
    SharedPreferences.setMockInitialValues({
      'groupImageMessages': true,
      'appearanceThemingEnabled': themingEnabled,
    });
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    if (cloudTheme != null) theme.installCloudTheme(cloudTheme);
    if (bubbleBackground != null) {
      theme.messageBubbleBackground = bubbleBackground;
    }
    addTearDown(theme.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          theme: colors == null ? null : ThemeData(extensions: [colors]),
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MessageBubble(
              message: message,
              groupedMedia: groupedMedia,
              peerTitle: 'Test',
              isGroup: isGroup,
              showCommentAttachment: showCommentAttachment,
              channelHasLinkedDiscussion: channelHasLinkedDiscussion,
              outgoingBubbleColor: outgoingBubbleColor,
              outgoingBubbleTextColor: outgoingBubbleTextColor,
              incomingBubbleColor: incomingBubbleColor,
              incomingBubbleTextColor: incomingBubbleTextColor,
              messageColors: messageColors,
              translationDisplayStyle: translationDisplayStyle,
              showOriginalTranslationMessageIds:
                  showOriginalTranslationMessageIds,
              mobileTextSelectionAreaKey: mobileTextSelectionAreaKey,
              onMobileTextSelectionChanged: onMobileTextSelectionChanged,
              onOpenComments: onOpenComments,
              onLongPress:
                  onActionMenu ??
                  (onLongPress == null
                      ? null
                      : (message, _, _) => onLongPress(message)),
            ),
          ),
        ),
      ),
    );
    return theme;
  }

  const messageColors = TelegramMessageColors(
    incomingLink: Color(0xFF0055AA),
    outgoingLink: Color(0xFFFF66AA),
    incomingQuote: Color(0xFF008844),
    outgoingQuote: Color(0xFFFF8800),
    incomingReplyLine: Color(0xFF117733),
    outgoingReplyLine: Color(0xFFDD7700),
    incomingReplyName: Color(0xFF226644),
    outgoingReplyName: Color(0xFFCC6600),
    incomingReplyText: Color(0xFF335544),
    outgoingReplyText: Color(0xFFBB5500),
    incomingReplyMediaText: Color(0xFF123443),
    outgoingReplyMediaText: Color(0xFF432112),
    incomingForwardedName: Color(0xFF4444AA),
    outgoingForwardedName: Color(0xFFAA44AA),
    incomingPreviewLine: Color(0x805555AA),
    outgoingPreviewLine: Color(0xFFAA55AA),
    incomingSiteName: Color(0xFF6666AA),
    outgoingSiteName: Color(0xFFAA66AA),
    incomingTime: Color(0xFF777788),
    outgoingTime: Color(0xFF887788),
  );

  testWidgets('translation display styles replace, reveal, or divide text', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 901,
      isOutgoing: false,
      text: 'Original text',
      date: 1,
      contentType: 'messageText',
      translationText: 'Translated text',
      translationLanguageCode: 'en',
    );

    await pumpBubble(
      tester,
      message,
      translationDisplayStyle: TranslationDisplayStyle.translatedOnly,
    );

    expect(find.text('Original text', findRichText: true), findsNothing);
    expect(find.text('Translated text', findRichText: true), findsOneWidget);
    expect(find.byKey(const ValueKey('messageTranslationBlock')), findsNothing);
    final translatedOnly = tester.widget<RichText>(
      find
          .descendant(
            of: find.byKey(const ValueKey('messageTranslatedOnlyText')),
            matching: find.byType(RichText),
          )
          .first,
    );
    expect(
      (translatedOnly.text as TextSpan).style?.color,
      Color.lerp(AppColors.light.bubbleIncomingText, AppTheme.brand, 0.52),
    );

    await pumpBubble(
      tester,
      message,
      translationDisplayStyle: TranslationDisplayStyle.translatedOnly,
      showOriginalTranslationMessageIds: const {901},
    );

    expect(find.text('Original text', findRichText: true), findsOneWidget);
    expect(find.text('Translated text', findRichText: true), findsNothing);
    expect(
      find.byKey(const ValueKey('messageTranslatedOnlyText')),
      findsNothing,
    );

    await pumpBubble(
      tester,
      message,
      translationDisplayStyle: TranslationDisplayStyle.both,
    );

    expect(find.text('Original text', findRichText: true), findsOneWidget);
    expect(find.text('Translated text', findRichText: true), findsOneWidget);
    final bothBlock = tester.widget<Container>(
      find.byKey(const ValueKey('messageTranslationBlock')),
    );
    final border = (bothBlock.decoration! as BoxDecoration).border! as Border;
    expect(border.top.width, 0.5);
    expect(border.left, BorderSide.none);
  });

  testWidgets('mobile selection includes each displayed translation text', (
    tester,
  ) async {
    final selectionKey = GlobalKey<SelectionAreaState>();
    final message = ChatMessage(
      id: 902,
      isOutgoing: false,
      text: 'Original selectable words',
      date: 1,
      contentType: 'messageText',
      translationText: 'Translated selectable words',
      translationLanguageCode: 'en',
    );

    await pumpBubble(
      tester,
      message,
      translationDisplayStyle: TranslationDisplayStyle.both,
      mobileTextSelectionAreaKey: selectionKey,
    );

    final original = tester.renderObject<RenderParagraph>(
      find.text('Original selectable words', findRichText: true),
    );
    final translated = tester.renderObject<RenderParagraph>(
      find.text('Translated selectable words', findRichText: true),
    );
    expect(selectionKey.currentState, isNotNull);
    expect(original.registrar, isNotNull);
    expect(translated.registrar, isNotNull);
  });

  testWidgets('secondary mouse click invokes message action callback', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 100,
      isOutgoing: false,
      text: 'Open message actions',
      date: 1,
    );
    ChatMessage? actionTarget;
    Rect? actionAnchor;

    await pumpBubble(
      tester,
      message,
      onActionMenu: (message, bounds, _) {
        actionTarget = message;
        actionAnchor = bounds;
      },
    );

    final contextGesture = find.descendant(
      of: find.byType(MessageBubble),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is GestureDetector && widget.onSecondaryTapUp != null,
      ),
    );
    expect(contextGesture, findsOneWidget);

    final clickPosition =
        tester.getTopLeft(contextGesture) + const Offset(41, 17);
    await tester.tapAt(
      clickPosition,
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    expect(actionTarget, same(message));
    expect(
      actionAnchor,
      Rect.fromLTWH(clickPosition.dx, clickPosition.dy, 0, 0),
    );
  });

  testWidgets('grouped photo captions render their translation', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 1,
      isOutgoing: false,
      text: 'Original caption',
      date: 1,
      contentType: 'messagePhoto',
      image: TdFileRef(
        id: 101,
        miniThumb: base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      ),
      imageWidth: 600,
      imageHeight: 400,
      translationText: 'Translated caption',
      translationLanguageCode: 'en',
    );

    await pumpBubble(tester, message);

    expect(find.text('Original caption', findRichText: true), findsOneWidget);
    expect(find.text('Translated caption', findRichText: true), findsOneWidget);
    expect(
      find.byKey(const ValueKey('messageTranslationBlock')),
      findsOneWidget,
    );

    // Expire the mocked TDLib image lookup timeout before test teardown.
    await tester.pump(const Duration(minutes: 3, seconds: 1));
  });

  testWidgets('forwarded photos keep attribution above attached comments', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 6,
      isOutgoing: false,
      text: '',
      date: 1,
      contentType: 'messagePhoto',
      image: TdFileRef(
        id: 106,
        miniThumb: base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      ),
      imageWidth: 600,
      imageHeight: 400,
    )..forwardOrigin = 'Original Channel';

    await pumpBubble(
      tester,
      message,
      showCommentAttachment: true,
      channelHasLinkedDiscussion: true,
    );

    final combined = find.byKey(const ValueKey('messageCombinedBubble-6'));
    final header = find.byKey(const ValueKey('messageForwardHeader-6'));
    final comments = find.byKey(const ValueKey('messageCommentsAttachment-6'));
    expect(combined, findsOneWidget);
    expect(header, findsOneWidget);
    expect(find.text('Forwarded from Original Channel'), findsOneWidget);
    expect(find.descendant(of: combined, matching: header), findsOneWidget);
    expect(find.descendant(of: combined, matching: comments), findsOneWidget);
    expect(
      tester.getBottomLeft(header).dy,
      lessThan(tester.getTopLeft(comments).dy),
    );

    // Expire the mocked TDLib image lookup timeout before test teardown.
    await tester.pump(const Duration(minutes: 3, seconds: 1));
  });

  testWidgets('photo replies keep one quote above the media', (tester) async {
    final message =
        ChatMessage(
            id: 7,
            isOutgoing: false,
            text: '',
            date: 1,
            contentType: 'messagePhoto',
            image: TdFileRef(
              id: 107,
              miniThumb: base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
              ),
            ),
            imageWidth: 600,
            imageHeight: 400,
            replyToMessageId: 5,
            replyToDate: 1,
          )
          ..replyToSender = 'Original Channel'
          ..replyToPreview = 'Earlier post';

    final theme = await pumpBubble(tester, message);

    final quote = find.byKey(const ValueKey('messageReplyQuote'));
    final media = find.byType(TDImage);
    expect(quote, findsOneWidget);
    expect(media, findsOneWidget);
    expect(
      (tester.widget<Container>(quote).decoration! as BoxDecoration)
          .borderRadius,
      const BorderRadius.only(
        topRight: Radius.circular(AppRadius.control),
        bottomRight: Radius.circular(AppRadius.control),
      ),
    );
    expect(find.byKey(const ValueKey('messageForwardHeader-7')), findsNothing);
    expect(
      tester.getRect(quote).bottom,
      lessThanOrEqualTo(tester.getRect(media).top),
    );

    message.text = 'Photo caption';
    theme.groupImageMessages = true;
    await tester.pump();

    expect(quote, findsOneWidget);
    expect(find.text('Photo caption', findRichText: true), findsOneWidget);
    expect(
      tester.getRect(quote).bottom,
      lessThanOrEqualTo(tester.getRect(media).top),
    );

    theme.groupImageMessages = false;
    await tester.pump();

    expect(quote, findsOneWidget);
    expect(find.text('Photo caption', findRichText: true), findsOneWidget);
    expect(
      tester.getRect(quote).bottom,
      lessThanOrEqualTo(tester.getRect(media).top),
    );

    // Expire the mocked TDLib image lookup timeout before test teardown.
    await tester.pump(const Duration(minutes: 3, seconds: 1));
  });

  testWidgets('document captions render their translation', (tester) async {
    final message = ChatMessage(
      id: 2,
      isOutgoing: false,
      text: 'Document caption',
      date: 1,
      contentType: 'messageDocument',
      document: MessageDocument(
        fileName: 'report.pdf',
        size: 1024,
        ext: 'PDF',
        file: null,
      ),
      translationText: 'Translated document caption',
      translationLanguageCode: 'en',
    );

    await pumpBubble(tester, message);

    expect(find.text('Document caption', findRichText: true), findsOneWidget);
    expect(
      find.text('Translated document caption', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('messageTranslationBlock')),
      findsOneWidget,
    );
  });

  testWidgets('document cards use directional Android message colors', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 427,
      isOutgoing: true,
      text: 'Document link',
      date: 1,
      contentType: 'messageDocument',
      textEntities: const [
        MessageTextEntity(
          offset: 9,
          length: 4,
          type: 'textEntityTypeTextUrl',
          url: 'https://example.com',
        ),
      ],
      document: MessageDocument(
        fileName: 'themed.pdf',
        size: 1024,
        ext: 'PDF',
        file: null,
      ),
    );
    const bubble = Color(0xFF234567);
    const foreground = Color(0xFFF5F7FA);

    await pumpBubble(
      tester,
      message,
      outgoingBubbleColor: bubble,
      outgoingBubbleTextColor: foreground,
      messageColors: messageColors,
    );

    final card = find.byKey(const ValueKey('messageDocumentAlbumCard-427'));
    final decoration =
        tester.widget<Container>(card).decoration! as BoxDecoration;
    expect(decoration.color, bubble);
    expect(decoration.border, isNull);
    expect(
      tester.widget<Text>(find.text('themed.pdf')).style?.color,
      foreground,
    );
    final spans = tester
        .widgetList<RichText>(
          find.descendant(of: card, matching: find.byType(RichText)),
        )
        .expand((widget) => _textSpans(widget.text));
    expect(
      spans.singleWhere((span) => span.text == 'link').style?.color,
      messageColors.outgoingLink,
    );
  });

  testWidgets('document cards expand to the standard message width', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 3,
      isOutgoing: false,
      text: '',
      date: 1,
      contentType: 'messageDocument',
      document: MessageDocument(
        fileName: 'archive.ipa',
        size: 1024,
        ext: 'IPA',
        file: null,
      ),
    );

    await pumpBubble(tester, message);

    final card = find.byKey(const ValueKey('messageDocumentAlbumCard-3'));
    final bubble = find.byType(MessageBubble);
    expect(
      tester.getSize(card).width,
      moreOrLessEquals(tester.getSize(bubble).width * 0.75),
    );
    expect(tester.getSize(card).width, greaterThan(244));

    final fileIcon = find.byKey(const ValueKey('documentFileIcon-3'));
    expect(fileIcon, findsOneWidget);
    final glyph = tester.widget<AppIcon>(
      find.descendant(of: fileIcon, matching: find.byType(AppIcon)).first,
    );
    expect(glyph.icon.data, HeroAppIcons.solidFile.data);
    expect(glyph.color, DocumentFilePalette.green.color);
    expect(
      find.descendant(of: fileIcon, matching: find.text('ipa')),
      findsOneWidget,
    );
  });

  testWidgets('message links have no generated underline', (tester) async {
    const text = 'site https://example.com manual';
    final message = ChatMessage(
      id: 4,
      isOutgoing: false,
      text: text,
      date: 1,
      contentType: 'messageText',
      textEntities: const [
        MessageTextEntity(
          offset: 0,
          length: 4,
          type: 'textEntityTypeTextUrl',
          url: 'https://example.com/site',
        ),
        MessageTextEntity(
          offset: 25,
          length: 6,
          type: 'textEntityTypeUnderline',
        ),
      ],
    );

    await pumpBubble(tester, message);

    final textBubble = find.byKey(const ValueKey('messageTextBubble-4'));
    final richText = tester
        .widgetList<RichText>(
          find.descendant(of: textBubble, matching: find.byType(RichText)),
        )
        .firstWhere((widget) => widget.text.toPlainText().contains(text));
    final spans = _textSpans(richText.text).toList();
    final entityLink = spans.singleWhere((span) => span.text == 'site');
    final autoLink = spans.singleWhere(
      (span) => span.text == 'https://example.com',
    );
    final explicitUnderline = spans.singleWhere(
      (span) => span.text == 'manual',
    );

    expect(entityLink.style?.decoration, isNot(TextDecoration.underline));
    expect(autoLink.style?.decoration, isNot(TextDecoration.underline));
    expect(explicitUnderline.style?.decoration, TextDecoration.underline);
  });

  testWidgets('incoming message surfaces use Android theme colors', (
    tester,
  ) async {
    const text = 'body link\nquote';
    final message = ChatMessage(
      id: 420,
      isOutgoing: false,
      text: text,
      date: 1,
      contentType: 'messageText',
      textEntities: const [
        MessageTextEntity(
          offset: 5,
          length: 4,
          type: 'textEntityTypeTextUrl',
          url: 'https://example.com',
        ),
        MessageTextEntity(
          offset: 10,
          length: 5,
          type: 'textEntityTypeExpandableBlockQuote',
        ),
        MessageTextEntity(
          offset: 10,
          length: 5,
          type: 'textEntityTypeTextUrl',
          url: 'https://example.com/quote',
        ),
      ],
    );
    const bubble = Color(0xFFE8F1FA);
    const foreground = Color(0xFF18212A);

    await pumpBubble(
      tester,
      message,
      incomingBubbleColor: bubble,
      incomingBubbleTextColor: foreground,
      messageColors: messageColors,
    );

    final textBubble = find.byKey(const ValueKey('messageTextBubble-420'));
    final background = tester.widget<StretchableMessageBubbleBackground>(
      textBubble,
    );
    expect(background.fallbackColor, bubble);
    expect(background.fallbackBorder, isNull);

    final spans = tester
        .widgetList<RichText>(
          find.descendant(of: textBubble, matching: find.byType(RichText)),
        )
        .expand((widget) => _textSpans(widget.text))
        .toList();
    expect(
      spans.singleWhere((span) => span.text == 'link').style?.color,
      messageColors.incomingLink,
    );
    expect(
      spans.singleWhere((span) => span.text == 'quote').style?.color,
      messageColors.incomingQuote,
    );
    final body = tester
        .widgetList<RichText>(
          find.descendant(of: textBubble, matching: find.byType(RichText)),
        )
        .firstWhere((widget) => widget.text.toPlainText().contains('body'));
    expect(body.text.style?.color, foreground);

    final quote = tester.widget<Container>(
      find.byKey(const ValueKey('messageBlockQuote-420-10:5')),
    );
    final decoration = quote.decoration! as BoxDecoration;
    expect(
      decoration.color,
      messageColors.incomingQuote.withValues(alpha: 0.10),
    );
    expect(
      (decoration.border! as Border).left.color,
      messageColors.incomingQuote,
    );
    expect(
      tester
          .widget<Text>(
            find.text(AppStrings.t(AppStringKeys.messageBubbleExpandQuote)),
          )
          .style
          ?.color,
      messageColors.incomingQuote,
    );
    final paintedBackground = Color.alphaBlend(decoration.color!, bubble);
    final lighter = math.max(
      foreground.computeLuminance(),
      paintedBackground.computeLuminance(),
    );
    final darker = math.min(
      foreground.computeLuminance(),
      paintedBackground.computeLuminance(),
    );
    expect((lighter + 0.05) / (darker + 0.05), greaterThanOrEqualTo(4.5));
  });

  testWidgets('structured block quotes use Android theme colors', (
    tester,
  ) async {
    const quoteText = 'Rich link';
    final message = ChatMessage(
      id: 423,
      isOutgoing: false,
      text: '',
      date: 1,
      contentType: 'messageRichMessage',
      richBlocks: const [
        RichMessageBlock.container(
          kind: RichMessageBlockKind.blockQuote,
          children: [
            RichMessageBlock.text(
              kind: RichMessageBlockKind.paragraph,
              text: quoteText,
              entities: [
                MessageTextEntity(
                  offset: 5,
                  length: 4,
                  type: 'textEntityTypeTextUrl',
                  url: 'https://example.com',
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await pumpBubble(tester, message, messageColors: messageColors);

    final block = find.byKey(const ValueKey('rich-message-block-0-blockQuote'));
    final quote = find.descendant(
      of: block,
      matching: find.byWidgetPredicate((widget) {
        if (widget case Container(decoration: final BoxDecoration decoration)) {
          final border = decoration.border;
          return border is Border &&
              border.left.width == 3 &&
              border.left.color == messageColors.incomingQuote;
        }
        return false;
      }),
    );
    expect(quote, findsOneWidget);
    final decoration =
        tester.widget<Container>(quote).decoration! as BoxDecoration;
    expect(
      decoration.color,
      messageColors.incomingQuote.withValues(alpha: 0.10),
    );
    final spans = tester
        .widgetList<RichText>(
          find.descendant(of: quote, matching: find.byType(RichText)),
        )
        .expand((widget) => _textSpans(widget.text));
    expect(
      spans.singleWhere((span) => span.text == 'link').style?.color,
      messageColors.incomingQuote,
    );
  });

  testWidgets('outgoing message surfaces use Android theme colors', (
    tester,
  ) async {
    const text = 'body link\nquote';
    final message =
        ChatMessage(
            id: 421,
            isOutgoing: true,
            text: text,
            date: 1,
            contentType: 'messageText',
            replyToMessageId: 8,
            replyToDate: 1,
            isEdited: true,
            linkPreview: const MessageLinkPreview(
              url: 'https://example.com',
              displayUrl: 'example.com',
              siteName: 'Outgoing site',
              title: 'Outgoing preview',
              description: 'Outgoing preview body',
            ),
            textEntities: const [
              MessageTextEntity(
                offset: 5,
                length: 4,
                type: 'textEntityTypeTextUrl',
                url: 'https://example.com',
              ),
              MessageTextEntity(
                offset: 10,
                length: 5,
                type: 'textEntityTypeBlockQuote',
              ),
              MessageTextEntity(
                offset: 10,
                length: 5,
                type: 'textEntityTypeTextUrl',
                url: 'https://example.com/quote',
              ),
            ],
          )
          ..forwardOrigin = 'Outgoing Channel'
          ..replyToSender = 'Outgoing sender'
          ..replyToPreview = 'Outgoing earlier message';
    const bubble = Color(0xFF234567);
    const foreground = Color(0xFFF5F7FA);

    await pumpBubble(
      tester,
      message,
      outgoingBubbleColor: bubble,
      outgoingBubbleTextColor: foreground,
      messageColors: messageColors,
    );

    final textBubble = find.byKey(const ValueKey('messageTextBubble-421'));
    final background = tester.widget<StretchableMessageBubbleBackground>(
      textBubble,
    );
    expect(background.fallbackColor, bubble);

    final spans = tester
        .widgetList<RichText>(
          find.descendant(of: textBubble, matching: find.byType(RichText)),
        )
        .expand((widget) => _textSpans(widget.text))
        .toList();
    expect(
      spans.singleWhere((span) => span.text == 'link').style?.color,
      messageColors.outgoingLink,
    );
    expect(
      spans.singleWhere((span) => span.text == 'quote').style?.color,
      messageColors.outgoingLink,
    );
    final body = tester
        .widgetList<RichText>(
          find.descendant(of: textBubble, matching: find.byType(RichText)),
        )
        .firstWhere((widget) => widget.text.toPlainText().contains('body'));
    expect(body.text.style?.color, foreground);

    final quote = tester.widget<Container>(
      find.byKey(const ValueKey('messageBlockQuote-421-10:5')),
    );
    final decoration = quote.decoration! as BoxDecoration;
    expect(
      decoration.color,
      messageColors.outgoingQuote.withValues(alpha: 0.10),
    );
    expect(
      (decoration.border! as Border).left.color,
      messageColors.outgoingQuote,
    );

    expect(
      tester
          .widget<Text>(find.text('Forwarded from Outgoing Channel'))
          .style
          ?.color,
      messageColors.outgoingForwardedName,
    );
    final reply = find.byKey(const ValueKey('messageReplyQuote'));
    final replyDecoration =
        tester.widget<Container>(reply).decoration! as BoxDecoration;
    expect(
      replyDecoration.color,
      messageColors.outgoingReplyLine.withValues(alpha: 0.10),
    );
    expect(
      (replyDecoration.border! as Border).left.color,
      messageColors.outgoingReplyLine,
    );
    expect(
      tester.widget<Text>(find.text('Outgoing earlier message')).style?.color,
      messageColors.outgoingReplyText,
    );
    expect(
      tester
          .widgetList<Text>(
            find.descendant(of: reply, matching: find.byType(Text)),
          )
          .firstWhere((text) => text.textSpan != null)
          .style
          ?.color,
      messageColors.outgoingReplyName,
    );
    expect(
      tester
          .widget<AppIcon>(find.byKey(const ValueKey('messageDeliveryEdited')))
          .color,
      messageColors.outgoingTime,
    );
    final previewDecoration =
        tester
                .widget<Container>(
                  find.byKey(const ValueKey('messageLinkPreviewCard-421')),
                )
                .decoration!
            as BoxDecoration;
    expect(
      previewDecoration.color,
      messageColors.outgoingPreviewLine.withValues(alpha: 0.10),
    );
    expect(
      (previewDecoration.border! as Border).left.color,
      messageColors.outgoingPreviewLine,
    );
    expect(
      tester.widget<Text>(find.text('Outgoing site')).style?.color,
      messageColors.outgoingSiteName,
    );
  });

  testWidgets('standalone bubbles inherit the installed cloud theme', (
    tester,
  ) async {
    const cloudTheme = TelegramCloudTheme(
      slug: 'standalone-message-colors',
      rawTitle: 'Standalone message colors',
      baseTheme: 'builtInThemeDay',
      accentColorValue: 0x224466,
      outgoingColors: [0x315273],
      palette: {
        'chat_messageTextOut': 0xF7F8F9,
        'chat_messageLinkOut': 0xE8C45A,
      },
    );
    const text = 'body link';
    final message = ChatMessage(
      id: 423,
      isOutgoing: true,
      text: text,
      date: 1,
      contentType: 'messageText',
      textEntities: const [
        MessageTextEntity(
          offset: 5,
          length: 4,
          type: 'textEntityTypeTextUrl',
          url: 'https://example.com',
        ),
      ],
    );

    await pumpBubble(tester, message, cloudTheme: cloudTheme);

    final textBubble = find.byKey(const ValueKey('messageTextBubble-423'));
    expect(
      tester
          .widget<StretchableMessageBubbleBackground>(textBubble)
          .fallbackColor,
      const Color(0xFF315273),
    );
    final richText = tester
        .widgetList<RichText>(
          find.descendant(of: textBubble, matching: find.byType(RichText)),
        )
        .firstWhere((widget) => widget.text.toPlainText().contains(text));
    expect(richText.text.style?.color, const Color(0xFFF7F8F9));
    expect(
      _textSpans(
        richText.text,
      ).singleWhere((span) => span.text == 'link').style?.color,
      const Color(0xFFE8C45A),
    );
  });

  testWidgets('decorative bubbles retain their owned foreground palette', (
    tester,
  ) async {
    const text = 'link\nquote';
    final message = ChatMessage(
      id: 424,
      isOutgoing: true,
      text: text,
      date: 1,
      contentType: 'messageText',
      textEntities: const [
        MessageTextEntity(
          offset: 0,
          length: 4,
          type: 'textEntityTypeTextUrl',
          url: 'https://example.com',
        ),
        MessageTextEntity(
          offset: 5,
          length: 5,
          type: 'textEntityTypeBlockQuote',
        ),
      ],
    );

    await pumpBubble(
      tester,
      message,
      messageColors: messageColors,
      bubbleBackground: MessageBubbleBackground.midnightAurora,
    );

    final textBubble = find.byKey(const ValueKey('messageTextBubble-424'));
    final spans = tester
        .widgetList<RichText>(
          find.descendant(of: textBubble, matching: find.byType(RichText)),
        )
        .expand((widget) => _textSpans(widget.text))
        .toList();
    expect(
      spans.singleWhere((span) => span.text == 'link').style?.color,
      MessageBubbleBackgroundSpec.midnightAurora.foregroundColor,
    );
    final quote = tester.widget<Container>(
      find.byKey(const ValueKey('messageBlockQuote-424-5:5')),
    );
    expect(
      ((quote.decoration! as BoxDecoration).border! as Border).left.color,
      MessageBubbleBackgroundSpec.midnightAurora.foregroundColor,
    );
  });

  testWidgets('reply, forward, and metadata use Android theme colors', (
    tester,
  ) async {
    const incomingMessageText = Color(0xFF192A3B);
    final message =
        ChatMessage(
            id: 422,
            isOutgoing: false,
            text: 'Body',
            date: 1,
            contentType: 'messageText',
            replyToMessageId: 7,
            replyToDate: 1,
            replyToImage: TdFileRef(
              id: 1422,
              miniThumb: base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
              ),
            ),
            isEdited: true,
            linkPreview: const MessageLinkPreview(
              url: 'https://example.com',
              displayUrl: 'example.com',
              siteName: 'Example site',
              title: 'Preview title',
              description: 'Preview body',
            ),
          )
          ..forwardOrigin = 'Original Channel'
          ..replyToSender = 'Sender'
          ..replyToPreview = 'Earlier message';

    await pumpBubble(
      tester,
      message,
      incomingBubbleTextColor: incomingMessageText,
      messageColors: messageColors,
    );

    final forwardHeader = find.byKey(
      const ValueKey('messageForwardHeader-422'),
    );
    final forwardText = tester.widget<Text>(
      find.descendant(
        of: forwardHeader,
        matching: find.text('Forwarded from Original Channel'),
      ),
    );
    expect(forwardText.style?.color, messageColors.incomingForwardedName);

    final reply = find.byKey(const ValueKey('messageReplyQuote'));
    final replyDecoration =
        tester.widget<Container>(reply).decoration! as BoxDecoration;
    expect(
      replyDecoration.color,
      messageColors.incomingReplyLine.withValues(alpha: 0.10),
    );
    expect(
      (replyDecoration.border! as Border).left.color,
      messageColors.incomingReplyLine,
    );
    expect(
      tester.widget<Text>(find.text('Earlier message')).style?.color,
      messageColors.incomingReplyText,
    );
    final replyLabels = tester.widgetList<Text>(
      find.descendant(of: reply, matching: find.byType(Text)),
    );
    expect(
      replyLabels.firstWhere((text) => text.textSpan != null).style?.color,
      messageColors.incomingReplyName,
    );

    final edited = tester.widget<AppIcon>(
      find.byKey(const ValueKey('messageDeliveryEdited')),
    );
    expect(edited.color, messageColors.incomingTime);

    final preview = tester.widget<Container>(
      find.byKey(const ValueKey('messageLinkPreviewCard-422')),
    );
    final previewDecoration = preview.decoration! as BoxDecoration;
    expect(
      previewDecoration.color,
      messageColors.incomingPreviewLine.withValues(
        alpha: messageColors.incomingPreviewLine.a * 0.10,
      ),
    );
    expect(
      (previewDecoration.border! as Border).left.color,
      messageColors.incomingPreviewLine,
    );
    expect(
      tester.widget<Text>(find.text('Example site')).style?.color,
      messageColors.incomingSiteName,
    );
    expect(
      tester.widget<Text>(find.text('Preview title')).style?.color,
      incomingMessageText,
    );

    // Expire the mocked TDLib image lookup timeout before test teardown.
    await tester.pump(const Duration(minutes: 3, seconds: 1));
  });

  testWidgets('media-only replies use Android media reply text color', (
    tester,
  ) async {
    final message =
        ChatMessage(
            id: 425,
            isOutgoing: false,
            text: 'Body',
            date: 1,
            contentType: 'messageText',
            replyToMessageId: 9,
            replyToDate: 1,
            replyToImage: TdFileRef(
              id: 1425,
              miniThumb: base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
              ),
            ),
          )
          ..replyToSender = 'Media sender'
          ..replyToPreview = '';

    await pumpBubble(tester, message, messageColors: messageColors);

    final openOriginal = find.byKey(const ValueKey('messageReplyOpenOriginal'));
    expect(
      tester
          .widget<AppIcon>(
            find.descendant(of: openOriginal, matching: find.byType(AppIcon)),
          )
          .color,
      messageColors.incomingReplyMediaText,
    );

    // Expire the mocked TDLib image lookup timeout before test teardown.
    await tester.pump(const Duration(minutes: 3, seconds: 1));
  });

  testWidgets('block quotes stay readable when search fill is dark', (
    tester,
  ) async {
    const text = 'Quoted copy';
    final colors = AppColors.light.copyWith(
      searchFill: Colors.black,
      bubbleIncoming: Colors.white,
      bubbleIncomingText: const Color(0xFF1A1A1A),
    );
    const disabledCloudTheme = TelegramCloudTheme(
      slug: 'disabled-cloud-theme',
      rawTitle: 'Disabled Cloud Theme',
      baseTheme: 'builtInThemeDay',
      accentColorValue: 0xFFFF00FF,
      outgoingColors: [0xFF112233],
      palette: {
        'chat_inBubble': 0xFF334455,
        'chat_messageTextIn': 0xFF556677,
        'chat_messageLinkIn': 0xFF778899,
      },
    );
    final message = ChatMessage(
      id: 42,
      isOutgoing: false,
      text: text,
      date: 1,
      contentType: 'messageText',
      textEntities: const [
        MessageTextEntity(
          offset: 0,
          length: text.length,
          type: 'textEntityTypeBlockQuote',
        ),
        MessageTextEntity(
          offset: 0,
          length: text.length,
          type: 'textEntityTypeTextUrl',
          url: 'https://example.com',
        ),
      ],
    );

    await pumpBubble(
      tester,
      message,
      colors: colors,
      themingEnabled: false,
      messageColors: messageColors,
      cloudTheme: disabledCloudTheme,
    );

    final textBubble = find.byKey(const ValueKey('messageTextBubble-42'));
    final bubble = tester.widget<StretchableMessageBubbleBackground>(
      textBubble,
    );
    expect(bubble.fallbackColor, colors.bubbleIncoming);
    final quote = find.descendant(
      of: textBubble,
      matching: find.byWidgetPredicate((widget) {
        if (widget case Container(decoration: final BoxDecoration decoration)) {
          final border = decoration.border;
          return border is Border &&
              border.left.width == 3 &&
              border.left.color == AppTheme.brand;
        }
        return false;
      }),
    );
    expect(quote, findsOneWidget);
    final decoration =
        tester.widget<Container>(quote).decoration! as BoxDecoration;
    final paintedBackground = Color.alphaBlend(
      decoration.color!,
      colors.bubbleIncoming,
    );

    double contrast(Color first, Color second) {
      final lighter = math.max(
        first.computeLuminance(),
        second.computeLuminance(),
      );
      final darker = math.min(
        first.computeLuminance(),
        second.computeLuminance(),
      );
      return (lighter + 0.05) / (darker + 0.05);
    }

    expect(decoration.color, colors.bubbleIncomingText.withValues(alpha: 0.07));
    final quoteText = tester.widget<RichText>(
      find.descendant(of: quote, matching: find.byType(RichText)),
    );
    final expectedLinkStyle = readableLinkStyle(
      background: colors.bubbleIncoming,
      body: colors.bubbleIncomingText,
      preferred: colors.linkBlue,
    );
    final renderedLink = _textSpans(
      quoteText.text,
    ).singleWhere((span) => span.text == text);
    expect(renderedLink.style?.color, expectedLinkStyle.color);
    expect(
      renderedLink.style?.decoration?.contains(TextDecoration.underline) ??
          false,
      expectedLinkStyle.underline,
    );
    expect(
      contrast(colors.bubbleIncomingText, paintedBackground),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets('message custom emoji does not leak through a spoiler', (
    tester,
  ) async {
    const text = '🙂';
    final message = ChatMessage(
      id: 41,
      isOutgoing: false,
      text: text,
      date: 1,
      contentType: 'messageText',
      textEntities: const [
        MessageTextEntity(offset: 0, length: 2, type: 'textEntityTypeSpoiler'),
        MessageTextEntity(
          offset: 0,
          length: 2,
          type: 'textEntityTypeCustomEmoji',
          customEmojiId: 123,
        ),
      ],
    );

    await pumpBubble(tester, message);
    expect(find.byType(CustomEmojiView), findsNothing);
    final spoiler = tester
        .widgetList<RichText>(find.byType(RichText))
        .expand((widget) => _textSpans(widget.text))
        .singleWhere((span) => span.text == text);
    (spoiler.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pump();

    expect(find.byType(CustomEmojiView), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('mobile message selection preserves custom emoji fallback text', (
    tester,
  ) async {
    const text = 'A🙂B';
    final selectionKey = GlobalKey<SelectionAreaState>();
    String? selectedText;
    final message = ChatMessage(
      id: 42,
      isOutgoing: false,
      text: text,
      date: 1,
      contentType: 'messageText',
      textEntities: const [
        MessageTextEntity(
          offset: 1,
          length: 2,
          type: 'textEntityTypeCustomEmoji',
          customEmojiId: 456,
        ),
      ],
    );

    await pumpBubble(
      tester,
      message,
      mobileTextSelectionAreaKey: selectionKey,
      onMobileTextSelectionChanged: (content) {
        selectedText = content?.plainText;
      },
    );
    selectionKey.currentState!.selectableRegion.selectAll(
      SelectionChangedCause.toolbar,
    );
    await tester.pump();

    expect(selectedText, text);
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('document albums render as one bubble with one shared caption', (
    tester,
  ) async {
    final first =
        ChatMessage(
            id: 10,
            isOutgoing: false,
            text: '',
            date: 1,
            contentType: 'messageDocument',
            mediaAlbumId: 99,
            commentCount: 420,
            document: MessageDocument(
              fileName: 'first.deb',
              size: 1024 * 1024,
              ext: 'DEB',
              file: null,
            ),
          )
          ..reactions = const [
            MessageReaction(emoji: '❤️', count: 50, chosen: false),
          ];
    final second = ChatMessage(
      id: 11,
      isOutgoing: false,
      text: 'One caption for both files',
      date: 1,
      contentType: 'messageDocument',
      mediaAlbumId: 99,
      translationText: 'Translated album caption',
      translationLanguageCode: 'en',
      document: MessageDocument(
        fileName: 'second.dylib',
        size: 3 * 1024 * 1024,
        ext: 'DYLIB',
        file: null,
      ),
    );

    ChatMessage? longPressed;
    await pumpBubble(
      tester,
      first,
      groupedMedia: [first, second],
      showCommentAttachment: true,
      onLongPress: (message) => longPressed = message,
    );

    expect(find.byKey(const ValueKey('messageTapTarget-10')), findsOneWidget);
    expect(find.byKey(const ValueKey('messageTapTarget-11')), findsNothing);
    expect(find.text('first.deb'), findsOneWidget);
    expect(find.text('second.dylib'), findsOneWidget);
    expect(
      find.text('One caption for both files', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.text('Translated album caption', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('420 comments'), findsOneWidget);
    expect(find.text('❤️'), findsOneWidget);

    final albumFinder = find.byKey(
      const ValueKey('messageDocumentAlbumCard-10'),
    );
    final commentsFinder = find.byKey(
      const ValueKey('messageCommentsAttachment-10'),
    );
    final combinedFinder = find.byKey(
      const ValueKey('messageCombinedBubble-10'),
    );
    final album = tester.widget<Container>(albumFinder);
    final albumRadius =
        (album.decoration! as BoxDecoration).borderRadius! as BorderRadius;
    expect(
      tester.getRect(commentsFinder).top,
      tester.getRect(albumFinder).bottom,
    );
    expect(albumRadius.bottomLeft, isNot(Radius.zero));
    expect(
      tester
          .getRect(combinedFinder)
          .contains(tester.getRect(albumFinder).center),
      isTrue,
    );
    expect(
      tester
          .getRect(combinedFinder)
          .contains(tester.getRect(commentsFinder).center),
      isTrue,
    );

    await tester.longPress(
      find.byKey(const ValueKey('messageDocumentAlbumFile-11')),
    );
    expect(longPressed?.id, 11);
  });

  testWidgets('comments render inside one rounded message surface', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 12,
      isOutgoing: false,
      text: 'Channel post',
      date: 1,
      contentType: 'messageText',
      commentCount: 108,
    );

    await pumpBubble(tester, message, showCommentAttachment: true);

    final mainFinder = find.byKey(const ValueKey('messageTextBubble-12'));
    final commentsFinder = find.byKey(
      const ValueKey('messageCommentsAttachment-12'),
    );
    final combinedFinder = find.byKey(
      const ValueKey('messageCombinedBubble-12'),
    );
    final main = tester.widget<Container>(mainFinder);
    final comments = tester.widget<Container>(commentsFinder);
    final combined = tester.widget<StretchableMessageBubbleBackground>(
      combinedFinder,
    );
    final commentsDecoration = comments.decoration! as BoxDecoration;

    expect(
      tester.getRect(commentsFinder).top,
      tester.getRect(mainFinder).bottom,
    );
    expect(main.decoration, isNull);
    expect(commentsDecoration.color, isNull);
    expect(commentsDecoration.borderRadius, isNull);
    expect((commentsDecoration.border! as Border).top.width, 0.5);
    expect(combined.fallbackBorderRadius, BorderRadius.circular(12));
    expect(
      tester
          .getRect(combinedFinder)
          .contains(tester.getRect(commentsFinder).bottomCenter),
      isTrue,
    );
  });

  testWidgets('normal group replies use only the compact bottom-right count', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final message = ChatMessage(
      id: 121,
      isOutgoing: false,
      text: 'Group message',
      date: 1,
      contentType: 'messageText',
      hasCommentThread: true,
      commentCount: 7,
    );

    ChatMessage? opened;
    await pumpBubble(
      tester,
      message,
      isGroup: true,
      onOpenComments: (message) => opened = message,
    );

    expect(
      find.byKey(const ValueKey('messageCommentsAttachment-121')),
      findsNothing,
    );
    expect(find.text('7 comments'), findsNothing);
    final compact = find.byKey(const ValueKey('messageCompactReplies-121'));
    expect(compact, findsOneWidget);
    expect(
      find.descendant(of: compact, matching: find.text('7')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(compact);
    expect(opened, same(message));
  });

  testWidgets('linked channel discussion stays visible before first comment', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 13,
      isOutgoing: false,
      text: 'Channel post',
      date: 1,
      contentType: 'messageText',
    );

    await pumpBubble(
      tester,
      message,
      showCommentAttachment: true,
      channelHasLinkedDiscussion: true,
    );

    expect(
      find.byKey(const ValueKey('messageCommentsAttachment-13')),
      findsOneWidget,
    );
    expect(find.text('Leave a comment'), findsOneWidget);
    final messageFinder = find.byKey(const ValueKey('messageTextBubble-13'));
    final commentsFinder = find.byKey(
      const ValueKey('messageCommentsAttachment-13'),
    );
    expect(
      tester.getRect(commentsFinder).width,
      tester.getRect(messageFinder).width,
    );
    final commentRow = tester.widget<Row>(
      find.descendant(of: commentsFinder, matching: find.byType(Row)),
    );
    expect(commentRow.mainAxisSize, MainAxisSize.max);
    expect(
      find.descendant(of: commentsFinder, matching: find.byType(Expanded)),
      findsOneWidget,
    );
    final combinedFinder = find.byKey(
      const ValueKey('messageCombinedBubble-13'),
    );
    final expectedBackground = tester
        .element(messageFinder)
        .colors
        .bubbleIncoming;
    final combined = tester.widget<StretchableMessageBubbleBackground>(
      combinedFinder,
    );
    expect(combined.fallbackColor, expectedBackground);
    expect(
      tester
          .getRect(combinedFinder)
          .contains(tester.getRect(commentsFinder).center),
      isTrue,
    );
  });

  testWidgets('decorative comments paint one center-sliced message surface', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 131,
      isOutgoing: false,
      text: 'One decorated message',
      date: 1,
      contentType: 'messageText',
      commentCount: 3,
    );

    final theme = await pumpBubble(
      tester,
      message,
      showCommentAttachment: true,
    );
    theme.messageBubbleBackground = MessageBubbleBackground.forestFamiliar;
    await tester.pumpAndSettle();

    final combinedFinder = find.byKey(
      const ValueKey('messageCombinedBubble-131'),
    );
    final combined = tester.widget<StretchableMessageBubbleBackground>(
      combinedFinder,
    );
    expect(
      combined.background.selection,
      MessageBubbleBackground.forestFamiliar,
    );
    expect(combined.background.centerSlice, const Rect.fromLTWH(24, 18, 1, 1));
    expect(
      tester
          .widget<Container>(
            find.byKey(const ValueKey('messageTextBubble-131')),
          )
          .decoration,
      isNull,
    );
    expect(
      find.descendant(
        of: combinedFinder,
        matching: find.byType(StretchableMessageBubbleBackground),
      ),
      findsNothing,
    );
  });

  testWidgets('outgoing bubble stays white on blue when theming is off', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 14,
      isOutgoing: true,
      text: 'Own message',
      date: 1,
      contentType: 'messageText',
    );

    await pumpBubble(tester, message, themingEnabled: false);

    final richText = tester.widget<RichText>(
      find.descendant(
        of: find.byKey(const ValueKey('messageTextBubble-14')),
        matching: find.byType(RichText),
      ),
    );
    expect(richText.text.style?.color, AppTheme.bubbleOutgoingText);
  });

  testWidgets('captionless media labels never render as captions', (
    tester,
  ) async {
    final message = TDParse.message({
      '@type': 'message',
      'id': 20,
      'date': 1,
      'content': {
        '@type': 'messageVideo',
        'caption': {'@type': 'formattedText', 'text': ''},
        'video': {
          '@type': 'video',
          'duration': 48,
          'width': 320,
          'height': 180,
          'video': {'@type': 'file', 'id': 201},
        },
      },
    });

    expect(message, isNotNull);
    expect(message!.text, isEmpty);
    await pumpBubble(tester, message);

    expect(find.text('Video', findRichText: true), findsNothing);
  });

  testWidgets('a real caption equal to a media label still renders', (
    tester,
  ) async {
    final message = TDParse.message({
      '@type': 'message',
      'id': 21,
      'date': 1,
      'content': {
        '@type': 'messageVideo',
        'caption': {'@type': 'formattedText', 'text': 'Video'},
        'video': {
          '@type': 'video',
          'duration': 48,
          'width': 320,
          'height': 180,
          'video': {'@type': 'file', 'id': 202},
        },
      },
    });

    expect(message, isNotNull);
    await pumpBubble(tester, message!);

    expect(find.text('Video', findRichText: true), findsOneWidget);
  });
}
