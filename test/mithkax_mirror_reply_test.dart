//
//  Reply-to-deleted → quote: when a reply's target is gone from the live
//  transcript but the mirror holds a kept copy, the reply anchor fills from
//  the mirror (Telegram §1.4, self-build gated).
//

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/history/message_history_store.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabled = allowTelegramTosViolations;

const _accountUserId = 9101;
const _chatId = 21;

MessageHistoryEntry _keptEntry(
  int messageId, {
  String text = 'the deleted original',
  int senderId = 42,
}) => MessageHistoryEntry(
  accountUserId: _accountUserId,
  chatId: _chatId,
  messageId: messageId,
  senderId: senderId,
  date: 1700000000 + messageId,
  text: text,
  kindKey: '',
  state: MessageHistoryState.deleted,
  deletedAt: 1700009999,
  events: const [],
);

ChatMessage _reply(int id, int replyToId) => ChatMessage(
  id: id,
  isOutgoing: false,
  text: 'the reply',
  date: 1700000500,
  chatId: _chatId,
  senderId: 7,
)..replyToMessageId = replyToId;

void main() {
  if (!_enabled) {
    return;
  }

  late MessageHistoryStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    store = MessageHistoryStore.forTesting();
    store.debugSetActiveAccount(_accountUserId);
    ChatViewModel.accountSummaryProvider = (_) => AccountSummary(
      slot: 0,
      userId: _accountUserId,
      name: 'me',
      phone: '+1',
    );
  });

  tearDown(() {
    ChatViewModel.accountSummaryProvider = null;
    store.dispose();
  });

  ChatViewModel makeViewModel() => ChatViewModel(
    chatId: _chatId,
    title: 'test',
    markReadOnOpen: false,
    historyStoreOverride: store,
  );

  test('a deleted reply target fills its anchor from the mirror', () {
    store.debugSeed([_keptEntry(100)]);
    final vm = makeViewModel();
    addTearDown(vm.dispose);
    vm.debugMergeMessagesForTesting([_reply(101, 100)]);
    final reply = vm.messages.firstWhere((m) => m.id == 101);
    expect(reply.replyToPreview, 'the deleted original');
    expect(reply.replyToDate, 1700000100);
  });

  test('a live target in the transcript wins over the mirror', () {
    store.debugSeed([_keptEntry(100, text: 'mirror copy')]);
    final live = ChatMessage(
      id: 100,
      isOutgoing: false,
      text: 'the live original',
      date: 1700000100,
      chatId: _chatId,
      senderId: 42,
    );
    final vm = makeViewModel();
    addTearDown(vm.dispose);
    vm.debugMergeMessagesForTesting([live, _reply(101, 100)]);
    final reply = vm.messages.firstWhere((m) => m.id == 101);
    expect(reply.replyToPreview, 'the live original');
  });

  test('no mirror copy leaves the reply to the normal TDLib path', () {
    final vm = makeViewModel();
    addTearDown(vm.dispose);
    vm.debugMergeMessagesForTesting([_reply(101, 100)]);
    final reply = vm.messages.firstWhere((m) => m.id == 101);
    expect(reply.replyToPreview, isNull);
  });

  test('a media-only kept copy fills the kind label, not empty text', () {
    store.debugSeed([
      _keptEntry(100, text: '').copyWith(kindKey: 'historyKindPhoto'),
    ]);
    final vm = makeViewModel();
    addTearDown(vm.dispose);
    vm.debugMergeMessagesForTesting([_reply(101, 100)]);
    final reply = vm.messages.firstWhere((m) => m.id == 101);
    // Localized through AppStrings (ambient locale, no BuildContext).
    expect(reply.replyToPreview, AppStrings.t(AppStringKeys.historyKindPhoto));
  });
}
