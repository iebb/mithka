import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view_model.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';

// Edit-mode pinned reorder: the model swaps the dragged chat onto its
// neighbour's slot locally and commits the full pinned order through
// `setPinnedChats`, mirroring the reference client's ItemTouchHelper drag that ends in
// reorderPinnedDialogs.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final requests = <Map<String, dynamic>>[];
  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          requests.add(Map<String, dynamic>.from(request));
          return {'@type': 'ok'};
        },
        send: (_) async {},
        updates: const Stream.empty(),
      ),
    );
  });
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
  });

  test('reorderPinnedChat swaps the pair and commits setPinnedChats', () async {
    final model = ChatListViewModel();
    addTearDown(model.dispose);
    requests.clear();

    ChatSummary pinned(int id, int order) => ChatSummary(
      id: id,
      title: 'P$id',
      lastMessage: '',
      lastMessageId: 1,
      date: 1,
      unreadCount: 0,
      order: order,
      isPinned: true,
      isMuted: false,
    );

    // Feed three pinned chats through the same update path the list uses.
    model.debugIngestChatsForTest([
      pinned(1, 300),
      pinned(2, 200),
      pinned(3, 100),
    ]);
    expect(model.chats.map((c) => c.id).toList(), [
      1,
      2,
      3,
    ], reason: 'higher order sorts first');

    model.reorderPinnedChat(chatId: 1, targetChatId: 2);
    await Future<void>.delayed(Duration.zero);

    expect(
      model.chats.map((c) => c.id).toList(),
      [2, 1, 3],
      reason: 'dragging chat 1 down one slot swaps it with chat 2',
    );
    final commit = requests.where((r) => r['@type'] == 'setPinnedChats').single;
    expect(commit['chat_ids'], [2, 1, 3]);
    expect(commit['chat_list'], {'@type': 'chatListMain'});
  });

  test('reorder in a folder rewrites that folder’s pin order only', () async {
    final model = ChatListViewModel();
    addTearDown(model.dispose);
    requests.clear();

    ChatSummary chat(int id, int order) => ChatSummary(
      id: id,
      title: 'C$id',
      lastMessage: '',
      lastMessageId: 1,
      date: 1,
      unreadCount: 0,
      order: order,
      isMuted: false,
    );

    model.debugIngestChatsForTest([chat(1, 300), chat(2, 200), chat(3, 100)]);
    model.debugSelectFolderForTest(7, pinnedIds: {1, 2});
    model.reorderPinnedChat(chatId: 2, targetChatId: 1);
    await Future<void>.delayed(Duration.zero);

    final commit = requests.where((r) => r['@type'] == 'setPinnedChats').single;
    expect(commit['chat_list'], {
      '@type': 'chatListFolder',
      'chat_folder_id': 7,
    });
    expect(commit['chat_ids'], [2, 1]);
  });
}
