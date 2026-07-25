import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/appearance_preview_repository.dart';

Map<String, dynamic> _textMessage({
  required int id,
  required int chatId,
  required int senderId,
  required String text,
  required int date,
  bool outgoing = false,
}) => {
  '@type': 'message',
  'id': id,
  'chat_id': chatId,
  'sender_id': {'@type': 'messageSenderUser', 'user_id': senderId},
  'is_outgoing': outgoing,
  'date': date,
  'content': {
    '@type': 'messageText',
    'text': {'@type': 'formattedText', 'text': text, 'entities': <Object>[]},
  },
};

Map<String, dynamic> _chat({
  required int id,
  required String title,
  required Map<String, dynamic> type,
  required Map<String, dynamic> lastMessage,
  int order = 1,
  int lastReadOutboxId = 0,
  bool protected = false,
}) => {
  '@type': 'chat',
  'id': id,
  'title': title,
  'type': type,
  'unread_count': 0,
  'last_read_outbox_message_id': lastReadOutboxId,
  'has_protected_content': protected,
  'last_message': lastMessage,
  'positions': [
    {
      '@type': 'chatPosition',
      'list': {'@type': 'chatListMain'},
      'order': order,
      'is_pinned': false,
    },
  ],
};

void main() {
  test('loads only bounded read-only TDLib preview data', () async {
    const clientId = 71;
    const slot = 2;
    final requests = <Map<String, dynamic>>[];
    final clients = <int>[];
    final chats = <int, Map<String, dynamic>>{
      100: _chat(
        id: 100,
        title: 'Actual group',
        type: {'@type': 'chatTypeBasicGroup', 'basic_group_id': 7},
        lastMessage: _textMessage(
          id: 106,
          chatId: 100,
          senderId: 9,
          text: 'Latest actual text',
          date: 106,
        ),
        order: 4,
        lastReadOutboxId: 103,
      ),
      200: _chat(
        id: 200,
        title: 'Saved Messages',
        type: {'@type': 'chatTypePrivate', 'user_id': 1},
        lastMessage: _textMessage(
          id: 201,
          chatId: 200,
          senderId: 1,
          text: 'Saved note',
          date: 201,
          outgoing: true,
        ),
        order: 3,
      ),
      300: _chat(
        id: 300,
        title: 'Actual channel',
        type: {
          '@type': 'chatTypeSupergroup',
          'supergroup_id': 3,
          'is_channel': true,
        },
        lastMessage: _textMessage(
          id: 301,
          chatId: 300,
          senderId: 9,
          text: 'Channel update',
          date: 301,
        ),
        order: 2,
      ),
      400: _chat(
        id: 400,
        title: 'Secret',
        type: {'@type': 'chatTypeSecret', 'secret_chat_id': 4, 'user_id': 9},
        lastMessage: _textMessage(
          id: 401,
          chatId: 400,
          senderId: 9,
          text: 'Never preview this',
          date: 401,
        ),
      ),
    };
    final history = [
      _textMessage(
        id: 106,
        chatId: 100,
        senderId: 9,
        text: 'Newest',
        date: 106,
      ),
      {
        '@type': 'message',
        'id': 105,
        'chat_id': 100,
        'sender_id': {'@type': 'messageSenderUser', 'user_id': 9},
        'is_outgoing': false,
        'date': 105,
        'content': {'@type': 'messageSticker'},
      },
      _textMessage(
        id: 104,
        chatId: 100,
        senderId: 1,
        text: 'Unread by peer',
        date: 104,
        outgoing: true,
      ),
      {
        '@type': 'message',
        'id': 103,
        'chat_id': 100,
        'sender_id': {'@type': 'messageSenderUser', 'user_id': 9},
        'is_outgoing': false,
        'date': 103,
        'content': {'@type': 'messageChatChangeTitle', 'title': 'New title'},
      },
      _textMessage(
        id: 102,
        chatId: 100,
        senderId: 1,
        text: 'Read by peer',
        date: 102,
        outgoing: true,
      ),
      _textMessage(
        id: 101,
        chatId: 100,
        senderId: 9,
        text: 'Oldest',
        date: 101,
      ),
    ];

    final repository = AppearancePreviewRepository(
      activeClientId: () => clientId,
      activeSlot: () => slot,
      cachedUser: (accountSlot, userId) => userId == 9
          ? {
              '@type': 'user',
              'id': 9,
              'first_name': 'Actual',
              'last_name': 'Sender',
              'is_premium': true,
              'accent_color_id': 2,
            }
          : null,
      queryTo: (request, targetClientId) async {
        requests.add(Map<String, dynamic>.from(request));
        clients.add(targetClientId);
        return switch (request['@type']) {
          'getMe' => {
            '@type': 'user',
            'id': 1,
            'first_name': 'Account',
            'last_name': 'Owner',
            'phone_number': '819012345678',
          },
          'getChats' => {
            '@type': 'chats',
            'chat_ids': [100, 200, 300, 400, 500],
          },
          'getChat' => chats[request['chat_id']]!,
          'getChatHistory' => {
            '@type': 'messages',
            'total_count': history.length,
            'messages': history,
          },
          _ => throw StateError('Unexpected request: $request'),
        };
      },
    );

    final snapshot = await repository.load();

    expect(snapshot, isNotNull);
    expect(snapshot!.clientId, clientId);
    expect(snapshot.accountSlot, slot);
    expect(snapshot.meId, 1);
    expect(snapshot.meName, 'Account Owner');
    expect(snapshot.mePhone, isNotEmpty);
    expect(snapshot.chatRows.map((chat) => chat.id), [100, 200]);
    expect(snapshot.chatRows.last.isSavedMessages, isTrue);
    expect(snapshot.groupChat?.id, 100);
    expect(snapshot.transcriptChat?.id, 100);
    expect(snapshot.peerTitle, 'Actual group');
    expect(snapshot.isGroup, isTrue);
    expect(snapshot.messages.map((item) => item.message.id), [102, 104, 106]);
    expect(snapshot.messages[0].message.senderName, 'Account Owner');
    expect(snapshot.messages[0].isRead, isTrue);
    expect(snapshot.messages[1].isRead, isFalse);
    expect(snapshot.messages[2].message.senderName, 'Actual Sender');

    expect(clients, everyElement(clientId));
    expect(requests.map((request) => request['@type']).toSet(), {
      'getMe',
      'getChats',
      'getChat',
      'getChatHistory',
    });
    final getChats = requests.singleWhere(
      (request) => request['@type'] == 'getChats',
    );
    expect(getChats['limit'], AppearancePreviewRepository.inspectedChatLimit);
    final getHistory = requests.singleWhere(
      (request) => request['@type'] == 'getChatHistory',
    );
    expect(
      getHistory['limit'],
      lessThanOrEqualTo(AppearancePreviewRepository.historyRequestLimit),
    );
    expect(getHistory['only_local'], isTrue);
    expect(
      requests.where((request) => request['@type'] == 'getChat'),
      hasLength(AppearancePreviewRepository.inspectedChatLimit),
    );
  });

  test('discards in-flight data after the active client changes', () async {
    var activeClientId = 71;
    final meCompleter = Completer<Map<String, dynamic>>();
    final requests = <Map<String, dynamic>>[];
    final repository = AppearancePreviewRepository(
      activeClientId: () => activeClientId,
      activeSlot: () => 0,
      queryTo: (request, _) {
        requests.add(Map<String, dynamic>.from(request));
        if (request['@type'] == 'getMe') return meCompleter.future;
        return Future.value({'@type': 'chats', 'chat_ids': <int>[]});
      },
    );

    final load = repository.load();
    activeClientId = 72;
    meCompleter.complete({
      '@type': 'user',
      'id': 1,
      'first_name': 'Stale',
      'last_name': 'Account',
    });

    expect(await load, isNull);
    expect(
      requests.map((request) => request['@type']),
      containsAll(['getMe', 'getChats']),
    );
    expect(
      requests.any(
        (request) =>
            request['@type'] == 'getChat' ||
            request['@type'] == 'getChatHistory',
      ),
      isFalse,
    );
  });
}
