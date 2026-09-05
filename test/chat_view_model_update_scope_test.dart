import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/settings/keyword_blocker.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chatId = 42;
const _firstMessageId = 100000;

List<ChatMessage> _messages(int count) => [
  for (var index = 0; index < count; index++)
    ChatMessage(
      id: _firstMessageId + index,
      chatId: _chatId,
      isOutgoing: false,
      text: 'message $index',
      date: index + 1,
      senderId: 9000 + index,
    ),
];

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

  for (final messageCount in const [500, 5000]) {
    test(
      'targeted updates avoid transcript scans with $messageCount messages',
      () {
        final vm = ChatViewModel(
          chatId: _chatId,
          title: 'Test',
          markReadOnOpen: false,
          sessionMessages: _messages(messageCount),
        );
        addTearDown(vm.dispose);
        vm.primeMessageIndexesForTesting();
        vm.resetTranscriptScanVisitsForTesting();

        final targetId = _firstMessageId + messageCount ~/ 2;
        final siblingId = targetId + 1;
        final targetRevision = vm.messageRevisionListenable(targetId);
        final siblingRevision = vm.messageRevisionListenable(siblingId);
        final transcript = vm.messages;
        var modelNotifications = 0;
        vm.addListener(() => modelNotifications++);

        void expectLocalizedUpdate(
          Map<String, dynamic> update, {
          required int previousTargetRevision,
          required int previousComposerRevision,
          required int previousModelNotifications,
        }) {
          final previousFullViewRevision = vm.fullViewRevision;
          final previousSiblingRevision = siblingRevision.value;

          vm.applyLiveUpdateForTesting(update);

          expect(targetRevision.value, previousTargetRevision + 1);
          expect(siblingRevision.value, previousSiblingRevision);
          expect(vm.composerRevision, previousComposerRevision + 1);
          expect(vm.fullViewRevision, previousFullViewRevision);
          expect(modelNotifications, previousModelNotifications + 1);
          expect(vm.messages, same(transcript));
          expect(vm.transcriptScanVisitsForTesting, 0);
          expect(
            chatViewRequiresFullSync(
              previousRevision: previousFullViewRevision,
              nextRevision: vm.fullViewRevision,
            ),
            isFalse,
          );
        }

        expectLocalizedUpdate(
          {
            '@type': 'updateMessageEdited',
            'chat_id': _chatId,
            'message_id': targetId,
            'edit_date': 123,
          },
          previousTargetRevision: targetRevision.value,
          previousComposerRevision: vm.composerRevision,
          previousModelNotifications: modelNotifications,
        );
        expectLocalizedUpdate(
          {
            '@type': 'updateMessageInteractionInfo',
            'chat_id': _chatId,
            'message_id': targetId,
            'interaction_info': {
              '@type': 'messageInteractionInfo',
              'view_count': 5,
              'forward_count': 1,
            },
          },
          previousTargetRevision: targetRevision.value,
          previousComposerRevision: vm.composerRevision,
          previousModelNotifications: modelNotifications,
        );
        final targetRevisionBeforeContent = targetRevision.value;
        final siblingRevisionBeforeContent = siblingRevision.value;
        final composerRevisionBeforeContent = vm.composerRevision;
        final fullViewRevisionBeforeContent = vm.fullViewRevision;
        final modelNotificationsBeforeContent = modelNotifications;
        vm.applyLiveUpdateForTesting({
          '@type': 'updateMessageContent',
          'chat_id': _chatId,
          'message_id': targetId,
          'new_content': _textContent('edited body'),
        });

        expect(vm.messages[messageCount ~/ 2].text, 'edited body');
        expect(targetRevision.value, targetRevisionBeforeContent + 1);
        expect(siblingRevision.value, siblingRevisionBeforeContent);
        expect(vm.composerRevision, composerRevisionBeforeContent + 1);
        expect(vm.fullViewRevision, fullViewRevisionBeforeContent + 1);
        expect(modelNotifications, modelNotificationsBeforeContent + 1);
        expect(vm.messages, same(transcript));
        expect(vm.transcriptScanVisitsForTesting, 0);
        expect(
          chatViewRequiresFullSync(
            previousRevision: fullViewRevisionBeforeContent,
            nextRevision: vm.fullViewRevision,
          ),
          isTrue,
        );
      },
    );
  }

  test('header and irrelevant updates bypass the full chat sync', () {
    final vm = ChatViewModel(
      chatId: _chatId,
      title: 'Test',
      markReadOnOpen: false,
    );
    addTearDown(vm.dispose);
    vm.resetTranscriptScanVisitsForTesting();
    final headerRevision = vm.headerRevisionListenable;
    var headerNotifications = 0;
    var modelNotifications = 0;
    headerRevision.addListener(() => headerNotifications++);
    vm.addListener(() => modelNotifications++);
    final initialComposerRevision = vm.composerRevision;
    final initialFullViewRevision = vm.fullViewRevision;

    final typingUpdate = <String, dynamic>{
      '@type': 'updateChatAction',
      'chat_id': _chatId,
      'sender_id': {'@type': 'messageSenderUser', 'user_id': 9001},
      'action': {'@type': 'chatActionTyping'},
    };
    vm.applyLiveUpdateForTesting(typingUpdate);

    expect(headerNotifications, 1);
    expect(modelNotifications, 1);
    expect(vm.composerRevision, initialComposerRevision);
    expect(vm.fullViewRevision, initialFullViewRevision);
    expect(vm.transcriptScanVisitsForTesting, 0);
    expect(
      chatViewRequiresFullSync(
        previousRevision: initialFullViewRevision,
        nextRevision: vm.fullViewRevision,
      ),
      isFalse,
    );

    // TDLib repeats an unchanged typing action while it remains active.
    vm.applyLiveUpdateForTesting(typingUpdate);
    vm.applyLiveUpdateForTesting({
      '@type': 'updateFile',
      'file': {'@type': 'file', 'id': 7},
    });
    vm.applyLiveUpdateForTesting({...typingUpdate, 'chat_id': _chatId + 1});

    expect(headerNotifications, 1);
    expect(modelNotifications, 1);
    expect(vm.composerRevision, initialComposerRevision);
    expect(vm.fullViewRevision, initialFullViewRevision);
    expect(vm.transcriptScanVisitsForTesting, 0);
  });

  test('an offscreen localized update does not allocate a bubble notifier', () {
    final vm = ChatViewModel(
      chatId: _chatId,
      title: 'Test',
      markReadOnOpen: false,
      sessionMessages: _messages(1),
    );
    addTearDown(vm.dispose);
    vm.primeMessageIndexesForTesting();
    vm.resetTranscriptScanVisitsForTesting();

    vm.applyLiveUpdateForTesting({
      '@type': 'updateMessageInteractionInfo',
      'chat_id': _chatId,
      'message_id': _firstMessageId,
      'interaction_info': {'@type': 'messageInteractionInfo', 'view_count': 1},
    });

    expect(vm.messageRevisionNotifierCountForTesting, 0);
    expect(vm.fullViewRevision, 0);
    expect(vm.transcriptScanVisitsForTesting, 0);
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

  test('structural notifications still request a full chat sync', () {
    final vm = ChatViewModel(
      chatId: _chatId,
      title: 'Test',
      markReadOnOpen: false,
    );
    addTearDown(vm.dispose);
    final previousFullViewRevision = vm.fullViewRevision;

    vm.applyLiveUpdateForTesting({
      '@type': 'updateChatReadInbox',
      'chat_id': _chatId,
      'last_read_inbox_message_id': 7,
      'unread_count': 2,
    });

    expect(
      chatViewRequiresFullSync(
        previousRevision: previousFullViewRevision,
        nextRevision: vm.fullViewRevision,
      ),
      isTrue,
    );
  });
}
