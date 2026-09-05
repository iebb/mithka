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

  test('an edited attachment is re-read instead of merged in place', () {
    // The in-place merge keeps the previous attachment, so a message whose
    // media was replaced kept stale dimensions and a deleted thumbnail path.
    expect(
      mediaContentUpdateNeedsRefresh(
        contentType: 'messagePhoto',
        isSending: false,
      ),
      isTrue,
    );
    expect(
      mediaContentUpdateNeedsRefresh(
        contentType: 'messageVideo',
        isSending: false,
      ),
      isTrue,
    );
    expect(
      mediaContentUpdateNeedsRefresh(
        contentType: 'messageVideoNote',
        isSending: false,
      ),
      isTrue,
    );
  });

  test('an uploading video keeps its local source instead', () {
    expect(
      mediaContentUpdateNeedsRefresh(
        contentType: 'messageVideo',
        isSending: true,
      ),
      isFalse,
    );
  });

  test('a non-media content update needs no re-read', () {
    expect(
      mediaContentUpdateNeedsRefresh(
        contentType: 'messageText',
        isSending: false,
      ),
      isFalse,
    );
    expect(
      mediaContentUpdateNeedsRefresh(contentType: null, isSending: false),
      isFalse,
    );
  });

  test('live video update hydrates the outgoing preview media', () {
    final pending = ChatMessage(
      id: 77,
      chatId: 42,
      isOutgoing: true,
      isSending: true,
      text: '',
      date: 1,
      contentType: 'messageVideo',
      video: TdFileRef(id: 301, localPath: '/tmp/outgoing-video.mp4'),
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
      'new_content': {
        '@type': 'messageVideo',
        'caption': {'@type': 'formattedText', 'text': ''},
        'video': {
          '@type': 'video',
          'file_name': 'clip.webm',
          'mime_type': 'video/webm',
          'duration': 7,
          'width': 1080,
          'height': 1920,
          'thumbnail': {
            '@type': 'thumbnail',
            'file': {'@type': 'file', 'id': 401},
          },
          'video': {'@type': 'file', 'id': 402},
        },
      },
    });

    final updated = vm.messages.single;
    expect(updated.text, isEmpty);
    expect(updated.image?.id, 401);
    expect(updated.video?.id, 402);
    expect(updated.video?.localPath, '/tmp/outgoing-video.mp4');
    expect(updated.video?.fileName, 'clip.webm');
    expect(updated.video?.mimeType, 'video/webm');
    expect(updated.imageWidth, 1080);
    expect(updated.imageHeight, 1920);
    expect(updated.videoDuration, 7);

    vm.applyLiveUpdateForTesting({
      '@type': 'updateMessageSendSucceeded',
      'old_message_id': 77,
      'message': {
        '@type': 'message',
        'id': 88,
        'chat_id': 42,
        'is_outgoing': true,
        'date': 2,
        'content': {
          '@type': 'messageVideo',
          'caption': {'@type': 'formattedText', 'text': ''},
          'video': {
            '@type': 'video',
            'duration': 0,
            'width': 0,
            'height': 0,
            'video': {'@type': 'file', 'id': 502},
          },
        },
      },
    });

    final confirmed = vm.messages.single;
    expect(confirmed.id, 88);
    expect(confirmed.image?.id, 401);
    expect(confirmed.video?.id, 502);
    expect(confirmed.video?.localPath, '/tmp/outgoing-video.mp4');
    expect(confirmed.video?.fileName, 'clip.webm');
    expect(confirmed.video?.mimeType, 'video/webm');
    expect(confirmed.imageWidth, 1080);
    expect(confirmed.imageHeight, 1920);
    expect(confirmed.videoDuration, 7);
    vm.dispose();
  });

  test('send update chat id falls back to the nested TDLib message', () {
    expect(
      messageSendUpdateChatId({
        '@type': 'updateMessageSendFailed',
        'old_message_id': 77,
        'message': {'@type': 'message', 'id': 77, 'chat_id': 42},
      }),
      42,
    );
  });

  test('server acknowledgement settles the visual sending state', () {
    final pending = ChatMessage(
      id: 77,
      chatId: 42,
      isOutgoing: true,
      isSending: true,
      text: 'Sent',
      date: 1,
    );
    final vm = ChatViewModel(
      chatId: 42,
      title: 'Test',
      markReadOnOpen: false,
      sessionMessages: [pending],
    );
    final transcriptBeforeAcknowledgement = vm.messages;
    final fullViewRevisionBeforeAcknowledgement = vm.fullViewRevision;
    final composerRevisionBeforeAcknowledgement = vm.composerRevision;
    var bubbleRefreshes = 0;
    var unrelatedBubbleRefreshes = 0;
    vm.messageRevisionListenable(77).addListener(() => bubbleRefreshes++);
    vm
        .messageRevisionListenable(78)
        .addListener(() => unrelatedBubbleRefreshes++);

    vm.applyLiveUpdateForTesting({
      '@type': 'updateMessageSendAcknowledged',
      'chat_id': 42,
      'message_id': 77,
    });

    expect(vm.messages.single.isSending, isTrue);
    expect(vm.messages.single.isSendAcknowledged, isTrue);
    expect(vm.messages, same(transcriptBeforeAcknowledgement));
    expect(vm.fullViewRevision, fullViewRevisionBeforeAcknowledgement);
    expect(vm.composerRevision, composerRevisionBeforeAcknowledgement + 1);
    expect(bubbleRefreshes, 1);
    expect(unrelatedBubbleRefreshes, 0);
    vm.dispose();
  });

  test('server acknowledgement survives arriving before its bubble', () {
    final vm = ChatViewModel(chatId: 42, title: 'Test', markReadOnOpen: false);

    vm.applyLiveUpdateForTesting({
      '@type': 'updateMessageSendAcknowledged',
      'chat_id': 42,
      'message_id': 77,
    });
    vm.mergeMessageForTesting(
      ChatMessage(
        id: 77,
        chatId: 42,
        isOutgoing: true,
        isSending: true,
        text: 'Sent',
        date: 1,
      ),
    );

    expect(vm.messages.single.isSending, isTrue);
    expect(vm.messages.single.isSendAcknowledged, isTrue);
    vm.dispose();
  });
}
