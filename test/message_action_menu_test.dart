import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_action_menu.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('message action rows stay balanced', () {
    expect(MessageActionMenu.rowCountsForActionCount(6), (first: 3, second: 3));
    expect(MessageActionMenu.rowCountsForActionCount(7), (first: 4, second: 3));
    expect(MessageActionMenu.rowCountsForActionCount(8), (first: 4, second: 4));
    expect(MessageActionMenu.rowCountsForActionCount(9), (first: 5, second: 4));

    for (var count = 6; count <= 24; count++) {
      final rows = MessageActionMenu.rowCountsForActionCount(count);
      expect(rows.first - rows.second, inInclusiveRange(0, 1));
    }
  });

  test('action menu matches the compact reaction bar width', () {
    expect(MessageActionMenu.widthForAvailable(400), 332);
    expect(MessageActionMenu.widthForAvailable(300), 300);
  });

  testWidgets('ten or fewer reaction controls fit without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: QuickReactionBar(
            reactions: const ['👍', '❤️', '🔥', '🎉', '😁', '😢', '😡'],
            onReaction: (_) {},
            onExpand: () {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('quick-reaction-bar'))).width,
      MessageActionMenu.preferredWidth,
    );
    expect(find.byKey(const ValueKey('quick-reaction-expand')), findsOneWidget);
  });

  test('+1 preserves sender by default and persists the override', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    expect(theme.preserveSenderWhenRepeating, isTrue);

    theme.preserveSenderWhenRepeating = false;
    expect(ThemeController(prefs).preserveSenderWhenRepeating, isFalse);
  });

  testWidgets('message menu renders +1 at reaction bar width', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final translation = TranslationController(prefs);
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: translation,
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: MessageActionMenu(
                message: ChatMessage(
                  id: 1,
                  isOutgoing: false,
                  text: 'message',
                  date: 1,
                  contentType: 'messageText',
                ),
                isPinned: false,
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('+1'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('message-action-menu-surface')))
          .width,
      MessageActionMenu.preferredWidth,
    );
  });

  testWidgets('captionless outgoing media still exposes edit', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final translation = TranslationController(prefs);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: translation,
        child: MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MessageActionMenu(
              message: ChatMessage(
                id: 2,
                isOutgoing: true,
                text: '',
                date: 1,
                contentType: 'messagePhoto',
              ),
              isPinned: false,
              onSelect: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Edit'), findsOneWidget);
  });
}
