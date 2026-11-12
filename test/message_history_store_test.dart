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

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/history/message_history_settings.dart';
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
    // The runtime switches default to OFF; this suite exercises the store
    // with recording enabled.
    final settings = MessageHistorySettings.shared;
    settings.setEnableAll(true);
    settings.setRecordDeleted(true);
    settings.setRecordEdits(true);
    settings.setSnapshotPrivate(true);
    store.initialize(await SharedPreferences.getInstance());
    notifications = 0;
    store.addListener(() => notifications++);
  });

  tearDown(() async {
    store.dispose();
    await updates.close();
    await activeSlotChanges.close();
    await dir.delete(recursive: true);
    // Reset the runtime switches for the next suite (defaults are OFF).
    final settings = MessageHistorySettings.shared;
    settings.setEnableAll(false);
    settings.setRecordDeleted(false);
    settings.setRecordEdits(false);
    settings.setSnapshotPrivate(false);
  });

  Future<void> pump() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> start() async {
    store.startObserving();
    await pump();
  }

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

  test('an excluded chat records nothing', () async {
    await start();
    store.excludeChat(11);
    await pump();

    emitAs(_clientA, 'updateNewMessage', {'message': _message(11, 100)});
    await pump();

    expect(store.entries, isEmpty);
    expect(store.isChatExcluded(11), isTrue);
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

  // ---------------------------------------------------------------------------
  // Account ownership
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // Pending-work invalidation, arrival ordering, failed resolutions
  // (second review round)
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // Scoped invalidation (third review round): removing one account or
  // clearing one chat must not cancel unrelated pending work — only the
  // explicitly global operations (clearAll, dispose) invalidate everything.
  // ---------------------------------------------------------------------------

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
