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
}
