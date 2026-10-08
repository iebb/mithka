import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view_model.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Completer<Map<String, dynamic>> folder;
  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (_) => folder.future,
        send: (_) async {},
        updates: const Stream<Map<String, dynamic>>.empty(),
      ),
    );
  });
  tearDownAll(TdClient.shared.closeProxy);
  testWidgets('folder metadata cannot gate or reset a native unread badge', (
    tester,
  ) async {
    folder = Completer<Map<String, dynamic>>();
    final model = ChatListViewModel();
    addTearDown(model.dispose);
    model.seedChatForTesting(
      ChatSummary(
        id: 31,
        title: 'Fixture',
        lastMessage: '',
        lastMessageId: 1,
        date: 1,
        unreadCount: 5,
        isMuted: false,
        order: 1,
      ),
    );
    model.applyUpdateForTesting({
      '@type': 'updateChatPosition',
      'chat_id': 31,
      'position': {
        '@type': 'chatPosition',
        'order': 10,
        'is_pinned': false,
        'list': {'@type': 'chatListFolder', 'chat_folder_id': 7},
      },
    });
    await tester.pump(const Duration(milliseconds: 60));
    final before = model.filters
        .singleWhere((f) => f.folderId == 7)
        .unreadChatCount;
    folder.complete({
      '@type': 'chatFolder',
      'name': {
        '@type': 'chatFolderName',
        'text': {'@type': 'formattedText', 'text': 'Resolved', 'entities': []},
      },
      'icon': {'@type': 'chatFolderIcon', 'name': 'Work'},
    });
    await tester.pump(const Duration(milliseconds: 10));
    final after = model.filters
        .singleWhere((f) => f.folderId == 7)
        .unreadChatCount;
    expect(model.chatsForFolder(7), hasLength(1));
    expect(
      before,
      1,
      reason: 'native membership does not depend on folder metadata',
    );
    expect(after, 1, reason: 'a title/icon refresh must preserve the badge');
  });
}
