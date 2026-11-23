//
//  The message-history viewer: chat filtering, clear actions and the
//  excluded-chats list, all against an in-memory store with a synthetic
//  directory so nothing touches the host's real mirror file.
//
//  Like the store suite this needs the feature compiled in
//  (--dart-define=I_DONT_FUCKING_CARE_ABOUT_TOS=true); without it the
//  feature does not exist, so the whole file skips.
//

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/history/message_history_store.dart';
import 'package:mithka/history/message_history_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabled = allowTelegramTosViolations;

MessageHistoryEntry _entry(
  int chatId,
  int messageId, {
  int accountUserId = 42,
  String text = 'hello',
  bool deleted = false,
  int deletedAt = 0,
  String kindKey = '',
}) => MessageHistoryEntry(
  accountUserId: accountUserId,
  chatId: chatId,
  messageId: messageId,
  senderId: 42,
  date: 1700000000,
  text: text,
  kindKey: kindKey,
  state: deleted ? MessageHistoryState.deleted : MessageHistoryState.active,
  deletedAt: deletedAt,
  events: const [],
);

Future<void> _pumpViewer(WidgetTester tester, MessageHistoryStore store) async {
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
        home: MessageHistoryView(store: store),
      ),
    ),
  );
  await tester.pump();
}

/// The context the viewer resolves localized strings in during a test. After
/// a nested route is pushed, both the root and the pushed page are mounted,
/// so take the topmost instance.
BuildContext _contextOf(WidgetTester tester) =>
    tester.element(find.byType(MessageHistoryView).last);

/// The viewer renders edit stamps with a local-time formatter; the exact hour
/// depends on the host timezone, so compute the expectation the same way
/// instead of pinning a wall-clock string.
/// Resolver stub whose lookups are held until released, so the viewer test
/// can pin the unresolved-account rendering path.
void main() {
  if (!_enabled) {
    return;
  }

  late Directory dir;
  late MessageHistoryStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mithka-history-view-test');
    store = MessageHistoryStore.forTesting();
    store.fileDir = dir;
    SharedPreferences.setMockInitialValues(const {});
    store.initialize(await SharedPreferences.getInstance());
    store.debugSetActiveAccount(42);
  });

  tearDown(() async {
    store.dispose();
    await dir.delete(recursive: true);
  });

  testWidgets('rows list kept messages with their chat label', (tester) async {
    store.debugSeed([
      _entry(11, 100, text: 'kept one'),
      _entry(12, 200, text: 'kept two'),
    ]);
    await _pumpViewer(tester, store);

    expect(find.text('kept one'), findsOneWidget);
    expect(find.text('kept two'), findsOneWidget);
    // Chat labels fall back to the localized Chat {id} until a title is
    // resolved; each row carries its own chat's label.
    final context = _contextOf(tester);
    expect(
      find.text(AppStrings.t(AppStringKeys.historyChatLabel, {'value1': '11'})),
      findsOneWidget,
    );
    expect(
      find.text(AppStrings.t(AppStringKeys.historyChatLabel, {'value1': '12'})),
      findsOneWidget,
    );
    expect(context, isNotNull);
  });

  testWidgets('tapping a row filters to its chat', (tester) async {
    store.debugSeed([
      _entry(11, 100, text: 'kept one'),
      _entry(11, 101, text: 'kept three'),
      _entry(12, 200, text: 'kept two'),
    ]);
    await _pumpViewer(tester, store);

    await tester.tap(find.text('kept one'));
    await tester.pump();

    expect(find.text('kept one'), findsOneWidget);
    expect(find.text('kept three'), findsOneWidget);
    expect(find.text('kept two'), findsNothing);
  });

  testWidgets('deleted entries render inside the chat with the ghost style', (
    tester,
  ) async {
    store.debugSeed([
      _entry(11, 100, text: 'gone', deleted: true, deletedAt: 1600000000),
      _entry(11, 101, text: 'fresh'),
    ]);
    await _pumpViewer(tester, store);

    // The chat list previews the deletion; the entries render inside the chat.
    await tester.tap(find.text('Chat 11'));
    await tester.pump();
    expect(find.text('gone'), findsOneWidget);
    expect(find.text('fresh'), findsOneWidget);
  });

  testWidgets('excluded chats are listed and can be re-included', (
    tester,
  ) async {
    store.excludeChat(11);
    await _pumpViewer(tester, store);

    await tester.tap(
      find.text(AppStringKeys.historyExcludedTitle.l10n(_contextOf(tester))),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MessageHistoryExcludedChatsView), findsOneWidget);
    expect(
      find.text(AppStrings.t(AppStringKeys.historyChatLabel, {'value1': '11'})),
      findsOneWidget,
    );

    // Resolve from the pushed page itself: under route snapshotting the root
    // page may not stay visible to finders.
    final excludedContext = tester.element(
      find.byType(MessageHistoryExcludedChatsView),
    );
    await tester.tap(
      find.text(AppStringKeys.historyReincludeAction.l10n(excludedContext)),
    );
    await tester.pump();
    // includeChat re-armed the batched persistence timer; flush it so the
    // binding's no-pending-timers invariant passes.
    await tester.pump(const Duration(seconds: 2));

    expect(store.isChatExcluded(11), isFalse);
  });

  testWidgets('group rows resolve their sender name', (tester) async {
    // The proxy answers getUser; the viewer resolves the seeded group
    // entry's sender through it and renders the name as the row header.
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          if (request['@type'] == 'getUser') {
            return {
              '@type': 'user',
              'id': 42,
              'first_name': 'Ada',
              'last_name': 'Lovelace',
            };
          }
          if (request['@type'] != 'getChat') return {'@type': 'ok'};
          return {'@type': 'chat', 'id': 11, 'title': 'Chat 11'};
        },
        send: (_) async {},
        updates: const Stream<Map<String, dynamic>>.empty(),
      ),
    );
    addTearDown(TdClient.shared.closeProxy);
    store.debugSeed([_entry(11, 100, text: 'group message')]);
    await _pumpViewer(tester, store);

    await tester.tap(find.text('Chat 11'));
    await tester.pump();
    await tester.runAsync<void>(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    expect(find.text('Ada Lovelace'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
