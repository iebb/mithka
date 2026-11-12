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
    });
  });

  test('cold Handoff waits for the local account catalogue', () async {
    var readinessChecks = 0;

    await waitForHandoffStartup(
      isReady: () => ++readinessChecks >= 3,
      isActive: () => true,
      retryDelay: Duration.zero,
    );

    expect(readinessChecks, 3);
  });
}
