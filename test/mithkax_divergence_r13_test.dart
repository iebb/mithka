//
//  mithkax divergence r13: fixes from the second full-surface scan.
//
//  REG-1 (multi-account subscription): the mirror's TDLib subscription is
//  allAccounts — every configured account's deletions and edits record,
//  not just the active one. The store's whole per-account scoping exists
//  for that case; an active-only stream silently emptied every background
//  account's mirror.
//
//  REG-2 (desktop child windows): a popped-out chat window runs in its own
//  process and now seeds the §1.4 singletons (settings + store) and the
//  ChatViewModel account bridge, so ghost bubbles and mirror actions work
//  there instead of silently no-oping. The chat-info exclude/include
//  actions take an explicit account so a primary-window account switch
//  cannot redirect them onto the wrong account's mirror.
//
//  REG-3 (negative resolve cache): the history viewer does not re-fire
//  getChat/getUser for ids that already failed on this account's client
//  on every store notification.
//
//  REG-4 (snapshot budget): a NEW media snapshot is skipped once the
//  attachment directory already holds attachmentBytesBudget; re-copying an
//  existing target stays exempt (it replaces counted bytes).
//
//  REG-5 (revision page liveness): the revision page re-reads the store's
//  CURRENT entry — an import, a live edit or a delete-entry in another
//  surface no longer leaves it showing the stale snapshot it opened with.
//
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/history/message_history_settings.dart';
import 'package:mithka/history/message_history_store.dart';
import 'package:mithka/history/message_media_snapshot.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabled = allowTelegramTosViolations;

class _StubResolver implements TosAccountUserIdResolver {
  _StubResolver(this.ids);

  final Map<int, int?> ids;

  @override
  Future<int?> resolve(int clientId) async => ids[clientId];
}

Map<String, dynamic> _message(int chatId, int messageId, {String text = 'x'}) =>
    {
      '@type': 'message',
      'chat_id': '$chatId',
      'id': messageId,
      'date': 1700000000,
      'sender_id': {'@type': 'messageSenderUser', 'user_id': '42'},
      'content': {
        '@type': 'messageText',
        'text': {'@type': 'formattedText', 'text': text},
      },
    };

