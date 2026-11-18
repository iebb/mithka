import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view_model.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'archive without a pinned owner never falls back to a later account',
    () async {
      final requests = <Map<String, dynamic>>[];
      TdClient.shared.configureProxy(
        TdClientProxyTransport(
          accountSlot: 4,
          query: (request) async {
            requests.add(Map<String, dynamic>.from(request));
            return {'@type': 'ok'};
          },
          send: (_) async {},
          updates: const Stream.empty(),
        ),
      );
      addTearDown(TdClient.shared.closeProxy);
      final model = ChatListViewModel();
      addTearDown(model.dispose);
      final chat = ChatSummary(
        id: 42,
        title: 'Example',
        lastMessage: '',
        lastMessageId: 1,
        date: 1,
        unreadCount: 0,
        order: 1,
        isMuted: false,
      );

      // The menu could not pin an account at open. Another account is now
      // available, but it never owned the menu's chat.
      model.archive(chat, owner: null);
      await Future<void>.delayed(Duration.zero);
      expect(requests, isEmpty);
    },
  );
}
