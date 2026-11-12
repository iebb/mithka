import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/notifications/notification_target.dart';

void main() {
  group('account slot', () {
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
  });
}
