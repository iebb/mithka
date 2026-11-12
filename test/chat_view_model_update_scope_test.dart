import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/settings/keyword_blocker.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chatId = 42;

Map<String, dynamic> _textContent(String text) => {
  '@type': 'messageText',
  'text': {'@type': 'formattedText', 'text': text, 'entities': []},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    KeywordBlocker.shared.initialize(await SharedPreferences.getInstance());
  });

  setUp(() {
    KeywordBlocker.shared.replaceAll(const []);
  });

  test('live media updates apply and clear spoiler before refresh', () {
    final message = ChatMessage(
      id: 1,
      chatId: _chatId,
      isOutgoing: true,
      text: '',
      date: 1,
      contentType: 'messageVideo',
      isSending: true,
    );
    final vm = ChatViewModel(
      chatId: _chatId,
      title: 'Test',
      markReadOnOpen: false,
      sessionMessages: [message],
    );
    addTearDown(vm.dispose);
    for (final spoiler in [true, false]) {
      vm.applyLiveUpdateForTesting({
        '@type': 'updateMessageContent',
        'chat_id': _chatId,
        'message_id': 1,
        'new_content': {'@type': 'messageVideo', 'has_spoiler': spoiler},
      });
      expect(message.hasSpoiler, spoiler);
    }
  });

  test('text rules retain full filtering when edited content can hide', () {
    KeywordBlocker.shared.replaceAll(const ['blocked']);
    final vm = ChatViewModel(
      chatId: _chatId,
      title: 'Test',
      markReadOnOpen: false,
      sessionMessages: [
        ChatMessage(
          id: 1,
          chatId: _chatId,
          isOutgoing: false,
          text: 'visible',
          date: 1,
        ),
        ChatMessage(
          id: 2,
          chatId: _chatId,
          isOutgoing: false,
          text: 'also visible',
          date: 2,
        ),
      ],
    );
    addTearDown(() {
      vm.dispose();
      KeywordBlocker.shared.replaceAll(const []);
    });
    vm.primeMessageIndexesForTesting();
    vm.resetTranscriptScanVisitsForTesting();

    vm.applyLiveUpdateForTesting({
      '@type': 'updateMessageContent',
      'chat_id': _chatId,
      'message_id': 1,
      'new_content': _textContent('now blocked'),
    });

    expect(vm.messages.map((message) => message.id), [2]);
    expect(vm.transcriptScanVisitsForTesting, 2);
  });

  test('a transcript on its way out ignores the sync its own exit requests', () {
    final vm = ChatViewModel(
      chatId: _chatId,
      title: 'Test',
      markReadOnOpen: false,
    );
    addTearDown(vm.dispose);
    final previousFullViewRevision = vm.fullViewRevision;

    expect(
      chatViewSyncsModelNotification(
        viewTickerEnabled: true,
        exitStatePrepared: false,
      ),
      isTrue,
    );

    // Marking the conversation read on the way out emits this local update, so
    // it arrives while the route is still animating and the transcript is still
    // mounted.
    vm.applyLiveUpdateForTesting({
      '@type': 'updateChatReadInbox',
      'chat_id': _chatId,
      'last_read_inbox_message_id': 7,
      'unread_count': 0,
    });

    expect(
      chatViewRequiresFullSync(
        previousRevision: previousFullViewRevision,
        nextRevision: vm.fullViewRevision,
      ),
      isTrue,
    );
    expect(
      chatViewSyncsModelNotification(
        viewTickerEnabled: true,
        exitStatePrepared: true,
      ),
      isFalse,
    );
    // A covered transcript defers instead, so it still owes the sync once the
    // surface above it is gone.
    expect(
      chatViewSyncsModelNotification(
        viewTickerEnabled: false,
        exitStatePrepared: false,
      ),
      isFalse,
    );
  });
}
