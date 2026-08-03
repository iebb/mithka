import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  test('reply selection does not insert a sender mention into the draft', () {
    final viewModel = ChatViewModel(
      chatId: 1,
      title: 'Group',
      markReadOnOpen: false,
    )..isGroup = true;
    addTearDown(viewModel.dispose);
    final message = ChatMessage(
      id: 42,
      isOutgoing: false,
      text: 'Original message',
      date: 1,
      senderId: 7,
      senderName: 'inlinebot',
      contentType: 'messageText',
    );

    viewModel.setReply(message);

    expect(viewModel.replyTo, same(message));
    expect(viewModel.draft, isEmpty);
  });

  test(
    'inline edit preloads formatting and cancel restores draft and reply',
    () {
      final viewModel = ChatViewModel(
        chatId: 1,
        title: 'Group',
        markReadOnOpen: false,
      );
      addTearDown(viewModel.dispose);
      final reply = ChatMessage(
        id: 7,
        isOutgoing: false,
        text: 'Reply target',
        date: 1,
        contentType: 'messageText',
      );
      final edited = ChatMessage(
        id: 42,
        isOutgoing: true,
        text: 'Original message',
        date: 2,
        contentType: 'messageText',
        textEntities: const [
          MessageTextEntity(offset: 0, length: 8, type: 'textEntityTypeBold'),
        ],
      );
      viewModel.setDraft('Unfinished draft');
      viewModel.setReply(reply);

      viewModel.beginMessageEdit(edited);

      expect(viewModel.editingMessage, same(edited));
      expect(viewModel.replyTo, isNull);
      expect(viewModel.draft, 'Original message');
      expect(viewModel.composerDraftEntities.single['type'], {
        '@type': 'textEntityTypeBold',
      });

      viewModel.setDraft('Changed inline text');
      viewModel.cancelMessageEdit();

      expect(viewModel.editingMessage, isNull);
      expect(viewModel.draft, 'Unfinished draft');
      expect(viewModel.replyTo, same(reply));
    },
  );
}
