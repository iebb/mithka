import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/chat/message_replies_sheet.dart';
import 'package:mithka/chat/rich_text_format.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('reply sheet requests share channel and nested reply routing', () {
    const formatted = FormattedTextPayload('Nested reply', []);
    final forum = buildReplySheetTextRequest(
      chatId: -1001,
      formatted: formatted,
      topicId: const {'@type': 'messageTopicForum', 'forum_topic_id': 77},
      legacyMessageThreadId: 77,
      replyToMessageId: 42,
    );
    expect((forum['topic_id'] as Map)['@type'], 'messageTopicForum');
    expect(forum['message_thread_id'], 77);
    expect((forum['reply_to'] as Map)['message_id'], 42);

    final thread = buildReplySheetTextRequest(
      chatId: -2002,
      formatted: formatted,
      topicId: const {'@type': 'messageTopicThread', 'message_thread_id': 99},
    );
    expect((thread['topic_id'] as Map)['@type'], 'messageTopicThread');
    expect(thread, isNot(contains('reply_to')));
  });

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
    ChatMessage? replied;

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
                    onReply: (message) => replied = message,
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
      find.byKey(const ValueKey('messageTappedTimestamp')),
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

    final richBubble = tester.widget<MessageBubble>(
      find.byKey(const ValueKey('messageRepliesSheetMessage-42')),
    );
    richBubble.onReply?.call(rich);
    expect(replied, same(rich));

    final play = find.byWidgetPredicate(
      (widget) => widget is AppIcon && widget.icon == HeroAppIcons.play,
    );
    expect(play, findsOneWidget);
    await tester.tap(play);
    expect(played, same(video));
    expect(tester.takeException(), isNull);
  });
}
