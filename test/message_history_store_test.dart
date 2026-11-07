//
//  Mirror for the messages this account received: deleted and edited ones
//  stay readable. Every observation runs against a store whose TDLib wiring
//  is replaced by a broadcast controller, so updates are injected directly.
//
//  Records are owned by the account whose client produced the update:
//  injected updates carry '@client_id' (as every real TDLib update does) and
//  a stub resolver maps client ids to account user ids.
//
//  The suite needs the feature compiled in
//  (--dart-define=I_DONT_FUCKING_CARE_ABOUT_TOS=true); without it the store
//  is a no-op by design, so the whole file skips.
//

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/history/message_history_store.dart';
import 'package:mithka/history/message_media_snapshot.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabled = allowTelegramTosViolations;

/// Client id used by the pre-account tests' updates; resolved to 7001.
const _clientA = 101;
const _accountA = 7001;
const _clientB = 202;
const _accountB = 7002;

/// Stub per-client identity mapping; a missing client resolves to null so
/// its updates are dropped instead of misattributed.
class _StubResolver implements TosAccountUserIdResolver {
  _StubResolver(this.ids);

  final Map<int, int?> ids;

  @override
  Future<int?> resolve(int clientId) async => ids[clientId];
}

/// Stub resolver whose per-client lookups complete only when the test
/// releases the held completer, so interleavings around identity resolution
/// become deterministic.
class _GatedResolver implements TosAccountUserIdResolver {
  _GatedResolver(this.ids);

  final Map<int, Completer<int?>> ids;

  @override
  Future<int?> resolve(int clientId) => ids[clientId]!.future;
}

/// Stub resolver that fails every lookup for [failing] clients; used to pin
/// that a failed identity resolution never writes anything and that later
/// events of the same client retry instead of caching the failure forever.
class _FailingResolver implements TosAccountUserIdResolver {
  _FailingResolver(this.ids, {this.failing = const {}});

  final Map<int, int?> ids;
  final Set<int> failing;

  @override
  Future<int?> resolve(int clientId) async {
    if (failing.contains(clientId)) throw StateError('getMe lost');
    return ids[clientId];
  }
}

/// Stub resolver whose FIRST lookup per client is held until the test
/// releases it; later lookups for the same client complete immediately —
/// the shape of concurrent getMe calls where only the first is stuck.
class _HoldFirstResolver implements TosAccountUserIdResolver {
  _HoldFirstResolver(this.ids);

  final Map<int, int?> ids;
  final Map<int, Completer<int?>> _gates = {};

  void release(int clientId, int? userId) => _gates[clientId]!.complete(userId);

  @override
  Future<int?> resolve(int clientId) {
    if (_gates.containsKey(clientId)) return Future.value(ids[clientId]);
    final gate = Completer<int?>();
    _gates[clientId] = gate;
    return gate.future;
  }
}

Map<String, dynamic> _message(
  int chatId,
  int messageId, {
  String text = 'hello',
  int date = 1700000000,
  int senderId = 42,
}) => {
  '@type': 'message',
  'chat_id': '$chatId',
  'id': messageId,
  'date': date,
  'sender_id': {'@type': 'messageSenderUser', 'user_id': '$senderId'},
  'content': {
    '@type': 'messageText',
    'text': {'@type': 'formattedText', 'text': text},
  },
};

/// A captionless photo content whose single size is fully on disk.
Map<String, dynamic> _photoContent(String path, {required int id}) => {
  '@type': 'messagePhoto',
  'photo': {
    '@type': 'photo',
    'sizes': [
      {
        '@type': 'photoSize',
        'width': 100,
        'height': 50,
        'photo': {
          '@type': 'file',
          'id': id,
          'local': {
            '@type': 'localFile',
            'path': path,
            'is_downloading_completed': true,
            'is_active_downloading': false,
          },
        },
      },
    ],
  },
};

