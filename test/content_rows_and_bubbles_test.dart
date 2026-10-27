import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/channels/topic_list_row.dart';
import 'package:mithka/channels/topic_navigation.dart';
import 'package:mithka/chat/custom_emoji.dart';
import 'package:mithka/chat/image_media_album_bubble.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/chats/chat_folder_tag_controller.dart';
import 'package:mithka/chats/chat_row_metrics.dart';
import 'package:mithka/chats/chat_row_view.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/content_size_preview.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/content_size.dart';
import 'package:mithka/theme/date_text.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _sizes = [...contentSizePresets, 1.47, 2.0];

void main() {
  Future<ThemeController> theme() async {
    SharedPreferences.setMockInitialValues({});
    final result = ThemeController(await SharedPreferences.getInstance());
    addTearDown(result.dispose);
    return result;
  }

  Widget harness(
    ThemeController theme,
    Widget child,
    double scale, {
    double osScale = 1,
    TextDirection direction = TextDirection.ltr,
  }) => ChangeNotifierProvider<ThemeController>.value(
    value: theme,
    child: MaterialApp(
      theme: ThemeData(extensions: [AppColors.light]),
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizations.delegate],
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(osScale)),
        child: Directionality(
          textDirection: direction,
          child: ContentSizeRoot(
            appScale: scale,
            child: Scaffold(body: SingleChildScrollView(child: child)),
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'rows agree with scroll extent at every preset, custom and OS size',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final controller = await theme();
        final chat = ChatSummary(
          id: 7,
          title: '长标题 A long fictional conversation 👋',
          lastMessage: 'Preview 预览 with a long message',
          lastMessageId: 1,
          date: 1600000000,
          unreadCount: 4,
          order: 1,
          isMuted: false,
        );
        for (final direction in TextDirection.values) {
          for (final osScale in [1.0, 2.0]) {
            double previous = 0;
            for (final scale in [..._sizes]..sort()) {
              late double extent;
              late bool timeBelow;
              await tester.pumpWidget(
                harness(
                  controller,
                  SizedBox(
                    width: 320,
                    child: ChatRowWidth(
                      width: 320,
                      child: Builder(
                        builder: (context) {
                          extent = chatRowMetricsFor(context, chat).extent;
                          timeBelow = chatRowMetricsFor(
                            context,
                            chat,
                          ).timeBelow;
                          return Column(
                            children: [
                              const Text(
                                'Navigation',
                                key: ValueKey('navigation'),
                              ),
                              ChatRowView(
                                chat: chat,
                                key: const ValueKey('row'),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  scale,
                  osScale: osScale,
                  direction: direction,
                ),
              );
              await tester.pump();
              expect(
                tester.getSize(find.byKey(const ValueKey('row'))).height,
                extent,
              );
              expect(extent, greaterThanOrEqualTo(previous));
              if (osScale == 2) expect(extent, greaterThan(72 * scale));
              previous = extent;
              expect(
                tester.widget<PhotoAvatar>(find.byType(PhotoAvatar)).size,
                48 * scale,
              );
              final navContext = tester.element(
                find.byKey(const ValueKey('navigation')),
              );
              expect(
                MediaQuery.textScalerOf(navContext).scale(12),
                12 * osScale,
              );
              if (timeBelow) {
                expect(
                  tester
                      .getTopLeft(find.text(DateText.listLabel(chat.date)))
                      .dy,
                  greaterThan(tester.getTopLeft(find.text(chat.title)).dy),
                );
              }
              expect(tester.takeException(), isNull);
            }
          }
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'touch row pitch matches actual, synthetic and scroll estimates',
    (tester) async {
      final controller = await theme();
      final chat = ChatSummary(
        id: 70,
        title: 'Conversation',
        lastMessage: 'Preview',
        lastMessageId: 1,
        date: 0,
        unreadCount: 0,
        order: 1,
        isMuted: false,
      );
      for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
        debugDefaultTargetPlatformOverride = platform;
        try {
          for (final (scale, expected) in [
            (.9, 64.8),
            (1.0, 72.0),
            (1.6, 115.2),
          ]) {
            late double actual;
            late double estimate;
            await tester.pumpWidget(
              harness(
                controller,
                SizedBox(
                  width: 390,
                  child: Builder(
                    builder: (context) {
                      actual = chatRowMetricsFor(
                        context,
                        chat,
                        width: 390,
                      ).extent;
                      estimate = chatListRowExtentFor(context, width: 390);
                      return Column(
                        children: [
                          ChatRowView(
                            key: const ValueKey('pitch-row'),
                            chat: chat,
                          ),
                          ContentSizePreview(
                            appScale: scale,
                            chatList: true,
                            now: DateTime.now(),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                scale,
              ),
            );
            await tester.pump();
            expect(actual, closeTo(expected, .0001));
            expect(estimate, closeTo(expected, .0001));
            expect(
              tester.getSize(find.byKey(const ValueKey('pitch-row'))).height,
              closeTo(expected, .0001),
            );
            final previewRows = find.descendant(
              of: find.byKey(const ValueKey('font-size-chat-list-preview')),
              matching: find.byType(ChatRowView),
            );
            for (final row in previewRows.evaluate()) {
              expect(
                tester.getSize(find.byWidget(row.widget)).height,
                closeTo(expected, .0001),
              );
            }
            final avatar = tester.getRect(
              find.descendant(
                of: find.byKey(const ValueKey('pitch-row')),
                matching: find.byType(PhotoAvatar),
              ),
            );
            final row = tester.getRect(find.byKey(const ValueKey('pitch-row')));
            expect(avatar.height, closeTo(48 * scale, .0001));
            expect(avatar.center.dy, closeTo(row.center.dy, .0001));
            expect(
              chatRowCumulativeOffset([actual, estimate]),
              closeTo(2 * expected, .0001),
            );
            expect(tester.takeException(), isNull);
          }
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      }
    },
  );

  testWidgets('three-line CJK and mixed emoji body uses 22pt even pitch', (
    tester,
  ) async {
    final controller = await theme();
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      debugDefaultTargetPlatformOverride = platform;
      try {
        for (final text in ['中文测试\n第二行文\n第三行文', '中文👋Hi\n第二行😀\n第三行文']) {
          for (final (scale, osScale) in [(1.0, 1.0), (1.6, 1.0), (1.0, 2.0)]) {
            await tester.pumpWidget(
              harness(
                controller,
                SizedBox(
                  width: 600,
                  child: DefaultTextStyle.merge(
                    // An explicit inherited 24pt pitch at 17pt must be replaced,
                    // not multiplied into the body's new leading.
                    style: const TextStyle(height: 24 / 17),
                    child: MessageBubble(
                      peerTitle: 'Fictional',
                      isGroup: false,
                      message: ChatMessage(
                        id: 71,
                        isOutgoing: false,
                        text: text,
                        date: 1,
                      ),
                    ),
                  ),
                ),
                scale,
                osScale: osScale,
              ),
            );
            final paragraph = tester.renderObject<RenderParagraph>(
              find
                  .byWidgetPredicate(
                    (widget) =>
                        widget is RichText &&
                        widget.text.toPlainText().startsWith(text),
                  )
                  .first,
            );
            final painter = TextPainter(
              text: paragraph.text,
              textDirection: paragraph.textDirection,
              textScaler: paragraph.textScaler,
              textHeightBehavior: paragraph.textHeightBehavior,
            )..layout(maxWidth: paragraph.size.width);
            final lines = painter.computeLineMetrics();
            expect(lines, hasLength(3));
            for (var i = 1; i < lines.length; i++) {
              expect(
                lines[i].baseline - lines[i - 1].baseline,
                closeTo((22 * scale * osScale).roundToDouble(), .05),
              );
            }
            expect(paragraph.text.style?.height, 22 / 17);
            expect(
              paragraph.text.style?.leadingDistribution,
              TextLeadingDistribution.even,
            );
            painter.dispose();
            expect(tester.takeException(), isNull);
          }
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }
  });

  testWidgets(
    'body leading includes quotes and captions but excludes code and reply',
    (tester) async {
      final controller = await theme();
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        const body = 'Body text\n';
        const quote = 'Quoted text\n';
        const code = 'Code text';
        await tester.pumpWidget(
          harness(
            controller,
            DefaultTextStyle.merge(
              style: const TextStyle(
                height: 1.5,
                leadingDistribution: TextLeadingDistribution.proportional,
              ),
              child: Column(
                children: [
                  MessageBubble(
                    peerTitle: 'Fictional',
                    isGroup: false,
                    message: ChatMessage(
                      id: 72,
                      isOutgoing: false,
                      text: '$body$quote$code',
                      date: 1,
                      replyToQuote: const MessageTextQuote(
                        text: 'Reply preview',
                        position: 0,
                      ),
                      textEntities: const [
                        MessageTextEntity(
                          offset: body.length,
                          length: quote.length,
                          type: 'textEntityTypeBlockQuote',
                        ),
                        MessageTextEntity(
                          offset: body.length + quote.length,
                          length: code.length,
                          type: 'textEntityTypePre',
                        ),
                      ],
                    ),
                  ),
                  MessageBubble(
                    peerTitle: 'Fictional',
                    isGroup: false,
                    message: ChatMessage(
                      id: 73,
                      isOutgoing: false,
                      text: 'Document caption',
                      date: 1,
                      contentType: 'messageDocument',
                      document: MessageDocument(
                        fileName: 'test.pdf',
                        size: 1024,
                        ext: 'PDF',
                        file: null,
                      ),
                    ),
                  ),
                  MessageBubble(
                    peerTitle: 'Fictional',
                    isGroup: false,
                    message: ChatMessage(
                      id: 75,
                      isOutgoing: false,
                      text: 'Start inline body',
                      date: 1,
                      textEntities: const [
                        MessageTextEntity(
                          offset: 6,
                          length: 6,
                          type: 'textEntityTypeCode',
                        ),
                      ],
                      linkPreview: const MessageLinkPreview(
                        url: 'https://example.com',
                        displayUrl: 'example.com',
                        siteName: 'Example',
                        title: 'Card title',
                        description: 'Card description',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            1,
          ),
        );
        TextStyle? styleFor(String text) => tester
            .widget<RichText>(
              find
                  .byWidgetPredicate(
                    (widget) =>
                        widget is RichText &&
                        widget.text.toPlainText().startsWith(text),
                  )
                  .first,
            )
            .text
            .style;
        expect(styleFor(body)?.height, 22 / 17);
        for (final text in [quote, 'Document caption', 'Card description']) {
          expect(styleFor(text)?.height, 22 / 17, reason: text);
          expect(
            styleFor(text)?.leadingDistribution,
            TextLeadingDistribution.even,
            reason: text,
          );
        }
        for (final text in [code, 'Reply preview', 'inline']) {
          expect(styleFor(text)?.height, 1.5, reason: text);
          expect(
            styleFor(text)?.leadingDistribution,
            TextLeadingDistribution.proportional,
            reason: text,
          );
        }
        expect(styleFor(code)?.fontSize, 16);
        expect(styleFor('Reply preview')?.fontSize, 14);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('link description uses body leading without changing card UI', (
    tester,
  ) async {
    final controller = await theme();
    const description = 'Card description\n第二行正文\nThird line 😀';
    for (final platform in [
      TargetPlatform.iOS,
      TargetPlatform.android,
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final touch =
            platform == TargetPlatform.iOS ||
            platform == TargetPlatform.android;
        for (final osScale in [1.0, 1.6]) {
          await tester.pumpWidget(
            harness(
              controller,
              DefaultTextStyle.merge(
                style: const TextStyle(
                  height: 1.5,
                  leadingDistribution: TextLeadingDistribution.proportional,
                ),
                child: MessageBubble(
                  peerTitle: 'Fictional',
                  isGroup: false,
                  message: ChatMessage(
                    id: 76,
                    isOutgoing: false,
                    text: 'Linked message',
                    date: 1,
                    linkPreview: const MessageLinkPreview(
                      url: 'https://example.com',
                      displayUrl: 'example.com',
                      siteName: 'Example',
                      title: 'Card title',
                      description: description,
                    ),
                  ),
                ),
              ),
              1,
              osScale: osScale,
            ),
          );
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(description, findRichText: true),
          );
          expect(paragraph.text.style?.fontSize, touch ? 17 : 14);
          expect(paragraph.text.style?.height, touch ? 22 / 17 : 1.5);
          expect(
            paragraph.text.style?.leadingDistribution,
            touch
                ? TextLeadingDistribution.even
                : TextLeadingDistribution.proportional,
          );
          final painter = TextPainter(
            text: paragraph.text,
            textDirection: paragraph.textDirection,
            textScaler: paragraph.textScaler,
            textHeightBehavior: paragraph.textHeightBehavior,
          )..layout(maxWidth: paragraph.size.width);
          final lines = painter.computeLineMetrics();
          expect(lines, hasLength(3));
          for (var i = 1; i < lines.length; i++) {
            expect(
              lines[i].baseline - lines[i - 1].baseline,
              closeTo(((touch ? 22 : 21) * osScale).roundToDouble(), .05),
            );
          }
          painter.dispose();
          final site = tester.widget<Text>(find.text('Example'));
          final title = tester.widget<Text>(find.text('Card title'));
          final url = tester.widget<Text>(find.text('example.com'));
          expect(site.style?.fontSize, 12);
          expect(site.style?.fontWeight, FontWeight.w600);
          expect(title.style?.fontSize, 15);
          expect(title.style?.fontWeight, FontWeight.w600);
          expect(title.style?.height, 1.2);
          expect(url.style?.fontSize, 12);
          for (final label in [site, title, url]) {
            expect(label.style?.leadingDistribution, isNull);
          }
          expect(tester.takeException(), isNull);
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }
  });

  testWidgets('nested rich list/details and quote body share body leading', (
    tester,
  ) async {
    final controller = await theme();
    const body = '列表正文\n第二行文\n第三行文';
    const quoted = '引用正文\n第二行文\n第三行文';
    RichMessageBlock listWithDetails(String text) => RichMessageBlock.container(
      kind: RichMessageBlockKind.list,
      listItems: [
        RichMessageListItem(
          blocks: [
            RichMessageBlock.container(
              kind: RichMessageBlockKind.details,
              text: 'Details',
              isOpen: true,
              children: [
                RichMessageBlock.text(
                  kind: RichMessageBlockKind.paragraph,
                  text: text,
                ),
              ],
            ),
          ],
        ),
      ],
    );
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(
          harness(
            controller,
            DefaultTextStyle.merge(
              style: const TextStyle(height: 1.5),
              child: MessageBubble(
                peerTitle: 'Fictional',
                isGroup: false,
                message: ChatMessage(
                  id: 74,
                  isOutgoing: false,
                  text: '',
                  date: 1,
                  contentType: 'messageRichMessage',
                  richBlocks: [
                    listWithDetails(body),
                    RichMessageBlock.container(
                      kind: RichMessageBlockKind.blockQuote,
                      children: [listWithDetails(quoted)],
                    ),
                  ],
                ),
              ),
            ),
            1,
          ),
        );
        await tester.pump();
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(body, findRichText: true),
        );
        expect(paragraph.text.style?.height, 22 / 17);
        expect(
          paragraph.text.style?.leadingDistribution,
          TextLeadingDistribution.even,
        );
        final painter = TextPainter(
          text: paragraph.text,
          textDirection: paragraph.textDirection,
          textScaler: paragraph.textScaler,
          textHeightBehavior: paragraph.textHeightBehavior,
        )..layout(maxWidth: paragraph.size.width);
        final lines = painter.computeLineMetrics();
        expect(lines, hasLength(3));
        for (var i = 1; i < lines.length; i++) {
          expect(lines[i].baseline - lines[i - 1].baseline, closeTo(22, .05));
        }
        painter.dispose();
        final quoteParagraph = tester.renderObject<RenderParagraph>(
          find.text(quoted, findRichText: true),
        );
        expect(quoteParagraph.text.style?.height, 22 / 17);
        expect(
          quoteParagraph.text.style?.leadingDistribution,
          TextLeadingDistribution.even,
        );
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }
  });

  testWidgets(
    'bubble text grows naturally and sender avatar follows content size',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final controller = await theme();
        double previous = 0;
        for (final scale in [..._sizes]..sort()) {
          await tester.pumpWidget(
            harness(
              controller,
              SizedBox(
                width: 360,
                child: MessageBubble(
                  key: const ValueKey('bubble'),
                  peerTitle: 'Fictional',
                  isGroup: false,
                  message: ChatMessage(
                    id: 8,
                    isOutgoing: false,
                    text:
                        'A longer message with 中文 and emoji 👋. Natural height follows the text, not a fixed box.',
                    date: 1,
                  ),
                ),
              ),
              scale,
            ),
          );
          await tester.pump();
          final height = tester
              .getSize(find.byKey(const ValueKey('bubble')))
              .height;
          expect(height, greaterThanOrEqualTo(previous));
          previous = height;
          expect(
            tester.widget<PhotoAvatar>(find.byType(PhotoAvatar)).size,
            38 * scale,
          );
          expect(tester.takeException(), isNull);
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'actual bubble and preview body roles retain custom and OS scaling',
    (tester) async {
      final controller = await theme();
      const text = 'Ordinary bubble text';
      for (final platform in [
        TargetPlatform.iOS,
        TargetPlatform.android,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        try {
          final size =
              platform == TargetPlatform.iOS ||
                  platform == TargetPlatform.android
              ? 17.0
              : 14.0;
          for (final scale in [.8, 1.0, 1.47, 2.0]) {
            for (final osScale in [1.0, 1.7]) {
              await tester.pumpWidget(
                harness(
                  controller,
                  SizedBox(
                    width: 360,
                    child: Column(
                      children: [
                        MessageBubble(
                          peerTitle: 'Fictional',
                          isGroup: false,
                          message: ChatMessage(
                            id: 80,
                            isOutgoing: false,
                            text: text,
                            date: 1,
                          ),
                        ),
                        ContentSizePreview(
                          appScale: scale,
                          chatList: false,
                          now: DateTime(2026),
                        ),
                      ],
                    ),
                  ),
                  scale,
                  osScale: osScale,
                ),
              );
              await tester.pump();
              final paragraph = tester.renderObject<RenderParagraph>(
                find
                    .byWidgetPredicate(
                      (widget) =>
                          widget is RichText &&
                          widget.text.toPlainText().startsWith(text),
                    )
                    .first,
              );
              expect(paragraph.text.style?.fontSize, size);
              final touch =
                  platform == TargetPlatform.iOS ||
                  platform == TargetPlatform.android;
              final inheritedStyle = DefaultTextStyle.of(
                tester.element(find.byType(MessageBubble)),
              ).style;
              expect(
                paragraph.text.style?.height,
                touch ? 22 / 17 : inheritedStyle.height,
              );
              expect(
                paragraph.text.style?.leadingDistribution,
                touch
                    ? TextLeadingDistribution.even
                    : inheritedStyle.leadingDistribution,
              );
              expect(
                paragraph.textScaler.scale(size),
                closeTo(size * scale * osScale, .0001),
              );
              final previewText = tester.widget<Text>(
                find.descendant(
                  of: find.byKey(const ValueKey('content-size-bubble-in')),
                  matching: find.byType(Text),
                ),
              );
              expect(previewText.style?.fontSize, size);
              expect(previewText.style?.height, touch ? 22 / 17 : null);
              expect(
                previewText.style?.leadingDistribution,
                touch ? TextLeadingDistribution.even : null,
              );
              final previewParagraph = tester.renderObject<RenderParagraph>(
                find.descendant(
                  of: find.byKey(const ValueKey('content-size-bubble-in')),
                  matching: find.byType(RichText),
                ),
              );
              expect(
                previewParagraph.textScaler.scale(size),
                closeTo(size * scale * osScale, .0001),
              );
              expect(tester.takeException(), isNull);
            }
          }
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      }
    },
  );

  testWidgets('emoji-only bubble keeps its 34 point role', (tester) async {
    final controller = await theme();
    await tester.pumpWidget(
      harness(
        controller,
        MessageBubble(
          peerTitle: 'Fictional',
          isGroup: false,
          message: ChatMessage(
            id: 81,
            isOutgoing: false,
            text: '😀😀',
            date: 1,
          ),
        ),
        1,
      ),
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is RichText &&
                widget.text.toPlainText().startsWith('😀'),
          )
          .first,
    );
    expect(paragraph.text.style?.fontSize, 34.0);
    expect(paragraph.text.style?.height, isNot(22 / 17));
  });

  testWidgets('album media dimensions do not inherit content scaling', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final controller = await theme();
      Size? baseline;
      for (final scale in _sizes) {
        await tester.pumpWidget(
          harness(
            controller,
            SizedBox(
              width: 600,
              child: ImageMediaAlbumBubble(
                peerTitle: 'Fictional',
                isGroup: false,
                messages: [
                  for (final id in [1, 2])
                    ChatMessage(
                      id: id,
                      isOutgoing: false,
                      text: '',
                      date: 1,
                      contentType: 'messagePhoto',
                      mediaAlbumId: 91,
                      image: TdFileRef(id: id),
                      imageWidth: 1600,
                      imageHeight: 1200,
                    ),
                ],
                imageBuilder: (context, message, width, height) => ColoredBox(
                  key: ValueKey('image-${message.id}'),
                  color: const Color(0xff336699),
                ),
              ),
            ),
            scale,
          ),
        );
        await tester.pump();
        final size = tester.getSize(
          find.byKey(const ValueKey('messageImageAlbumTile-1')),
        );
        baseline ??= size;
        expect(size, baseline);
        expect(tester.takeException(), isNull);
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
  test('cumulative targets use actual entries and only real separators', () {
    expect(chatRowCumulativeOffset([64, 112, 78], leadingExtent: 44), 298);
    expect(
      chatRowCumulativeOffset(
        [64, 112, 78],
        leadingExtent: 44,
        separatorExtent: .5,
      ),
      299.5,
    );
    expect(chatRowCumulativeOffset([], leadingExtent: 44), 44);
  });

  testWidgets('ordinary Standard rows remain exactly72 at280 and320', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final controller = await theme();
      final chat = ChatSummary(
        id: 10,
        title: 'Ordinary conversation',
        lastMessage: 'Preview',
        lastMessageId: 1,
        date: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        unreadCount: 0,
        order: 1,
        isMuted: false,
      );
      for (final width in [280.0, 320.0]) {
        await tester.pumpWidget(
          harness(
            controller,
            SizedBox(
              width: width,
              child: ChatRowView(
                key: const ValueKey('ordinary-row'),
                chat: chat,
              ),
            ),
            1,
          ),
        );
        await tester.pump();
        expect(
          tester.getSize(find.byKey(const ValueKey('ordinary-row'))).height,
          72,
        );
        final title = tester.widget<Text>(find.text(chat.title));
        expect(title.style?.fontSize, 17);
        expect(title.style?.fontWeight, AppTextWeight.medium);
        expect(
          tester.widget<ChatPreviewText>(find.byType(ChatPreviewText)).fontSize,
          13,
        );
        expect(
          tester
              .widget<Text>(find.text(DateText.listLabel(chat.date)))
              .style
              ?.fontSize,
          13,
        );

        expect(tester.takeException(), isNull);
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  /// Global y of a text's first alphabetic baseline, measured from the
  /// paragraph's own resolved span, scaler and direction.
  double baselineOf(WidgetTester tester, Finder text) {
    final paragraph = tester.renderObject<RenderParagraph>(text);
    final painter = TextPainter(
      text: paragraph.text,
      textAlign: paragraph.textAlign,
      textDirection: paragraph.textDirection,
      textScaler: paragraph.textScaler,
      maxLines: paragraph.maxLines,
      locale: paragraph.locale,
      strutStyle: paragraph.strutStyle,
      textWidthBasis: paragraph.textWidthBasis,
      textHeightBehavior: paragraph.textHeightBehavior,
    )..layout(maxWidth: paragraph.size.width);
    try {
      final baseline = painter.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      return paragraph.localToGlobal(Offset(0, baseline)).dy;
    } finally {
      painter.dispose();
    }
  }

  /// The time sits on the name's line at the row's trailing edge, sharing
  /// the name's baseline, and the name never runs under it.
  void expectTimeOnNameLine(
    WidgetTester tester, {
    required Finder row,
    required Finder name,
    required Finder time,
    required double padding,
    required TextDirection direction,
    required String reason,
  }) {
    expect(name, findsOneWidget, reason: reason);
    expect(time, findsOneWidget, reason: reason);
    expect(
      (baselineOf(tester, time) - baselineOf(tester, name)).abs(),
      lessThanOrEqualTo(1.0),
      reason: reason,
    );
    final rowRect = tester.getRect(row);
    final nameRect = tester.getRect(name);
    final timeRect = tester.getRect(time);
    if (direction == TextDirection.ltr) {
      expect(
        timeRect.right,
        closeTo(rowRect.right - padding, .5),
        reason: reason,
      );
      expect(nameRect.right, lessThanOrEqualTo(timeRect.left), reason: reason);
    } else {
      expect(
        timeRect.left,
        closeTo(rowRect.left + padding, .5),
        reason: reason,
      );
      expect(
        nameRect.left,
        greaterThanOrEqualTo(timeRect.right),
        reason: reason,
      );
    }
  }

  testWidgets('chat row time shares the name baseline at every size', (
    tester,
  ) async {
    final controller = await theme();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final chats = [
      ChatSummary(
        id: 21,
        title: 'Ordinary conversation',
        lastMessage: 'Preview',
        lastMessageId: 1,
        date: now,
        unreadCount: 0,
        order: 1,
        isMuted: false,
      ),
      // Every header accessory at once: lock, community mark and status
      // emoji around a name long enough to ellipsize, plus indicators.
      ChatSummary(
        id: 22,
        title: 'A secret conversation whose long name must ellipsize 中文',
        lastMessage: 'Preview 预览 with a long message',
        lastMessageId: 1,
        date: now,
        unreadCount: 4,
        unreadMentionCount: 2,
        order: 1,
        isMuted: true,
        isPinned: true,
        kind: ChatKind.secret,
        peerEmojiStatusId: 123,
      ),
    ];
    for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
      debugDefaultTargetPlatformOverride = platform;
      try {
        for (final direction in TextDirection.values) {
          for (final (osScale, width) in [(1.0, 390.0), (2.0, 640.0)]) {
            for (final scale in [1.0, 1.6]) {
              for (final chat in chats) {
                final reason =
                    '$platform $direction os=$osScale scale=$scale '
                    '${chat.id}';
                await tester.pumpWidget(
                  harness(
                    controller,
                    SizedBox(
                      width: width,
                      child: ChatRowView(
                        key: const ValueKey('aligned-row'),
                        chat: chat,
                        titleTrailing: chat.kind == ChatKind.secret
                            ? const AppIcon(HeroAppIcons.lock, size: 14)
                            : null,
                      ),
                    ),
                    scale,
                    osScale: osScale,
                    direction: direction,
                  ),
                );
                await tester.pump();
                CustomEmojiCenter.shared.reset();
                await tester.pump(const Duration(milliseconds: 50));
                final name = find.text(chat.title);
                expectTimeOnNameLine(
                  tester,
                  row: find.byKey(const ValueKey('aligned-row')),
                  name: name,
                  time: find.text(DateText.listLabel(chat.date)),
                  padding: AppSpacing.xl,
                  direction: direction,
                  reason: reason,
                );
                if (chat.kind == ChatKind.secret) {
                  expect(
                    tester
                        .renderObject<RenderParagraph>(name)
                        .didExceedMaxLines,
                    isTrue,
                    reason: reason,
                  );
                  expect(find.byType(StatusEmojiView), findsOneWidget);
                  expect(
                    find.byKey(const ValueKey('chat-row-muted')),
                    findsOneWidget,
                  );
                }
                expect(tester.takeException(), isNull, reason: reason);
              }
            }
          }
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }
  });

  testWidgets('topic row time shares the name baseline at every size', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final controller = await theme();
      final topic = TopicNavigationItem(
        id: 5,
        name: 'A closed topic whose long name must ellipsize 话题',
        lastPreview: 'Latest message in the topic',
        lastSender: 'Mina',
        lastMessageDate: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        isPinned: true,
        isMuted: true,
        isClosed: true,
      );
      for (final direction in TextDirection.values) {
        for (final scale in [1.0, 1.6]) {
          await tester.pumpWidget(
            harness(
              controller,
              SizedBox(
                width: 390,
                child: TopicListRowView(
                  key: const ValueKey('aligned-topic'),
                  topic: topic,
                  selected: false,
                  onTap: () {},
                ),
              ),
              scale,
              direction: direction,
            ),
          );
          await tester.pump();
          expectTimeOnNameLine(
            tester,
            row: find.byKey(const ValueKey('aligned-topic')),
            name: find.text(topic.name),
            time: find.text(DateText.listLabel(topic.lastMessageDate)),
            padding: AppSpacing.lg,
            direction: direction,
            reason: '$direction scale=$scale',
          );
          expect(
            find.byKey(const ValueKey('topic-row-muted-5')),
            findsOneWidget,
          );
          expect(
            tester.widget<Text>(find.text(topic.name)).style?.fontSize,
            17,
          );
          expect(
            tester
                .widget<ChatPreviewText>(find.byType(ChatPreviewText))
                .fontSize,
            13,
          );
          expect(
            tester
                .widget<Text>(
                  find.text(DateText.listLabel(topic.lastMessageDate)),
                )
                .style
                ?.fontSize,
            13,
          );

          expect(tester.takeException(), isNull);
        }
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('chat list preview rows keep the time on the name baseline', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final controller = await theme();
      for (final direction in TextDirection.values) {
        for (final scale in contentSizePresets) {
          await tester.pumpWidget(
            harness(
              controller,
              SizedBox(
                width: 430,
                child: ContentSizePreview(
                  appScale: scale,
                  chatList: true,
                  now: DateTime.now(),
                ),
              ),
              1,
              direction: direction,
            ),
          );
          await tester.pump();
          final rows = find.byType(ChatRowView);
          expect(rows, findsNWidgets(3));
          for (var index = 0; index < 3; index++) {
            final row = rows.at(index);
            final chat = tester.widget<ChatRowView>(row).chat;
            expectTimeOnNameLine(
              tester,
              row: row,
              name: find.descendant(of: row, matching: find.text(chat.title)),
              time: find.descendant(
                of: row,
                matching: find.text(DateText.listLabel(chat.date)),
              ),
              padding: AppSpacing.xl,
              direction: direction,
              reason: '$direction scale=$scale row=$index',
            );
          }
          expect(tester.takeException(), isNull);
        }
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('tag and topic metrics reserve only actual content', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final controller = await theme();
      await tester.pumpWidget(
        harness(
          controller,
          Builder(
            builder: (context) {
              final plain = ChatRowMetrics.resolve(
                context,
                width: 280,
                timestamp: '12:34',
              );
              final tagged = ChatRowMetrics.resolve(
                context,
                width: 280,
                timestamp: '12:34',
                folderTags: true,
              );
              final topic = ChatRowMetrics.resolve(
                context,
                width: 280,
                timestamp: '12:34',
                pinned: true,
              );
              expect(plain.extent, 72);
              expect(plain.timeBelow, isFalse);
              expect(topic.extent, 72);
              expect(topic.timeBelow, isFalse);
              expect(tagged.extent, greaterThan(plain.extent));
              return const SizedBox();
            },
          ),
          1,
        ),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'narrow accessibility row wraps every accessory without overflow',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final controller = await theme();
        final chat = ChatSummary(
          id: 9,
          title: 'A complete long title 中文 preserved for accessibility',
          lastMessage: 'A long preview 中文 with emoji 👋',
          lastMessageId: 1,
          date: 1600000000,
          unreadCount: 999,
          unreadMentionCount: 999,
          unreadReactionCount: 999,
          order: 1,
          isMuted: true,
          isPinned: true,
          peerEmojiStatusId: 123,
        );
        for (final direction in TextDirection.values) {
          await tester.pumpWidget(
            harness(
              controller,
              SizedBox(
                width: 320,
                child: ChatRowView(
                  chat: chat,
                  key: const ValueKey('accessory-row'),
                  trailingIndicator: const AppIcon(
                    HeroAppIcons.bellSlash,
                    size: 17,
                  ),
                ),
              ),
              1.6,
              osScale: 2,
              direction: direction,
            ),
          );
          await tester.pump();
          // Keep this local geometry fixture offline; drain the scheduled batch
          // with no pending IDs rather than asking TDLib for a real sticker.
          CustomEmojiCenter.shared.reset();
          await tester.pump(const Duration(milliseconds: 50));
          final row = tester.getRect(
            find.byKey(const ValueKey('accessory-row')),
          );
          for (final key in [
            'chat-row-unread-mention',
            'chat-row-unread-reaction',
            'chat-row-pinned',
            'chat-row-muted',
          ]) {
            final rect = tester.getRect(find.byKey(ValueKey(key)));
            expect(rect.left, greaterThanOrEqualTo(row.left));
            expect(rect.right, lessThanOrEqualTo(row.right));
            expect(rect.bottom, lessThanOrEqualTo(row.bottom));
          }
          expect(find.byType(StatusEmojiView), findsOneWidget);
          expect(tester.widget<Text>(find.text(chat.title)).data, chat.title);
          expect(tester.takeException(), isNull);
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'unread badge drag origin and hit box follow scaled font geometry',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final controller = await theme();
        var cleared = false;
        for (final direction in TextDirection.values) {
          for (final scale in [1.0, 1.6, 2.0, 1.0]) {
            await tester.pumpWidget(
              harness(
                controller,
                ContentSizeScope(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: UnreadBadge(
                      count: 99,
                      onClear: () => cleared = true,
                    ),
                  ),
                ),
                scale,
                osScale: 2,
                direction: direction,
              ),
            );
            await tester.pump();
            final badge = find.byType(UnreadBadge);
            final paintFinder = find.descendant(
              of: badge,
              matching: find.byType(CustomPaint),
            );
            final paint = tester.widget<CustomPaint>(paintFinder);
            final origin = (paint.painter as dynamic).origin as Offset;
            final paintRect = tester.getRect(paintFinder);
            final visualRect = tester.getRect(
              find.descendant(
                of: badge,
                matching: find.byType(UnconstrainedBox),
              ),
            );
            expect(
              origin.dx,
              closeTo(visualRect.center.dx - paintRect.left, .01),
            );
            expect(
              origin.dy,
              closeTo(visualRect.center.dy - paintRect.top, .01),
            );
            expect(paintRect.height, greaterThanOrEqualTo(visualRect.height));
            expect(paintRect.width, greaterThanOrEqualTo(visualRect.width));
            final gesture = await tester.startGesture(visualRect.center);
            await gesture.moveBy(const Offset(12, 0));
            await tester.pump();
            final dragged = tester.widget<CustomPaint>(paintFinder);
            expect((dragged.painter as dynamic).origin, origin);
            await gesture.up();
            await tester.pump();
            expect(cleared, isFalse);
            expect(tester.takeException(), isNull);
          }
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
