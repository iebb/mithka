//
//  message_bubble_swipe_reply_test.dart
//
//  Swipe-to-reply. The reply glyph is deliberately absent from a bubble at
//  rest — every mounted bubble used to build and lay out an Icon that opacity
//  0 then hid — so these cover both halves: nothing while idle, and the real
//  affordance the moment a drag starts.
//

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final replyIcon = find.byWidgetPredicate(
    (widget) => widget is AppIcon && widget.icon == HeroAppIcons.reply,
  );
  final bubbleText = find.text('Swipe me', findRichText: true);

  /// Pumps one incoming bubble and returns a reader for the replied-to message.
  Future<ChatMessage? Function()> pumpBubble(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    ChatMessage? replied;

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MessageBubble(
              message: ChatMessage(
                id: 78,
                isOutgoing: false,
                text: 'Swipe me',
                date: 1785862260,
              ),
              peerTitle: 'Test',
              isGroup: false,
              onReply: (message) => replied = message,
            ),
          ),
        ),
      ),
    );
    return () => replied;
  }

  /// Drags left in steps, the way a finger arrives, so the recognizer claims
  /// the gesture and each update reaches the swipe controller.
  Future<TestGesture> dragLeft(
    WidgetTester tester, {
    required int steps,
  }) async {
    final gesture = await tester.startGesture(tester.getCenter(bubbleText));
    for (var step = 0; step < steps; step++) {
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    return gesture;
  }

  testWidgets('a bubble at rest builds no reply glyph', (tester) async {
    await pumpBubble(tester);

    expect(replyIcon, findsNothing);
    // Guard the finder itself: a predicate that never matches would make the
    // assertion above pass for the wrong reason.
    expect(find.byType(MessageBubble), findsOneWidget);
  });

  testWidgets('a swipe past the trigger reveals the glyph and replies', (
    tester,
  ) async {
    final replied = await pumpBubble(tester);
    expect(replyIcon, findsNothing);

    final gesture = await dragLeft(tester, steps: 12);
    expect(
      replyIcon,
      findsOneWidget,
      reason: 'the affordance appears as soon as the bubble moves',
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(replied()?.id, 78);
    expect(
      replyIcon,
      findsNothing,
      reason: 'and goes away again once the bubble springs back',
    );
  });

  testWidgets('a short swipe reveals the glyph but does not reply', (
    tester,
  ) async {
    final replied = await pumpBubble(tester);

    final gesture = await dragLeft(tester, steps: 2);
    expect(replyIcon, findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(replied(), isNull);
    expect(replyIcon, findsNothing);
  });
}
