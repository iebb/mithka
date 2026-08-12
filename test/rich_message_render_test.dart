import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('rich tables paint full backgrounds behind uneven cells', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);
    final message = ChatMessage(
      id: 899,
      chatId: 42,
      isOutgoing: false,
      text: '',
      date: 1,
      contentType: 'messageRichMessage',
      richBlocks: const [
        RichMessageBlock.captionedTable(
          tableRows: [
            [
              RichMessageTableCell(text: 'UTC', isHeader: true),
              RichMessageTableCell(text: 'Balance', isHeader: true),
            ],
            [
              RichMessageTableCell(text: '00:45'),
              RichMessageTableCell(text: '135.7000 USD\n→ 93.1000 USD'),
            ],
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              peerTitle: 'Test',
              isGroup: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final table = tester.widget<Table>(find.byType(Table));
    expect(table.children, hasLength(2));
    final bodyCells = table.children[1].children.cast<TableCell>();
    final firstCell = find.byWidget(bodyCells[0].child);
    final secondCell = find.byWidget(bodyCells[1].child);
    expect(tester.getTopLeft(firstCell).dy, tester.getTopLeft(secondCell).dy);
    expect(
      tester.getBottomLeft(firstCell).dy,
      tester.getBottomLeft(secondCell).dy,
    );
    expect(tester.getSize(firstCell).height, tester.getSize(secondCell).height);
    for (final cell in bodyCells) {
      expect((cell.child as Container).color, isNotNull);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('MessageBubble renders every rich message block kind', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);

    const paragraph = RichMessageBlock.text(
      kind: RichMessageBlockKind.paragraph,
      text: 'Paragraph',
    );
    final selectionKey = GlobalKey<SelectionAreaState>();
    MessageButton? tappedButton;
    final message = ChatMessage(
      id: 900,
      chatId: 42,
      isOutgoing: false,
      text: '',
      date: 1,
      contentType: 'messageRichMessage',
      richBlocks: [
        paragraph,
        const RichMessageBlock.text(
          kind: RichMessageBlockKind.heading,
          text: 'Heading',
          size: 2,
        ),
        const RichMessageBlock.text(
          kind: RichMessageBlockKind.preformatted,
          text: 'code()',
          language: 'dart',
        ),
        const RichMessageBlock.text(
          kind: RichMessageBlockKind.footer,
          text: 'Footer',
        ),
        const RichMessageBlock.text(
          kind: RichMessageBlockKind.thinking,
          text: 'Thinking',
        ),
        const RichMessageBlock.container(kind: RichMessageBlockKind.divider),
        const RichMessageBlock.math(r'x^2'),
        const RichMessageBlock.container(
          kind: RichMessageBlockKind.anchor,
          name: 'chapter-1',
        ),
        const RichMessageBlock.buttonRow([
          MessageButton(
            text: 'Open Mithka',
            type: 'inlineKeyboardButtonTypeUrl',
            url: 'https://mithka.app',
            style: MessageButtonStyle.success,
          ),
        ], horizontalAlignment: 'center'),
        const RichMessageBlock.container(
          kind: RichMessageBlockKind.list,
          listItems: [
            RichMessageListItem(
              blocks: [paragraph],
              hasCheckbox: true,
              isChecked: true,
            ),
          ],
        ),
        const RichMessageBlock.container(
          kind: RichMessageBlockKind.blockQuote,
          children: [paragraph],
          caption: 'Credit',
        ),
        const RichMessageBlock.container(
          kind: RichMessageBlockKind.pullQuote,
          text: 'Pull quote',
          caption: 'Credit',
        ),
        const RichMessageBlock.media(kind: RichMessageBlockKind.animation),
        const RichMessageBlock.media(kind: RichMessageBlockKind.audio),
        const RichMessageBlock.media(kind: RichMessageBlockKind.photo),
        const RichMessageBlock.media(kind: RichMessageBlockKind.video),
        const RichMessageBlock.media(kind: RichMessageBlockKind.voiceNote),
        const RichMessageBlock.container(
          kind: RichMessageBlockKind.collage,
          children: [RichMessageBlock.media(kind: RichMessageBlockKind.photo)],
          caption: 'Collage',
        ),
        const RichMessageBlock.container(
          kind: RichMessageBlockKind.slideshow,
          children: [RichMessageBlock.media(kind: RichMessageBlockKind.video)],
          caption: 'Slideshow',
        ),
        const RichMessageBlock.captionedTable(
          tableRows: [
            [RichMessageTableCell(text: 'Cell', isHeader: true)],
          ],
          caption: 'Table',
        ),
        const RichMessageBlock.container(
          kind: RichMessageBlockKind.details,
          text: 'Details',
          children: [paragraph],
          isOpen: true,
        ),
        RichMessageBlock.map(
          mapLocation: MessageLocation(
            latitude: 35.681236,
            longitude: 139.767125,
          ),
          caption: 'Tokyo',
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MessageBubble(
                message: message,
                peerTitle: 'Test',
                isGroup: false,
                mobileTextSelectionAreaKey: selectionKey,
                onButtonTap: (_, button) => tappedButton = button,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    for (final kind in RichMessageBlockKind.values) {
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'rich-message-block-',
              ) &&
              (widget.key! as ValueKey<String>).value.endsWith('-${kind.name}'),
        ),
        findsWidgets,
        reason: 'Missing renderer for ${kind.name}',
      );
    }
    expect(find.text('Open Mithka'), findsOneWidget);
    expect(
      tester
          .renderObject<RenderParagraph>(
            find.text('Paragraph', findRichText: true).first,
          )
          .registrar,
      isNotNull,
    );
    expect(
      tester
          .renderObject<RenderParagraph>(
            find.text('Open Mithka', findRichText: true),
          )
          .registrar,
      isNull,
    );
    expect(
      tester
          .renderObject<RenderParagraph>(find.text('dart', findRichText: true))
          .registrar,
      isNull,
    );
    await tester.tap(find.text('Open Mithka'));
    await tester.pump();
    expect(tappedButton?.url, 'https://mithka.app');
    expect(tester.takeException(), isNull);
  });

  testWidgets('rich collage opens its photo siblings at the tapped photo', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);
    final first = TdFileRef(id: 101, localPath: 'assets/penguin.png');
    final videoPoster = TdFileRef(id: 999, localPath: 'assets/penguin.png');
    final second = TdFileRef(id: 102, localPath: 'assets/penguin.png');
    final video = TdFileRef(id: 700, localPath: 'assets/penguin.png');
    final message = ChatMessage(
      id: 901,
      chatId: 42,
      isOutgoing: false,
      text: '',
      date: 1,
      contentType: 'messageRichMessage',
      richBlocks: [
        RichMessageBlock.container(
          kind: RichMessageBlockKind.collage,
          children: [
            RichMessageBlock.media(
              kind: RichMessageBlockKind.photo,
              image: first,
            ),
            RichMessageBlock.media(
              kind: RichMessageBlockKind.video,
              image: videoPoster,
              video: video,
            ),
            RichMessageBlock.media(
              kind: RichMessageBlockKind.photo,
              image: second,
            ),
          ],
        ),
      ],
    );
    List<TdFileRef>? openedItems;
    int? openedIndex;
    ChatMessage? openedVideo;
    ChatMessage? legacyImage;

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              peerTitle: 'Test',
              isGroup: false,
              onOpenImage: (value) => legacyImage = value,
              onOpenImageGallery:
                  ({required List<TdFileRef> items, required int startIndex}) {
                    openedItems = items;
                    openedIndex = startIndex;
                  },
              onPlayVideo: (value) => openedVideo = value,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(_tdImageWithId(102));
    await tester.pump();
    expect(openedItems?.map((item) => item.id), [101, 102]);
    expect(openedIndex, 1);
    expect(legacyImage, isNull);

    await tester.tapAt(
      tester.getCenter(_tdImageWithId(999)) - const Offset(36, 0),
    );
    await tester.pump();
    expect(openedVideo?.video?.id, 700);
    expect(openedItems?.map((item) => item.id), [101, 102]);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('rich slideshow opens its photo siblings at the visible photo', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);
    final first = TdFileRef(id: 201, localPath: 'assets/penguin.png');
    final second = TdFileRef(id: 202, localPath: 'assets/penguin.png');
    final message = ChatMessage(
      id: 902,
      chatId: 42,
      isOutgoing: false,
      text: '',
      date: 1,
      contentType: 'messageRichMessage',
      richBlocks: [
        RichMessageBlock.container(
          kind: RichMessageBlockKind.slideshow,
          children: [
            RichMessageBlock.media(
              kind: RichMessageBlockKind.photo,
              image: first,
            ),
            RichMessageBlock.media(
              kind: RichMessageBlockKind.photo,
              image: second,
            ),
          ],
        ),
      ],
    );
    List<TdFileRef>? openedItems;
    int? openedIndex;

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              peerTitle: 'Test',
              isGroup: false,
              onOpenImageGallery:
                  ({required List<TdFileRef> items, required int startIndex}) {
                    openedItems = items;
                    openedIndex = startIndex;
                  },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(_tdImageWithId(202));
    await tester.pump();
    expect(openedItems?.map((item) => item.id), [201, 202]);
    expect(openedIndex, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('standalone rich photo keeps the existing image callback', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);
    final photo = TdFileRef(id: 301, localPath: 'assets/penguin.png');
    final message = ChatMessage(
      id: 903,
      chatId: 42,
      isOutgoing: false,
      text: '',
      date: 1,
      contentType: 'messageRichMessage',
      richBlocks: [
        RichMessageBlock.media(kind: RichMessageBlockKind.photo, image: photo),
      ],
    );
    ChatMessage? legacyImage;
    var galleryOpened = false;

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              peerTitle: 'Test',
              isGroup: false,
              onOpenImage: (value) => legacyImage = value,
              onOpenImageGallery:
                  ({required List<TdFileRef> items, required int startIndex}) =>
                      galleryOpened = true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(_tdImageWithId(301));
    await tester.pump();
    expect(legacyImage?.id, 903);
    expect(legacyImage?.image?.id, 301);
    expect(galleryOpened, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}

Finder _tdImageWithId(int id) => find.byWidgetPredicate(
  (widget) => widget is TDImage && widget.photo?.id == id,
);
