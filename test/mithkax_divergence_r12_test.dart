//
//  mithkax divergence r12: the fixes from the deep re-scan.
//
//  REG-1 (cross-account leak): the chat surface's mirror lookups (view-edits
//  gate, message info read-time row) resolve the OWNING slot's account, not
//  whichever account is active. A stale pane after an account switch must
//  neither show another account's mirror row (same chat/message ids) nor
//  lose its own.
//
//  REG-2 (forum topic ghost leak): a topic transcript folds only its own
//  topic's ghosts; other topics' deleted messages stay out. Entries with no
//  recorded topic (0, pre-capture rows or General's unattributed arrivals)
//  render only in the General view; the chat-wide view keeps everything.
//
//  REG-3 (content generation guard): updateMessageContent without an edited
//  date is a TDLib content generation (dice, poll, live location), never a
//  revision — and it leaves no stale pairing state behind.
//
//  REG-4 (topic capture): a message carrying an explicit messageTopicForum
//  topic_id records that topic id; a message with none records 0.
//
//  REG-5 (reversed edit pair): when TDLib catch-up delivers
//  updateMessageContent BEFORE its updateMessageEdited, the content is held
//  briefly and the late edited-date completes the revision instead of the
//  pair being dropped wholesale.
//
//  REG-7 (revision page cold start): the page resolves the snapshot
//  directory itself and rebuilds for its media; entering it first in a
//  session must not render persisted snapshots as bare kind labels.
//
//  A scanned B3 (snapshot gate bypass) did not reproduce: _snapshotsEnabledFor
//  already reaches settings.recordDeleted through recordsChatType, so it was
//  dropped instead of "fixed".
//
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/forum_topic_transcript.dart';
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
const _groupChatId = -1001234;

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

  group('REG-2 topic transcripts fold only their own ghosts', () {
    test('a topic pane hides other topics ghosts, keeps its own', () {
      ChatViewModel.accountSummaryProvider = (_) =>
          AccountSummary(slot: 0, userId: _accountA, name: 'me', phone: '+1');
      store.debugSeed([
        _deleted(messageId: 200, topicId: 7),
        _deleted(messageId: 201, topicId: 8),
        _deleted(messageId: 202, topicId: 0),
      ]);
      final vm = makeViewModel(forumTopicId: 7);
      addTearDown(vm.dispose);
      vm.debugRebuildTranscriptForTesting();
      final ghostIds = vm.messages
          .where((m) => m.mirrorEntry != null)
          .map((m) => m.id)
          .toSet();
      expect(
        ghostIds,
        {200},
        reason:
            'topic 7 shows only its own ghost; 0-topic rows belong to '
            'the General view alone',
      );
    });

    test('the General topic view inherits unattributed ghosts', () {
      ChatViewModel.accountSummaryProvider = (_) =>
          AccountSummary(slot: 0, userId: _accountA, name: 'me', phone: '+1');
      store.debugSeed([
        _deleted(messageId: 200, topicId: 7),
        _deleted(messageId: 201, topicId: 8),
        _deleted(messageId: 202, topicId: 0),
      ]);
      final vm = makeViewModel(forumTopicId: generalForumTopicId);
      addTearDown(vm.dispose);
      vm.debugRebuildTranscriptForTesting();
      final ghostIds = vm.messages
          .where((m) => m.mirrorEntry != null)
          .map((m) => m.id)
          .toSet();
      expect(
        ghostIds,
        {202},
        reason:
            'General owns the unattributed rows, exactly like the '
            'transcript scoping fallback',
      );
    });

    test('the chat-wide view keeps every ghost', () {
      ChatViewModel.accountSummaryProvider = (_) =>
          AccountSummary(slot: 0, userId: _accountA, name: 'me', phone: '+1');
      store.debugSeed([
        _deleted(messageId: 200, topicId: 7),
        _deleted(messageId: 201, topicId: 8),
        _deleted(messageId: 202, topicId: 0),
      ]);
      final vm = makeViewModel();
      addTearDown(vm.dispose);
      vm.debugRebuildTranscriptForTesting();
      final ghostIds = vm.messages
          .where((m) => m.mirrorEntry != null)
          .map((m) => m.id)
          .toSet();
      expect(ghostIds, {200, 201, 202});
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

  group('REG-4 topic capture', () {
    test('a group message with an explicit topic records it', () async {
      emitAs(_clientA, 'updateNewMessage', {
        'message': {
          '@type': 'message',
          'id': 400,
          'chat_id': '$_groupChatId',
          'is_outgoing': false,
          'date': 10,
          'topic_id': {'@type': 'messageTopicForum', 'forum_topic_id': 9},
          'content': {
            '@type': 'messageText',
            'text': {'@type': 'formattedText', 'text': 'topic msg'},
          },
        },
      });
      await pump();
      final entry = store.entryFor(_accountA, _groupChatId, 400);
      expect(entry, isNotNull);
      expect(entry!.topicId, 9);
    });

    test('a private chat message never records a topic', () async {
      emitAs(_clientA, 'updateNewMessage', {
        'message': {
          '@type': 'message',
          'id': 401,
          'chat_id': '$_chatId',
          'is_outgoing': false,
          'date': 10,
          'content': {
            '@type': 'messageText',
            'text': {'@type': 'formattedText', 'text': 'private msg'},
          },
        },
      });
      await pump();
      final entry = store.entryFor(_accountA, _chatId, 401);
      expect(entry, isNotNull);
      expect(entry!.topicId, 0);
    });
  });

  group('REG-5 a reversed edit pair still records its revision', () {
    test(
      'content before its edited date lands when the date arrives',
      () async {
        store.debugSeed([
          const MessageHistoryEntry(
            accountUserId: _accountA,
            chatId: _chatId,
            messageId: 500,
            senderId: 42,
            date: 1,
            text: 'original',
            kindKey: '',
            state: MessageHistoryState.active,
            deletedAt: 0,
            events: [],
          ),
        ]);
        // TDLib catch-up can deliver the pair backwards: the content first.
        emitAs(_clientA, 'updateMessageContent', {
          'chat_id': '$_chatId',
          'message_id': 500,
          'new_content': {
            '@type': 'messageText',
            'text': {'@type': 'formattedText', 'text': 'revised'},
          },
        });
        await pump();
        var entry = store.entryFor(_accountA, _chatId, 500);
        expect(
          entry?.text,
          'original',
          reason: 'content alone is held, never applied as a revision',
        );
        expect(entry?.events, isEmpty);

        emitAs(_clientA, 'updateMessageEdited', {
          'chat_id': '$_chatId',
          'message_id': 500,
          'edit_date': 88,
        });
        await pump();
        entry = store.entryFor(_accountA, _chatId, 500);
        expect(entry?.text, 'revised');
        expect(
          entry?.events,
          hasLength(1),
          reason: 'the late date completes the pair instead of dropping it',
        );
        expect(entry?.events.single.editDate, 88);
        expect(entry?.events.single.oldText, 'original');
        expect(entry?.events.single.newText, 'revised');
      },
    );
  });

  group(
    'REG-7 the revision page resolves the snapshot dir on a cold start',
    () {
      testWidgets('a persisted snapshot renders once the directory lands', (
        tester,
      ) async {
        final root = Directory.systemTemp.createTempSync('mithkax-r12-rev-');
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

MessageHistoryEntry _deleted({required int messageId, required int topicId}) =>
    MessageHistoryEntry(
      accountUserId: _accountA,
      chatId: _chatId,
      messageId: messageId,
      senderId: 42,
      date: 1,
      text: 'ghost $messageId',
      kindKey: '',
      state: MessageHistoryState.deleted,
      deletedAt: 2,
      events: const [],
      topicId: topicId,
    );

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
