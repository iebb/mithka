//
//  r10: ghost bubbles keep attribution and never render empty.
//  A group ghost carries its author's name (fold-time cache lookup and the
//  sender-resolution patch); a media-only ghost shows the localized kind
//  label instead of an empty bubble; a self-sent ghost keeps the account's
//  own name.
//
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/history/message_history_settings.dart';
import 'package:mithka/history/message_history_store.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabled = allowTelegramTosViolations;
const _accountUserId = 9101;
const _chatId = 21;

void main() {
  if (!_enabled) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  late MessageHistoryStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    store = MessageHistoryStore.forTesting();
    store.updateSource = (_) => const Stream<Map<String, dynamic>>.empty();
    store.activeSlotChangeSource = () => const Stream<int>.empty();
    store.activeClientIdProvider = () => 1;
    ChatViewModel.accountSummaryProvider = (_) => AccountSummary(
      slot: 0,
      userId: _accountUserId,
      name: 'me',
      phone: '+1',
    );
    final settings = MessageHistorySettings.shared;
    settings.setRenderGhosts(true);
  });

  tearDown(() {
    ChatViewModel.accountSummaryProvider = null;
    final settings = MessageHistorySettings.shared;
    settings.setRenderGhosts(false);
    store.dispose();
  });

  ChatViewModel makeViewModel() => ChatViewModel(
    chatId: _chatId,
    title: 'test',
    markReadOnOpen: false,
    historyStoreOverride: store,
  );

  test('a self-sent ghost carries the account name', () {
    store.debugSeed([
      const MessageHistoryEntry(
        accountUserId: _accountUserId,
        chatId: _chatId,
        messageId: 100,
        senderId: _accountUserId,
        date: 1,
        text: 'mine',
        kindKey: '',
        state: MessageHistoryState.deleted,
        deletedAt: 2,
        events: [],
      ),
    ]);
    final vm = makeViewModel();
    addTearDown(vm.dispose);
    vm.debugRebuildTranscriptForTesting();
    final ghost = vm.messages.firstWhere((m) => m.mirrorEntry != null);
    expect(ghost.isOutgoing, isTrue);
    expect(ghost.senderName, 'Me');
  });

  test('a media-only ghost shows the localized kind label', () {
    store.debugSeed([
      const MessageHistoryEntry(
        accountUserId: _accountUserId,
        chatId: _chatId,
        messageId: 101,
        senderId: 42,
        date: 1,
        text: '',
        kindKey: 'historyKindPhoto',
        state: MessageHistoryState.deleted,
        deletedAt: 2,
        events: [],
      ),
    ]);
    final vm = makeViewModel();
    addTearDown(vm.dispose);
    vm.debugRebuildTranscriptForTesting();
    final ghost = vm.messages.firstWhere((m) => m.mirrorEntry != null);
    expect(
      ghost.text,
      AppStrings.t(AppStringKeys.historyKindPhoto),
      reason: 'an empty media ghost must not render as an empty bubble',
    );
  });
}
