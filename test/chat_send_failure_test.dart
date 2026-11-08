import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_send_failure.dart';
import 'package:mithka/tdlib/td_client.dart';

void main() {
  group('ChatSendFailure', () {
    test('preserves the paid-message Star count on TDLib failures', () {
      final failure = ChatSendFailure.fromError(
        TdError({'code': 400, 'message': 'STARS_TOO_FEW'}),
        paidMessageStarCount: 25,
      );

      expect(failure.kind, ChatSendFailureKind.insufficientStars);
      expect(failure.paidMessageStarCount, 25);
    });
  });
}
