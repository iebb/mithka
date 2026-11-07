//
//  Ghost transcript tests: deleted mirror entries fold into the chat
//  transcript as translucent ghost bubbles, behind the runtime render
//  switch (default OFF) and the compile-time feature gate.
//

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/history/message_history_settings.dart';
import 'package:mithka/history/message_history_store.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabled = allowTelegramTosViolations;

const _accountUserId = 7001;

MessageHistoryEntry _deletedEntry(
  int messageId, {
  String text = 'vanished',
  int senderId = 42,
}) => MessageHistoryEntry(
  accountUserId: _accountUserId,
  chatId: 11,
  messageId: messageId,
  senderId: senderId,
  date: 1700000000 + messageId,
  text: text,
  kindKey: '',
  state: MessageHistoryState.deleted,
  deletedAt: 1700009999,
  events: const [],
);

void main() {
  if (!_enabled) return;

  late MessageHistoryStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    store = MessageHistoryStore.forTesting();
    store.debugSetActiveAccount(_accountUserId);
    ChatViewModel.accountSummaryProvider = (_) => null;
  });

  tearDown(() {
    ChatViewModel.accountSummaryProvider = null;
    final settings = MessageHistorySettings.shared;
    settings.setRenderGhosts(false);
    settings.setRecordDeleted(false);
    settings.setRecordEdits(false);
    store.dispose();
  });

  ChatViewModel makeViewModel() => ChatViewModel(
    chatId: 11,
    title: 'test',
    markReadOnOpen: false,
    historyStoreOverride: store,
  );

  test('ghosts stay out while the render switch is off (the default)', () {
    store.debugSeed([_deletedEntry(100)]);
    final vm = makeViewModel();
    addTearDown(vm.dispose);
    vm.debugRebuildTranscriptForTesting();
    expect(vm.messages.where((m) => m.mirrorEntry != null), isEmpty);
  });

  test('deleted entries fold into the transcript when ghosts are on', () {
    MessageHistorySettings.shared.setRenderGhosts(true);
    ChatViewModel.accountSummaryProvider = (_) => AccountSummary(
      slot: 0,
      userId: _accountUserId,
      name: 'me',
      phone: '+1',
    );
    store.debugSeed([
      _deletedEntry(100),
      _deletedEntry(300, text: 'later ghost'),
      // A live message's kept copy is NOT a ghost — the bubble renders it.
      _deletedEntry(200).copyWith(state: MessageHistoryState.active),
    ]);
    final vm = makeViewModel();
    addTearDown(vm.dispose);
    vm.debugRebuildTranscriptForTesting();
    final ghosts = vm.messages.where((m) => m.mirrorEntry != null).toList();
    expect(ghosts.map((m) => m.id), [100, 300]);
    // The ghost carries the kept text and marks the bubble layer.
    expect(ghosts.first.text, 'vanished');
    expect(ghosts.first.contentType, 'mithkaGhost');
    // Ghosts join only `messages` — the id indexes stay clean.
    expect(vm.debugAllMessageIdsForTesting(), isEmpty);
  });

  test('a ghost whose message still loads as live is not duplicated', () {
    MessageHistorySettings.shared.setRenderGhosts(true);
    ChatViewModel.accountSummaryProvider = (_) => AccountSummary(
      slot: 0,
      userId: _accountUserId,
      name: 'me',
      phone: '+1',
    );
    store.debugSeed([_deletedEntry(100)]);
    final vm = makeViewModel();
    addTearDown(vm.dispose);
    vm.debugMergeMessagesForTesting([
      ChatMessage(id: 100, isOutgoing: false, text: 'back', date: 1700000000),
    ]);
    vm.debugRebuildTranscriptForTesting();
    expect(vm.messages.where((m) => m.mirrorEntry != null), isEmpty);
    expect(vm.messages.map((m) => m.id), contains(100));
  });

  test('turning the switch off removes the ghosts again', () {
    final settings = MessageHistorySettings.shared;
    settings.setRenderGhosts(true);
    ChatViewModel.accountSummaryProvider = (_) => AccountSummary(
      slot: 0,
      userId: _accountUserId,
      name: 'me',
      phone: '+1',
    );
    store.debugSeed([_deletedEntry(100)]);
    final vm = makeViewModel();
    addTearDown(vm.dispose);
    vm.debugRebuildTranscriptForTesting();
    expect(vm.messages.where((m) => m.mirrorEntry != null), isNotEmpty);
    settings.setRenderGhosts(false);
    vm.debugRebuildTranscriptForTesting();
    expect(vm.messages.where((m) => m.mirrorEntry != null), isEmpty);
  });
}
