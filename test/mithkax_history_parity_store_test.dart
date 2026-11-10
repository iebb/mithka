//
//  Exteraless-parity store tests: per-chat-type recording gates, bot
//  detection, exclusions, and the export/import round trip.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/history/message_history_settings.dart';
import 'package:mithka/history/message_history_store.dart';
import 'package:mithka/history/message_media_snapshot.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabled = allowTelegramTosViolations;

const _clientA = 301;
const _accountA = 8101;

class _StubResolver implements TosAccountUserIdResolver {
  _StubResolver(this.ids);

  final Map<int, int> ids;

  @override
  Future<int?> resolve(int clientId) async => ids[clientId];
}

Map<String, dynamic> _message(
  int chatId,
  int messageId, {
  String text = 'hello',
  bool isBot = false,
  int senderId = 42,
  Map<String, dynamic>? content,
}) => {
  '@type': 'message',
  'chat_id': '$chatId',
  'id': messageId,
  'date': 1700000000 + messageId,
  'is_outgoing': false,
  'sender_id': {
    '@type': 'messageSenderUser',
    'user_id': '$senderId',
    if (isBot) 'is_bot': true,
  },
  'content':
      content ??
      {
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

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mithkax-parity-test');
    updates = StreamController<Map<String, dynamic>>.broadcast();
    activeSlotChanges = StreamController<int>.broadcast();
    store = MessageHistoryStore.forTesting();
    store.fileDir = dir;
    store.updateSource = (_) => updates.stream;
    store.activeSlotChangeSource = () => activeSlotChanges.stream;
    store.accountUserIdResolver = _StubResolver({_clientA: _accountA});
    store.activeClientIdProvider = () => _clientA;
    SharedPreferences.setMockInitialValues(const {});
    final settings = MessageHistorySettings.shared;
    settings.setEnableAll(true);
    settings.setRecordDeleted(true);
    settings.setRecordEdits(true);
    store.initialize(await SharedPreferences.getInstance());
    store.debugSetActiveAccount(_accountA);
  });

  tearDown(() async {
    store.dispose();
    await updates.close();
    await activeSlotChanges.close();
    await dir.delete(recursive: true);
    final settings = MessageHistorySettings.shared;
    settings.setEnableAll(false);
    settings.setRecordDeleted(false);
    settings.setRecordEdits(false);
    settings.setRecordPrivate(true);
    settings.setRecordGroups(true);
    settings.setRecordChannels(true);
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

  Future<void> start() async {
    store.startObserving();
    await pump();
  }

  test(
    'per-type gates: private off drops user chats, groups keep theirs',
    () async {
      await start();
      final settings = MessageHistorySettings.shared;
      settings.setRecordPrivate(false);
      await emit({
        '@type': 'updateNewMessage',
        '@client_id': _clientA,
        'message': _message(501, 1),
      });
      await emit({
        '@type': 'updateNewMessage',
        '@client_id': _clientA,
        'message': _message(-1001234567890, 2),
      });
      expect(store.entries.map((e) => e.chatId), [-1001234567890]);
    },
  );

  test('bot chats record only with the bot switch on', () async {
    await start();
    final settings = MessageHistorySettings.shared;
    settings.setRecordBots(false);
    await emit({
      '@type': 'updateNewMessage',
      '@client_id': _clientA,
      'message': _message(601, 1, isBot: true),
    });
    expect(store.entries, isEmpty);

    settings.setRecordBots(true);
    await emit({
      '@type': 'updateNewMessage',
      '@client_id': _clientA,
      'message': _message(601, 2, isBot: true),
    });
    expect(store.entries.map((e) => e.messageId), [2]);
  });

  test('updateChat seeds bot knowledge and overrides the sniff', () async {
    await start();
    final settings = MessageHistorySettings.shared;
    settings.setRecordBots(false);
    // No is_bot on the message — the sniff misses it; updateChat then says
    // the chat IS a bot chat, so the second message must be dropped.
    await emit({
      '@type': 'updateNewMessage',
      '@client_id': _clientA,
      'message': _message(701, 1),
    });
    await emit({
      '@type': 'updateChat',
      '@client_id': _clientA,
      'chat': {
        '@type': 'chat',
        'id': '701',
        'type': {'@type': 'chatTypePrivate', 'user_id': '42', 'is_bot': true},
      },
    });
    await emit({
      '@type': 'updateNewMessage',
      '@client_id': _clientA,
      'message': _message(701, 2),
    });
    expect(store.entries.map((e) => e.messageId), [1]);
  });

  test(
    'export/import round-trips entries and replaces the account mirror',
    () async {
      await start();
      await emit({
        '@type': 'updateNewMessage',
        '@client_id': _clientA,
        'message': _message(1001, 1, text: 'keep me'),
      });
      final exported = await store.exportAccount();
      expect(exported['format'], MessageHistoryStore.exportFormat);
      expect((exported['entries'] as List).length, 1);

      // Wipe, then import the document back.
      store.clearAll();
      expect(store.entries, isEmpty);
      final restored = await store.importAccount(
        Map<String, Object?>.from(exported),
      );
      expect(restored, 1);
      expect(store.entry(1001, 1)?.text, 'keep me');
    },
  );

  test('import rejects foreign documents and keeps state intact', () async {
    await start();
    await emit({
      '@type': 'updateNewMessage',
      '@client_id': _clientA,
      'message': _message(1101, 1, text: 'present'),
    });
    expect(
      () => store.importAccount({'format': 'something-else', 'version': 1}),
      throwsA(isA<FormatException>()),
    );
    expect(store.entry(1101, 1)?.text, 'present');
  });

  test('a via-bot human group message does not flip its chat to bot', () async {
    await start();
    final settings = MessageHistorySettings.shared;
    settings.setRecordGroups(true);
    settings.setRecordBots(false);
    const groupChat = -1009998887770;
    await emit({
      '@type': 'updateNewMessage',
      '@client_id': _clientA,
      'message': {
        ..._message(groupChat, 1),
        'via_bot_user_id': '123',
        'reply_markup': {
          '@type': 'replyMarkupInlineKeyboard',
          'rows': const [],
        },
      },
    });
    // Group dim on → recorded: the sniff must not have treated it as a bot.
    expect(store.entries.map((e) => e.chatId), [groupChat]);
  });

  test('excluded chats import no rows', () async {
    await start();
    await emit({
      '@type': 'updateNewMessage',
      '@client_id': _clientA,
      'message': _message(1301, 1, text: 'x'),
    });
    // Hand-craft the document: the row PLUS the exclusion, the way a real
    // export from a device whose preference changed later would carry both.
    final exported = await store.exportAccount();
    store.excludeChat(1301);
    final document = Map<String, Object?>.from(exported)..['excluded'] = [1301];
    final restored = await store.importAccount(document);
    expect(restored, 0);
    expect(store.entry(1301, 1), isNull);
    // The exclusion itself imports as the account's preference.
    expect(store.excludedChats, contains(1301));
  });

  test('REG-1: a genuine bot posting inside a group still records', () async {
    store.startObserving();
    await pump();
    final settings = MessageHistorySettings.shared;
    settings.setRecordBots(false);
    const group = -1001234567890;
    await emit({
      '@type': 'updateNewMessage',
      '@client_id': _clientA,
      'message': _message(group, 1, isBot: true),
    });
    expect(store.entries, isNotEmpty);
    // A human message in the same group after the bot one records too —
    // the bot post must not have flipped the chat's gate.
    await emit({
      '@type': 'updateNewMessage',
      '@client_id': _clientA,
      'message': _message(group, 2),
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
        'message': _message(601, 1),
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

  test('REG-1: export view passes bytes to saveFile (source scan)', () async {
    // The widget lives behind an SAF flow we cannot drive headless; assert
    // the source contract instead: the call site forwards `bytes:` and does
    // not write the returned path.
    final source = File(
      'lib/settings/message_history_transfer_view.dart',
    ).readAsStringSync();
    expect(source, contains('bytes: encodedBytes'));
    expect(
      source,
      isNot(contains('File(destination).writeAsString')),
      reason: 'the plugin owns the write on Android SAF paths',
    );
  });

  test('REG-4a: rows of an excluded chat never load back from disk', () async {
    const chat = -1001234567891;
    // Simulate: entries persisted, exclusion written to prefs (immediate),
    // then the process died inside the entry-persist debounce window.
    final persistedStore = MessageHistoryStore.forTesting();
    persistedStore.fileDir = dir;
    persistedStore.updateSource = (_) => const Stream.empty();
    persistedStore.activeSlotChangeSource = () => const Stream<int>.empty();
    persistedStore.accountUserIdResolver = _StubResolver({_clientA: _accountA});
    persistedStore.activeClientIdProvider = () => _clientA;
    final prefs = await SharedPreferences.getInstance();
    persistedStore.initialize(prefs);
    persistedStore.debugSetActiveAccount(_accountA);
    persistedStore.debugSeed([
      const MessageHistoryEntry(
        accountUserId: _accountA,
        chatId: chat,
        messageId: 5,
        senderId: 42,
        date: 1,
        text: 'ghost-food',
        kindKey: 'historyKindText',
        state: MessageHistoryState.deleted,
        deletedAt: 123,
        events: [],
      ),
    ]);
    await persistedStore.persistNowForTesting();
    persistedStore.dispose();

    // Fresh boot: the exclusion is already in prefs, the file still holds
    // the chat's rows.
    final prefs2 = await SharedPreferences.getInstance();
    await prefs2.setStringList('$_prefsKeyPrefixProbe$_accountA', ['$chat']);
    final rebooted = MessageHistoryStore.forTesting();
    rebooted.fileDir = dir;
    rebooted.updateSource = (_) => const Stream.empty();
    rebooted.activeSlotChangeSource = () => const Stream<int>.empty();
    rebooted.accountUserIdResolver = _StubResolver({_clientA: _accountA});
    rebooted.activeClientIdProvider = () => _clientA;
    rebooted.initialize(prefs2);
    rebooted.debugSetActiveAccount(_accountA);
    await rebooted.ensureLoaded();
    expect(
      rebooted.entries.where((e) => e.chatId == chat),
      isEmpty,
      reason: 'excluded chat rows must not resurrect on reboot',
    );
    expect(
      rebooted.deletedEntriesFor(_accountA, chat),
      isEmpty,
      reason: 'excluded chat owes no ghosts',
    );
    rebooted.dispose();
  });

  test('REG-4b: deletedEntriesFor defends an excluded chat', () async {
    const chat = -1001234567892;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('$_prefsKeyPrefixProbe$_accountA', ['$chat']);
    // initialize() already ran in setUp with empty prefs; re-run with the
    // exclusion present so it lands in _excludedChatsByAccount.
    store.initialize(prefs);
    store.debugSeed([
      const MessageHistoryEntry(
        accountUserId: _accountA,
        chatId: chat,
        messageId: 7,
        senderId: 42,
        date: 1,
        text: 'stale',
        kindKey: 'historyKindText',
        state: MessageHistoryState.deleted,
        deletedAt: 123,
        events: [],
      ),
    ]);
    expect(store.deletedEntriesFor(_accountA, chat), isEmpty);
  });
}

// The store's prefs key prefix is private; mirror it for the test only.
const _prefsKeyPrefixProbe = 'messageHistory.excludedChats.v2.';
