import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/notifications/notification_controller.dart';
import 'package:mithka/notifications/notification_target.dart';

Map<String, dynamic> _newMessage({
  required int chatId,
  required int messageId,
}) => {
  '@type': 'updateNewMessage',
  'message': {
    '@type': 'message',
    'id': messageId,
    'chat_id': chatId,
    'is_outgoing': false,
    'content': {'@type': 'messageText'},
  },
};

Map<String, dynamic> _readInbox({
  required int chatId,
  required int lastReadMessageId,
}) => {
  '@type': 'updateChatReadInbox',
  'chat_id': chatId,
  'last_read_inbox_message_id': lastReadMessageId,
  'unread_count': 0,
};

void main() {
  final controller = NotificationController.shared;
  setUp(controller.resetSyncStateForTesting);
  tearDown(controller.resetSyncStateForTesting);

  test('messages up to the read marker count as already read', () {
    expect(
      notificationMessageIsRead(messageId: 900, lastReadInboxMessageId: 1000),
      isTrue,
    );
    expect(
      notificationMessageIsRead(messageId: 1000, lastReadInboxMessageId: 1000),
      isTrue,
    );
    expect(
      notificationMessageIsRead(messageId: 1100, lastReadInboxMessageId: 1000),
      isFalse,
    );
    expect(
      notificationMessageIsRead(messageId: 1100, lastReadInboxMessageId: 0),
      isFalse,
    );
  });

  test('the chat snapshot and later read updates both mark a message read', () {
    final chat = <String, dynamic>{
      '@type': 'chat',
      'id': 7,
      'last_read_inbox_message_id': 500,
    };

    expect(
      controller.isMessageReadForTesting(chatId: 7, messageId: 400, chat: chat),
      isTrue,
    );
    expect(
      controller.isMessageReadForTesting(chatId: 7, messageId: 600, chat: chat),
      isFalse,
    );

    controller.applyChatReadInboxUpdateForTesting(
      _readInbox(chatId: 7, lastReadMessageId: 600),
    );

    // A fresher read marker wins over the snapshot TDLib handed back.
    expect(
      controller.isMessageReadForTesting(chatId: 7, messageId: 600, chat: chat),
      isTrue,
    );
    // A stale marker never walks the read position backwards.
    controller.applyChatReadInboxUpdateForTesting(
      _readInbox(chatId: 7, lastReadMessageId: 100),
    );
    expect(
      controller.isMessageReadForTesting(chatId: 7, messageId: 600, chat: chat),
      isTrue,
    );
  });

  test('a backlog message read on another device is dropped, not announced', () {
    controller.holdBacklogMessageForTesting(
      _newMessage(chatId: 42, messageId: 1000),
    );
    expect(controller.heldBacklogChatIdsForTesting(0), [42]);

    controller.applyChatReadInboxUpdateForTesting(
      _readInbox(chatId: 42, lastReadMessageId: 1000),
    );
    expect(controller.heldBacklogChatIdsForTesting(0), isEmpty);

    // Later replays of the same read stretch stay silent too.
    controller.holdBacklogMessageForTesting(
      _newMessage(chatId: 42, messageId: 900),
    );
    expect(controller.heldBacklogChatIdsForTesting(0), isEmpty);
  });

  test('an offline backlog collapses to one notification per chat', () {
    for (var messageId = 1000; messageId < 1010; messageId++) {
      controller.holdBacklogMessageForTesting(
        _newMessage(chatId: 42, messageId: messageId),
      );
    }
    controller.holdBacklogMessageForTesting(
      _newMessage(chatId: 43, messageId: 2000),
    );

    expect(controller.heldBacklogChatIdsForTesting(0), [42, 43]);
  });

  test('unread backlog survives a read marker below it', () {
    controller.holdBacklogMessageForTesting(
      _newMessage(chatId: 42, messageId: 1000),
    );
    controller.applyChatReadInboxUpdateForTesting(
      _readInbox(chatId: 42, lastReadMessageId: 999),
    );

    expect(controller.heldBacklogChatIdsForTesting(0), [42]);
  });

  test('reading a chat elsewhere dismisses its visible banner', () {
    addTearDown(controller.dismissInAppBanner);
    controller.presentInAppBannerForTesting(
      const InAppNotificationBannerData(
        target: NotificationTarget(chatId: 42, messageId: 1000),
        title: 'Chat',
        body: 'Message',
        photo: null,
        squarePhoto: false,
      ),
    );
    expect(controller.inAppBanner, isNotNull);

    controller.applyChatReadInboxUpdateForTesting(
      _readInbox(chatId: 42, lastReadMessageId: 999),
    );
    expect(controller.inAppBanner, isNotNull);

    controller.applyChatReadInboxUpdateForTesting(
      _readInbox(chatId: 42, lastReadMessageId: 1000),
    );
    expect(controller.inAppBanner, isNull);
  });

  test('a synced account announces without waiting on the backlog hold', () {
    controller.applyConnectionStateUpdateForTesting({
      '@type': 'updateConnectionState',
      'state': {'@type': 'connectionStateReady'},
    });
    expect(controller.isSyncedForTesting(0), isTrue);

    // A dropped connection re-arms the hold for the next reconnect backlog.
    controller.applyConnectionStateUpdateForTesting({
      '@type': 'updateConnectionState',
      'state': {'@type': 'connectionStateUpdating'},
    });
    expect(controller.isSyncedForTesting(0), isFalse);
  });
}
