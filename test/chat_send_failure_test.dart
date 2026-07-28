import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_send_failure.dart';
import 'package:mithka/tdlib/td_client.dart';

void main() {
  group('ChatSendFailure', () {
    test('classifies mutual-contact and privacy restrictions', () {
      expect(
        classifyChatSendFailure('USER_NOT_MUTUAL_CONTACT', code: 403),
        ChatSendFailureKind.mutualContactRequired,
      );
      expect(
        classifyChatSendFailure('USER_PRIVACY_RESTRICTED', code: 403),
        ChatSendFailureKind.privacyRestricted,
      );
    });

    test('distinguishes Premium and paid-message requirements', () {
      expect(
        classifyChatSendFailure('PRIVACY_PREMIUM_REQUIRED', code: 406),
        ChatSendFailureKind.premiumRequired,
      );
      expect(
        classifyChatSendFailure('ALLOW_PAYMENT_REQUIRED', code: 406),
        ChatSendFailureKind.paidMessageRequired,
      );
    });

    test('preserves the paid-message Star count on TDLib failures', () {
      final failure = ChatSendFailure.fromError(
        TdError({'code': 400, 'message': 'STARS_TOO_FEW'}),
        paidMessageStarCount: 25,
      );

      expect(failure.kind, ChatSendFailureKind.insufficientStars);
      expect(failure.paidMessageStarCount, 25);
    });

    test('maps group write restrictions to permission denied', () {
      expect(
        classifyChatSendFailure('CHAT_WRITE_FORBIDDEN', code: 403),
        ChatSendFailureKind.chatPermissionDenied,
      );
      expect(
        classifyChatSendFailure('USER_BANNED_IN_CHANNEL', code: 403),
        ChatSendFailureKind.chatPermissionDenied,
      );
    });
  });
}
