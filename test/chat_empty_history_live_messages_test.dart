import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_message_merge.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A chat with no history at all: a bot that was never started, a new DM found
// by search, or an empty Saved Messages. getChat has no last_message and both
// the local and the remote latest history pages are empty.
const _chatId = 777;
const _botUserId = 777;

Map<String, dynamic> _message(
  int id, {
  bool outgoing = false,
  bool pending = false,
  String text = 'hello',
}) => {
  '@type': 'message',
  'id': id,
  'chat_id': _chatId,
  'date': 1700000000 + id ~/ 1048576,
  'is_outgoing': outgoing,
  'sender_id': {
    '@type': 'messageSenderUser',
    'user_id': outgoing ? 1 : _botUserId,
  },
  if (pending) 'sending_state': {'@type': 'messageSendingStatePending'},
  'content': {
    '@type': 'messageText',
    'text': {'@type': 'formattedText', 'text': text},
  },
};

const _emptyPage = <String, dynamic>{
  '@type': 'messages',
  'total_count': 0,
  'messages': <Map<String, dynamic>>[],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final historyRequests = <Map<String, dynamic>>[];
  late Future<Map<String, dynamic>> Function(Map<String, dynamic>)
  remoteHistory;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          switch (request['@type']) {
            case 'getChatHistory':
              historyRequests.add(request);
              if (request['only_local'] == true) return _emptyPage;
              return remoteHistory(request);
            case 'getChat':
              return {
                '@type': 'chat',
                'id': _chatId,
                'title': 'Never Started Bot',
                'type': {'@type': 'chatTypePrivate', 'user_id': _botUserId},
                'permissions': {
                  '@type': 'chatPermissions',
                  'can_send_basic_messages': true,
                },
                'last_read_inbox_message_id': 0,
                'last_read_outbox_message_id': 0,
                'unread_count': 0,
                // No 'last_message': the chat has never had any history.
              };
            case 'getUser':
              return {
                '@type': 'user',
                'id': _botUserId,
                'first_name': 'Never Started Bot',
                'type': {'@type': 'userTypeBot'},
              };
          }
          return {'@type': 'ok'};
        },
        send: (_) async {},
        updates: const Stream.empty(),
      ),
    );
  });
  tearDownAll(TdClient.shared.closeProxy);
  setUp(() {
    historyRequests.clear();
    remoteHistory = (_) async => _emptyPage;
  });

  Future<ChatViewModel> openEmptyChat() async {
    final vm = ChatViewModel(
      chatId: _chatId,
      title: 'Never Started Bot',
      markReadOnOpen: false,
    );
    addTearDown(vm.dispose);
    vm.onAppear();
    for (var i = 0; i < 100 && !vm.initialLoaded; i++) {
      await pumpEventQueue();
    }
    expect(vm.initialLoaded, isTrue);
    expect(vm.messages, isEmpty);
    expect(
      historyRequests.map((request) => request['only_local']),
      containsAllInOrder([true, false]),
      reason: 'the open path checks the local cache, then the server',
    );
    return vm;
  }

  test('a live message appears in a chat opened with no history', () async {
    final vm = await openEmptyChat();

    vm.applyLiveUpdateForTesting({
      '@type': 'updateNewMessage',
      'message': _message(1048576, text: 'Welcome!'),
    });

    expect(vm.messages.map((message) => message.id), [1048576]);
  });

  test('bot start: the sent /start and the bot reply both appear', () async {
    final vm = await openEmptyChat();

    vm.applyLiveUpdateForTesting({
      '@type': 'updateNewMessage',
      'message': _message(1, outgoing: true, pending: true, text: '/start'),
    });
    vm.applyLiveUpdateForTesting({
      '@type': 'updateMessageSendSucceeded',
      'old_message_id': 1,
      'message': _message(1048576, outgoing: true, text: '/start'),
    });
    vm.applyLiveUpdateForTesting({
      '@type': 'updateNewMessage',
      'message': _message(2097152, text: 'Hi! I am a bot.'),
    });

    expect(vm.messages.map((message) => message.id), [1048576, 2097152]);
    expect(vm.messages.map((message) => message.text), [
      '/start',
      'Hi! I am a bot.',
    ]);
  });

  test('an empty local page alone does not claim the latest edge', () async {
    final remote = Completer<Map<String, dynamic>>();
    remoteHistory = (_) => remote.future;
    final vm = ChatViewModel(
      chatId: _chatId,
      title: 'Never Started Bot',
      markReadOnOpen: false,
    );
    addTearDown(vm.dispose);
    vm.onAppear();
    for (
      var i = 0;
      i < 100 && !historyRequests.any((r) => r['only_local'] == false);
      i++
    ) {
      await pumpEventQueue();
    }
    // The local cache was empty but the server has not answered yet: it may
    // still hold history, so the window must not claim to be at the latest.
    expect(vm.historyReachesLatest, isFalse);

    remote.complete(_emptyPage);
    for (var i = 0; i < 100 && !vm.initialLoaded; i++) {
      await pumpEventQueue();
    }
    expect(vm.historyReachesLatest, isTrue);
  });

  test('only an empty remote latest page of an unanchored empty window '
      'confirms the latest edge', () {
    bool confirms({
      bool onlyLocal = false,
      int fromMessageId = 0,
      int offset = 0,
      bool anchoredHistory = false,
      bool restoredFromSession = false,
      int windowLatestServerMessageId = 0,
    }) => confirmsEmptyChatReachesLatest(
      onlyLocal: onlyLocal,
      fromMessageId: fromMessageId,
      offset: offset,
      anchoredHistory: anchoredHistory,
      restoredFromSession: restoredFromSession,
      windowLatestServerMessageId: windowLatestServerMessageId,
    );

    expect(confirms(), isTrue);
    expect(confirms(onlyLocal: true), isFalse);
    expect(confirms(fromMessageId: 1048576), isFalse);
    expect(confirms(offset: -30), isFalse);
    expect(confirms(anchoredHistory: true), isFalse);
    expect(confirms(restoredFromSession: true), isFalse);
    expect(confirms(windowLatestServerMessageId: 1048576), isFalse);
  });
}
