import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/notifications/notification_target.dart';

void main() {
  group('NotificationTarget.fromLocalPayload', () {
    test('keeps TDLib chat and message identifiers', () {
      final target = NotificationTarget.fromLocalPayload(
        '{"chat_id":"-100123","message_id":"456789","title":"Group","account_slot":2}',
      );

      expect(target?.chatId, -100123);
      expect(target?.messageId, 456789);
      expect(target?.title, 'Group');
      expect(target?.accountSlot, 2);
    });

    test('rejects invalid payloads', () {
      expect(NotificationTarget.fromLocalPayload(null), isNull);
      expect(NotificationTarget.fromLocalPayload('not json'), isNull);
      expect(NotificationTarget.fromLocalPayload('{"message_id":1}'), isNull);
    });
  });

  group('NotificationTarget.fromRemoteUserInfo', () {
    test('converts private-chat and server message identifiers', () {
      final target = NotificationTarget.fromRemoteUserInfo({
        'data': {
          'user_id': '42',
          'custom': {'from_id': '123', 'msg_id': '456'},
        },
        'aps': {
          'alert': {'title': 'Alice'},
        },
      });

      expect(target?.chatId, 123);
      expect(target?.messageId, 456 << 20);
      expect(target?.accountUserId, 42);
      expect(target?.title, 'Alice');
    });

    test('converts basic-group identifiers', () {
      final target = NotificationTarget.fromRemoteUserInfo({
        'custom': {'chat_id': 321, 'msg_id': 12},
      });

      expect(target?.chatId, -321);
      expect(target?.messageId, 12 << 20);
    });

    test('converts supergroup and channel identifiers', () {
      final target = NotificationTarget.fromRemoteUserInfo({
        'data': {
          'custom': {'channel_id': 654, 'msg_id': 20},
        },
      });

      expect(target?.chatId, -1000000000654);
      expect(target?.messageId, 20 << 20);
    });

    test('converts secret-chat identifiers', () {
      final target = NotificationTarget.fromRemoteUserInfo({
        'data': {
          'custom': {'encryption_id': 77, 'msg_id': 3},
        },
      });

      expect(target?.chatId, -1999999999923);
      expect(target?.messageId, 3 << 20);
    });
  });

  group('account slot', () {
    test('the extension stamp is read back on tap', () {
      final target = NotificationTarget.fromRemoteUserInfo({
        'mithka_account_slot': 2,
        'mithka_account_user_id': '4242',
        'data': {
          'custom': {'from_id': 777, 'msg_id': 9},
        },
      });

      expect(target?.accountSlot, 2);
      expect(target?.accountUserId, 4242);
    });

    test('the payload user id still wins over the stamped copy', () {
      final target = NotificationTarget.fromRemoteUserInfo({
        'mithka_account_user_id': '1',
        'data': {
          'user_id': 4242,
          'custom': {'from_id': 777, 'msg_id': 9},
        },
      });

      expect(target?.accountUserId, 4242);
    });

    test('a remote payload arrives naming its account only by user id', () {
      final target = NotificationTarget.fromRemoteUserInfo({
        'data': {
          'user_id': 4242,
          'custom': {'from_id': 777, 'msg_id': 9},
        },
      });

      expect(target, isNotNull);
      expect(target!.accountUserId, 4242);
      // Telegram's payload has no concept of Mithka's slot numbering, so the
      // slot has to be attached later, where the client registry lives.
      expect(target.accountSlot, isNull);
    });

    test('tagging a slot keeps everything else about the target', () {
      const target = NotificationTarget(
        chatId: -100,
        messageId: 88,
        title: 'Group',
        accountUserId: 4242,
      );

      final tagged = target.withAccountSlot(2);
      expect(tagged.accountSlot, 2);
      expect(tagged.accountUserId, 4242);
      expect(tagged.chatId, -100);
      expect(tagged.messageId, 88);
      expect(tagged.title, 'Group');
    });

    test('a local payload already knows its slot', () {
      final target = NotificationTarget.fromLocalPayload(
        '{"chat_id":-100,"message_id":88,"account_slot":3,'
        '"account_user_id":4242}',
      );

      expect(target?.accountSlot, 3);
      expect(target?.accountUserId, 4242);
    });
  });
}
