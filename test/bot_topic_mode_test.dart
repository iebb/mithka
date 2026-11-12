import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/channels/topic_chat_view.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/message_replies_sheet.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  test(
    'failed scoped send is attempted once and never loses its topic',
    () async {
      final attempts = <Map<String, dynamic>>[];
      final request = forumTopicScopedSendRequest(
        request: {'@type': 'sendMessage', 'chat_id': 420},
        forumTopicId: 77,
      );

      await expectLater(
        sendScopedForumTopicMessage(
          query: (candidate) async {
            attempts.add(candidate);
            throw StateError('rejected');
          },
          request: request,
        ),
        throwsA(isA<StateError>()),
      );

      expect(attempts, hasLength(1));
      expect(
        (attempts.single['topic_id'] as Map<String, dynamic>)['forum_topic_id'],
        77,
      );
    },
  );

  test('reply compatibility never drops a forum topic destination', () {
    final candidates = replySheetSendCandidates({
      '@type': 'sendMessage',
      'chat_id': 420,
      'topic_id': {'@type': 'messageTopicForum', 'forum_topic_id': 77},
      'message_thread_id': 77,
      'reply_to': {'@type': 'inputMessageReplyToMessage', 'message_id': 88},
    });

    expect(candidates, hasLength(2));
    expect(
      candidates.every(
        (candidate) =>
            (candidate['topic_id'] as Map<String, dynamic>)['@type'] ==
            'messageTopicForum',
      ),
      isTrue,
    );
  });

  test('a bot topic transcript drops unattributed traffic', () {
    // Live updateNewMessage for the open transcript: in a bot topic chat
    // (isForum false) a message without topic_id must not join the transcript
    // — the General fallback is forum-only.
    Map<String, dynamic> rawMessage({required int id, int? topicId}) => {
      '@type': 'message',
      'id': id,
      'chat_id': 700,
      'date': id,
      'is_outgoing': false,
      'sender_id': {'@type': 'messageSenderUser', 'user_id': 42},
      if (topicId != null)
        'topic_id': {'@type': 'messageTopicForum', 'forum_topic_id': topicId},
      'content': {
        '@type': 'messageText',
        'text': {'@type': 'formattedText', 'text': 'hi'},
      },
    };
    final model =
        ChatViewModel(
            chatId: 700,
            title: 'Topic Bot',
            markReadOnOpen: false,
            forumTopicId: 61474,
            sessionMessages: [
              TDParse.message(rawMessage(topicId: 61474, id: 5))!,
            ],
            sessionAnchoredHistory: true,
          )
          ..isForumForTesting(false)
          ..supportsBotTopicsForTesting(true)
          ..historyReachesLatestForTesting();
    addTearDown(model.dispose);
    expect(model.messages, hasLength(1));

    model.applyLiveUpdateForTesting({
      '@type': 'updateNewMessage',
      'message': rawMessage(id: 6),
    });
    expect(
      model.messages,
      hasLength(1),
      reason: 'no topic reference, no General bucket — the message is dropped',
    );

    model.applyLiveUpdateForTesting({
      '@type': 'updateNewMessage',
      'message': rawMessage(id: 7, topicId: 61474),
    });
    expect(model.messages, hasLength(2));
  });
}
