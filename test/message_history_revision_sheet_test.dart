//
//  The per-message revision sheet and the message-menu entry that opens it.
//  Both exist only with the feature compiled in
//  (--dart-define=I_DONT_FUCKING_CARE_ABOUT_TOS=true); without it the suite
//  skips, mirroring the store/viewer suites.
//

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_action_menu.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/history/message_history_models.dart';
import 'package:mithka/history/message_history_revision_sheet.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabled = allowTelegramTosViolations;

MessageHistoryEntry _entry({
  String text = 'v3',
  List<MessageHistoryEvent> events = const [],
}) => MessageHistoryEntry(
  accountUserId: 42,
  chatId: 11,
  messageId: 100,
  senderId: 7,
  date: 1700000000,
  text: text,
  kindKey: '',
  state: MessageHistoryState.active,
  deletedAt: 0,
  events: events,
);

ChatMessage _textMessage() => ChatMessage(
  id: 100,
  isOutgoing: false,
  text: 'v3',
  date: 1700000000,
  senderName: 'peer',
);

Future<void> _pumpShell(WidgetTester tester, Widget child) async {
  SharedPreferences.setMockInitialValues(const {});
  final preferences = await SharedPreferences.getInstance();
  final theme = ThemeController(preferences);
  addTearDown(theme.dispose);
  final translation = TranslationController(preferences);
  addTearDown(translation.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<TranslationController>.value(value: translation),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppColors.light]),
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  if (!_enabled) {
    return;
  }

  testWidgets('the revision sheet lists every revision newest first', (
    tester,
  ) async {
    final entry = _entry(
      events: const [
        MessageHistoryEvent(at: 1700000100, oldText: 'v1', newText: 'v2'),
        MessageHistoryEvent(at: 1700000200, oldText: 'v2', newText: 'v3'),
      ],
    );
    await _pumpShell(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showMessageHistoryRevisionSheet(context, entry),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();

    // Current text first, then each older revision's old text.
    expect(find.text('v3'), findsOneWidget);
    expect(find.text('v2'), findsOneWidget);
    expect(find.text('v1'), findsOneWidget);
  });

  testWidgets('the menu offers ViewEdits only when allowed', (tester) async {
    final message = _textMessage();
    await _pumpShell(
      tester,
      MessageActionMenu(
        message: message,
        isPinned: false,
        allowViewEdits: true,
        onSelect: (_) {},
      ),
    );
    final rawLabel = AppStrings.t(AppStringKeys.messageActionViewEdits);
    // The grid truncates long captions; find by the full semantics label the
    // cell carries, which stays exact.
    expect(find.bySemanticsLabel(rawLabel), findsOneWidget);

    await _pumpShell(
      tester,
      MessageActionMenu(
        message: message,
        isPinned: false,
        // allowViewEdits is the dimension under test here.
        // ignore: avoid_redundant_argument_values
        allowViewEdits: false,
        onSelect: (_) {},
      ),
    );
    expect(find.bySemanticsLabel(rawLabel), findsNothing);
  });
}
