import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/profile/profile_identity_summary.dart';

void main() {
  group('fullProfileIdentityLines', () {
    test('keeps the phone separate from the Telegram ID and username', () {
      expect(
        fullProfileIdentityLines(
          formattedPhone: '+372 8198 1998',
          usernames: ['nekoko14', 'collectible'],
          userId: 12345,
        ),
        [
          (kind: ProfileIdentityKind.phoneNumber, text: '+372 8198 1998'),
          (kind: ProfileIdentityKind.telegramId, text: 'TG: 12345'),
          (kind: ProfileIdentityKind.username, text: '@nekoko14'),
          (kind: ProfileIdentityKind.username, text: '@collectible'),
        ],
      );
    });

    test('shows the Telegram ID even when no username exists', () {
      expect(
        fullProfileIdentityLines(
          formattedPhone: '',
          usernames: const [],
          userId: 12345,
        ),
        [(kind: ProfileIdentityKind.telegramId, text: 'TG: 12345')],
      );
    });

    test('hides only the phone number, not the Telegram identity', () {
      expect(
        fullProfileIdentityLines(
          formattedPhone: '+372 8198 1998',
          usernames: ['nekoko14'],
          userId: 12345,
          hidePhone: true,
        ),
        [
          (kind: ProfileIdentityKind.telegramId, text: 'TG: 12345'),
          (kind: ProfileIdentityKind.username, text: '@nekoko14'),
        ],
      );
    });
  });
}
