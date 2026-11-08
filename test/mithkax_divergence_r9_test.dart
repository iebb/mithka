//
//  r9 divergent-review regressions:
//  1) a genuine bot sender inside a GROUP must not flip the whole chat into
//     the bot-dialog gate — the bot question exists only for private chats.
//  2) imported media is rewritten under the IMPORTING account prefix, so
//     deleteScope/deleteAccount of that account can reclaim the file, and the
//     imported row carries the new path (not the exporter's stale one).
//
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/history/message_history_settings.dart';
import 'package:mithka/history/message_history_store.dart';
import 'package:mithka/history/message_media_snapshot.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabled = allowTelegramTosViolations;
const _clientA = 901;
const _accountA = 7901;

class _R implements TosAccountUserIdResolver {
  @override
  Future<int?> resolve(int clientId) async => _accountA;
}

Map<String, dynamic> _msg(
  int chatId,
  int id, {
  bool isBot = false,
  int senderId = 42,
}) => {
  '@type': 'message',
  'chat_id': '$chatId',
  'id': id,
  'date': 1700000000 + id,
  'is_outgoing': false,
  'sender_id': {
    '@type': 'messageSenderUser',
    'user_id': '$senderId',
    if (isBot) 'is_bot': true,
  },
  'content': {
    '@type': 'messageText',
    'text': {'@type': 'formattedText', 'text': 'x'},
  },
};

void main() {
  if (!_enabled) return;

  late Directory dir;
  late StreamController<Map<String, dynamic>> updates;
  late MessageHistoryStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mithkax-r9-reg');
    updates = StreamController<Map<String, dynamic>>.broadcast();
    store = MessageHistoryStore.forTesting();
    store.fileDir = dir;
    store.updateSource = (_) => updates.stream;
    store.activeSlotChangeSource = () => const Stream<int>.empty();
    store.accountUserIdResolver = _R();
    store.activeClientIdProvider = () => _clientA;
    SharedPreferences.setMockInitialValues(const {});
    final settings = MessageHistorySettings.shared;
    settings.setEnableAll(true);
    settings.setRecordDeleted(true);
    settings.setRecordGroups(true);
    store.initialize(await SharedPreferences.getInstance());
    store.debugSetActiveAccount(_accountA);
  });

  tearDown(() async {
    store.dispose();
    await updates.close();
    await dir.delete(recursive: true);
    final settings = MessageHistorySettings.shared;
    settings.setEnableAll(false);
    settings.setRecordDeleted(false);
    settings.setRecordGroups(true);
    settings.setRecordBots(false);
  });

  Future<void> pump() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> emit(Map<String, dynamic> update) async {
    updates.add(update);
    await pump();
    await pump();
  }

  test('REG-1: a genuine bot posting inside a group still records', () async {
    store.startObserving();
    await pump();
    final settings = MessageHistorySettings.shared;
    settings.setRecordBots(false);
    const group = -1001234567890;
    await emit({
      '@type': 'updateNewMessage',
      '@client_id': _clientA,
      'message': _msg(group, 1, isBot: true),
    });
    expect(store.entries, isNotEmpty);
    // A human message in the same group after the bot one records too —
    // the bot post must not have flipped the chat's gate.
    await emit({
      '@type': 'updateNewMessage',
      '@client_id': _clientA,
      'message': _msg(group, 2),
    });
    expect(store.entries.map((e) => e.messageId), [1, 2]);
  });

  test(
    'REG-2: updateChat(verified bot private chat) still gates that dialog',
    () async {
      store.startObserving();
      await pump();
      final settings = MessageHistorySettings.shared;
      settings.setRecordBots(false);
      await emit({
        '@type': 'updateChat',
        '@client_id': _clientA,
        'chat': {
          '@type': 'chat',
          'id': '601',
          'type': {'@type': 'chatTypePrivate', 'user_id': '99', 'is_bot': true},
        },
      });
      await emit({
        '@type': 'updateNewMessage',
        '@client_id': _clientA,
        'message': _msg(601, 1),
      });
      expect(
        store.entries,
        isEmpty,
        reason: 'bot dialog stays gated by recordBots',
      );
    },
  );

  test(
    'REG-3: imported media is renamed to the importing account prefix',
    () async {
      final snap = MessageMediaSnapshotter.forTesting();
      snap.dir = Directory('${dir.path}/media');
      store.mediaSnapshotter = snap;
      final path = await snap.writeSnapshotBytes('7901:55:9', [1, 2, 3]);
      expect(path, isNotNull);
      store.debugSeed([
        MessageHistoryEntry(
          accountUserId: 7901,
          chatId: 55,
          messageId: 9,
          senderId: 42,
          date: 1,
          text: '',
          kindKey: 'historyKindPhoto',
          state: MessageHistoryState.active,
          deletedAt: 0,
          events: const [],
          mediaPath: path!,
        ),
      ]);
      final doc = await store.exportAccount();
      store.debugSetActiveAccount(7902);
      final restored = await store.importAccount(
        Map<String, Object?>.from(doc),
      );
      expect(restored, 1);
      final entry = store.entry(55, 9)!;
      expect(entry.mediaPath, contains('7902_55_9_'));
      // And the importing account can reclaim the file by scope.
      store.excludeChat(55);
      expect(File(entry.mediaPath).existsSync(), isFalse);
    },
  );
}