void main() {
  if (!_enabled) {
    return;
  }

  late Directory dir;
  late StreamController<Map<String, dynamic>> updates;
  late StreamController<int> activeSlotChanges;
  late MessageHistoryStore store;
  late int notifications;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mithka-history-test');
    updates = StreamController<Map<String, dynamic>>.broadcast();
    activeSlotChanges = StreamController<int>.broadcast();
    store = MessageHistoryStore.forTesting();
    store.fileDir = dir;
    store.updateSource = (_) => updates.stream;
    store.activeSlotChangeSource = () => activeSlotChanges.stream;
    store.accountUserIdResolver = _StubResolver({
      _clientA: _accountA,
      _clientB: _accountB,
    });
    store.activeClientIdProvider = () => _clientA;
    SharedPreferences.setMockInitialValues(const {});
    store.initialize(await SharedPreferences.getInstance());
    notifications = 0;
    store.addListener(() => notifications++);
  });

  tearDown(() async {
    store.dispose();
    await updates.close();
    await activeSlotChanges.close();
    await dir.delete(recursive: true);
  });

  Future<void> pump() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> start() async {
    store.startObserving();
    await pump();
  }

  void emit(String type, Map<String, dynamic> update) =>
      updates.add({'@type': type, ...update});

  /// Emits an update stamped with the TDLib client that observed it, the
  /// way every real update arrives.
  void emitAs(int clientId, String type, Map<String, dynamic> update) =>
      updates.add({'@type': type, '@client_id': clientId, ...update});

  Map<String, dynamic> persistedJson() {
    final file = File('${dir.path}/message-history.json');
    expect(file.existsSync(), isTrue, reason: 'mirror file was never written');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  test(
    'a refetched message refreshes content without losing its history',
    () async {
      await start();
      store.recordIncomingMessage(_message(11, 100, text: 'before'));
      emitAs(_clientA, 'updateMessageEdited', {
        'chat_id': '11',
        'message_id': 100,
        'edit_date': 123,
      });
      emitAs(_clientA, 'updateMessageContent', {
        'chat_id': '11',
        'message_id': 100,
        'new_content': {
          '@type': 'messageText',
          'text': {'@type': 'formattedText', 'text': 'edited'},
        },
      });
      await pump();
      store.recordIncomingMessage({
        ..._message(11, 100),
        'content': {
          '@type': 'messagePhoto',
          'caption': {'@type': 'formattedText', 'text': 'refetched caption'},
        },
      });
      final entry = store.entry(11, 100)!;
      expect(entry.text, 'refetched caption');
      expect(entry.kindKey, 'historyKindPhoto');
      expect(entry.events.single.oldText, 'before');
      expect(entry.events.single.newText, 'edited');
    },
  );

  test(
    'clearAll invalidates queued updates even while the mirror is empty',
    () async {
      final gate = Completer<int?>();
      store.accountUserIdResolver = _GatedResolver({_clientA: gate});
      await start();
      emitAs(_clientA, 'updateNewMessage', {'message': _message(11, 100)});
      await pump();
      expect(store.clearAll(), 0);
      gate.complete(_accountA);
      await pump();
      expect(store.entryCount, 0);
    },
  );

  test(
    'clearChat stamps an empty chat without cancelling another chat',
    () async {
      final gate = Completer<int?>();
      store.accountUserIdResolver = _GatedResolver({_clientA: gate});
      await start();
      store.debugSetActiveAccount(_accountA);
      emitAs(_clientA, 'updateNewMessage', {'message': _message(11, 100)});
      emitAs(_clientA, 'updateNewMessage', {'message': _message(22, 200)});
      await pump();
      expect(store.clearChat(11), 0);
      gate.complete(_accountA);
      await pump();
      expect(store.entry(11, 100), isNull);
      expect(store.entry(22, 200), isNotNull);
    },
  );

  test(
    'exclude then include does not revive updates queued before exclusion',
    () async {
      final gate = Completer<int?>();
      store.accountUserIdResolver = _GatedResolver({_clientA: gate});
      await start();
      store.debugSetActiveAccount(_accountA);
      emitAs(_clientA, 'updateNewMessage', {'message': _message(11, 100)});
      await pump();
      store.excludeChat(11);
      store.includeChat(11);
      gate.complete(_accountA);
      await pump();
      expect(store.entryCount, 0);
      emitAs(_clientA, 'updateNewMessage', {'message': _message(11, 101)});
      await pump();
      expect(store.entry(11, 101), isNotNull);
    },
  );

  test('incoming messages mirror with sender, kind and text', () async {
    await start();
    emitAs(_clientA, 'updateNewMessage', {'message': _message(11, 100)});
    await pump();
    await store.persistNowForTesting();

    final entries = store.entries;
    expect(entries, hasLength(1));
    expect(entries.single.chatId, 11);
    expect(entries.single.messageId, 100);
    expect(entries.single.senderId, 42);
    expect(entries.single.date, 1700000000);
    expect(entries.single.text, 'hello');
    expect(entries.single.kindKey, isEmpty);
    expect(entries.single.state, MessageHistoryState.active);
    expect(persistedJson()['entries'], hasLength(1));
  });

  test('the bounded persisted batch keeps the most recent messages', () async {
    await start();
    for (var id = 1; id <= MessageHistoryStore.persistBatch + 1; id++) {
      store.recordIncomingMessage(_message(11, id));
    }
    await store.persistNowForTesting();
    final rows = persistedJson()['entries'] as List;
    expect(rows, hasLength(MessageHistoryStore.persistBatch));
    expect((rows.first as Map)['id'], 2);
    expect((rows.last as Map)['id'], MessageHistoryStore.persistBatch + 1);
  });

  for (final scope in ['chat', 'all', 'account']) {
    test(
      'a $scope clear during persistence cannot resurrect stale disk rows',
      () async {
        store.debugSetActiveAccount(_accountA);
        store.recordIncomingMessage(_message(11, 100));
        final reachedCommit = Completer<void>();
        final releaseCommit = Completer<void>();
        store.beforePersistRenameForTesting = () async {
          reachedCommit.complete();
          await releaseCommit.future;
        };
        final writing = store.persistNowForTesting();
        await reachedCommit.future;
        switch (scope) {
          case 'chat':
            store.clearChat(11);
          case 'all':
            store.clearAll();
          case 'account':
            store.removeAccount(_accountA);
        }
        releaseCommit.complete();
        await writing;
        store.beforePersistRenameForTesting = null;
        await store.ensureLoaded();
        expect(store.entryCount, 0);
      },
    );
  }

  test(
    'clearing an empty mirror before its first load invalidates old disk rows',
    () async {
      store.debugSetActiveAccount(_accountA);
      store.recordIncomingMessage(_message(11, 100));
      await store.persistNowForTesting();
      store.dispose();
      store = MessageHistoryStore.forTesting()..fileDir = dir;
      store.initialize(await SharedPreferences.getInstance());
      expect(store.clearAll(), 0);
      await store.ensureLoaded();
      expect(store.entryCount, 0);
    },
  );

  test('updateDeleteMessages keeps the copy and marks it deleted', () async {
    await start();
    emitAs(_clientA, 'updateNewMessage', {
      'message': _message(11, 100, text: 'secret'),
    });
    await pump();
    emitAs(_clientA, 'updateDeleteMessages', {
      'chat_id': '11',
      'message_ids': ['100'],
      'is_permanent': true,
      'from_cache': false,
    });
    await pump();

    final entry = store.entry(11, 100);
    expect(entry, isNotNull);
    expect(entry!.state, MessageHistoryState.deleted);
    expect(entry.deletedAt, greaterThan(0));
    expect(entry.text, 'secret');

    await store.persistNowForTesting();
    final state = (persistedJson()['entries'] as List).single;
    expect(state['state'], 'deleted');
    expect(state['text'], 'secret');
  });

  test(
    'deletions for unknown chats and unknown messages are ignored',
    () async {
      await start();
      emitAs(_clientA, 'updateDeleteMessages', {
        'chat_id': '99',
        'message_ids': ['100'],
        'is_permanent': true,
        'from_cache': false,
      });
      await pump();
      // The active-client resolution during start() legitimately notifies.
      notifications = 0;
      expect(store.entries, isEmpty);
      expect(notifications, 0);
    },
  );

  test(
    'an edited pair produces one history event and keeps the old text',
    () async {
      await start();
      emitAs(_clientA, 'updateNewMessage', {
        'message': _message(11, 100, text: 'v1'),
      });
      await pump();
      emitAs(_clientA, 'updateMessageEdited', {
        'chat_id': '11',
        'message_id': 100,
        'edit_date': 1700000123,
        'reply_markup': null,
      });
      emitAs(_clientA, 'updateMessageContent', {
        'chat_id': '11',
        'message_id': 100,
        'new_content': {
          '@type': 'messageText',
          'text': {'@type': 'formattedText', 'text': 'v2'},
        },
      });
      await pump();

      final entry = store.entry(11, 100)!;
      expect(entry.isEdited, isTrue);
      expect(entry.text, 'v2');
      expect(entry.events, hasLength(1));
      expect(entry.events.single.oldText, 'v1');
      expect(entry.events.single.newText, 'v2');
      expect(entry.events.single.editDate, 1700000123);
      expect(notifications, greaterThan(0));
    },
  );

  test('content changes without a preceding edit produce nothing', () async {
    await start();
    emitAs(_clientA, 'updateNewMessage', {
      'message': _message(11, 100, text: 'v1'),
    });
    await pump();
    emitAs(_clientA, 'updateMessageContent', {
      'chat_id': '11',
      'message_id': 100,
      'new_content': {
        '@type': 'messageText',
        'text': {'@type': 'formattedText', 'text': 'v2'},
      },
    });
    await pump();

    final entry = store.entry(11, 100)!;
    expect(entry.isEdited, isFalse);
    expect(entry.text, 'v1');
  });

  test(
    'a deleted message that comes back is active again, history intact',
    () async {
      await start();
      emitAs(_clientA, 'updateNewMessage', {
        'message': _message(11, 100, text: 'v1'),
      });
      await pump();
      emitAs(_clientA, 'updateDeleteMessages', {
        'chat_id': '11',
        'message_ids': ['100'],
        'is_permanent': true,
        'from_cache': false,
      });
      await pump();
      emitAs(_clientA, 'updateNewMessage', {
        'message': _message(11, 100, text: 'v1'),
      });
      await pump();

      final entry = store.entry(11, 100)!;
      expect(entry.state, MessageHistoryState.active);
      expect(entry.deletedAt, 0);
    },
  );

  test('media messages mirror their caption and kind', () async {
    await start();
    final photo = _message(11, 100)
      ..['content'] = {
        '@type': 'messagePhoto',
        'photo': {'@type': 'photo'},
        'caption': {'@type': 'formattedText', 'text': 'sunset'},
      };
    emitAs(_clientA, 'updateNewMessage', {'message': photo});
    await pump();

    final entry = store.entry(11, 100)!;
    expect(entry.text, 'sunset');
    expect(entry.kindKey, 'historyKindPhoto');
  });

  test('an excluded chat records nothing', () async {
    await start();
    store.excludeChat(11);
    await pump();

    emitAs(_clientA, 'updateNewMessage', {'message': _message(11, 100)});
    await pump();

    expect(store.entries, isEmpty);
    expect(store.isChatExcluded(11), isTrue);
  });

  test('exclusions load from the active account’s prefs key', () async {
    SharedPreferences.setMockInitialValues({
      'messageHistory.excludedChats.v2.$_accountA': <String>['11', '22'],
    });
    store.initialize(await SharedPreferences.getInstance());
    store.debugSetActiveAccount(_accountA);
    expect(store.excludedChats, {11, 22});
  });

  test('excludeChat removes the chat’s kept copies', () async {
    await start();
    emitAs(_clientA, 'updateNewMessage', {'message': _message(11, 100)});
    emitAs(_clientA, 'updateNewMessage', {'message': _message(12, 200)});
    await pump();

    store.excludeChat(11);
    await store.persistNowForTesting();

    expect(store.entries.map((entry) => entry.chatId), [12]);
    expect((persistedJson()['entries'] as List), hasLength(1));
  });

  test('clearChat and clearAll empty the mirror and the file', () async {
    await start();
    emitAs(_clientA, 'updateNewMessage', {'message': _message(11, 100)});
    emitAs(_clientA, 'updateNewMessage', {'message': _message(11, 101)});
    emitAs(_clientA, 'updateNewMessage', {'message': _message(12, 200)});
    await pump();

    expect(store.clearChat(11), 2);
    expect(store.entryCount, 1);
    expect(store.clearChat(11), 0);
    expect(store.clearAll(), 1);
    expect(store.entryCount, 0);

    await store.persistNowForTesting();
    expect((persistedJson()['entries'] as List), isEmpty);
  });

  test('persisted copies load back', () async {
    await start();
    emitAs(_clientA, 'updateNewMessage', {
      'message': _message(11, 100, text: 'kept'),
    });
    await pump();
    await store.persistNowForTesting();

    // A fresh instance must read what the first one wrote; the original is
    // left alive for tearDown to dispose.
    final revived = MessageHistoryStore.forTesting();
    revived.fileDir = dir;
    addTearDown(revived.dispose);
    await revived.ensureLoaded();
    expect(revived.entryCount, 1);
    revived.debugSetActiveAccount(_accountA);
    expect(revived.entry(11, 100)!.text, 'kept');
  });

  test('the mirror is bounded by maxEntries, dropping the oldest', () async {
    await start();
    for (var i = 0; i < MessageHistoryStore.maxEntries + 20; i++) {
      emitAs(_clientA, 'updateNewMessage', {'message': _message(11, i)});
    }
    await pump();

    expect(store.entryCount, MessageHistoryStore.maxEntries);
    // LinkedHashMap insertion order: the earliest messages were evicted.
    expect(store.entry(11, 0), isNull);
    expect(store.entry(11, MessageHistoryStore.maxEntries + 19), isNotNull);
  });

  test('chats with kept copies feed entriesFor', () async {
    await start();
    emitAs(_clientA, 'updateNewMessage', {'message': _message(11, 100)});
    emitAs(_clientA, 'updateNewMessage', {'message': _message(11, 101)});
    emitAs(_clientA, 'updateNewMessage', {'message': _message(12, 200)});
    await pump();

    expect(store.entriesFor(11), hasLength(2));
    expect(store.entriesFor(12), hasLength(1));
    expect(store.entriesFor(33), isEmpty);
  });

  // ---------------------------------------------------------------------------
  // Account ownership
  // ---------------------------------------------------------------------------

  test(
    'two accounts with the same chat/message ids keep two records',
    () async {
      await start();
      emitAs(_clientA, 'updateNewMessage', {
        'message': _message(11, 100, text: 'from A'),
      });
      await pump();
      emitAs(_clientB, 'updateNewMessage', {
        'message': _message(11, 100, text: 'from B'),
      });
      await pump();

      expect(store.entryCount, 2);
      // entryCount is global; entries is scoped to the active account, so
      // read the keys off entryCount-verified entries from both scopes.
      store.debugSetActiveAccount(_accountB);
      expect(store.entries.map((entry) => entry.key), ['$_accountB:11:100']);
      store.debugSetActiveAccount(_accountA);
      expect(store.entries.map((entry) => entry.key), ['$_accountA:11:100']);

      // The viewer only ever sees the active account's copy.
      expect(store.activeAccountUserId, _accountA);
      expect(store.entriesFor(11).single.text, 'from A');
      expect(store.entriesFor(11).single.accountUserId, _accountA);

      store.debugSetActiveAccount(_accountB);
      expect(store.entriesFor(11).single.text, 'from B');
      expect(store.entriesFor(11).single.accountUserId, _accountB);
      expect(store.entry(11, 100)!.text, 'from B');
    },
  );

  test('a switch of the active client re-scopes the mirror', () async {
    await start();
    emitAs(_clientA, 'updateNewMessage', {
      'message': _message(11, 100, text: 'from A'),
    });
    await pump();
    expect(store.activeAccountUserId, _accountA);

    store.activeClientIdProvider = () => _clientB;
    activeSlotChanges.add(_clientB);
    await pump();
    expect(store.activeAccountUserId, _accountB);
    expect(store.entriesFor(11), isEmpty);
  });

  test(
    'edits from one account never touch the other account’s entry',
    () async {
      await start();
      emitAs(_clientA, 'updateNewMessage', {
        'message': _message(11, 100, text: 'from A'),
      });
      emitAs(_clientB, 'updateNewMessage', {
        'message': _message(11, 100, text: 'from B'),
      });
      await pump();

      // Account B's counterpart edits; A's copy must stay untouched.
      emitAs(_clientB, 'updateMessageEdited', {
        'chat_id': '11',
        'message_id': 100,
        'edit_date': 1700000123,
      });
      emitAs(_clientB, 'updateMessageContent', {
        'chat_id': '11',
        'message_id': 100,
        'new_content': {
          '@type': 'messageText',
          'text': {'@type': 'formattedText', 'text': 'edited B'},
        },
      });
      await pump();

      store.debugSetActiveAccount(_accountA);
      final a = store.entry(11, 100)!;
      expect(a.isEdited, isFalse);
      expect(a.text, 'from A');
      expect(a.events, isEmpty);

      store.debugSetActiveAccount(_accountB);
      final b = store.entry(11, 100)!;
      expect(b.isEdited, isTrue);
      expect(b.text, 'edited B');
      expect(b.events.single.editDate, 1700000123);

      // And the other way around.
      emitAs(_clientA, 'updateMessageEdited', {
        'chat_id': '11',
        'message_id': 100,
        'edit_date': 1700000456,
      });
      emitAs(_clientA, 'updateMessageContent', {
        'chat_id': '11',
        'message_id': 100,
        'new_content': {
          '@type': 'messageText',
          'text': {'@type': 'formattedText', 'text': 'edited A'},
        },
      });
      await pump();

      store.debugSetActiveAccount(_accountB);
      expect(store.entry(11, 100)!.text, 'edited B');
      store.debugSetActiveAccount(_accountA);
      final a2 = store.entry(11, 100)!;
      expect(a2.text, 'edited A');
      expect(a2.events, hasLength(1));
      expect(a2.events.single.editDate, 1700000456);
    },
  );

  test('deletions from one account mark only that account’s copy', () async {
    await start();
    emitAs(_clientA, 'updateNewMessage', {
      'message': _message(11, 100, text: 'from A'),
    });
    emitAs(_clientB, 'updateNewMessage', {
      'message': _message(11, 100, text: 'from B'),
    });
    await pump();

    emitAs(_clientB, 'updateDeleteMessages', {
      'chat_id': '11',
      'message_ids': ['100'],
      'is_permanent': true,
      'from_cache': false,
    });
    await pump();

    store.debugSetActiveAccount(_accountA);
    expect(store.entry(11, 100)!.state, MessageHistoryState.active);
    expect(store.entry(11, 100)!.deletedAt, 0);

    store.debugSetActiveAccount(_accountB);
    expect(store.entry(11, 100)!.state, MessageHistoryState.deleted);
    expect(store.entry(11, 100)!.deletedAt, greaterThan(0));
  });

  test('exclusions are per account and the same chat stays recorded '
      'elsewhere', () async {
    await start();
    emitAs(_clientA, 'updateNewMessage', {
      'message': _message(11, 100, text: 'from A'),
    });
    emitAs(_clientB, 'updateNewMessage', {
      'message': _message(11, 100, text: 'from B'),
    });
    await pump();

    // Account A excludes the chat: its copies are dropped, B's are kept.
    store.debugSetActiveAccount(_accountA);
    store.excludeChat(11);
    await pump();

    expect(store.isChatExcluded(11), isTrue);
    expect(store.entriesFor(11), isEmpty);
    store.debugSetActiveAccount(_accountB);
    expect(store.isChatExcluded(11), isFalse);
    expect(store.entriesFor(11).single.text, 'from B');

    // A no longer records the chat; B still does.
    emitAs(_clientA, 'updateNewMessage', {
      'message': _message(11, 101, text: 'from A again'),
    });
    emitAs(_clientB, 'updateNewMessage', {
      'message': _message(11, 102, text: 'from B again'),
    });
    await pump();
    store.debugSetActiveAccount(_accountA);
    expect(store.entriesFor(11), isEmpty);
    store.debugSetActiveAccount(_accountB);
    expect(store.entriesFor(11).map((entry) => entry.messageId), [100, 102]);

    // Each account's exclusion persists under its own prefs key.
    store.debugSetActiveAccount(_accountB);
    store.excludeChat(33);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('messageHistory.excludedChats.v2.$_accountA'), [
      '11',
    ]);
    expect(prefs.getStringList('messageHistory.excludedChats.v2.$_accountB'), [
      '33',
    ]);
  });

  test(
    'persisted records carry their account and reload per account',
    () async {
      await start();
      emitAs(_clientA, 'updateNewMessage', {
        'message': _message(11, 100, text: 'from A'),
      });
      emitAs(_clientB, 'updateNewMessage', {
        'message': _message(11, 100, text: 'from B'),
      });
      await pump();
      await store.persistNowForTesting();

      final json = persistedJson();
      expect(json['version'], 2);
      final entries = json['entries'] as List;
      expect(entries, hasLength(2));
      expect(entries.map((entry) => entry['account']).toSet(), {
        _accountA,
        _accountB,
      });

      final revived = MessageHistoryStore.forTesting();
      revived.fileDir = dir;
      addTearDown(revived.dispose);
      await revived.ensureLoaded();
      expect(revived.entryCount, 2);

      revived.debugSetActiveAccount(_accountA);
      expect(revived.entry(11, 100)!.text, 'from A');
      revived.debugSetActiveAccount(_accountB);
      expect(revived.entry(11, 100)!.text, 'from B');
    },
  );

  test('a pre-account mirror file loads to zero entries', () async {
    // v1 records have no account field; loading them would attribute the
    // history to whichever account happens to be active, so they are
    // dropped on purpose.
    File('${dir.path}/message-history.json').writeAsStringSync(
      '{"version":1,"entries":[{"chat":11,"id":100,"sender":42,'
      '"date":1700000000,"text":"stale","kind":"","state":"active",'
      '"deletedAt":0,"events":[]}]}',
    );
    final revived = MessageHistoryStore.forTesting();
    revived.fileDir = dir;
    addTearDown(revived.dispose);
    await revived.ensureLoaded();
    expect(revived.entryCount, 0);
    expect(revived.entries, isEmpty);
  });

  test('removeAccount forgets that account and keeps the others', () async {
    await start();
    emitAs(_clientA, 'updateNewMessage', {'message': _message(12, 200)});
    emitAs(_clientB, 'updateNewMessage', {'message': _message(11, 100)});
    emitAs(_clientB, 'updateMessageEdited', {
      'chat_id': '11',
      'message_id': 100,
      'edit_date': 1700000123,
    });
    await pump();

    store.debugSetActiveAccount(_accountA);
    store.excludeChat(22);
    store.debugSetActiveAccount(_accountB);
    store.excludeChat(33);
    await pump();

    store.removeAccount(_accountB);

    expect(store.entryCount, 1);
    store.debugSetActiveAccount(_accountA);
    expect(store.entries.single.chatId, 12);
    store.debugSetActiveAccount(_accountB);
    expect(store.entries, isEmpty);
    expect(store.isChatExcluded(33), isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.containsKey('messageHistory.excludedChats.v2.$_accountB'),
      isFalse,
    );
    expect(prefs.getStringList('messageHistory.excludedChats.v2.$_accountA'), [
      '22',
    ]);

    // B's pending edit dates died with the account: a late content update
    // produces nothing instead of touching a re-registered account's copy.
    emitAs(_clientB, 'updateNewMessage', {
      'message': _message(11, 100, text: 'fresh'),
    });
    await pump();
    emitAs(_clientB, 'updateMessageContent', {
      'chat_id': '11',
      'message_id': 100,
      'new_content': {
        '@type': 'messageText',
        'text': {'@type': 'formattedText', 'text': 'orphan edit'},
      },
    });
    await pump();
    store.debugSetActiveAccount(_accountB);
    final entry = store.entry(11, 100)!;
    expect(entry.text, 'fresh');
    expect(entry.isEdited, isFalse);
  });

  test('updates whose client cannot be resolved are dropped', () async {
    store.accountUserIdResolver = _StubResolver({
      _clientA: _accountA,
      777: null,
    });
    await start();
    // The active-client resolution during start() legitimately notifies.
    notifications = 0;
    emitAs(777, 'updateNewMessage', {'message': _message(11, 100)});
    await pump();
    expect(store.entryCount, 0);
    expect(store.entries, isEmpty);
    expect(notifications, 0);

    // A later resolvable account still records; the failure is per client.
    emitAs(_clientA, 'updateNewMessage', {'message': _message(11, 100)});
    await pump();
    expect(store.entryCount, 1);
  });

  test('updates without a client id are dropped, not attributed', () async {
    await start();
    // The active-client resolution during start() legitimately notifies.
    notifications = 0;
    emit('updateNewMessage', {'message': _message(11, 100)});
    await pump();
    expect(store.entryCount, 0);
    expect(notifications, 0);
  });

  test('a burst of edits on one account lands in arrival order', () async {
    await start();
    emitAs(_clientA, 'updateNewMessage', {
      'message': _message(11, 100, text: 'v0'),
    });
    emitAs(_clientB, 'updateNewMessage', {
      'message': _message(11, 100, text: 'other account'),
    });
    emitAs(_clientA, 'updateMessageEdited', {
      'chat_id': '11',
      'message_id': 100,
      'edit_date': 111,
    });
    emitAs(_clientA, 'updateMessageContent', {
      'chat_id': '11',
      'message_id': 100,
      'new_content': {
        '@type': 'messageText',
        'text': {'@type': 'formattedText', 'text': 'v1'},
      },
    });
    emitAs(_clientA, 'updateMessageEdited', {
      'chat_id': '11',
      'message_id': 100,
      'edit_date': 222,
    });
    emitAs(_clientA, 'updateMessageContent', {
      'chat_id': '11',
      'message_id': 100,
      'new_content': {
        '@type': 'messageText',
        'text': {'@type': 'formattedText', 'text': 'v2'},
      },
    });
    await pump();

    store.debugSetActiveAccount(_accountA);
    final entry = store.entry(11, 100)!;
    expect(entry.text, 'v2');
    expect(entry.events.map((event) => event.editDate), [111, 222]);
    expect(entry.events[0].newText, 'v1');
    expect(entry.events[1].newText, 'v2');
  });

  // ---------------------------------------------------------------------------
  // Pending-work invalidation, arrival ordering, failed resolutions
  // (second review round)
  // ---------------------------------------------------------------------------

  test(
    'removeAccount during a held identity lookup keeps the mirror empty',
    () async {
      final gates = {_clientA: Completer<int?>(), _clientB: Completer<int?>()};
      store.accountUserIdResolver = _GatedResolver(gates);
      await start();
      gates[_clientA]!.complete(_accountA);
      await pump();
      notifications = 0;

      // The new message for account B arrives while its client identity is
      // still being resolved.
      emitAs(_clientB, 'updateNewMessage', {
        'message': _message(11, 100, text: 'from B'),
      });
      await pump();

      // The slot is logged out / removed before the lookup completes.
      store.removeAccount(_accountB);
      expect(store.entryCount, 0);
      await pump();
      expect(store.entryCount, 0);
      // The removal's account-context invalidation notifies legitimately.
      notifications = 0;

      // The lookup completes AFTER the removal: its pending work must be
      // invalidated, not resurrect the removed account's history.
      gates[_clientB]!.complete(_accountB);
      await pump();
      await pump();

      expect(store.entryCount, 0);
      expect(store.entries, isEmpty);
      expect(notifications, 0);

      await store.persistNowForTesting();
      // No record may have been persisted either: the resurrection would
      // have armed the batched writer for the removed account's entry.
      expect(persistedJson()['entries'], isEmpty);
    },
  );

  test(
    'held first lookup does not reorder a client\'s arrival chain',
    () async {
      final held = _HoldFirstResolver({
        _clientA: _accountA,
        _clientB: _accountB,
      });
      store.accountUserIdResolver = held;
      await start();
      held.release(_clientA, _accountA);
      await pump();
      notifications = 0;

      // One client's updates arrive in this TDLib order.
      emitAs(_clientB, 'updateNewMessage', {
        'message': _message(11, 100, text: 'before edit'),
      });
      emitAs(_clientB, 'updateMessageEdited', {
        'chat_id': '11',
        'message_id': 100,
        'edit_date': 111,
      });
      emitAs(_clientB, 'updateMessageContent', {
        'chat_id': '11',
        'message_id': 100,
        'new_content': {
          '@type': 'messageText',
          'text': {'@type': 'formattedText', 'text': 'after edit'},
        },
      });
      await pump();

      // Identity resolution completes only now; the already-arrived chain
      // must still apply in arrival order.
      held.release(_clientB, _accountB);
      await pump();
      await pump();

      store.debugSetActiveAccount(_accountB);
      final entry = store.entry(11, 100)!;
      expect(entry.text, 'after edit');
      expect(entry.isEdited, isTrue, reason: 'the edit event must survive');
      expect(entry.events.single.editDate, 111);
      expect(entry.events.single.oldText, 'before edit');
      expect(entry.events.single.newText, 'after edit');
    },
  );

  test('a failing resolution drops the updates and later ones retry', () async {
    final gates = {_clientA: Completer<int?>(), _clientB: Completer<int?>()};
    store.accountUserIdResolver = _GatedResolver(gates);
    await start();
    gates[_clientA]!.complete(_accountA);
    await pump();

    emitAs(_clientB, 'updateNewMessage', {
      'message': _message(11, 100, text: 'from B'),
    });
    await pump();
    // Failing the first lookup drops that client's queued events; nothing
    // may be written, guessed or partially recorded.
    gates[_clientB]!.completeError(StateError('getMe lost'));
    await pump();
    await pump();
    expect(store.entryCount, 0);
    expect(store.entries, isEmpty);

    // The next event starts a fresh resolution attempt.
    gates[_clientB] = Completer<int?>()..complete(_accountB);
    emitAs(_clientB, 'updateNewMessage', {
      'message': _message(11, 100, text: 'second attempt'),
    });
    await pump();
    await pump();
    store.debugSetActiveAccount(_accountB);
    expect(store.entry(11, 100)!.text, 'second attempt');
  });

  test('a throwing resolver keeps the mirror inert on every attempt', () async {
    store.accountUserIdResolver = _FailingResolver(
      {_clientA: _accountA, _clientB: _accountB},
      failing: {_clientB},
    );
    await start();
    notifications = 0;

    emitAs(_clientB, 'updateNewMessage', {
      'message': _message(11, 100, text: 'from B'),
    });
    emitAs(_clientB, 'updateDeleteMessages', {
      'chat_id': '11',
      'message_ids': ['100'],
      'is_permanent': true,
      'from_cache': false,
    });
    await pump();
    await pump();
    await pump();

    expect(store.entryCount, 0);
    expect(store.entries, isEmpty);
    expect(notifications, 0);

    // A resolvable client keeps recording next to the failing one.
    emitAs(_clientA, 'updateNewMessage', {
      'message': _message(11, 100, text: 'from A'),
    });
    await pump();
    expect(store.entryCount, 1);
    store.debugSetActiveAccount(_accountA);
    expect(store.entries.single.text, 'from A');
  });

  test(
    'an active account whose re-resolution fails keeps the viewer empty',
    () async {
      final gates = {_clientA: Completer<int?>(), _clientB: Completer<int?>()};
      store.accountUserIdResolver = _GatedResolver(gates);
      await start();
      gates[_clientA]!.complete(_accountA);
      await pump();

      emitAs(_clientA, 'updateNewMessage', {
        'message': _message(11, 100, text: 'from A'),
      });
      await pump();
      store.debugSetActiveAccount(_accountA);
      expect(store.entries.single.text, 'from A');
      notifications = 0;

      // Switch the active client to B; the store must drop to unresolved
      // (empty) and notify the viewer IMMEDIATELY, not only when the
      // resolution lands.
      store.activeClientIdProvider = () => _clientB;
      activeSlotChanges.add(_clientB);
      await pump();
      expect(store.activeAccountUserId, isNull);
      expect(store.entries, isEmpty);
      expect(notifications, greaterThan(0));

      // B's resolution fails: still empty, still notified, never A's rows.
      notifications = 0;
      gates[_clientB]!.completeError(StateError('getMe lost'));
      await pump();
      await pump();
      expect(store.activeAccountUserId, isNull);
      expect(store.entries, isEmpty);
      expect(store.entryCount, 1, reason: 'A’s copy must be untouched');
      expect(notifications, greaterThan(0));

      // Recovering the resolution on a later attempt shows B's rows.
      gates[_clientB] = Completer<int?>()..complete(_accountB);
      emitAs(_clientB, 'updateNewMessage', {
        'message': _message(11, 100, text: 'from B'),
      });
      await pump();
      await pump();
      expect(store.activeAccountUserId, _accountB);
      expect(store.entries.single.text, 'from B');
    },
  );

  test(
    'a switch away clears the active scope immediately, before resolution',
    () async {
      final gates = {
        _clientA: Completer<int?>()..complete(_accountA),
        _clientB: Completer<int?>(),
      };
      store.accountUserIdResolver = _GatedResolver(gates);
      await start();
      await pump();

      emitAs(_clientA, 'updateNewMessage', {
        'message': _message(11, 100, text: 'from A'),
      });
      await pump();
      expect(store.entries.single.text, 'from A');

      // The slot switches to an unresolved client: the accessors must read
      // empty from that very moment (they do), and the switch itself must
      // notify so listeners re-read them.
      notifications = 0;
      store.activeClientIdProvider = () => _clientB;
      activeSlotChanges.add(_clientB);
      await pump();
      expect(store.entries, isEmpty);
      expect(notifications, greaterThan(0));
    },
  );

  // ---------------------------------------------------------------------------
  // Scoped invalidation (third review round): removing one account or
  // clearing one chat must not cancel unrelated pending work — only the
  // explicitly global operations (clearAll, dispose) invalidate everything.
  // ---------------------------------------------------------------------------

  test(
    'removing one account does not drop another account\'s pending update',
    () async {
      final gates = {_clientA: Completer<int?>(), _clientB: Completer<int?>()};
      store.accountUserIdResolver = _GatedResolver(gates);
      await start();
      gates[_clientA]!.complete(_accountA);
      await pump();
      // Seed A's mirror so the removal below really removes something.
      emitAs(_clientA, 'updateNewMessage', {
        'message': _message(12, 200, text: 'from A'),
      });
      await pump();
      expect(store.entry(12, 200)!.text, 'from A');

      // B's message arrives while B's identity lookup is still held.
      emitAs(_clientB, 'updateNewMessage', {
        'message': _message(11, 100, text: 'from B'),
      });
      await pump();

      // Removing A invalidates A's scope only.
      store.removeAccount(_accountA);
      expect(store.entryCount, 0);
      await pump();
      expect(store.entryCount, 0);

      // B was not removed: its queued update must still record.
      gates[_clientB]!.complete(_accountB);
      await pump();
      await pump();

      expect(store.entryCount, 1);
      store.debugSetActiveAccount(_accountB);
      expect(store.entry(11, 100)!.text, 'from B');
    },
  );

  test(
    'clearing one chat does not drop a pending update of another chat',
    () async {
      // The account is logged in on two slots; the active one is resolved
      // while the other slot's identity lookup stays held.
      const clientB2 = 303;
      final gates = {
        _clientB: Completer<int?>()..complete(_accountB),
        clientB2: Completer<int?>(),
      };
      store.accountUserIdResolver = _GatedResolver(gates);
      store.activeClientIdProvider = () => _clientB;
      await start();
      await pump();
      await pump();
      expect(store.activeAccountUserId, _accountB);

      // Chat 42 has history to clear.
      emitAs(_clientB, 'updateNewMessage', {
        'message': _message(42, 400, text: 'chat 42'),
      });
      await pump();
      expect(store.entry(42, 400)!.text, 'chat 42');

      // Chat 77's message arrives on the other slot while ITS identity
      // lookup is still pending.
      emitAs(clientB2, 'updateNewMessage', {
        'message': _message(77, 700, text: 'chat 77'),
      });
      await pump();

      // Clearing chat 42 must not touch chat 77's queued update.
      store.clearChat(42);
      expect(store.entry(42, 400), isNull);

      gates[clientB2]!.complete(_accountB);
      await pump();
      await pump();

      expect(store.entry(42, 400), isNull, reason: 'chat 42 stays cleared');
      expect(store.entry(77, 700)!.text, 'chat 77');
    },
  );

  test('a load after removeAccount restores the other accounts only', () async {
    await start();
    emitAs(_clientA, 'updateNewMessage', {
      'message': _message(12, 200, text: 'from A'),
    });
    emitAs(_clientB, 'updateNewMessage', {
      'message': _message(42, 400, text: 'chat 42'),
    });
    emitAs(_clientB, 'updateNewMessage', {
      'message': _message(77, 700, text: 'chat 77'),
    });
    await pump();
    await store.persistNowForTesting();

    final revived = MessageHistoryStore.forTesting();
    revived.fileDir = dir;
    addTearDown(revived.dispose);
    // Removing A must drop A's disk rows on load but leave the load itself
    // — and every other account's rows — alive.
    revived.removeAccount(_accountA);
    await revived.ensureLoaded();

    expect(revived.entryCount, 2);
    revived.debugSetActiveAccount(_accountB);
    expect(revived.entry(42, 400)!.text, 'chat 42');
    expect(revived.entry(77, 700)!.text, 'chat 77');
    revived.debugSetActiveAccount(_accountA);
    expect(revived.entries, isEmpty);
  });

  test('outgoing messages are not mirrored', () async {
    await start();
    emitAs(_clientA, 'updateNewMessage', {
      'message': {..._message(11, 300), 'is_outgoing': true},
    });
    await pump();
    expect(store.entry(11, 300), isNull);
  });

  test('saved messages (self chat) mirror even when outgoing', () async {
    await start();
    // chat id == own user id: the self dialog is incoming from itself.
    emitAs(_clientA, 'updateNewMessage', {
      'message': {
        ..._message(_accountA, 301, text: 'note to self'),
        'is_outgoing': true,
      },
    });
    await pump();
    expect(store.entry(_accountA, 301)?.text, 'note to self');
  });

  test('a chat TDLib reports gone marks its entries ghost', () async {
    await start();
    emitAs(_clientA, 'updateNewMessage', {'message': _message(11, 100)});
    await pump();
    expect(store.entry(11, 100)?.hasLiveChat, isTrue);
    emitAs(_clientA, 'updateChat', {
      'chat': {
        '@type': 'chat',
        'id': '11',
        'type': {'@type': 'chatTypeUnknown'},
      },
    });
    await pump();
    expect(store.entry(11, 100)?.hasLiveChat, isFalse);
  });

  test(
    'a media file fully on disk is snapshotted into the mirror dir',
    () async {
      final media = MessageMediaSnapshotter.forTesting();
      media.dir = dir;
      store.mediaSnapshotter = media;
      final source = File('${dir.path}/tdlib-cache-photo.jpg')
        ..writeAsBytesSync(List.filled(8, 7));
      await start();
      emitAs(_clientA, 'updateNewMessage', {
        'message': {
          ..._message(11, 400),
          'content': {
            '@type': 'messagePhoto',
            'photo': {
              '@type': 'photo',
              'sizes': [
                {
                  '@type': 'photoSize',
                  'width': 100,
                  'height': 50,
                  'photo': {
                    '@type': 'file',
                    'id': 5,
                    'local': {
                      '@type': 'localFile',
                      'path': source.path,
                      'is_downloading_completed': true,
                      'is_active_downloading': false,
                    },
                  },
                },
              ],
            },
          },
        },
      });
      // The copy runs off the update chain; wait for it deterministically
      // instead of counting microtask pumps.
      for (var i = 0; i < 100; i++) {
        if ((store.entry(11, 400)?.mediaPath ?? '').isNotEmpty) break;
        await Future<void>.delayed(Duration.zero);
      }
      final entry = store.entry(11, 400)!;
      expect(entry.kindKey, 'historyKindPhoto');
      expect(entry.mediaPath, isNotEmpty);
      expect(File(entry.mediaPath).existsSync(), isTrue);
      // clearing the chat deletes the snapshot file too
      store.debugSetActiveAccount(_accountA);
      store.clearChat(11);
      expect(File(entry.mediaPath).existsSync(), isFalse);
    },
  );

  test('a messageAudio file is snapshotted too', () async {
    final media = MessageMediaSnapshotter.forTesting();
    media.dir = dir;
    store.mediaSnapshotter = media;
    final source = File('${dir.path}/tdlib-cache-song.mp3')
      ..writeAsBytesSync(List.filled(8, 3));
    await start();
    emitAs(_clientA, 'updateNewMessage', {
      'message': {
        ..._message(11, 402),
        'content': {
          '@type': 'messageAudio',
          'audio': {
            '@type': 'audio',
            'audio': {
              '@type': 'file',
              'id': 7,
              'local': {
                '@type': 'localFile',
                'path': source.path,
                'is_downloading_completed': true,
                'is_active_downloading': false,
              },
            },
          },
        },
      },
    });
    for (var i = 0; i < 100; i++) {
      if ((store.entry(11, 402)?.mediaPath ?? '').isNotEmpty) break;
      await Future<void>.delayed(Duration.zero);
    }
    final entry = store.entry(11, 402)!;
    expect(entry.kindKey, 'historyKindAudio');
    expect(entry.mediaPath, isNotEmpty);
    expect(File(entry.mediaPath).existsSync(), isTrue);
  });

  test(
    'a copy finishing after removeAccount leaves no snapshot file behind',
    () async {
      final media = MessageMediaSnapshotter.forTesting();
      media.dir = dir;
      store.mediaSnapshotter = media;
      final source = File('${dir.path}/tdlib-cache-voice.oga')
        ..writeAsBytesSync(List.filled(8, 5));
      // Hold every copy right before its post-copy validation, so the
      // account removal lands while the copy is in flight.
      final copyGate = Completer<void>();
      media.beforeValidateForTesting = () => copyGate.future;
      await start();
      emitAs(_clientA, 'updateNewMessage', {
        'message': {
          ..._message(11, 403),
          'content': {
            '@type': 'messageVoiceNote',
            'voice_note': {
              '@type': 'voiceNote',
              'voice': {
                '@type': 'file',
                'id': 8,
                'local': {
                  '@type': 'localFile',
                  'path': source.path,
                  'is_downloading_completed': true,
                  'is_active_downloading': false,
                },
              },
            },
          },
        },
      });
      // Wait until the copy itself has landed on disk (validation still held).
      String? copiedPath;
      for (var i = 0; i < 100; i++) {
        final files = dir
            .listSync()
            .whereType<File>()
            .map((f) => f.path)
            .where((p) => p.contains('${_accountA}_11_'))
            .toList();
        if (files.isNotEmpty) {
          copiedPath = files.single;
          break;
        }
        await Future<void>.delayed(Duration.zero);
      }
      expect(copiedPath, isNotNull, reason: 'the copy never started');

      store.removeAccount(_accountA);
      copyGate.complete();
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(store.entryCount, 0);
      expect(
        File(copiedPath!).existsSync(),
        isFalse,
        reason: 'an in-flight copy must be deleted, not left behind',
      );
    },
  );

  test(
    'the production snapshotter resolves its directory from app support',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final media = MessageMediaSnapshotter.forTesting();
      store.mediaSnapshotter = media;
      // Drive the same platform channel production uses; without it the
      // widget-test binding has no path_provider backend and the resolver
      // would stay inert (the bug: snapshots only ran in tests).
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      messenger.setMockMethodCallHandler(paths, (call) async => dir.path);
      addTearDown(() {
        messenger.setMockMethodCallHandler(paths, null);
      });
      final source = File('${dir.path}/tdlib-cache-pic.jpg')
        ..writeAsBytesSync(List.filled(4, 9));
      await start();
      emitAs(_clientA, 'updateNewMessage', {
        'message': {
          ..._message(11, 404),
          'content': _photoContent(source.path, id: 9),
        },
      });
      for (var i = 0; i < 100; i++) {
        if (media.dir != null) break;
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        media.dir,
        isNotNull,
        reason: 'snapshots must run in production, not only in tests',
      );
      for (var i = 0; i < 100; i++) {
        if ((store.entry(11, 404)?.mediaPath ?? '').isNotEmpty) break;
        await Future<void>.delayed(Duration.zero);
      }
      expect(store.entry(11, 404)?.mediaPath, isNotEmpty);
    },
  );

  test('a partially downloaded media file is not snapshotted', () async {
    final media = MessageMediaSnapshotter.forTesting();
    media.dir = dir;
    store.mediaSnapshotter = media;
    await start();
    emitAs(_clientA, 'updateNewMessage', {
      'message': {
        ..._message(11, 401),
        'content': {
          '@type': 'messagePhoto',
          'photo': {
            '@type': 'photo',
            'sizes': [
              {
                '@type': 'photoSize',
                'width': 100,
                'height': 50,
                'photo': {
                  '@type': 'file',
                  'id': 6,
                  'local': {
                    '@type': 'localFile',
                    'path': '/nonexistent/partial.jpg',
                    'is_downloading_completed': false,
                    'is_active_downloading': true,
                  },
                },
              },
            ],
          },
        },
      },
    });
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(store.entry(11, 401)?.mediaPath, isEmpty);
  });
}
