import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/chat/telegram_rich_text.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The painted runs of a paragraph, so a test can see which text ended up
/// carrying which style.
List<({String text, TextStyle? style})> paintedRuns(RenderParagraph paragraph) {
  final runs = <({String text, TextStyle? style})>[];
  paragraph.text.visitChildren((span) {
    if (span is TextSpan && span.text != null) {
      runs.add((text: span.text!, style: span.style));
    }
    return true;
  });
  return runs;
}

void main() {
  Future<ThemeController> theme({bool receive = false}) async {
    SharedPreferences.setMockInitialValues({'panguOnReceive': receive});
    final preferences = await SharedPreferences.getInstance();
    final controller = ThemeController(preferences);
    addTearDown(controller.dispose);
    return controller;
  }

  Widget bubble(ThemeController theme, ChatMessage message) =>
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          home: Scaffold(
            body: MessageBubble(
              message: message,
              peerTitle: 'Pangu',
              isGroup: false,
            ),
          ),
        ),
      );

  ChatMessage mixed({List<MessageTextEntity> entities = const []}) =>
      ChatMessage(
        id: 1,
        isOutgoing: false,
        date: 1,
        contentType: 'messageText',
        text: '中文English中文',
        textEntities: entities,
      );

  testWidgets('a mixed message paints as authored while the switch is off', (
    tester,
  ) async {
    final controller = await theme();
    await tester.pumpWidget(bubble(controller, mixed()));
    await tester.pumpAndSettle();
    expect(find.text('中文English中文', findRichText: true), findsOneWidget);
  });

  testWidgets('a mixed message gains one space per boundary when it is on', (
    tester,
  ) async {
    final controller = await theme(receive: true);
    await tester.pumpWidget(bubble(controller, mixed()));
    await tester.pumpAndSettle();
    expect(find.text('中文 English 中文', findRichText: true), findsOneWidget);
  });

  testWidgets('the switch takes effect on the next frame', (tester) async {
    final controller = await theme();
    await tester.pumpWidget(bubble(controller, mixed()));
    await tester.pumpAndSettle();
    expect(find.text('中文English中文', findRichText: true), findsOneWidget);

    controller.panguOnReceive = true;
    await tester.pumpAndSettle();
    expect(find.text('中文 English 中文', findRichText: true), findsOneWidget);

    controller.panguOnReceive = false;
    await tester.pumpAndSettle();
    expect(find.text('中文English中文', findRichText: true), findsOneWidget);
  });

  testWidgets('a bold run keeps exactly the text it styled', (tester) async {
    final controller = await theme(receive: true);
    await tester.pumpWidget(
      bubble(
        controller,
        mixed(
          entities: const [
            MessageTextEntity(offset: 2, length: 7, type: 'textEntityTypeBold'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('中文 English 中文', findRichText: true),
    );
    final bold = paintedRuns(
      paragraph,
    ).where((run) => run.style?.fontWeight == FontWeight.w600).toList();
    expect(bold.map((run) => run.text).join(), 'English');
  });

  testWidgets('a code block moves with the text and keeps its content', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 1,
      isOutgoing: false,
      date: 1,
      contentType: 'messageText',
      text: '中文code中文',
      textEntities: const [
        MessageTextEntity(
          offset: 2,
          length: 4,
          type: 'textEntityTypePreCode',
          language: 'dart',
        ),
      ],
    );

    final plain = await theme();
    await tester.pumpWidget(bubble(plain, message));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('message-code-block-1-2-6')),
      findsOneWidget,
    );

    final spaced = await theme(receive: true);
    await tester.pumpWidget(bubble(spaced, message));
    await tester.pumpAndSettle();
    // The block's key carries the shifted offsets, and the run inside it is the
    // untouched code.
    expect(
      find.byKey(const ValueKey('message-code-block-1-3-7')),
      findsOneWidget,
    );
    expect(find.text('code', findRichText: true), findsOneWidget);
  });

  testWidgets('a message that is only CJK is left alone', (tester) async {
    final controller = await theme(receive: true);
    final message = ChatMessage(
      id: 1,
      isOutgoing: false,
      date: 1,
      contentType: 'messageText',
      text: '今天天气不错',
    );
    await tester.pumpWidget(bubble(controller, message));
    await tester.pumpAndSettle();
    expect(find.text('今天天气不错', findRichText: true), findsOneWidget);
  });

  testWidgets('rich text outside the transcript spaces the same way', (
    tester,
  ) async {
    final controller = await theme(receive: true);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: controller,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          home: const Scaffold(
            body: TelegramRichText(
              text: '简介English简介',
              entities: [
                MessageTextEntity(
                  offset: 2,
                  length: 7,
                  type: 'textEntityTypeItalic',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('简介 English 简介', findRichText: true),
    );
    final italic = paintedRuns(
      paragraph,
    ).where((run) => run.style?.fontStyle == FontStyle.italic).toList();
    expect(italic.map((run) => run.text).join(), 'English');
  });
}
