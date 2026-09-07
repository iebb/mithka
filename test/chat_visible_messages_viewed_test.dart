import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final updates = StreamController<Map<String, dynamic>>.broadcast();
  final requests = <Map<String, dynamic>>[];

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (_) async => <String, dynamic>{'@type': 'ok'},
        send: (request) async => requests.add(request),
        updates: updates.stream,
      ),
    );
  });

  setUp(requests.clear);

  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  test(
    'visible incoming messages and unread reactions issue one request',
    () async {
      final viewModel = ChatViewModel(
        chatId: -10042,
        title: 'Group',
        markReadOnOpen: false,
      );
      addTearDown(viewModel.dispose);

      viewModel.markVisibleMessagesViewed([
        ChatMessage(id: 101, text: 'visible', date: 1, isOutgoing: false),
        ChatMessage(
          id: 102,
          text: 'outgoing',
          date: 2,
          isOutgoing: true,
          hasUnreadReactions: true,
        ),
        ChatMessage(
          id: 103,
          text: 'service',
          date: 3,
          isOutgoing: false,
          isService: true,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(requests, [
        {
          '@type': 'viewMessages',
          'chat_id': -10042,
          'message_ids': [101, 102],
          'force_read': true,
        },
      ]);
    },
  );

  test(
    'viewing a loaded reaction clears its local counter immediately',
    () async {
      final message = ChatMessage(
        id: 201,
        text: 'outgoing',
        date: 1,
        isOutgoing: true,
        hasUnreadReactions: true,
      );
      final viewModel = ChatViewModel(
        chatId: -10042,
        title: 'Group',
        markReadOnOpen: false,
        sessionMessages: [message],
      );
      addTearDown(viewModel.dispose);
      viewModel.applyLiveUpdateForTesting({
        '@type': 'updateChatUnreadReactionCount',
        'chat_id': -10042,
        'unread_reaction_count': 1,
      });

      viewModel.markVisibleMessagesViewed([message]);
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.unreadReactionCount, 0);
      expect(message.hasUnreadReactions, isFalse);
    },
  );
}
