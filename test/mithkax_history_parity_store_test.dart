//
//  Exteraless-parity store tests: per-chat-type recording gates, bot
//  detection, Spy-style read-time stamps, and the export/import round trip.
//

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/history/message_history_settings.dart';
import 'package:mithka/history/message_history_store.dart';
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
    settings.setRecordReadTimes(false);
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

  test('updateChatReadOutbox stamps kept copies with a read time', () async {
    await start();
    final settings = MessageHistorySettings.shared;
    settings.setRecordReadTimes(true);
    await emit({
      '@type': 'updateNewMessage',
      '@client_id': _clientA,
      'message': _message(801, 10, senderId: _accountA),
    });
    await emit({
      '@type': 'updateNewMessage',
      '@client_id': _clientA,
      'message': _message(801, 11, senderId: _accountA),
    });
    expect(store.entry(801, 10)?.readAt, 0);

    await emit({
      '@type': 'updateChatReadOutbox',
      '@client_id': _clientA,
      'chat_id': '801',
      'last_read_outbox_message_id': 10,
    });
    expect(store.entry(801, 10)?.readAt, greaterThan(0));
    expect(
      store.entry(801, 11)?.readAt,
      0,
      reason: 'beyond the cursor it stays unread',
    );

    // The earliest crossing wins: a later cursor does not restamp.
    final first = store.entry(801, 10)!.readAt;
    await emit({
      '@type': 'updateChatReadOutbox',
      '@client_id': _clientA,
      'chat_id': '801',
      'last_read_outbox_message_id': 11,
    });
    expect(store.entry(801, 10)?.readAt, first);
    expect(store.entry(801, 11)?.readAt, greaterThan(0));
  });

  test('read-time stamps respect the switch and survive persistence', () async {
    await start();
    final settings = MessageHistorySettings.shared;
    settings.setRecordReadTimes(false);
    await emit({
      '@type': 'updateNewMessage',
      '@client_id': _clientA,
      'message': _message(901, 1),
    });
    await emit({
      '@type': 'updateChatReadOutbox',
      '@client_id': _clientA,
      'chat_id': '901',
      'last_read_outbox_message_id': 1,
    });
    expect(store.entry(901, 1)?.readAt, 0, reason: 'switch off → no stamp');

    settings.setRecordReadTimes(true);
    await store.persistNowForTesting();
    final raw =
        jsonDecode(
              await File('${dir.path}/message-history.json').readAsString(),
            )
            as Map<String, dynamic>;
    final rows = (raw['entries'] as List)
        .map(MessageHistoryEntry.fromJson)
        .whereType<MessageHistoryEntry>()
        .toList();
    expect(rows.single.readAt, 0);
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

  test('an incoming kept copy never takes an outbox read stamp', () async {
    await start();
    final settings = MessageHistorySettings.shared;
    settings.setRecordReadTimes(true);
    // sender 42 is NOT the account — a kept INCOMING copy.
    await emit({
      '@type': 'updateNewMessage',
      '@client_id': _clientA,
      'message': _message(1201, 1),
    });
    await emit({
      '@type': 'updateChatReadOutbox',
      '@client_id': _clientA,
      'chat_id': '1201',
      'last_read_outbox_message_id': 5,
    });
    expect(store.entry(1201, 1)?.readAt, 0);
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
}
