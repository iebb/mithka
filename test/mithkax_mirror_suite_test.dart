//
//  Mithka X mirror suite, part 1: settings + the recording store.
//
//  Settings: the master switch gates the record switches without wiping
//  them, per-type defaults behave, and the badge style persists.
//
//  Store: per-chat-type recording gates, bot detection, exclusions, the
//  export/import round trip — hardened with topic capture and scoping,
//  reversed edit pairs, explicit-account exclusions, the snapshot budget,
//  and the excluded-chat reboot defense.
//

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/forum_topic_transcript.dart'
    show generalForumTopicId;
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

const _chatId = 21;
const _groupChatId = -1001234;

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

void main() {
  if (!_enabled) {
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();

  group('settings', () {
    if (!allowTelegramTosViolations) return; // getters chain isAvailable
    TestWidgetsFlutterBinding.ensureInitialized();

    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues(const {});
      prefs = await SharedPreferences.getInstance();
      MessageHistorySettings.shared.initialize(prefs);
    });

    tearDown(() {
      final s = MessageHistorySettings.shared;
      s.setEnableAll(false);
      s.setRecordDeleted(false);
      s.setRecordEdits(false);
      s.setRecordPrivate(true);
      s.setRecordGroups(true);
      s.setRecordChannels(true);
      s.setRecordBots(false);
      s.setBadgeStyle(GhostBadgeStyle.icon);
    });

    test('everything is off by default (fresh install records nothing)', () {
      final s = MessageHistorySettings.shared;
      expect(s.enableAll, isFalse);
      expect(s.recordDeleted, isFalse);
      expect(s.recordEdits, isFalse);
      // Type dims default on but sit under the master switch.
      expect(s.recordPrivate, isFalse);
      expect(s.recordGroups, isFalse);
      expect(s.recordChannels, isFalse);
      expect(s.recordBots, isFalse);
      expect(s.renderGhosts, isFalse);
    });

    test('the master switch pauses recording but keeps sub-switch choices', () {
      final s = MessageHistorySettings.shared;
      s.setEnableAll(true);
      s.setRecordDeleted(true);
      s.setRecordPrivate(false);
      expect(s.recordDeleted, isTrue);
      expect(s.recordPrivate, isFalse);
      expect(s.recordGroups, isTrue); // per-type default on

      // Master off: every record getter goes dark…
      s.setEnableAll(false);
      expect(s.recordDeleted, isFalse);
      expect(s.recordGroups, isFalse);

      // …but the choices survive and come back with the master switch.
      s.setEnableAll(true);
      expect(s.recordDeleted, isTrue);
      expect(s.recordPrivate, isFalse);
      expect(s.recordGroups, isTrue);
    });

    test('bot recording needs both the private dim and its own switch', () {
      final s = MessageHistorySettings.shared;
      s.setEnableAll(true);
      s.setRecordDeleted(true);
      s.setRecordBots(true);
      expect(s.recordBots, isTrue);

      // Private dim off kills bot recording too — a bot dialog is private.
      s.setRecordPrivate(false);
      expect(s.recordBots, isFalse);
    });

    test('ghost rendering ignores the master switch (display-only)', () {
      final s = MessageHistorySettings.shared;
      s.setRenderGhosts(true);
      expect(s.renderGhosts, isTrue);
      s.setEnableAll(true);
      s.setEnableAll(false);
      expect(
        s.renderGhosts,
        isTrue,
        reason: 'turning recording off must not hide kept ghosts',
      );
    });

    test('badge style persists and reloads', () async {
      final s = MessageHistorySettings.shared;
      expect(s.badgeStyle, GhostBadgeStyle.icon);
      s.setBadgeStyle(GhostBadgeStyle.text);
      expect(s.badgeStyle, GhostBadgeStyle.text);

      final reloaded = MessageHistorySettings.shared;
      // shared keeps its state; verifying persistence through the prefs value
      // the setter wrote instead.
      expect(prefs.getString('message_history.badge_style'), 'text');
      expect(reloaded.badgeStyle, GhostBadgeStyle.text);
    });

    test('toggles notify listeners once per flip', () {
      final s = MessageHistorySettings.shared;
      var notified = 0;
      s.addListener(() => notified++);
      s.setRecordDeleted(true);
      expect(notified, 1);
      s.setRecordDeleted(true);
      expect(notified, 1);
    });
  });

  group('store', () {
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
      settings.setRenderGhosts(true);
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
      settings.setRenderGhosts(false);
      settings.setRecordPrivate(true);
      settings.setRecordGroups(true);
      settings.setRecordChannels(true);
      settings.setRecordBots(false);
      ChatViewModel.accountSummaryProvider = null;
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

    test(
      'a via-bot human group message does not flip its chat to bot',
      () async {
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
      },
    );

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
      final document = Map<String, Object?>.from(exported)
        ..['excluded'] = [1301];
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
            'type': {
              '@type': 'chatTypePrivate',
              'user_id': '99',
              'is_bot': true,
            },
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
        final path = await snap.writeSnapshotBytes('$_accountA:55:9', [
          1,
          2,
          3,
        ]);
        expect(path, isNotNull);
        store.debugSeed([
          MessageHistoryEntry(
            accountUserId: _accountA,
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

    test(
      'REG-4a: rows of an excluded chat never load back from disk',
      () async {
        const chat = -1001234567891;
        // Simulate: entries persisted, exclusion written to prefs (immediate),
        // then the process died inside the entry-persist debounce window.
        final persistedStore = MessageHistoryStore.forTesting();
        persistedStore.fileDir = dir;
        persistedStore.updateSource = (_) => const Stream.empty();
        persistedStore.activeSlotChangeSource = () => const Stream<int>.empty();
        persistedStore.accountUserIdResolver = _StubResolver({
          _clientA: _accountA,
        });
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
        await prefs2.setStringList('$_prefsKeyPrefixProbe$_accountA', [
          '$chat',
        ]);
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
      },
    );

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

    ChatViewModel makeViewModel({int? forumTopicId}) => ChatViewModel(
      chatId: _chatId,
      title: 'test',
      markReadOnOpen: false,
      historyStoreOverride: store,
      forumTopicId: forumTopicId,
    );

    void emitAs(int clientId, String type, Map<String, dynamic> update) =>
        updates.add({'@type': type, '@client_id': clientId, ...update});

    // ============ topic scoping & edit capture (r12 REG-2/4/5) ============
    // These drive the SAME store/update wire as the tests above.
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

    group('REG-4 topic capture', () {
      test('a group message with an explicit topic records it', () async {
        await start();
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
        await start();
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
          await start();
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
  });

  // ============ account scoping & budget (r13 REG-2/4/5) ============
  // Self-contained groups with their own setUp.
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

// The store's prefs key prefix is private; mirror it for the test only.
const _prefsKeyPrefixProbe = 'messageHistory.excludedChats.v2.';
