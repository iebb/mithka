import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reply quote preserves formatting entities', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);

    final message = ChatMessage(
      id: 42,
      isOutgoing: false,
      text: 'A reply',
      date: 2,
      replyToMessageId: 7,
      replyToEntities: const [
        MessageTextEntity(offset: 0, length: 9, type: 'textEntityTypeBold'),
      ],
    );
    message.replyToSender = 'Sender';
    message.replyToPreview = 'formatted quote';

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
              message: message,
              peerTitle: 'Test',
              isGroup: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final quote = find.byKey(const ValueKey('messageReplyQuote'));
    final richTexts = tester
        .widgetList<RichText>(
          find.descendant(of: quote, matching: find.byType(RichText)),
        )
        .where((richText) => richText.text.toPlainText() == 'formatted quote')
        .toList();
    expect(richTexts, hasLength(1));
    final spans = (richTexts.single.text as TextSpan).children!;
    expect(spans.first.toPlainText(), 'formatted');
    expect(spans.first.style?.fontWeight, isNotNull);
  });
}
