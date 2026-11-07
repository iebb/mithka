//
//  The message-history viewer: chat filtering, clear actions and the
//  excluded-chats list, all against an in-memory store with a synthetic
//  directory so nothing touches the host's real mirror file.
//
//  Like the store suite this needs the feature compiled in
//  (--dart-define=I_DONT_FUCKING_CARE_ABOUT_TOS=true); without it the
//  feature does not exist, so the whole file skips.
//

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/history/message_history_store.dart';
import 'package:mithka/history/message_history_view.dart';
import 'package:mithka/history/message_media_snapshot.dart';
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
String _editStamp(int unixSeconds) {
  final t = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000).toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// Resolver stub whose lookups are held until released, so the viewer test
/// can pin the unresolved-account rendering path.
class _GatedResolver implements TosAccountUserIdResolver {
  _GatedResolver(this.ids);

  final Map<int, Completer<int?>> ids;

  @override
  Future<int?> resolve(int clientId) => ids[clientId]!.future;
}

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

  testWidgets('empty mirror shows the empty note', (tester) async {
    await _pumpViewer(tester, store);
    expect(find.byType(MessageHistoryView), findsOneWidget);
    expect(
      find.text(AppStringKeys.historyEmpty.l10n(_contextOf(tester))),
      findsOneWidget,
    );
  });

  testWidgets('a held chat title cannot cross an account switch', (
    tester,
  ) async {
    final oldTitle = Completer<Map<String, dynamic>>();
    var account = 42;
    addTearDown(() => account = 0);
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
          if (account == 0) return {'@type': 'ok'};
          if (account == 42) return oldTitle.future;
          return {'@type': 'chat', 'id': 11, 'title': 'Second account title'};
        },
        send: (_) async {},
        updates: const Stream<Map<String, dynamic>>.empty(),
      ),
    );
    addTearDown(TdClient.shared.closeProxy);
    store.debugSeed([
      _entry(11, 100, text: 'first account message'),
      _entry(11, 100, accountUserId: 43, text: 'second account message'),
    ]);
    await _pumpViewer(tester, store);
    account = 43;
    store.debugSetActiveAccount(43);
    await tester.pump();
    oldTitle.complete({
      '@type': 'chat',
      'id': 11,
      'title': 'First account title',
    });
    await tester.pumpAndSettle();
    expect(find.text('first account message'), findsNothing);
    expect(find.text('First account title'), findsNothing);
    expect(find.text('second account message'), findsOneWidget);
    expect(find.text('Second account title'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
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

  testWidgets('edited rows show the edit event trail', (tester) async {
    final entry = _entry(11, 100, text: 'v3').copyWith(
      events: const [
        MessageHistoryEvent(at: 1700000100, oldText: 'v1', newText: 'v2'),
        MessageHistoryEvent(at: 1700000200, oldText: 'v2', newText: 'v3'),
      ],
    );
    store.debugSeed([entry]);
    await _pumpViewer(tester, store);
    await tester.tap(find.text('Chat 11'));
    await tester.pump();

    expect(find.text('v3'), findsOneWidget);
    expect(
      find.text(
        AppStrings.t(AppStringKeys.historyEditEvent, {
          'value1': _editStamp(1700000100),
          'value2': 'v2',
        }),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        AppStrings.t(AppStringKeys.historyEditEvent, {
          'value1': _editStamp(1700000200),
          'value2': 'v3',
        }),
      ),
      findsOneWidget,
    );
  });

  testWidgets('media-only rows fall back to their kind label', (tester) async {
    store.debugSeed([_entry(11, 100, text: '', kindKey: 'historyKindPhoto')]);
    await _pumpViewer(tester, store);

    // The kind name shows as the body fallback and again in the status line.
    expect(
      find.text(AppStrings.t(AppStringKeys.historyKindPhoto)),
      findsAtLeastNWidgets(1),
    );
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

  testWidgets('a photo snapshot renders inline and opens externally', (
    tester,
  ) async {
    final media = MessageMediaSnapshotter.forTesting();
    media.dir = dir;
    store.mediaSnapshotter = media;
    final photo = File('${dir.path}/7001_11_500_m.jpg')
      ..writeAsBytesSync(List.filled(16, 1));
    final entry = _entry(
      11,
      500,
      kindKey: 'historyKindPhoto',
    ).copyWith(mediaPath: photo.path);
    store.debugSeed([entry]);
    await _pumpViewer(tester, store);

    await tester.tap(find.text('Chat 11'));
    await tester.pump();
    // The snapshot image renders inline once the existence probe lands.
    await tester.runAsync<void>(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    expect(find.byKey(ValueKey('history-media-${photo.path}')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a missing snapshot falls back to the kind label', (
    tester,
  ) async {
    final media = MessageMediaSnapshotter.forTesting();
    media.dir = dir;
    store.mediaSnapshotter = media;
    final entry = _entry(11, 501, kindKey: 'historyKindVideo').copyWith(
      mediaPath: '${dir.path}/7001_11_501_m.mp4', // never written
    );
    store.debugSeed([entry]);
    await _pumpViewer(tester, store);

    await tester.tap(find.text('Chat 11'));
    await tester.pump();
    await tester.runAsync<void>(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    // The existence probe found nothing: the row keeps its kind label and
    // renders no broken preview.
    expect(
      find.byKey(const ValueKey('history-media-placeholder')),
      findsNothing,
    );
    expect(
      find.text(AppStringKeys.historyKindVideo.l10n(_contextOf(tester))),
      findsAtLeastNWidgets(1),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('group rows resolve their sender name', (tester) async {
    // The proxy is one per process (configured by the account-switch test
    // above); its transport keeps answering getUser, so the viewer resolves
    // the seeded group entry's sender through it.
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

  testWidgets(
    'a failed re-resolution of the active account clears the rendered rows',
    (tester) async {
      final gates = {
        101: Completer<int?>()..complete(7001),
        202: Completer<int?>(),
      };
      final slotChanges = StreamController<int>.broadcast();
      addTearDown(slotChanges.close);
      store.accountUserIdResolver = _GatedResolver(gates);
      store.activeClientIdProvider = () => 101;
      store.updateSource = (_) => const Stream.empty();
      store.activeSlotChangeSource = () => slotChanges.stream;
      store.startObserving();
      await tester.pump();

      // Account A's rows are on screen, the way the viewer legitimately
      // looks while its account is resolved.
      store.debugSeed([_entry(11, 100, accountUserId: 7001, text: 'kept one')]);
      await _pumpViewer(tester, store);
      expect(find.text('kept one'), findsOneWidget);

      // The active client switches to B while B's identity is unresolved:
      // the store drops to empty and must notify the viewer NOW, so the
      // rows of the previous account leave the screen at once.
      store.activeClientIdProvider = () => 202;
      slotChanges.add(202);
      await tester.pump();

      // B's resolution FAILS: the empty state must be the terminal one.
      // (Store.entries already reads [] while unresolved; the regression
      // was that no notification ever reached the real listeners.)
      gates[202]!.completeError(StateError('getMe lost'));
      await tester.pump();
      await tester.pump();

      expect(store.entries, isEmpty);
      expect(find.text('kept one'), findsNothing);
      expect(
        find.text(AppStringKeys.historyEmpty.l10n(_contextOf(tester))),
        findsOneWidget,
      );
    },
  );
}
