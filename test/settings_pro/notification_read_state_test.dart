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

  test(
    'a backlog message read on another device is dropped, not announced',
    () {
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
    },
  );

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
}
