import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_action_menu.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  L10nFixtures.load().install();

  final replyAction = find.byKey(const ValueKey('message-action-reply'));
  final quoteAction = find.byKey(const ValueKey('message-action-quote'));

  Future<MessageAction?> tapWhenAllowed(
    WidgetTester tester, {
    required bool allowReply,
    required bool allowQuote,
  }) async {
    MessageAction? selected;
    SharedPreferences.setMockInitialValues({});
    final translation = TranslationController(
      await SharedPreferences.getInstance(),
    );
    addTearDown(translation.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: translation,
        child: MaterialApp(
          home: Scaffold(
            body: MessageActionMenu(
              message: ChatMessage(
                id: 7,
                isOutgoing: false,
                text: 'hello',
                date: 1,
                contentType: 'messageText',
              ),
              isPinned: false,
              allowReply: allowReply,
              allowQuote: allowQuote,
              onSelect: (action) => selected = action,
            ),
          ),
        ),
      ),
    );
    final row = allowQuote ? quoteAction : replyAction;
    if (row.evaluate().isNotEmpty) {
      await tester.tap(row);
    }
    return selected;
  }

  testWidgets('reply and quote disappear together when replies are refused', (
    tester,
  ) async {
    expect(
      await tapWhenAllowed(tester, allowReply: false, allowQuote: true),
      isNull,
    );
    expect(replyAction, findsNothing);
    expect(quoteAction, findsNothing);
  });

  testWidgets('reply stays available by default', (tester) async {
    expect(
      await tapWhenAllowed(tester, allowReply: true, allowQuote: false),
      MessageAction.reply,
    );
    expect(replyAction, findsOneWidget);
  });

  testWidgets('quote still follows allowQuote when replies are allowed', (
    tester,
  ) async {
    expect(
      await tapWhenAllowed(tester, allowReply: true, allowQuote: true),
      MessageAction.quote,
    );
    expect(replyAction, findsOneWidget);
    expect(quoteAction, findsOneWidget);
  });
}
