import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  test('live attachment updates do not turn preview labels into captions', () {
    final attachmentContents = <Map<String, dynamic>>[
      {
        '@type': 'messagePhoto',
        'caption': {'@type': 'formattedText', 'text': ''},
      },
      {
        '@type': 'messageVideo',
        'caption': {'@type': 'formattedText', 'text': ''},
      },
      {
        '@type': 'messageAnimation',
        'caption': {'@type': 'formattedText', 'text': ''},
      },
      {
        '@type': 'messageAudio',
        'caption': {'@type': 'formattedText', 'text': ''},
      },
      {
        '@type': 'messageDocument',
        'caption': {'@type': 'formattedText', 'text': ''},
        'document': {'@type': 'document', 'file_name': 'report.pdf'},
      },
      {
        '@type': 'messageVoiceNote',
        'caption': {'@type': 'formattedText', 'text': ''},
      },
      {
        '@type': 'messagePaidMedia',
        'caption': {'@type': 'formattedText', 'text': ''},
      },
    ];

    for (final content in attachmentContents) {
      final pending = ChatMessage(
        id: 77,
        chatId: 42,
        isOutgoing: true,
        isSending: true,
        text: '',
        date: 1,
        contentType: content['@type'] as String,
      );
      final vm = ChatViewModel(
        chatId: 42,
        title: 'Test',
        markReadOnOpen: false,
        sessionMessages: [pending],
      );
      vm.applyLiveUpdateForTesting({
        '@type': 'updateMessageContent',
        'chat_id': 42,
        'message_id': 77,
        'new_content': content,
      });

      expect(
        vm.messages.single.text,
        isEmpty,
        reason: '${content['@type']} live transcript caption',
      );
      vm.dispose();
    }
  });
}
