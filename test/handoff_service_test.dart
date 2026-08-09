import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/handoff_service.dart';

void main() {
  group('HandoffChatActivity', () {
    test('parses the bounded non-secret continuation payload', () {
      final activity = HandoffChatActivity.tryParse({
        'version': 1,
        'activityId': 'A7F8C5E1-9F55-4ACE-91B4-23E947FC7412',
        'accountUserId': 42,
        'chatId': -100123,
        'messageId': 88,
      });

      expect(activity, isNotNull);
      expect(activity!.accountUserId, 42);
      expect(activity.chatId, -100123);
      expect(activity.messageId, 88);
      expect(activity.toJson(), isNot(contains('sessionString')));
    });

    test('accepts a chat activity without an exact message', () {
      final activity = HandoffChatActivity.tryParse({
        'version': 1,
        'activityId': 'chat-only',
        'accountUserId': 42,
        'chatId': 7,
      });

      expect(activity?.messageId, isNull);
    });

    test('rejects malformed and unsupported payloads', () {
      expect(
        HandoffChatActivity.tryParse({
          'version': 2,
          'activityId': 'future',
          'accountUserId': 42,
          'chatId': 7,
        }),
        isNull,
      );
      expect(
        HandoffChatActivity.tryParse({
          'version': 1,
          'activityId': 'missing-account',
          'chatId': 7,
        }),
        isNull,
      );
      expect(
        HandoffChatActivity.tryParse({
          'version': 1,
          'activityId': 'zero-message',
          'accountUserId': 42,
          'chatId': 7,
          'messageId': 0,
        }),
        isNull,
      );
      expect(
        HandoffChatActivity.tryParse({
          'version': 1,
          'activityId': 'temporary-message',
          'accountUserId': 42,
          'chatId': 7,
          'messageId': -1,
        }),
        isNull,
      );
      expect(
        HandoffChatActivity.tryParse({
          'version': 1,
          'activityId': 'string-ids-are-not-coerced',
          'accountUserId': '42',
          'chatId': '7',
        }),
        isNull,
      );
    });
  });
}
