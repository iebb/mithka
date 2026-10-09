import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/chats/chat_list_view_model.dart';
import 'package:mithka/components/chat_folder_icons.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';

void main() {
  ChatSummary chat(
    int id, {
    int unread = 0,
    bool markedUnread = false,
    bool muted = false,
  }) => ChatSummary(
    id: id,
    title: 'Chat $id',
    lastMessage: 'hi',
    lastMessageId: 1,
    date: id,
    unreadCount: unread,
    isMarkedUnread: markedUnread,
    isMuted: muted,
    order: id,
  );

  testWidgets('folder badges count unread chats, not unread messages', (
    tester,
  ) async {
    final model = ChatListViewModel();
    addTearDown(model.dispose);

    // Folder 7 gains three chats: one read, one with 50 unread messages in a
    // single chat, one flagged unread without a count. Only two are unread
    // chats, so the badge must read 2.
    model.applyUpdateForTesting({
      '@type': 'updateChatFolders',
      'chat_folders': [
        {'id': 7, 'title': 'Work'},
      ],
    });
    model.seedChatForTesting(chat(1, unread: 50));
    model.seedChatForTesting(chat(2));
    model.seedChatForTesting(chat(3, markedUnread: true));
    model.seedChatForTesting(chat(9, unread: 4));
    model.applyUpdateForTesting({
      '@type': 'updateChatPosition',
      'chat_id': 1,
      'position': {
        '@type': 'chatPosition',
        'order': 10,
        'is_pinned': false,
        'list': {'@type': 'chatListFolder', 'chat_folder_id': 7},
      },
    });
    model.applyUpdateForTesting({
      '@type': 'updateChatPosition',
      'chat_id': 2,
      'position': {
        '@type': 'chatPosition',
        'order': 9,
        'is_pinned': false,
        'list': {'@type': 'chatListFolder', 'chat_folder_id': 7},
      },
    });
    model.applyUpdateForTesting({
      '@type': 'updateChatPosition',
      'chat_id': 3,
      'position': {
        '@type': 'chatPosition',
        'order': 8,
        'is_pinned': false,
        'list': {'@type': 'chatListFolder', 'chat_folder_id': 7},
      },
    });
    // chat 9 stays out of the folder: its unread must not leak in.
    await tester.pump(const Duration(milliseconds: 60));

    final work = model.filters.firstWhere((f) => f.folderId == 7);
    expect(work.unreadChatCount, 2);
    expect(work.hasUnmutedUnread, isTrue);
    expect(model.filters.first.unreadChatCount, 0);

    // Reading one chat drops the badge to 1.
    model.applyUpdateForTesting({
      '@type': 'updateChatReadInbox',
      'chat_id': 1,
      'last_read_inbox_message_id': 1,
      'unread_count': 0,
    });
    await tester.pump(const Duration(milliseconds: 60));
    expect(model.filters.firstWhere((f) => f.folderId == 7).unreadChatCount, 1);
  });

  testWidgets('an all-muted folder keeps its count but loses the accent', (
    tester,
  ) async {
    final model = ChatListViewModel();
    addTearDown(model.dispose);
    model.applyUpdateForTesting({
      '@type': 'updateChatFolders',
      'chat_folders': [
        {'id': 2, 'title': 'Quiet'},
      ],
    });
    model.seedChatForTesting(chat(5, unread: 3, muted: true));
    model.applyUpdateForTesting({
      '@type': 'updateChatPosition',
      'chat_id': 5,
      'position': {
        '@type': 'chatPosition',
        'order': 7,
        'is_pinned': false,
        'list': {'@type': 'chatListFolder', 'chat_folder_id': 2},
      },
    });
    await tester.pump(const Duration(milliseconds: 60));
    final quiet = model.filters.firstWhere((f) => f.folderId == 2);
    expect(quiet.unreadChatCount, 1);
    expect(quiet.hasUnmutedUnread, isFalse);
  });

  testWidgets('a folder that excludes muted chats skips them entirely', (
    tester,
  ) async {
    final model = ChatListViewModel();
    addTearDown(model.dispose);
    model.applyUpdateForTesting({
      '@type': 'updateChatFolders',
      'chat_folders': [
        {'id': 4, 'title': 'Loud only', 'exclude_muted': true},
      ],
    });
    model.seedChatForTesting(chat(6, unread: 2, muted: true));
    model.seedChatForTesting(chat(7, unread: 1));
    model.applyUpdateForTesting({
      '@type': 'updateChatPosition',
      'chat_id': 6,
      'position': {
        '@type': 'chatPosition',
        // TDLib omits an excluded muted chat from the folder projection.
        'order': 0,
        'is_pinned': false,
        'list': {'@type': 'chatListFolder', 'chat_folder_id': 4},
      },
    });
    model.applyUpdateForTesting({
      '@type': 'updateChatPosition',
      'chat_id': 7,
      'position': {
        '@type': 'chatPosition',
        'order': 6,
        'is_pinned': false,
        'list': {'@type': 'chatListFolder', 'chat_folder_id': 4},
      },
    });
    await tester.pump(const Duration(milliseconds: 60));
    final loudOnly = model.filters.firstWhere((f) => f.folderId == 4);
    expect(loudOnly.unreadChatCount, 1);
    expect(loudOnly.hasUnmutedUnread, isTrue);
  });

  testWidgets(
    'an exclude_muted folder still counts a muted chat it pins or includes',
    (tester) async {
      final model = ChatListViewModel();
      addTearDown(model.dispose);
      // Real chatFilter shape: excluded muted chats are cut, but
      // pinned_chat_ids/included_chat_ids are unconditional members —
      // TDLib keeps their folder position and the projection shows them.
      model.applyUpdateForTesting({
        '@type': 'updateChatFolders',
        'chat_folders': [
          {
            '@type': 'chatFolderInfo',
            'id': 11,
            'name': 'Pinned work',
            'folder': {
              '@type': 'chatFilter',
              'title': 'Pinned work',
              'exclude_muted': true,
              'pinned_chat_ids': [21],
              'included_chat_ids': [22],
            },
          },
        ],
      });
      model.seedChatForTesting(chat(21, unread: 4, muted: true));
      model.seedChatForTesting(chat(22, unread: 2, muted: true));
      model.seedChatForTesting(chat(23, unread: 9, muted: true));
      for (final entry in [21, 22, 23]) {
        model.applyUpdateForTesting({
          '@type': 'updateChatPosition',
          'chat_id': entry,
          'position': {
            '@type': 'chatPosition',
            'order': 30 - entry,
            'is_pinned': entry == 21,
            'list': {'@type': 'chatListFolder', 'chat_folder_id': 11},
          },
        });
      }
      await tester.pump(const Duration(milliseconds: 60));

      final folder = model.filters.firstWhere((f) => f.folderId == 11);
      // The projection still shows all three chats.
      expect(
        model.chatsForFolder(11).map((c) => c.id),
        containsAll([21, 22, 23]),
      );
      // Until TDLib removes a native position, the row remains visible and
      // belongs in the count. All three visible unread chats are muted.
      expect(folder.unreadChatCount, 3);
      expect(folder.hasUnmutedUnread, isFalse);
    },
  );

  testWidgets('folder rails draw the badge after the label', (tester) async {
    const filter = ChatFilterOption(
      title: 'Work',
      folderId: 7,
      unreadChatCount: 3,
      hasUnmutedUnread: true,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: ChatFolderRail(
          filters: [
            ChatFilterOption(title: 'All'),
            filter,
          ],
          selectedFolderId: null,
          showUnreadBadges: true,
        ),
      ),
    );
    expect(find.text('3'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(find.text('3'), findsNothing);
  });

  testWidgets('the badge never covers the folder glyph or title', (
    tester,
  ) async {
    const filter = ChatFilterOption(
      title: 'Zeta',
      folderId: 9,
      unreadChatCount: 12,
      hasUnmutedUnread: true,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: ChatFolderRail(
          filters: [filter],
          selectedFolderId: null,
          showUnreadBadges: true,
        ),
      ),
    );
    final badge = tester.getRect(find.byType(FolderUnreadBadge));
    final title = tester.getRect(find.text('Zeta'));
    final glyph = tester.getRect(find.byType(ChatFolderIcon).first);
    // Same row as the title: the pill starts clear of the last letter.
    expect(badge.left, greaterThanOrEqualTo(title.right));
    // And it intersects neither the title nor the glyph.
    expect(badge.overlaps(title), isFalse);
    expect(badge.overlaps(glyph), isFalse);
  });

  testWidgets('a narrow folder rail accommodates scaled badges', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 72,
              height: 200,
              child: ChatFolderRail(
                filters: [
                  ChatFilterOption(
                    title: 'Long folder title',
                    folderId: 8,
                    unreadChatCount: 150,
                    hasUnmutedUnread: true,
                  ),
                ],
                selectedFolderId: null,
                showUnreadBadges: true,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('99+'), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'the real 72-pixel rail must not overflow at larger text sizes',
    );
  });

  testWidgets('folder badges cap at 99+ unless exact counts are requested', (
    tester,
  ) async {
    const filter = ChatFilterOption(
      title: 'Busy',
      folderId: 8,
      unreadChatCount: 150,
      hasUnmutedUnread: true,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: ChatFolderRail(
          filters: [filter],
          selectedFolderId: null,
          showUnreadBadges: true,
        ),
      ),
    );
    expect(find.text('99+'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: ChatFolderRail(
          filters: [filter],
          selectedFolderId: null,
          showUnreadBadges: true,
          badgeOverflowMode: UnreadBadgeOverflowMode.exact,
        ),
      ),
    );
    expect(find.text('150'), findsOneWidget);
    expect(find.text('99+'), findsNothing);
  });
}
