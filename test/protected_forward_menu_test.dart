import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/messages/message_action_menu.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/ai_translation/translation_controller.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

/// Protected chats with the copy-forward toggle on must still expose 转发 in
/// the long-press menu: the entry routes through forwardMany, which re-sends
/// as a copy. The user's report: the route existed but the menu entry was
/// missing, so a restricted message had no forward option at all.
void main() {
  setUpAll(() => L10nFixtures.load().install());

  ChatMessage message({bool isService = false}) => ChatMessage(
    id: 1,
    isOutgoing: false,
    text: 'hello',
    date: 1700000000,
    chatId: 100,
    contentType: 'messageText',
    isService: isService,
  );

  Future<void> pumpMenu(
    WidgetTester tester, {
    required bool allowForwarding,
    bool allowProtectedCopyForward = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferences.getInstance();
    final translation = TranslationController(
      await SharedPreferences.getInstance(),
    );
    addTearDown(translation.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<TranslationController>.value(
        value: translation,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppColors.light]),
          home: Scaffold(
            body: MessageActionMenu(
              message: message(),
              isPinned: false,
              onSelect: (_) {},
              allowForwarding: allowForwarding,
              allowProtectedCopyForward: allowProtectedCopyForward,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('protected chat with copy-forward shows the forward entry', (
    tester,
  ) async {
    await pumpMenu(
      tester,
      allowForwarding: false,
      allowProtectedCopyForward: true,
    );
    expect(find.text('Forward'), findsOneWidget);
    // Repeat rides the same copy route in a protected chat: it re-sends the
    // message as a no-quote copy into the CURRENT chat.
    expect(find.text('Repeat'), findsOneWidget);
  });

  testWidgets('protected chat without the toggle hides forward entirely', (
    tester,
  ) async {
    // Failing-first: the menu used to decide on allowForwarding alone, so a
    // protected chat with the copy route live still showed nothing.
    await pumpMenu(tester, allowForwarding: false);
    expect(find.text('Forward'), findsNothing);
    expect(find.text('Repeat'), findsNothing);
  });

  testWidgets('ordinary chats keep forward and repeat as a pair', (
    tester,
  ) async {
    await pumpMenu(tester, allowForwarding: true);
    expect(find.text('Forward'), findsOneWidget);
    expect(find.text('Repeat'), findsOneWidget);
  });

  testWidgets('service messages never gain the copy-forward entry', (
    tester,
  ) async {
    final translation = TranslationController(
      await SharedPreferences.getInstance(),
    );
    addTearDown(translation.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<TranslationController>.value(
        value: translation,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppColors.light]),
          home: Scaffold(
            body: MessageActionMenu(
              message: message(isService: true),
              isPinned: false,
              onSelect: (_) {},
              allowForwarding: false,
              allowProtectedCopyForward: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Forward'), findsNothing);
  });
}
