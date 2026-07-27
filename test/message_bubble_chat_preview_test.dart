import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_bubble_chat_preview.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/message_bubble_background.dart';

void main() {
  testWidgets(
    'bubble preview hugs its messages while remaining width-responsive',
    (tester) async {
      Future<Size> pumpPreview(double width) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(extensions: [AppColors.dark]),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: const MessageBubbleChatPreview(
                    incomingBackground: MessageBubbleBackgroundSpec.standard,
                    outgoingBackground:
                        MessageBubbleBackgroundSpec.midnightAurora,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return tester.getSize(
          find.byKey(const ValueKey('message-bubble-chat-preview')),
        );
      }

      final wideSize = await pumpPreview(420);

      expect(wideSize.width, 420);
      expect(wideSize.height, lessThan(225));
      expect(find.byType(PhotoAvatar), findsOneWidget);
      expect(
        find.text('Repository bubble preview with a longer message.'),
        findsOneWidget,
      );
      expect(
        find.text('The center stretches with longer messages.'),
        findsOneWidget,
      );

      final preview = find.byKey(const ValueKey('message-bubble-chat-preview'));
      final outgoing = find.byKey(
        const ValueKey('message-bubble-preview-outgoing'),
      );
      expect(
        tester.getBottomRight(preview).dy - tester.getBottomRight(outgoing).dy,
        11,
      );

      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: outgoing,
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(
        decoration.image?.centerSlice,
        MessageBubbleBackgroundSpec.midnightAurora.centerSlice,
      );

      final narrowSize = await pumpPreview(240);
      expect(narrowSize.width, 240);
      expect(narrowSize.height, greaterThan(wideSize.height));
      expect(narrowSize.height, lessThan(350));
      expect(tester.takeException(), isNull);
    },
  );
}
