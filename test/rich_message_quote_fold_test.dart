import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _tallViewport = Size(420, 1600);

String get _expandLabel => AppStrings.t(AppStringKeys.messageBubbleExpandQuote);
String get _collapseLabel => AppStrings.t(AppStringKeys.messageBubbleCollapse);

/// Enough prose to run well past three lines in a 420px-wide bubble.
const _longQuote =
    'A quote that keeps going long enough to need folding: it carries several '
    'sentences of ordinary prose, mentions a link to https://example.com and '
    'still has more to say about the shape of the paragraph before it finally '
    'stops, well below the three-line cap that the bubble applies.';

Future<void> _pumpBubble(WidgetTester tester, ChatMessage message) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = _tallViewport;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final theme = ThemeController(preferences);
  addTearDown(theme.dispose);

  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: MessageBubble(
              message: message,
              peerTitle: 'Test',
              isGroup: false,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ChatMessage _richMessage(int id, List<RichMessageBlock> blocks) => ChatMessage(
  id: id,
  chatId: 42,
  isOutgoing: false,
  text: '',
  date: 1,
  contentType: 'messageRichMessage',
  richBlocks: blocks,
);

RichMessageBlock _richQuote(RichMessageBlockKind kind, String text) =>
    RichMessageBlock.container(
      kind: kind,
      text: kind == RichMessageBlockKind.pullQuote ? text : '',
      children: kind == RichMessageBlockKind.pullQuote
          ? const []
          : [
              RichMessageBlock.text(
                kind: RichMessageBlockKind.paragraph,
                text: text,
              ),
            ],
    );

double _blockHeight(WidgetTester tester, int index, String kind) => tester
    .getSize(find.byKey(ValueKey('rich-message-block-$index-$kind')))
    .height;

double _paragraphHeight(WidgetTester tester, String text) => tester
    .renderObject<RenderParagraph>(find.text(text, findRichText: true))
    .size
    .height;

/// The paragraph's own line height, measured from the style it was laid out
/// with.
double _lineHeight(WidgetTester tester, String text) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.text(text, findRichText: true),
  );
  final painter = TextPainter(
    text: TextSpan(text: 'M', style: paragraph.text.style),
    textDirection: TextDirection.ltr,
  )..layout();
  final height = painter.height;
  painter.dispose();
  return height;
}

