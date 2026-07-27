import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/message_bubble_background.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'large link media stays clipped to decorative bubble content geometry',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final theme = ThemeController(preferences)
        ..messageBubbleBackground = MessageBubbleBackground.pastryPal
        ..messageBubbleApplicationScope =
            MessageBubbleApplicationScope.allMessages;
      addTearDown(theme.dispose);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final message = ChatMessage(
        id: 6428,
        isOutgoing: false,
        text: 'https://t.me/example/6428',
        date: 1,
        senderName: 'Preview sender',
        linkPreview: MessageLinkPreview(
          url: 'https://t.me/example/6428',
          displayUrl: 't.me/example/6428',
          siteName: 'Telegram',
          title: 'A quoted post with a large image',
          description: '',
          image: TdFileRef(
            id: -6428,
            localPath: 'assets/message_bubbles/pastry-pal.png',
          ),
          imageWidth: 1600,
          imageHeight: 900,
          showLargeMedia: true,
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: message,
                peerTitle: 'Preview chat',
                isGroup: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bubble = find.byKey(const ValueKey('messageTextBubble-6428'));
      final card = find.byKey(const ValueKey('messageLinkPreviewCard-6428'));
      final media = find.byKey(const ValueKey('messageLinkPreviewMedia-6428'));
      final bubbleRect = tester.getRect(bubble);
      final cardRect = tester.getRect(card);
      final mediaRect = tester.getRect(media);

      expect(cardRect.left, greaterThanOrEqualTo(bubbleRect.left));
      expect(cardRect.right, lessThanOrEqualTo(bubbleRect.right));
      expect(mediaRect.left, greaterThanOrEqualTo(cardRect.left));
      expect(mediaRect.right, lessThanOrEqualTo(cardRect.right));
      expect(mediaRect.width / mediaRect.height, closeTo(16 / 9, 0.01));

      final cardContainer = tester.widget<Container>(card);
      final decoration = cardContainer.decoration! as BoxDecoration;
      expect(decoration.color!.a, 1);
      expect(cardContainer.clipBehavior, Clip.antiAlias);
      expect(tester.takeException(), isNull);
    },
  );
}
