//
//  History ownership regressions, consolidated: the chat surface's mirror
//  lookups resolve the owning slot, content generations never fake
//  revisions, the revision page resolves its snapshot directory on a cold
//  start, and the production update wire is active-only — background
//  accounts never record.
//

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/history/message_history_entry_view.dart';
import 'package:mithka/history/message_history_revision_view.dart';
import 'package:mithka/history/message_history_settings.dart';
import 'package:mithka/history/message_history_store.dart';
import 'package:mithka/history/message_media_snapshot.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabled = allowTelegramTosViolations;
const _accountA = 9101;
const _accountB = 9102;
const _clientA = 101;
const _clientB = 202;
const _chatId = 21;

class _StubResolver implements TosAccountUserIdResolver {
  _StubResolver(this.ids);

  final Map<int, int?> ids;

  @override
  Future<int?> resolve(int clientId) async => ids[clientId];
}

void main() {
  if (!_enabled) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  late MessageHistoryStore store;
  late StreamController<Map<String, dynamic>> updates;

  Future<void> pump() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  void emitAs(int clientId, String type, Map<String, dynamic> update) =>
      updates.add({'@type': type, '@client_id': clientId, ...update});

  ChatViewModel makeViewModel({int? forumTopicId}) => ChatViewModel(
    chatId: _chatId,
    title: 'test',
    markReadOnOpen: false,
    historyStoreOverride: store,
    forumTopicId: forumTopicId,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    updates = StreamController<Map<String, dynamic>>.broadcast();
    store = MessageHistoryStore.forTesting();
    store.updateSource = (_) => updates.stream;
    store.activeSlotChangeSource = () => const Stream<int>.empty();
    store.accountUserIdResolver = _StubResolver({
      _clientA: _accountA,
      _clientB: _accountB,
    });
    store.activeClientIdProvider = () => _clientA;
    store.initialize(await SharedPreferences.getInstance());
    final settings = MessageHistorySettings.shared;
    settings.setEnableAll(true);
    settings.setRecordDeleted(true);
    settings.setRecordEdits(true);
    settings.setRenderGhosts(true);
    store.startObserving();
  });

  tearDown(() async {
    ChatViewModel.accountSummaryProvider = null;
    final settings = MessageHistorySettings.shared;
    settings
      ..setEnableAll(false)
      ..setRecordDeleted(false)
      ..setRecordEdits(false)
      ..setRenderGhosts(false);
    store.dispose();
    await updates.close();
  });

  group('REG-1 chat-surface mirror lookups use the owning slot', () {
    test('a stale pane reads its own account, not the active one', () {
      // The pane was opened under slot 1 (account B); the user has since
      // switched the ACTIVE account to slot 0 (account A).
      TdClient.shared.debugSetActiveAccountForTesting(1, _clientB);
      addTearDown(() => TdClient.shared.debugSetActiveAccountForTesting(0, 1));
      ChatViewModel.accountSummaryProvider = (slot) => slot == 0
          ? AccountSummary(slot: 0, userId: _accountA, name: 'a', phone: '+1')
          : AccountSummary(slot: 1, userId: _accountB, name: 'b', phone: '+2');
      // Both accounts keep a copy of the SAME chat/message ids, with
      // different edit trails — the collision that makes an active-account
      // lookup read the wrong row.
      store.debugSeed([
        const MessageHistoryEntry(
          accountUserId: _accountA,
          chatId: _chatId,
          messageId: 100,
          senderId: 42,
          date: 1,
          text: 'from A',
          kindKey: '',
          state: MessageHistoryState.active,
          deletedAt: 0,
          events: [],
        ),
        const MessageHistoryEntry(
          accountUserId: _accountB,
          chatId: _chatId,
          messageId: 100,
          senderId: 42,
          date: 1,
          text: 'from B',
          kindKey: '',
          state: MessageHistoryState.active,
          deletedAt: 0,
          events: [
            MessageHistoryEvent(at: 5, oldText: 'B0', newText: 'from B'),
          ],
        ),
      ]);
      final vm = makeViewModel();
      addTearDown(vm.dispose);
      // The pane's own account (B) answers even though A is active.
      expect(vm.mirrorAccountUserId, _accountB);
      final entry = vm.mirrorEntryForMessage(
        ChatMessage(id: 100, isOutgoing: false, text: 'x', date: 1),
      );
      expect(
        entry?.accountUserId,
        _accountB,
        reason: 'the pane must resolve its owning slot, not the active account',
      );
      expect(
        entry?.events,
        isNotEmpty,
        reason: 'the view-edits gate would be dead with the wrong row',
      );
    });

    test('no account identity answers nothing', () {
      ChatViewModel.accountSummaryProvider = (_) => null;
      store.debugSeed([
        const MessageHistoryEntry(
          accountUserId: _accountA,
          chatId: _chatId,
          messageId: 100,
          senderId: 42,
          date: 1,
          text: 'x',
          kindKey: '',
          state: MessageHistoryState.active,
          deletedAt: 0,
          events: [],
        ),
      ]);
      final vm = makeViewModel();
      addTearDown(vm.dispose);
      expect(
        vm.mirrorEntryForMessage(
          ChatMessage(id: 100, isOutgoing: false, text: 'x', date: 1),
        ),
        isNull,
      );
    });
  });

  group(
    'REG-3 content updates without an edited date never fake a revision',
    () {
      test(
        'content-first records nothing and a later real pair still works',
        () async {
          ChatViewModel.accountSummaryProvider = (_) => null;
          final settings = MessageHistorySettings.shared;
          settings
            ..setSnapshotPrivate(false)
            ..setSnapshotGroups(false)
            ..setSnapshotChannels(false);

          const newText = 'revised';
          store.debugSeed([
            const MessageHistoryEntry(
              accountUserId: _accountA,
              chatId: _chatId,
              messageId: 300,
              senderId: 42,
              date: 1,
              text: 'original',
              kindKey: '',
              state: MessageHistoryState.active,
              deletedAt: 0,
              events: [],
            ),
          ]);
          // Reversed arrival: content first. A content generation (dice roll,
          // live location, poll) arrives exactly like this, so nothing records
          // and the text stays put.
          emitAs(_clientA, 'updateMessageContent', {
            'chat_id': '$_chatId',
            'message_id': 300,
            'new_content': {
              '@type': 'messageText',
              'text': {'@type': 'formattedText', 'text': newText},
            },
          });
          await pump();
          var entry = store.entryFor(_accountA, _chatId, 300);
          expect(
            entry?.events,
            isEmpty,
            reason:
                'a content generation without an edited date is not an edit',
          );
          expect(entry?.text, 'original');

          // A subsequent genuine edited+content pair still records cleanly —
          // the missed content left no stale pending state behind.
          emitAs(_clientA, 'updateMessageEdited', {
            'chat_id': '$_chatId',
            'message_id': 300,
            'edit_date': 77,
          });
          await pump();
          emitAs(_clientA, 'updateMessageContent', {
            'chat_id': '$_chatId',
            'message_id': 300,
            'new_content': {
              '@type': 'messageText',
              'text': {'@type': 'formattedText', 'text': newText},
            },
          });
          await pump();
          entry = store.entryFor(_accountA, _chatId, 300);
          expect(entry?.events, hasLength(1));
          expect(entry?.events.single.editDate, 77);
          expect(entry?.text, newText);
        },
      );
    },
  );

  group(
    'REG-7 the revision page resolves the snapshot dir on a cold start',
    () {
      testWidgets('a persisted snapshot renders once the directory lands', (
        tester,
      ) async {
        final root = Directory.systemTemp.createTempSync('push-r12-rev-');
        addTearDown(() => root.deleteSync(recursive: true));
        PathProviderPlatform.instance = _FakePathProvider(root.path);
        final snapshotDir = Directory(
          '${root.path}/${MessageMediaSnapshotter.dirName}',
        )..createSync(recursive: true);
        final file = File('${snapshotDir.path}/9101_21_700_photo.bin')
          ..writeAsBytesSync(List.filled(8, 1));
        final entry = MessageHistoryEntry(
          accountUserId: _accountA,
          chatId: _chatId,
          messageId: 700,
          senderId: 42,
          date: 1,
          text: '',
          kindKey: 'historyKindDocument',
          state: MessageHistoryState.active,
          deletedAt: 0,
          events: [
            MessageHistoryEvent(
              at: 2,
              oldText: 'before',
              newText: '',
              oldKindKey: 'historyKindDocument',
              oldMediaPath: file.path,
            ),
          ],
          mediaPath: file.path,
        );
        final preferences = await SharedPreferences.getInstance();
        final theme = ThemeController(preferences);
        addTearDown(theme.dispose);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeController>.value(value: theme),
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
              home: MessageHistoryRevisionView(entry: entry),
            ),
          ),
        );
        // First frame: the singleton has no directory yet, so a persisted
        // snapshot path is still rendered as a bare kind label.
        expect(find.byType(MediaSnapshotView), findsNothing);
        await tester.pumpAndSettle();
        expect(
          find.byType(MediaSnapshotView),
          findsWidgets,
          reason: 'the page resolves the directory and rebuilds for its media',
        );
      });
    },
  );
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
