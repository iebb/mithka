import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/channels/topic_chat_view.dart';
import 'package:mithka/chat/bot_platform_service.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/message_replies_sheet.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/chats/chat_list_view_model.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  Map<String, dynamic> botUser({required bool hasTopics}) => {
    '@type': 'user',
    'id': 42,
    'first_name': 'Topic',
    'last_name': 'Bot',
    'type': {
      '@type': 'userTypeBot',
      'has_topics': hasTopics,
      'allows_users_to_create_topics': true,
    },
  };

  ChatSummary botChat() => ChatSummary(
    id: 420,
    title: 'Topic Bot',
    lastMessage: '',
    lastMessageId: 0,
    date: 0,
    unreadCount: 0,
    order: 1,
    isMuted: false,
    kind: ChatKind.privateChat,
    peerUserId: 42,
  );

  test('bot topic capability is distinct from forum view state', () {
    final chat = botChat()..supportsBotTopics = true;
    final forum = botChat()..isForum = true;
    final regular = botChat();

    expect(TDParse.isBotUser(botUser(hasTopics: true)), isTrue);
    expect(TDParse.botUserHasTopics(botUser(hasTopics: true)), isTrue);
    expect(TDParse.botUserHasTopics(botUser(hasTopics: false)), isFalse);
    expect(chat.isForum, isFalse);
    expect(chat.supportsTopics, isTrue);
    expect(chat.isBotTopicChat, isTrue);
    expect(chat.usesSquareAvatar, isFalse);
    expect(showsGroupTopicControls(chat), isFalse);
    expect(canComposeInTopicSurface(chat: chat, forumTopicId: null), isFalse);
    expect(canComposeInTopicSurface(chat: chat, forumTopicId: 77), isTrue);
    expect(showsGroupTopicControls(forum), isTrue);
    expect(canComposeInTopicSurface(chat: forum, forumTopicId: null), isTrue);
    expect(showsGroupTopicControls(regular), isFalse);
    expect(canComposeInTopicSurface(chat: regular, forumTopicId: 77), isFalse);
    expect(ChatListSelection.fromChat(chat).supportsTopics, isTrue);
    expect(chatListPreviewSupportsQuickReply(chat), isFalse);
  });

  test('chat-list user hydration classifies topic-enabled bots', () {
    final model = ChatListViewModel();
    addTearDown(model.dispose);
    final chat = botChat();
    model.seedChatForTesting(chat);

    model.applyUpdateForTesting({
      '@type': 'updateUser',
      'user': botUser(hasTopics: true),
    });

    expect(chat.kind, ChatKind.bot);
    expect(chat.supportsBotTopics, isTrue);
    expect(chat.supportsTopics, isTrue);

    model.applyUpdateForTesting({
      '@type': 'updateUser',
      'user': botUser(hasTopics: false),
    });

    expect(chat.kind, ChatKind.bot);
    expect(chat.supportsBotTopics, isFalse);
    expect(chat.supportsTopics, isFalse);
  });

  test('open private chat view reacts to bot topic capability updates', () {
    final model = ChatViewModel(
      chatId: 420,
      title: 'Topic Bot',
      markReadOnOpen: false,
    )..peerUserId = 42;
    addTearDown(model.dispose);

    model.applyLiveUpdateForTesting({
      '@type': 'updateUser',
      'user': botUser(hasTopics: true),
    });

    expect(model.peerIsBot, isTrue);
    expect(model.isForum, isFalse);
    expect(model.supportsBotTopics, isTrue);
    expect(model.supportsTopics, isTrue);
  });

  test('forum topic send request uses only the typed topic destination', () {
    final request = forumTopicScopedSendRequest(
      request: {
        '@type': 'sendMessage',
        'chat_id': 420,
        'message_thread_id': 77,
      },
      forumTopicId: 77,
    );

    expect(request, isNot(contains('message_thread_id')));
    expect(request['topic_id'], {
      '@type': 'messageTopicForum',
      'forum_topic_id': 77,
    });
  });

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

  test('created topic id is read from TDLib forumTopicInfo', () {
    expect(
      forumTopicIdFromResult({'@type': 'forumTopicInfo', 'forum_topic_id': 77}),
      77,
    );
    expect(
      forumTopicIdFromResult({
        '@type': 'forumTopic',
        'info': {'@type': 'forumTopicInfo', 'forum_topic_id': 88},
      }),
      88,
    );
  });
}
