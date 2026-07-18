import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/channel_direct_messages_service.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  group('channel direct-message requests', () {
    test(
      'loads the administered topic stream with the pinned schema fields',
      () {
        expect(loadDirectMessagesTopicsRequest(chatId: -10042, limit: 25), {
          '@type': 'loadDirectMessagesChatTopics',
          'chat_id': -10042,
          'limit': 25,
        });
        expect(
          directMessagesTopicHistoryRequest(
            chatId: -10042,
            topicId: 77,
            fromMessageId: 100,
            limit: 30,
          ),
          {
            '@type': 'getDirectMessagesChatTopicHistory',
            'chat_id': -10042,
            'topic_id': 77,
            'from_message_id': 100,
            'offset': 0,
            'limit': 30,
          },
        );
      },
    );

    test('free suggested post still carries inputSuggestedPostInfo', () {
      final request = sendDirectMessageRequest(
        chatId: -10042,
        topicId: 77,
        text: 'A post proposal',
        asSuggestedPost: true,
      );
      expect(request['topic_id'], {
        '@type': 'messageTopicDirectMessages',
        'direct_messages_chat_topic_id': 77,
      });
      expect(request['options'], {
        '@type': 'messageSendOptions',
        'suggested_post_info': {
          '@type': 'inputSuggestedPostInfo',
          'price': null,
          'send_date': 0,
        },
      });
    });

    test(
      'paid suggested post keeps Stars and scheduled publish time exact',
      () {
        final request = sendDirectMessageRequest(
          chatId: -10042,
          topicId: 77,
          text: 'Sponsored post',
          price: const SuggestedPostPrice(
            kind: SuggestedPostPriceKind.stars,
            amount: 250,
          ),
          sendDate: 1800000000,
          asSuggestedPost: true,
        );
        final options = request['options']! as Map<String, dynamic>;
        final info = options['suggested_post_info']! as Map<String, dynamic>;
        expect(info['price'], {
          '@type': 'suggestedPostPriceStar',
          'star_count': 250,
        });
        expect(info['send_date'], 1800000000);
      },
    );

    test('media suggested post uses the same topic and offer envelope', () {
      final request = sendDirectContentRequest(
        chatId: -10042,
        topicId: 77,
        inputMessageContent: {
          '@type': 'inputMessagePhoto',
          'photo': {
            '@type': 'inputPhoto',
            'photo': {'@type': 'inputFileLocal', 'path': '/tmp/post.jpg'},
          },
        },
        asSuggestedPost: true,
      );
      expect(request['topic_id'], {
        '@type': 'messageTopicDirectMessages',
        'direct_messages_chat_topic_id': 77,
      });
      expect(
        (request['input_message_content'] as Map<String, dynamic>)['@type'],
        'inputMessagePhoto',
      );
      expect(
        (request['options'] as Map<String, dynamic>)['suggested_post_info'],
        {'@type': 'inputSuggestedPostInfo', 'price': null, 'send_date': 0},
      );
    });

    test('TON offers use hundredths of a Gram as required by TDLib', () {
      final request = addSuggestedPostOfferRequest(
        chatId: -10042,
        messageId: 991,
        price: const SuggestedPostPrice(
          kind: SuggestedPostPriceKind.ton,
          amount: 1234,
        ),
      );
      final options = request['options']! as Map<String, dynamic>;
      final info = options['suggested_post_info']! as Map<String, dynamic>;
      expect(info['price'], {
        '@type': 'suggestedPostPriceGram',
        'gram_cent_count': 1234,
      });
    });

    test('approval and decline requests use their dedicated functions', () {
      expect(
        approveSuggestedPostRequest(
          chatId: -10042,
          messageId: 991,
          sendDate: 1800000000,
        ),
        {
          '@type': 'approveSuggestedPost',
          'chat_id': -10042,
          'message_id': 991,
          'send_date': 1800000000,
        },
      );
      expect(
        declineSuggestedPostRequest(
          chatId: -10042,
          messageId: 991,
          comment: 'Not a fit',
        ),
        {
          '@type': 'declineSuggestedPost',
          'chat_id': -10042,
          'message_id': 991,
          'comment': 'Not a fit',
        },
      );
    });

    test('topic drafts are scoped with messageTopicDirectMessages', () {
      final request = directMessagesTopicDraftRequest(
        chatId: -10042,
        topicId: 77,
        text: 'Work in progress',
        date: 1700000000,
      );
      expect(request['topic_id'], {
        '@type': 'messageTopicDirectMessages',
        'direct_messages_chat_topic_id': 77,
      });
      final draft = request['draft_message']! as Map<String, dynamic>;
      expect(draft['date'], 1700000000);
      expect(
        (draft['content'] as Map<String, dynamic>)['@type'],
        'draftMessageContentText',
      );
      expect(
        directMessagesTopicDraftRequest(
          chatId: -10042,
          topicId: 77,
          text: '',
          date: 1700000000,
        )['draft_message'],
        isNull,
      );
    });

    test('date navigation and deletion use direct-topic functions', () {
      expect(
        directMessagesTopicMessageByDateRequest(
          chatId: -10042,
          topicId: 77,
          date: 1700000000,
        ),
        {
          '@type': 'getDirectMessagesChatTopicMessageByDate',
          'chat_id': -10042,
          'topic_id': 77,
          'date': 1700000000,
        },
      );
      expect(
        deleteDirectMessagesTopicByDateRequest(
          chatId: -10042,
          topicId: 77,
          minDate: 1700000000,
          maxDate: 1700600000,
        ),
        {
          '@type': 'deleteDirectMessagesChatTopicMessagesByDate',
          'chat_id': -10042,
          'topic_id': 77,
          'min_date': 1700000000,
          'max_date': 1700600000,
        },
      );
    });
  });

  group('direct-message topic parsing', () {
    test('parses counters, sender, draft and last message', () {
      final topic = DirectMessagesTopic.fromTd({
        '@type': 'directMessagesChatTopic',
        'chat_id': '-10042',
        'id': '77',
        'sender_id': {'@type': 'messageSenderUser', 'user_id': '9'},
        'order': '500',
        'can_send_unpaid_messages': true,
        'is_marked_as_unread': true,
        'unread_count': '3',
        'last_read_inbox_message_id': '90',
        'last_read_outbox_message_id': '91',
        'unread_reaction_count': '2',
        'last_message': {
          '@type': 'message',
          'id': '100',
          'chat_id': '-10042',
          'is_outgoing': false,
          'date': 1700000000,
          'content': {
            '@type': 'messageText',
            'text': {'@type': 'formattedText', 'text': 'Hello'},
          },
        },
        'draft_message': {
          '@type': 'draftMessage',
          'content': {
            '@type': 'draftMessageContentText',
            'text': {'@type': 'formattedText', 'text': 'Draft answer'},
          },
        },
      });
      expect(topic, isNotNull);
      expect(topic!.chatId, -10042);
      expect(topic.id, 77);
      expect(topic.order, 500);
      expect(topic.canSendUnpaidMessages, isTrue);
      expect(topic.isMarkedAsUnread, isTrue);
      expect(topic.unreadCount, 3);
      expect(topic.unreadReactionCount, 2);
      expect(topic.lastMessage?.text, 'Hello');
      expect(topic.draftText, 'Draft answer');
    });

    test('message properties preserve every suggested-post action', () {
      final capabilities = SuggestedPostCapabilities.fromTd({
        '@type': 'messageProperties',
        'can_add_offer': true,
        'can_be_approved': true,
        'can_be_declined': true,
        'can_be_edited': true,
        'can_edit_suggested_post_info': true,
      });
      expect(capabilities.canAddOffer, isTrue);
      expect(capabilities.canBeApproved, isTrue);
      expect(capabilities.canBeDeclined, isTrue);
      expect(capabilities.canBeEdited, isTrue);
      expect(capabilities.canEditSuggestedPostInfo, isTrue);
      expect(capabilities.hasActions, isTrue);
    });
  });

  group('suggested-post message rendering data', () {
    test('parses pending post price, schedule, and server action flags', () {
      final message = TDParse.message({
        '@type': 'message',
        'id': '101',
        'chat_id': '-10042',
        'is_outgoing': true,
        'date': 1700000000,
        'suggested_post_info': {
          '@type': 'suggestedPostInfo',
          'price': {'@type': 'suggestedPostPriceStar', 'star_count': '500'},
          'send_date': 1800000000,
          'state': {'@type': 'suggestedPostStatePending'},
          'can_be_approved': true,
          'can_be_declined': true,
        },
        'content': {
          '@type': 'messageText',
          'text': {'@type': 'formattedText', 'text': 'Suggested copy'},
        },
      });
      expect(message?.suggestedPostInfo, isNotNull);
      expect(message?.suggestedPostInfo?.state, SuggestedPostState.pending);
      expect(message?.suggestedPostInfo?.price?.amount, 500);
      expect(
        message?.suggestedPostInfo?.price?.kind,
        SuggestedPostPriceKind.stars,
      );
      expect(message?.suggestedPostInfo?.sendDate, 1800000000);
      expect(message?.suggestedPostInfo?.canBeApproved, isTrue);
      expect(message?.suggestedPostInfo?.canBeDeclined, isTrue);
    });

    test('renders paid and refund service states as suggested-post cards', () {
      final paid = TDParse.summaryCard({}, {
        '@type': 'messageSuggestedPostPaid',
        'suggested_post_message_id': '101',
        'star_amount': {
          '@type': 'starAmount',
          'star_count': '250',
          'nanostar_count': 0,
        },
        'gram_amount': '0',
      });
      final refunded = TDParse.summaryCard({}, {
        '@type': 'messageSuggestedPostRefunded',
        'suggested_post_message_id': '101',
        'reason': {'@type': 'suggestedPostRefundReasonPostDeleted'},
      });
      expect(paid?.kind, MessageSummaryKind.suggestedPost);
      expect(paid?.detail, '250 Stars');
      expect(refunded?.kind, MessageSummaryKind.suggestedPost);
      expect(refunded?.detail, isNotEmpty);
    });
  });
}
