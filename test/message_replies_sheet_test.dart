import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/chat/message_replies_sheet.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('reply sheet items render video and structured rich content', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);

    final video = ChatMessage(
      id: 41,
      isOutgoing: false,
      text: '[Video]',
      date: 1,
      contentType: 'messageVideo',
      senderName: 'Video sender',
      video: TdFileRef(id: 401),
      videoDuration: 75,
      imageWidth: 1280,
      imageHeight: 720,
    );
    final rich = ChatMessage(
      id: 42,
      isOutgoing: false,
      text: '',
      date: 2,
      contentType: 'messageRichMessage',
      senderName: 'Rich sender',
      richBlocks: const [
        RichMessageBlock.text(
          kind: RichMessageBlockKind.heading,
          text: 'Structured reply heading',
          size: 2,
        ),
        RichMessageBlock.text(
          kind: RichMessageBlockKind.paragraph,
          text: 'Formatted reply body',
          entities: [
            MessageTextEntity(offset: 0, length: 9, type: 'textEntityTypeBold'),
          ],
        ),
      ],
    );
    ChatMessage? played;

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  MessageReplySheetItem(
                    message: video,
                    peerTitle: 'Discussion',
                    senderName: 'Video sender',
                    onPlayVideo: (message) => played = message,
                  ),
                  MessageReplySheetItem(
                    message: rich,
                    peerTitle: 'Discussion',
                    senderName: 'Rich sender',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(MessageBubble), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('messageInlineTimestamp')),
      findsNWidgets(2),
    );
    expect(find.text('[Video]'), findsNothing);
    expect(
      find.text('Structured reply heading', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.text('Formatted reply body', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('rich-message-block-0-heading')),
      findsOneWidget,
    );

    final play = find.byWidgetPredicate(
      (widget) => widget is AppIcon && widget.icon == HeroAppIcons.play,
    );
    expect(play, findsOneWidget);
    await tester.tap(play);
    expect(played, same(video));
    expect(tester.takeException(), isNull);
  });
}
