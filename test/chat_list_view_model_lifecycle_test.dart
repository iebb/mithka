import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view_model.dart';
import 'package:mithka/communities/community_models.dart';

void main() {
  test('hiding "All" offers only real folders and moves the selection', () {
    final model = ChatListViewModel();
    addTearDown(model.dispose);

    model.hideAllFilter = true;
    // Without folders "All" is the only list, so it stays available.
    expect(model.filters.map((f) => f.folderId), [null]);
    expect(model.selectionHiddenByFilterPreference, isFalse);

    model.applyUpdateForTesting({
      '@type': 'updateChatFolders',
      'chat_folders': [
        {'id': 7, 'title': 'Business'},
        {'id': 8, 'title': 'Personal'},
      ],
    });
    expect(model.filters.map((f) => f.folderId), [7, 8]);
    expect(model.selectedFilter.folderId, 7);
    expect(identical(model.filters, model.filters), isTrue);

    model.hideAllFilter = false;
    expect(model.filters.map((f) => f.folderId), [null, 7, 8]);
    expect(model.selectedFilter.folderId, 7);
  });

  test('enabling the preference later is applied after the frame', () {
    final model = ChatListViewModel();
    addTearDown(model.dispose);
    model.applyUpdateForTesting({
      '@type': 'updateChatFolders',
      'chat_folders': [
        {'id': 7, 'title': 'Business'},
      ],
    });
    expect(model.selectedFilter.isAll, isTrue);

    model.hideAllFilter = true;
    // A single folder keeps "All" so the switcher stays reachable.
    expect(model.filters.map((f) => f.folderId), [null, 7]);
    expect(model.selectionHiddenByFilterPreference, isFalse);

    model.applyUpdateForTesting({
      '@type': 'updateChatFolders',
      'chat_folders': [
        {'id': 7, 'title': 'Business'},
        {'id': 8, 'title': 'Personal'},
      ],
    });
    // The folder update already moves off "All"; re-select it to exercise the
    // post-frame path the view uses when the preference is turned on later.
    model.hideAllFilter = false;
    model.selectFilter(model.filters.first);
    expect(model.selectedFilter.isAll, isTrue);
    model.hideAllFilter = true;
    expect(model.selectionHiddenByFilterPreference, isTrue);
    model.selectFirstVisibleFilterIfHidden();
    expect(model.selectedFilter.folderId, 7);
    expect(model.selectionHiddenByFilterPreference, isFalse);
  });

  test('late chat-list resort is ignored after disposal', () async {
    final model = ChatListViewModel();
    model.dispose();

    expect(() => model.meId = 42, returnsNormally);
    expect(model.scheduleResortForTesting, returnsNormally);
    await Future<void>.delayed(const Duration(milliseconds: 30));
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

  testWidgets(
    'stale community snapshot cannot restore an unread badge after read',
    (tester) async {
      final model = ChatListViewModel(
        membershipForTesting: (_, _) async => true,
      );
      addTearDown(model.dispose);

      final staleUnreadSnapshot = _groupChat(
        order: 100,
        messageId: 10,
        messageDate: 10,
        text: 'community message',
        unreadCount: 4,
      );
      await model.ingestRawChatForTesting(staleUnreadSnapshot);
      model.applyUpdateForTesting({
        '@type': 'updateChatReadInbox',
        'chat_id': 42,
        'last_read_inbox_message_id': 10,
        'unread_count': 0,
      });
      await tester.pump(const Duration(milliseconds: 50));

      model.applyUpdateForTesting({
        '@type': 'updateChatReadInbox',
        'chat_id': 42,
        'last_read_inbox_message_id': 5,
        'unread_count': 2,
      });
      await tester.pump(const Duration(milliseconds: 50));
      expect(model.chats.single.unreadCount, 0);

      // A community catalogue getChat that started before the read update can
      // return afterwards with the same last message and its old unread count.
      await model.ingestRawChatForTesting(staleUnreadSnapshot);
      await tester.pump(const Duration(milliseconds: 50));

      expect(model.chats.single.unreadCount, 0);
      expect(model.chats.single.lastReadInboxMessageId, 10);
      final community = CommunityGroupEntry(
        community: CommunitySummary(
          id: 7,
          name: 'Community',
          haveAccess: true,
          isAdministrator: false,
          canEditChatList: false,
        ),
        chats: model.chats,
      );
      expect(community.unreadCount, 0);

      // A genuinely newer message still creates a new unread count.
      await model.ingestRawChatForTesting(
        _groupChat(
          order: 200,
          messageId: 20,
          messageDate: 20,
          text: 'new community message',
          unreadCount: 1,
          lastReadInboxMessageId: 10,
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(model.chats.single.unreadCount, 1);
    },
  );
}

Map<String, dynamic> _groupChat({
  required int order,
  required int messageId,
  required int messageDate,
  required String text,
  int unreadCount = 0,
  int lastReadInboxMessageId = 0,
}) => {
  '@type': 'chat',
  'id': 42,
  'title': 'Current group',
  'view_as_topics': true,
  'unread_count': unreadCount,
  'last_read_inbox_message_id': lastReadInboxMessageId,
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