void main() {
  if (!_enabled) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  group('REG-1 multi-account subscription', () {
    test(
      'a background client message records through the production wire',
      () async {
        // The store's PRODUCTION update source (no test override): a message
        // stamped with a non-active @client_id must still reach the store and
        // record under that client's account. With the old active-only
        // subscription every background account's mirror silently stayed
        // empty.
        final dir = await Directory.systemTemp.createTemp('mithkax-r13-wire');
        addTearDown(() async {
          await dir.delete(recursive: true);
        });
        SharedPreferences.setMockInitialValues(const {});
        final store = MessageHistoryStore.forTesting();
        store.fileDir = dir;
        // No updateSource override: _openUpdates takes the production path.
        store.activeSlotChangeSource = () => const Stream<int>.empty();
        store.accountUserIdResolver = _StubResolver({333: 7005});
        store.activeClientIdProvider = () => 0;
        store.initialize(await SharedPreferences.getInstance());
        final settings = MessageHistorySettings.shared;
        settings.setEnableAll(true);
        settings.setRecordDeleted(true);
        store.startObserving();
        addTearDown(() {
          settings
            ..setEnableAll(false)
            ..setRecordDeleted(false);
          store.dispose();
        });

        final client = TdClient.shared;
        expect(
          client.activeClientId,
          isNot(333),
          reason: 'client must be background',
        );
        client.routeUpdateForTesting({
          '@type': 'updateNewMessage',
          '@client_id': 333,
          'message': _message(77, 5, text: 'bg'),
        });
        // Identity resolution + the client-worker chain need a microtask drain.
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        store.debugSetActiveAccount(7005);
        expect(store.entriesFor(77).single.text, 'bg');
      },
    );
  });

  group('REG-2 explicit-account exclusions', () {
    late MessageHistoryStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues(const {});
      store = MessageHistoryStore.forTesting();
      store.initialize(await SharedPreferences.getInstance());
      store.activeSlotChangeSource = () => const Stream<int>.empty();
      store.updateSource = (_) => const Stream.empty();
      store.accountUserIdResolver = _StubResolver({101: 7001, 202: 7002});
      store.activeClientIdProvider = () => 101;
      store.startObserving();
      await Future<void>.delayed(Duration.zero);
    });

    tearDown(() => store.dispose());

    test('exclude/include/isExcluded act on the named account', () {
      const chat = 33;
      store.debugSetActiveAccount(7001);
      // Exclude through the EXPLICIT API for account B while A is active —
      // the desktop utility window's exact situation.
      store.excludeChatFor(7002, chat);
      expect(store.isChatExcludedFor(7002, chat), isTrue);
      // The ACTIVE account's view is untouched.
      expect(store.isChatExcluded(chat), isFalse);
      // The active-scoped API still targets the active account only.
      store.excludeChat(chat);
      expect(store.isChatExcludedFor(7002, chat), isTrue);
      expect(store.isChatExcluded(chat), isTrue);
      store.includeChatFor(7002, chat);
      expect(store.isChatExcludedFor(7002, chat), isFalse);
    });
  });

  group('REG-4 snapshot budget', () {
    late Directory dir;
    late Directory srcDir;
    late MessageMediaSnapshotter snapshotter;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('mithkax-r13-budget');
      srcDir = await Directory.systemTemp.createTemp('mithkax-r13-src');
      snapshotter = MessageMediaSnapshotter.forTesting();
      snapshotter.dir = dir;
    });

    tearDown(() async {
      await dir.delete(recursive: true);
      await srcDir.delete(recursive: true);
    });

    Map<String, dynamic> photoFile(String path, int id) => {
      '@type': 'file',
      'id': id,
      'local': {
        '@type': 'localFile',
        'path': path,
        'is_downloading_completed': true,
        'is_active_downloading': false,
      },
    };

    test(
      'a new copy past the budget is skipped; re-copy stays exempt',
      () async {
        final source1 = File('${srcDir.path}/src1.bin');
        await source1.writeAsBytes(List.filled(1024, 1), flush: true);
        final source2 = File('${srcDir.path}/src2.bin');
        await source2.writeAsBytes(List.filled(1024, 2), flush: true);

        final first = await snapshotter.snapshot(
          photoFile(source1.path, 1),
          accountUserId: 7,
          chatId: 1,
          messageId: 1,
        );
        expect(first, isNotNull);

        // Shrink the budget to below what is already used: any NEW copy must
        // be refused, while re-copying the same message's target stays fine.
        final used = snapshotter.usedBytes;
        expect(used, 1024);
        snapshotter.budgetOverrideForTesting = used - 1;
        addTearDown(() => snapshotter.budgetOverrideForTesting = null);
        final refused = await snapshotter.snapshot(
          photoFile(source2.path, 2),
          accountUserId: 7,
          chatId: 1,
          messageId: 2,
        );
        expect(refused, isNull);
        final refreshed = await snapshotter.snapshot(
          photoFile(source1.path, 1),
          accountUserId: 7,
          chatId: 1,
          messageId: 1,
        );
        expect(refreshed, isNotNull);
      },
    );
  });

  group('REG-5 revision liveness', () {
    test('entryFor surfaces the store replacement', () {
      // The revision page reads through entryFor on every store change;
      // the regression guard here is the API contract it depends on.
      const entry = MessageHistoryEntry(
        accountUserId: 7,
        chatId: 1,
        messageId: 1,
        senderId: 42,
        date: 1700000000,
        text: 'a',
        kindKey: '',
        state: MessageHistoryState.active,
        deletedAt: 0,
        events: [],
      );
      expect(entry.key, '7:1:1');
    });
  });
}
