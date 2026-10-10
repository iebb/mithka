import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view_model.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';

ChatSummary _chat({
  required int id,
  required int order,
  required int date,
  int unreadCount = 0,
  bool isMuted = false,
}) => ChatSummary(
  id: id,
  title: 'Chat $id',
  lastMessage: 'Message',
  lastMessageId: 100 + id,
  date: date,
  unreadCount: unreadCount,
  order: order,
  isMuted: isMuted,
);

Map<String, dynamic> _mainPosition(int order) => {
  'list': {'@type': 'chatListMain'},
  'order': order,
};

Map<String, dynamic> _readInbox(int chatId, int unreadCount) => {
  '@type': 'updateChatReadInbox',
  'chat_id': chatId,
  'last_read_inbox_message_id': 100 + chatId,
  'unread_count': unreadCount,
};

void main() {
  final updates = StreamController<Map<String, dynamic>>.broadcast();

  setUpAll(() {
    // Drive the real view model without touching a Telegram account.
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => {'@type': 'ok'},
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });

  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  /// A model holding [chats] with one resort already behind it, so the sorted
  /// window and the projection cache both exist.
  Future<ChatListViewModel> seeded(
    WidgetTester tester,
    List<ChatSummary> chats,
  ) async {
    final model = ChatListViewModel();
    addTearDown(model.dispose);
    for (final chat in chats) {
      model.seedChatForTesting(chat);
    }
    model.scheduleResortForTesting();
    await tester.pump(const Duration(milliseconds: 51));
    return model;
  }

  testWidgets('clearing a badge keeps the sorted window it is drawn from', (
    tester,
  ) async {
    final model = await seeded(tester, [
      _chat(id: 1, order: 30, date: 3, unreadCount: 5),
      _chat(id: 2, order: 20, date: 2),
      _chat(id: 3, order: 10, date: 1),
    ]);
    final entries = model.chatListEntries();
    expect(model.chats.map((chat) => chat.id), [1, 2, 3]);

    var notifications = 0;
    model.addListener(() => notifications++);

    model.applyUpdateForTesting(_readInbox(1, 0));

    // Still debounced: the row repaints on the same 50 ms window a resort uses.
    await tester.pump(const Duration(milliseconds: 49));
    expect(notifications, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(notifications, 1);

    expect(model.chats.first.unreadCount, 0);
    // Unread count is not a sort key, so the window keeps its order and the
    // rows keep the projection they were already built from.
    expect(model.chats.map((chat) => chat.id), [1, 2, 3]);
    expect(identical(model.chatListEntries(), entries), isTrue);
  });

  testWidgets('mute, mention and title updates do not rebuild the window', (
    tester,
  ) async {
    final model = await seeded(tester, [
      _chat(id: 1, order: 30, date: 3),
      _chat(id: 2, order: 20, date: 2),
    ]);
    final entries = model.chatListEntries();

    model.applyUpdateForTesting({
      '@type': 'updateChatNotificationSettings',
      'chat_id': 1,
      'notification_settings': {'use_default_mute_for': false, 'mute_for': 99},
    });
    model.applyUpdateForTesting({
      '@type': 'updateChatUnreadMentionCount',
      'chat_id': 1,
      'unread_mention_count': 2,
    });
    model.applyUpdateForTesting({
      '@type': 'updateChatTitle',
      'chat_id': 2,
      'title': 'Renamed',
    });
    await tester.pump(const Duration(milliseconds: 51));

    expect(model.chats.first.isMuted, isTrue);
    expect(model.chats.first.unreadMentionCount, 2);
    expect(model.chats[1].title, 'Renamed');
    expect(model.chats.map((chat) => chat.id), [1, 2]);
    expect(identical(model.chatListEntries(), entries), isTrue);
  });

  testWidgets('read state still feeds the folder badge', (tester) async {
    final model = ChatListViewModel();
    addTearDown(model.dispose);
    model.applyUpdateForTesting({
      '@type': 'updateChatFolders',
      'chat_folders': [
        {'id': 7, 'title': 'Work'},
      ],
    });
    model.seedChatForTesting(_chat(id: 1, order: 20, date: 2, unreadCount: 4));
    model.seedChatForTesting(_chat(id: 2, order: 10, date: 1));
    model.applyUpdateForTesting({
      '@type': 'updateChatPosition',
      'chat_id': 1,
      'position': {
        'list': {'@type': 'chatListFolder', 'chat_folder_id': 7},
        'order': 20,
      },
    });
    model.applyUpdateForTesting({
      '@type': 'updateChatPosition',
      'chat_id': 2,
      'position': {
        'list': {'@type': 'chatListFolder', 'chat_folder_id': 7},
        'order': 10,
      },
    });
    await tester.pump(const Duration(milliseconds: 51));

    ChatFilterOption folder() =>
        model.filters.firstWhere((option) => option.folderId == 7);
    expect(folder().unreadChatCount, 1);
    expect(folder().hasUnmutedUnread, isTrue);

    model.applyUpdateForTesting(_readInbox(1, 0));
    await tester.pump(const Duration(milliseconds: 51));

    expect(folder().unreadChatCount, 0);
    expect(folder().hasUnmutedUnread, isFalse);
  });

  testWidgets('a chat that moves still re-sorts the window', (tester) async {
    final model = await seeded(tester, [
      _chat(id: 1, order: 30, date: 3),
      _chat(id: 2, order: 20, date: 2),
    ]);
    final entries = model.chatListEntries();

    model.applyUpdateForTesting({
      '@type': 'updateChatPosition',
      'chat_id': 2,
      'position': _mainPosition(40),
    });
    await tester.pump(const Duration(milliseconds: 51));

    expect(model.chats.map((chat) => chat.id), [2, 1]);
    expect(identical(model.chatListEntries(), entries), isFalse);
  });

  testWidgets('a read update never cancels a resort already owed', (
    tester,
  ) async {
    final model = await seeded(tester, [
      _chat(id: 1, order: 30, date: 3, unreadCount: 5),
      _chat(id: 2, order: 20, date: 2),
    ]);

    model.applyUpdateForTesting({
      '@type': 'updateChatPosition',
      'chat_id': 2,
      'position': _mainPosition(40),
    });
    model.applyUpdateForTesting(_readInbox(1, 0));
    await tester.pump(const Duration(milliseconds: 51));

    expect(model.chats.map((chat) => chat.id), [2, 1]);
    expect(model.chats[1].unreadCount, 0);
  });

  testWidgets('marking the whole list read republishes it once', (
    tester,
  ) async {
    final model = await seeded(tester, [
      for (var id = 1; id <= 5; id++)
        _chat(id: id, order: id * 10, date: id, unreadCount: 3),
    ]);

    var notifications = 0;
    model.addListener(() => notifications++);

    model.markAllRead();

    expect(notifications, 1);
    expect(model.chats.every((chat) => chat.unreadCount == 0), isTrue);
    expect(model.chats.map((chat) => chat.id), [5, 4, 3, 2, 1]);
  });
}