void main() {
  testWidgets(
    'a short rich block quote renders unfolded without an affordance',
    (tester) async {
      const text = 'Short quote';
      await _pumpBubble(
        tester,
        _richMessage(910, [_richQuote(RichMessageBlockKind.blockQuote, text)]),
      );

      expect(find.text(_expandLabel), findsNothing);
      expect(find.text(_collapseLabel), findsNothing);
      // Vertically the block is the paragraph plus its 7px top and bottom frame
      // padding: nothing was clipped away.
      expect(
        _blockHeight(tester, 0, 'blockQuote'),
        moreOrLessEquals(_paragraphHeight(tester, text) + 14, epsilon: 0.5),
      );
    },
  );

  testWidgets('a long rich block quote folds, expands on tap and folds again', (
    tester,
  ) async {
    await _pumpBubble(
      tester,
      _richMessage(911, [
        _richQuote(RichMessageBlockKind.blockQuote, _longQuote),
      ]),
    );

    final block = find.byKey(const ValueKey('rich-message-block-0-blockQuote'));
    final foldedHeight = tester.getSize(block).height;
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text(_longQuote, findRichText: true),
    );
    final bodyHeight = paragraph.size.height;
    expect(find.text(_expandLabel), findsOneWidget);
    expect(foldedHeight, lessThan(bodyHeight));
    // The cap is exactly three of the body's own lines, plus the frame's 7px
    // top and bottom padding, the 4px label gap and the label itself.
    final threeLines = 3 * _lineHeight(tester, _longQuote);
    expect(
      foldedHeight,
      moreOrLessEquals(
        threeLines + 14 + 4 + tester.getSize(find.text(_expandLabel)).height,
        epsilon: 1,
      ),
    );

    await tester.tap(block);
    await tester.pumpAndSettle();
    expect(find.text(_expandLabel), findsNothing);
    expect(find.text(_collapseLabel), findsOneWidget);
    final expandedHeight = tester.getSize(block).height;
    expect(expandedHeight, greaterThan(foldedHeight + 20));

    await tester.tap(block);
    await tester.pumpAndSettle();
    expect(find.text(_expandLabel), findsOneWidget);
    expect(tester.getSize(block).height, moreOrLessEquals(foldedHeight));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long pull quote never folds', (tester) async {
    await _pumpBubble(
      tester,
      _richMessage(912, [
        _richQuote(RichMessageBlockKind.pullQuote, _longQuote),
      ]),
    );

    expect(find.text(_expandLabel), findsNothing);
    expect(
      _blockHeight(tester, 0, 'pullQuote'),
      moreOrLessEquals(_paragraphHeight(tester, _longQuote) + 14, epsilon: 0.5),
    );
  });

  testWidgets('each rich block quote folds on its own identity', (
    tester,
  ) async {
    const shortText = 'Short quote';
    await _pumpBubble(
      tester,
      _richMessage(914, [
        _richQuote(RichMessageBlockKind.blockQuote, shortText),
        _richQuote(RichMessageBlockKind.blockQuote, _longQuote),
      ]),
    );

    expect(find.text(_expandLabel), findsOneWidget);
    final longBlock = find.byKey(
      const ValueKey('rich-message-block-1-blockQuote'),
    );
    final foldedHeight = tester.getSize(longBlock).height;
    await tester.tap(longBlock);
    await tester.pumpAndSettle();
    expect(find.text(_collapseLabel), findsOneWidget);
    expect(tester.getSize(longBlock).height, greaterThan(foldedHeight));
    expect(
      _blockHeight(tester, 0, 'blockQuote'),
      moreOrLessEquals(_paragraphHeight(tester, shortText) + 14, epsilon: 0.5),
    );
  });

  testWidgets('a quote that carries media does not fold', (tester) async {
    await _pumpBubble(
      tester,
      _richMessage(915, [
        const RichMessageBlock.container(
          kind: RichMessageBlockKind.blockQuote,
          children: [
            RichMessageBlock.text(
              kind: RichMessageBlockKind.paragraph,
              text: _longQuote,
            ),
            RichMessageBlock.media(
              kind: RichMessageBlockKind.photo,
              imageWidth: 400,
              imageHeight: 300,
              caption: 'A photo',
            ),
          ],
        ),
      ]),
    );

    // The three-line cap would slice the photo, so the quote stays whole and
    // offers no toggle.
    expect(find.text(_expandLabel), findsNothing);
    expect(find.text(_collapseLabel), findsNothing);
    expect(
      _blockHeight(tester, 0, 'blockQuote'),
      greaterThan(_paragraphHeight(tester, _longQuote) + 14),
    );
  });

  testWidgets('entity block quotes still fold through the same toggle', (
    tester,
  ) async {
    const text = 'Intro line\n$_longQuote';
    final message = ChatMessage(
      id: 913,
      chatId: 42,
      isOutgoing: false,
      text: text,
      date: 1,
      contentType: 'messageText',
      textEntities: const [
        MessageTextEntity(
          offset: 11,
          length: 279,
          type: 'textEntityTypeExpandableBlockQuote',
        ),
      ],
    );
    await _pumpBubble(tester, message);

    final quote = find.byKey(const ValueKey('messageBlockQuote-913-11:279'));
    expect(find.text(_expandLabel), findsOneWidget);

    await tester.tap(quote);
    await tester.pumpAndSettle();
    expect(find.text(_collapseLabel), findsOneWidget);

    await tester.tap(quote);
    await tester.pumpAndSettle();
    expect(find.text(_expandLabel), findsOneWidget);
  });
}
