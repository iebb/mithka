import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('code block uses a five percent $brightness tint', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final theme = ThemeController(preferences);
      addTearDown(theme.dispose);
      final message = ChatMessage(
        id: 1,
        isOutgoing: false,
        text: 'final value = 5;',
        date: 1,
        textEntities: const [
          MessageTextEntity(
            offset: 0,
            length: 16,
            type: 'textEntityTypePreCode',
            language: 'dart',
          ),
        ],
      );
      final colors = brightness == Brightness.dark
          ? AppColors.dark
          : AppColors.light;

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            theme: ThemeData(brightness: brightness, extensions: [colors]),
            home: Scaffold(
              body: MessageBubble(
                message: message,
                peerTitle: 'Code',
                isGroup: false,
              ),
            ),
          ),
        ),
      );

      final surface = find.descendant(
        of: find.byKey(const ValueKey('message-code-block-1-0-16')),
        matching: find.byWidgetPredicate(
          (widget) => widget is Container && widget.decoration is BoxDecoration,
        ),
      );
      final decoration =
          tester.widget<Container>(surface.first).decoration! as BoxDecoration;
      expect(decoration.color!.a, closeTo(0.05, 0.001));
    });
  }

  testWidgets('forwarded messages render each code block with a unique key', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    final message = ChatMessage(
      id: 9,
      isOutgoing: false,
      text: 'one\ntwo',
      date: 1,
      contentType: 'messageText',
      textEntities: const [
        MessageTextEntity(offset: 0, length: 3, type: 'textEntityTypePreCode'),
        MessageTextEntity(offset: 4, length: 3, type: 'textEntityTypePreCode'),
      ],
    )..forwardOrigin = 'Original Channel';

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              peerTitle: 'Code',
              isGroup: false,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('messageForwardHeader-9')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('message-code-block-9-0-3')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('message-code-block-9-4-7')),
      findsOneWidget,
    );
    expect(find.text('one', findRichText: true), findsOneWidget);
    expect(find.text('two', findRichText: true), findsOneWidget);
  });
}
