//
//  r11 divergent-review regressions (full-audit fixes):
//  1) Android export must pass bytes to FilePicker.saveFile — the plugin
//     writes the file itself; the caller never touches the SAF path.
//  2) a revived message (same id as a folded ghost) entering through the
//     strictly-newest fast path must retire its ghost — no dual bubble.
//  3) AccountSummary caches the RAW server premium; the local-premium
//     overlay applies only at read time and AccountStore notifies on flips.
//  4) excludeChat rows on disk (stale persist window, process kill) never
//     load back, and deletedEntriesFor defends excluded chats.
//
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/history/message_history_settings.dart';
import 'package:mithka/history/message_history_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabled = allowTelegramTosViolations;
const _clientA = 911;
const _accountA = 7911;

class _R implements TosAccountUserIdResolver {
  @override
  Future<int?> resolve(int clientId) async => _accountA;
}

void main() {
  if (!_enabled) return;

  late Directory dir;
  late StreamController<Map<String, dynamic>> updates;
  late MessageHistoryStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mithkax-r11-reg');
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
    persistedStore.accountUserIdResolver = _R();
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
    rebooted.accountUserIdResolver = _R();
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
