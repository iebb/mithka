import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view.dart';
import 'package:mithka/chat/image_media_album_bubble.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/chat/message_quote_selection_dialog.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const sourceText = 'before selected and selected after';

Offset textPosition(WidgetTester tester, Finder text, int offset) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  return paragraph.localToGlobal(
    paragraph.getOffsetForCaret(
          TextPosition(offset: offset),
          const Rect.fromLTWH(0, 0, 2, 20),
        ) +
        const Offset(0, 5),
  );
}

Future<void> waitForText(WidgetTester tester, Finder text) async {
  // Initial transcript alignment advances across several end-of-frame passes.
  for (
    var frame = 0;
    frame < 20 && text.hitTestable().evaluate().isEmpty;
    frame++
  ) {
    tester.binding.scheduleFrame();
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(text.hitTestable(), findsOneWidget);
}

Future<void> selectRange(
  WidgetTester tester,
  Finder text,
  int start,
  int end,
) async {
  // Nested selection containers register their content after layout.
  await tester.pumpAndSettle();
  await waitForText(tester, text);
  final paragraph = tester.renderObject<RenderParagraph>(text);
  Offset position(int offset) => paragraph.localToGlobal(
    paragraph.getOffsetForCaret(
          TextPosition(offset: offset),
          const Rect.fromLTWH(0, 0, 2, 20),
        ) +
        const Offset(0, 5),
  );
  final gesture = await tester.startGesture(
    position(start),
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveTo(position(end));
  await gesture.up();
  await gesture.removePointer();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ThemeController theme;
  late TranslationController translation;
  var quoteLimit = 1024;
  var protectedContent = false;

  setUpAll(() {
    // All queries, including startup/read requests, stay in this test transport.
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => switch (request['@type']) {
          'getChat' => {
            '@type': 'chat',
            'id': 42,
            'title': 'Selection test',
            'type': {'@type': 'chatTypePrivate', 'user_id': 2},
            'has_protected_content': protectedContent,
            'last_read_inbox_message_id': 78,
            'permissions': {'can_send_basic_messages': true},
          },
          'getUser' || 'getMe' => {
            '@type': 'user',
            'id': request['user_id'] ?? 1,
            'first_name': 'Test',
            'type': {'@type': 'userTypeRegular'},
          },
          'getChatHistory' => {
            '@type': 'messages',
            'total_count': 1,
            'messages': [
              {
                '@type': 'message',
                'id': 78,
                'chat_id': 42,
                'date': 1785862260,
                'sender_id': {'@type': 'messageSenderUser', 'user_id': 2},
                'content': {
                  '@type': 'messageText',
                  'text': {
                    '@type': 'formattedText',
                    'text': sourceText,
                    'entities': [],
                  },
                },
              },
            ],
          },
          'getOption' => {
            '@type': 'optionValueInteger',
            'value': '$quoteLimit',
          },
          _ => {'@type': 'ok'},
        },
        send: (_) async {},
        updates: const Stream.empty(),
      ),
    );
  });
  tearDownAll(TdClient.shared.closeProxy);

  setUp(() async {
    clearChatMemoryCaches();
    SharedPreferences.setMockInitialValues({'openChatsAtLatest': true});
    final preferences = await SharedPreferences.getInstance();
    theme = ThemeController(preferences);
    translation = TranslationController(preferences);
    quoteLimit = 1024;
    protectedContent = false;
  });
  tearDown(() {
    theme.dispose();
    translation.dispose();
  });

  Widget app(Widget child, TargetPlatform platform) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: theme),
      ChangeNotifierProvider.value(value: translation),
    ],
    child: MaterialApp(
      theme: ThemeData(platform: platform, extensions: [AppColors.light]),
      locale: const Locale('en'),
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    for (final album in [false, true]) {
      testWidgets(
        '${platform.name} ${album ? 'album caption' : 'message'} clicks without dragging do not select text',
        (tester) async {
          MessageTextQuote? selected;
          final message = ChatMessage(
            id: 78,
            isOutgoing: false,
            date: 1,
            contentType: album ? 'messagePhoto' : 'messageText',
            text: sourceText,
            image: album ? TdFileRef(id: 1) : null,
          );
          void onQuoteChanged(ChatMessage _, MessageTextQuote? quote) =>
              selected = quote;
          await tester.pumpWidget(
            app(
              album
                  ? ImageMediaAlbumBubble(
                      messages: [
                        ChatMessage(
                          id: 77,
                          isOutgoing: false,
                          date: 1,
                          contentType: 'messagePhoto',
                          text: '',
                          image: TdFileRef(id: 2),
                        ),
                        message,
                      ],
                      peerTitle: 'Test',
                      isGroup: false,
                      imageBuilder: (_, _, _, _) => const SizedBox.shrink(),
                      onDesktopQuoteChanged: onQuoteChanged,
                    )
                  : MessageBubble(
                      message: message,
                      peerTitle: 'Test',
                      isGroup: false,
                      onDesktopQuoteChanged: onQuoteChanged,
                    ),
              platform,
            ),
          );
          await tester.pumpAndSettle();
          final text = find.text(sourceText, findRichText: true);
          final paragraph = tester.renderObject<RenderParagraph>(text);
          final position = textPosition(tester, text, 24);
          // Include rapid repeated clicks: only a drag should select content.
          for (var click = 0; click < 3; click++) {
            final clickGesture = await tester.startGesture(
              position,
              kind: PointerDeviceKind.mouse,
            );
            await tester.pump(kPressTimeout + const Duration(milliseconds: 20));
            expect(paragraph.selections, isEmpty);
            expect(selected, isNull);
            await clickGesture.up();
            await clickGesture.removePointer();
            await tester.pump(const Duration(milliseconds: 80));
            expect(paragraph.selections, isEmpty);
            expect(selected, isNull);
          }
          await tester.pump(const Duration(seconds: 1));
          // Minor pointer jitter must not turn a click into a selection.
          final gesture = await tester.startGesture(
            position,
            kind: PointerDeviceKind.mouse,
          );
          await gesture.moveBy(const Offset(0.5, 0));
          await gesture.up();
          await gesture.removePointer();
          await tester.pump();
          expect(paragraph.selections, isEmpty);
          expect(selected, isNull);

          await tester.pump(const Duration(seconds: 1));
          await selectRange(tester, text, 20, 28);
          expect(selected?.text, 'selected');
          // A primary click clears an existing drag selection, rather than
          // creating a new word selection from the preceding drag's tap count.
          await tester.tapAt(position, kind: PointerDeviceKind.mouse);
          await tester.pump();
          expect(paragraph.selections, isEmpty);
          expect(selected, isNull);
          tester
              .state<SelectionAreaState>(find.byType(SelectionArea).first)
              .selectableRegion
              .selectAll(SelectionChangedCause.keyboard);
          await tester.pump();
          expect(selected?.text, sourceText);

          // Word-wise selection still works when the second click is dragged.
          await tester.pump(const Duration(seconds: 1));
          await tester.tapAt(position, kind: PointerDeviceKind.mouse);
          await tester.pump(const Duration(milliseconds: 80));
          final wordDrag = await tester.startGesture(
            position,
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump(kPressTimeout + const Duration(milliseconds: 20));
          expect(paragraph.selections, isEmpty);
          await wordDrag.moveTo(textPosition(tester, text, 26));
          await wordDrag.up();
          await wordDrag.removePointer();
          await tester.pump();
          expect(selected?.text, 'selected');
          expect(selected?.position, 20);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        variant: TargetPlatformVariant.only(platform),
      );

      testWidgets(
        '${platform.name} ${album ? 'album caption' : 'message'} secondary click opens actions without selecting a word',
        (tester) async {
          MessageTextQuote? selected;
          var menus = 0;
          final message = ChatMessage(
            id: 78,
            isOutgoing: false,
            date: 1,
            contentType: album ? 'messagePhoto' : 'messageText',
            text: sourceText,
            image: album ? TdFileRef(id: 1) : null,
          );
          void onQuoteChanged(ChatMessage _, MessageTextQuote? quote) =>
              selected = quote;
          await tester.pumpWidget(
            app(
              album
                  ? ImageMediaAlbumBubble(
                      messages: [
                        ChatMessage(
                          id: 77,
                          isOutgoing: false,
                          date: 1,
                          contentType: 'messagePhoto',
                          text: '',
                          image: TdFileRef(id: 2),
                        ),
                        message,
                      ],
                      peerTitle: 'Test',
                      isGroup: false,
                      imageBuilder: (_, _, _, _) => const SizedBox.shrink(),
                      onDesktopQuoteChanged: onQuoteChanged,
                      onLongPress: (_, _, _) => menus++,
                    )
                  : MessageBubble(
                      message: message,
                      peerTitle: 'Test',
                      isGroup: false,
                      onDesktopQuoteChanged: onQuoteChanged,
                      onLongPress: (_, _, _) => menus++,
                    ),
              platform,
            ),
          );
          await tester.pumpAndSettle();
          final text = find.text(sourceText, findRichText: true);
          await tester.tapAt(
            textPosition(tester, text, 24),
            kind: PointerDeviceKind.mouse,
            buttons: kSecondaryMouseButton,
          );
          await tester.pump();
          expect(menus, 1);
          expect(
            tester.renderObject<RenderParagraph>(text).selections,
            isEmpty,
          );
          expect(selected, isNull);
          await selectRange(tester, text, 20, 28);
          expect(selected?.text, 'selected');
          // Opening actions elsewhere in this message must retain the exact
          // drag-selected quote instead of replacing it with the clicked word.
          await tester.tapAt(
            textPosition(tester, text, 3),
            kind: PointerDeviceKind.mouse,
            buttons: kSecondaryMouseButton,
          );
          await tester.pump();
          expect(menus, 2);
          expect(selected?.text, 'selected');
          expect(selected?.position, 20);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        variant: TargetPlatformVariant.only(platform),
      );
    }

    testWidgets(
      '${platform.name} mouse click still activates an inline text action',
      (tester) async {
        String? command;
        MessageTextQuote? selected;
        await tester.pumpWidget(
          app(
            MessageBubble(
              message: ChatMessage(
                id: 78,
                isOutgoing: false,
                date: 1,
                text: '/help',
                contentType: 'messageText',
                textEntities: const [
                  MessageTextEntity(
                    offset: 0,
                    length: 5,
                    type: 'textEntityTypeBotCommand',
                  ),
                ],
              ),
              peerTitle: 'Test',
              isGroup: false,
              onBotCommandTap: (value) => command = value,
              onDesktopQuoteChanged: (_, quote) => selected = quote,
            ),
            platform,
          ),
        );
        await tester.pumpAndSettle();
        final text = find.text('/help', findRichText: true);
        await tester.tap(text, kind: PointerDeviceKind.mouse);
        await tester.pump();
        expect(command, '/help');
        expect(tester.renderObject<RenderParagraph>(text).selections, isEmpty);
        expect(selected, isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant.only(platform),
    );

    testWidgets(
      '${platform.name} quotes the selected occurrence directly from the menu',
      (tester) async {
        await tester.pumpWidget(
          app(const ChatView(chatId: 42, title: 'Selection test'), platform),
        );
        await tester.pumpAndSettle();
        final text = find.text(sourceText, findRichText: true);
        expect(text, findsOneWidget);
        // Reverse-drag the second occurrence, not the identical first word.
        await selectRange(tester, text, 28, 20);
        await tester.tapAt(
          textPosition(tester, text, 24),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('message-action-reply')),
          findsNothing,
        );
        await tester.tap(find.byKey(const ValueKey('message-action-quote')));
        await tester.pumpAndSettle();
        expect(find.byType(MessageQuoteSelectionDialog), findsNothing);
        final vm = tester.widget<ChatInputBar>(find.byType(ChatInputBar)).vm;
        expect(vm.replyQuote?.text, 'selected');
        expect(vm.replyQuote?.position, 20);
        expect(vm.replyTo?.id, 78);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets('ordinary desktop reply has no separate quote-window action', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const ChatView(chatId: 42, title: 'Selection test'),
        TargetPlatform.macOS,
      ),
    );
    await tester.pumpAndSettle();
    await waitForText(tester, find.text(sourceText, findRichText: true));
    await tester.tapAt(
      tester.getCenter(find.text(sourceText, findRichText: true)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('message-action-quote')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('message-action-reply')));
    await tester.pumpAndSettle();
    final vm = tester.widget<ChatInputBar>(find.byType(ChatInputBar)).vm;
    expect(vm.replyTo?.id, 78);
    expect(vm.replyQuote, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('selected quote still respects the server length limit', (
    tester,
  ) async {
    quoteLimit = 4;
    await tester.pumpWidget(
      app(
        const ChatView(chatId: 42, title: 'Selection test'),
        TargetPlatform.macOS,
      ),
    );
    await tester.pumpAndSettle();
    final text = find.text(sourceText, findRichText: true);
    await selectRange(tester, text, 20, 28);
    await tester.tapAt(
      textPosition(tester, text, 24),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('message-action-quote')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ChatInputBar>(find.byType(ChatInputBar)).vm.replyQuote,
      isNull,
    );
    expect(find.byType(MessageQuoteSelectionDialog), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('body offsets exclude reply headers and preserve formatting', (
    tester,
  ) async {
    MessageTextQuote? selected;
    final message =
        ChatMessage(
            id: 78,
            isOutgoing: false,
            date: 1,
            contentType: 'messageText',
            text: sourceText,
            replyToMessageId: 77,
            textEntities: const [
              MessageTextEntity(
                offset: 20,
                length: 8,
                type: 'textEntityTypeBold',
              ),
            ],
          )
          ..replyToSender = 'Another sender'
          ..replyToPreview = 'Other text';
    await tester.pumpWidget(
      app(
        MessageBubble(
          message: message,
          peerTitle: 'Test',
          isGroup: false,
          onDesktopQuoteChanged: (_, quote) => selected = quote,
        ),
        TargetPlatform.macOS,
      ),
    );
    await selectRange(
      tester,
      find.text(sourceText, findRichText: true),
      20,
      28,
    );
    expect(selected?.position, 20);
    expect(selected?.text, 'selected');
    expect(selected?.entities.single.offset, 0);
    expect(selected?.entities.single.type, 'textEntityTypeBold');
    tester
        .state<SelectionAreaState>(find.byType(SelectionArea).first)
        .selectableRegion
        .clearSelection();
    await tester.pump();
    expect(selected, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final guarded in ['protected', 'edited']) {
    testWidgets(
      '$guarded messages cannot turn a selection into an invalid quote',
      (tester) async {
        protectedContent = guarded == 'protected';
        await tester.pumpWidget(
          app(
            const ChatView(chatId: 42, title: 'Selection test'),
            TargetPlatform.macOS,
          ),
        );
        await tester.pumpAndSettle();
        final text = find.text(sourceText, findRichText: true);
        await selectRange(tester, text, 20, 28);
        await tester.tapAt(
          textPosition(tester, text, 24),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        final vm = tester.widget<ChatInputBar>(find.byType(ChatInputBar)).vm;
        if (protectedContent) {
          expect(
            find.byKey(const ValueKey('message-action-quote')),
            findsNothing,
          );
          await tester.tap(find.byKey(const ValueKey('message-action-reply')));
        } else {
          vm.messages.single.textQuoteSource = 'edited original text';
          await tester.tap(find.byKey(const ValueKey('message-action-quote')));
        }
        await tester.pumpAndSettle();
        expect(vm.replyQuote, isNull);
        expect(find.byType(MessageQuoteSelectionDialog), findsNothing);
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('album caption selection belongs to its caption message', (
    tester,
  ) async {
    MessageTextQuote? selected;
    ChatMessage? selectedMessage;
    ChatMessage? menuMessage;
    final first = ChatMessage(
      id: 1,
      isOutgoing: false,
      date: 1,
      text: '',
      contentType: 'messagePhoto',
      image: TdFileRef(id: 1),
    );
    final caption = ChatMessage(
      id: 2,
      isOutgoing: false,
      date: 1,
      text: sourceText,
      contentType: 'messagePhoto',
      image: TdFileRef(id: 2),
    );
    await tester.pumpWidget(
      app(
        ImageMediaAlbumBubble(
          messages: [first, caption],
          peerTitle: 'Test',
          isGroup: false,
          imageBuilder: (_, _, _, _) => const SizedBox.shrink(),
          onDesktopQuoteChanged: (message, quote) {
            selectedMessage = message;
            selected = quote;
          },
          onLongPress: (message, _, _) => menuMessage = message,
        ),
        TargetPlatform.macOS,
      ),
    );
    final text = find.text(sourceText, findRichText: true);
    await selectRange(tester, text, 20, 28);
    await tester.tapAt(
      textPosition(tester, text, 24),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    expect(selectedMessage, same(caption));
    expect(menuMessage, same(caption));
    expect(selected?.position, 20);
    expect(selected?.text, 'selected');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(selected, isNull);
  });

  testWidgets('custom emoji keeps UTF-16 source offsets for following text', (
    tester,
  ) async {
    MessageTextQuote? selected;
    final message = ChatMessage(
      id: 78,
      isOutgoing: false,
      date: 1,
      contentType: 'messageText',
      text: 'a 😀 selected z',
      textEntities: const [
        MessageTextEntity(
          offset: 2,
          length: 2,
          type: 'textEntityTypeCustomEmoji',
          customEmojiId: 123,
        ),
      ],
    );
    await tester.pumpWidget(
      app(
        MessageBubble(
          message: message,
          peerTitle: 'Test',
          isGroup: false,
          onDesktopQuoteChanged: (_, quote) => selected = quote,
        ),
        TargetPlatform.macOS,
      ),
    );
    final rendered = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText() == 'a \uFFFC selected z',
    );
    // The WidgetSpan is one render offset, but the source emoji uses two.
    await selectRange(tester, rendered, 4, 12);
    expect(selected?.text, 'selected');
    expect(selected?.position, 5);
    tester
        .state<SelectionAreaState>(find.byType(SelectionArea).first)
        .selectableRegion
        .selectAll(SelectionChangedCause.keyboard);
    await tester.pumpAndSettle();
    expect(selected?.text, message.text);
    expect(selected?.entities.single.customEmojiId, 123);
    expect(selected?.entities.single.offset, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('a selection spanning quote blocks keeps source newlines', (
    tester,
  ) async {
    MessageTextQuote? selected;
    final message = ChatMessage(
      id: 78,
      isOutgoing: false,
      date: 1,
      contentType: 'messageText',
      text: 'before\nquoted\nafter',
      textEntities: const [
        MessageTextEntity(
          offset: 7,
          length: 6,
          type: 'textEntityTypeBlockQuote',
        ),
      ],
    );
    await tester.pumpWidget(
      app(
        MessageBubble(
          message: message,
          peerTitle: 'Test',
          isGroup: false,
          onDesktopQuoteChanged: (_, quote) => selected = quote,
        ),
        TargetPlatform.macOS,
      ),
    );
    await tester.pumpAndSettle();
    tester
        .state<SelectionAreaState>(find.byType(SelectionArea).first)
        .selectableRegion
        .selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
    expect(selected?.text, message.text);
    expect(selected?.position, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'grouped-file caption opens the context menu for its own source',
    (tester) async {
      ChatMessage? menuMessage;
      MessageTextQuote? selected;
      var menus = 0;
      ChatMessage file(int id, String text) => ChatMessage(
        id: id,
        isOutgoing: false,
        date: 1,
        text: text,
        contentType: 'messageDocument',
        mediaAlbumId: 400,
        document: MessageDocument(
          fileName: '$id.zip',
          size: 1024,
          ext: 'ZIP',
          file: null,
        ),
      );
      final first = file(1, '');
      final caption = file(2, sourceText);
      await tester.pumpWidget(
        app(
          MessageBubble(
            message: first,
            groupedMedia: [first, caption],
            peerTitle: 'Test',
            isGroup: false,
            onDesktopQuoteChanged: (_, quote) => selected = quote,
            onLongPress: (message, _, _) {
              menus++;
              menuMessage = message;
            },
          ),
          TargetPlatform.macOS,
        ),
      );
      final text = find.text(sourceText, findRichText: true);
      await selectRange(tester, text, 20, 28);
      await tester.tapAt(
        textPosition(tester, text, 24),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      expect(menus, 1);
      expect(menuMessage, same(caption));
      expect(selected?.text, 'selected');
      expect(selected?.position, 20);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final codeType in ['textEntityTypeCode', 'textEntityTypePreCode']) {
    testWidgets(
      '$codeType preserves source text across nested selection containers',
      (tester) async {
        MessageTextQuote? selected;
        final message = ChatMessage(
          id: 78,
          isOutgoing: false,
          date: 1,
          text: sourceText,
          contentType: 'messageText',
          textEntities: [
            MessageTextEntity(offset: 7, length: 8, type: codeType),
          ],
        );
        await tester.pumpWidget(
          app(
            MessageBubble(
              message: message,
              peerTitle: 'Test',
              isGroup: false,
              onDesktopQuoteChanged: (_, quote) => selected = quote,
            ),
            TargetPlatform.macOS,
          ),
        );
        await tester.pumpAndSettle();
        tester
            .state<SelectionAreaState>(find.byType(SelectionArea).first)
            .selectableRegion
            .selectAll(SelectionChangedCause.keyboard);
        await tester.pump();
        expect(selected?.text, sourceText);
        expect(selected?.position, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('translated text is not sent as a quote of the original', (
    tester,
  ) async {
    MessageTextQuote? selected;
    final message = ChatMessage(
      id: 78,
      isOutgoing: false,
      date: 1,
      text: sourceText,
      contentType: 'messageText',
    )..translationText = 'translated words';
    await tester.pumpWidget(
      app(
        MessageBubble(
          message: message,
          peerTitle: 'Test',
          isGroup: false,
          translationDisplayStyle: TranslationDisplayStyle.translatedOnly,
          onDesktopQuoteChanged: (_, quote) => selected = quote,
        ),
        TargetPlatform.macOS,
      ),
    );
    await selectRange(
      tester,
      find.text('translated words', findRichText: true),
      0,
      10,
    );
    expect(selected, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
