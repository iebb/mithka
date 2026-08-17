import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view_model.dart';
import 'package:mithka/tdlib/json_helpers.dart';

void main() {
  testWidgets('chat-list update bursts produce one batched notification', (
    tester,
  ) async {
    final model = ChatListViewModel();
    addTearDown(model.dispose);
    var notifications = 0;
    model.addListener(() => notifications++);

    model.scheduleResortForTesting();
    model.scheduleResortForTesting();
    model.scheduleResortForTesting();
    await tester.pump(const Duration(milliseconds: 49));
    expect(notifications, 0);

    await tester.pump(const Duration(milliseconds: 1));
    expect(notifications, 1);
  });

  test('late chat-list resort is ignored after disposal', () async {
    final model = ChatListViewModel();
    model.dispose();

    expect(() => model.meId = 42, returnsNormally);
    expect(model.scheduleResortForTesting, returnsNormally);
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });

  testWidgets('startup hydrates local rows while loadChats is pending', (
    tester,
  ) async {
    final firstLoad = Completer<Map<String, dynamic>>();
    final requestTypes = <String>[];
    final currentChat = _privateChat(
      title: 'Current chat',
      order: 200,
      messageId: 20,
      messageDate: 20,
      text: 'current message',
    );
    final model = ChatListViewModel(
      queryForTesting: (request) {
        requestTypes.add(request.type ?? 'unknown');
        return switch (request.type) {
          'loadChats' => firstLoad.future,
          'getChats' => Future.value({
            '@type': 'chats',
            'chat_ids': const <int>[42],
          }),
          'getChat' => Future.value(currentChat),
          _ => Future.value({'@type': 'ok'}),
        };
      },
    );

    model.onAppear();
    model.loadMore();
    model.applyUpdateForTesting({
      '@type': 'updateNewChat',
      'chat': _privateChat(
        title: 'Restored old chat',
        order: 100,
        messageId: 10,
        messageDate: 10,
        text: 'old cached message',
      ),
    });
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      requestTypes,
      ['loadChats', 'getChats', 'getChat'],
      reason: 'the local page should render without waiting on loadChats',
    );
    expect(model.isInitialLoading, isFalse);
    expect(model.chats, hasLength(1));
    expect(model.chats.single.title, 'Current chat');
    expect(model.chats.single.lastMessage, 'current message');

    firstLoad.complete({'@type': 'ok'});
    await tester.pump();
    await tester.pump();

    expect(requestTypes, [
      'loadChats',
      'getChats',
      'getChat',
      'getChats',
      'getChat',
    ]);
    expect(model.isInitialLoading, isFalse);
    expect(model.chats, hasLength(1));
    expect(model.chats.single.title, 'Current chat');
    expect(model.chats.single.lastMessage, 'current message');

    model.applyUpdateForTesting({
      '@type': 'updateNewChat',
      'chat': _privateChat(
        title: 'Late restored old chat',
        order: 100,
        messageId: 10,
        messageDate: 10,
        text: 'late old cached message',
      ),
    });
    await tester.pump(const Duration(milliseconds: 50));

    expect(model.chats.single.title, 'Current chat');
    expect(model.chats.single.lastMessage, 'current message');

    model.dispose();
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('live chat updates survive a delayed startup membership lookup', (
    tester,
  ) async {
    final membership = Completer<bool>();
    final model = ChatListViewModel(
      membershipForTesting: (_, _) => membership.future,
    );
    addTearDown(model.dispose);

    final ingest = model.ingestRawChatForTesting(
      _groupChat(
        order: 100,
        messageId: 10,
        messageDate: 10,
        text: 'old startup message',
      ),
    );
    expect(model.chats, isEmpty);

    model.applyUpdateForTesting({
      '@type': 'updateChatLastMessage',
      'chat_id': 42,
      'last_message': _message(id: 20, date: 20, text: 'live message'),
      'positions': [
        {
          '@type': 'chatPosition',
          'list': {'@type': 'chatListMain'},
          'order': 200,
          'is_pinned': false,
        },
      ],
    });
    await tester.pump(const Duration(milliseconds: 50));

    expect(model.chats, hasLength(1));
    expect(model.chats.single.lastMessage, 'live message');
    expect(model.chats.single.order, 200);

    membership.complete(true);
    await ingest;
    await tester.pump(const Duration(milliseconds: 50));

    expect(model.chats, hasLength(1));
    expect(model.chats.single.lastMessage, 'live message');
    expect(model.chats.single.lastMessageId, 20);
    expect(model.chats.single.date, 20);
    expect(model.chats.single.order, 200);
  });
}

Map<String, dynamic> _privateChat({
  required String title,
  required int order,
  required int messageId,
  required int messageDate,
  required String text,
}) => {
  '@type': 'chat',
  'id': 42,
  'title': title,
  'type': {'@type': 'chatTypePrivate', 'user_id': 7},
  'last_message': _message(id: messageId, date: messageDate, text: text),
  'positions': [
    {
      '@type': 'chatPosition',
      'list': {'@type': 'chatListMain'},
      'order': order,
      'is_pinned': false,
    },
  ],
};

Map<String, dynamic> _groupChat({
  required int order,
  required int messageId,
  required int messageDate,
  required String text,
}) => {
  '@type': 'chat',
  'id': 42,
  'title': 'Current group',
  'view_as_topics': true,
  'type': {
    '@type': 'chatTypeSupergroup',
    'supergroup_id': 7,
    'is_channel': false,
  },
  'last_message': _message(id: messageId, date: messageDate, text: text),
  'positions': [
    {
      '@type': 'chatPosition',
      'list': {'@type': 'chatListMain'},
      'order': order,
      'is_pinned': false,
    },
  ],
};

Map<String, dynamic> _message({
  required int id,
  required int date,
  required String text,
}) => {
  '@type': 'message',
  'id': id,
  'chat_id': 42,
  'date': date,
  'is_outgoing': false,
  'content': {
    '@type': 'messageText',
    'text': {'@type': 'formattedText', 'text': text, 'entities': <Object>[]},
  },
};
