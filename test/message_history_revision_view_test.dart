//
//  Full-screen edit history view: revisions render newest first with the
//  media snapshot each revision had; the old bottom sheet is gone.
//

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/ui_components.dart' show SettingsNote;
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/history/message_history_models.dart';
import 'package:mithka/history/message_history_revision_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabled = allowTelegramTosViolations;

MessageHistoryEvent _event(int at, String oldText, {String oldKind = ''}) =>
    MessageHistoryEvent(
      at: at,
      oldText: oldText,
      newText: 'newer',
      editDate: at,
      oldKindKey: oldKind,
    );

MessageHistoryEntry _entry({List<MessageHistoryEvent> events = const []}) =>
    MessageHistoryEntry(
      accountUserId: 1,
      chatId: 11,
      messageId: 100,
      senderId: 42,
      date: 1700000000,
      text: 'current',
      kindKey: '',
      state: MessageHistoryState.active,
      deletedAt: 0,
      events: events,
    );

Future<void> _pump(WidgetTester tester, Widget child) async {
  SharedPreferences.setMockInitialValues(const {});
  final preferences = await SharedPreferences.getInstance();
  final theme = ThemeController(preferences);
  addTearDown(theme.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [ChangeNotifierProvider<ThemeController>.value(value: theme)],
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
        home: child,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  if (!_enabled) return;

  testWidgets('revisions render newest first', (tester) async {
    final entry = _entry(
      events: [_event(1700000100, 'original'), _event(1700000200, 'middle')],
    );
    await _pump(tester, MessageHistoryRevisionView(entry: entry));
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    final iCurrent = texts.indexOf('current');
    final iMiddle = texts.indexOf('middle');
    final iOriginal = texts.indexOf('original');
    expect(iCurrent, greaterThanOrEqualTo(0));
    expect(iMiddle, greaterThan(iCurrent));
    expect(iOriginal, greaterThan(iMiddle));
  });

  testWidgets('an entry without events shows the empty note', (tester) async {
    await _pump(tester, MessageHistoryRevisionView(entry: _entry()));
    expect(find.byType(SettingsNote), findsOneWidget);
  });
}
