import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_bubble_chat_preview.dart';
import 'package:mithka/chat/stretchable_message_bubble_background.dart';
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

  testWidgets('decorative preview keeps its selected artwork surfaces', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.dark]),
        home: const Scaffold(
          body: MessageBubbleChatPreview(
            incomingBackground: MessageBubbleBackgroundSpec.midnightAurora,
            outgoingBackground: MessageBubbleBackgroundSpec.emberArcade,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(StretchableMessageBubbleBackground), findsNWidgets(2));
    final incoming = tester.widget<StretchableMessageBubbleBackground>(
      find.descendant(
        of: find.byKey(const ValueKey('message-bubble-preview-incoming')),
        matching: find.byType(StretchableMessageBubbleBackground),
      ),
    );
    expect(
      incoming.background.selection,
      MessageBubbleBackground.midnightAurora,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('flat preview keeps standard messages readable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.dark]),
        home: const Scaffold(
          body: MessageBubbleChatPreview(
            showIncomingSurface: false,
            showOutgoingSurface: false,
            incomingBackground: MessageBubbleBackgroundSpec.standard,
            outgoingBackground: MessageBubbleBackgroundSpec.standard,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(StretchableMessageBubbleBackground), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('message-bubble-preview-incoming')),
        matching: find.byType(DecoratedBox),
      ),
      findsNothing,
    );
    for (final message in const [
      'Repository bubble preview with a longer message.',
      'The center stretches with longer messages.',
    ]) {
      expect(
        tester.widget<Text>(find.text(message)).style?.color,
        AppColors.dark.textPrimary,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview represents theme-provided surface and text colors', (
    tester,
  ) async {
    const incomingSurface = Color(0xFF123456);
    const outgoingSurface = Color(0xFF654321);
    const incomingText = Color(0xFFF1E2D3);
    const outgoingText = Color(0xFFD3E2F1);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.dark]),
        home: const Scaffold(
          body: MessageBubbleChatPreview(
            incomingBackground: MessageBubbleBackgroundSpec.standard,
            outgoingBackground: MessageBubbleBackgroundSpec.standard,
            incomingSurfaceColor: incomingSurface,
            outgoingSurfaceColor: outgoingSurface,
            incomingTextColor: incomingText,
            outgoingTextColor: outgoingText,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final surfaces = tester.widgetList<StretchableMessageBubbleBackground>(
      find.byType(StretchableMessageBubbleBackground),
    );
    expect(surfaces.map((surface) => surface.fallbackColor), [
      incomingSurface,
      outgoingSurface,
    ]);
    expect(
      tester
          .widget<Text>(
            find.text('Repository bubble preview with a longer message.'),
          )
          .style
          ?.color,
      incomingText,
    );
    expect(
      tester
          .widget<Text>(find.text('The center stretches with longer messages.'))
          .style
          ?.color,
      outgoingText,
    );
  });
}
